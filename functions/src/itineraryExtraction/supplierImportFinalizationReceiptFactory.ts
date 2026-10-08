import {itineraryDraftImportPolicies, ItineraryDraftV2} from "./itineraryDraftV2";
import {itineraryDraftV2ToMap, validateItineraryDraftV2} from "./itineraryDraftV2Validation";
import {array, enumValue, exact, identity, positiveInteger, sourceLabel, timestamp, unique} from "./itineraryDraftValidationPrimitives";
import {
  ReceiptOutputField, ReceiptOutputTarget, SupplierImportFinalizationReceipt,
  SupplierImportFinalizationReceiptContext, SupplierImportReceiptOutcome,
  supplierImportFinalizationReceiptSchemaVersion,
} from "./supplierImportFinalizationReceipt";
import {finalizationRequestFingerprint, supplierImportCanonicalContentDigest} from "./supplierImportFinalizationReceiptDigest";
import {boundedIdentity, dateMap, receiptInvalid, supplierImportFinalizationReceiptFromMap} from "./supplierImportFinalizationReceiptValidation";
import type {SupplierImportV2AssemblyResult} from "./supplierImportV2AssemblyTypes";

/** Trusted assembly input, not an authorization or provider-output boundary.
 * Source membership/decision validity remain the assembler's responsibility.
 * No IDs, times, decisions or disposition policy are invented here.
 */
export function createSupplierImportFinalizationReceipt(
  assembly: SupplierImportV2AssemblyResult, context: SupplierImportFinalizationReceiptContext,
): SupplierImportFinalizationReceipt {
  try {
    exact(assembly, ["resolutionId", "evaluatedRevision", "canFinalize", "blockers", "warnings", "informational", "accounting", "candidate"], "Assembly");
    if (assembly.canFinalize !== true || assembly.candidate === null || array(assembly.blockers, "Blockers").length !== 0) receiptInvalid();
    exact(context, ["tripId", "extractionId", "commandId", "expectedRevision", "policyVersion", "actorUid", "finalizedAt"], "Context");
    const trusted = {
      tripId: identity(context.tripId, "Trip"), extractionId: identity(context.extractionId, "Extraction"),
      commandId: boundedIdentity(context.commandId), expectedRevision: positiveInteger(context.expectedRevision, "Revision"),
      policyVersion: enumValue(context.policyVersion, itineraryDraftImportPolicies, "Policy"), actorUid: boundedIdentity(context.actorUid),
    };
    const finalizedAt = timestamp(dateMap(context.finalizedAt), "Finalized at");
    const candidate = validateItineraryDraftV2(assembly.candidate.id, itineraryDraftV2ToMap(assembly.candidate));
    const imported = candidate.importResult;
    if (assembly.resolutionId !== imported.resolutionId || assembly.evaluatedRevision !== imported.evaluatedRevision ||
        trusted.tripId !== candidate.tripId || trusted.extractionId !== imported.extractionId ||
        trusted.expectedRevision !== imported.evaluatedRevision || trusted.commandId !== imported.finalizationId ||
        trusted.policyVersion !== imported.policyVersion || trusted.actorUid !== candidate.createdByUid ||
        finalizedAt < candidate.updatedAt || candidate.sourcePackageIds.length !== 1 ||
        candidate.sourcePackageIds[0] !== imported.sourcePackageId) receiptInvalid();
    const outcomes = array(assembly.accounting, "Accounting").map((entry) => outcomeFromAccounting(entry, candidate));
    const receipt = supplierImportFinalizationReceiptFromMap({
      schemaVersion: supplierImportFinalizationReceiptSchemaVersion, tripId: trusted.tripId,
      extractionId: imported.extractionId, resolutionId: imported.resolutionId, sourcePackageId: imported.sourcePackageId,
      finalizationId: trusted.commandId, commandId: trusted.commandId, actorUid: trusted.actorUid, finalizedAt: dateMap(finalizedAt),
      evaluatedRevision: imported.evaluatedRevision, resultingRevision: imported.evaluatedRevision + 1,
      policyVersion: imported.policyVersion, canonicalSchemaVersion: candidate.schemaVersion, resultingDraftId: candidate.id,
      requestFingerprint: finalizationRequestFingerprint(trusted), contentDigest: supplierImportCanonicalContentDigest(candidate), outcomes,
    });
    assertSupplierImportReceiptMatchesCandidate(receipt, candidate);
    checkFindings(assembly, receipt);
    return receipt;
  } catch { return receiptInvalid(); }
}

const destinations: Readonly<Record<string, ReceiptOutputField>> = {
  service_inclusion: "inclusions", service_exclusion: "exclusions", service_notes: "notes",
  transfer_vehicle_type: "transferDetails.vehicleType", transfer_type: "transferDetails.transferType",
};

function outcomeFromAccounting(input: unknown, candidate: ItineraryDraftV2): object {
  const entry = exact(input, ["entityId", "entityKind", "origin", "outcome", "outputIds", "outputDayNumber",
    "mappingDestination", "sources", "decisionIds", "fieldChanges"], "Accounting");
  const id = identity(entry.entityId, "Entity");
  const manual = entry.entityKind === "consultant_day" || entry.entityKind === "consultant_service";
  if (entry.origin !== (manual ? "consultant" : "supplier") || entry.entityKind === "title" && id !== "title") receiptInvalid();
  const sources = array(entry.sources, "Sources");
  if (manual ? sources.length !== 0 : sources.length === 0) receiptInvalid();
  for (const source of sources) {
    const ref = exact(source, ["supplierSourcePackageId", "supplierSourceFileId", "sourceLabel"], "Source");
    if (ref.supplierSourcePackageId !== candidate.importResult.sourcePackageId) receiptInvalid();
    if (ref.supplierSourceFileId !== null) identity(ref.supplierSourceFileId, "Source file");
    sourceLabel(ref.sourceLabel);
  }
  const ids = array(entry.outputIds, "Output IDs").map((value) => identity(value, "Output"));
  unique(ids, "Output IDs");
  const decisions = array(entry.decisionIds, "Decisions").map((value) => identity(value, "Decision"));
  const operations = array(entry.fieldChanges, "Changes").map((value) => {
    const change = exact(value, ["field", "operation"], "Change");
    if (decisions.length !== 1) receiptInvalid();
    return {...change, decisionId: decisions[0]};
  });
  const outputs: ReceiptOutputTarget[] = [];
  const day = entry.entityKind === "day" || entry.entityKind === "consultant_day";
  if (entry.outputDayNumber !== null) {
    if (!day || ids.length !== 0) receiptInvalid();
    outputs.push({kind: "day", dayNumber: positiveInteger(entry.outputDayNumber, "Day"), field: "entity"});
  } else if (day && ids.length !== 0) receiptInvalid();
  const mappedField = entry.mappingDestination === null ? null : destinations[
    enumValue(entry.mappingDestination, Object.keys(destinations), "Mapping destination")];
  if (mappedField !== null && !(entry.outcome === "mapped" &&
      ["package_inclusion", "package_exclusion", "package_condition"].includes(String(entry.entityKind)))) receiptInvalid();
  if (entry.outcome === "mapped" && entry.entityKind !== "package_accommodation" && mappedField === null) receiptInvalid();
  const index = outputIndex(candidate);
  for (const outputId of ids) {
    const output = index.find((value) => "id" in value && value.id === outputId);
    if (!output) receiptInvalid();
    outputs.push({...output, field: mappedField ?? output.field} as ReceiptOutputTarget);
  }
  return {targetKind: entry.entityKind, targetId: entry.entityKind === "title" ? null : id,
    outcome: entry.outcome, decisionIds: decisions, outputTargets: outputs, fieldOperations: operations};
}

/** Optional read-side verification against the INITIAL result, never an edited
 * itinerary. Revalidates both inputs and checks linkage, digest and output ledger.
 */
export function assertSupplierImportReceiptMatchesCandidate(receipt: SupplierImportFinalizationReceipt, candidate: ItineraryDraftV2): void {
  try {
    receipt = supplierImportFinalizationReceiptFromMap({...receipt, finalizedAt: dateMap(receipt.finalizedAt)});
    candidate = validateItineraryDraftV2(candidate.id, itineraryDraftV2ToMap(candidate));
    const result = candidate.importResult;
    if (receipt.tripId !== candidate.tripId || receipt.resultingDraftId !== candidate.id ||
        receipt.canonicalSchemaVersion !== candidate.schemaVersion || receipt.actorUid !== candidate.createdByUid ||
        receipt.extractionId !== result.extractionId || receipt.resolutionId !== result.resolutionId ||
        receipt.sourcePackageId !== result.sourcePackageId || receipt.evaluatedRevision !== result.evaluatedRevision ||
        receipt.finalizationId !== result.finalizationId || receipt.policyVersion !== result.policyVersion ||
        receipt.contentDigest !== supplierImportCanonicalContentDigest(candidate)) receiptInvalid();
    const outputs = receipt.outcomes.flatMap((entry) => entry.outputTargets);
    const actual = outputs.filter((item) => item.field === "entity" || item.field === "title").map(outputKey).sort();
    const expected = outputIndex(candidate).map(outputKey).sort();
    if (JSON.stringify(actual) !== JSON.stringify(expected)) receiptInvalid();
    for (const entry of receipt.outcomes) {
      checkContributorIdentity(entry, candidate);
      for (const output of entry.outputTargets) {
        if (output.kind !== "service" || output.field === "entity") continue;
        const service = [...candidate.days.flatMap((day) => day.services), ...(candidate.unscheduledServices ?? [])].find((value) => value.id === output.id);
        if (!service || output.field === "inclusions" && service.inclusions.length === 0 ||
            output.field === "exclusions" && service.exclusions.length === 0 || output.field === "notes" && service.notes === null ||
            output.field === "transferDetails.vehicleType" && service.transferDetails?.vehicleType == null ||
            output.field === "transferDetails.transferType" && service.transferDetails?.transferType == null) receiptInvalid();
      }
    }
  } catch { receiptInvalid(); }
}

function outputIndex(candidate: ItineraryDraftV2): ReceiptOutputTarget[] {
  return [
    {kind: "draft", id: candidate.id, field: "title"},
    ...candidate.days.flatMap((day): ReceiptOutputTarget[] => [
      {kind: "day", dayNumber: day.dayNumber, field: "entity"},
      ...day.services.map((service) => ({kind: "service" as const, id: service.id, field: "entity" as const})),
    ]),
    ...(candidate.unscheduledServices ?? []).map((service): ReceiptOutputTarget => ({kind: "service", id: service.id, field: "entity"})),
    ...candidate.packageContent.accommodations.flatMap((row): ReceiptOutputTarget[] => [
      {kind: "package_accommodation", id: row.id, field: "entity"},
      ...row.options.map((option) => ({kind: "accommodation_option" as const, id: option.id, field: "entity" as const})),
    ]),
    ...candidate.packageContent.inclusions.map((row) => ({kind: "package_inclusion" as const, id: row.id, field: "entity" as const})),
    ...candidate.packageContent.exclusions.map((row) => ({kind: "package_exclusion" as const, id: row.id, field: "entity" as const})),
    ...candidate.packageContent.conditions.map((row) => ({kind: "package_condition" as const, id: row.id, field: "entity" as const})),
    ...candidate.reviewIssues.map((row) => ({kind: "review_issue" as const, id: row.id, field: "entity" as const})),
  ];
}

function outputKey(output: ReceiptOutputTarget): string {
  return output.kind === "day" ? `day:${output.dayNumber}` : `${output.kind}:${output.id}`;
}

function checkContributorIdentity(entry: SupplierImportReceiptOutcome, candidate: ItineraryDraftV2): void {
  const extractionId = candidate.importResult.extractionId;
  const idFor = (kind: string): string => `import:${extractionId.length}:${extractionId}:${kind}:${entry.targetId!.length}:${entry.targetId}`;
  for (const output of entry.outputTargets) {
    if (output.kind === "day" || output.kind === "draft" || output.field !== "entity") continue;
    const kind = entry.targetKind === "review_issue" ? "review" : entry.targetKind;
    if (output.id !== idFor(output.kind === "accommodation_option" ? "accommodation_option" : kind)) receiptInvalid();
    // Package inline lineage already names the same contributor and operations.
    const content = candidate.packageContent;
    const row = output.kind === "accommodation_option" ? content.accommodations.flatMap((item) => item.options).find((item) => item.id === output.id) :
      [...content.inclusions, ...content.exclusions, ...content.conditions].find((item) => item.id === output.id);
    if (row && (row.provenance.contributors.length !== 1 || row.provenance.contributors[0].stagedFactId !== entry.targetId ||
        JSON.stringify(row.provenance.decisionIds) !== JSON.stringify(entry.decisionIds) ||
        JSON.stringify([...row.provenance.fieldChanges].sort((a, b) => a.field < b.field ? -1 : 1)) !==
        JSON.stringify(entry.fieldOperations.map(({field, operation}) => ({field, operation}))))) receiptInvalid();
  }
}

function checkFindings(assembly: SupplierImportV2AssemblyResult, receipt: SupplierImportFinalizationReceipt): void {
  const warnings = array(assembly.warnings, "Warnings").map((value) => {
    const finding = exact(value, ["code", "targetKind", "targetId"], "Warning");
    if (finding.targetKind !== "review_issue") receiptInvalid();
    return `${enumValue(finding.code, ["snapshot_warning_open", "snapshot_warning_acknowledged", "review_issue_overridden"], "Warning")}:${identity(finding.targetId, "Review")}`;
  }).sort();
  const codes = {review_open_warning: "snapshot_warning_open", review_acknowledged: "snapshot_warning_acknowledged", review_overridden: "review_issue_overridden"};
  const expected = receipt.outcomes.filter((item) => item.outcome in codes)
    .map((item) => `${codes[item.outcome as keyof typeof codes]}:${item.targetId}`).sort();
  if (JSON.stringify(warnings) !== JSON.stringify(expected)) receiptInvalid();
  const informational = array(assembly.informational, "Informational").map((value) => {
    const finding = exact(value, ["code", "targetKind", "targetId"], "Information");
    if (finding.code !== "commercial_presence" || finding.targetKind !== "commercial_fact") receiptInvalid();
    return identity(finding.targetId, "Commercial marker");
  }).sort();
  if (JSON.stringify(informational) !== JSON.stringify(receipt.outcomes.filter((item) => item.targetKind === "commercial_presence").map((item) => item.targetId).sort())) receiptInvalid();
}
