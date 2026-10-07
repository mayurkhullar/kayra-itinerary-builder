import type {StagedReviewIssue, SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import type {SupplierImportResolutionAggregate} from "./supplierImportResolution";
import {evaluateReviewIssue, permitsReviewOverride, structuralReviewCodes as structural} from "./supplierImportReviewEvidence";
import type {
  FinalizationBlockerCode, FinalizationFinding, FinalizationWarningCode, SupplierImportAccounting,
} from "./supplierImportV2AssemblyTypes";
import {account, canonicalId} from "./supplierImportV2AssemblyValues";

export function assessAssemblyReview(
  snapshot: SupplierExtractionSnapshot, resolution: SupplierImportResolutionAggregate,
  blockers: FinalizationFinding<FinalizationBlockerCode>[], warnings: FinalizationFinding<FinalizationWarningCode>[],
  accounting: SupplierImportAccounting[],
  representationSafe = false,
): object[] {
  const decisions = new Map(resolution.decisions.map((decision) => [decision.decisionId, decision]));
  const specificsClear = snapshot.reviewIssues.filter((i) => i.target.kind !== "snapshot").every((i) =>
    evaluateReviewIssue(i, snapshot, resolution, representationSafe, true) !== "unresolved");
  const remaining: object[] = [];
  for (const issue of snapshot.reviewIssues) {
    const value = decisions.get(issue.id);
    const decision = value?.decisionKind === "review_issue" ? value : undefined;
    const evaluation = evaluateReviewIssue(issue, snapshot, resolution, representationSafe, specificsClear);
    const blocking = evaluation === "unresolved";
    const resolved = evaluation === "derived" || evaluation === "explicit";
    const overridden = evaluation === "overridden";
    const outcome = blocking ? "blocked" : overridden ? "review_overridden" :
      evaluation === "derived" ? "review_derived" : resolved ? "review_resolved" :
        decision?.outcome === "acknowledged" ? "review_acknowledged" : "review_open_warning";
    account(accounting, issue.id, "review_issue", issue.sources, evaluation === "derived" ? undefined : decision, outcome,
      outcome === "review_open_warning" || outcome === "review_acknowledged" ?
        [canonicalId(snapshot, "review", issue.id)] : []);
    if (blocking && !resolved && !overridden) {
      if (representationSafe && permitsReviewOverride(issue) && (issue.target.kind !== "snapshot" || specificsClear)) {
        warnings.push({code: "review_issue_override_available", targetKind: "review_issue", targetId: issue.id});
      }
      blockers.push({code: structural.has(issue.code) ? "structural_review_issue_unresolved" : "unresolved_review_issue",
        targetKind: "review_issue", targetId: issue.id});
    } else if (overridden) {
      warnings.push({code: "review_issue_overridden", targetKind: "review_issue", targetId: issue.id});
    } else if (!resolved && !blocking) {
      warnings.push({code: decision?.outcome === "acknowledged" ? "snapshot_warning_acknowledged" : "snapshot_warning_open",
        targetKind: "review_issue", targetId: issue.id});
      remaining.push({id: canonicalId(snapshot, "review", issue.id), fieldPath: reviewPath(issue),
        message: issue.message, severity: "warning"});
    }
  }
  return remaining;
}

function reviewPath(issue: StagedReviewIssue): string {
  // Stable evidence locator; do not claim a shifted canonical array index.
  return issue.target.kind === "snapshot" ? "importResult" : `importResult.${issue.target.kind}.${issue.target.entityId}`;
}
