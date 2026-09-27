import {Storage} from "firebase-admin/storage";
import {
  geminiItineraryExtractionProvider,
  GeminiProviderLog,
  TrustedCsvTextReader,
  vertexGeminiGenerationClient,
} from "./geminiProvider";
import {
  ItineraryExtractionProvider,
  ItineraryExtractionProviderError,
} from "./processor";
import {
  maxTrustedSourceSizeBytes,
} from "./sourceReaderValidation";

type Bucket = ReturnType<Storage["bucket"]>;

export interface AdminGeminiProviderOptions {
  projectId?: string;
  log?: GeminiProviderLog;
}

export function adminGeminiItineraryExtractionProvider(
  bucket: Bucket,
  options: AdminGeminiProviderOptions = {},
): ItineraryExtractionProvider {
  const projectId = options.projectId ?? resolveGoogleCloudProjectId();
  return geminiItineraryExtractionProvider({
    bucketName: bucket.name,
    client: vertexGeminiGenerationClient(projectId),
    csvTextReader: adminCsvTextReader(bucket),
    log: options.log,
  });
}

export function resolveGoogleCloudProjectId(
  environment: NodeJS.ProcessEnv = process.env,
): string {
  const direct = environment.GOOGLE_CLOUD_PROJECT ??
    environment.GCLOUD_PROJECT ?? environment.GCP_PROJECT;
  if (direct) return direct;
  const firebaseConfig = environment.FIREBASE_CONFIG;
  if (firebaseConfig) {
    try {
      const parsed = JSON.parse(firebaseConfig) as {projectId?: unknown};
      if (typeof parsed.projectId === "string" && parsed.projectId.length > 0) {
        return parsed.projectId;
      }
    } catch (_) {
      // The sanitized failure below covers malformed runtime configuration.
    }
  }
  throw new ItineraryExtractionProviderError(
    "PROVIDER_EXECUTION_FAILED",
    "Google Cloud project identity is unavailable.",
  );
}

export function adminCsvTextReader(bucket: Bucket): TrustedCsvTextReader {
  return {
    async readUtf8Csv(file) {
      if (file.contentType !== "text/csv") {
        throw new ItineraryExtractionProviderError(
          "PROVIDER_EXECUTION_FAILED",
          "Only validated CSV evidence may use the text reader.",
        );
      }
      let bytes: Uint8Array;
      try {
        const [downloaded] = await bucket.file(file.storagePath).download({
          start: 0,
          end: maxTrustedSourceSizeBytes,
        });
        bytes = downloaded;
      } catch (_) {
        throw new ItineraryExtractionProviderError(
          "PROVIDER_EXECUTION_FAILED",
          "CSV evidence could not be read.",
        );
      }
      if (bytes.byteLength > maxTrustedSourceSizeBytes ||
          bytes.byteLength !== file.sizeBytes) {
        throw new ItineraryExtractionProviderError(
          "PROVIDER_EXECUTION_FAILED",
          "CSV evidence size changed after source validation.",
        );
      }
      try {
        return new TextDecoder("utf-8", {fatal: true}).decode(bytes);
      } catch (_) {
        throw new ItineraryExtractionProviderError(
          "PROVIDER_EXECUTION_FAILED",
          "CSV evidence is not valid UTF-8 text.",
        );
      }
    },
  };
}
