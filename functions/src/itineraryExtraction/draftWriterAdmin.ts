import {FieldValue, Firestore} from "firebase-admin/firestore";
import {DraftBoundaryError, DraftRecord} from "./draftValidation";
import {DraftCreateData, DraftWriterDependencies} from "./draftWriter";

export function adminDraftWriterDependencies(
  db: Firestore,
): DraftWriterDependencies {
  return {
    async createDraft(tripId, data) {
      const trip = db.doc(`trips/${tripId}`);
      const draft = trip.collection("itinerary_drafts").doc();
      return db.runTransaction(async (transaction) => {
        const tripSnapshot = await transaction.get(trip);
        if (!tripSnapshot.exists) {
          throw new DraftBoundaryError(
            "DRAFT_PERSISTENCE_FAILED",
            "Parent Trip does not exist.",
          );
        }
        transaction.create(draft, withServerTimestamps(data));
        return draft.id;
      });
    },
  };
}

function withServerTimestamps(data: DraftCreateData): DraftRecord {
  return {
    ...data,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}
