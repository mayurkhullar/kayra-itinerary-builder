import {Timestamp} from "firebase-admin/firestore";
import {
  DraftBoundaryError,
  DraftRecord,
  ValidatedDraftPayload,
  validateDraftPayload,
} from "./draftValidation";
import {TrustedSupplierSourcePackage} from "./sourceReaderValidation";

export interface DraftWriteInput {
  tripId: string;
  sourcePackageId: string;
  requestedByUid: string;
  extractedPayload: unknown;
  trustedPackage: TrustedSupplierSourcePackage;
}

export interface DraftWriterDependencies {
  createDraft(
    tripId: string,
    data: DraftCreateData,
  ): Promise<string>;
}

export interface DraftCreateData extends DraftRecord {
  tripId: string;
  title: string;
  days: unknown;
  sourcePackageIds: readonly string[];
  reviewIssues: unknown;
  createdByUid: string;
}

export interface DraftWriteResult {
  draftId: string;
}

export async function writeTrustedItineraryDraft(
  input: DraftWriteInput,
  dependencies: DraftWriterDependencies,
): Promise<DraftWriteResult> {
  validateBackendInput(input);
  const validated = validateDraftPayload(
    input.extractedPayload,
    input.trustedPackage,
  );
  const data = draftData(input, validated);
  try {
    const draftId = await dependencies.createDraft(input.tripId, data);
    return {draftId};
  } catch (error) {
    if (error instanceof DraftBoundaryError) throw error;
    throw new DraftBoundaryError(
      "DRAFT_PERSISTENCE_FAILED",
      "Validated itinerary draft could not be persisted.",
    );
  }
}

function validateBackendInput(input: DraftWriteInput): void {
  requiredId(input.tripId, "Trip");
  requiredId(input.sourcePackageId, "Supplier Source package");
  requiredId(input.requestedByUid, "Draft creator");
  if (input.trustedPackage.tripId !== input.tripId ||
      input.trustedPackage.packageId !== input.sourcePackageId ||
      input.trustedPackage.files.length === 0) {
    throw new DraftBoundaryError(
      "INVALID_EXTRACTION_RESULT",
      "Trusted Supplier Source package does not match the draft request.",
    );
  }
}

function draftData(
  input: DraftWriteInput,
  payload: ValidatedDraftPayload,
): DraftCreateData {
  return {
    tripId: input.tripId,
    title: payload.title,
    days: firestoreValue(payload.days),
    sourcePackageIds: [input.sourcePackageId],
    reviewIssues: firestoreValue(payload.reviewIssues),
    createdByUid: input.requestedByUid,
  };
}

function firestoreValue(value: unknown): unknown {
  if (value instanceof Date) return Timestamp.fromDate(value);
  if (Array.isArray(value)) return value.map(firestoreValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [key, firestoreValue(nested)]),
    );
  }
  return value;
}

function requiredId(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.trim() !== value || value.includes("/") ||
      value === "." || value === "..") {
    throw new DraftBoundaryError(
      "INVALID_EXTRACTION_RESULT",
      `${label} identity is invalid.`,
    );
  }
  return value;
}
