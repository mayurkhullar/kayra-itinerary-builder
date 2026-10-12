import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {
  ExtractionContractVersion,
  itineraryDraftExtractionContractVersion,
  legacyQueuedExtractionJobData,
  parseExtractionJobRecord,
  resultTypeForExtractionContract,
  versionedQueuedExtractionJobData,
} from "./extractionJob";
import {ExtractionRequestDependencies, ExtractionRequestLog} from "./request";
import {extractionRecoveryDeadline, queuedRecoveryWindowMs, staleExtractionJobUpdate} from "./extractionJobRecovery";
import {
  ExtractionRequestContext,
  ExtractionRequestInput,
  requireExtractionContext,
} from "./requestValidation";

export const currentProductionExtractionContractVersion =
  itineraryDraftExtractionContractVersion;

export interface AdminExtractionRequestOptions {
  now?: () => Timestamp;
  log?: ExtractionRequestLog;
  extractionContractVersion?: ExtractionContractVersion;
  persistVersionedContractMetadata?: boolean;
}

export function adminExtractionRequestDependencies(
  db: Firestore,
  options: AdminExtractionRequestOptions = {},
): ExtractionRequestDependencies {
  const extractionContractVersion = options.extractionContractVersion ??
    currentProductionExtractionContractVersion;
  const persistVersionedContractMetadata =
    options.persistVersionedContractMetadata ??
    extractionContractVersion !== itineraryDraftExtractionContractVersion;
  resultTypeForExtractionContract(extractionContractVersion);
  if (!persistVersionedContractMetadata &&
      extractionContractVersion !== itineraryDraftExtractionContractVersion) {
    throw new Error("Only the legacy draft contract may omit metadata.");
  }
  return {
    requestJob: async (uid, input) => {
      const committed = await db.runTransaction(async (transaction) => {
        const trip = db.doc(`trips/${input.tripId}`);
        const profile = db.doc(`users/${uid}`);
        const sourcePackage = trip.collection("supplier_source_packages")
          .doc(input.sourcePackageId);
        const jobs = trip.collection("itinerary_extraction_jobs");

        const [profileSnapshot, tripSnapshot, packageSnapshot] =
          await transaction.getAll(profile, trip, sourcePackage);
        const context: ExtractionRequestContext = {
          profile: profileSnapshot.data() ?? null,
          trip: tripSnapshot.data() ?? null,
          sourcePackage: packageSnapshot.data() ?? null,
        };
        requireExtractionContext(context, uid, input);

        // Query by one automatically indexed field. The transaction gives the
        // authorization reads and active-job check one authoritative snapshot.
        const attempts = await transaction.get(
          jobs.where("sourcePackageId", "==", input.sourcePackageId),
        );
        const active = attempts.docs.map((snapshot) => ({snapshot,
          job: parseExtractionJobRecord(snapshot.data(), {
            isTimestamp: (value) => value instanceof Timestamp,
          }),
        })).filter(({job}) => job.extractionContractVersion === extractionContractVersion &&
          (job.status === "queued" || job.status === "processing"));
        const now = (options.now ?? Timestamp.now)();
        const fresh = active.find(({job}) => now.toMillis() < extractionRecoveryDeadline(job).toMillis());
        if (fresh) return {result: {
          jobId: fresh.snapshot.id,
          status: fresh.job.status as "queued" | "processing",
          createdNew: false,
        }, recovered: []};

        // All reads precede writes. Query conflicts retry this transaction, so a
        // concurrent request sees the replacement instead of creating a second one.
        for (const {snapshot, job} of active) {
          transaction.update(jobs.doc(snapshot.id), {
            ...staleExtractionJobUpdate(job, now),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
        const job = jobs.doc();
        transaction.create(job, {...queuedJobData(
          input,
          uid,
          extractionContractVersion,
          persistVersionedContractMetadata,
        ), staleAfter: Timestamp.fromMillis(now.toMillis() + queuedRecoveryWindowMs)});
        return {result: {jobId: job.id, status: "queued" as const, createdNew: true},
          recovered: active.map(({snapshot, job: old}) => ({
            functionName: "requestItineraryExtraction", tripId: input.tripId,
            oldJobId: snapshot.id, newJobId: job.id, extractionContractVersion,
            priorStatus: old.status,
            failureCode: old.status === "queued" ? "queued_stale" : "processing_stale",
          }))};
      });
      // Log only committed recovery, never speculative transaction retries.
      for (const fields of committed.recovered) {
        options.log?.("itinerary-extraction-stale-active-job-replaced", fields);
      }
      return committed.result;
    },
  };
}

function queuedJobData(
  input: ExtractionRequestInput,
  uid: string,
  extractionContractVersion: ExtractionContractVersion,
  persistVersionedContractMetadata: boolean,
): Record<string, unknown> {
  const timestamps = FieldValue.serverTimestamp();
  const queued = {
    tripId: input.tripId,
    sourcePackageId: input.sourcePackageId,
    requestedByUid: uid,
    createdAt: timestamps,
    updatedAt: timestamps,
  };
  return persistVersionedContractMetadata ?
    versionedQueuedExtractionJobData(queued, extractionContractVersion) :
    legacyQueuedExtractionJobData(queued);
}
