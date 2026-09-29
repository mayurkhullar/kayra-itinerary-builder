import {
  ExtractionJobFailureCode,
  supplierExtractionContractVersion,
} from "./extractionJob";
import {
  GeminiStagingProviderError,
  SupplierExtractionStagingProvider,
} from "./geminiStagingProvider";
import {
  ClaimedExtractionJob,
  ItineraryExtractionProviderError,
} from "./processor";
import {
  normalizeProviderSupplierExtractionV3,
  ProviderSupplierExtractionV3,
} from "./providerSupplierExtractionV3";
import {
  serializeSupplierExtractionForPersistence,
  SupplierExtractionFinalizationInspection,
  SupplierExtractionPersistenceRecords,
  SupplierExtractionRepositoryStore,
} from "./supplierExtractionRepository";
import {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import {
  TrustedSourceError,
  TrustedSupplierSourcePackage,
  validSourceIdentity,
} from "./sourceReaderValidation";

export type SupplierExtractionFailureCode = Exclude<
  ExtractionJobFailureCode,
  "draft_persistence_failed"
>;

export type SupplierExtractionJobClaimResult =
  {kind: "claimed"; job: ClaimedExtractionJob} |
  {kind: "already_processing"} |
  {kind: "already_completed"; extractionId: string} |
  {kind: "terminal_failure"; failureCode: SupplierExtractionFailureCode} |
  {kind: "not_applicable"};

export type SupplierExtractionFailureFinalizationResult =
  {kind: "failed"; failureCode: SupplierExtractionFailureCode} |
  {kind: "completed"; extractionId: string};

export interface SupplierExtractionProcessorJobStore {
  claimSupplierExtractionJob(
    tripId: string,
    jobId: string,
  ): Promise<SupplierExtractionJobClaimResult>;
  finalizeSupplierExtractionFailure(
    job: ClaimedExtractionJob,
    failureCode: SupplierExtractionFailureCode,
  ): Promise<SupplierExtractionFailureFinalizationResult>;
}

export interface SupplierExtractionProcessorSourceReader {
  readTrustedPackage(
    tripId: string,
    sourcePackageId: string,
  ): Promise<TrustedSupplierSourcePackage>;
}

export interface SupplierExtractionSnapshotPersistence extends Pick<
  SupplierExtractionRepositoryStore,
  "beginSnapshot" |
  "writeSnapshotChildren" |
  "finalizeSnapshot" |
  "inspectFinalization"
> {}

export type SupplierExtractionNormalizer = (
  value: ProviderSupplierExtractionV3,
  context: {
    extractionId: string;
    tripId: string;
    sourcePackageId: string;
    jobId: string;
    requestedByUid: string;
    createdAt: Date;
    trustedPackage: TrustedSupplierSourcePackage;
  },
) => SupplierExtractionSnapshot;

export interface SupplierExtractionProcessorDependencies {
  jobs: SupplierExtractionProcessorJobStore;
  sources: SupplierExtractionProcessorSourceReader;
  provider: SupplierExtractionStagingProvider;
  snapshots: SupplierExtractionSnapshotPersistence;
  normalize?: SupplierExtractionNormalizer;
  now?: () => Date;
}

export interface SupplierExtractionProcessorInput {
  tripId: string;
  jobId: string;
}

export type SupplierExtractionProcessorResult =
  {outcome: "completed"; jobId: string; extractionId: string} |
  {outcome: "already_completed"; jobId: string; extractionId: string} |
  {outcome: "terminal_failure"; jobId: string;
    failureCode: SupplierExtractionFailureCode} |
  {outcome: "already_processing"; jobId: string} |
  {outcome: "not_applicable"; jobId: string};

export type SupplierExtractionProcessorErrorCode =
  "JOB_UNAVAILABLE" |
  "FAILURE_FINALIZATION_FAILED" |
  "PERSISTENCE_STATE_INCONSISTENT";

export class SupplierExtractionProcessorError extends Error {
  constructor(
    readonly code: SupplierExtractionProcessorErrorCode,
    message: string,
    readonly failureCode: SupplierExtractionFailureCode | null = null,
  ) {
    super(message);
    this.name = "SupplierExtractionProcessorError";
  }
}

export type SupplierExtractionProcessorLog = (
  event: string,
  fields: Record<string, unknown>,
) => void;

export async function processSupplierExtractionJob(
  input: SupplierExtractionProcessorInput,
  dependencies: SupplierExtractionProcessorDependencies,
  log: SupplierExtractionProcessorLog = () => {},
): Promise<SupplierExtractionProcessorResult> {
  requireIdentity(input.tripId, "Trip");
  requireIdentity(input.jobId, "Extraction job");
  const startedAt = performance.now();
  const claim = await dependencies.jobs.claimSupplierExtractionJob(
    input.tripId,
    input.jobId,
  );
  if (claim.kind !== "claimed") {
    const terminal = terminalClaimResult(input.jobId, claim);
    log("supplier-extraction-v3-processing-no-op", {
      tripId: input.tripId,
      jobId: input.jobId,
      outcome: terminal.outcome,
    });
    return terminal;
  }
  const job = claim.job;
  log("supplier-extraction-v3-job-claimed", safeJobFields(job));

  const sourceStartedAt = performance.now();
  let sourcePackage: TrustedSupplierSourcePackage;
  try {
    sourcePackage = await dependencies.sources.readTrustedPackage(
      job.tripId,
      job.sourcePackageId,
    );
  } catch (error) {
    return finalizeFailure(
      job,
      sourceFailureCode(error),
      dependencies.jobs,
      log,
      startedAt,
    );
  }
  log("supplier-extraction-v3-source-validated", {
    ...safeJobFields(job),
    sourceValidationDurationMs: elapsed(sourceStartedAt),
    fileCount: sourcePackage.files.length,
  });

  const providerStartedAt = performance.now();
  let providerResult: ProviderSupplierExtractionV3;
  try {
    providerResult = await dependencies.provider.extract({
      tripId: job.tripId,
      sourcePackage,
    });
  } catch (error) {
    const failureCode = providerFailureCode(error);
    log("supplier-extraction-v3-provider-phase-failed", {
      ...safeJobFields(job),
      providerDurationMs: elapsed(providerStartedAt),
      failureCode,
      category: safeProviderCategory(error),
    });
    return finalizeFailure(
      job,
      failureCode,
      dependencies.jobs,
      log,
      startedAt,
    );
  }
  log("supplier-extraction-v3-provider-phase-completed", {
    ...safeJobFields(job),
    providerDurationMs: elapsed(providerStartedAt),
  });

  const normalize = dependencies.normalize ??
    normalizeProviderSupplierExtractionV3;
  let snapshot: SupplierExtractionSnapshot;
  try {
    snapshot = normalize(providerResult, {
      extractionId: job.jobId,
      tripId: job.tripId,
      sourcePackageId: job.sourcePackageId,
      jobId: job.jobId,
      requestedByUid: job.requestedByUid,
      createdAt: (dependencies.now ?? (() => new Date()))(),
      trustedPackage: sourcePackage,
    });
  } catch (_) {
    return finalizeFailure(
      job,
      "invalid_extraction_result",
      dependencies.jobs,
      log,
      startedAt,
    );
  }
  log("supplier-extraction-v3-result-normalized", {
    ...safeJobFields(job),
    extractionId: snapshot.extractionId,
    ...snapshot.counts,
  });

  const records = serializeSupplierExtractionForPersistence(snapshot);
  let persistencePhase: "begin" | "children" | "finalize" = "begin";
  try {
    const state = await dependencies.snapshots.beginSnapshot(
      records,
      sourcePackage,
    );
    log("supplier-extraction-v3-snapshot-begin-completed", {
      ...safeJobFields(job),
      extractionId: snapshot.extractionId,
      persistenceState: state,
    });
    if (state === "writing") {
      persistencePhase = "children";
      await dependencies.snapshots.writeSnapshotChildren(records);
      log("supplier-extraction-v3-snapshot-children-persisted", {
        ...safeJobFields(job),
        extractionId: snapshot.extractionId,
        dayCount: records.days.length,
        factCount: records.facts.length,
        reviewIssueCount: records.reviewIssues.length,
      });
    }
    persistencePhase = "finalize";
    await dependencies.snapshots.finalizeSnapshot(records, sourcePackage);
  } catch (_) {
    log("supplier-extraction-v3-snapshot-persistence-failed", {
      ...safeJobFields(job),
      extractionId: snapshot.extractionId,
      phase: persistencePhase,
      failureCode: "supplier_extraction_persistence_failed",
    });
    return handlePersistenceFailure(
      job,
      records,
      sourcePackage,
      dependencies,
      log,
      startedAt,
    );
  }

  log("supplier-extraction-v3-processing-completed", {
    ...safeJobFields(job),
    extractionId: snapshot.extractionId,
    outcome: "completed",
    totalProcessingDurationMs: elapsed(startedAt),
  });
  return {
    outcome: "completed",
    jobId: job.jobId,
    extractionId: snapshot.extractionId,
  };
}

function terminalClaimResult(
  jobId: string,
  claim: Exclude<SupplierExtractionJobClaimResult, {kind: "claimed"}>,
): SupplierExtractionProcessorResult {
  switch (claim.kind) {
    case "already_processing": return {outcome: claim.kind, jobId};
    case "already_completed": return {
      outcome: claim.kind,
      jobId,
      extractionId: claim.extractionId,
    };
    case "terminal_failure": return {
      outcome: claim.kind,
      jobId,
      failureCode: claim.failureCode,
    };
    case "not_applicable": return {outcome: claim.kind, jobId};
  }
}

async function handlePersistenceFailure(
  job: ClaimedExtractionJob,
  records: SupplierExtractionPersistenceRecords,
  sourcePackage: TrustedSupplierSourcePackage,
  dependencies: SupplierExtractionProcessorDependencies,
  log: SupplierExtractionProcessorLog,
  startedAt: number,
): Promise<SupplierExtractionProcessorResult> {
  let inspection: SupplierExtractionFinalizationInspection;
  try {
    inspection = await dependencies.snapshots.inspectFinalization(
      records,
      sourcePackage,
    );
  } catch (_) {
    throw inconsistentPersistence();
  }
  if (inspection === "complete_completed") {
    log("supplier-extraction-v3-processing-completed", {
      ...safeJobFields(job),
      extractionId: job.jobId,
      outcome: "completed-after-authoritative-read",
      totalProcessingDurationMs: elapsed(startedAt),
    });
    return {outcome: "completed", jobId: job.jobId, extractionId: job.jobId};
  }
  if (inspection === "eligible_for_failure") {
    return finalizeFailure(
      job,
      "supplier_extraction_persistence_failed",
      dependencies.jobs,
      log,
      startedAt,
    );
  }
  throw inconsistentPersistence();
}

async function finalizeFailure(
  job: ClaimedExtractionJob,
  failureCode: SupplierExtractionFailureCode,
  jobs: SupplierExtractionProcessorJobStore,
  log: SupplierExtractionProcessorLog,
  startedAt: number,
): Promise<SupplierExtractionProcessorResult> {
  let result: SupplierExtractionFailureFinalizationResult;
  try {
    result = await jobs.finalizeSupplierExtractionFailure(job, failureCode);
  } catch (_) {
    throw new SupplierExtractionProcessorError(
      "FAILURE_FINALIZATION_FAILED",
      "Supplier Extraction processing failure could not be recorded.",
      failureCode,
    );
  }
  if (result.kind === "completed") {
    log("supplier-extraction-v3-processing-completed", {
      ...safeJobFields(job),
      extractionId: result.extractionId,
      outcome: "completed-during-failure-finalization",
      totalProcessingDurationMs: elapsed(startedAt),
    });
    return {
      outcome: "already_completed",
      jobId: job.jobId,
      extractionId: result.extractionId,
    };
  }
  log("supplier-extraction-v3-processing-failed", {
    ...safeJobFields(job),
    outcome: "terminal_failure",
    failureCode: result.failureCode,
    totalProcessingDurationMs: elapsed(startedAt),
  });
  return {
    outcome: "terminal_failure",
    jobId: job.jobId,
    failureCode: result.failureCode,
  };
}

function sourceFailureCode(error: unknown): SupplierExtractionFailureCode {
  return error instanceof TrustedSourceError &&
    error.code === "UNSUPPORTED_SOURCE" ?
    "unsupported_source" : "source_unavailable";
}

function providerFailureCode(error: unknown): SupplierExtractionFailureCode {
  if (error instanceof GeminiStagingProviderError &&
      error.reason === "invalid_v3_response") {
    return "invalid_extraction_result";
  }
  if (error instanceof ItineraryExtractionProviderError &&
      error.code === "UNSUPPORTED_SOURCE") {
    return "unsupported_source";
  }
  return "extraction_failed";
}

function safeProviderCategory(error: unknown): string {
  if (error instanceof GeminiStagingProviderError) return error.reason;
  if (error instanceof ItineraryExtractionProviderError) return error.code;
  return "unknown";
}

function safeJobFields(job: ClaimedExtractionJob): Record<string, unknown> {
  return {
    tripId: job.tripId,
    jobId: job.jobId,
    sourcePackageId: job.sourcePackageId,
    extractionContractVersion: supplierExtractionContractVersion,
  };
}

function elapsed(startedAt: number): number {
  return Math.max(0, Math.round(performance.now() - startedAt));
}

function requireIdentity(value: unknown, label: string): string {
  if (!validSourceIdentity(value)) {
    throw new SupplierExtractionProcessorError(
      "JOB_UNAVAILABLE",
      `${label} identity is invalid.`,
    );
  }
  return value;
}

function inconsistentPersistence(): SupplierExtractionProcessorError {
  return new SupplierExtractionProcessorError(
    "PERSISTENCE_STATE_INCONSISTENT",
    "Supplier Extraction persistence state could not be verified safely.",
    "supplier_extraction_persistence_failed",
  );
}
