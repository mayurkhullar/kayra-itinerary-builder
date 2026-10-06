import type {StagedReviewIssue, SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import type {SupplierImportDecision, SupplierImportResolutionAggregate} from "./supplierImportResolution";
import {concretelyResolves} from "./supplierImportResolutionValidation";
import type {
  FinalizationBlockerCode, FinalizationFinding, FinalizationWarningCode,
} from "./supplierImportV2AssemblyTypes";
import {canonicalId} from "./supplierImportV2AssemblyValues";

const structural = new Set(["chronology_unknown", "accommodation_span_unknown",
  "classification_ambiguous", "conflicting_dates", "global_mapping_required", "source_conflict"]);

export function assessAssemblyReview(
  snapshot: SupplierExtractionSnapshot, resolution: SupplierImportResolutionAggregate,
  blockers: FinalizationFinding<FinalizationBlockerCode>[], warnings: FinalizationFinding<FinalizationWarningCode>[],
): object[] {
  const decisions = new Map(resolution.decisions.map((decision) => [decision.decisionId, decision]));
  const manualIds = new Set(resolution.manualItems.map((item) => item.itemKind === "consultant_day" ? item.manualDayId : item.manualServiceId));
  const remaining: object[] = [];
  for (const issue of snapshot.reviewIssues) {
    const value = decisions.get(issue.id);
    const decision = value?.decisionKind === "review_issue" ? value : undefined;
    const blocking = structural.has(issue.code) || issue.severity === "blocker" || issue.resolutionRequired;
    const references = decision?.resolutionReferences.filter((reference) => reference.kind === "decision") ?? [];
    const concrete = references.map((reference) => decisions.get(reference.decisionId)).filter((item): item is SupplierImportDecision => item !== undefined)
      .filter((item) => structural.has(issue.code) ? concretelyResolves(issue.code,
        {kind: "decision", decisionId: item.decisionId}, decisions, manualIds) : hasConcreteChange(item));
    // Snapshot-wide issues carry no affected-entity list. Conservatively require
    // coverage of every source day/fact, rather than guessing from message prose.
    const requiredIds = issue.target.entityId === null ?
      [...snapshot.days.map((day) => day.id), ...snapshot.facts.filter((fact) => fact.factKind !== "commercial_presence").map((fact) => fact.id)] :
      [issue.target.entityId];
    const resolved = decision?.outcome === "resolved" && requiredIds.length > 0 &&
      requiredIds.every((id) => concrete.some((item) => item.targetEntityId === id));
    const overridden = decision?.outcome === "overridden" && issue.code === "other";
    if (blocking && !resolved && !overridden) {
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

function hasConcreteChange(decision: SupplierImportDecision): boolean {
  if (decision.decisionKind === "review_issue") return false;
  if ("overrides" in decision && Object.keys(decision.overrides).length > 0) return true;
  if ("disposition" in decision && !["retain", "retain_package_level", "accept"].includes(decision.disposition)) return true;
  return (decision.decisionKind === "day" || decision.decisionKind === "service") && decision.canonicalOrder !== undefined ||
    decision.decisionKind === "service" && decision.day !== undefined;
}

function reviewPath(issue: StagedReviewIssue): string {
  // Stable evidence locator; do not claim a shifted canonical array index.
  return issue.target.kind === "snapshot" ? "importResult" : `importResult.${issue.target.kind}.${issue.target.entityId}`;
}
