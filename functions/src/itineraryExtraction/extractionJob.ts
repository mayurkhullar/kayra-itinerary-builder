import {validSourceIdentity} from "./sourceReaderValidation";

export const itineraryDraftExtractionContractVersion =
  "itinerary_draft_v1" as const;
export const supplierExtractionContractVersion =
  "supplier_extraction_v1" as const;

export type ExtractionContractVersion =
  typeof itineraryDraftExtractionContractVersion |
  typeof supplierExtractionContractVersion;

export type ExtractionJobResultType =
  "itinerary_draft" | "supplier_extraction";

export type ExtractionJobStatus =
  "queued" | "processing" | "completed" | "failed";

export type ExtractionJobFailureCode =
  "source_unavailable" |
  "unsupported_source" |
  "extraction_failed" |
  "invalid_extraction_result" |
  "draft_persistence_failed" |
  "supplier_extraction_persistence_failed";

export type ExtractionJobPersistenceShape = "legacy" | "versioned";

export interface ExtractionJobRecord {
  persistenceShape: ExtractionJobPersistenceShape;
  tripId: string;
  sourcePackageId: string;
  status: ExtractionJobStatus;
  requestedByUid: string;
  extractionContractVersion: ExtractionContractVersion;
  resultType: ExtractionJobResultType;
  resultingDraftId: string | null;
  resultingExtractionId: string | null;
  failureCode: ExtractionJobFailureCode | null;
  createdAt: unknown;
  updatedAt: unknown;
}

export interface ExtractionJobReadOptions {
  isTimestamp?: (value: unknown) => boolean;
}

export interface QueuedExtractionJobInput {
  tripId: string;
  sourcePackageId: string;
  requestedByUid: string;
  createdAt: unknown;
  updatedAt: unknown;
}

const legacyJobFields = [
  "tripId",
  "sourcePackageId",
  "status",
  "requestedByUid",
  "resultingDraftId",
  "failureCode",
  "createdAt",
  "updatedAt",
] as const;

const versionedJobFields = [
  ...legacyJobFields,
  "extractionContractVersion",
  "resultType",
  "resultingExtractionId",
] as const;

const genericFailureCodes = new Set<ExtractionJobFailureCode>([
  "source_unavailable",
  "unsupported_source",
  "extraction_failed",
  "invalid_extraction_result",
]);

export function resultTypeForExtractionContract(
  contract: ExtractionContractVersion,
): ExtractionJobResultType {
  switch (contract) {
    case itineraryDraftExtractionContractVersion:
      return "itinerary_draft";
    case supplierExtractionContractVersion:
      return "supplier_extraction";
    default:
      throw invalidJob();
  }
}

export function parseExtractionJobRecord(
  input: unknown,
  options: ExtractionJobReadOptions = {},
): ExtractionJobRecord {
  const data = record(input);
  const persistenceShape = jobPersistenceShape(data);
  exactFields(
    data,
    persistenceShape === "legacy" ? legacyJobFields : versionedJobFields,
  );

  const tripId = identity(data.tripId, "Trip");
  const sourcePackageId = identity(
    data.sourcePackageId,
    "Supplier Source package",
  );
  const requestedByUid = identity(data.requestedByUid, "Requester");
  const status = extractionStatus(data.status);
  const createdAt = timestamp(data.createdAt, options);
  const updatedAt = timestamp(data.updatedAt, options);

  const extractionContractVersion = persistenceShape === "legacy" ?
    itineraryDraftExtractionContractVersion : contractVersion(
      data.extractionContractVersion,
    );
  const resultType = persistenceShape === "legacy" ?
    "itinerary_draft" : parseResultType(data.resultType);
  if (resultType !== resultTypeForExtractionContract(
    extractionContractVersion,
  )) {
    throw invalidJob();
  }

  const resultingDraftId = nullableIdentity(data.resultingDraftId);
  const resultingExtractionId = persistenceShape === "legacy" ?
    null : nullableIdentity(data.resultingExtractionId);
  const failureCode = nullableFailureCode(data.failureCode);
  const parsed: ExtractionJobRecord = {
    persistenceShape,
    tripId,
    sourcePackageId,
    status,
    requestedByUid,
    extractionContractVersion,
    resultType,
    resultingDraftId,
    resultingExtractionId,
    failureCode,
    createdAt,
    updatedAt,
  };
  validateOutcome(parsed);
  return Object.freeze(parsed);
}

export function legacyQueuedExtractionJobData(
  input: QueuedExtractionJobInput,
): Record<string, unknown> {
  validateQueuedInput(input);
  return {
    tripId: input.tripId,
    sourcePackageId: input.sourcePackageId,
    status: "queued",
    requestedByUid: input.requestedByUid,
    resultingDraftId: null,
    failureCode: null,
    createdAt: input.createdAt,
    updatedAt: input.updatedAt,
  };
}

export function versionedQueuedExtractionJobData(
  input: QueuedExtractionJobInput,
  extractionContractVersion: ExtractionContractVersion,
): Record<string, unknown> {
  validateQueuedInput(input);
  return {
    tripId: input.tripId,
    sourcePackageId: input.sourcePackageId,
    status: "queued",
    requestedByUid: input.requestedByUid,
    resultingDraftId: null,
    failureCode: null,
    createdAt: input.createdAt,
    updatedAt: input.updatedAt,
    extractionContractVersion,
    resultType: resultTypeForExtractionContract(extractionContractVersion),
    resultingExtractionId: null,
  };
}

export function processingExtractionJobUpdate(
  job: ExtractionJobRecord,
): Record<string, unknown> {
  requireStatus(job, "queued");
  return outcomeUpdate(job, {
    status: "processing",
    resultingDraftId: null,
    resultingExtractionId: null,
    failureCode: null,
  });
}

export function failedExtractionJobUpdate(
  job: ExtractionJobRecord,
  failureCode: ExtractionJobFailureCode,
): Record<string, unknown> {
  requireStatus(job, "processing");
  validateFailureForContract(
    failureCode,
    job.extractionContractVersion,
    job.persistenceShape,
  );
  return outcomeUpdate(job, {
    status: "failed",
    resultingDraftId: null,
    resultingExtractionId: null,
    failureCode,
  });
}

export function completedDraftJobUpdate(
  job: ExtractionJobRecord,
  resultingDraftId: string,
): Record<string, unknown> {
  requireStatus(job, "processing");
  if (job.extractionContractVersion !==
      itineraryDraftExtractionContractVersion ||
      job.resultType !== "itinerary_draft") {
    throw invalidJob();
  }
  return outcomeUpdate(job, {
    status: "completed",
    resultingDraftId: identity(resultingDraftId, "Itinerary draft"),
    resultingExtractionId: null,
    failureCode: null,
  });
}

export function completedSupplierExtractionJobUpdate(
  job: ExtractionJobRecord,
  resultingExtractionId: string,
): Record<string, unknown> {
  requireStatus(job, "processing");
  if (job.persistenceShape !== "versioned" ||
      job.extractionContractVersion !== supplierExtractionContractVersion ||
      job.resultType !== "supplier_extraction") {
    throw invalidJob();
  }
  return outcomeUpdate(job, {
    status: "completed",
    resultingDraftId: null,
    resultingExtractionId: identity(
      resultingExtractionId,
      "Supplier extraction",
    ),
    failureCode: null,
  });
}

function validateOutcome(job: ExtractionJobRecord): void {
  switch (job.status) {
    case "queued":
    case "processing":
      if (job.resultingDraftId !== null ||
          job.resultingExtractionId !== null ||
          job.failureCode !== null) {
        throw invalidJob();
      }
      return;
    case "completed":
      if (job.failureCode !== null) throw invalidJob();
      if (job.resultType === "itinerary_draft") {
        if (job.resultingDraftId === null ||
            job.resultingExtractionId !== null) {
          throw invalidJob();
        }
      } else if (job.resultingExtractionId === null ||
          job.resultingDraftId !== null) {
        throw invalidJob();
      }
      return;
    case "failed":
      if (job.resultingDraftId !== null ||
          job.resultingExtractionId !== null ||
          job.failureCode === null) {
        throw invalidJob();
      }
      validateFailureForContract(
        job.failureCode,
        job.extractionContractVersion,
        job.persistenceShape,
      );
  }
}

function validateFailureForContract(
  failureCode: ExtractionJobFailureCode,
  contract: ExtractionContractVersion,
  persistenceShape: ExtractionJobPersistenceShape,
): void {
  if (genericFailureCodes.has(failureCode)) return;
  if (failureCode === "draft_persistence_failed" &&
      contract === itineraryDraftExtractionContractVersion) {
    return;
  }
  if (failureCode === "supplier_extraction_persistence_failed" &&
      persistenceShape === "versioned" &&
      contract === supplierExtractionContractVersion) {
    return;
  }
  throw invalidJob();
}

function outcomeUpdate(
  job: ExtractionJobRecord,
  outcome: {
    status: ExtractionJobStatus;
    resultingDraftId: string | null;
    resultingExtractionId: string | null;
    failureCode: ExtractionJobFailureCode | null;
  },
): Record<string, unknown> {
  const update: Record<string, unknown> = {
    status: outcome.status,
    resultingDraftId: outcome.resultingDraftId,
    failureCode: outcome.failureCode,
  };
  if (job.persistenceShape === "versioned") {
    update.resultingExtractionId = outcome.resultingExtractionId;
  } else if (outcome.resultingExtractionId !== null) {
    throw invalidJob();
  }
  return update;
}

function jobPersistenceShape(
  data: Record<string, unknown>,
): ExtractionJobPersistenceShape {
  const newFields = [
    "extractionContractVersion",
    "resultType",
    "resultingExtractionId",
  ];
  const present = newFields.filter((field) =>
    Object.prototype.hasOwnProperty.call(data, field)).length;
  if (present === 0) return "legacy";
  if (present === newFields.length) return "versioned";
  throw invalidJob();
}

function exactFields(
  data: Record<string, unknown>,
  fields: readonly string[],
): void {
  const keys = Object.keys(data);
  if (keys.length !== fields.length ||
      fields.some((field) =>
        !Object.prototype.hasOwnProperty.call(data, field)) ||
      keys.some((key) => !fields.includes(key))) {
    throw invalidJob();
  }
}

function validateQueuedInput(input: QueuedExtractionJobInput): void {
  identity(input.tripId, "Trip");
  identity(input.sourcePackageId, "Supplier Source package");
  identity(input.requestedByUid, "Requester");
  if (input.createdAt === undefined || input.updatedAt === undefined) {
    throw invalidJob();
  }
}

function requireStatus(
  job: ExtractionJobRecord,
  expected: ExtractionJobStatus,
): void {
  if (job.status !== expected) throw invalidJob();
}

function record(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw invalidJob();
  }
  return input as Record<string, unknown>;
}

function identity(input: unknown, _label: string): string {
  if (!validSourceIdentity(input)) throw invalidJob();
  return input;
}

function nullableIdentity(input: unknown): string | null {
  if (input === null) return null;
  return identity(input, "Result");
}

function timestamp(
  input: unknown,
  options: ExtractionJobReadOptions,
): unknown {
  if (options.isTimestamp && !options.isTimestamp(input)) throw invalidJob();
  if (input === undefined || input === null) throw invalidJob();
  return input;
}

function extractionStatus(input: unknown): ExtractionJobStatus {
  if (input === "queued" || input === "processing" ||
      input === "completed" || input === "failed") {
    return input;
  }
  throw invalidJob();
}

function contractVersion(input: unknown): ExtractionContractVersion {
  if (input === itineraryDraftExtractionContractVersion ||
      input === supplierExtractionContractVersion) {
    return input;
  }
  throw invalidJob();
}

function parseResultType(input: unknown): ExtractionJobResultType {
  if (input === "itinerary_draft" || input === "supplier_extraction") {
    return input;
  }
  throw invalidJob();
}

function nullableFailureCode(input: unknown): ExtractionJobFailureCode | null {
  if (input === null) return null;
  if (input === "source_unavailable" || input === "unsupported_source" ||
      input === "extraction_failed" ||
      input === "invalid_extraction_result" ||
      input === "draft_persistence_failed" ||
      input === "supplier_extraction_persistence_failed") {
    return input;
  }
  throw invalidJob();
}

function invalidJob(): Error {
  return new Error("Itinerary extraction job data is invalid.");
}
