import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {
  SupplierExtractionChildRecord,
  SupplierExtractionPersistenceError,
  SupplierExtractionPersistenceRecords,
  SupplierExtractionRootRecord,
  SupplierExtractionRepositoryStore,
  validateSupplierExtractionForFinalization,
} from "./supplierExtractionRepository";
import {
  completedSupplierExtractionJobUpdate,
  ExtractionJobRecord,
  parseExtractionJobRecord,
  supplierExtractionContractVersion,
} from "./extractionJob";
import {
  TrustedSupplierSourcePackage,
  validateSourceFile,
  validateSourcePackage,
} from "./sourceReaderValidation";

const childBatchSize = 450;

interface FirestoreReader {
  get(reference: DocumentReference): Promise<DocumentSnapshot>;
  getAll(...references: DocumentReference[]): Promise<DocumentSnapshot[]>;
}

export function adminSupplierExtractionRepositoryStore(
  db: Firestore,
): SupplierExtractionRepositoryStore {
  return {
    loadTrustedPackage: (tripId, sourcePackageId) =>
      loadTrustedPackage(db, {
        get: (reference) => reference.get(),
        getAll: (...references) => db.getAll(...references),
      }, tripId, sourcePackageId),

    async beginSnapshot(records, trustedPackage) {
      const root = records.root;
      const rootReference = extractionDocument(
        db,
        root.tripId,
        root.extractionId,
      );
      const jobReference = extractionJobDocument(db, root.tripId, root.jobId);
      return db.runTransaction(async (transaction) => {
        const currentPackage = await loadTrustedPackage(
          db,
          transaction,
          root.tripId,
          root.sourcePackageId,
        );
        requireSameTrustedPackage(trustedPackage, currentPackage);
        const [rootSnapshot, jobSnapshot] = await transaction.getAll(
          rootReference,
          jobReference,
        );
        const job = storedExtractionJob(jobSnapshot);
        if (rootSnapshot.exists) {
          const storedRoot = requireMatchingRoot(
            rootSnapshot,
            root,
            ["writing", "complete"],
          );
          if (storedRoot.persistenceState === "complete") {
            requireCompletedPair(storedRoot, job, jobReference.id);
          } else {
            requireProcessingSupplierJob(storedRoot, job, jobReference.id);
          }
          return storedRoot.persistenceState;
        }
        requireProcessingSupplierJob(root, job, jobReference.id);
        transaction.create(rootReference, rootForFirestore(root));
        return "writing";
      });
    },

    async writeSnapshotChildren(records) {
      const root = records.root;
      const rootReference = extractionDocument(
        db,
        root.tripId,
        root.extractionId,
      );
      const jobReference = extractionJobDocument(db, root.tripId, root.jobId);
      const children = [
        ...childWrites(rootReference, "days", records.days),
        ...childWrites(rootReference, "facts", records.facts),
        ...childWrites(rootReference, "review_issues", records.reviewIssues),
      ];
      for (let offset = 0; offset < children.length; offset += childBatchSize) {
        const group = children.slice(offset, offset + childBatchSize);
        await db.runTransaction(async (transaction) => {
          const snapshots = await transaction.getAll(
            rootReference,
            jobReference,
            ...group.map((child) => child.reference),
          );
          const storedRoot = requireMatchingRoot(snapshots[0], root, ["writing"]);
          const job = storedExtractionJob(snapshots[1]);
          requireProcessingSupplierJob(storedRoot, job, jobReference.id);
          group.forEach((child, index) => {
            const snapshot = snapshots[index + 2];
            if (!snapshot.exists) {
              transaction.create(child.reference, child.data);
            } else if (!sameJsonValue(snapshot.data(), child.data)) {
              throw invalidStoredChildren();
            }
          });
        });
      }
    },

    async finalizeSnapshot(records, trustedPackage) {
      try {
        return await finalizeSnapshotAndJob(db, records, trustedPackage);
      } catch (error) {
        if (error instanceof SupplierExtractionPersistenceError) throw error;
        throw finalizationFailure();
      }
    },

    async inspectFinalization(records, trustedPackage) {
      try {
        return await inspectSnapshotAndJob(db, records, trustedPackage);
      } catch (error) {
        if (error instanceof SupplierExtractionPersistenceError) {
          return "inconsistent";
        }
        throw finalizationFailure();
      }
    },

    async readSnapshot(tripId, extractionId) {
      const rootReference = extractionDocument(db, tripId, extractionId);
      const rootSnapshot = await rootReference.get();
      if (!rootSnapshot.exists) return null;
      const [days, facts, reviewIssues] = await Promise.all([
        readChildren(rootReference, "days"),
        readChildren(rootReference, "facts"),
        readChildren(rootReference, "review_issues"),
      ]);
      return {
        root: rootFromFirestore(rootSnapshot.data()),
        days,
        facts,
        reviewIssues,
      } as SupplierExtractionPersistenceRecords;
    },
  };
}

async function inspectSnapshotAndJob(
  db: Firestore,
  records: SupplierExtractionPersistenceRecords,
  trustedPackage: TrustedSupplierSourcePackage,
): Promise<"complete_completed" | "eligible_for_failure" | "inconsistent"> {
  const expectedRoot = records.root;
  const rootReference = extractionDocument(
    db,
    expectedRoot.tripId,
    expectedRoot.extractionId,
  );
  const jobReference = extractionJobDocument(
    db,
    expectedRoot.tripId,
    expectedRoot.jobId,
  );
  return db.runTransaction(async (transaction) => {
    const currentPackage = await loadTrustedPackage(
      db,
      transaction,
      expectedRoot.tripId,
      expectedRoot.sourcePackageId,
    );
    requireSameTrustedPackage(trustedPackage, currentPackage);
    const [rootSnapshot, jobSnapshot] = await transaction.getAll(
      rootReference,
      jobReference,
    );
    const job = storedExtractionJob(jobSnapshot);
    if (!rootSnapshot.exists) {
      requireProcessingSupplierJob(expectedRoot, job, jobReference.id);
      return "eligible_for_failure";
    }
    const root = requireMatchingRoot(
      rootSnapshot,
      expectedRoot,
      ["writing", "complete"],
    );
    if (root.persistenceState === "complete") {
      requireCompletedPair(root, job, jobReference.id);
      return "complete_completed";
    }
    requireProcessingSupplierJob(root, job, jobReference.id);
    return "eligible_for_failure";
  });
}

async function finalizeSnapshotAndJob(
  db: Firestore,
  records: SupplierExtractionPersistenceRecords,
  trustedPackage: TrustedSupplierSourcePackage,
): Promise<"completed" | "already_completed"> {
  const expectedRoot = records.root;
  const rootReference = extractionDocument(
    db,
    expectedRoot.tripId,
    expectedRoot.extractionId,
  );
  const jobReference = extractionJobDocument(
    db,
    expectedRoot.tripId,
    expectedRoot.jobId,
  );
  return db.runTransaction(async (transaction) => {
    const currentPackage = await loadTrustedPackage(
      db,
      transaction,
      expectedRoot.tripId,
      expectedRoot.sourcePackageId,
    );
    requireSameTrustedPackage(trustedPackage, currentPackage);
    const [rootSnapshot, jobSnapshot] = await transaction.getAll(
      rootReference,
      jobReference,
    );
    const root = requireMatchingRoot(
      rootSnapshot,
      expectedRoot,
      ["writing", "complete"],
    );
    const job = storedExtractionJob(jobSnapshot);
    if (root.persistenceState === "complete") {
      requireCompletedPair(root, job, jobReference.id);
      return "already_completed";
    }
    requireProcessingSupplierJob(root, job, jobReference.id);

    const [days, facts, reviewIssues] = await Promise.all([
      transaction.get(rootReference.collection("days").orderBy("snapshotOrder")),
      transaction.get(rootReference.collection("facts").orderBy("snapshotOrder")),
      transaction.get(
        rootReference.collection("review_issues").orderBy("snapshotOrder"),
      ),
    ]);
    validateSupplierExtractionForFinalization({
      root,
      days: childRecordsFromSnapshot(days.docs),
      facts: childRecordsFromSnapshot(facts.docs),
      reviewIssues: childRecordsFromSnapshot(reviewIssues.docs),
    }, currentPackage);

    transaction.update(rootReference, {persistenceState: "complete"});
    transaction.update(jobReference, {
      ...completedSupplierExtractionJobUpdate(job, root.extractionId),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "completed";
  });
}

async function loadTrustedPackage(
  db: Firestore,
  reader: FirestoreReader,
  tripId: string,
  sourcePackageId: string,
): Promise<TrustedSupplierSourcePackage> {
  const tripReference = db.doc(`trips/${tripId}`);
  const packageReference = tripReference.collection("supplier_source_packages")
    .doc(sourcePackageId);
  const tripSnapshot = await reader.get(tripReference);
  if (!tripSnapshot.exists) throw invalidRelationship("Parent Trip is unavailable.");
  const packageSnapshot = await reader.get(packageReference);
  if (!packageSnapshot.exists) {
    throw invalidRelationship("Supplier Source package is unavailable.");
  }
  let sourcePackage;
  try {
    sourcePackage = validateSourcePackage(
      packageSnapshot.data() ?? {},
      tripId,
      sourcePackageId,
    );
  } catch (_) {
    throw invalidRelationship("Supplier Source package relationship is invalid.");
  }
  const references = sourcePackage.fileIds.map((sourceFileId) => tripReference
    .collection("supplier_source_files").doc(sourceFileId));
  const snapshots = await reader.getAll(...references);
  if (snapshots.length !== references.length) {
    throw invalidRelationship("Supplier Source file metadata is unavailable.");
  }
  const files = snapshots.map((snapshot, index) => {
    if (!snapshot.exists) {
      throw invalidRelationship("Supplier Source file metadata is unavailable.");
    }
    try {
      return validateSourceFile(
        snapshot.data() ?? {},
        tripId,
        sourcePackageId,
        sourcePackage.fileIds[index],
        sourcePackage.uploadedByUid,
      );
    } catch (_) {
      throw invalidRelationship("Supplier Source file relationship is invalid.");
    }
  });
  return Object.freeze({
    tripId,
    packageId: sourcePackageId,
    supplierId: sourcePackage.supplierId,
    supplierNameSnapshot: sourcePackage.supplierNameSnapshot,
    files: Object.freeze(files),
  });
}

function requireSameTrustedPackage(
  expected: TrustedSupplierSourcePackage,
  current: TrustedSupplierSourcePackage,
): void {
  if (expected.tripId !== current.tripId || expected.packageId !== current.packageId ||
      expected.files.length !== current.files.length ||
      expected.files.some((file, index) =>
        file.sourceFileId !== current.files[index].sourceFileId)) {
    throw invalidRelationship("Supplier Source package changed before persistence.");
  }
}

function extractionDocument(
  db: Firestore,
  tripId: string,
  extractionId: string,
): DocumentReference {
  return db.doc(`trips/${tripId}/supplier_extractions/${extractionId}`);
}

function extractionJobDocument(
  db: Firestore,
  tripId: string,
  jobId: string,
): DocumentReference {
  return db.doc(`trips/${tripId}/itinerary_extraction_jobs/${jobId}`);
}

function rootForFirestore(
  root: SupplierExtractionPersistenceRecords["root"],
): Record<string, unknown> {
  const createdAt = new Date(root.createdAt);
  if (Number.isNaN(createdAt.getTime()) || createdAt.toISOString() !== root.createdAt) {
    throw invalidRelationship("Supplier Extraction creation time is invalid.");
  }
  return {
    ...root,
    createdAt: Timestamp.fromDate(createdAt),
  };
}

function rootFromFirestore(input: unknown): unknown {
  if (!input || typeof input !== "object" || Array.isArray(input)) return input;
  const data = {...input as Record<string, unknown>};
  if (data.createdAt instanceof Timestamp) {
    data.createdAt = data.createdAt.toDate().toISOString();
  }
  return data;
}

function requireMatchingRoot(
  snapshot: DocumentSnapshot,
  expected: SupplierExtractionRootRecord,
  allowedStates: readonly SupplierExtractionRootRecord["persistenceState"][],
): SupplierExtractionRootRecord {
  if (!snapshot.exists) throw invalidSnapshotState();
  const raw = rootFromFirestore(snapshot.data());
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw relationshipMismatch();
  }
  const actual = raw as Record<string, unknown>;
  if (!allowedStates.includes(
    actual.persistenceState as SupplierExtractionRootRecord["persistenceState"],
  )) {
    throw invalidSnapshotState();
  }
  const comparable = {...expected, persistenceState: actual.persistenceState};
  if (!sameJsonValue(actual, comparable)) throw relationshipMismatch();
  return actual as unknown as SupplierExtractionRootRecord;
}

function storedExtractionJob(snapshot: DocumentSnapshot): ExtractionJobRecord {
  if (!snapshot.exists) throw jobStateMismatch();
  try {
    return parseExtractionJobRecord(snapshot.data(), {
      isTimestamp: (value) => value instanceof Timestamp,
    });
  } catch (_) {
    throw jobStateMismatch();
  }
}

function requireSnapshotJobRelationship(
  root: SupplierExtractionRootRecord,
  job: ExtractionJobRecord,
  jobId: string,
): void {
  if (root.extractionId !== jobId || root.jobId !== jobId ||
      root.tripId !== job.tripId ||
      root.sourcePackageId !== job.sourcePackageId ||
      root.requestedByUid !== job.requestedByUid) {
    throw relationshipMismatch();
  }
}

function requireProcessingSupplierJob(
  root: SupplierExtractionRootRecord,
  job: ExtractionJobRecord,
  jobId: string,
): void {
  requireSnapshotJobRelationship(root, job, jobId);
  if (job.extractionContractVersion !== supplierExtractionContractVersion ||
      job.resultType !== "supplier_extraction" ||
      job.persistenceShape !== "versioned") {
    throw jobContractMismatch();
  }
  if (job.status !== "processing" || job.resultingDraftId !== null ||
      job.resultingExtractionId !== null || job.failureCode !== null) {
    throw jobStateMismatch();
  }
}

function requireCompletedPair(
  root: SupplierExtractionRootRecord,
  job: ExtractionJobRecord,
  jobId: string,
): void {
  requireSnapshotJobRelationship(root, job, jobId);
  if (job.extractionContractVersion !== supplierExtractionContractVersion ||
      job.resultType !== "supplier_extraction" ||
      job.persistenceShape !== "versioned") {
    throw jobContractMismatch();
  }
  if (job.status !== "completed" ||
      job.resultingExtractionId !== root.extractionId) {
    throw jobStateMismatch();
  }
}

function childWrites<T>(
  root: DocumentReference,
  collectionName: string,
  records: readonly SupplierExtractionChildRecord<T>[],
): readonly {reference: DocumentReference; data: Record<string, unknown>}[] {
  return records.map((record) => ({
    reference: root.collection(collectionName).doc(record.documentId),
    data: {
      snapshotOrder: record.snapshotOrder,
      value: record.value,
    },
  }));
}

async function readChildren(
  root: DocumentReference,
  collectionName: string,
): Promise<readonly SupplierExtractionChildRecord<never>[]> {
  const snapshot = await root.collection(collectionName)
    .orderBy("snapshotOrder").get();
  return snapshot.docs.map((document) => {
    const data = document.data();
    return {
      documentId: document.id,
      snapshotOrder: data.snapshotOrder,
      value: data.value,
    } as SupplierExtractionChildRecord<never>;
  });
}

function childRecordsFromSnapshot(
  documents: readonly DocumentSnapshot[],
): readonly SupplierExtractionChildRecord<never>[] {
  return documents.map((document) => {
    const data = document.data() ?? {};
    return {
      documentId: document.id,
      snapshotOrder: data.snapshotOrder,
      value: data.value,
    } as SupplierExtractionChildRecord<never>;
  });
}

function sameJsonValue(left: unknown, right: unknown): boolean {
  if (left === right) return true;
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left) && Array.isArray(right) &&
      left.length === right.length &&
      left.every((value, index) => sameJsonValue(value, right[index]));
  }
  if (!left || !right || typeof left !== "object" || typeof right !== "object") {
    return false;
  }
  const leftRecord = left as Record<string, unknown>;
  const rightRecord = right as Record<string, unknown>;
  const leftKeys = Object.keys(leftRecord).sort();
  const rightKeys = Object.keys(rightRecord).sort();
  return leftKeys.length === rightKeys.length &&
    leftKeys.every((key, index) => key === rightKeys[index] &&
      sameJsonValue(leftRecord[key], rightRecord[key]));
}

function invalidRelationship(message: string): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "INVALID_SUPPLIER_EXTRACTION",
    message,
  );
}

function invalidSnapshotState(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "INVALID_SUPPLIER_EXTRACTION_STATE",
    "Supplier Extraction Snapshot persistence state is invalid.",
  );
}

function invalidStoredChildren(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "INVALID_STORED_SUPPLIER_EXTRACTION",
    "Stored Supplier Extraction Snapshot children are inconsistent.",
  );
}

function jobStateMismatch(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "SUPPLIER_EXTRACTION_JOB_STATE_MISMATCH",
    "Supplier Extraction job state does not match its Snapshot.",
  );
}

function jobContractMismatch(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "SUPPLIER_EXTRACTION_JOB_CONTRACT_MISMATCH",
    "Supplier Extraction job contract is invalid.",
  );
}

function relationshipMismatch(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "SUPPLIER_EXTRACTION_RELATIONSHIP_MISMATCH",
    "Supplier Extraction Snapshot relationships are inconsistent.",
  );
}

function finalizationFailure(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "SUPPLIER_EXTRACTION_FINALIZATION_FAILED",
    "Supplier Extraction Snapshot finalization did not complete.",
  );
}

export const supplierExtractionChildBatchSize = childBatchSize;
