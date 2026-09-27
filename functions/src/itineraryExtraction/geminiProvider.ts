import {
  GenerateContentParameters,
  GenerateContentResponseUsageMetadata,
  GoogleGenAI,
  Part,
  ThinkingLevel,
} from "@google/genai";
import {
  ItineraryExtractionProvider,
  ItineraryExtractionProviderError,
  ItineraryExtractionProviderInput,
} from "./processor";
import {
  maxTrustedSourceSizeBytes,
  TrustedSupplierSourceFile,
  validateCanonicalStoragePath,
  validSourceIdentity,
} from "./sourceReaderValidation";
import {
  kayraItineraryExtractionPrompt,
  kayraItineraryExtractionPromptVersion,
} from "./geminiProviderPrompt";
import {
  kayraItineraryExtractionResponseSchema,
} from "./geminiProviderSchema";

export const geminiItineraryModel = "gemini-3.5-flash";
export const geminiVertexLocation = "global";

const gcsContentTypes = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
  "text/plain",
]);
const inlineTextContentTypes = new Set(["text/csv"]);

export interface GeminiGenerationResponse {
  readonly text?: string;
  readonly usageMetadata?: GenerateContentResponseUsageMetadata;
}

export interface GeminiGenerationClient {
  generateContent(
    request: GenerateContentParameters,
  ): Promise<GeminiGenerationResponse>;
}

export interface TrustedCsvTextReader {
  readUtf8Csv(file: TrustedSupplierSourceFile): Promise<string>;
}

export type GeminiProviderLog = (
  event: string,
  fields: Record<string, unknown>,
) => void;

export interface GeminiProviderOptions {
  bucketName: string;
  client: GeminiGenerationClient;
  csvTextReader: TrustedCsvTextReader;
  log?: GeminiProviderLog;
}

export function geminiItineraryExtractionProvider(
  options: GeminiProviderOptions,
): ItineraryExtractionProvider {
  const bucketName = requireBucketName(options.bucketName);
  const log = options.log ?? (() => {});
  return {
    async extract(input) {
      try {
        validateProviderInput(input);
        const parts = await sourceParts(
          input,
          bucketName,
          options.csvTextReader,
        );
        const request: GenerateContentParameters = {
          model: geminiItineraryModel,
          contents: [{role: "user", parts}],
          config: {
            systemInstruction: kayraItineraryExtractionPrompt,
            responseMimeType: "application/json",
            responseJsonSchema: kayraItineraryExtractionResponseSchema,
            candidateCount: 1,
            maxOutputTokens: 16_384,
            thinkingConfig: {thinkingLevel: ThinkingLevel.LOW},
          },
        };
        log("itinerary-extraction-provider-requested", safeFields(input));
        const response = await options.client.generateContent(request);
        const text = response.text;
        if (typeof text !== "string" || text.trim().length === 0) {
          throw executionFailure("Gemini returned no usable JSON response.");
        }
        let parsed: unknown;
        try {
          parsed = JSON.parse(text);
        } catch (_) {
          throw executionFailure("Gemini returned invalid JSON.");
        }
        log("itinerary-extraction-provider-completed", {
          ...safeFields(input),
          ...safeUsage(response.usageMetadata),
        });
        return parsed;
      } catch (error) {
        const providerError = error instanceof ItineraryExtractionProviderError ?
          error : executionFailure("Gemini extraction failed.");
        log("itinerary-extraction-provider-failed", {
          ...safeFields(input),
          category: providerError.code,
        });
        throw providerError;
      }
    },
  };
}

export function vertexGeminiGenerationClient(
  projectId: string,
): GeminiGenerationClient {
  if (!validSourceIdentity(projectId)) {
    throw executionFailure("Google Cloud project identity is unavailable.");
  }
  const client = new GoogleGenAI({
    vertexai: true,
    project: projectId,
    location: geminiVertexLocation,
    apiVersion: "v1",
  });
  return {
    generateContent: (request) => client.models.generateContent(request),
  };
}

async function sourceParts(
  input: ItineraryExtractionProviderInput,
  bucketName: string,
  csvTextReader: TrustedCsvTextReader,
): Promise<Part[]> {
  const parts: Part[] = [];
  for (let index = 0; index < input.sourcePackage.files.length; index += 1) {
    const file = input.sourcePackage.files[index];
    const label = sourceLabel(
      index,
      input.sourcePackage.packageId,
      file,
    );
    parts.push({text: label});
    if (gcsContentTypes.has(file.contentType)) {
      parts.push({
        fileData: {
          fileUri: privateGcsUri(bucketName, file.storagePath),
          mimeType: file.contentType,
        },
      });
    } else {
      const text = await csvTextReader.readUtf8Csv(file);
      parts.push({text: `UTF-8 SOURCE CONTENT\n${text}`});
    }
    parts.push({text: `END SOURCE FILE ${index + 1}`});
  }
  return parts;
}

function validateProviderInput(input: ItineraryExtractionProviderInput): void {
  const sourcePackage = input.sourcePackage;
  if (sourcePackage.files.length === 0 ||
      sourcePackage.tripId !== input.tripId ||
      !validSourceIdentity(input.tripId) ||
      !validSourceIdentity(sourcePackage.packageId)) {
    throw executionFailure("Trusted Supplier Source package is invalid.");
  }
  for (const file of sourcePackage.files) {
    if (!gcsContentTypes.has(file.contentType) &&
        !inlineTextContentTypes.has(file.contentType)) {
      throw new ItineraryExtractionProviderError(
        "UNSUPPORTED_SOURCE",
        "Supplier Source format is unsupported by this extraction provider.",
      );
    }
  }
  for (const file of sourcePackage.files) {
    if (!validSourceIdentity(file.sourceFileId) ||
        file.packageId !== sourcePackage.packageId ||
        !Number.isSafeInteger(file.sizeBytes) || file.sizeBytes <= 0 ||
        file.sizeBytes > maxTrustedSourceSizeBytes) {
      throw executionFailure("Trusted Supplier Source file is invalid.");
    }
    try {
      validateCanonicalStoragePath(
        file.storagePath,
        input.tripId,
        file.sourceFileId,
      );
    } catch (_) {
      throw executionFailure("Trusted Supplier Source path is invalid.");
    }
  }
}

function sourceLabel(
  index: number,
  packageId: string,
  file: TrustedSupplierSourceFile,
): string {
  return [
    `SOURCE FILE ${index + 1}`,
    `sourcePackageId = ${packageId}`,
    `sourceFileId = ${file.sourceFileId}`,
    `contentType = ${file.contentType}`,
  ].join("\n");
}

function privateGcsUri(bucketName: string, storagePath: string): string {
  return `gs://${bucketName}/${storagePath}`;
}

function requireBucketName(value: string): string {
  if (value.trim() !== value ||
      !/^[a-z0-9][a-z0-9._-]*[a-z0-9]$/.test(value)) {
    throw executionFailure("Firebase Storage bucket identity is invalid.");
  }
  return value;
}

function safeFields(
  input: ItineraryExtractionProviderInput,
): Record<string, unknown> {
  return {
    provider: "vertex-ai-gemini",
    model: geminiItineraryModel,
    promptVersion: kayraItineraryExtractionPromptVersion,
    fileCount: input.sourcePackage.files.length,
    mimeTypes: input.sourcePackage.files.map((file) => file.contentType),
  };
}

function safeUsage(
  usage: GenerateContentResponseUsageMetadata | undefined,
): Record<string, unknown> {
  if (!usage) return {};
  return {
    promptTokenCount: usage.promptTokenCount,
    candidatesTokenCount: usage.candidatesTokenCount,
    thoughtsTokenCount: usage.thoughtsTokenCount,
    totalTokenCount: usage.totalTokenCount,
  };
}

function executionFailure(message: string): ItineraryExtractionProviderError {
  return new ItineraryExtractionProviderError(
    "PROVIDER_EXECUTION_FAILED",
    message,
  );
}
