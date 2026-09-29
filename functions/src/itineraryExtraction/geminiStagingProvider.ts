import {
  ApiError,
  Candidate,
  FinishReason,
  GenerateContentParameters,
  GenerateContentResponseUsageMetadata,
  GoogleGenAI,
  ModalityTokenCount,
  Part,
  ThinkingLevel,
} from "@google/genai";
import {
  kayraSupplierExtractionV3Prompt,
  kayraSupplierExtractionV3PromptVersion,
} from "./geminiStagingProviderPrompt";
import {
  kayraSupplierExtractionV3ResponseSchema,
} from "./geminiStagingProviderSchema";
import {
  ProviderSupplierExtractionV3,
  validateProviderSupplierExtractionV3,
} from "./providerSupplierExtractionV3";
import {
  ItineraryExtractionProviderError,
  ItineraryExtractionProviderInput,
} from "./processor";
import {
  maxTrustedSourceSizeBytes,
  TrustedSupplierSourceFile,
  validateCanonicalStoragePath,
  validSourceIdentity,
} from "./sourceReaderValidation";

export const geminiStagingModel = "gemini-3.5-flash";
export const geminiStagingVertexLocation = "global";
export const geminiStagingVertexApiVersion = "v1";

const privateGcsContentTypes = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
  "text/plain",
]);
const boundedTextContentTypes = new Set(["text/csv"]);

export interface GeminiStagingGenerationResponse {
  readonly text?: string;
  readonly candidates?: readonly Candidate[];
  readonly usageMetadata?: GenerateContentResponseUsageMetadata;
}

export interface GeminiStagingGenerationClient {
  generateContent(
    request: GenerateContentParameters,
  ): Promise<GeminiStagingGenerationResponse>;
}

export interface GeminiStagingCsvTextReader {
  readUtf8Csv(file: TrustedSupplierSourceFile): Promise<string>;
}

export type GeminiStagingProviderLog = (
  event: string,
  fields: Record<string, unknown>,
) => void;

export interface GeminiStagingProviderOptions {
  bucketName: string;
  client: GeminiStagingGenerationClient;
  csvTextReader: GeminiStagingCsvTextReader;
  log?: GeminiStagingProviderLog;
}

export interface SupplierExtractionStagingProvider {
  extract(
    input: ItineraryExtractionProviderInput,
  ): Promise<ProviderSupplierExtractionV3>;
}

export type GeminiStagingProviderFailureReason =
  "unsupported_source" |
  "provider_execution" |
  "empty_response" |
  "incomplete_response" |
  "malformed_json" |
  "invalid_v3_response";

export class GeminiStagingProviderError extends
  ItineraryExtractionProviderError {
  constructor(
    code: "UNSUPPORTED_SOURCE" | "PROVIDER_EXECUTION_FAILED",
    readonly reason: GeminiStagingProviderFailureReason,
    message: string,
  ) {
    super(code, message);
    this.name = "GeminiStagingProviderError";
  }
}

export function geminiSupplierExtractionStagingProvider(
  options: GeminiStagingProviderOptions,
): SupplierExtractionStagingProvider {
  const bucketName = requireBucketName(options.bucketName);
  const log = options.log ?? (() => {});
  return {
    async extract(input) {
      let providerStartedAt: number | null = null;
      try {
        validateProviderInput(input);
        const parts = await sourceParts(
          input,
          bucketName,
          options.csvTextReader,
        );
        const request: GenerateContentParameters = {
          model: geminiStagingModel,
          contents: [{role: "user", parts}],
          config: {
            systemInstruction: kayraSupplierExtractionV3Prompt,
            responseMimeType: "application/json",
            responseJsonSchema: kayraSupplierExtractionV3ResponseSchema,
            candidateCount: 1,
            maxOutputTokens: 16_384,
            thinkingConfig: {thinkingLevel: ThinkingLevel.LOW},
          },
        };
        providerStartedAt = performance.now();
        log("supplier-extraction-v3-provider-requested", {
          ...safeFields(input),
          providerStartedAt: new Date().toISOString(),
        });
        const response = await options.client.generateContent(request);
        const providerDurationMs = elapsedMilliseconds(providerStartedAt);
        const text = response.text;
        const finishReason = response.candidates?.[0]?.finishReason ?? null;
        log("supplier-extraction-v3-provider-completed", {
          ...safeFields(input),
          providerDurationMs,
          candidateCount: response.candidates?.length ?? null,
          finishReason,
          ...safeUsage(response.usageMetadata),
          ...(finishReason === FinishReason.MAX_TOKENS &&
              typeof text === "string" ? truncatedResponseDiagnostics(text) : {}),
        });
        if (typeof text !== "string" || text.trim().length === 0) {
          throw stagingFailure(
            "empty_response",
            "Gemini returned no usable structured response.",
          );
        }
        if (finishReason !== FinishReason.STOP) {
          throw stagingFailure(
            "incomplete_response",
            "Gemini response did not finish successfully.",
          );
        }
        let parsed: unknown;
        try {
          parsed = JSON.parse(text);
        } catch (_) {
          throw stagingFailure(
            "malformed_json",
            "Gemini returned malformed structured JSON.",
          );
        }
        try {
          return validateProviderSupplierExtractionV3(
            parsed,
            input.sourcePackage,
          );
        } catch (_) {
          throw stagingFailure(
            "invalid_v3_response",
            "Gemini response did not match the V3 staging contract.",
          );
        }
      } catch (error) {
        const providerError = error instanceof GeminiStagingProviderError ?
          error : stagingFailure(
            "provider_execution",
            "Gemini staging extraction failed.",
          );
        log("supplier-extraction-v3-provider-failed", {
          ...safeFields(input),
          category: providerError.code,
          reason: providerError.reason,
          providerDurationMs: providerStartedAt === null ?
            null : elapsedMilliseconds(providerStartedAt),
          ...safeProviderFailureMetadata(error),
        });
        throw providerError;
      }
    },
  };
}

export function vertexGeminiStagingGenerationClient(
  projectId: string,
): GeminiStagingGenerationClient {
  if (!validSourceIdentity(projectId)) {
    throw stagingFailure(
      "provider_execution",
      "Google Cloud project identity is unavailable.",
    );
  }
  const client = new GoogleGenAI({
    vertexai: true,
    project: projectId,
    location: geminiStagingVertexLocation,
    apiVersion: geminiStagingVertexApiVersion,
  });
  return {
    generateContent: (request) => client.models.generateContent(request),
  };
}

async function sourceParts(
  input: ItineraryExtractionProviderInput,
  bucketName: string,
  csvTextReader: GeminiStagingCsvTextReader,
): Promise<Part[]> {
  const parts: Part[] = [];
  for (let index = 0; index < input.sourcePackage.files.length; index += 1) {
    const file = input.sourcePackage.files[index];
    const mode = inputMode(file.contentType);
    parts.push({text: sourceLabel(index, file.contentType, mode)});
    if (mode === "private-gcs-uri") {
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
    throw stagingFailure(
      "provider_execution",
      "Trusted Supplier Source package is invalid.",
    );
  }
  for (const file of sourcePackage.files) {
    if (!privateGcsContentTypes.has(file.contentType) &&
        !boundedTextContentTypes.has(file.contentType)) {
      throw new GeminiStagingProviderError(
        "UNSUPPORTED_SOURCE",
        "unsupported_source",
        "Supplier Source format is unsupported by this staging provider.",
      );
    }
  }
  for (const file of sourcePackage.files) {
    if (!validSourceIdentity(file.sourceFileId) ||
        file.packageId !== sourcePackage.packageId ||
        !Number.isSafeInteger(file.sizeBytes) || file.sizeBytes <= 0 ||
        file.sizeBytes > maxTrustedSourceSizeBytes) {
      throw stagingFailure(
        "provider_execution",
        "Trusted Supplier Source file is invalid.",
      );
    }
    try {
      validateCanonicalStoragePath(
        file.storagePath,
        input.tripId,
        file.sourceFileId,
      );
    } catch (_) {
      throw stagingFailure(
        "provider_execution",
        "Trusted Supplier Source path is invalid.",
      );
    }
  }
}

function sourceLabel(index: number, contentType: string, mode: string): string {
  return [
    `SOURCE FILE ${index + 1}`,
    `fileIndex = ${index + 1}`,
    `contentType = ${contentType}`,
    `inputMode = ${mode}`,
  ].join("\n");
}

function inputMode(contentType: string): string {
  return boundedTextContentTypes.has(contentType) ?
    "bounded-inline-text" : "private-gcs-uri";
}

function privateGcsUri(bucketName: string, storagePath: string): string {
  return `gs://${bucketName}/${storagePath}`;
}

function requireBucketName(value: string): string {
  if (value.trim() !== value ||
      !/^[a-z0-9][a-z0-9._-]*[a-z0-9]$/.test(value)) {
    throw stagingFailure(
      "provider_execution",
      "Firebase Storage bucket identity is invalid.",
    );
  }
  return value;
}

function safeFields(
  input: ItineraryExtractionProviderInput,
): Record<string, unknown> {
  return {
    provider: "vertex-ai-gemini",
    model: geminiStagingModel,
    promptVersion: kayraSupplierExtractionV3PromptVersion,
    fileCount: input.sourcePackage.files.length,
    mimeTypes: input.sourcePackage.files.map((file) => file.contentType),
    fileSizesBytes: input.sourcePackage.files.map((file) => file.sizeBytes),
    totalSourceBytes: input.sourcePackage.files.reduce(
      (total, file) => total + file.sizeBytes,
      0,
    ),
    inputModes: input.sourcePackage.files.map((file) =>
      inputMode(file.contentType)),
    thinkingLevel: ThinkingLevel.LOW,
  };
}

function safeUsage(
  usage: GenerateContentResponseUsageMetadata | undefined,
): Record<string, unknown> {
  if (!usage) return {};
  return {
    cacheTokensDetails: safeTokenDetails(usage.cacheTokensDetails),
    promptTokenCount: usage.promptTokenCount,
    promptTokensDetails: safeTokenDetails(usage.promptTokensDetails),
    candidatesTokenCount: usage.candidatesTokenCount,
    candidatesTokensDetails: safeTokenDetails(usage.candidatesTokensDetails),
    thoughtsTokenCount: usage.thoughtsTokenCount,
    cachedContentTokenCount: usage.cachedContentTokenCount,
    toolUsePromptTokenCount: usage.toolUsePromptTokenCount,
    toolUsePromptTokensDetails: safeTokenDetails(
      usage.toolUsePromptTokensDetails,
    ),
    totalTokenCount: usage.totalTokenCount,
    trafficType: usage.trafficType,
  };
}

function safeTokenDetails(
  details: ModalityTokenCount[] | undefined,
): readonly Record<string, unknown>[] | undefined {
  return details?.map((detail) => ({
    modality: detail.modality,
    tokenCount: detail.tokenCount,
  }));
}

function elapsedMilliseconds(startedAt: number): number {
  return Math.max(0, Math.round(performance.now() - startedAt));
}

const diagnosticJsonKeys = [
  ["days", "keyCountDays"],
  ["services", "keyCountServices"],
  ["unassignedServices", "keyCountUnassignedServices"],
  ["packageFacts", "keyCountPackageFacts"],
  ["ancillaryFacts", "keyCountAncillaryFacts"],
  ["reviewIssues", "keyCountReviewIssues"],
  ["commercialContent", "keyCountCommercialContent"],
  ["type", "keyCountType"],
  ["hotelDetails", "keyCountHotelDetails"],
  ["transferDetails", "keyCountTransferDetails"],
  ["activityDetails", "keyCountActivityDetails"],
  ["sources", "keyCountSources"],
] as const;

function truncatedResponseDiagnostics(text: string): Record<string, unknown> {
  let responseCharacterCount = 0;
  for (const _character of text) responseCharacterCount += 1;
  const fields: Record<string, unknown> = {
    responseUtf8Bytes: Buffer.byteLength(text, "utf8"),
    responseCharacterCount,
    startsWithObjectBrace: boundaryCharacter(text, true) === "{",
    endsWithObjectBrace: boundaryCharacter(text, false) === "}",
  };
  const counts = countFixedJsonObjectKeys(text);
  for (let index = 0; index < diagnosticJsonKeys.length; index += 1) {
    fields[diagnosticJsonKeys[index][1]] = counts[index];
  }
  return fields;
}

function countFixedJsonObjectKeys(text: string): readonly number[] {
  const counts = diagnosticJsonKeys.map(() => 0);
  let inString = false;
  let escaped = false;
  let stringLength = 0;
  let matches = diagnosticJsonKeys.map(() => false);

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (!inString) {
      if (character === "\"") {
        inString = true;
        escaped = false;
        stringLength = 0;
        matches = diagnosticJsonKeys.map(() => true);
      }
      continue;
    }
    if (escaped) {
      escaped = false;
      matches.fill(false);
      stringLength += 1;
      continue;
    }
    if (character === "\\") {
      escaped = true;
      matches.fill(false);
      continue;
    }
    if (character !== "\"") {
      for (let keyIndex = 0; keyIndex < diagnosticJsonKeys.length; keyIndex += 1) {
        if (matches[keyIndex] &&
            diagnosticJsonKeys[keyIndex][0][stringLength] !== character) {
          matches[keyIndex] = false;
        }
      }
      stringLength += 1;
      continue;
    }

    let following = index + 1;
    while (following < text.length && isJsonWhitespace(text[following])) {
      following += 1;
    }
    if (text[following] === ":") {
      for (let keyIndex = 0; keyIndex < diagnosticJsonKeys.length; keyIndex += 1) {
        if (matches[keyIndex] &&
            stringLength === diagnosticJsonKeys[keyIndex][0].length) {
          counts[keyIndex] += 1;
        }
      }
    }
    inString = false;
  }
  return counts;
}

function boundaryCharacter(text: string, fromStart: boolean): string | null {
  let index = fromStart ? 0 : text.length - 1;
  const end = fromStart ? text.length : -1;
  while (index !== end) {
    if (!isJsonWhitespace(text[index])) return text[index];
    index += fromStart ? 1 : -1;
  }
  return null;
}

function isJsonWhitespace(value: string): boolean {
  return value === " " || value === "\t" || value === "\n" || value === "\r";
}

const safeRpcStatuses = [
  "INVALID_ARGUMENT",
  "UNAUTHENTICATED",
  "PERMISSION_DENIED",
  "NOT_FOUND",
  "RESOURCE_EXHAUSTED",
  "ABORTED",
  "INTERNAL",
  "UNAVAILABLE",
  "DEADLINE_EXCEEDED",
] as const;

const safeNetworkCodes = [
  "ECONNRESET",
  "ECONNREFUSED",
  "ENOTFOUND",
  "EAI_AGAIN",
  "ETIMEDOUT",
] as const;

const safeErrorNames = new Set([
  "ApiError",
  "APIConnectionError",
  "APIConnectionTimeoutError",
  "BadRequestError",
  "AuthenticationError",
  "PermissionDeniedError",
  "NotFoundError",
  "RateLimitError",
  "InternalServerError",
  "GoogleGenAiError",
  "RequestTimeoutError",
  "ConnectionError",
  "UnexpectedClientError",
  "GeminiStagingProviderError",
  "Error",
]);

function safeProviderFailureMetadata(error: unknown): Record<string, unknown> {
  const errorName = safeErrorName(error);
  const httpStatus = safeHttpStatus(error);
  const errorCode = safeErrorCode(error);
  const rpcStatus = safeRpcStatus([
    safeStringProperty(error, "status"),
    safeStringProperty(error, "reason"),
    errorCode,
    safeStringProperty(error, "message"),
  ]) ?? rpcStatusForHttpStatus(httpStatus);
  const fields: Record<string, unknown> = {
    providerErrorName: errorName,
    providerFailureCategory: providerFailureCategory(
      rpcStatus,
      httpStatus,
      errorCode,
      errorName,
    ),
  };
  if (httpStatus !== null) fields.providerHttpStatus = httpStatus;
  if (rpcStatus !== null) fields.providerRpcStatus = rpcStatus;
  if (errorCode !== null) fields.providerErrorCode = errorCode;
  return fields;
}

function safeErrorName(error: unknown): string {
  const name = safeStringProperty(error, "name");
  return name !== null && safeErrorNames.has(name) ? name : "unknown";
}

function safeHttpStatus(error: unknown): number | null {
  const apiStatus = error instanceof ApiError ? error.status : null;
  for (const candidate of [
    apiStatus,
    safeNumberProperty(error, "statusCode"),
    safeNumberProperty(error, "status"),
  ]) {
    if (candidate !== null && Number.isInteger(candidate) &&
        candidate >= 100 && candidate <= 599) {
      return candidate;
    }
  }
  const message = safeStringProperty(error, "message");
  if (message === null) return null;
  const match = message.match(
    /(?:^|\D)(400|401|403|404|408|409|429|500|502|503|504)(?:\D|$)/,
  );
  return match ? Number(match[1]) : null;
}

function safeErrorCode(error: unknown): string | null {
  const code = safeStringProperty(error, "code");
  if (code === null) return null;
  if ((safeNetworkCodes as readonly string[]).includes(code) ||
      (safeRpcStatuses as readonly string[]).includes(code)) {
    return code;
  }
  return null;
}

function safeRpcStatus(values: readonly (string | null)[]):
    typeof safeRpcStatuses[number] | null {
  for (const value of values) {
    if (value === null) continue;
    for (const status of safeRpcStatuses) {
      if (new RegExp(`(?:^|[^A-Z_])${status}(?:[^A-Z_]|$)`, "i").test(value)) {
        return status;
      }
    }
  }
  return null;
}

function rpcStatusForHttpStatus(
  status: number | null,
): typeof safeRpcStatuses[number] | null {
  switch (status) {
    case 400: return "INVALID_ARGUMENT";
    case 401: return "UNAUTHENTICATED";
    case 403: return "PERMISSION_DENIED";
    case 404: return "NOT_FOUND";
    case 408:
    case 504: return "DEADLINE_EXCEEDED";
    case 409: return "ABORTED";
    case 429: return "RESOURCE_EXHAUSTED";
    case 500: return "INTERNAL";
    case 502:
    case 503: return "UNAVAILABLE";
    default: return null;
  }
}

function providerFailureCategory(
  rpcStatus: typeof safeRpcStatuses[number] | null,
  httpStatus: number | null,
  errorCode: string | null,
  errorName: string,
): string {
  if (rpcStatus !== null) return rpcStatus.toLowerCase();
  if (httpStatus !== null) return "http_error";
  if (errorCode !== null) return errorCode === "ETIMEDOUT" ?
    "deadline_exceeded" : "network_error";
  if ([
    "APIConnectionTimeoutError",
    "RequestTimeoutError",
  ].includes(errorName)) return "deadline_exceeded";
  if ([
    "APIConnectionError",
    "ConnectionError",
    "UnexpectedClientError",
  ].includes(errorName)) return "network_error";
  return "unknown";
}

function safeStringProperty(error: unknown, key: string): string | null {
  const value = safeProperty(error, key);
  return typeof value === "string" ? value : null;
}

function safeNumberProperty(error: unknown, key: string): number | null {
  const value = safeProperty(error, key);
  return typeof value === "number" ? value : null;
}

function safeProperty(error: unknown, key: string): unknown {
  if ((typeof error !== "object" && typeof error !== "function") ||
      error === null) return null;
  try {
    return (error as Record<string, unknown>)[key];
  } catch (_) {
    return null;
  }
}

function stagingFailure(
  reason: Exclude<GeminiStagingProviderFailureReason, "unsupported_source">,
  message: string,
): GeminiStagingProviderError {
  return new GeminiStagingProviderError(
    "PROVIDER_EXECUTION_FAILED",
    reason,
    message,
  );
}
