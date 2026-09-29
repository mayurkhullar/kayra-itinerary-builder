import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {
  ExtractionContractVersion,
  itineraryDraftExtractionContractVersion,
  legacyQueuedExtractionJobData,
  parseExtractionJobRecord,
  resultTypeForExtractionContract,
  versionedQueuedExtractionJobData,
} from "./extractionJob";
import {ExtractionRequestDependencies} from "./request";
import {
  ExtractionRequestContext,
  ExtractionRequestInput,
  requireExtractionContext,
} from "./requestValidation";

export const currentProductionExtractionContractVersion =
  itineraryDraftExtractionContractVersion;

export interface AdminExtractionRequestOptions {
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
    requestJob: (uid, input) => db.runTransaction(async (transaction) => {
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
      const active = attempts.docs.find((snapshot) => {
        const job = parseExtractionJobRecord(snapshot.data(), {
          isTimestamp: (value) => value instanceof Timestamp,
        });
        return job.extractionContractVersion === extractionContractVersion &&
          (job.status === "queued" || job.status === "processing");
      });
      if (active) {
        const activeJob = parseExtractionJobRecord(active.data(), {
          isTimestamp: (value) => value instanceof Timestamp,
        });
        return {
          jobId: active.id,
          status: activeJob.status as "queued" | "processing",
          createdNew: false,
        };
      }

      const job = jobs.doc();
      transaction.create(job, queuedJobData(
        input,
        uid,
        extractionContractVersion,
        persistVersionedContractMetadata,
      ));
      return {jobId: job.id, status: "queued", createdNew: true};
    }),
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
