import {Timestamp} from "firebase-admin/firestore";
import {ExtractionJobRecord} from "./extractionJob";

// 900s exceeds the configured 540s processor maximum by six minutes.
// Queue delay gets the same conservative window; neither deadline schedules work.
export const queuedRecoveryWindowMs = 15 * 60 * 1000;
export const processingRecoveryWindowMs = 15 * 60 * 1000;

export function extractionRecoveryDeadline(job: ExtractionJobRecord): Timestamp {
  if (job.status !== "queued" && job.status !== "processing") throw new Error("Job is terminal.");
  if (job.staleAfter instanceof Timestamp) return job.staleAfter;
  if (job.staleAfter !== undefined || !(job.updatedAt instanceof Timestamp)) {
    throw new Error("Invalid extraction recovery deadline.");
  }
  return Timestamp.fromMillis(job.updatedAt.toMillis() +
    (job.status === "queued" ? queuedRecoveryWindowMs : processingRecoveryWindowMs));
}

export function staleExtractionJobUpdate(job: ExtractionJobRecord, now: Timestamp): Record<string, unknown> {
  if (now.toMillis() < extractionRecoveryDeadline(job).toMillis()) throw new Error("Job is not expired.");
  return {
    status: "failed",
    failureCode: job.status === "queued" ? "queued_stale" : "processing_stale",
    staleAfter: null,
    resultingDraftId: null,
    ...(job.persistenceShape === "versioned" ? {resultingExtractionId: null} : {}),
  };
}
