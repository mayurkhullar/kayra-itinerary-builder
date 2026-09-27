import {HttpsError} from "firebase-functions/v2/https";
import {
  ExtractionRequestAuth,
  ExtractionRequestInput,
  parseExtractionRequestInput,
  requireExtractionAuth,
} from "./requestValidation";

export interface ExtractionRequestResult {
  jobId: string;
  status: "queued" | "processing";
  createdNew: boolean;
}

export interface ExtractionRequestDependencies {
  requestJob(
    uid: string,
    input: ExtractionRequestInput,
  ): Promise<ExtractionRequestResult>;
}

export type ExtractionRequestLog = (
  event: string,
  fields: Record<string, unknown>,
) => void;

export async function requestExtraction(
  request: {auth?: ExtractionRequestAuth; data: unknown},
  dependencies: ExtractionRequestDependencies |
    (() => ExtractionRequestDependencies),
  log: ExtractionRequestLog,
): Promise<ExtractionRequestResult> {
  let stage = "authentication";
  try {
    const uid = requireExtractionAuth(request.auth);
    stage = "input-validation";
    const input = parseExtractionRequestInput(request.data);
    stage = "authorization-and-job-request";
    const services = typeof dependencies === "function" ?
      dependencies() : dependencies;
    const result = await services.requestJob(uid, input);
    log("itinerary-extraction-request-completed", {
      functionName: "requestItineraryExtraction",
      status: result.status,
      createdNew: result.createdNew,
    });
    return result;
  } catch (error) {
    const code = error instanceof HttpsError ? error.code : "internal";
    log("itinerary-extraction-request-rejected", {
      functionName: "requestItineraryExtraction",
      stage,
      code,
    });
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "internal",
      "Itinerary extraction could not be requested. Please try again.",
    );
  }
}
