import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {logger} from "firebase-functions";
import {
  DocumentOptions,
  onDocumentCreated,
} from "firebase-functions/v2/firestore";
import {
  ExtractionProcessorRouterDependencies,
  ExtractionProcessorRouterResult,
  routeItineraryExtractionJob,
} from "./extractionProcessorRouter";
import {
  adminExtractionProcessorRouterDependencies,
} from "./extractionProcessorRouterAdmin";
import {
  ItineraryExtractionProcessorError,
  ItineraryExtractionProcessorInput,
  ItineraryExtractionProcessorLog,
} from "./processor";
import {
  SupplierExtractionProcessorError,
} from "./supplierExtractionProcessor";
import {validSourceIdentity} from "./sourceReaderValidation";

export {
  adminItineraryExtractionProcessorDependencies,
  productionItineraryExtractionAdapters,
} from "./extractionProcessorRouterAdmin";

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

export type ItineraryExtractionRouterRunner = (
  input: ItineraryExtractionProcessorInput,
  dependencies: ExtractionProcessorRouterDependencies,
  log?: ItineraryExtractionProcessorLog,
) => Promise<ExtractionProcessorRouterResult>;

export function createItineraryExtractionCreateHandler(options: {
  createDependencies: () => ExtractionProcessorRouterDependencies;
  router?: ItineraryExtractionRouterRunner;
  log?: ItineraryExtractionTriggerLog;
}): (event: ItineraryExtractionCreateEvent) => Promise<void> {
  const router = options.router ?? routeItineraryExtractionJob;
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
      const result = await router(
        {tripId, jobId},
        options.createDependencies(),
        (routerEvent, routerFields) => log(
          "info",
          routerEvent,
          {...routerFields, ...fields},
        ),
      );
      if (result.outcome === "non_retryable") {
        log("error", "itinerary-extraction-trigger-non-retryable", {
          ...fields,
          outcome: result.outcome,
          reason: result.reason,
          extractionContractVersion: result.extractionContractVersion,
          selectedProcessorRoute: result.route,
        });
        return;
      }
      log("info", "itinerary-extraction-trigger-handled", {
        ...fields,
        outcome: result.outcome,
        extractionContractVersion: result.extractionContractVersion,
        selectedProcessorRoute: result.route,
        ...(result.failureCode ? {failureCode: result.failureCode} : {}),
      });
    } catch (error) {
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
  createDependencies: () => adminExtractionProcessorRouterDependencies(
    getFirestore(),
    getStorage().bucket(),
  ),
  log: productionLog,
});

export const processItineraryExtractionJob = onDocumentCreated(
  itineraryExtractionTriggerOptions,
  async (event) => productionHandler({id: event.id, params: event.params}),
);

function safeEventId(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function safeErrorCategory(error: unknown): string {
  if (error instanceof ItineraryExtractionProcessorError) return error.code;
  if (error instanceof SupplierExtractionProcessorError) return error.code;
  if (error instanceof Error && error.name.length > 0) return error.name;
  return "unknown";
}
