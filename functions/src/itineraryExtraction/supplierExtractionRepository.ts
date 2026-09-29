import {
  StagedDay,
  StagedReviewIssue,
  SupplierExtractionFact,
  SupplierExtractionSnapshot,
} from "./supplierExtractionSnapshot";
import {SupplierExtractionSnapshotError} from
  "./supplierExtractionValidation";
import {parseStoredSupplierExtractionSnapshot} from
  "./supplierExtractionStoredValidation";
import {
  TrustedSupplierSourcePackage,
  validSourceIdentity,
} from "./sourceReaderValidation";

export type SupplierExtractionPersistenceState = "writing" | "complete";

export type SupplierExtractionPersistenceErrorCode =
  "INVALID_SUPPLIER_EXTRACTION" |
  "SUPPLIER_EXTRACTION_PERSISTENCE_FAILED" |
  "SUPPLIER_EXTRACTION_UNAVAILABLE" |
  "INVALID_STORED_SUPPLIER_EXTRACTION" |
  "INVALID_SUPPLIER_EXTRACTION_STATE" |
  "INCOMPLETE_SUPPLIER_EXTRACTION" |
  "SUPPLIER_EXTRACTION_JOB_STATE_MISMATCH" |
  "SUPPLIER_EXTRACTION_JOB_CONTRACT_MISMATCH" |
  "SUPPLIER_EXTRACTION_RELATIONSHIP_MISMATCH" |
  "SUPPLIER_EXTRACTION_FINALIZATION_FAILED";

export class SupplierExtractionPersistenceError extends Error {
  constructor(
    readonly code: SupplierExtractionPersistenceErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "SupplierExtractionPersistenceError";
  }
}

export interface SupplierExtractionRootRecord {
  persistenceState: SupplierExtractionPersistenceState;
  schemaVersion: SupplierExtractionSnapshot["schemaVersion"];
  extractionId: string;
  tripId: string;
  sourcePackageId: string;
  jobId: string;
  requestedByUid: string;
  createdAt: string;
  providerVersion: string | null;
  title: SupplierExtractionSnapshot["title"];
  counts: SupplierExtractionSnapshot["counts"];
}

export interface SupplierExtractionChildRecord<T> {
  documentId: string;
  snapshotOrder: number;
  value: T;
}

export interface SupplierExtractionPersistenceRecords {
  root: SupplierExtractionRootRecord;
  days: readonly SupplierExtractionChildRecord<StagedDay>[];
  facts: readonly SupplierExtractionChildRecord<SupplierExtractionFact>[];
  reviewIssues: readonly SupplierExtractionChildRecord<StagedReviewIssue>[];
}

export interface SupplierExtractionRepositoryStore {
  loadTrustedPackage(
    tripId: string,
    sourcePackageId: string,
  ): Promise<TrustedSupplierSourcePackage>;
  beginSnapshot(
    records: SupplierExtractionPersistenceRecords,
    trustedPackage: TrustedSupplierSourcePackage,
  ): Promise<SupplierExtractionPersistenceState>;
  writeSnapshotChildren(
    records: SupplierExtractionPersistenceRecords,
  ): Promise<void>;
  finalizeSnapshot(
    records: SupplierExtractionPersistenceRecords,
    trustedPackage: TrustedSupplierSourcePackage,
  ): Promise<"completed" | "already_completed">;
  inspectFinalization(
    records: SupplierExtractionPersistenceRecords,
    trustedPackage: TrustedSupplierSourcePackage,
  ): Promise<SupplierExtractionFinalizationInspection>;
  readSnapshot(
    tripId: string,
    extractionId: string,
  ): Promise<SupplierExtractionPersistenceRecords | null>;
}

export type SupplierExtractionFinalizationInspection =
  "complete_completed" |
  "eligible_for_failure" |
  "inconsistent";

export interface SupplierExtractionWriteResult {
  extractionId: string;
}

export interface SupplierExtractionWriteInput {
  tripId: string;
  extractionId: string;
  snapshot: unknown;
}

export async function writeSupplierExtractionSnapshot(
  input: SupplierExtractionWriteInput,
  store: SupplierExtractionRepositoryStore,
): Promise<SupplierExtractionWriteResult> {
  requireIdentity(input.tripId, "Trip");
  requireIdentity(input.extractionId, "Supplier extraction");
  const identities = snapshotIdentities(input.snapshot);
  if (identities.tripId !== input.tripId ||
      identities.extractionId !== input.extractionId ||
      identities.extractionId !== supplierExtractionIdForJob(
        identities.jobId,
      )) {
    throw invalid("Snapshot path identities are inconsistent.");
  }
  try {
    const trustedPackage = await store.loadTrustedPackage(
      identities.tripId,
      identities.sourcePackageId,
    );
    const snapshot = parseStoredSupplierExtractionSnapshot(
      input.snapshot,
      trustedPackage,
    );
    const records = serializeSupplierExtractionForPersistence(snapshot);
    const state = await store.beginSnapshot(records, trustedPackage);
    if (state === "writing") {
      await store.writeSnapshotChildren(records);
    }
    await store.finalizeSnapshot(records, trustedPackage);
    return {extractionId: snapshot.extractionId};
  } catch (error) {
    if (error instanceof SupplierExtractionPersistenceError) throw error;
    if (error instanceof SupplierExtractionSnapshotError) {
      throw invalid(error.message);
    }
    throw new SupplierExtractionPersistenceError(
      "SUPPLIER_EXTRACTION_PERSISTENCE_FAILED",
      "Validated Supplier Extraction Snapshot could not be persisted.",
    );
  }
}

/** One server-created extraction job owns one stable Snapshot identity. */
export function supplierExtractionIdForJob(jobId: string): string {
  return requireIdentity(jobId, "Extraction job");
}

export async function readSupplierExtractionSnapshot(
  tripId: string,
  extractionId: string,
  store: SupplierExtractionRepositoryStore,
): Promise<SupplierExtractionSnapshot> {
  requireIdentity(tripId, "Trip");
  requireIdentity(extractionId, "Supplier extraction");
  let records: SupplierExtractionPersistenceRecords | null;
  try {
    records = await store.readSnapshot(tripId, extractionId);
  } catch (error) {
    if (error instanceof SupplierExtractionPersistenceError) throw error;
    throw unavailable();
  }
  if (records === null) throw unavailable();
  try {
    const reconstructed = reconstructStoredSnapshot(
      records,
      tripId,
      extractionId,
    );
    const trustedPackage = await store.loadTrustedPackage(
      tripId,
      reconstructed.sourcePackageId,
    );
    return parseStoredSupplierExtractionSnapshot(reconstructed, trustedPackage);
  } catch (error) {
    if (error instanceof SupplierExtractionPersistenceError) throw error;
    if (error instanceof SupplierExtractionSnapshotError) {
      throw new SupplierExtractionPersistenceError(
        "INVALID_STORED_SUPPLIER_EXTRACTION",
        "Stored Supplier Extraction Snapshot is malformed.",
      );
    }
    throw unavailable();
  }
}

export function serializeSupplierExtractionForPersistence(
  snapshot: SupplierExtractionSnapshot,
): SupplierExtractionPersistenceRecords {
  return {
    root: {
      persistenceState: "writing",
      schemaVersion: snapshot.schemaVersion,
      extractionId: snapshot.extractionId,
      tripId: snapshot.tripId,
      sourcePackageId: snapshot.sourcePackageId,
      jobId: snapshot.jobId,
      requestedByUid: snapshot.requestedByUid,
      createdAt: snapshot.createdAt,
      providerVersion: snapshot.providerVersion,
      title: snapshot.title,
      counts: snapshot.counts,
    },
    days: childRecords(snapshot.days),
    facts: childRecords(snapshot.facts),
    reviewIssues: childRecords(snapshot.reviewIssues),
  };
}

function childRecords<T extends {id: string}>(
  values: readonly T[],
): readonly SupplierExtractionChildRecord<T>[] {
  return values.map((value, index) => ({
    documentId: value.id,
    snapshotOrder: index + 1,
    value,
  }));
}

function reconstructStoredSnapshot(
  records: SupplierExtractionPersistenceRecords,
  tripId: string,
  extractionId: string,
): SupplierExtractionSnapshot {
  const root = exactRoot(records.root);
  if (root.persistenceState !== "complete") {
    throw new SupplierExtractionPersistenceError(
      "SUPPLIER_EXTRACTION_UNAVAILABLE",
      "Supplier Extraction Snapshot is not complete.",
    );
  }
  if (root.tripId !== tripId || root.extractionId !== extractionId) {
    throw malformed();
  }
  return {
    schemaVersion: root.schemaVersion,
    extractionId: root.extractionId,
    tripId: root.tripId,
    sourcePackageId: root.sourcePackageId,
    jobId: root.jobId,
    requestedByUid: root.requestedByUid,
    createdAt: root.createdAt,
    providerVersion: root.providerVersion,
    title: root.title,
    days: orderedValues(records.days, "staged days"),
    facts: orderedValues(records.facts, "staged facts"),
    reviewIssues: orderedValues(records.reviewIssues, "review issues"),
    counts: root.counts,
  };
}

export function validateSupplierExtractionForFinalization(
  records: SupplierExtractionPersistenceRecords,
  trustedPackage: TrustedSupplierSourcePackage,
): SupplierExtractionSnapshot {
  const root = exactRoot(records.root);
  if (root.persistenceState !== "writing") {
    throw new SupplierExtractionPersistenceError(
      "INVALID_SUPPLIER_EXTRACTION_STATE",
      "Supplier Extraction Snapshot is not awaiting finalization.",
    );
  }
  requireExpectedChildCounts(records, root);
  try {
    return parseStoredSupplierExtractionSnapshot({
      schemaVersion: root.schemaVersion,
      extractionId: root.extractionId,
      tripId: root.tripId,
      sourcePackageId: root.sourcePackageId,
      jobId: root.jobId,
      requestedByUid: root.requestedByUid,
      createdAt: root.createdAt,
      providerVersion: root.providerVersion,
      title: root.title,
      days: orderedValues(records.days, "staged days"),
      facts: orderedValues(records.facts, "staged facts"),
      reviewIssues: orderedValues(records.reviewIssues, "review issues"),
      counts: root.counts,
    }, trustedPackage);
  } catch (error) {
    if (error instanceof SupplierExtractionPersistenceError) throw error;
    if (error instanceof SupplierExtractionSnapshotError) throw malformed();
    throw error;
  }
}

function requireExpectedChildCounts(
  records: SupplierExtractionPersistenceRecords,
  root: SupplierExtractionRootRecord,
): void {
  const expectedFacts = root.counts.assignedServices +
    root.counts.unassignedServices + root.counts.packageFacts +
    root.counts.ancillaryFlights + root.counts.ancillaryVisas +
    root.counts.commercialIndicators;
  const actual = [
    [records.days.length, root.counts.days],
    [records.facts.length, expectedFacts],
    [records.reviewIssues.length, root.counts.reviewIssues],
  ] as const;
  if (actual.some(([count, expected]) => count < expected)) {
    throw new SupplierExtractionPersistenceError(
      "INCOMPLETE_SUPPLIER_EXTRACTION",
      "Supplier Extraction Snapshot children are incomplete.",
    );
  }
  if (actual.some(([count, expected]) => count !== expected)) throw malformed();
}

function exactRoot(input: unknown): SupplierExtractionRootRecord {
  const data = record(input, "Stored extraction root");
  const fields = [
    "persistenceState", "schemaVersion", "extractionId", "tripId",
    "sourcePackageId", "jobId", "requestedByUid", "createdAt",
    "providerVersion", "title", "counts",
  ];
  exactKeys(data, fields, "Stored extraction root");
  if (data.persistenceState !== "writing" && data.persistenceState !== "complete") {
    throw malformed();
  }
  return data as unknown as SupplierExtractionRootRecord;
}

function orderedValues<T extends {id: string}>(
  inputs: readonly SupplierExtractionChildRecord<T>[],
  label: string,
): readonly T[] {
  if (!Array.isArray(inputs)) throw malformed();
  const values = [...inputs].sort((left, right) =>
    left.snapshotOrder - right.snapshotOrder);
  values.forEach((entry, index) => {
    const data = record(entry, `Stored ${label} envelope`);
    exactKeys(
      data,
      ["documentId", "snapshotOrder", "value"],
      `Stored ${label} envelope`,
    );
    if (!Number.isSafeInteger(entry.snapshotOrder) ||
        entry.snapshotOrder !== index + 1 ||
        !entry.value || typeof entry.value !== "object" ||
        entry.documentId !== entry.value.id) {
      throw malformed();
    }
  });
  return values.map((entry) => entry.value);
}

function snapshotIdentities(input: unknown): {
  extractionId: string;
  tripId: string;
  sourcePackageId: string;
  jobId: string;
} {
  const data = record(input, "Supplier Extraction Snapshot");
  return {
    extractionId: requireIdentity(data.extractionId, "Supplier extraction"),
    tripId: requireIdentity(data.tripId, "Trip"),
    sourcePackageId: requireIdentity(
      data.sourcePackageId,
      "Supplier Source package",
    ),
    jobId: requireIdentity(data.jobId, "Extraction job"),
  };
}

function record(input: unknown, label: string): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw invalid(`${label} must be an object.`);
  }
  return input as Record<string, unknown>;
}

function exactKeys(
  data: Record<string, unknown>,
  fields: readonly string[],
  label: string,
): void {
  const keys = Object.keys(data);
  if (keys.length !== fields.length ||
      fields.some((field) => !Object.prototype.hasOwnProperty.call(data, field)) ||
      keys.some((key) => !fields.includes(key))) {
    throw new SupplierExtractionPersistenceError(
      "INVALID_STORED_SUPPLIER_EXTRACTION",
      `${label} fields are invalid.`,
    );
  }
}

function requireIdentity(input: unknown, label: string): string {
  if (!validSourceIdentity(input)) {
    throw invalid(`${label} identity is invalid.`);
  }
  return input;
}

function invalid(message: string): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "INVALID_SUPPLIER_EXTRACTION",
    message,
  );
}

function malformed(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "INVALID_STORED_SUPPLIER_EXTRACTION",
    "Stored Supplier Extraction Snapshot is malformed.",
  );
}

function unavailable(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "SUPPLIER_EXTRACTION_UNAVAILABLE",
    "Supplier Extraction Snapshot is unavailable.",
  );
}
