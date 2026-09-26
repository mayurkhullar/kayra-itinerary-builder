import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {logger} from "firebase-functions";
import {onCall} from "firebase-functions/v2/https";
import {cleanupUpload} from "./supplierSources/cleanup";
import {adminCleanupDependencies} from "./supplierSources/cleanupAdmin";

if (getApps().length === 0) initializeApp();

export const cleanupSupplierSourceUpload = onCall(
  {region: "asia-south2"},
  async (request) => cleanupUpload(
    request,
    () => adminCleanupDependencies(getFirestore(), getStorage().bucket()),
    (event, fields) => logger.info(event, fields),
  ),
);
