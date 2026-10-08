import {createHash} from "node:crypto";
import {ItineraryDraftImportPolicy, itineraryDraftImportPolicies} from "./itineraryDraftV2";
import {enumValue, exact, identity, immutable, positiveInteger} from "./itineraryDraftValidationPrimitives";
import {supplierImportResolutionPaths} from "./supplierImportResolutionRepository";
import type {SupplierImportFinalizationAssessment} from "./supplierImportV2AssemblyTypes";

/** Internal request. The server derives finalizationId = commandId and draft ID.
 * The future callable supplies the authenticated actor separately, never a role.
 */
export interface SupplierImportFinalizationRequest {
  readonly tripId: string;
  readonly extractionId: string;
  readonly commandId: string;
  readonly expectedRevision: number;
  readonly policyVersion: ItineraryDraftImportPolicy;
}

export type FinalizationCapacityBoundary = "canonical" | "package_content" | "receipt" |
  "resolution" | "event" | "commit" | "inputs" | "nesting" | "firestore";
export type SupplierImportFinalizationResult =
  Readonly<{outcome: "applied" | "already_applied"; resolutionId: string; revision: number; resultingDraftId: string; finalizationId: string}> |
  Readonly<{outcome: "resolution_conflict"; resolutionId: string; currentRevision: number}> |
  Readonly<{outcome: "resolution_not_started" | "resolution_finalized"; resolutionId: string; revision: number}> |
  Readonly<{outcome: "snapshot_unavailable" | "trusted_state_invalid"; resolutionId: string}> |
  Readonly<{outcome: "persistence_capacity_exceeded"; resolutionId: string; boundary: FinalizationCapacityBoundary}> |
  Readonly<{outcome: "not_ready"; assessment: SupplierImportFinalizationAssessment}>;

export class SupplierImportFinalizationError extends Error {
  constructor(readonly code: "INVALID_FINALIZATION_REQUEST" | "UNAUTHORIZED_OR_FORBIDDEN" | "FINALIZATION_PERSISTENCE_FAILED") {
    super(code === "INVALID_FINALIZATION_REQUEST" ? "Supplier Import finalization request is invalid." :
      code === "UNAUTHORIZED_OR_FORBIDDEN" ? "Supplier Import finalization is not authorized." :
        "Supplier Import finalization could not be completed.");
    this.name = "SupplierImportFinalizationError";
  }
}

export class InvalidFinalizationState extends Error {
  constructor() { super("Stored Supplier Import finalization state is invalid."); }
}

export function validateFinalizationRequest(input: unknown): SupplierImportFinalizationRequest {
  try {
    const data = exact(input, ["tripId", "extractionId", "commandId", "expectedRevision", "policyVersion"], "Finalization request");
    const tripId = finalizationIdentity(data.tripId);
    const extractionId = finalizationIdentity(data.extractionId);
    const commandId = finalizationIdentity(data.commandId, 128);
    const expectedRevision = positiveInteger(data.expectedRevision, "Revision");
    if (!Number.isSafeInteger(expectedRevision + 1)) throw new Error();
    return immutable({tripId, extractionId, commandId, expectedRevision,
      policyVersion: enumValue(data.policyVersion, itineraryDraftImportPolicies, "Policy")});
  } catch { throw new SupplierImportFinalizationError("INVALID_FINALIZATION_REQUEST"); }
}

export function finalizationIdentity(input: unknown, maximum = 256): string {
  const result = identity(input, "Identity");
  if (result.length > maximum) throw new SupplierImportFinalizationError("INVALID_FINALIZATION_REQUEST");
  return result;
}

export function supplierImportFinalizationPaths(request: SupplierImportFinalizationRequest) {
  request = validateFinalizationRequest(request);
  const resolution = supplierImportResolutionPaths(request.tripId, request.extractionId);
  // Reserved namespace, injective tuple encoding before SHA-256, no randomness.
  // One Resolution has one initial canonical result, independent of command ID.
  const resultingDraftId = `supplier-import-${createHash("sha256")
    .update(JSON.stringify([request.tripId, request.extractionId]), "utf8").digest("hex")}`;
  return Object.freeze({...resolution, resultingDraftId,
    snapshot: `trips/${request.tripId}/supplier_extractions/${request.extractionId}`,
    draft: `trips/${request.tripId}/itinerary_drafts/${resultingDraftId}`,
    receipt: `${resolution.root}/finalizations/${request.commandId}`,
    event: `${resolution.auditEvents}/${request.commandId}`,
  });
}
