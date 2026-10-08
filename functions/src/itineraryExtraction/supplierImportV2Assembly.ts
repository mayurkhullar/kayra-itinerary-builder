import type {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import type {SupplierImportResolutionAggregate} from "./supplierImportResolution";
import {parseSupplierExtractionSnapshotStructure} from "./supplierExtractionStoredValidation";
import {validateSupplierImportResolution} from "./supplierImportResolutionValidation";
import {itineraryDraftImportPolicies, itineraryDraftV2SchemaVersion, optionalChronologyImportPolicy} from "./itineraryDraftV2";
import {validateItineraryDraftV2} from "./itineraryDraftV2Validation";
import {enumValue, exact, identity, immutable, timestamp} from "./itineraryDraftValidationPrimitives";
import {findAssemblyStructureIssues} from "./supplierImportV2AssemblyPolicy";
import {buildTimeline, timelineMap} from "./supplierImportV2Timeline";
import {buildPackageContent} from "./supplierImportV2PackageContent";
import {assessAssemblyReview} from "./supplierImportV2Review";
import {account} from "./supplierImportV2AssemblyValues";
import type {
  FinalizationBlockerCode, FinalizationFinding, FinalizationWarningCode,
  FinalizationInformationalCode, SupplierImportAccounting,
  SupplierImportV2AssemblyContext, SupplierImportV2AssemblyResult,
} from "./supplierImportV2AssemblyTypes";
export type {
  SupplierImportV2AssemblyContext, SupplierImportV2AssemblyResult, SupplierImportAccounting,
} from "./supplierImportV2AssemblyTypes";

/** Single authoritative exception-driven evaluation. Inputs come from trusted
 * readers; structural revalidation is not authentication/authorization. No
 * writes, clock reads, source authority fabrication or supplier-text repair. */
export function assembleSupplierImportV2(
  source: SupplierExtractionSnapshot, input: SupplierImportResolutionAggregate,
  context: SupplierImportV2AssemblyContext,
): SupplierImportV2AssemblyResult {
  const blockers: FinalizationFinding<FinalizationBlockerCode>[] = [];
  const warnings: FinalizationFinding<FinalizationWarningCode>[] = [];
  const informational: FinalizationFinding<FinalizationInformationalCode>[] = [];
  const accounting: SupplierImportAccounting[] = [];
  let resolutionId = "invalid-resolution";
  let evaluatedRevision = 0;
  const blocked = (): SupplierImportV2AssemblyResult => immutable({
    resolutionId, evaluatedRevision, canFinalize: false, candidate: null,
    blockers: sorted(blockers), warnings: sorted(warnings), informational: sorted(informational), accounting,
  });
  const fail = (code: FinalizationBlockerCode): SupplierImportV2AssemblyResult => {
    blockers.push({code, targetKind: "resolution", targetId: resolutionId});
    return blocked();
  };
  let snapshot: SupplierExtractionSnapshot;
  try {
    snapshot = parseSupplierExtractionSnapshotStructure(source);
    resolutionId = snapshot.extractionId;
  } catch {
    return fail("invalid_snapshot");
  }
  let resolution: SupplierImportResolutionAggregate;
  try {
    resolution = validateSupplierImportResolution(snapshot, input);
    evaluatedRevision = resolution.root.revision;
  } catch {
    for (const fact of snapshot.facts.filter((item) => item.factKind.startsWith("package_"))) {
      account(accounting, fact.id, fact.factKind, fact.sources, undefined, "blocked");
    }
    return fail("invalid_resolution");
  }
  try {
    validateContext(context, snapshot);
  } catch {
    for (const fact of snapshot.facts.filter((item) => item.factKind.startsWith("package_"))) {
      account(accounting, fact.id, fact.factKind, fact.sources, undefined, "blocked");
    }
    return fail("invalid_assembly_context");
  }
  const importResult = {
    extractionId: snapshot.extractionId, resolutionId, evaluatedRevision,
    sourcePackageId: snapshot.sourcePackageId, finalizationId: context.finalizationId,
    policyVersion: context.policyVersion,
  };
  const optionalChronology = context.policyVersion === optionalChronologyImportPolicy;
  const structure = findAssemblyStructureIssues(snapshot, resolution, optionalChronology);
  blockers.push(...structure.blockers);
  informational.push(...structure.informational);
  const timeline = buildTimeline(snapshot, resolution, accounting, optionalChronology);
  const packageContent = buildPackageContent(snapshot, resolution, importResult, timeline, accounting, blockers, optionalChronology);
  const unscheduled = optionalChronology && [...timeline.services.values()].some((s) => s.dayId === null) ?
    {unscheduledServices: [...timeline.services.values()].filter((s) => s.dayId === null)
      .sort((a, b) => a.order - b.order || a.entityId.localeCompare(b.entityId)).map((s) => s.data)} : {};
  const titleDecision = resolution.decisions.find((decision) => decision.decisionKind === "title");
  const title = titleDecision?.overrides.title?.value ?? snapshot.title.text;
  let representationSafe = blockers.length === 0;
  if (representationSafe) {
    try {
      validateItineraryDraftV2(context.draftId, {tripId: context.tripId,
        schemaVersion: itineraryDraftV2SchemaVersion, title, days: timelineMap(timeline), ...unscheduled,
        sourcePackageIds: [snapshot.sourcePackageId], reviewIssues: [], createdByUid: context.actorUid,
        createdAt: context.createdAt, updatedAt: context.updatedAt, packageContent, importResult});
    } catch {
      representationSafe = false;
      blockers.push({code: "canonical_validation_failed", targetKind: "resolution", targetId: resolutionId});
    }
  }
  const reviewIssues = assessAssemblyReview(snapshot, resolution, blockers, warnings, accounting, representationSafe, optionalChronology);
  account(accounting, "title", "title", snapshot.title.sources, titleDecision,
    titleDecision ? "explicit_retained" : "auto_retained", [context.draftId]);
  for (const fact of snapshot.facts) {
    if (fact.factKind === "commercial_presence") {
      account(accounting, fact.id, fact.factKind, fact.sources, undefined, "informational");
    } else if (fact.factKind === "flight" || fact.factKind === "visa") {
      const decision = resolution.decisions.find((item) => item.targetEntityId === fact.id);
      const disposition = decision && "disposition" in decision ? decision.disposition : null;
      account(accounting, fact.id, fact.factKind, fact.sources, decision,
        disposition === "exclude" ? "excluded" : disposition === "handled_separately" ? "handled_separately" :
          disposition === "route_to_flight_workflow" || disposition === "route_to_visa_workflow" ? "routed" : "blocked");
    }
  }
  accounting.sort((a, b) => a.entityKind.localeCompare(b.entityKind) || a.entityId.localeCompare(b.entityId));
  for (let index = 0; index < accounting.length; index++) {
    const entry = accounting[index];
    const affected = blockers.some((finding) => finding.targetId === entry.entityId ||
      finding.targetKind === "review_issue" && snapshot.reviewIssues.some((issue) =>
        issue.id === finding.targetId && (issue.target.entityId === entry.entityId || issue.target.kind === "snapshot")));
    if (affected && entry.outcome !== "excluded") accounting[index] = {...entry, outcome: "blocked", outputIds: [], outputDayNumber: null};
  }
  if (blockers.length > 0) return blocked();
  try {
    const candidate = validateItineraryDraftV2(context.draftId, {
      tripId: context.tripId, schemaVersion: itineraryDraftV2SchemaVersion, title,
      days: timelineMap(timeline), ...unscheduled, sourcePackageIds: [snapshot.sourcePackageId], reviewIssues,
      createdByUid: context.actorUid, createdAt: context.createdAt, updatedAt: context.updatedAt,
      packageContent, importResult,
    });
    return immutable({resolutionId, evaluatedRevision, canFinalize: true, candidate,
      blockers: [], warnings: sorted(warnings), informational: sorted(informational), accounting});
  } catch {
    // Never expose source text, arbitrary validator errors or a partial draft.
    for (let index = 0; index < accounting.length; index++) {
      if (["auto_retained", "explicit_retained", "mapped", "manual"].includes(accounting[index].outcome)) {
        accounting[index] = {...accounting[index], outcome: "blocked", outputIds: [], outputDayNumber: null};
      }
    }
    return fail("canonical_validation_failed");
  }
}

function validateContext(context: SupplierImportV2AssemblyContext, snapshot: SupplierExtractionSnapshot): void {
  exact(context, ["draftId", "tripId", "actorUid", "finalizationId", "createdAt", "updatedAt", "policyVersion"], "Assembly context");
  identity(context.draftId, "Draft");
  identity(context.actorUid, "Actor");
  identity(context.finalizationId, "Finalization");
  if (context.finalizationId.length > 128 || context.tripId !== snapshot.tripId ||
      timestamp(context.updatedAt, "Updated at") < timestamp(context.createdAt, "Created at")) {
    throw new Error("Invalid trusted assembly context.");
  }
  enumValue(context.policyVersion, itineraryDraftImportPolicies, "Policy");
}

function sorted<Code extends string>(findings: readonly FinalizationFinding<Code>[]): FinalizationFinding<Code>[] {
  return [...findings].sort((a, b) => a.code.localeCompare(b.code) ||
    a.targetKind.localeCompare(b.targetKind) || (a.targetId ?? "").localeCompare(b.targetId ?? ""));
}
