import {HttpsError} from "firebase-functions/v2/https";
import {
  FinalizationCapacityBoundary, SupplierImportFinalizationError,
  SupplierImportFinalizationRequest, SupplierImportFinalizationResult,
  finalizationIdentity, validateFinalizationRequest,
} from "./supplierImportFinalization";
import type {SupplierImportResolutionServerActor} from "./supplierImportResolutionMutationAdmin";
import type {FinalizationFinding, SupplierImportFinalizationAssessment} from "./supplierImportV2AssemblyTypes";

export interface SupplierImportFinalizationCallableDependencies {
  finalize(actor: SupplierImportResolutionServerActor,
    request: SupplierImportFinalizationRequest): Promise<SupplierImportFinalizationResult>;
}

export type SupplierImportFinalizationCallableResult =
  Readonly<{outcome: "applied" | "already_applied"; resolutionId: string;
    revision: number; resultingDraftId: string}> |
  Readonly<{outcome: "resolution_conflict"; resolutionId: string; currentRevision: number}> |
  Readonly<{outcome: "resolution_not_started" | "resolution_finalized";
    resolutionId: string; revision: number}> |
  Readonly<{outcome: "persistence_capacity_exceeded"; resolutionId: string;
    boundary: FinalizationCapacityBoundary}> |
  Readonly<{outcome: "not_ready"; assessment: Readonly<Pick<
    SupplierImportFinalizationAssessment,
    "resolutionId" | "evaluatedRevision" | "blockers" | "warnings"
  > & {canFinalize: false}>}>;

export async function handleSupplierImportFinalization(
  callableRequest: {auth?: {uid: string; token: {email?: unknown}}; data: unknown},
  dependencies: SupplierImportFinalizationCallableDependencies |
    (() => SupplierImportFinalizationCallableDependencies),
  log: (event: string, fields: Record<string, unknown>) => void,
): Promise<SupplierImportFinalizationCallableResult> {
  try {
    const actor = requireActor(callableRequest.auth);
    const request = parseSupplierImportFinalizationRequest(callableRequest.data);
    let result: SupplierImportFinalizationResult;
    try {
      const services = typeof dependencies === "function" ? dependencies() : dependencies;
      // One invocation, no transport retry or second idempotency mechanism.
      result = await services.finalize(actor, request);
    } catch (error) {
      throw engineError(error);
    }
    const response = callableResult(result);
    log("supplier-import-finalization-callable-completed", {
      functionName: "finalizeSupplierImport", outcome: response.outcome,
    });
    return response;
  } catch (error) {
    const mapped = error instanceof HttpsError ? error : internalError();
    log("supplier-import-finalization-callable-rejected", {
      functionName: "finalizeSupplierImport", code: mapped.code,
    });
    throw mapped;
  }
}

export function parseSupplierImportFinalizationRequest(input: unknown): SupplierImportFinalizationRequest {
  // Reuse the exact Admin contract, including its authoritative policy constant.
  try { return validateFinalizationRequest(input); }
  catch { throw new HttpsError("invalid-argument", "A valid Supplier Import finalization request is required."); }
}

function requireActor(auth: {uid: string; token: {email?: unknown}} | undefined): SupplierImportResolutionServerActor {
  try {
    if (!auth) throw new Error();
    return Object.freeze({uid: finalizationIdentity(auth.uid, 128),
      email: typeof auth.token?.email === "string" ? auth.token.email : ""});
  } catch { throw new HttpsError("unauthenticated", "Sign in to finalize a Supplier Import review."); }
}

function callableResult(result: SupplierImportFinalizationResult): SupplierImportFinalizationCallableResult {
  switch (result.outcome) {
  case "applied":
  case "already_applied":
    return Object.freeze({outcome: result.outcome, resolutionId: result.resolutionId,
      revision: result.revision, resultingDraftId: result.resultingDraftId});
  case "resolution_conflict":
    return Object.freeze({outcome: result.outcome, resolutionId: result.resolutionId,
      currentRevision: result.currentRevision});
  case "resolution_not_started":
  case "resolution_finalized":
    return Object.freeze({outcome: result.outcome, resolutionId: result.resolutionId, revision: result.revision});
  case "persistence_capacity_exceeded":
    return Object.freeze({outcome: result.outcome, resolutionId: result.resolutionId, boundary: result.boundary});
  case "not_ready": {
    const assessment = result.assessment;
    // Project findings individually: never spread domain/private payloads.
    const findings = <T extends string>(items: readonly FinalizationFinding<T>[]) =>
      Object.freeze(items.map(({code, targetKind, targetId}) => Object.freeze({code, targetKind, targetId})));
    return Object.freeze({outcome: result.outcome, assessment: Object.freeze({
      resolutionId: assessment.resolutionId, evaluatedRevision: assessment.evaluatedRevision,
      canFinalize: false as const, blockers: findings(assessment.blockers), warnings: findings(assessment.warnings),
    })});
  }
  case "snapshot_unavailable":
    throw new HttpsError("failed-precondition", "The Supplier Extraction Snapshot is unavailable.");
  case "trusted_state_invalid":
    throw new HttpsError("failed-precondition", "The Supplier Import review cannot be finalized in its current state.");
  default:
    throw internalError();
  }
}

function engineError(error: unknown): HttpsError {
  if (error instanceof SupplierImportFinalizationError) {
    if (error.code === "UNAUTHORIZED_OR_FORBIDDEN") {
      return new HttpsError("permission-denied", "You cannot finalize this Supplier Import review.");
    }
    if (error.code === "INVALID_FINALIZATION_REQUEST") {
      return new HttpsError("invalid-argument", "The Supplier Import finalization request is invalid.");
    }
  }
  // Even an unexpected HttpsError from a dependency must not expose its details.
  return internalError();
}

function internalError(): HttpsError {
  return new HttpsError("internal", "Supplier Import finalization could not be completed.");
}
