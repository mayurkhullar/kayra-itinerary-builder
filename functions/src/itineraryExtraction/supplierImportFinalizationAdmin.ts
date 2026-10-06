import {isDeepStrictEqual} from "node:util";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {
  InvalidFinalizationState, SupplierImportFinalizationError, SupplierImportFinalizationRequest,
  SupplierImportFinalizationResult, finalizationIdentity, supplierImportFinalizationPaths, validateFinalizationRequest,
} from "./supplierImportFinalization";
import {FinalizationCapacityError, checkFinalizationWriteBudgets, isFirestoreCapacityError} from "./supplierImportFinalizationCapacity";
import {LoadedSupplierImportFinalization, authorizeFinalization, loadSupplierImportFinalizationAdmin} from "./supplierImportFinalizationLoaderAdmin";
import {SupplierImportFinalizationPlan, originalFinalizationInput, prepareSupplierImportFinalization} from "./supplierImportFinalizationPlan";
import {finalizationReceiptForFirestore, itineraryDraftV2ForFirestore, readStoredFinalizationReceipt,
  readStoredItineraryDraftV2, resolutionFromFirestore} from "./supplierImportFinalizationStored";
import {supplierImportFinalizationReceiptToMap} from "./supplierImportFinalizationReceiptValidation";
import {SupplierImportResolutionServerActor} from "./supplierImportResolutionMutationAdmin";
import {supplierImportResolutionValueForFirestore} from "./supplierImportResolutionRepositoryAdmin";
import {SupplierImportResolutionError} from "./supplierImportResolutionValidation";
import {SupplierExtractionPersistenceError} from "./supplierExtractionRepository";
import {SupplierImportFinalizationReceiptError} from "./supplierImportFinalizationReceipt";
import {ItineraryDraftV2Error, exact} from "./itineraryDraftValidationPrimitives";

/** Sole write entry point. Internal Admin API; deliberately not exported from
 * Functions index or connected to a callable/UI/extraction request route.
 */
export async function finalizeSupplierImportAdmin(
  db: Firestore, actor: SupplierImportResolutionServerActor, input: SupplierImportFinalizationRequest,
): Promise<SupplierImportFinalizationResult> {
  const request = validateFinalizationRequest(input);
  try {
    exact(actor, ["uid", "email"], "Authenticated actor");
    actor = {uid: finalizationIdentity(actor.uid, 128), email: actor.email};
    if (typeof actor.email !== "string") throw new Error();
  } catch { throw new SupplierImportFinalizationError("INVALID_FINALIZATION_REQUEST"); }
  try {
    const loaded = await loadSupplierImportFinalizationAdmin(db, actor, request);
    if (loaded === "not_started") return {outcome: "resolution_not_started", resolutionId: request.extractionId, revision: 0};
    if (loaded === "snapshot_unavailable") return {outcome: "snapshot_unavailable", resolutionId: request.extractionId};
    if ("conflictRevision" in loaded) return conflict(request, loaded.conflictRevision);
    const sealed = loaded.resolution.root.status === "finalized";
    const current = sealed ? originalFinalizationInput(loaded.snapshot, loaded.resolution) : loaded.resolution;
    if (sealed) {
      const final = loaded.resolution.auditEvents.find((event) => event.action === "finalize");
      if (!final) throw new InvalidFinalizationState();
      if (final.commandId !== request.commandId) return {outcome: "resolution_finalized", resolutionId: request.extractionId, revision: loaded.resolution.root.revision};
      if (final.actorUid !== actor.uid || final.previousRevision !== request.expectedRevision) return conflict(request, loaded.resolution.root.revision);
    } else if (loaded.resolution.root.revision !== request.expectedRevision) return conflict(request, loaded.resolution.root.revision);
    // Server-owned logical time captured ONCE outside the retryable callback.
    const at = sealed ? loaded.resolution.root.finalizedAt! : Timestamp.now().toDate().toISOString();
    const plan = prepareSupplierImportFinalization(loaded.snapshot, current, request, actor.uid, at);
    if (!("candidate" in plan)) {
      if (sealed) throw new InvalidFinalizationState();
      return {outcome: "not_ready", assessment: plan};
    }
    const paths = supplierImportFinalizationPaths(request);
    const writes = {
      canonical: {path: paths.draft, data: itineraryDraftV2ForFirestore(plan.candidate)},
      receipt: {path: paths.receipt, data: finalizationReceiptForFirestore(plan.receipt)},
      resolution: {path: paths.root, data: supplierImportResolutionValueForFirestore(plan.root) as Record<string, unknown>},
      event: {path: paths.event, data: supplierImportResolutionValueForFirestore(plan.event) as Record<string, unknown>},
    };
    checkFinalizationWriteBudgets(writes);
    return await db.runTransaction(async (transaction) => {
      const [profile, trip, extraction, root, receipt, event, draft] = await transaction.getAll(
        db.doc(`users/${actor.uid}`), db.doc(`trips/${request.tripId}`), db.doc(paths.snapshot), db.doc(paths.root),
        db.doc(paths.receipt), db.doc(paths.event), db.doc(paths.draft),
      );
      authorizeFinalization(actor, profile, trip);
      if (!extraction.exists || !isDeepStrictEqual(extraction.data(), loaded.snapshotRoot) || !root.exists) throw new InvalidFinalizationState();
      const state = resolutionFromFirestore(root.data()) as Record<string, unknown>;
      if (state.status === "finalized") {
        if (!receipt.exists || !event.exists || !draft.exists) {
          if (!receipt.exists && !event.exists && draft.exists && state.resultingDraftId === paths.resultingDraftId &&
              readStoredItineraryDraftV2(paths.resultingDraftId, draft.data()).importResult.finalizationId !== request.commandId) {
            return {outcome: "resolution_finalized", resolutionId: request.extractionId, revision: Number(state.revision)};
          }
          throw new InvalidFinalizationState();
        }
        verifyCommittedTuple(loaded, plan, state, receipt.data(), event.data(), draft.data());
        return success("already_applied", request, plan);
      }
      if (state.status !== "active" || !Number.isSafeInteger(state.revision) || Number(state.revision) < 1) throw new InvalidFinalizationState();
      if (state.revision !== request.expectedRevision) return conflict(request, Number(state.revision));
      if (!isDeepStrictEqual(state, current.root)) throw new InvalidFinalizationState();
      if (receipt.exists) throw new InvalidFinalizationState();
      if (event.exists || draft.exists) return conflict(request, Number(state.revision));
      // No more reads after this point. All finalization evidence is atomic.
      transaction.create(db.doc(paths.draft), writes.canonical.data);
      transaction.create(db.doc(paths.receipt), writes.receipt.data);
      const {status, revision, resultingDraftId, updatedByUid, updatedAt, finalizedByUid, finalizedAt} = writes.resolution.data;
      transaction.update(db.doc(paths.root), {status, revision, resultingDraftId, updatedByUid, updatedAt, finalizedByUid, finalizedAt});
      transaction.create(db.doc(paths.event), writes.event.data);
      return success("applied", request, plan);
    });
  } catch (error) {
    if (error instanceof SupplierImportFinalizationError) throw error;
    if (error instanceof FinalizationCapacityError || isFirestoreCapacityError(error)) return {
      outcome: "persistence_capacity_exceeded", resolutionId: request.extractionId,
      boundary: error instanceof FinalizationCapacityError ? error.boundary : "firestore",
    };
    if (error instanceof InvalidFinalizationState || error instanceof SupplierImportResolutionError ||
        error instanceof SupplierImportFinalizationReceiptError || error instanceof ItineraryDraftV2Error ||
        error instanceof SupplierExtractionPersistenceError && error.code !== "SUPPLIER_EXTRACTION_PERSISTENCE_FAILED") {
      return {outcome: "trusted_state_invalid", resolutionId: request.extractionId};
    }
    // No raw error/cause, source data, SDK text or digest input crosses this API.
    throw new SupplierImportFinalizationError("FINALIZATION_PERSISTENCE_FAILED");
  }
}

function verifyCommittedTuple(
  loaded: LoadedSupplierImportFinalization, plan: SupplierImportFinalizationPlan, root: Record<string, unknown>,
  receiptData: unknown, eventData: unknown, draftData: unknown,
): void {
  const receipt = readStoredFinalizationReceipt(receiptData);
  const at = receipt.finalizedAt.toISOString();
  const expectedReceipt = {...supplierImportFinalizationReceiptToMap(plan.receipt), finalizedAt: at};
  if (!isDeepStrictEqual(supplierImportFinalizationReceiptToMap(receipt), expectedReceipt) ||
      !isDeepStrictEqual(root, {...plan.root, updatedAt: at, finalizedAt: at}) ||
      !isDeepStrictEqual(resolutionFromFirestore(eventData), {...plan.event, occurredAt: at})) throw new InvalidFinalizationState();
  if (Date.parse(at) < Date.parse(loaded.snapshot.createdAt)) throw new InvalidFinalizationState();
  const draft = readStoredItineraryDraftV2(plan.candidate.id, draftData);
  // Rebuilt initial candidate+receipt prove contentDigest. Current itinerary
  // prose may have been edited later; compare only immutable identity linkage.
  if (draft.id !== receipt.resultingDraftId || draft.tripId !== receipt.tripId ||
      !isDeepStrictEqual(draft.importResult, plan.candidate.importResult) || draft.createdByUid !== receipt.actorUid ||
      draft.createdAt.toISOString() !== at) throw new InvalidFinalizationState();
}

function conflict(request: SupplierImportFinalizationRequest, currentRevision: number): SupplierImportFinalizationResult {
  return {outcome: "resolution_conflict", resolutionId: request.extractionId, currentRevision};
}
function success(outcome: "applied" | "already_applied", request: SupplierImportFinalizationRequest, plan: SupplierImportFinalizationPlan): SupplierImportFinalizationResult {
  return {outcome, resolutionId: request.extractionId, revision: plan.receipt.resultingRevision,
    resultingDraftId: plan.candidate.id, finalizationId: request.commandId};
}
