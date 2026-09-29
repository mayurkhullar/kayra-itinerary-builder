import {Firestore, Timestamp} from "firebase-admin/firestore";
import {Storage} from "firebase-admin/storage";
import {
  parseExtractionJobRecord,
} from "./extractionJob";
import {
  ExtractionProcessorRouterDependencies,
  ExtractionRoutingJobReader,
} from "./extractionProcessorRouter";
import {
  adminGeminiItineraryExtractionProvider,
} from "./geminiProviderAdmin";
import {
  ItineraryExtractionProcessorDependencies,
  ItineraryExtractionProcessorLog,
  processItineraryExtractionJob,
} from "./processor";
import {adminExtractionJobStore} from "./processorAdmin";
import {
  adminSupplierSourceReaderDependencies,
} from "./sourceReaderAdmin";
import {
  processSupplierExtractionJob,
} from "./supplierExtractionProcessor";
import {
  adminSupplierExtractionProcessorDependencies,
} from "./supplierExtractionProcessorAdmin";
import {validSourceIdentity} from "./sourceReaderValidation";

type Bucket = ReturnType<Storage["bucket"]>;

interface ItineraryDraftAdapterFactories {
  readonly jobs: typeof adminExtractionJobStore;
  readonly sources: typeof adminSupplierSourceReaderDependencies;
  readonly provider: typeof adminGeminiItineraryExtractionProvider;
}

export const productionItineraryExtractionAdapters:
    ItineraryDraftAdapterFactories = Object.freeze({
  jobs: adminExtractionJobStore,
  sources: adminSupplierSourceReaderDependencies,
  provider: adminGeminiItineraryExtractionProvider,
});

export function adminItineraryExtractionProcessorDependencies(
  db: Firestore,
  bucket: Bucket,
  providerLog: ItineraryExtractionProcessorLog = () => {},
  adapters: ItineraryDraftAdapterFactories =
    productionItineraryExtractionAdapters,
): ItineraryExtractionProcessorDependencies {
  return {
    jobs: adapters.jobs(db),
    sources: adapters.sources(db, bucket),
    provider: adapters.provider(bucket, {log: providerLog}),
  };
}

export function adminExtractionRoutingJobReader(
  db: Firestore,
): ExtractionRoutingJobReader {
  return {
    async readAuthoritativeJob(tripId, jobId) {
      if (!validSourceIdentity(tripId) || !validSourceIdentity(jobId)) {
        return {kind: "not_processable", reason: "invalid_contract"};
      }
      const snapshot = await db.doc(
        `trips/${tripId}/itinerary_extraction_jobs/${jobId}`,
      ).get();
      if (!snapshot.exists) {
        return {kind: "not_processable", reason: "missing"};
      }
      try {
        const job = parseExtractionJobRecord(snapshot.data(), {
          isTimestamp: (value) => value instanceof Timestamp,
        });
        if (job.tripId !== tripId) {
          return {kind: "not_processable", reason: "invalid_contract"};
        }
        return {kind: "job", job};
      } catch (_) {
        return {kind: "not_processable", reason: "invalid_contract"};
      }
    },
  };
}

export function adminExtractionProcessorRouterDependencies(
  db: Firestore,
  bucket: Bucket,
): ExtractionProcessorRouterDependencies {
  return {
    jobs: adminExtractionRoutingJobReader(db),
    processItineraryDraft: (input, log) => processItineraryExtractionJob(
      input,
      adminItineraryExtractionProcessorDependencies(db, bucket, log),
      log,
    ),
    processSupplierExtraction: (input, log) =>
      processSupplierExtractionJob(
        input,
        adminSupplierExtractionProcessorDependencies(db, bucket, {
          providerLog: log,
        }),
        log,
      ),
  };
}
