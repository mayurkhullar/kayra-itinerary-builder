import {
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {Storage} from "firebase-admin/storage";
import {
  failedExtractionJobUpdate,
  ExtractionJobRecord,
  parseExtractionJobRecord,
  processingExtractionJobUpdate,
  supplierExtractionContractVersion,
} from "./extractionJob";
import {
  GeminiStagingProviderLog,
  geminiSupplierExtractionStagingProvider,
  vertexGeminiStagingGenerationClient,
} from "./geminiStagingProvider";
import {
  adminCsvTextReader,
  resolveGoogleCloudProjectId,
} from "./geminiProviderAdmin";
import {ClaimedExtractionJob} from "./processor";
import {readTrustedSupplierSourcePackage} from "./sourceReader";
import {
  adminSupplierSourceReaderDependencies,
} from "./sourceReaderAdmin";
import {
  adminSupplierExtractionRepositoryStore,
} from "./supplierExtractionRepositoryAdmin";
import {
  SupplierExtractionFailureCode,
  SupplierExtractionProcessorDependencies,
  SupplierExtractionProcessorError,
  SupplierExtractionProcessorJobStore,
} from "./supplierExtractionProcessor";
import {validSourceIdentity} from "./sourceReaderValidation";

type Bucket = ReturnType<Storage["bucket"]>;

export interface AdminSupplierExtractionProcessorOptions {
  projectId?: string;
  providerLog?: GeminiStagingProviderLog;
  now?: () => Date;
}

/** Isolated V3 composition. No production entrypoint imports this module. */
export function adminSupplierExtractionProcessorDependencies(
  db: Firestore,
  bucket: Bucket,
  options: AdminSupplierExtractionProcessorOptions = {},
): SupplierExtractionProcessorDependencies {
  const sourceDependencies = adminSupplierSourceReaderDependencies(db, bucket);
  return {
    jobs: adminSupplierExtractionProcessorJobStore(db),
    sources: {
      readTrustedPackage: (tripId, sourcePackageId) =>
        readTrustedSupplierSourcePackage(
          tripId,
          sourcePackageId,
          sourceDependencies,
        ),
    },
    provider: geminiSupplierExtractionStagingProvider({
      bucketName: bucket.name,
      client: vertexGeminiStagingGenerationClient(
        options.projectId ?? resolveGoogleCloudProjectId(),
      ),
      csvTextReader: adminCsvTextReader(bucket),
      log: options.providerLog,
    }),
    snapshots: adminSupplierExtractionRepositoryStore(db),
    now: options.now,
  };
}

export function adminSupplierExtractionProcessorJobStore(
  db: Firestore,
): SupplierExtractionProcessorJobStore {
  return {
    async claimSupplierExtractionJob(tripId, jobId) {
      const reference = jobDocument(db, tripId, jobId);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        if (!snapshot.exists) throw jobUnavailable();
        const record = parseJobOrNotApplicable(snapshot.data());
        if (record === null || record.tripId !== tripId ||
            record.extractionContractVersion !==
              supplierExtractionContractVersion ||
            record.resultType !== "supplier_extraction" ||
            record.persistenceShape !== "versioned") {
          return {kind: "not_applicable"} as const;
        }
        switch (record.status) {
          case "queued": {
            transaction.update(reference, {
              ...processingExtractionJobUpdate(record),
              updatedAt: FieldValue.serverTimestamp(),
            });
            return {
              kind: "claimed",
              job: claimedJob(record, jobId),
            } as const;
          }
          case "processing":
            return {kind: "already_processing"} as const;
          case "completed":
            if (record.resultingExtractionId !== jobId) throw inconsistent();
            return {
              kind: "already_completed",
              extractionId: record.resultingExtractionId,
            } as const;
          case "failed":
            return {
              kind: "terminal_failure",
              failureCode: supplierFailureCode(record.failureCode),
            } as const;
        }
      });
    },

    async finalizeSupplierExtractionFailure(job, failureCode) {
      const reference = jobDocument(db, job.tripId, job.jobId);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        if (!snapshot.exists) throw jobUnavailable();
        const record = strictSupplierJob(snapshot.data(), job);
        if (record.status === "completed") {
          if (record.resultingExtractionId !== job.jobId) throw inconsistent();
          return {
            kind: "completed",
            extractionId: record.resultingExtractionId,
          } as const;
        }
        if (record.status === "failed") {
          return {
            kind: "failed",
            failureCode: supplierFailureCode(record.failureCode),
          } as const;
        }
        if (record.status !== "processing") throw inconsistent();
        transaction.update(reference, {
          ...failedExtractionJobUpdate(record, failureCode),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {kind: "failed", failureCode} as const;
      });
    },
  };
}

function parseJobOrNotApplicable(input: unknown): ExtractionJobRecord | null {
  try {
    return parseExtractionJobRecord(input, {
      isTimestamp: (value) => value instanceof Timestamp,
    });
  } catch (_) {
    return null;
  }
}

function strictSupplierJob(
  input: unknown,
  expected: ClaimedExtractionJob,
): ExtractionJobRecord {
  const record = parseJobOrNotApplicable(input);
  if (record === null || record.tripId !== expected.tripId ||
      record.sourcePackageId !== expected.sourcePackageId ||
      record.requestedByUid !== expected.requestedByUid ||
      record.extractionContractVersion !== supplierExtractionContractVersion ||
      record.resultType !== "supplier_extraction" ||
      record.persistenceShape !== "versioned") {
    throw inconsistent();
  }
  return record;
}

function claimedJob(
  record: ExtractionJobRecord,
  jobId: string,
): ClaimedExtractionJob {
  return Object.freeze({
    jobId,
    tripId: record.tripId,
    sourcePackageId: record.sourcePackageId,
    requestedByUid: record.requestedByUid,
    extractionContractVersion: record.extractionContractVersion,
    resultType: record.resultType,
    persistenceShape: record.persistenceShape,
  });
}

function supplierFailureCode(
  input: ExtractionJobRecord["failureCode"],
): SupplierExtractionFailureCode {
  if (input === null || input === "draft_persistence_failed") {
    throw inconsistent();
  }
  return input;
}

function jobDocument(db: Firestore, tripId: string, jobId: string) {
  if (!validSourceIdentity(tripId) || !validSourceIdentity(jobId)) {
    throw jobUnavailable();
  }
  return db.doc(`trips/${tripId}/itinerary_extraction_jobs/${jobId}`);
}

function jobUnavailable(): SupplierExtractionProcessorError {
  return new SupplierExtractionProcessorError(
    "JOB_UNAVAILABLE",
    "Supplier Extraction job is unavailable.",
  );
}

function inconsistent(): SupplierExtractionProcessorError {
  return new SupplierExtractionProcessorError(
    "PERSISTENCE_STATE_INCONSISTENT",
    "Supplier Extraction job state is inconsistent.",
  );
}
