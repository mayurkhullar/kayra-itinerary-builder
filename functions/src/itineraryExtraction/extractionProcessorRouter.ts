import {
  ExtractionJobRecord,
  itineraryDraftExtractionContractVersion,
  supplierExtractionContractVersion,
} from "./extractionJob";
import {
  ItineraryExtractionProcessorError,
  ItineraryExtractionProcessorInput,
  ItineraryExtractionProcessorLog,
  ItineraryExtractionProcessorResult,
} from "./processor";
import {
  SupplierExtractionProcessorResult,
} from "./supplierExtractionProcessor";
import {validSourceIdentity} from "./sourceReaderValidation";

export type ExtractionProcessorRoute =
  typeof itineraryDraftExtractionContractVersion |
  typeof supplierExtractionContractVersion;

export type ExtractionRoutingJobReadResult =
  {kind: "job"; job: ExtractionJobRecord} |
  {kind: "not_processable"; reason: "missing" | "invalid_contract"};

export interface ExtractionRoutingJobReader {
  readAuthoritativeJob(
    tripId: string,
    jobId: string,
  ): Promise<ExtractionRoutingJobReadResult>;
}

export type ItineraryDraftProcessorRunner = (
  input: ItineraryExtractionProcessorInput,
  log: ItineraryExtractionProcessorLog,
) => Promise<ItineraryExtractionProcessorResult>;

export type SupplierExtractionProcessorRunner = (
  input: ItineraryExtractionProcessorInput,
  log: ItineraryExtractionProcessorLog,
) => Promise<SupplierExtractionProcessorResult>;

export interface ExtractionProcessorRouterDependencies {
  jobs: ExtractionRoutingJobReader;
  processItineraryDraft: ItineraryDraftProcessorRunner;
  processSupplierExtraction: SupplierExtractionProcessorRunner;
}

export type ExtractionProcessorRouterResult =
  {
    outcome: "completed" | "already_completed" | "already_processing" |
      "terminal_failure" | "no_op";
    route: ExtractionProcessorRoute;
    extractionContractVersion: ExtractionProcessorRoute;
    failureCode?: string;
  } |
  {
    outcome: "non_retryable";
    route: ExtractionProcessorRoute | null;
    extractionContractVersion: ExtractionProcessorRoute | null;
    reason: "job_missing" | "invalid_job_contract" |
      "selected_processor_not_applicable";
  };

type HandledExtractionProcessorRouterResult = Exclude<
  ExtractionProcessorRouterResult,
  {outcome: "non_retryable"}
>;

export async function routeItineraryExtractionJob(
  input: ItineraryExtractionProcessorInput,
  dependencies: ExtractionProcessorRouterDependencies,
  log: ItineraryExtractionProcessorLog = () => {},
): Promise<ExtractionProcessorRouterResult> {
  requireIdentity(input.tripId, "Trip");
  requireIdentity(input.jobId, "Extraction job");
  const read = await dependencies.jobs.readAuthoritativeJob(
    input.tripId,
    input.jobId,
  );
  if (read.kind === "not_processable") {
    return {
      outcome: "non_retryable",
      route: null,
      extractionContractVersion: null,
      reason: read.reason === "missing" ?
        "job_missing" : "invalid_job_contract",
    };
  }

  const route = selectedRoute(read.job);
  if (route === null) {
    return {
      outcome: "non_retryable",
      route: null,
      extractionContractVersion: null,
      reason: "invalid_job_contract",
    };
  }
  log("itinerary-extraction-router-selected", {
    tripId: input.tripId,
    jobId: input.jobId,
    extractionContractVersion: route,
    selectedProcessorRoute: route,
  });

  if (route === itineraryDraftExtractionContractVersion) {
    return runItineraryDraftProcessor(input, route, dependencies, log);
  }
  return runSupplierExtractionProcessor(input, route, dependencies, log);
}

function selectedRoute(job: ExtractionJobRecord): ExtractionProcessorRoute | null {
  if (job.extractionContractVersion ===
      itineraryDraftExtractionContractVersion &&
      job.resultType === "itinerary_draft") {
    return itineraryDraftExtractionContractVersion;
  }
  if (job.extractionContractVersion === supplierExtractionContractVersion &&
      job.resultType === "supplier_extraction") {
    return supplierExtractionContractVersion;
  }
  return null;
}

async function runItineraryDraftProcessor(
  input: ItineraryExtractionProcessorInput,
  route: typeof itineraryDraftExtractionContractVersion,
  dependencies: ExtractionProcessorRouterDependencies,
  log: ItineraryExtractionProcessorLog,
): Promise<ExtractionProcessorRouterResult> {
  try {
    await dependencies.processItineraryDraft(input, log);
    return routed("completed", route);
  } catch (error) {
    if (error instanceof ItineraryExtractionProcessorError) {
      if (error.code === "JOB_NOT_PROCESSABLE") {
        return routed("no_op", route);
      }
      if (isFinalizedDraftBusinessFailure(error)) {
        return {
          ...routed("terminal_failure", route),
          failureCode: error.failureCode ?? undefined,
        };
      }
    }
    throw error;
  }
}

async function runSupplierExtractionProcessor(
  input: ItineraryExtractionProcessorInput,
  route: typeof supplierExtractionContractVersion,
  dependencies: ExtractionProcessorRouterDependencies,
  log: ItineraryExtractionProcessorLog,
): Promise<ExtractionProcessorRouterResult> {
  const result = await dependencies.processSupplierExtraction(input, log);
  if (result.outcome === "not_applicable") {
    return {
      outcome: "non_retryable",
      route,
      extractionContractVersion: route,
      reason: "selected_processor_not_applicable",
    };
  }
  if (result.outcome === "terminal_failure") {
    return {
      ...routed(result.outcome, route),
      failureCode: result.failureCode,
    };
  }
  return routed(result.outcome, route);
}

function routed(
  outcome: HandledExtractionProcessorRouterResult["outcome"],
  route: ExtractionProcessorRoute,
): HandledExtractionProcessorRouterResult {
  return {
    outcome,
    route,
    extractionContractVersion: route,
  };
}

function isFinalizedDraftBusinessFailure(
  error: ItineraryExtractionProcessorError,
): boolean {
  return error.failureCode !== null && [
    "SOURCE_FAILURE",
    "EXTRACTION_PROVIDER_FAILED",
    "INVALID_EXTRACTION_RESULT",
    "DRAFT_PERSISTENCE_FAILED",
  ].includes(error.code);
}

function requireIdentity(value: unknown, label: string): string {
  if (!validSourceIdentity(value)) {
    throw new Error(`${label} identity is invalid.`);
  }
  return value;
}
