import {
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {
  SupplierExtractionChildRecord,
  SupplierExtractionPersistenceError,
  SupplierExtractionPersistenceRecords,
  SupplierExtractionRepositoryStore,
} from "./supplierExtractionRepository";
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

    async createSnapshot(records, trustedPackage) {
      const root = records.root;
      const rootReference = extractionDocument(
        db,
        root.tripId,
        root.extractionId,
      );
      await db.runTransaction(async (transaction) => {
        const currentPackage = await loadTrustedPackage(
          db,
          transaction,
          root.tripId,
          root.sourcePackageId,
        );
        requireSameTrustedPackage(trustedPackage, currentPackage);
        transaction.create(rootReference, rootForFirestore(root));
      });

      const children = [
        ...childWrites(rootReference, "days", records.days),
        ...childWrites(rootReference, "facts", records.facts),
        ...childWrites(rootReference, "review_issues", records.reviewIssues),
      ];
      for (let offset = 0; offset < children.length; offset += childBatchSize) {
        const batch = db.batch();
        for (const child of children.slice(offset, offset + childBatchSize)) {
          batch.create(child.reference, child.data);
        }
        await batch.commit();
      }

      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(rootReference);
        if (!snapshot.exists || snapshot.data()?.persistenceState !== "writing") {
          throw persistenceFailure();
        }
        transaction.update(rootReference, {persistenceState: "complete"});
      });
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

function invalidRelationship(message: string): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "INVALID_SUPPLIER_EXTRACTION",
    message,
  );
}

function persistenceFailure(): SupplierExtractionPersistenceError {
  return new SupplierExtractionPersistenceError(
    "SUPPLIER_EXTRACTION_PERSISTENCE_FAILED",
    "Supplier Extraction Snapshot persistence did not complete.",
  );
}

export const supplierExtractionChildBatchSize = childBatchSize;
