import {FieldValue, Firestore, Transaction} from "firebase-admin/firestore";
import {Storage} from "firebase-admin/storage";
import {HttpsError} from "firebase-functions/v2/https";
import {CleanupDependencies} from "./cleanup";
import {
  CleanupInput, CleanupContext, requireContext, requireObject,
} from "./cleanupValidation";

type Bucket = ReturnType<Storage["bucket"]>;

function errorCode(error: unknown): number | undefined {
  if (!error || typeof error !== "object" || !("code" in error)) return undefined;
  return Number(error.code);
}

export function adminCleanupDependencies(db: Firestore, bucket: Bucket): CleanupDependencies {
  function refs(uid: string, input: CleanupInput) {
    const trip = db.doc(`trips/${input.tripId}`);
    return {
      profile: db.doc(`users/${uid}`), trip,
      package: trip.collection("supplier_source_packages").doc(input.packageId),
      file: trip.collection("supplier_source_files").doc(input.sourceFileId),
    };
  }

  async function readContext(
    reader: Firestore | Transaction, uid: string, input: CleanupInput,
  ): Promise<CleanupContext> {
    const references = refs(uid, input);
    const [profile, trip, sourcePackage, file] = await reader.getAll(
      references.profile, references.trip, references.package, references.file,
    );
    return {
      profile: profile.data() ?? null, trip: trip.data() ?? null,
      package: sourcePackage.data() ?? null, file: file.data() ?? null,
    };
  }

  return {
    readContext: (uid, input) => readContext(db, uid, input),
    async readObject(path) {
      try {
        const [data] = await bucket.file(path).getMetadata();
        return {
          generation: String(data.generation ?? ""),
          metageneration: String(data.metageneration ?? ""),
          metadata: data.metadata ?? {},
        };
      } catch (error) {
        if (errorCode(error) === 404) return null;
        throw error;
      }
    },
    async claimRollback(uid, input, object) {
      return db.runTransaction(async (transaction) => {
        const context = await readContext(transaction, uid, input);
        const uploader = requireContext(context, uid, input);
        requireObject(object, input, uploader);
        // Claim before any deletion. Monotonic package rules prevent completion
        // after this commit; a completion that wins first aborts this transaction.
        if (context.package!.status === "uploading") {
          transaction.update(refs(uid, input).package, {
            status: "failed", updatedAt: FieldValue.serverTimestamp(),
          });
        }
        return uploader;
      });
    },
    async deleteObject(path, object) {
      try {
        await bucket.file(path, {preconditionOpts: {
          ifGenerationMatch: object.generation,
          ifMetagenerationMatch: object.metageneration,
        }}).delete();
        return true;
      } catch (error) {
        if (errorCode(error) === 404) return false;
        if (errorCode(error) === 412) {
          throw new HttpsError("failed-precondition", "Storage object changed during cleanup.");
        }
        throw error;
      }
    },
    async deleteMetadata(uid, input, expectedUploader) {
      return db.runTransaction(async (transaction) => {
        const context = await readContext(transaction, uid, input);
        const uploader = requireContext(context, uid, input);
        if (context.package!.status !== "failed" || uploader !== expectedUploader) {
          throw new HttpsError("failed-precondition", "Package changed during cleanup.");
        }
        if (!context.file) return false;
        transaction.delete(refs(uid, input).file);
        return true;
      });
    },
  };
}
