import {
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {DraftCreateData} from "./draftWriter";
import {draftWithServerTimestamps} from "./draftWriterAdmin";
import {
  completedDraftJobUpdate,
  completedSupplierExtractionJobUpdate,
  ExtractionJobRecord,
  failedExtractionJobUpdate,
  parseExtractionJobRecord,
  processingExtractionJobUpdate,
} from "./extractionJob";
import {
  ClaimedExtractionJob,
  ExtractionJobStore,
  ItineraryExtractionProcessorError,
} from "./processor";
import {validSourceIdentity} from "./sourceReaderValidation";

export function adminExtractionJobStore(db: Firestore): ExtractionJobStore {
  return {
    async claimQueuedJob(tripId, jobId, extractionContractVersion) {
      const jobReference = jobDocument(db, tripId, jobId);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(jobReference);
        if (!snapshot.exists) {
          throw new ItineraryExtractionProcessorError(
            "JOB_UNAVAILABLE",
            "Itinerary extraction job does not exist.",
          );
        }
        const {job, record} = requireQueuedJob(
          snapshot.data(),
          tripId,
          jobId,
          extractionContractVersion,
        );
        transaction.update(jobReference, {
          ...processingExtractionJobUpdate(record),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return job;
      });
    },

    async markJobFailed(job, failureCode) {
      const jobReference = jobDocument(db, job.tripId, job.jobId);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(jobReference);
        const record = requireProcessingJob(
          snapshot.data(),
          snapshot.exists,
          job,
        );
        transaction.update(jobReference, {
          ...failedExtractionJobUpdate(record, failureCode),
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
        const record = requireProcessingJob(
          jobSnapshot.data(),
          jobSnapshot.exists,
          job,
        );
        requireDraftIdentity(draftData, job);
        transaction.create(
          draftReference,
          draftWithServerTimestamps(draftData),
        );
        transaction.update(jobReference, {
          ...completedDraftJobUpdate(record, draftReference.id),
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
  extractionContractVersion: ClaimedExtractionJob[
    "extractionContractVersion"
  ],
): {job: ClaimedExtractionJob; record: ExtractionJobRecord} {
  const record = jobRecord(value);
  if (record.status !== "queued" ||
      record.extractionContractVersion !== extractionContractVersion) {
    throw notProcessable();
  }
  return {job: claimedJob(record, tripId, jobId), record};
}

function requireProcessingJob(
  value: unknown,
  exists: boolean,
  expected: ClaimedExtractionJob,
): ExtractionJobRecord {
  if (!exists) throw notProcessable();
  const record = jobRecord(value);
  if (record.status !== "processing") throw notProcessable();
  const actual = claimedJob(record, expected.tripId, expected.jobId);
  if (actual.sourcePackageId !== expected.sourcePackageId ||
      actual.requestedByUid !== expected.requestedByUid ||
      actual.extractionContractVersion !==
        expected.extractionContractVersion ||
      actual.resultType !== expected.resultType ||
      actual.persistenceShape !== expected.persistenceShape) {
    throw notProcessable();
  }
  return record;
}

function claimedJob(
  data: ExtractionJobRecord,
  tripId: string,
  jobId: string,
): ClaimedExtractionJob {
  if (data.tripId !== tripId ||
      !validSourceIdentity(data.sourcePackageId) ||
      !validSourceIdentity(data.requestedByUid)) {
    throw notProcessable();
  }
  return Object.freeze({
    jobId,
    tripId,
    sourcePackageId: data.sourcePackageId,
    requestedByUid: data.requestedByUid,
    extractionContractVersion: data.extractionContractVersion,
    resultType: data.resultType,
    persistenceShape: data.persistenceShape,
  });
}

function jobRecord(value: unknown): ExtractionJobRecord {
  try {
    return parseExtractionJobRecord(value, {
      isTimestamp: (timestamp) => timestamp instanceof Timestamp,
    });
  } catch (_) {
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

/**
 * Builds the strict job update for the future Supplier Extraction final
 * transaction. It performs no Firestore write and is not used by production.
 */
export function supplierExtractionCompletionUpdate(
  job: ExtractionJobRecord,
  resultingExtractionId: string,
): Record<string, unknown> {
  return completedSupplierExtractionJobUpdate(job, resultingExtractionId);
}
