import {Firestore, Timestamp} from "firebase-admin/firestore";
import {
  SupplierImportResolutionMutationError,
  SupplierImportResolutionMutationPlan,
  SupplierImportResolutionMutationRequest,
  SupplierImportResolutionMutationResult,
  SupplierImportResolutionMutationStore,
  mutateSupplierImportResolution,
} from "./supplierImportResolutionMutation";
import {readSupplierExtractionSnapshot} from "./supplierExtractionRepository";
import {adminSupplierExtractionRepositoryStore} from
  "./supplierExtractionRepositoryAdmin";
import {
  reconstructStoredSupplierImportResolution,
} from "./supplierImportResolutionStoredValidation";
import {
  supplierImportResolutionReferences,
  supplierImportResolutionValueForFirestore,
} from "./supplierImportResolutionRepositoryAdmin";

export interface SupplierImportResolutionServerActor {
  uid: string;
  email: string;
}

export type SupplierImportResolutionMutationLog = (
  event: string,
  fields: Record<string, unknown>,
) => void;

export async function applySupplierImportResolutionMutationAdmin(
  db: Firestore,
  actor: SupplierImportResolutionServerActor,
  request: SupplierImportResolutionMutationRequest,
  now: Date,
  log: SupplierImportResolutionMutationLog = () => undefined,
): Promise<SupplierImportResolutionMutationResult> {
  const startedAt = Date.now();
  try {
    let snapshot;
    try {
      snapshot = await readSupplierExtractionSnapshot(
        request.tripId,
        request.extractionId,
        adminSupplierExtractionRepositoryStore(db),
      );
    } catch (_) {
      throw new SupplierImportResolutionMutationError(
        "SNAPSHOT_UNAVAILABLE",
        "Supplier Extraction Snapshot is unavailable.",
      );
    }
    const store = adminMutationStore(db, snapshot, actor);
    const result = await mutateSupplierImportResolution(
      snapshot, request, {uid: actor.uid}, now.toISOString(), store,
    );
    log("supplier-import-resolution-mutation-completed", {
      tripId: request.tripId,
      extractionId: request.extractionId,
      action: request.mutation.action,
      expectedRevision: request.expectedRevision,
      outcome: result.outcome,
      revision: "revision" in result ? result.revision : result.currentRevision,
      durationMs: Date.now() - startedAt,
    });
    return result;
  } catch (error) {
    log("supplier-import-resolution-mutation-failed", {
      tripId: request.tripId,
      extractionId: request.extractionId,
      action: request.mutation.action,
      expectedRevision: request.expectedRevision,
      code: error instanceof SupplierImportResolutionMutationError ?
        error.code : "internal",
      durationMs: Date.now() - startedAt,
    });
    throw error;
  }
}

export function requireSupplierImportResolutionAuthorization(
  actor: SupplierImportResolutionServerActor,
  profile: Record<string, unknown> | null | undefined,
  trip: Record<string, unknown> | null | undefined,
): void {
  if (!/^[^@\s]+@kholidaymaps\.com$/u.test(actor.email.trim().toLowerCase()) ||
      trip === null || trip === undefined ||
      profile?.status !== "active" ||
      (profile?.role !== "agent" && profile?.role !== "admin") ||
      (profile.role !== "admin" && trip?.ownerUid !== actor.uid)) {
    forbidden();
  }
}

function adminMutationStore(
  db: Firestore,
  snapshot: Parameters<typeof reconstructStoredSupplierImportResolution>[0],
  actor: SupplierImportResolutionServerActor,
): SupplierImportResolutionMutationStore {
  return {
    runTransaction: (operation) => db.runTransaction(async (firestoreTransaction) => {
      const references = supplierImportResolutionReferences(
        db, snapshot.tripId, snapshot.extractionId,
      );
      let committed = false;
      const transaction = {
        async readState(commandId: string) {
          const eventReference = references.auditEvent(commandId);
          const profileReference = db.doc(`users/${actor.uid}`);
          const tripReference = db.doc(`trips/${snapshot.tripId}`);
          const [profile, trip, root, existingEvent] =
            await firestoreTransaction.getAll(
              profileReference, tripReference, references.root, eventReference,
          );
          requireSupplierImportResolutionAuthorization(
            actor, profile.exists ? profile.data() : null,
            trip.exists ? trip.data() : null,
          );
          if (!root.exists) {
            if (existingEvent.exists) {
              throw new SupplierImportResolutionMutationError(
                "MALFORMED_STORED_RESOLUTION",
                "Stored Supplier Import Resolution is malformed.",
              );
            }
            return {aggregate: null, existingCommandEvent: null};
          }
          const [decisions, manualItems, events] = await Promise.all([
            firestoreTransaction.get(references.root.collection("decisions")),
            firestoreTransaction.get(references.root.collection("manual_items")),
            firestoreTransaction.get(references.root.collection("events")),
          ]);
          const records = {
            root: {documentId: root.id, value: fromFirestore(root.data())},
            decisions: decisions.docs.map((item) => ({documentId: item.id,
              value: fromFirestore(item.data())})),
            manualItems: manualItems.docs.map((item) => ({documentId: item.id,
              value: fromFirestore(item.data())})),
            auditEvents: events.docs.map((item) => ({documentId: item.id,
              value: fromFirestore(item.data())})),
          };
          const aggregate = reconstructStoredSupplierImportResolution(
            snapshot, records, snapshot.tripId, snapshot.extractionId,
          );
          return {aggregate,
            existingCommandEvent: existingEvent.exists ?
              aggregate.auditEvents.find((item) => item.eventId === commandId) ?? null :
              null};
        },
        commit(plan: SupplierImportResolutionMutationPlan) {
          if (committed) throw new Error("Mutation plan already committed.");
          committed = true;
          const rootData = supplierImportResolutionValueForFirestore(plan.root) as
            Record<string, unknown>;
          if (plan.root.revision === 1) {
            firestoreTransaction.create(references.root, rootData);
          } else {
            firestoreTransaction.set(references.root, rootData);
          }
          if (plan.decision !== null) {
            const reference = references.decision(plan.decision.decisionId);
            if (plan.decision.operation === "delete") {
              firestoreTransaction.delete(reference);
            } else {
              firestoreTransaction.set(reference,
                supplierImportResolutionValueForFirestore(plan.decision.value));
            }
          }
          if (plan.manualItem !== null) {
            const reference = references.manualItem(plan.manualItem.manualItemId);
            if (plan.manualItem.operation === "delete") {
              firestoreTransaction.delete(reference);
            } else {
              firestoreTransaction.set(reference,
                supplierImportResolutionValueForFirestore(plan.manualItem.value));
            }
          }
          firestoreTransaction.create(references.auditEvent(plan.event.eventId),
            supplierImportResolutionValueForFirestore(plan.event) as
              Record<string, unknown>);
        },
      };
      return operation(transaction);
    }),
  };
}

function fromFirestore(input: unknown): unknown {
  if (input instanceof Timestamp) return input.toDate().toISOString();
  if (Array.isArray(input)) return input.map(fromFirestore);
  if (input === null || typeof input !== "object") return input;
  return Object.fromEntries(Object.entries(input as Record<string, unknown>)
    .map(([key, value]) => [key, fromFirestore(value)]));
}

function forbidden(): never {
  throw new SupplierImportResolutionMutationError(
    "UNAUTHORIZED_OR_FORBIDDEN",
    "Supplier Import Resolution mutation is not authorized.",
  );
}
