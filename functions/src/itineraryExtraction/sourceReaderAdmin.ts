import {Firestore} from "firebase-admin/firestore";
import {Storage} from "firebase-admin/storage";
import {SupplierSourceReaderDependencies} from "./sourceReader";
import {TrustedSourceError} from "./sourceReaderValidation";

type Bucket = ReturnType<Storage["bucket"]>;

function errorCode(error: unknown): number | undefined {
  if (!error || typeof error !== "object" || !("code" in error)) {
    return undefined;
  }
  return Number(error.code);
}

export function adminSupplierSourceReaderDependencies(
  db: Firestore,
  bucket: Bucket,
): SupplierSourceReaderDependencies {
  return {
    async readPackage(tripId, sourcePackageId) {
      try {
        const snapshot = await db.doc(
          `trips/${tripId}/supplier_source_packages/${sourcePackageId}`,
        ).get();
        return snapshot.data() ?? null;
      } catch (_) {
        throw unavailable();
      }
    },
    async readFiles(tripId, sourceFileIds) {
      try {
        const references = sourceFileIds.map((sourceFileId) => db.doc(
          `trips/${tripId}/supplier_source_files/${sourceFileId}`,
        ));
        const snapshots = await db.getAll(...references);
        return snapshots.map((snapshot) => snapshot.data() ?? null);
      } catch (_) {
        throw unavailable();
      }
    },
    async inspectObject(storagePath) {
      try {
        const [metadata] = await bucket.file(storagePath).getMetadata();
        return {
          name: metadata.name,
          contentType: metadata.contentType,
          size: metadata.size,
          metadata: metadata.metadata,
        };
      } catch (error) {
        if (errorCode(error) === 404) return null;
        throw unavailable();
      }
    },
  };
}

function unavailable(): TrustedSourceError {
  return new TrustedSourceError(
    "SOURCE_UNAVAILABLE",
    "Supplier Source evidence could not be read.",
  );
}
