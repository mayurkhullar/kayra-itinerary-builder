import {HttpsError} from "firebase-functions/v2/https";

export interface ExtractionRequestInput {
  tripId: string;
  sourcePackageId: string;
}

export interface ExtractionRequestAuth {
  uid: string;
  token: {email?: unknown};
}

export type RecordData = Record<string, unknown>;

export interface ExtractionRequestContext {
  profile: RecordData | null;
  trip: RecordData | null;
  sourcePackage: RecordData | null;
}

function validSegment(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 &&
    value.trim() === value && !/[\/\\\u0000-\u001f\u007f]/.test(value) &&
    value !== "." && value !== "..";
}

export function requireExtractionAuth(
  auth: ExtractionRequestAuth | undefined,
): string {
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Sign in to request itinerary extraction.",
    );
  }
  const email = auth.token.email;
  if (typeof email !== "string" ||
      !/^[^@\s]+@kholidaymaps\.com$/.test(email.trim().toLowerCase())) {
    throw new HttpsError(
      "permission-denied",
      "A Kayra company account is required.",
    );
  }
  if (!validSegment(auth.uid)) {
    throw new HttpsError("unauthenticated", "Invalid authenticated identity.");
  }
  return auth.uid;
}

export function parseExtractionRequestInput(
  data: unknown,
): ExtractionRequestInput {
  const keys = ["tripId", "sourcePackageId"];
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError(
      "invalid-argument",
      "Trip and source package identifiers are required.",
    );
  }
  const record = data as RecordData;
  if (Object.keys(record).length !== keys.length ||
      !keys.every((key) => validSegment(record[key]))) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid Trip or source package identifier.",
    );
  }
  return {
    tripId: record.tripId as string,
    sourcePackageId: record.sourcePackageId as string,
  };
}

export function requireExtractionContext(
  context: ExtractionRequestContext,
  uid: string,
  input: ExtractionRequestInput,
): void {
  const {profile, trip, sourcePackage} = context;
  if (!profile || profile.status !== "active" ||
      (profile.role !== "agent" && profile.role !== "admin")) {
    throw new HttpsError(
      "permission-denied",
      "An active Kayra profile is required.",
    );
  }
  if (!trip) throw new HttpsError("not-found", "Trip does not exist.");
  if (profile.role !== "admin" && trip.ownerUid !== uid) {
    throw new HttpsError(
      "permission-denied",
      "You cannot manage this Trip.",
    );
  }
  if (!sourcePackage) {
    throw new HttpsError("not-found", "Source package does not exist.");
  }
  if (sourcePackage.tripId !== input.tripId) {
    throw new HttpsError(
      "failed-precondition",
      "Source package does not belong to this Trip.",
    );
  }
  if (sourcePackage.status !== "uploaded") {
    throw new HttpsError(
      "failed-precondition",
      "Source package is not ready for extraction.",
    );
  }
  if (!Array.isArray(sourcePackage.fileIds) ||
      sourcePackage.fileIds.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "Uploaded source package has no files.",
    );
  }
}
