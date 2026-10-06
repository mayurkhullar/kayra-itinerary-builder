import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {logger} from "firebase-functions";
import {onCall} from "firebase-functions/v2/https";
import {cleanupUpload} from "./supplierSources/cleanup";
import {adminCleanupDependencies} from "./supplierSources/cleanupAdmin";
import {requestExtraction} from "./itineraryExtraction/request";
import {
  adminExtractionRequestDependencies,
} from "./itineraryExtraction/requestAdmin";
import {
  handleSupplierImportResolutionMutation,
} from "./itineraryExtraction/supplierImportResolutionMutationCallable";
import {
  applySupplierImportResolutionMutationAdmin,
} from "./itineraryExtraction/supplierImportResolutionMutationAdmin";
import {handleSupplierImportFinalization} from "./itineraryExtraction/supplierImportFinalizationCallable";
import {finalizeSupplierImportAdmin} from "./itineraryExtraction/supplierImportFinalizationAdmin";
export {
  processItineraryExtractionJob,
} from "./itineraryExtraction/trigger";

if (getApps().length === 0) initializeApp();

export const cleanupSupplierSourceUpload = onCall(
  {region: "asia-south2"},
  async (request) => cleanupUpload(
    request,
    () => adminCleanupDependencies(getFirestore(), getStorage().bucket()),
    (event, fields) => logger.info(event, fields),
  ),
);

export const requestItineraryExtraction = onCall(
  {region: "asia-south2"},
  async (request) => requestExtraction(
    request,
    () => adminExtractionRequestDependencies(getFirestore()),
    (event, fields) => logger.info(event, fields),
  ),
);

export const applySupplierImportResolutionMutation = onCall(
  {region: "asia-south2"},
  async (request) => handleSupplierImportResolutionMutation(
    request,
    {
      mutate: (actor, input) => applySupplierImportResolutionMutationAdmin(
        getFirestore(),
        actor,
        input,
        new Date(),
        (event, fields) => logger.info(event, fields),
      ),
    },
    (event, fields) => logger.info(event, fields),
  ),
);

export const finalizeSupplierImport = onCall(
  {region: "asia-south2"},
  async (request) => handleSupplierImportFinalization(
    request,
    {finalize: (actor, input) => finalizeSupplierImportAdmin(getFirestore(), actor, input)},
    (event, fields) => logger.info(event, fields),
  ),
);
