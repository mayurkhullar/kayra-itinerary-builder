import {containsCommercialTerm, containsCommercialValue} from "./nonCommercialText";

export class ItineraryDraftV2Error extends Error {
  readonly code = "INVALID_ITINERARY_DRAFT_V2";

  constructor(message: string) {
    super(message);
    this.name = "ItineraryDraftV2Error";
  }
}

export function invalid(message: string): never {
  throw new ItineraryDraftV2Error(message);
}

export function exact(
  value: unknown, fields: readonly string[], label: string,
): Record<string, unknown> {
  if (value === null || typeof value !== "object" ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) {
    invalid(`${label} must be a plain map.`);
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== fields.length || keys.some((key) =>
    typeof key !== "string" || !fields.includes(key)) ||
      fields.some((key) => !Object.prototype.hasOwnProperty.call(value, key) ||
        !("value" in Object.getOwnPropertyDescriptor(value, key)!))) {
    invalid(`${label} fields do not match the canonical schema.`);
  }
  return value as Record<string, unknown>;
}

export function array(value: unknown, label: string): unknown[] {
  if (!Array.isArray(value) || Object.keys(value).length !== value.length ||
      Reflect.ownKeys(value).length !== value.length + 1) {
    invalid(`${label} must be a dense array.`);
  }
  for (let i = 0; i < value.length; i++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(i));
    if (!descriptor || !("value" in descriptor)) invalid(`${label} is invalid.`);
  }
  return value;
}

export function identity(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0 || value.trim() !== value ||
      /[/\\\u0000-\u001f\u007f]/u.test(value) || value === "." || value === "..") {
    invalid(`${label} identity is invalid.`);
  }
  return value;
}

export function text(value: unknown, label: string, directPayment = false): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    invalid(`${label} must be non-empty text.`);
  }
  const result = value.trim();
  const terms = directPayment ? result.replace(/\bdirect\s+payment\b/giu, "") : result;
  // Deterministic rejection of known commercial patterns, not a claim that a
  // regex can authenticate prose or replace later publication sanitization.
  if (containsCommercialValue(result) || containsCommercialTerm(terms, true)) {
    invalid(`${label} contains commercial content.`);
  }
  return result;
}

export function nullableText(value: unknown, label: string): string | null {
  return value === null ? null : text(value, label);
}

export function sourceLabel(value: unknown): string | null {
  const label = nullableText(value, "Source label");
  if (label !== null && (label.length > 160 ||
      /(?:[a-z][a-z\d+.-]*:\/\/|^\/|\\|\btrips\/)/iu.test(label))) {
    invalid("Source label must be a short label, not a URL or path.");
  }
  return label;
}

export function positiveInteger(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) {
    invalid(`${label} must be a positive safe integer.`);
  }
  return value;
}

export function nullablePositiveInteger(value: unknown, label: string): number | null {
  return value === null ? null : positiveInteger(value, label);
}

export function enumValue<const T extends string>(
  value: unknown, allowed: readonly T[], label: string,
): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    invalid(`${label} is invalid.`);
  }
  return value as T;
}

export function unique(values: readonly (string | number)[], label: string): void {
  if (new Set(values).size !== values.length) invalid(`${label} must be unique.`);
}

export function dateOnly(value: unknown, label: string): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/u.test(value)) {
    invalid(`${label} must use YYYY-MM-DD.`);
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    invalid(`${label} must be a real calendar date.`);
  }
  return value;
}

export function nullableDateOnly(value: unknown, label: string): string | null {
  return value === null ? null : dateOnly(value, label);
}

export function timelineDate(value: unknown, label: string): Date | null {
  return value === null ? null : new Date(`${dateOnly(value, label)}T00:00:00.000Z`);
}

export function timestamp(value: unknown, label: string): Date {
  if (typeof value !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(value)) {
    invalid(`${label} must be a UTC ISO timestamp.`);
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date.toISOString() !== value) {
    invalid(`${label} must be a valid UTC timestamp.`);
  }
  return date;
}

export function dateRange(start: string | null, end: string | null): void {
  if (start !== null && end !== null && end <= start) {
    invalid("Check-out must follow check-in.");
  }
}

/** Clone before freezing: never freeze caller-owned input or leak mutable Dates. */
export function immutable<T>(value: T): T {
  if (Array.isArray(value)) return Object.freeze(value.map(immutable)) as T;
  if (value !== null && typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value)) {
      if (item instanceof Date) {
        const millis = item.getTime();
        Object.defineProperty(result, key, {
          enumerable: true,
          get: () => Object.freeze(new Date(millis)),
        });
      } else {
        result[key] = immutable(item);
      }
    }
    return Object.freeze(result) as T;
  }
  return value;
}

export const serviceTypes = [
  "hotel", "transfer", "activity", "meal", "sightseeing", "free_time", "other",
] as const;
