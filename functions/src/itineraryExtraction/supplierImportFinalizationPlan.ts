import {ItineraryDraftV2} from "./itineraryDraftV2";
import {assembleSupplierImportV2} from "./supplierImportV2Assembly";
import {SupplierImportFinalizationAssessment} from "./supplierImportV2AssemblyTypes";
import {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import {SupplierImportAuditEvent, SupplierImportResolutionAggregate, SupplierImportResolutionRoot} from "./supplierImportResolution";
import {serializeSupplierImportResolution} from "./supplierImportResolutionStoredValidation";
import {createSupplierImportFinalizationReceipt} from "./supplierImportFinalizationReceiptFactory";
import {SupplierImportFinalizationReceipt} from "./supplierImportFinalizationReceipt";
import {InvalidFinalizationState, SupplierImportFinalizationRequest, supplierImportFinalizationPaths} from "./supplierImportFinalization";

export interface SupplierImportFinalizationPlan {
  readonly candidate: ItineraryDraftV2;
  readonly receipt: SupplierImportFinalizationReceipt;
  readonly root: SupplierImportResolutionRoot;
  readonly event: SupplierImportAuditEvent;
}

/** Internal pure preparation; never writes and never accepts a caller candidate. */
export function prepareSupplierImportFinalization(
  snapshot: SupplierExtractionSnapshot, current: SupplierImportResolutionAggregate,
  request: SupplierImportFinalizationRequest, actorUid: string, at: string,
): SupplierImportFinalizationPlan | SupplierImportFinalizationAssessment {
  if (current.root.status !== "active" || current.root.revision !== request.expectedRevision ||
      Date.parse(at) < Date.parse(current.root.updatedAt)) throw new InvalidFinalizationState();
  const draftId = supplierImportFinalizationPaths(request).resultingDraftId;
  const assembly = assembleSupplierImportV2(snapshot, current, {draftId, tripId: request.tripId,
    actorUid, finalizationId: request.commandId, createdAt: at, updatedAt: at, policyVersion: request.policyVersion});
  if (!assembly.canFinalize) {
    const {candidate: _candidate, accounting: _accounting, ...assessment} = assembly;
    return Object.freeze(assessment);
  }
  const receipt = createSupplierImportFinalizationReceipt(assembly, {tripId: request.tripId, extractionId: request.extractionId,
    commandId: request.commandId, expectedRevision: request.expectedRevision, policyVersion: request.policyVersion,
    actorUid, finalizedAt: new Date(at)});
  const root: SupplierImportResolutionRoot = {...current.root, status: "finalized", revision: receipt.resultingRevision,
    resultingDraftId: draftId, updatedByUid: actorUid, updatedAt: at, finalizedByUid: actorUid, finalizedAt: at};
  const event: SupplierImportAuditEvent = {eventId: request.commandId, commandId: request.commandId,
    resolutionId: request.extractionId, extractionId: request.extractionId, previousRevision: request.expectedRevision,
    resultingRevision: receipt.resultingRevision, actorUid, occurredAt: at, action: "finalize", targetKind: "finalization",
    targetId: request.commandId, metadata: {kind: "lifecycle", status: "finalized"}};
  // The sealed root and event pass the SAME stored + cross-reference boundary.
  serializeSupplierImportResolution(snapshot, {...current, root, auditEvents: [...current.auditEvents, event]});
  return {candidate: assembly.candidate, receipt, root, event};
}

/** Reconstruct the initial input from sealed immutable history for replay digest
 * verification. This is an in-memory projection, NEVER a reopened stored root.
 */
export function originalFinalizationInput(snapshot: SupplierExtractionSnapshot, sealed: SupplierImportResolutionAggregate): SupplierImportResolutionAggregate {
  const finalEvents = sealed.auditEvents.filter((event) => event.action === "finalize");
  const final = finalEvents[0];
  const before = sealed.auditEvents.find((event) => event.resultingRevision === sealed.root.revision - 1);
  if (sealed.root.status !== "finalized" || finalEvents.length !== 1 || !before ||
      final.resultingRevision !== sealed.root.revision || final.actorUid !== sealed.root.finalizedByUid ||
      final.occurredAt !== sealed.root.finalizedAt || final.targetKind !== "finalization" || final.targetId !== final.commandId ||
      final.metadata.kind !== "lifecycle" || final.metadata.status !== "finalized" ||
      sealed.root.updatedAt !== final.occurredAt || sealed.root.updatedByUid !== final.actorUid) throw new InvalidFinalizationState();
  const current: SupplierImportResolutionAggregate = {...sealed,
    root: {...sealed.root, status: "active", revision: final.previousRevision, updatedByUid: before.actorUid,
      updatedAt: before.occurredAt, finalizedByUid: null, finalizedAt: null, resultingDraftId: null},
    auditEvents: sealed.auditEvents.filter((event) => event.eventId !== final.eventId),
  };
  serializeSupplierImportResolution(snapshot, current);
  return current;
}
