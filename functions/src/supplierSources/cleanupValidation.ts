import {HttpsError} from "firebase-functions/v2/https";

export interface CleanupInput {
  tripId: string;
  packageId: string;
  sourceFileId: string;
  fileName: string;
}

export interface CleanupAuth {
  uid: string;
  token: {email?: unknown};
}

export type RecordData = Record<string, unknown>;
export interface CleanupContext {
  profile: RecordData | null;
  trip: RecordData | null;
  package: RecordData | null;
  file: RecordData | null;
}

export interface SourceObject {
  generation: string;
  metageneration: string;
  metadata: RecordData;
}

export function requireAuth(auth: CleanupAuth | undefined): string {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in to request cleanup.");
  const email = auth.token.email;
  if (typeof email !== "string" ||
      !/^[^@\s]+@kholidaymaps\.com$/.test(email.trim().toLowerCase())) {
    throw new HttpsError("permission-denied", "A Kayra company account is required.");
  }
  if (!validSegment(auth.uid)) {
    throw new HttpsError("unauthenticated", "Invalid authenticated identity.");
  }
  return auth.uid;
}

function validSegment(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 &&
    value.trim() === value && !/[\/\\\u0000-\u001f\u007f]/.test(value) &&
    value !== "." && value !== "..";
}

export function parseInput(data: unknown): CleanupInput {
  const keys = ["tripId", "packageId", "sourceFileId", "fileName"];
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "Cleanup identifiers are required.");
  }
  const record = data as RecordData;
  if (Object.keys(record).length !== keys.length ||
      !keys.every((key) => validSegment(record[key])) ||
      (record.fileName as string).includes("..")) {
    throw new HttpsError("invalid-argument", "Invalid cleanup identifiers or filename.");
  }
  return {
    tripId: record.tripId as string,
    packageId: record.packageId as string,
    sourceFileId: record.sourceFileId as string,
    fileName: record.fileName as string,
  };
}

export function storagePath(input: CleanupInput): string {
  return `trips/${input.tripId}/supplier_sources/${input.sourceFileId}/${input.fileName}`;
}

export function requireContext(
  context: CleanupContext, uid: string, input: CleanupInput,
): string {
  const {profile, trip, package: sourcePackage, file} = context;
  if (!profile || profile.status !== "active" ||
      (profile.role !== "agent" && profile.role !== "admin")) {
    throw new HttpsError("permission-denied", "An active Kayra profile is required.");
  }
  if (!trip) throw new HttpsError("not-found", "Trip does not exist.");
  if (profile.role !== "admin" && trip.ownerUid !== uid) {
    throw new HttpsError("permission-denied", "You cannot manage this Trip.");
  }
  if (!sourcePackage) throw new HttpsError("not-found", "Source package does not exist.");
  if (sourcePackage.tripId !== input.tripId ||
      !["uploading", "failed"].includes(sourcePackage.status as string) ||
      !validSegment(sourcePackage.uploadedByUid)) {
    throw new HttpsError("failed-precondition", "Package is not eligible for rollback.");
  }
  const uploader = sourcePackage.uploadedByUid;
  // A new Trip owner or Admin can act for the uploader, but cannot bypass identity.
  if (file && (file.tripId !== input.tripId || file.packageId !== input.packageId ||
      file.storagePath !== storagePath(input) || file.uploadedByUid !== uploader)) {
    throw new HttpsError("failed-precondition", "Source file identity does not match.");
  }
  return uploader;
}

export function requireObject(
  object: SourceObject | null, input: CleanupInput, uploader: string,
): void {
  if (!object) return;
  if (object.metadata.packageId !== input.packageId ||
      object.metadata.uploadedByUid !== uploader ||
      !/^\d+$/.test(object.generation) || !/^\d+$/.test(object.metageneration)) {
    throw new HttpsError("failed-precondition", "Storage object identity does not match.");
  }
}
