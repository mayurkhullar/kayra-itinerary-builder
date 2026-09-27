import {FieldValue, Firestore} from "firebase-admin/firestore";
import {ExtractionRequestDependencies} from "./request";
import {
  ExtractionRequestContext,
  ExtractionRequestInput,
  requireExtractionContext,
} from "./requestValidation";

export function adminExtractionRequestDependencies(
  db: Firestore,
): ExtractionRequestDependencies {
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
        const status = snapshot.data().status;
        return status === "queued" || status === "processing";
      });
      if (active) {
        return {
          jobId: active.id,
          status: active.data().status as "queued" | "processing",
          createdNew: false,
        };
      }

      const job = jobs.doc();
      transaction.create(job, queuedJobData(input, uid));
      return {jobId: job.id, status: "queued", createdNew: true};
    }),
  };
}

function queuedJobData(
  input: ExtractionRequestInput,
  uid: string,
): Record<string, unknown> {
  return {
    tripId: input.tripId,
    sourcePackageId: input.sourcePackageId,
    status: "queued",
    requestedByUid: uid,
    resultingDraftId: null,
    failureCode: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}
