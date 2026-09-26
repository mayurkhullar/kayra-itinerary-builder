import {HttpsError} from "firebase-functions/v2/https";
import {
  CleanupAuth, CleanupContext, CleanupInput, SourceObject,
  parseInput, requireAuth, requireContext, requireObject, storagePath,
} from "./cleanupValidation";

export interface CleanupDependencies {
  readContext(uid: string, input: CleanupInput): Promise<CleanupContext>;
  readObject(path: string): Promise<SourceObject | null>;
  // Must revalidate current context and atomically make uploading -> failed.
  claimRollback(uid: string, input: CleanupInput, object: SourceObject | null): Promise<string>;
  deleteObject(path: string, object: SourceObject): Promise<boolean>;
  deleteMetadata(uid: string, input: CleanupInput, uploader: string): Promise<boolean>;
}

export interface CleanupResult {
  cleaned: true;
  storageDeleted: boolean;
  metadataDeleted: boolean;
}

export type CleanupLog = (event: string, fields: Record<string, unknown>) => void;

export async function cleanupUpload(
  request: {auth?: CleanupAuth; data: unknown},
  dependencies: CleanupDependencies | (() => CleanupDependencies),
  log: CleanupLog,
): Promise<CleanupResult> {
  let stage = "validation";
  let identifiers: Record<string, string> = {};
  try {
    const uid = requireAuth(request.auth);
    const input = parseInput(request.data);
    identifiers = {tripId: input.tripId, packageId: input.packageId, sourceFileId: input.sourceFileId};
    stage = "authorization";
    const services = typeof dependencies === "function" ? dependencies() : dependencies;
    const context = await services.readContext(uid, input);
    const uploader = requireContext(context, uid, input);
    const path = storagePath(input);
    stage = "object-inspection";
    const object = await services.readObject(path);
    requireObject(object, input, uploader);
    stage = "rollback-claim";
    const claimedUploader = await services.claimRollback(uid, input, object);
    stage = "storage-delete";
    const storageDeleted = object ? await services.deleteObject(path, object) : false;
    stage = "metadata-delete";
    const metadataDeleted = await services.deleteMetadata(uid, input, claimedUploader);
    const result: CleanupResult = {cleaned: true, storageDeleted, metadataDeleted};
    log("supplier-source-cleanup-completed", {...identifiers, ...result});
    return result;
  } catch (error) {
    const code = error instanceof HttpsError ? error.code : "internal";
    log("supplier-source-cleanup-rejected", {...identifiers, stage, code});
    if (error instanceof HttpsError) throw error;
    // Never expose SDK messages, object names, tokens or stack traces to clients.
    throw new HttpsError("internal", "Cleanup could not complete. Retry the same request.");
  }
}
