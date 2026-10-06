import {Timestamp} from "firebase-admin/firestore";
import {FinalizationCapacityBoundary, InvalidFinalizationState} from "./supplierImportFinalization";
import {array} from "./itineraryDraftValidationPrimitives";

export const finalizationPayloadLimits = Object.freeze({canonical: 768 * 1024,
  package_content: 256 * 1024, receipt: 256 * 1024, resolution: 32 * 1024,
  event: 32 * 1024, commit: 2 * 1024 * 1024, inputs: 16 * 1024 * 1024});

export class FinalizationCapacityError extends Error {
  constructor(readonly boundary: FinalizationCapacityBoundary) {
    super("Supplier Import finalization exceeds its application payload budget.");
  }
}

/** Conservative application payload units, NOT an exact Firestore/protobuf or
 * index-size calculator. UTF-8 JSON bytes + per-node/map overhead + document path
 * are measured using public values only. Commit adds 100% reserve plus 4 KiB.
 * Firestore is the final limit; index exemptions remain a deployment prerequisite.
 */
export function finalizationPayloadBytes(value: unknown, path = ""): number {
  let overhead = 128 + Buffer.byteLength(path, "utf8");
  const normalize = (item: unknown, depth: number): unknown => {
    if (depth > 18) throw new FinalizationCapacityError("nesting");
    overhead += 16;
    if (item instanceof Timestamp) return {seconds: item.seconds, nanoseconds: item.nanoseconds};
    if (item === null || typeof item === "string" || typeof item === "boolean") return item;
    if (typeof item === "number" && Number.isFinite(item)) return item;
    if (Array.isArray(item)) {
      return array(item, "Payload array").map((v) => normalize(v, depth + 1));
    }
    if (!item || typeof item !== "object" || ![Object.prototype, null].includes(Object.getPrototypeOf(item))) throw new InvalidFinalizationState();
    const result: Record<string, unknown> = {};
    for (const key of Reflect.ownKeys(item)) {
      const field = Object.getOwnPropertyDescriptor(item, key);
      if (typeof key !== "string" || !field?.enumerable || !("value" in field)) throw new InvalidFinalizationState();
      overhead += 32;
      Object.defineProperty(result, key, {value: normalize(field.value, depth + 1), enumerable: true});
    }
    return result;
  };
  const normalized = normalize(value, 0);
  return Buffer.byteLength(JSON.stringify(normalized), "utf8") + overhead;
}

export function requireFinalizationBudget(boundary: keyof typeof finalizationPayloadLimits, bytes: number): void {
  if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > finalizationPayloadLimits[boundary]) throw new FinalizationCapacityError(boundary);
}

export class FinalizationInputBudget {
  private bytes = 0;
  add(value: unknown, path = ""): void {
    this.bytes += finalizationPayloadBytes(value, path);
    requireFinalizationBudget("inputs", this.bytes);
  }
}

export function checkFinalizationWriteBudgets(writes: Readonly<{
  canonical: {path: string; data: Record<string, unknown>};
  receipt: {path: string; data: Record<string, unknown>};
  resolution: {path: string; data: Record<string, unknown>};
  event: {path: string; data: Record<string, unknown>};
}>): void {
  requireFinalizationBudget("package_content", finalizationPayloadBytes(writes.canonical.data.packageContent));
  let sum = 0;
  for (const key of ["canonical", "receipt", "resolution", "event"] as const) {
    const bytes = finalizationPayloadBytes(writes[key].data, writes[key].path);
    requireFinalizationBudget(key, bytes);
    sum += bytes;
  }
  requireFinalizationBudget("commit", 2 * sum + 4096);
}

export function isFirestoreCapacityError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const {code, message} = error as {code?: unknown; message?: unknown};
  if (([8, "8", "resource-exhausted", "RESOURCE_EXHAUSTED"] as unknown[]).includes(code)) return true;
  return ([3, "3", "invalid-argument", "INVALID_ARGUMENT"] as unknown[]).includes(code) && typeof message === "string" &&
    /(?:document|request|transaction).*(?:too large|maximum.*size|exceeds.*(?:size|limit))|maximum.*(?:document|request).*size/iu.test(message);
}
