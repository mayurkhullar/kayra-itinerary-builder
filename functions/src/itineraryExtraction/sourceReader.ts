import {
  SourceRecord,
  TrustedSourceError,
  TrustedStorageObjectMetadata,
  TrustedSupplierSourcePackage,
  validateSourceFile,
  validateSourcePackage,
  validateStorageObject,
  validSourceIdentity,
} from "./sourceReaderValidation";

export interface SupplierSourceReaderDependencies {
  readPackage(
    tripId: string,
    sourcePackageId: string,
  ): Promise<SourceRecord | null>;
  readFiles(
    tripId: string,
    sourceFileIds: readonly string[],
  ): Promise<readonly (SourceRecord | null)[]>;
  inspectObject(
    storagePath: string,
  ): Promise<TrustedStorageObjectMetadata | null>;
}

export async function readTrustedSupplierSourcePackage(
  tripId: string,
  sourcePackageId: string,
  dependencies: SupplierSourceReaderDependencies,
): Promise<TrustedSupplierSourcePackage> {
  if (!validSourceIdentity(tripId) ||
      !validSourceIdentity(sourcePackageId)) {
    throw new TrustedSourceError(
      "INVALID_SOURCE_INTEGRITY",
      "Invalid Supplier Source request identity.",
    );
  }
  const packageData = await dependencies.readPackage(tripId, sourcePackageId);
  if (!packageData) {
    throw new TrustedSourceError(
      "SOURCE_UNAVAILABLE",
      "Supplier Source package is unavailable.",
    );
  }
  const sourcePackage = validateSourcePackage(
    packageData,
    tripId,
    sourcePackageId,
  );
  const fileRecords = await dependencies.readFiles(
    tripId,
    sourcePackage.fileIds,
  );
  if (fileRecords.length !== sourcePackage.fileIds.length) {
    throw new TrustedSourceError(
      "SOURCE_UNAVAILABLE",
      "Supplier Source file metadata is unavailable.",
    );
  }

  const files = [];
  for (let index = 0; index < sourcePackage.fileIds.length; index += 1) {
    const sourceFileId = sourcePackage.fileIds[index];
    const fileData = fileRecords[index];
    if (!fileData) {
      throw new TrustedSourceError(
        "SOURCE_UNAVAILABLE",
        "Supplier Source file metadata is unavailable.",
      );
    }
    const file = validateSourceFile(
      fileData,
      tripId,
      sourcePackageId,
      sourceFileId,
      sourcePackage.uploadedByUid,
    );
    const object = await dependencies.inspectObject(file.storagePath);
    if (!object) {
      throw new TrustedSourceError(
        "SOURCE_UNAVAILABLE",
        "Supplier Source Storage object is unavailable.",
      );
    }
    validateStorageObject(object, file, sourcePackageId);
    files.push(file);
  }

  return Object.freeze({
    tripId,
    packageId: sourcePackageId,
    supplierId: sourcePackage.supplierId,
    supplierNameSnapshot: sourcePackage.supplierNameSnapshot,
    files: Object.freeze(files),
  });
}
