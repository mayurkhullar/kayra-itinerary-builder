import {TrustedSupplierSourcePackage} from "./sourceReaderValidation";

export type DraftBoundaryErrorCode =
  "INVALID_EXTRACTION_RESULT" |
  "DRAFT_PERSISTENCE_FAILED";

export class DraftBoundaryError extends Error {
  constructor(
    readonly code: DraftBoundaryErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "DraftBoundaryError";
  }
}

export type DraftRecord = Record<string, unknown>;

export interface ValidatedDraftPayload {
  title: string;
  days: readonly ValidatedItineraryDay[];
  reviewIssues: readonly ValidatedReviewIssue[];
}

export interface ValidatedItineraryDay {
  dayNumber: number;
  date: Date | null;
  title: string;
  summary: string | null;
  services: readonly ValidatedItineraryService[];
  notes: string | null;
}

export interface ValidatedItineraryService {
  id: string;
  type: ItineraryServiceType;
  title: string;
  description: string | null;
  startTime: string | null;
  endTime: string | null;
  location: string | null;
  city: string | null;
  inclusions: readonly string[];
  exclusions: readonly string[];
  notes: string | null;
  hotelDetails: ValidatedHotelDetails | null;
  transferDetails: ValidatedTransferDetails | null;
  activityDetails: ValidatedActivityDetails | null;
  sourceReference: ValidatedSourceReference | null;
}

export type ItineraryServiceType =
  "hotel" | "transfer" | "activity" | "meal" |
  "sightseeing" | "free_time" | "other";

export interface ValidatedHotelDetails {
  hotelName: string;
  checkInDate: Date | null;
  checkOutDate: Date | null;
  roomType: string | null;
  mealPlan: string | null;
  numberOfRooms: number | null;
  supplierStarRating: string | null;
}

export type ItineraryTransferType =
  "private" | "shared" | "scheduled" | "other";

export interface ValidatedTransferDetails {
  pickup: string;
  dropoff: string;
  vehicleType: string | null;
  transferType: ItineraryTransferType | null;
}

export interface ValidatedActivityDetails {
  activityName: string;
  duration: string | null;
  activityType: string | null;
}

export interface ValidatedSourceReference {
  supplierSourcePackageId: string;
  supplierSourceFileId: string | null;
  sourceLabel: string | null;
}

export type ReviewSeverity = "warning" | "blocker";

export interface ValidatedReviewIssue {
  id: string;
  fieldPath: string;
  message: string;
  severity: ReviewSeverity;
}

const rootFields = ["title", "days", "reviewIssues"] as const;
const dayFields = [
  "dayNumber", "date", "title", "summary", "services", "notes",
] as const;
const serviceFields = [
  "id", "type", "title", "description", "startTime", "endTime",
  "location", "city", "inclusions", "exclusions", "notes",
  "hotelDetails", "transferDetails", "activityDetails", "sourceReference",
] as const;
const hotelFields = [
  "hotelName", "checkInDate", "checkOutDate", "roomType", "mealPlan",
  "numberOfRooms", "supplierStarRating",
] as const;
const transferFields = [
  "pickup", "dropoff", "vehicleType", "transferType",
] as const;
const activityFields = ["activityName", "duration", "activityType"] as const;
const sourceReferenceFields = [
  "supplierSourcePackageId", "supplierSourceFileId", "sourceLabel",
] as const;
const reviewIssueFields = ["id", "fieldPath", "message", "severity"] as const;

const serviceTypes = new Set<ItineraryServiceType>([
  "hotel", "transfer", "activity", "meal", "sightseeing", "free_time", "other",
]);
const transferTypes = new Set<ItineraryTransferType>([
  "private", "shared", "scheduled", "other",
]);
const reviewSeverities = new Set<ReviewSeverity>(["warning", "blocker"]);

export function validateDraftPayload(
  input: unknown,
  trustedPackage: TrustedSupplierSourcePackage,
): ValidatedDraftPayload {
  const data = exactRecord(input, rootFields, "itinerary draft");
  const days = requiredArray(data.days, "Itinerary days")
    .map((day) => validateDay(day, trustedPackage));
  days.sort((left, right) => left.dayNumber - right.dayNumber);
  requireUnique(days.map((day) => String(day.dayNumber)), "day numbers");

  const reviewIssues = requiredArray(data.reviewIssues, "Review issues")
    .map(validateReviewIssue);
  requireUnique(reviewIssues.map((issue) => issue.id), "review issue identities");

  return Object.freeze({
    title: requiredText(data.title, "Itinerary title"),
    days: Object.freeze(days),
    reviewIssues: Object.freeze(reviewIssues),
  });
}

function validateDay(
  input: unknown,
  trustedPackage: TrustedSupplierSourcePackage,
): ValidatedItineraryDay {
  const data = exactRecord(input, dayFields, "itinerary day");
  const dayNumber = requiredInteger(data.dayNumber, "Day number");
  if (dayNumber < 1) invalid("Itinerary day number must be positive.");
  const services = requiredArray(data.services, "Itinerary services")
    .map((service) => validateService(service, trustedPackage));
  requireUnique(services.map((service) => service.id), "service identities");
  return Object.freeze({
    dayNumber,
    date: optionalDateOnly(data.date, "Itinerary day date"),
    title: requiredText(data.title, "Day title"),
    summary: optionalText(data.summary, "Day summary"),
    services: Object.freeze(services),
    notes: optionalText(data.notes, "Day notes"),
  });
}

function validateService(
  input: unknown,
  trustedPackage: TrustedSupplierSourcePackage,
): ValidatedItineraryService {
  const data = exactRecord(input, serviceFields, "itinerary service");
  const type = enumValue(data.type, serviceTypes, "service type");
  const hotelDetails = optionalRecord(
    data.hotelDetails,
    validateHotelDetails,
    "Hotel details",
  );
  const transferDetails = optionalRecord(
    data.transferDetails,
    validateTransferDetails,
    "Transfer details",
  );
  const activityDetails = optionalRecord(
    data.activityDetails,
    validateActivityDetails,
    "Activity details",
  );
  if (hotelDetails !== null && type !== "hotel") {
    invalid("Hotel details require a hotel service.");
  }
  if (transferDetails !== null && type !== "transfer") {
    invalid("Transfer details require a transfer service.");
  }
  if (activityDetails !== null && type !== "activity") {
    invalid("Activity details require an activity service.");
  }
  return Object.freeze({
    id: requiredId(data.id, "Itinerary service"),
    type,
    title: requiredText(data.title, "Service title"),
    description: optionalText(data.description, "Service description"),
    startTime: optionalText(data.startTime, "Service start time"),
    endTime: optionalText(data.endTime, "Service end time"),
    location: optionalText(data.location, "Service location"),
    city: optionalText(data.city, "Service city"),
    inclusions: textList(data.inclusions, "Service inclusions"),
    exclusions: textList(data.exclusions, "Service exclusions"),
    notes: optionalText(data.notes, "Service notes"),
    hotelDetails,
    transferDetails,
    activityDetails,
    sourceReference: optionalRecord(
      data.sourceReference,
      (value) => validateSourceReference(value, trustedPackage),
      "Source reference",
    ),
  });
}

function validateHotelDetails(input: unknown): ValidatedHotelDetails {
  const data = exactRecord(input, hotelFields, "hotel details");
  const checkInDate = optionalDateOnly(data.checkInDate, "Hotel check-in date");
  const checkOutDate = optionalDateOnly(data.checkOutDate, "Hotel check-out date");
  if (checkInDate && checkOutDate && checkOutDate <= checkInDate) {
    invalid("Hotel check-out must follow check-in.");
  }
  const numberOfRooms = optionalInteger(data.numberOfRooms, "Number of rooms");
  if (numberOfRooms !== null && numberOfRooms < 1) {
    invalid("Number of rooms must be positive.");
  }
  return Object.freeze({
    hotelName: requiredText(data.hotelName, "Hotel name"),
    checkInDate,
    checkOutDate,
    roomType: optionalText(data.roomType, "Room type"),
    mealPlan: optionalText(data.mealPlan, "Meal plan"),
    numberOfRooms,
    supplierStarRating: optionalText(
      data.supplierStarRating,
      "Supplier star rating",
    ),
  });
}

function validateTransferDetails(input: unknown): ValidatedTransferDetails {
  const data = exactRecord(input, transferFields, "transfer details");
  return Object.freeze({
    pickup: requiredText(data.pickup, "Pickup"),
    dropoff: requiredText(data.dropoff, "Dropoff"),
    vehicleType: optionalText(data.vehicleType, "Vehicle type"),
    transferType: data.transferType === null ? null :
      enumValue(data.transferType, transferTypes, "transfer type"),
  });
}

function validateActivityDetails(input: unknown): ValidatedActivityDetails {
  const data = exactRecord(input, activityFields, "activity details");
  return Object.freeze({
    activityName: requiredText(data.activityName, "Activity name"),
    duration: optionalText(data.duration, "Activity duration"),
    activityType: optionalText(data.activityType, "Activity type"),
  });
}

function validateSourceReference(
  input: unknown,
  trustedPackage: TrustedSupplierSourcePackage,
): ValidatedSourceReference {
  const data = exactRecord(input, sourceReferenceFields, "source reference");
  const packageId = requiredId(
    data.supplierSourcePackageId,
    "Supplier Source package",
  );
  if (packageId !== trustedPackage.packageId) {
    invalid("Source reference belongs to another Supplier Source package.");
  }
  const sourceFileId = data.supplierSourceFileId === null ? null :
    requiredId(data.supplierSourceFileId, "Supplier Source file");
  if (sourceFileId !== null &&
      !trustedPackage.files.some((file) => file.sourceFileId === sourceFileId)) {
    invalid("Source reference points to an unknown Supplier Source file.");
  }
  return Object.freeze({
    supplierSourcePackageId: packageId,
    supplierSourceFileId: sourceFileId,
    sourceLabel: optionalText(data.sourceLabel, "Source label"),
  });
}

function validateReviewIssue(input: unknown): ValidatedReviewIssue {
  const data = exactRecord(input, reviewIssueFields, "review issue");
  return Object.freeze({
    id: requiredId(data.id, "Review issue"),
    fieldPath: requiredText(data.fieldPath, "Review field path"),
    message: requiredText(data.message, "Review message"),
    severity: enumValue(data.severity, reviewSeverities, "review severity"),
  });
}

function exactRecord<K extends string>(
  value: unknown,
  fields: readonly K[],
  label: string,
): Record<K, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      value instanceof Date) {
    invalid(`${label} must be an object.`);
  }
  const data = value as DraftRecord;
  const keys = Object.keys(data);
  if (keys.length !== fields.length ||
      !fields.every((field) => Object.prototype.hasOwnProperty.call(data, field))) {
    invalid(`${label} fields do not match the itinerary schema.`);
  }
  return data as Record<K, unknown>;
}

function requiredArray(value: unknown, label: string): readonly unknown[] {
  if (!Array.isArray(value)) invalid(`${label} must be an array.`);
  return value;
}

function requiredText(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    invalid(`${label} is required.`);
  }
  return value.trim();
}

function optionalText(value: unknown, label: string): string | null {
  if (value === null) return null;
  if (typeof value !== "string") invalid(`${label} must be text or null.`);
  const normalized = value.trim();
  return normalized.length === 0 ? null : normalized;
}

function requiredId(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0 ||
      value.trim() !== value || value.includes("/") ||
      value === "." || value === "..") {
    invalid(`${label} identity is invalid.`);
  }
  return value;
}

function requiredInteger(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    invalid(`${label} must be an integer.`);
  }
  return value;
}

function optionalInteger(value: unknown, label: string): number | null {
  return value === null ? null : requiredInteger(value, label);
}

function optionalDateOnly(value: unknown, label: string): Date | null {
  if (value === null) return null;
  if (typeof value !== "string") invalid(`${label} must be an ISO date or null.`);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) invalid(`${label} must use YYYY-MM-DD.`);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const result = new Date(Date.UTC(year, month - 1, day));
  if (result.getUTCFullYear() !== year || result.getUTCMonth() !== month - 1 ||
      result.getUTCDate() !== day) {
    invalid(`${label} is not a valid calendar date.`);
  }
  return result;
}

function textList(value: unknown, label: string): readonly string[] {
  const values = requiredArray(value, label);
  const normalized: string[] = [];
  for (const item of values) {
    if (typeof item !== "string") invalid(`${label} must contain only text.`);
    const text = item.trim();
    if (text.length > 0) normalized.push(text);
  }
  return Object.freeze(normalized);
}

function enumValue<T extends string>(
  value: unknown,
  values: ReadonlySet<T>,
  label: string,
): T {
  if (typeof value !== "string" || !values.has(value as T)) {
    invalid(`Unknown ${label}.`);
  }
  return value as T;
}

function optionalRecord<T>(
  value: unknown,
  validator: (value: unknown) => T,
  label: string,
): T | null {
  if (value === null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    invalid(`${label} must be an object or null.`);
  }
  return validator(value);
}

function requireUnique(values: readonly string[], label: string): void {
  if (new Set(values).size !== values.length) {
    invalid(`Duplicate itinerary ${label}.`);
  }
}

function invalid(message: string): never {
  throw new DraftBoundaryError("INVALID_EXTRACTION_RESULT", message);
}
