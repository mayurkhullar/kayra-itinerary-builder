import {assessSupplierImportFinalization} from
  "./supplierImportFinalizationAssessment";
import {
  ManualItemMetadata,
  SupplierImportAuditAction,
  SupplierImportAuditEvent,
  SupplierImportChangedField,
  SupplierImportDecision,
  SupplierImportManualItem,
  SupplierImportResolutionAggregate,
  SupplierImportResolutionRoot,
  supplierImportResolutionSchemaVersion,
} from "./supplierImportResolution";
import {
  SupplierImportResolutionError,
  validateSupplierImportResolution,
} from "./supplierImportResolutionValidation";
import {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";

type SemanticDecision<T> = T extends SupplierImportDecision ?
  Omit<T, "decisionId" | "lastRevision" | "updatedByUid" | "updatedAt"> : never;
type SemanticManualItem<T> = T extends SupplierImportManualItem ?
  Omit<T, keyof ManualItemMetadata> : never;

export type SupplierImportResolutionMutationCommand =
  Readonly<{action: "start_review"}> |
  Readonly<{
    action: "set_decision";
    decision: SemanticDecision<SupplierImportDecision>;
  }> |
  Readonly<{action: "remove_decision"; decisionId: string}> |
  Readonly<{
    action: "upsert_manual_item";
    item: SemanticManualItem<SupplierImportManualItem>;
  }> |
  Readonly<{action: "remove_manual_item"; manualItemId: string}>;

export interface SupplierImportResolutionMutationRequest {
  tripId: string;
  extractionId: string;
  expectedRevision: number;
  commandId: string;
  mutation: SupplierImportResolutionMutationCommand;
}

export interface SupplierImportResolutionMutationActor {
  uid: string;
}

export type SupplierImportResolutionMutationResult =
  Readonly<{
    outcome: "applied";
    resolutionId: string;
    revision: number;
    status: "active";
    canFinalize: boolean;
    blockerCount: number;
    warningCount: number;
  }> |
  Readonly<{
    outcome: "already_applied";
    resolutionId: string;
    revision: number;
  }> |
  Readonly<{
    outcome: "resolution_conflict";
    resolutionId: string;
    currentRevision: number;
  }> |
  Readonly<{
    outcome: "resolution_not_started" | "resolution_finalized";
    resolutionId: string;
    revision: number;
  }>;

export type SupplierImportResolutionMutationErrorCode =
  "UNAUTHORIZED_OR_FORBIDDEN" |
  "SNAPSHOT_UNAVAILABLE" |
  "INVALID_MUTATION" |
  "MALFORMED_STORED_RESOLUTION" |
  "MUTATION_PERSISTENCE_FAILED";

export class SupplierImportResolutionMutationError extends Error {
  constructor(
    readonly code: SupplierImportResolutionMutationErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "SupplierImportResolutionMutationError";
  }
}

export interface SupplierImportResolutionTransactionState {
  aggregate: SupplierImportResolutionAggregate | null;
  existingCommandEvent: SupplierImportAuditEvent | null;
}

export interface SupplierImportResolutionMutationPlan {
  root: SupplierImportResolutionRoot;
  event: SupplierImportAuditEvent;
  decision: Readonly<{
    operation: "set" | "delete";
    decisionId: string;
    value: SupplierImportDecision | null;
  }> | null;
  manualItem: Readonly<{
    operation: "set" | "delete";
    manualItemId: string;
    value: SupplierImportManualItem | null;
  }> | null;
}

export interface SupplierImportResolutionMutationTransaction {
  readState(commandId: string): Promise<SupplierImportResolutionTransactionState>;
  commit(plan: SupplierImportResolutionMutationPlan): void;
}

export interface SupplierImportResolutionMutationStore {
  runTransaction<T>(
    operation: (transaction: SupplierImportResolutionMutationTransaction) => Promise<T>,
  ): Promise<T>;
}

export async function mutateSupplierImportResolution(
  snapshot: SupplierExtractionSnapshot,
  request: SupplierImportResolutionMutationRequest,
  actor: SupplierImportResolutionMutationActor,
  occurredAt: string,
  store: SupplierImportResolutionMutationStore,
): Promise<SupplierImportResolutionMutationResult> {
  validateRequest(request, actor, occurredAt);
  if (snapshot.tripId !== request.tripId ||
      snapshot.extractionId !== request.extractionId) invalid();
  try {
    return await store.runTransaction(async (transaction) => {
      let state: SupplierImportResolutionTransactionState;
      try {
        state = await transaction.readState(request.commandId);
      } catch (error) {
        if (error instanceof SupplierImportResolutionError) {
          throw new SupplierImportResolutionMutationError(
            "MALFORMED_STORED_RESOLUTION",
            "Stored Supplier Import Resolution is malformed.",
          );
        }
        throw error;
      }
      if (state.existingCommandEvent !== null) {
        return Object.freeze({
          outcome: "already_applied" as const,
          resolutionId: request.extractionId,
          revision: state.existingCommandEvent.resultingRevision,
        });
      }
      if (state.aggregate === null) {
        if (request.mutation.action !== "start_review") {
          return Object.freeze({outcome: "resolution_not_started" as const,
            resolutionId: request.extractionId, revision: 0});
        }
        if (request.expectedRevision !== 0) {
          return Object.freeze({outcome: "resolution_conflict" as const,
            resolutionId: request.extractionId, currentRevision: 0});
        }
        const plan = startPlan(snapshot, request.commandId, actor.uid, occurredAt);
        validateSupplierImportResolution(snapshot, {
          root: plan.root, decisions: [], manualItems: [], auditEvents: [plan.event],
        });
        transaction.commit(plan);
        return applied(snapshot, plan.root, [], [], [plan.event]);
      }
      const current = state.aggregate;
      if (request.mutation.action === "start_review") invalid();
      if (current.root.status === "finalized") {
        return Object.freeze({outcome: "resolution_finalized" as const,
          resolutionId: current.root.resolutionId, revision: current.root.revision});
      }
      if (request.expectedRevision !== current.root.revision) {
        return Object.freeze({outcome: "resolution_conflict" as const,
          resolutionId: current.root.resolutionId,
          currentRevision: current.root.revision});
      }
      const plan = mutationPlan(current, request.mutation, request.commandId,
        actor.uid, occurredAt);
      const projected = project(current, plan);
      const validated = validateSupplierImportResolution(snapshot, projected);
      transaction.commit(plan);
      return applied(snapshot, validated.root, validated.decisions,
        validated.manualItems, validated.auditEvents);
    });
  } catch (error) {
    if (error instanceof SupplierImportResolutionMutationError) throw error;
    if (error instanceof SupplierImportResolutionError) invalid();
    throw new SupplierImportResolutionMutationError(
      "MUTATION_PERSISTENCE_FAILED",
      "Supplier Import Resolution mutation did not complete.",
    );
  }
}

function startPlan(
  snapshot: SupplierExtractionSnapshot,
  commandId: string,
  uid: string,
  occurredAt: string,
): SupplierImportResolutionMutationPlan {
  const root: SupplierImportResolutionRoot = {
    schemaVersion: supplierImportResolutionSchemaVersion,
    resolutionId: snapshot.extractionId,
    tripId: snapshot.tripId,
    extractionId: snapshot.extractionId,
    sourcePackageId: snapshot.sourcePackageId,
    snapshotSchemaVersion: snapshot.schemaVersion,
    status: "active",
    revision: 1,
    createdByUid: uid,
    createdAt: occurredAt,
    updatedByUid: uid,
    updatedAt: occurredAt,
    finalizedByUid: null,
    finalizedAt: null,
    resultingDraftId: null,
  };
  return {root, event: auditEvent(commandId, snapshot.extractionId, 0, uid,
    occurredAt, "open_review", "resolution", snapshot.extractionId,
    {kind: "lifecycle", status: "active"}), decision: null, manualItem: null};
}

function mutationPlan(
  current: SupplierImportResolutionAggregate,
  command: Exclude<SupplierImportResolutionMutationCommand,
    Readonly<{action: "start_review"}>>,
  commandId: string,
  uid: string,
  occurredAt: string,
): SupplierImportResolutionMutationPlan {
  const revision = current.root.revision + 1;
  const root = {...current.root, revision, updatedByUid: uid, updatedAt: occurredAt};
  if (command.action === "set_decision") {
    assertNoTrustedFields(command.decision);
    const decisionId = command.decision.decisionKind === "title" ?
      "title" : command.decision.targetEntityId;
    const value = {...command.decision, decisionId, lastRevision: revision,
      updatedByUid: uid, updatedAt: occurredAt} as SupplierImportDecision;
    return {root, decision: {operation: "set", decisionId, value}, manualItem: null,
      event: decisionEvent(commandId, current.root.extractionId,
        current.root.revision, uid, occurredAt, "set_decision", value)};
  }
  if (command.action === "remove_decision") {
    const existing = current.decisions.find((item) =>
      item.decisionId === command.decisionId);
    if (existing === undefined) invalid();
    return {root, decision: {operation: "delete",
      decisionId: command.decisionId, value: null}, manualItem: null,
    event: decisionEvent(commandId, current.root.extractionId,
      current.root.revision, uid, occurredAt, "remove_decision", existing)};
  }
  if (command.action === "upsert_manual_item") {
    assertNoTrustedFields(command.item);
    const manualItemId = command.item.itemKind === "consultant_day" ?
      command.item.manualDayId : command.item.manualServiceId;
    const existing = current.manualItems.find((item) => manualId(item) === manualItemId);
    const value = {...command.item, origin: "consultant",
      createdByUid: existing?.createdByUid ?? uid,
      createdAt: existing?.createdAt ?? occurredAt,
      updatedByUid: uid, updatedAt: occurredAt, lastRevision: revision,
    } as SupplierImportManualItem;
    return {root, decision: null,
      manualItem: {operation: "set", manualItemId, value},
      event: manualEvent(commandId, current.root.extractionId,
        current.root.revision, uid, occurredAt, value.itemKind, manualItemId,
        existing === undefined ? "added" : "updated")};
  }
  const existing = current.manualItems.find((item) =>
    manualId(item) === command.manualItemId);
  if (existing === undefined) invalid();
  return {root, decision: null, manualItem: {operation: "delete",
    manualItemId: command.manualItemId, value: null},
  event: manualEvent(commandId, current.root.extractionId,
    current.root.revision, uid, occurredAt, existing.itemKind,
    command.manualItemId, "removed")};
}

function project(
  current: SupplierImportResolutionAggregate,
  plan: SupplierImportResolutionMutationPlan,
): SupplierImportResolutionAggregate {
  let decisions = [...current.decisions];
  if (plan.decision !== null) {
    decisions = decisions.filter((item) => item.decisionId !== plan.decision?.decisionId);
    if (plan.decision.value !== null) decisions.push(plan.decision.value);
  }
  let manualItems = [...current.manualItems];
  if (plan.manualItem !== null) {
    manualItems = manualItems.filter((item) => manualId(item) !==
      plan.manualItem?.manualItemId);
    if (plan.manualItem.value !== null) manualItems.push(plan.manualItem.value);
  }
  return {root: plan.root, decisions, manualItems,
    auditEvents: [...current.auditEvents, plan.event]};
}

function applied(
  snapshot: SupplierExtractionSnapshot,
  root: SupplierImportResolutionRoot,
  decisions: readonly SupplierImportDecision[],
  manualItems: readonly SupplierImportManualItem[],
  auditEvents: readonly SupplierImportAuditEvent[],
): SupplierImportResolutionMutationResult {
  const assessment = assessSupplierImportFinalization(snapshot, {
    root, decisions, manualItems, auditEvents,
  });
  return Object.freeze({outcome: "applied", resolutionId: root.resolutionId,
    revision: root.revision, status: "active", canFinalize: assessment.canFinalize,
    blockerCount: assessment.blockers.length,
    warningCount: assessment.warnings.length});
}

function decisionEvent(
  commandId: string, extractionId: string, previousRevision: number,
  uid: string, at: string, operation: "set_decision" | "remove_decision",
  decision: SupplierImportDecision,
): SupplierImportAuditEvent {
  const disposition = "outcome" in decision ? decision.outcome : decision.disposition;
  const action: SupplierImportAuditAction = operation === "remove_decision" ?
    "revert_decision" : decision.decisionKind === "title" ?
      "set_title_decision" : decision.decisionKind === "day" ?
        "set_day_decision" : decision.decisionKind === "service" ?
          "set_service_decision" : decision.decisionKind === "review_issue" ?
            "set_review_issue_decision" :
            decision.decisionKind === "flight" || decision.decisionKind === "visa" ?
              "set_ancillary_decision" : "set_package_fact_decision";
  const targetKind = decision.decisionKind === "day" ? "day" :
    decision.decisionKind === "service" ? "service" :
      decision.decisionKind === "review_issue" ? "review_issue" :
        decision.decisionKind === "flight" || decision.decisionKind === "visa" ?
          "ancillary_fact" : decision.decisionKind === "title" ? "title" :
            "package_fact";
  return auditEvent(commandId, extractionId, previousRevision, uid, at, action,
    targetKind, decision.targetEntityId, {kind: "decision", disposition,
      changedFields: changedFields(decision),
      exclusionReason: "exclusionReason" in decision ? decision.exclusionReason : null,
      referencedIds: []});
}

function changedFields(
  decision: SupplierImportDecision,
): readonly SupplierImportChangedField[] {
  if (!("overrides" in decision)) return [];
  const fields: string[] = [];
  for (const [key, value] of Object.entries(decision.overrides)) {
    if ((key === "hotel" || key === "transfer" || key === "activity") &&
        value !== null && typeof value === "object") {
      fields.push(...Object.keys(value));
    } else {
      fields.push(key);
    }
  }
  return fields as SupplierImportChangedField[];
}

function manualEvent(
  commandId: string, extractionId: string, previousRevision: number,
  uid: string, at: string, itemKind: "consultant_day" | "consultant_service",
  itemId: string, operation: "added" | "updated" | "removed",
): SupplierImportAuditEvent {
  const action: SupplierImportAuditAction = itemKind === "consultant_day" ?
    operation === "removed" ? "remove_manual_day" : "upsert_manual_day" :
    operation === "removed" ? "remove_manual_service" : "upsert_manual_service";
  return auditEvent(commandId, extractionId, previousRevision, uid, at, action,
    itemKind === "consultant_day" ? "manual_day" : "manual_service", itemId,
    {kind: "manual_item", itemKind, operation});
}

function auditEvent(
  commandId: string, extractionId: string, previousRevision: number,
  uid: string, occurredAt: string, action: SupplierImportAuditAction,
  targetKind: SupplierImportAuditEvent["targetKind"], targetId: string | null,
  metadata: SupplierImportAuditEvent["metadata"],
): SupplierImportAuditEvent {
  return {eventId: commandId, commandId, resolutionId: extractionId, extractionId,
    previousRevision, resultingRevision: previousRevision + 1, actorUid: uid,
    occurredAt, action, targetKind, targetId, metadata};
}

function validateRequest(
  request: SupplierImportResolutionMutationRequest,
  actor: SupplierImportResolutionMutationActor,
  occurredAt: string,
): void {
  if (!isSupplierImportResolutionIdentifier(request.tripId) ||
      !isSupplierImportResolutionIdentifier(request.extractionId) ||
      !isSupplierImportResolutionIdentifier(request.commandId, 128) ||
      !isSupplierImportResolutionIdentifier(actor.uid) ||
      !Number.isInteger(request.expectedRevision) ||
      request.expectedRevision < 0 || Number.isNaN(Date.parse(occurredAt))) invalid();
  assertNoTrustedFields(request.mutation);
}

const forbiddenFields = new Set([
  "createdByUid", "updatedByUid", "actorUid", "createdAt", "updatedAt",
  "occurredAt", "lastRevision", "revision", "sourcePackageId", "resolutionId",
  "schemaVersion", "snapshotSchemaVersion", "finalizedAt", "finalizedByUid",
  "resultingDraftId", "eventId", "commandId",
]);

function assertNoTrustedFields(input: unknown): void {
  if (input === null || typeof input !== "object") return;
  if (Array.isArray(input)) return input.forEach(assertNoTrustedFields);
  for (const [key, value] of Object.entries(input as Record<string, unknown>)) {
    if (forbiddenFields.has(key)) invalid();
    assertNoTrustedFields(value);
  }
}

function manualId(item: SupplierImportManualItem): string {
  return item.itemKind === "consultant_day" ? item.manualDayId : item.manualServiceId;
}

export function isSupplierImportResolutionIdentifier(
  value: unknown,
  maximumLength = 256,
): value is string {
  return typeof value === "string" && value.length > 0 &&
    value.length <= maximumLength &&
    !value.includes("/") && value !== "." && value !== "..";
}

function invalid(): never {
  throw new SupplierImportResolutionMutationError(
    "INVALID_MUTATION", "Supplier Import Resolution mutation is invalid.",
  );
}
