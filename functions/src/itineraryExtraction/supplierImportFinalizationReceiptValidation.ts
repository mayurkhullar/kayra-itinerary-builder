import {itineraryDraftImportPolicies, itineraryDraftV2SchemaVersion} from "./itineraryDraftV2";
import {array, enumValue, exact, identity, immutable, positiveInteger, timestamp, unique} from "./itineraryDraftValidationPrimitives";
import {
  maxReceiptDecisionsAndManualItems, maxReceiptSnapshotEntities, receiptOperationFields,
  receiptOutcomeCodes, receiptOutputFields, receiptOutputKinds, receiptTargetKinds,
  SupplierImportFinalizationReceipt, SupplierImportFinalizationReceiptError,
  SupplierImportReceiptOutcome, ReceiptFieldOperation, ReceiptOutputTarget,
  ReceiptTargetKind, supplierImportFinalizationReceiptSchemaVersion,
} from "./supplierImportFinalizationReceipt";
import {finalizationRequestFingerprint} from "./supplierImportFinalizationReceiptDigest";

export function receiptInvalid(): never { throw new SupplierImportFinalizationReceiptError(); }

/** Plain transport boundary: exact UTC ISO timestamps, no Firestore types.
 * Shape validation alone does not authenticate source membership or the digest.
 * Creation additionally binds the receipt to the trusted assembly candidate.
 */
export function supplierImportFinalizationReceiptFromMap(input: unknown): SupplierImportFinalizationReceipt {
  try {
    const data = exact(input, ["schemaVersion", "tripId", "extractionId", "resolutionId", "sourcePackageId",
      "finalizationId", "commandId", "actorUid", "finalizedAt", "evaluatedRevision", "resultingRevision",
      "policyVersion", "canonicalSchemaVersion", "resultingDraftId", "requestFingerprint", "contentDigest", "outcomes"], "Receipt");
    const schemaVersion = enumValue(data.schemaVersion, [supplierImportFinalizationReceiptSchemaVersion], "Version");
    const tripId = identity(data.tripId, "Trip");
    const extractionId = identity(data.extractionId, "Extraction");
    const resolutionId = identity(data.resolutionId, "Resolution");
    const sourcePackageId = identity(data.sourcePackageId, "Package");
    const finalizationId = boundedIdentity(data.finalizationId);
    const commandId = boundedIdentity(data.commandId);
    const actorUid = boundedIdentity(data.actorUid);
    const finalizedAt = timestamp(data.finalizedAt, "Finalized at");
    const evaluatedRevision = positiveInteger(data.evaluatedRevision, "Evaluated revision");
    const resultingRevision = positiveInteger(data.resultingRevision, "Resulting revision");
    const policyVersion = enumValue(data.policyVersion, itineraryDraftImportPolicies, "Policy");
    const canonicalSchemaVersion = enumValue(data.canonicalSchemaVersion, [itineraryDraftV2SchemaVersion], "Canonical schema");
    const resultingDraftId = identity(data.resultingDraftId, "Draft");
    const requestFingerprint = digest(data.requestFingerprint);
    const contentDigest = digest(data.contentDigest);
    if (resolutionId !== extractionId || finalizationId !== commandId || resultingRevision !== evaluatedRevision + 1 ||
        requestFingerprint !== finalizationRequestFingerprint({tripId, extractionId, commandId,
          actorUid, expectedRevision: evaluatedRevision, policyVersion})) receiptInvalid();
    const outcomes = array(data.outcomes, "Outcomes").map(parseOutcome).sort(compareOutcomes);
    unique(outcomes.map((item) => item.targetId ?? "title"), "Accounting identities");
    if (outcomes.filter((item) => item.targetKind === "title").length !== 1) receiptInvalid();
    const manualCount = outcomes.filter((item) => item.outcome === "manual").length;
    const decisionCount = new Set(outcomes.flatMap((item) => item.decisionIds)).size;
    if (outcomes.length - manualCount - 1 > maxReceiptSnapshotEntities ||
        manualCount + decisionCount > maxReceiptDecisionsAndManualItems) receiptInvalid();
    validateOutputOwnership(outcomes, resultingDraftId);
    return immutable({schemaVersion, tripId, extractionId, resolutionId, sourcePackageId, finalizationId,
      commandId, actorUid, finalizedAt, evaluatedRevision, resultingRevision, policyVersion,
      canonicalSchemaVersion, resultingDraftId, requestFingerprint, contentDigest, outcomes});
  } catch { return receiptInvalid(); }
}

export const validateSupplierImportFinalizationReceipt = supplierImportFinalizationReceiptFromMap;

export function supplierImportFinalizationReceiptToMap(receipt: SupplierImportFinalizationReceipt): Readonly<Record<string, unknown>> {
  try {
    const normalized = supplierImportFinalizationReceiptFromMap({...receipt, finalizedAt: dateMap(receipt.finalizedAt)});
    return immutable({...normalized, finalizedAt: dateMap(normalized.finalizedAt)});
  } catch { return receiptInvalid(); }
}

export function serializeSupplierImportFinalizationReceipt(receipt: SupplierImportFinalizationReceipt): string {
  return JSON.stringify(supplierImportFinalizationReceiptToMap(receipt));
}

export function dateMap(value: Date): string {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) receiptInvalid();
  return value.toISOString();
}

export function boundedIdentity(value: unknown): string {
  const result = identity(value, "Command/actor");
  if (result.length > 128) receiptInvalid();
  return result;
}

function digest(value: unknown): string {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/u.test(value)) receiptInvalid();
  return value;
}

export function compareOutcomes(a: SupplierImportReceiptOutcome, b: SupplierImportReceiptOutcome): number {
  return compare(a.targetKind, b.targetKind) || compare(a.targetId ?? "", b.targetId ?? "");
}
function compare(a: string, b: string): number { return a < b ? -1 : a > b ? 1 : 0; }

function parseOutcome(input: unknown): SupplierImportReceiptOutcome {
  const data = exact(input, ["targetKind", "targetId", "outcome", "decisionIds", "outputTargets", "fieldOperations"], "Outcome");
  const targetKind = enumValue(data.targetKind, receiptTargetKinds, "Target kind");
  const targetId = targetIdentity(targetKind, data.targetId);
  const outcome = enumValue(data.outcome, receiptOutcomeCodes, "Outcome code");
  const decisionIds = array(data.decisionIds, "Decisions").map((value) => identity(value, "Decision"));
  unique(decisionIds, "Decisions");
  if (decisionIds.length > 1 || decisionIds.some((id) => id !== (targetId ?? "title"))) receiptInvalid();
  const outputTargets = array(data.outputTargets, "Outputs").map(parseOutput)
    .sort((a, b) => compare(JSON.stringify(a), JSON.stringify(b)));
  unique(outputTargets.map((item) => JSON.stringify(item)), "Outputs");
  const fieldOperations = array(data.fieldOperations, "Operations").map((value): ReceiptFieldOperation => {
    const item = exact(value, ["field", "operation", "decisionId"], "Operation");
    const field = enumValue(item.field, receiptOperationFields[targetKind], "Field");
    const operation = enumValue(item.operation, ["set", "clear"], "Operation");
    const decisionId = identity(item.decisionId, "Decision");
    if (!decisionIds.includes(decisionId) || operation === "clear" &&
        (["title", "serviceType", "canonicalOrder", "day", "category", "kind", "value", "disposition"].includes(field) ||
          field === "text" && targetKind !== "visa")) receiptInvalid();
    return {field, operation, decisionId};
  }).sort((a, b) => compare(a.field, b.field));
  unique(fieldOperations.map((item) => item.field), "Fields");
  const item = {targetKind, targetId, outcome, decisionIds, outputTargets, fieldOperations};
  validateDisposition(item);
  return item;
}

function targetIdentity(kind: ReceiptTargetKind, value: unknown): string | null {
  if (kind === "title") {
    if (value !== null) receiptInvalid();
    return null;
  }
  const id = identity(value, "Target");
  if (kind === "consultant_day" || kind === "consultant_service") {
    const prefix = kind === "consultant_day" ? "consultant-day-" : "consultant-service-";
    if (!id.startsWith(prefix) || id.length === prefix.length) receiptInvalid();
  } else {
    const prefix = kind === "day" ? "staged-day-" : kind === "service" ? "staged-service-" :
      kind.startsWith("package_") ? "package-fact-" : kind === "review_issue" ? "review-" :
        kind === "commercial_presence" ? "commercial-presence-" : `ancillary-${kind}-`;
    const suffix = id.slice(prefix.length);
    if (!id.startsWith(prefix) || !/^[1-9]\d*$/u.test(suffix) || !Number.isSafeInteger(Number(suffix)) ||
        kind === "commercial_presence" && suffix !== "1") receiptInvalid();
  }
  return id;
}

function parseOutput(input: unknown): ReceiptOutputTarget {
  // Inspect via a descriptor first: never execute an untrusted accessor.
  const kindValue = input && typeof input === "object" ? Object.getOwnPropertyDescriptor(input, "kind")?.value : undefined;
  const kind = enumValue(kindValue, receiptOutputKinds, "Output kind");
  const data = exact(input, kind === "day" ? ["kind", "dayNumber", "field"] : ["kind", "id", "field"], "Output");
  const field = enumValue(data.field, receiptOutputFields, "Output field");
  if (kind === "day") {
    if (field !== "entity") receiptInvalid();
    return {kind, dayNumber: positiveInteger(data.dayNumber, "Day number"), field};
  }
  if (kind === "draft" ? field !== "title" : kind !== "service" && field !== "entity") receiptInvalid();
  if (kind === "service" && field === "title") receiptInvalid();
  return {kind, id: identity(data.id, "Output"), field};
}

function validateDisposition(item: SupplierImportReceiptOutcome): void {
  const {targetKind: kind, outcome: code, decisionIds: decisions, fieldOperations: operations, outputTargets: outputs} = item;
  const allowed = kind === "title" ? ["auto_retained", "explicit_retained"] :
    kind === "consultant_day" || kind === "consultant_service" ? ["manual"] :
      kind === "commercial_presence" ? ["informational"] :
        kind === "review_issue" ? ["review_resolved", "review_derived", "review_overridden", "review_open_warning", "review_acknowledged"] :
          kind === "flight" || kind === "visa" ? ["handled_separately", "routed", "excluded"] :
            kind.startsWith("package_") ? ["auto_retained", "explicit_retained", "mapped", "excluded"] :
              ["auto_retained", "explicit_retained", "excluded"];
  if (!allowed.includes(code)) receiptInvalid();
  const automatic = ["auto_retained", "manual", "informational", "review_derived"].includes(code);
  if (automatic && (decisions.length !== 0 || operations.length !== 0) ||
      !automatic && code !== "review_open_warning" && decisions.length !== 1) receiptInvalid();
  if (["excluded", "informational", "handled_separately", "routed", "review_resolved", "review_derived", "review_overridden"].includes(code)) {
    if (outputs.length !== 0) receiptInvalid();
    return;
  }
  if (kind === "package_accommodation" && code !== "mapped") {
    if (outputs.length !== 2 || !outputs.some((o) => o.kind === "package_accommodation") ||
        !outputs.some((o) => o.kind === "accommodation_option")) receiptInvalid();
    return;
  }
  if (outputs.length !== 1) receiptInvalid();
  const target = outputs[0];
  const expected = kind === "title" ? "draft" : kind === "consultant_day" ? "day" :
    kind === "consultant_service" || code === "mapped" ? "service" : kind;
  if (target.kind !== expected) receiptInvalid();
  if (code === "mapped" && (kind === "package_inclusion" || kind === "package_exclusion")) {
    if (target.field !== (kind === "package_inclusion" ? "inclusions" : "exclusions")) receiptInvalid();
  } else if (code === "mapped" && kind === "package_condition") {
    if (!["notes", "transferDetails.vehicleType", "transferDetails.transferType"].includes(target.field)) receiptInvalid();
  } else if (target.field !== (kind === "title" ? "title" : "entity")) receiptInvalid();
}

/** Every whole output has one owner; field mappings must reference that owner. */
function validateOutputOwnership(outcomes: readonly SupplierImportReceiptOutcome[], draftId: string): void {
  const outputs = outcomes.flatMap((item) => item.outputTargets);
  const whole = outputs.filter((item) => item.field === "entity" || item.field === "title");
  unique(whole.map((item) => item.kind === "day" ? `day:${item.dayNumber}` : `id:${item.id}`), "Output owners");
  const title = outcomes.find((item) => item.targetKind === "title")!.outputTargets[0];
  if (title.kind !== "draft" || title.id !== draftId) receiptInvalid();
  for (const output of outputs.filter((item) => item.kind === "service" && item.field !== "entity")) {
    if (!("id" in output) || !whole.some((item) => item.kind === "service" && item.id === output.id)) receiptInvalid();
  }
}
