import {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import {SupplierExtractionPersistenceError} from
  "./supplierExtractionRepository";
import {SupplierImportResolutionAggregate} from "./supplierImportResolution";
import {SupplierImportResolutionError} from
  "./supplierImportResolutionValidation";
import {
  StoredSupplierImportResolution,
  reconstructStoredSupplierImportResolution,
} from "./supplierImportResolutionStoredValidation";
import {validSourceIdentity} from "./sourceReaderValidation";

export type SupplierImportResolutionRepositoryErrorCode =
  "SUPPLIER_EXTRACTION_UNAVAILABLE" |
  "INVALID_STORED_SUPPLIER_EXTRACTION" |
  "INVALID_STORED_SUPPLIER_IMPORT_RESOLUTION" |
  "SUPPLIER_IMPORT_RESOLUTION_READ_FAILED";

export class SupplierImportResolutionRepositoryError extends Error {
  constructor(
    readonly code: SupplierImportResolutionRepositoryErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "SupplierImportResolutionRepositoryError";
  }
}

export type SupplierImportResolutionReadResult =
  Readonly<{kind: "not_started"}> |
  Readonly<{
    kind: "found";
    snapshot: SupplierExtractionSnapshot;
    resolution: SupplierImportResolutionAggregate;
  }>;

export interface SupplierImportResolutionRepositoryStore {
  loadAuthoritativeSnapshot(
    tripId: string,
    extractionId: string,
  ): Promise<SupplierExtractionSnapshot>;
  readResolution(
    tripId: string,
    extractionId: string,
    resolutionId: string,
  ): Promise<StoredSupplierImportResolution | null>;
}

export async function readSupplierImportResolution(
  tripId: string,
  extractionId: string,
  store: SupplierImportResolutionRepositoryStore,
): Promise<SupplierImportResolutionReadResult> {
  requireIdentity(tripId);
  requireIdentity(extractionId);
  let snapshot: SupplierExtractionSnapshot;
  let stored: StoredSupplierImportResolution | null;
  try {
    snapshot = await store.loadAuthoritativeSnapshot(tripId, extractionId);
    stored = await store.readResolution(tripId, extractionId, extractionId);
  } catch (error) {
    if (error instanceof SupplierImportResolutionRepositoryError) throw error;
    if (error instanceof SupplierExtractionPersistenceError) {
      const malformedSnapshot = error.code === "INVALID_STORED_SUPPLIER_EXTRACTION" ||
        error.code === "SUPPLIER_EXTRACTION_RELATIONSHIP_MISMATCH";
      throw new SupplierImportResolutionRepositoryError(
        malformedSnapshot ? "INVALID_STORED_SUPPLIER_EXTRACTION" :
          "SUPPLIER_EXTRACTION_UNAVAILABLE",
        malformedSnapshot ? "Stored Supplier Extraction Snapshot is malformed." :
          "Supplier Extraction Snapshot is unavailable.",
      );
    }
    throw new SupplierImportResolutionRepositoryError(
      "SUPPLIER_IMPORT_RESOLUTION_READ_FAILED",
      "Supplier Import Resolution could not be read.",
    );
  }
  if (stored === null) return Object.freeze({kind: "not_started"});
  try {
    return Object.freeze({
      kind: "found",
      snapshot,
      resolution: reconstructStoredSupplierImportResolution(
        snapshot, stored, tripId, extractionId,
      ),
    });
  } catch (error) {
    if (error instanceof SupplierImportResolutionError) {
      throw new SupplierImportResolutionRepositoryError(
        "INVALID_STORED_SUPPLIER_IMPORT_RESOLUTION",
        "Stored Supplier Import Resolution is malformed.",
      );
    }
    throw error;
  }
}

export interface SupplierImportResolutionPathSet {
  root: string;
  decisions: string;
  manualItems: string;
  auditEvents: string;
}

export function supplierImportResolutionPaths(
  tripId: string,
  extractionId: string,
): SupplierImportResolutionPathSet {
  requireIdentity(tripId);
  requireIdentity(extractionId);
  const root = `trips/${tripId}/supplier_extractions/${extractionId}` +
    `/resolutions/${extractionId}`;
  return Object.freeze({
    root,
    decisions: `${root}/decisions`,
    manualItems: `${root}/manual_items`,
    auditEvents: `${root}/events`,
  });
}

function requireIdentity(value: unknown): asserts value is string {
  if (!validSourceIdentity(value)) {
    throw new SupplierImportResolutionRepositoryError(
      "SUPPLIER_IMPORT_RESOLUTION_READ_FAILED",
      "Supplier Import Resolution identity is invalid.",
    );
  }
}
