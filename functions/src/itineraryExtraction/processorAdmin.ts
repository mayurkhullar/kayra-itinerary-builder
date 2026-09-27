import {
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {DraftCreateData} from "./draftWriter";
import {draftWithServerTimestamps} from "./draftWriterAdmin";
import {
  ClaimedExtractionJob,
  ExtractionJobStore,
  ItineraryExtractionProcessorError,
} from "./processor";
import {validSourceIdentity} from "./sourceReaderValidation";

const jobFields = [
  "tripId",
  "sourcePackageId",
  "status",
  "requestedByUid",
  "resultingDraftId",
  "failureCode",
  "createdAt",
  "updatedAt",
] as const;

type JobRecord = Record<(typeof jobFields)[number], unknown>;

export function adminExtractionJobStore(db: Firestore): ExtractionJobStore {
  return {
    async claimQueuedJob(tripId, jobId) {
      const jobReference = jobDocument(db, tripId, jobId);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(jobReference);
        if (!snapshot.exists) {
          throw new ItineraryExtractionProcessorError(
            "JOB_UNAVAILABLE",
            "Itinerary extraction job does not exist.",
          );
        }
        const job = requireQueuedJob(snapshot.data(), tripId, jobId);
        transaction.update(jobReference, {
          status: "processing",
          resultingDraftId: null,
          failureCode: null,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return job;
      });
    },

    async markJobFailed(job, failureCode) {
      const jobReference = jobDocument(db, job.tripId, job.jobId);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(jobReference);
        requireProcessingJob(snapshot.data(), snapshot.exists, job);
        transaction.update(jobReference, {
          status: "failed",
          resultingDraftId: null,
          failureCode,
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
    },

    async finalizeCompletedJob(job, draftData) {
      const tripReference = db.doc(`trips/${job.tripId}`);
      const jobReference = jobDocument(db, job.tripId, job.jobId);
      const draftReference = tripReference.collection("itinerary_drafts").doc();
      return db.runTransaction(async (transaction) => {
        const [tripSnapshot, jobSnapshot] = await transaction.getAll(
          tripReference,
          jobReference,
        );
        if (!tripSnapshot.exists) {
          throw new Error("Parent Trip is unavailable.");
        }
        requireProcessingJob(jobSnapshot.data(), jobSnapshot.exists, job);
        requireDraftIdentity(draftData, job);
        transaction.create(
          draftReference,
          draftWithServerTimestamps(draftData),
        );
        transaction.update(jobReference, {
          status: "completed",
          resultingDraftId: draftReference.id,
          failureCode: null,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return draftReference.id;
      });
    },
  };
}

function jobDocument(db: Firestore, tripId: string, jobId: string) {
  if (!validSourceIdentity(tripId) || !validSourceIdentity(jobId)) {
    throw new ItineraryExtractionProcessorError(
      "JOB_UNAVAILABLE",
      "Itinerary extraction job identity is invalid.",
    );
  }
  return db.doc(`trips/${tripId}/itinerary_extraction_jobs/${jobId}`);
}

function requireQueuedJob(
  value: unknown,
  tripId: string,
  jobId: string,
): ClaimedExtractionJob {
  const data = exactJobRecord(value);
  if (data.status !== "queued") {
    throw notProcessable();
  }
  requireUnfinishedOutcome(data);
  return claimedJob(data, tripId, jobId);
}

function requireProcessingJob(
  value: unknown,
  exists: boolean,
  expected: ClaimedExtractionJob,
): void {
  if (!exists) throw notProcessable();
  const data = exactJobRecord(value);
  if (data.status !== "processing") throw notProcessable();
  requireUnfinishedOutcome(data);
  const actual = claimedJob(data, expected.tripId, expected.jobId);
  if (actual.sourcePackageId !== expected.sourcePackageId ||
      actual.requestedByUid !== expected.requestedByUid) {
    throw notProcessable();
  }
}

function claimedJob(
  data: JobRecord,
  tripId: string,
  jobId: string,
): ClaimedExtractionJob {
  if (data.tripId !== tripId ||
      !validSourceIdentity(data.sourcePackageId) ||
      !validSourceIdentity(data.requestedByUid) ||
      !(data.createdAt instanceof Timestamp) ||
      !(data.updatedAt instanceof Timestamp)) {
    throw notProcessable();
  }
  return Object.freeze({
    jobId,
    tripId,
    sourcePackageId: data.sourcePackageId,
    requestedByUid: data.requestedByUid,
  });
}

function exactJobRecord(value: unknown): JobRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw notProcessable();
  }
  const data = value as Record<string, unknown>;
  if (Object.keys(data).length !== jobFields.length ||
      !jobFields.every((field) =>
        Object.prototype.hasOwnProperty.call(data, field))) {
    throw notProcessable();
  }
  return data as JobRecord;
}

function requireUnfinishedOutcome(data: JobRecord): void {
  if (data.resultingDraftId !== null || data.failureCode !== null) {
    throw notProcessable();
  }
}

function requireDraftIdentity(
  draft: DraftCreateData,
  job: ClaimedExtractionJob,
): void {
  if (draft.tripId !== job.tripId ||
      draft.createdByUid !== job.requestedByUid ||
      draft.sourcePackageIds.length !== 1 ||
      draft.sourcePackageIds[0] !== job.sourcePackageId) {
    throw new Error("Draft identity does not match its extraction job.");
  }
}

function notProcessable(): ItineraryExtractionProcessorError {
  return new ItineraryExtractionProcessorError(
    "JOB_NOT_PROCESSABLE",
    "Itinerary extraction job is not processable.",
  );
}
