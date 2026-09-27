import {getFirestore, Firestore} from "firebase-admin/firestore";
import {getStorage, Storage} from "firebase-admin/storage";
import {logger} from "firebase-functions";
import {
  DocumentOptions,
  onDocumentCreated,
} from "firebase-functions/v2/firestore";
import {
  adminGeminiItineraryExtractionProvider,
} from "./geminiProviderAdmin";
import {
  ItineraryExtractionProcessorDependencies,
  ItineraryExtractionProcessorError,
  ItineraryExtractionProcessorInput,
  ItineraryExtractionProcessorLog,
  ItineraryExtractionProcessorResult,
  processItineraryExtractionJob as runItineraryExtractionProcessor,
} from "./processor";
import {adminExtractionJobStore} from "./processorAdmin";
import {
  adminSupplierSourceReaderDependencies,
} from "./sourceReaderAdmin";
import {validSourceIdentity} from "./sourceReaderValidation";

type Bucket = ReturnType<Storage["bucket"]>;

export const itineraryExtractionTriggerPath =
  "trips/{tripId}/itinerary_extraction_jobs/{jobId}";
export const itineraryExtractionTriggerFunctionName =
  "processItineraryExtractionJob";
export const itineraryExtractionTriggerOptions = {
  document: itineraryExtractionTriggerPath,
  region: "asia-south2",
  minInstances: 0,
  maxInstances: 2,
  concurrency: 1,
  timeoutSeconds: 540,
  memory: "1GiB",
  retry: true,
  serviceAccount:
    "121704138111-compute@developer.gserviceaccount.com",
} as const satisfies DocumentOptions<typeof itineraryExtractionTriggerPath>;

export interface ItineraryExtractionCreateEvent {
  readonly id?: unknown;
  readonly params?: {
    readonly tripId?: unknown;
    readonly jobId?: unknown;
  };
}

export type ItineraryExtractionTriggerLog = (
  level: "info" | "error",
  event: string,
  fields: Record<string, unknown>,
) => void;

export type ItineraryExtractionProcessorRunner = (
  input: ItineraryExtractionProcessorInput,
  dependencies: ItineraryExtractionProcessorDependencies,
  log?: ItineraryExtractionProcessorLog,
) => Promise<ItineraryExtractionProcessorResult>;

interface ProductionAdapterFactories {
  readonly jobs: typeof adminExtractionJobStore;
  readonly sources: typeof adminSupplierSourceReaderDependencies;
  readonly provider: typeof adminGeminiItineraryExtractionProvider;
}

export const productionItineraryExtractionAdapters:
    ProductionAdapterFactories = Object.freeze({
  jobs: adminExtractionJobStore,
  sources: adminSupplierSourceReaderDependencies,
  provider: adminGeminiItineraryExtractionProvider,
});

export function adminItineraryExtractionProcessorDependencies(
  db: Firestore,
  bucket: Bucket,
  providerLog: ItineraryExtractionProcessorLog = () => {},
  adapters: ProductionAdapterFactories = productionItineraryExtractionAdapters,
): ItineraryExtractionProcessorDependencies {
  return {
    jobs: adapters.jobs(db),
    sources: adapters.sources(db, bucket),
    provider: adapters.provider(bucket, {log: providerLog}),
  };
}

export function createItineraryExtractionCreateHandler(options: {
  createDependencies: () => ItineraryExtractionProcessorDependencies;
  processor?: ItineraryExtractionProcessorRunner;
  log?: ItineraryExtractionTriggerLog;
}): (event: ItineraryExtractionCreateEvent) => Promise<void> {
  const processor = options.processor ?? runItineraryExtractionProcessor;
  const log = options.log ?? (() => {});
  return async (event) => {
    const eventId = safeEventId(event?.id);
    const tripId = event?.params?.tripId;
    const jobId = event?.params?.jobId;
    if (!validSourceIdentity(tripId) || !validSourceIdentity(jobId)) {
      log("error", "itinerary-extraction-trigger-invalid-event", {
        functionName: itineraryExtractionTriggerFunctionName,
        eventId,
        outcome: "infrastructure-error",
      });
      throw new Error("Itinerary extraction event identity is invalid.");
    }

    const fields = {
      functionName: itineraryExtractionTriggerFunctionName,
      eventId,
      tripId,
      jobId,
    };
    try {
      await processor(
        {tripId, jobId},
        options.createDependencies(),
        (processorEvent, processorFields) => log(
          "info",
          processorEvent,
          {...processorFields, ...fields},
        ),
      );
      log("info", "itinerary-extraction-trigger-handled", {
        ...fields,
        outcome: "completed",
      });
    } catch (error) {
      if (error instanceof ItineraryExtractionProcessorError) {
        if (error.code === "JOB_NOT_PROCESSABLE") {
          log("info", "itinerary-extraction-trigger-handled", {
            ...fields,
            outcome: "no-op",
          });
          return;
        }
        if (isFinalizedBusinessFailure(error)) {
          log("info", "itinerary-extraction-trigger-handled", {
            ...fields,
            outcome: "terminal-failure",
            failureCode: error.failureCode,
          });
          return;
        }
      }
      log("error", "itinerary-extraction-trigger-failed", {
        ...fields,
        outcome: "infrastructure-error",
        errorCategory: safeErrorCategory(error),
      });
      throw error;
    }
  };
}

const productionLog: ItineraryExtractionTriggerLog = (
  level,
  event,
  fields,
) => {
  if (level === "error") {
    logger.error(event, fields);
  } else {
    logger.info(event, fields);
  }
};

const productionHandler = createItineraryExtractionCreateHandler({
  createDependencies: () => adminItineraryExtractionProcessorDependencies(
    getFirestore(),
    getStorage().bucket(),
    (event, fields) => productionLog("info", event, {
      functionName: itineraryExtractionTriggerFunctionName,
      ...fields,
    }),
  ),
  log: productionLog,
});

export const processItineraryExtractionJob = onDocumentCreated(
  itineraryExtractionTriggerOptions,
  async (event) => productionHandler({id: event.id, params: event.params}),
);

function isFinalizedBusinessFailure(
  error: ItineraryExtractionProcessorError,
): boolean {
  return error.failureCode !== null && [
    "SOURCE_FAILURE",
    "EXTRACTION_PROVIDER_FAILED",
    "INVALID_EXTRACTION_RESULT",
    "DRAFT_PERSISTENCE_FAILED",
  ].includes(error.code);
}

function safeEventId(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function safeErrorCategory(error: unknown): string {
  if (error instanceof ItineraryExtractionProcessorError) return error.code;
  if (error instanceof Error && error.name.length > 0) return error.name;
  return "unknown";
}
