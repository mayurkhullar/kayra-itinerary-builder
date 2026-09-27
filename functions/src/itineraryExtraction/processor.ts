import {
  DraftCreateData,
  prepareTrustedItineraryDraft,
} from "./draftWriter";
import {
  readTrustedSupplierSourcePackage,
  SupplierSourceReaderDependencies,
} from "./sourceReader";
import {
  TrustedSourceError,
  TrustedSupplierSourcePackage,
  validSourceIdentity,
} from "./sourceReaderValidation";

export type ExtractionJobFailureCode =
  "source_unavailable" |
  "unsupported_source" |
  "extraction_failed" |
  "invalid_extraction_result" |
  "draft_persistence_failed";

export interface ClaimedExtractionJob {
  jobId: string;
  tripId: string;
  sourcePackageId: string;
  requestedByUid: string;
}

export interface ExtractionJobStore {
  claimQueuedJob(
    tripId: string,
    jobId: string,
  ): Promise<ClaimedExtractionJob>;
  markJobFailed(
    job: ClaimedExtractionJob,
    failureCode: ExtractionJobFailureCode,
  ): Promise<void>;
  finalizeCompletedJob(
    job: ClaimedExtractionJob,
    draft: DraftCreateData,
  ): Promise<string>;
}

export interface ItineraryExtractionProviderInput {
  tripId: string;
  sourcePackage: TrustedSupplierSourcePackage;
}

export interface ItineraryExtractionProvider {
  extract(input: ItineraryExtractionProviderInput): Promise<unknown>;
}

export interface ItineraryExtractionProcessorDependencies {
  jobs: ExtractionJobStore;
  sources: SupplierSourceReaderDependencies;
  provider: ItineraryExtractionProvider;
}

export interface ItineraryExtractionProcessorInput {
  tripId: string;
  jobId: string;
}

export interface ItineraryExtractionProcessorResult {
  jobId: string;
  draftId: string;
  status: "completed";
}

export type ItineraryExtractionProcessorErrorCode =
  "JOB_UNAVAILABLE" |
  "JOB_NOT_PROCESSABLE" |
  "SOURCE_FAILURE" |
  "EXTRACTION_PROVIDER_FAILED" |
  "INVALID_EXTRACTION_RESULT" |
  "DRAFT_PERSISTENCE_FAILED" |
  "JOB_FAILURE_FINALIZATION_FAILED";

export class ItineraryExtractionProcessorError extends Error {
  constructor(
    readonly code: ItineraryExtractionProcessorErrorCode,
    message: string,
    readonly failureCode: ExtractionJobFailureCode | null = null,
  ) {
    super(message);
    this.name = "ItineraryExtractionProcessorError";
  }
}

export type ItineraryExtractionProcessorLog = (
  event: string,
  fields: Record<string, unknown>,
) => void;

export async function processItineraryExtractionJob(
  input: ItineraryExtractionProcessorInput,
  dependencies: ItineraryExtractionProcessorDependencies,
  log: ItineraryExtractionProcessorLog = () => {},
): Promise<ItineraryExtractionProcessorResult> {
  requireProcessorIdentity(input.tripId, "Trip");
  requireProcessorIdentity(input.jobId, "Itinerary extraction job");
  log("itinerary-extraction-processing-started", {
    tripId: input.tripId,
    jobId: input.jobId,
  });

  const job = await claimJob(input, dependencies.jobs);
  log("itinerary-extraction-job-claimed", {
    tripId: job.tripId,
    jobId: job.jobId,
  });

  let sourcePackage: TrustedSupplierSourcePackage;
  try {
    sourcePackage = await readTrustedSupplierSourcePackage(
      job.tripId,
      job.sourcePackageId,
      dependencies.sources,
    );
  } catch (error) {
    const failureCode = sourceFailureCode(error);
    return failProcessingJob(
      job,
      failureCode,
      "SOURCE_FAILURE",
      "Trusted Supplier Source evidence could not be used.",
      dependencies.jobs,
      log,
    );
  }

  let extractedPayload: unknown;
  try {
    extractedPayload = await dependencies.provider.extract({
      tripId: job.tripId,
      sourcePackage,
    });
  } catch (_) {
    return failProcessingJob(
      job,
      "extraction_failed",
      "EXTRACTION_PROVIDER_FAILED",
      "The extraction provider did not produce a result.",
      dependencies.jobs,
      log,
    );
  }

  let draft: DraftCreateData;
  try {
    draft = prepareTrustedItineraryDraft({
      tripId: job.tripId,
      sourcePackageId: job.sourcePackageId,
      requestedByUid: job.requestedByUid,
      extractedPayload,
      trustedPackage: sourcePackage,
    });
  } catch (_) {
    return failProcessingJob(
      job,
      "invalid_extraction_result",
      "INVALID_EXTRACTION_RESULT",
      "The extracted itinerary did not match the trusted schema.",
      dependencies.jobs,
      log,
    );
  }

  let draftId: string;
  try {
    draftId = await dependencies.jobs.finalizeCompletedJob(job, draft);
  } catch (_) {
    return failProcessingJob(
      job,
      "draft_persistence_failed",
      "DRAFT_PERSISTENCE_FAILED",
      "The itinerary draft and job could not be finalized atomically.",
      dependencies.jobs,
      log,
    );
  }

  log("itinerary-extraction-processing-completed", {
    tripId: job.tripId,
    jobId: job.jobId,
    status: "completed",
  });
  return {jobId: job.jobId, draftId, status: "completed"};
}

async function claimJob(
  input: ItineraryExtractionProcessorInput,
  jobs: ExtractionJobStore,
): Promise<ClaimedExtractionJob> {
  try {
    return await jobs.claimQueuedJob(input.tripId, input.jobId);
  } catch (error) {
    if (error instanceof ItineraryExtractionProcessorError) throw error;
    throw new ItineraryExtractionProcessorError(
      "JOB_UNAVAILABLE",
      "Itinerary extraction job could not be loaded or claimed.",
    );
  }
}

function sourceFailureCode(error: unknown): ExtractionJobFailureCode {
  if (error instanceof TrustedSourceError &&
      error.code === "UNSUPPORTED_SOURCE") {
    return "unsupported_source";
  }
  return "source_unavailable";
}

async function failProcessingJob(
  job: ClaimedExtractionJob,
  failureCode: ExtractionJobFailureCode,
  processorCode: ItineraryExtractionProcessorErrorCode,
  message: string,
  jobs: ExtractionJobStore,
  log: ItineraryExtractionProcessorLog,
): Promise<never> {
  try {
    await jobs.markJobFailed(job, failureCode);
  } catch (_) {
    log("itinerary-extraction-failure-finalization-failed", {
      tripId: job.tripId,
      jobId: job.jobId,
      failureCode,
    });
    throw new ItineraryExtractionProcessorError(
      "JOB_FAILURE_FINALIZATION_FAILED",
      "The processing failure could not be recorded.",
      failureCode,
    );
  }
  log("itinerary-extraction-processing-failed", {
    tripId: job.tripId,
    jobId: job.jobId,
    status: "failed",
    failureCode,
  });
  throw new ItineraryExtractionProcessorError(
    processorCode,
    message,
    failureCode,
  );
}

function requireProcessorIdentity(value: unknown, label: string): string {
  if (!validSourceIdentity(value)) {
    throw new ItineraryExtractionProcessorError(
      "JOB_UNAVAILABLE",
      `${label} identity is invalid.`,
    );
  }
  return value;
}
