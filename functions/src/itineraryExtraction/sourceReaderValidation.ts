export const maxTrustedSourceSizeBytes = 26_214_400;

export const trustedSourceContentTypes = new Set([
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "text/csv",
  "text/plain",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const contentTypeByExtension: Readonly<Record<string, string>> = {
  pdf: "application/pdf",
  doc: "application/msword",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xls: "application/vnd.ms-excel",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  csv: "text/csv",
  txt: "text/plain",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

export type TrustedSourceErrorCode =
  "SOURCE_UNAVAILABLE" |
  "UNSUPPORTED_SOURCE" |
  "INVALID_SOURCE_INTEGRITY";

export class TrustedSourceError extends Error {
  constructor(
    readonly code: TrustedSourceErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "TrustedSourceError";
  }
}

export type SourceRecord = Record<string, unknown>;

export interface TrustedSupplierSourceFile {
  sourceFileId: string;
  packageId: string;
  originalFileName: string;
  storagePath: string;
  contentType: string;
  sizeBytes: number;
  uploadedByUid: string;
}

export interface TrustedSupplierSourcePackage {
  tripId: string;
  packageId: string;
  supplierId: string | null;
  supplierNameSnapshot: string | null;
  files: readonly TrustedSupplierSourceFile[];
}

export interface ValidatedSourcePackage {
  tripId: string;
  packageId: string;
  supplierId: string | null;
  supplierNameSnapshot: string | null;
  uploadedByUid: string;
  fileIds: readonly string[];
}

export interface TrustedStorageObjectMetadata {
  name: unknown;
  contentType: unknown;
  size: unknown;
  metadata: unknown;
}

function integrity(message: string): never {
  throw new TrustedSourceError("INVALID_SOURCE_INTEGRITY", message);
}

function unsupported(message: string): never {
  throw new TrustedSourceError("UNSUPPORTED_SOURCE", message);
}

export function validSourceIdentity(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 &&
    value.trim() === value && !/[\/\\\u0000-\u001f\u007f]/.test(value) &&
    value !== "." && value !== "..";
}

export function validateSourcePackage(
  data: SourceRecord,
  tripId: string,
  packageId: string,
): ValidatedSourcePackage {
  if (!validSourceIdentity(tripId) || !validSourceIdentity(packageId)) {
    integrity("Invalid Supplier Source package identity.");
  }
  if (data.tripId !== tripId) {
    integrity("Supplier Source package belongs to another Trip.");
  }
  if (data.status !== "uploaded") {
    integrity("Supplier Source package is not uploaded.");
  }
  if (!Array.isArray(data.fileIds) || data.fileIds.length === 0) {
    integrity("Uploaded Supplier Source package requires files.");
  }
  const fileIds = data.fileIds;
  if (!fileIds.every(validSourceIdentity)) {
    integrity("Supplier Source package contains an invalid file identity.");
  }
  if (new Set(fileIds).size !== fileIds.length) {
    integrity("Supplier Source package contains duplicate file identities.");
  }
  if (!validSourceIdentity(data.uploadedByUid)) {
    integrity("Supplier Source package uploader identity is invalid.");
  }

  const supplierId = nullableIdentity(data.supplierId, "Supplier identity");
  const supplierNameSnapshot = nullableText(
    data.supplierNameSnapshot,
    "Supplier name snapshot",
  );
  if ((supplierId === null) !== (supplierNameSnapshot === null)) {
    integrity("Supplier identity and name snapshot must be paired.");
  }
  return {
    tripId,
    packageId,
    supplierId,
    supplierNameSnapshot,
    uploadedByUid: data.uploadedByUid,
    fileIds: Object.freeze([...fileIds]),
  };
}

export function validateSourceFile(
  data: SourceRecord,
  tripId: string,
  packageId: string,
  sourceFileId: string,
  packageUploaderUid: string,
): TrustedSupplierSourceFile {
  if (!validSourceIdentity(sourceFileId)) {
    integrity("Supplier Source file identity is invalid.");
  }
  if (data.tripId !== tripId || data.packageId !== packageId) {
    integrity("Supplier Source file identity does not match its package.");
  }
  const originalFileName = requiredText(
    data.originalFileName,
    "Original filename",
  );
  const contentType = requiredText(data.contentType, "Content type");
  if (!trustedSourceContentTypes.has(contentType)) {
    unsupported("Supplier Source content type is unsupported.");
  }
  const sizeBytes = validateFirestoreSize(data.sizeBytes);
  const uploadedByUid = data.uploadedByUid;
  if (!validSourceIdentity(uploadedByUid) ||
      uploadedByUid !== packageUploaderUid) {
    integrity("Supplier Source uploader identity does not match its package.");
  }
  const storagePath = requiredText(data.storagePath, "Storage path");
  const storageFileName = validateCanonicalStoragePath(
    storagePath,
    tripId,
    sourceFileId,
  );
  validateExtensionAndMime(storageFileName, contentType);

  return Object.freeze({
    sourceFileId,
    packageId,
    originalFileName,
    storagePath,
    contentType,
    sizeBytes,
    uploadedByUid,
  });
}

export function validateCanonicalStoragePath(
  storagePath: string,
  tripId: string,
  sourceFileId: string,
): string {
  const segments = storagePath.split("/");
  if (storagePath.trim() !== storagePath || segments.length !== 5 ||
      segments[0] !== "trips" || segments[1] !== tripId ||
      segments[2] !== "supplier_sources" ||
      segments[3] !== sourceFileId) {
    integrity("Supplier Source Storage path is not canonical.");
  }
  const fileName = segments[4];
  if (!validSourceIdentity(fileName) || fileName.includes("..") ||
      /%(?:2e|2f|5c)/i.test(fileName)) {
    integrity("Supplier Source Storage filename is unsafe.");
  }
  return fileName;
}

export function validateExtensionAndMime(
  storageFileName: string,
  contentType: string,
): void {
  const dot = storageFileName.lastIndexOf(".");
  if (dot <= 0 || dot === storageFileName.length - 1) {
    unsupported("Supplier Source filename has no supported extension.");
  }
  const extension = storageFileName.slice(dot + 1).toLowerCase();
  const expected = contentTypeByExtension[extension];
  if (!expected) {
    unsupported("Supplier Source filename extension is unsupported.");
  }
  if (expected !== contentType) {
    unsupported("Supplier Source filename and content type do not agree.");
  }
}

export function validateStorageObject(
  object: TrustedStorageObjectMetadata,
  file: TrustedSupplierSourceFile,
  packageId: string,
): void {
  if (object.name !== file.storagePath) {
    integrity("Storage object name does not match Firestore metadata.");
  }
  if (object.contentType !== file.contentType) {
    integrity("Storage content type does not match Firestore metadata.");
  }
  const objectSize = validateSafeSize(object.size);
  if (objectSize !== file.sizeBytes) {
    integrity("Storage size does not match Firestore metadata.");
  }
  if (!object.metadata || typeof object.metadata !== "object" ||
      Array.isArray(object.metadata)) {
    integrity("Storage custom metadata is missing.");
  }
  const metadata = object.metadata as SourceRecord;
  if (metadata.packageId !== packageId) {
    integrity("Storage package identity does not match.");
  }
  if (metadata.uploadedByUid !== file.uploadedByUid) {
    integrity("Storage uploader identity does not match.");
  }
}

function validateSafeSize(value: unknown): number {
  let size: number;
  if (typeof value === "number") {
    size = value;
  } else if (typeof value === "string" && /^(?:0|[1-9]\d*)$/.test(value)) {
    size = Number(value);
  } else {
    unsupported("Supplier Source size is invalid.");
  }
  if (!Number.isSafeInteger(size) || size <= 0 ||
      size > maxTrustedSourceSizeBytes) {
    unsupported("Supplier Source size is outside the supported range.");
  }
  return size;
}

function validateFirestoreSize(value: unknown): number {
  if (typeof value !== "number") {
    unsupported("Supplier Source size is invalid.");
  }
  return validateSafeSize(value);
}

function requiredText(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    integrity(`${label} is invalid.`);
  }
  return value;
}

function nullableIdentity(value: unknown, label: string): string | null {
  if (value === null) return null;
  if (!validSourceIdentity(value)) integrity(`${label} is invalid.`);
  return value;
}

function nullableText(value: unknown, label: string): string | null {
  if (value === null) return null;
  return requiredText(value, label);
}
