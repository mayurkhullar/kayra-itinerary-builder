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

export type ItineraryExtractionProviderErrorCode =
  "UNSUPPORTED_SOURCE" |
  "PROVIDER_EXECUTION_FAILED";

export class ItineraryExtractionProviderError extends Error {
  constructor(
    readonly code: ItineraryExtractionProviderErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "ItineraryExtractionProviderError";
  }
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
  const processingStartedAt = performance.now();
  log("itinerary-extraction-processing-started", {
    tripId: input.tripId,
    jobId: input.jobId,
  });

  const claimStartedAt = performance.now();
  let job: ClaimedExtractionJob;
  try {
    job = await claimJob(input, dependencies.jobs);
  } catch (error) {
    log("itinerary-extraction-job-claim-failed", {
      tripId: input.tripId,
      jobId: input.jobId,
      jobClaimDurationMs: elapsedMilliseconds(claimStartedAt),
      totalProcessingDurationMs: elapsedMilliseconds(processingStartedAt),
    });
    throw error;
  }
  log("itinerary-extraction-job-claimed", {
    tripId: job.tripId,
    jobId: job.jobId,
    jobClaimDurationMs: elapsedMilliseconds(claimStartedAt),
  });

  const sourceValidationStartedAt = performance.now();
  let sourcePackage: TrustedSupplierSourcePackage;
  try {
    sourcePackage = await readTrustedSupplierSourcePackage(
      job.tripId,
      job.sourcePackageId,
      dependencies.sources,
    );
  } catch (error) {
    const failureCode = sourceFailureCode(error);
    log("itinerary-extraction-source-validation-failed", {
      tripId: job.tripId,
      jobId: job.jobId,
      sourceValidationDurationMs: elapsedMilliseconds(
        sourceValidationStartedAt,
      ),
      failureCode,
    });
    return failProcessingJob(
      job,
      failureCode,
      "SOURCE_FAILURE",
      "Trusted Supplier Source evidence could not be used.",
      dependencies.jobs,
      log,
      processingStartedAt,
    );
  }
  log("itinerary-extraction-source-validated", {
    tripId: job.tripId,
    jobId: job.jobId,
    sourceValidationDurationMs: elapsedMilliseconds(sourceValidationStartedAt),
  });

  const providerStartedAt = performance.now();
  let extractedPayload: unknown;
  try {
    extractedPayload = await dependencies.provider.extract({
      tripId: job.tripId,
      sourcePackage,
    });
  } catch (error) {
    const providerDurationMs = elapsedMilliseconds(providerStartedAt);
    if (error instanceof ItineraryExtractionProviderError &&
        error.code === "UNSUPPORTED_SOURCE") {
      log("itinerary-extraction-provider-phase-failed", {
        tripId: job.tripId,
        jobId: job.jobId,
        providerDurationMs,
        category: error.code,
      });
      return failProcessingJob(
        job,
        "unsupported_source",
        "SOURCE_FAILURE",
        "The source package contains a format this provider cannot extract.",
        dependencies.jobs,
        log,
        processingStartedAt,
      );
    }
    log("itinerary-extraction-provider-phase-failed", {
      tripId: job.tripId,
      jobId: job.jobId,
      providerDurationMs,
      category: error instanceof ItineraryExtractionProviderError ?
        error.code : "unknown",
    });
    return failProcessingJob(
      job,
      "extraction_failed",
      "EXTRACTION_PROVIDER_FAILED",
      "The extraction provider did not produce a result.",
      dependencies.jobs,
      log,
      processingStartedAt,
    );
  }
  log("itinerary-extraction-provider-phase-completed", {
    tripId: job.tripId,
    jobId: job.jobId,
    providerDurationMs: elapsedMilliseconds(providerStartedAt),
  });

  const draftValidationStartedAt = performance.now();
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
    log("itinerary-extraction-draft-validation-failed", {
      tripId: job.tripId,
      jobId: job.jobId,
      draftValidationDurationMs: elapsedMilliseconds(
        draftValidationStartedAt,
      ),
    });
    return failProcessingJob(
      job,
      "invalid_extraction_result",
      "INVALID_EXTRACTION_RESULT",
      "The extracted itinerary did not match the trusted schema.",
      dependencies.jobs,
      log,
      processingStartedAt,
    );
  }
  log("itinerary-extraction-draft-validated", {
    tripId: job.tripId,
    jobId: job.jobId,
    draftValidationDurationMs: elapsedMilliseconds(draftValidationStartedAt),
  });

  const draftFinalizationStartedAt = performance.now();
  let draftId: string;
  try {
    draftId = await dependencies.jobs.finalizeCompletedJob(job, draft);
  } catch (_) {
    log("itinerary-extraction-draft-finalization-failed", {
      tripId: job.tripId,
      jobId: job.jobId,
      draftFinalizationDurationMs: elapsedMilliseconds(
        draftFinalizationStartedAt,
      ),
    });
    return failProcessingJob(
      job,
      "draft_persistence_failed",
      "DRAFT_PERSISTENCE_FAILED",
      "The itinerary draft and job could not be finalized atomically.",
      dependencies.jobs,
      log,
      processingStartedAt,
    );
  }

  log("itinerary-extraction-processing-completed", {
    tripId: job.tripId,
    jobId: job.jobId,
    status: "completed",
    draftFinalizationDurationMs: elapsedMilliseconds(
      draftFinalizationStartedAt,
    ),
    totalProcessingDurationMs: elapsedMilliseconds(processingStartedAt),
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
  processingStartedAt: number,
): Promise<never> {
  try {
    await jobs.markJobFailed(job, failureCode);
  } catch (_) {
    log("itinerary-extraction-failure-finalization-failed", {
      tripId: job.tripId,
      jobId: job.jobId,
      failureCode,
      totalProcessingDurationMs: elapsedMilliseconds(processingStartedAt),
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
    totalProcessingDurationMs: elapsedMilliseconds(processingStartedAt),
  });
  throw new ItineraryExtractionProcessorError(
    processorCode,
    message,
    failureCode,
  );
}

function elapsedMilliseconds(startedAt: number): number {
  return Math.max(0, Math.round(performance.now() - startedAt));
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
