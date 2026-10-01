import {HttpsError} from "firebase-functions/v2/https";
import {
  isSupplierImportResolutionIdentifier,
  SupplierImportResolutionMutationCommand,
  SupplierImportResolutionMutationError,
  SupplierImportResolutionMutationRequest,
  SupplierImportResolutionMutationResult,
} from "./supplierImportResolutionMutation";
import {
  SupplierImportResolutionServerActor,
} from "./supplierImportResolutionMutationAdmin";

interface SupplierImportResolutionCallableAuth {
  uid: string;
  token: {email?: unknown};
}

export interface SupplierImportResolutionCallableDependencies {
  mutate(
    actor: SupplierImportResolutionServerActor,
    request: SupplierImportResolutionMutationRequest,
  ): Promise<SupplierImportResolutionMutationResult>;
}

export type SupplierImportResolutionCallableLog = (
  event: string,
  fields: Record<string, unknown>,
) => void;

export async function handleSupplierImportResolutionMutation(
  callableRequest: {
    auth?: SupplierImportResolutionCallableAuth;
    data: unknown;
  },
  dependencies: SupplierImportResolutionCallableDependencies |
    (() => SupplierImportResolutionCallableDependencies),
  log: SupplierImportResolutionCallableLog,
): Promise<SupplierImportResolutionMutationResult> {
  const startedAt = Date.now();
  let stage = "authentication";
  let safeContext: Record<string, unknown> = {
    functionName: "applySupplierImportResolutionMutation",
  };
  try {
    const actor = requireCallableActor(callableRequest.auth);
    safeContext = {...safeContext, uid: actor.uid};
    stage = "input-validation";
    const request = parseSupplierImportResolutionMutationRequest(
      callableRequest.data,
    );
    safeContext = {
      ...safeContext,
      tripId: request.tripId,
      extractionId: request.extractionId,
      commandId: request.commandId,
      action: request.mutation.action,
      expectedRevision: request.expectedRevision,
    };
    stage = "authorized-mutation";
    const services = typeof dependencies === "function" ?
      dependencies() : dependencies;
    const result = callableResult(await services.mutate(actor, request));
    log("supplier-import-resolution-callable-completed", {
      ...safeContext,
      outcome: result.outcome,
      revision: "revision" in result ?
        result.revision : result.currentRevision,
      durationMs: Date.now() - startedAt,
    });
    return result;
  } catch (error) {
    const mapped = callableError(error, stage);
    log("supplier-import-resolution-callable-rejected", {
      ...safeContext,
      stage,
      code: mapped.code,
      durationMs: Date.now() - startedAt,
    });
    throw mapped;
  }
}

export function parseSupplierImportResolutionMutationRequest(
  input: unknown,
): SupplierImportResolutionMutationRequest {
  const record = exactRecord(input, [
    "tripId", "extractionId", "expectedRevision", "commandId", "mutation",
  ]);
  if (!isSupplierImportResolutionIdentifier(record.tripId) ||
      !isSupplierImportResolutionIdentifier(record.extractionId) ||
      !isSupplierImportResolutionIdentifier(record.commandId, 128) ||
      !Number.isInteger(record.expectedRevision) ||
      (record.expectedRevision as number) < 0) {
    invalidRequest();
  }
  return Object.freeze({
    tripId: record.tripId as string,
    extractionId: record.extractionId as string,
    expectedRevision: record.expectedRevision as number,
    commandId: record.commandId as string,
    mutation: parseMutation(record.mutation),
  });
}

function parseMutation(input: unknown): SupplierImportResolutionMutationCommand {
  if (!isRecord(input) || typeof input.action !== "string") invalidRequest();
  if (input.action === "start_review") {
    exactRecord(input, ["action"]);
    return Object.freeze({action: "start_review"});
  }
  if (input.action === "remove_decision") {
    const record = exactRecord(input, ["action", "decisionId"]);
    if (!isSupplierImportResolutionIdentifier(record.decisionId)) invalidRequest();
    return Object.freeze({action: "remove_decision",
      decisionId: record.decisionId as string});
  }
  if (input.action === "remove_manual_item") {
    const record = exactRecord(input, ["action", "manualItemId"]);
    if (!isSupplierImportResolutionIdentifier(record.manualItemId)) invalidRequest();
    return Object.freeze({action: "remove_manual_item",
      manualItemId: record.manualItemId as string});
  }
  if (input.action === "set_decision") {
    const record = exactRecord(input, ["action", "decision"]);
    return Object.freeze({action: "set_decision",
      decision: transportObject(record.decision)}) as
      SupplierImportResolutionMutationCommand;
  }
  if (input.action === "upsert_manual_item") {
    const record = exactRecord(input, ["action", "item"]);
    return Object.freeze({action: "upsert_manual_item",
      item: transportObject(record.item)}) as
      SupplierImportResolutionMutationCommand;
  }
  invalidRequest();
}

function requireCallableActor(
  auth: SupplierImportResolutionCallableAuth | undefined,
): SupplierImportResolutionServerActor {
  if (!auth || !isSupplierImportResolutionIdentifier(auth.uid)) {
    throw new HttpsError(
      "unauthenticated",
      "Sign in to update a Supplier Import review.",
    );
  }
  return Object.freeze({
    uid: auth.uid,
    email: typeof auth.token.email === "string" ? auth.token.email : "",
  });
}

function callableResult(
  result: SupplierImportResolutionMutationResult,
): SupplierImportResolutionMutationResult {
  if (result.outcome === "applied") {
    return Object.freeze({
      outcome: result.outcome,
      resolutionId: result.resolutionId,
      revision: result.revision,
      status: result.status,
      canFinalize: result.canFinalize,
      blockerCount: result.blockerCount,
      warningCount: result.warningCount,
    });
  }
  if (result.outcome === "resolution_conflict") {
    return Object.freeze({
      outcome: result.outcome,
      resolutionId: result.resolutionId,
      currentRevision: result.currentRevision,
    });
  }
  return Object.freeze({
    outcome: result.outcome,
    resolutionId: result.resolutionId,
    revision: result.revision,
  });
}

function callableError(error: unknown, stage: string): HttpsError {
  if (error instanceof HttpsError && stage !== "authorized-mutation") {
    return error;
  }
  if (!(error instanceof SupplierImportResolutionMutationError)) {
    return new HttpsError(
      "internal",
      "Supplier Import Resolution mutation could not be completed.",
    );
  }
  if (error.code === "UNAUTHORIZED_OR_FORBIDDEN") {
    return new HttpsError(
      "permission-denied",
      "You cannot update this Supplier Import review.",
    );
  }
  if (error.code === "INVALID_MUTATION") {
    return new HttpsError(
      "invalid-argument",
      "The Supplier Import Resolution mutation is invalid.",
    );
  }
  if (error.code === "SNAPSHOT_UNAVAILABLE") {
    return new HttpsError(
      "failed-precondition",
      "The Supplier Extraction Snapshot is unavailable.",
    );
  }
  if (error.code === "MALFORMED_STORED_RESOLUTION") {
    return new HttpsError(
      "failed-precondition",
      "The Supplier Import review cannot be updated in its current state.",
    );
  }
  return new HttpsError(
    "internal",
    "Supplier Import Resolution mutation could not be completed.",
  );
}

function exactRecord(
  input: unknown,
  keys: readonly string[],
): Record<string, unknown> {
  if (!isRecord(input)) invalidRequest();
  const inputKeys = Object.keys(input);
  if (inputKeys.length !== keys.length ||
      !keys.every((key) => Object.prototype.hasOwnProperty.call(input, key))) {
    invalidRequest();
  }
  return input;
}

function transportObject(input: unknown): Record<string, unknown> {
  if (!isRecord(input)) invalidRequest();
  return cloneTransport(input) as Record<string, unknown>;
}

function cloneTransport(input: unknown): unknown {
  if (input === null || typeof input === "string" ||
      typeof input === "boolean") return input;
  if (typeof input === "number" && Number.isFinite(input)) return input;
  if (Array.isArray(input)) return input.map(cloneTransport);
  if (!isRecord(input)) invalidRequest();
  return Object.freeze(Object.fromEntries(
    Object.entries(input).map(([key, value]) => [key, cloneTransport(value)]),
  ));
}

function isRecord(input: unknown): input is Record<string, unknown> {
  return input !== null && typeof input === "object" && !Array.isArray(input);
}

function invalidRequest(): never {
  throw new HttpsError(
    "invalid-argument",
    "A valid Supplier Import Resolution mutation request is required.",
  );
}
