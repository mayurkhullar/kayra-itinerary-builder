import {DraftBoundaryError, DraftRecord} from "./draftValidation";
import {TrustedSupplierSourcePackage} from "./sourceReaderValidation";

const serviceTypes = new Set([
  "hotel",
  "transfer",
  "activity",
  "meal",
  "sightseeing",
  "free_time",
  "other",
] as const);
const transferTypes = new Set([
  "private",
  "shared",
  "scheduled",
  "other",
] as const);
const reviewSeverities = new Set(["warning", "blocker"] as const);

type ProviderServiceType = typeof serviceTypes extends ReadonlySet<infer T> ?
  T : never;

const rootFields = ["title", "days", "reviewIssues"] as const;
const dayFields = ["date", "title", "summary", "services", "notes"] as const;
const commonServiceFields = [
  "type",
  "title",
  "description",
  "startTime",
  "endTime",
  "location",
  "city",
  "inclusions",
  "exclusions",
  "notes",
  "source",
] as const;
const hotelFields = [
  "hotelName",
  "checkInDate",
  "checkOutDate",
  "roomType",
  "mealPlan",
  "numberOfRooms",
  "supplierStarRating",
] as const;
const transferFields = [
  "pickup",
  "dropoff",
  "vehicleType",
  "transferType",
] as const;
const activityFields = ["activityName", "duration", "activityType"] as const;
const sourceFields = ["fileIndex", "sourceLabel"] as const;
const reviewFields = ["fieldPath", "message", "severity"] as const;

/**
 * Validates the sparse, untrusted v2 provider DTO and expands it into the exact
 * persisted-domain shape. The result still passes through validateDraftPayload
 * before any write is attempted.
 */
export function normalizeItineraryExtractionV2(
  input: unknown,
  trustedPackage: TrustedSupplierSourcePackage,
): DraftRecord {
  const root = sparseRecord(input, rootFields, ["title", "days"], "provider draft");
  const days = requiredArray(root.days, "Provider days").map((value, dayIndex) =>
    normalizeDay(value, dayIndex, trustedPackage));
  const reviewIssues = optionalArray(root, "reviewIssues", "Provider review issues")
    .map((value, issueIndex) => normalizeReviewIssue(value, issueIndex));
  return {
    title: requiredText(root.title, "Provider itinerary title"),
    days,
    reviewIssues,
  };
}

function normalizeDay(
  input: unknown,
  dayIndex: number,
  trustedPackage: TrustedSupplierSourcePackage,
): DraftRecord {
  const day = sparseRecord(input, dayFields, ["title"], "provider day");
  const services = optionalArray(day, "services", "Provider services")
    .map((value, serviceIndex) => normalizeService(
      value,
      dayIndex,
      serviceIndex,
      trustedPackage,
    ));
  return {
    dayNumber: dayIndex + 1,
    date: optionalString(day, "date", "Provider day date"),
    title: requiredText(day.title, "Provider day title"),
    summary: optionalString(day, "summary", "Provider day summary"),
    services,
    notes: optionalString(day, "notes", "Provider day notes"),
  };
}

function normalizeService(
  input: unknown,
  dayIndex: number,
  serviceIndex: number,
  trustedPackage: TrustedSupplierSourcePackage,
): DraftRecord {
  const typeRecord = sparseRecord(input, ["type"], ["type"], "provider service", false);
  const type = enumValue(typeRecord.type, serviceTypes, "provider service type");
  const detailField = type === "hotel" ? "hotelDetails" :
    type === "transfer" ? "transferDetails" :
      type === "activity" ? "activityDetails" : null;
  const allowedFields = detailField === null ? commonServiceFields :
    [...commonServiceFields, detailField];
  const service = sparseRecord(
    input,
    allowedFields,
    ["type"],
    "provider service",
  );

  const hotelDetails = type === "hotel" && has(service, "hotelDetails") ?
    normalizeHotelDetails(service.hotelDetails) : null;
  const transferDetails = type === "transfer" && has(service, "transferDetails") ?
    normalizeTransferDetails(service.transferDetails) : null;
  const activityDetails = type === "activity" && has(service, "activityDetails") ?
    normalizeActivityDetails(service.activityDetails) : null;
  const title = has(service, "title") ?
    requiredText(service.title, "Provider service title") :
    fallbackTitle(type, hotelDetails, transferDetails, activityDetails);

  return {
    id: `service-d${dayIndex + 1}-s${serviceIndex + 1}`,
    type,
    title,
    description: optionalString(service, "description", "Provider service description"),
    startTime: optionalString(service, "startTime", "Provider service start time"),
    endTime: optionalString(service, "endTime", "Provider service end time"),
    location: optionalString(service, "location", "Provider service location"),
    city: optionalString(service, "city", "Provider service city"),
    inclusions: optionalTextArray(service, "inclusions", "Provider inclusions"),
    exclusions: optionalTextArray(service, "exclusions", "Provider exclusions"),
    notes: optionalString(service, "notes", "Provider service notes"),
    hotelDetails,
    transferDetails,
    activityDetails,
    sourceReference: normalizeSourceReference(service, trustedPackage),
  };
}

function normalizeHotelDetails(input: unknown): DraftRecord {
  const details = sparseRecord(
    input,
    hotelFields,
    ["hotelName"],
    "provider hotel details",
  );
  return {
    hotelName: requiredText(details.hotelName, "Provider hotel name"),
    checkInDate: optionalString(details, "checkInDate", "Provider check-in date"),
    checkOutDate: optionalString(details, "checkOutDate", "Provider check-out date"),
    roomType: optionalString(details, "roomType", "Provider room type"),
    mealPlan: optionalString(details, "mealPlan", "Provider meal plan"),
    numberOfRooms: optionalInteger(details, "numberOfRooms", "Provider room count"),
    supplierStarRating: optionalString(
      details,
      "supplierStarRating",
      "Provider supplier star rating",
    ),
  };
}

function normalizeTransferDetails(input: unknown): DraftRecord {
  const details = sparseRecord(
    input,
    transferFields,
    ["pickup", "dropoff"],
    "provider transfer details",
  );
  const transferType = has(details, "transferType") ?
    enumValue(details.transferType, transferTypes, "provider transfer type") : null;
  return {
    pickup: requiredText(details.pickup, "Provider transfer pickup"),
    dropoff: requiredText(details.dropoff, "Provider transfer dropoff"),
    vehicleType: optionalString(details, "vehicleType", "Provider vehicle type"),
    transferType,
  };
}

function normalizeActivityDetails(input: unknown): DraftRecord {
  const details = sparseRecord(
    input,
    activityFields,
    ["activityName"],
    "provider activity details",
  );
  return {
    activityName: requiredText(details.activityName, "Provider activity name"),
    duration: optionalString(details, "duration", "Provider activity duration"),
    activityType: optionalString(details, "activityType", "Provider activity type"),
  };
}

function normalizeSourceReference(
  service: DraftRecord,
  trustedPackage: TrustedSupplierSourcePackage,
): DraftRecord {
  const singleFileId = trustedPackage.files.length === 1 ?
    trustedPackage.files[0].sourceFileId : null;
  if (!has(service, "source")) {
    return {
      supplierSourcePackageId: trustedPackage.packageId,
      supplierSourceFileId: singleFileId,
      sourceLabel: null,
    };
  }
  const source = sparseRecord(
    service.source,
    sourceFields,
    [],
    "provider source reference",
  );
  let sourceFileId = singleFileId;
  if (has(source, "fileIndex")) {
    const fileIndex = requiredInteger(source.fileIndex, "Provider source file index");
    if (fileIndex < 1 || fileIndex > trustedPackage.files.length) {
      invalid("Provider source file index is outside the trusted package.");
    }
    sourceFileId = trustedPackage.files[fileIndex - 1].sourceFileId;
  }
  return {
    supplierSourcePackageId: trustedPackage.packageId,
    supplierSourceFileId: sourceFileId,
    sourceLabel: optionalString(source, "sourceLabel", "Provider source label"),
  };
}

function normalizeReviewIssue(input: unknown, issueIndex: number): DraftRecord {
  const issue = sparseRecord(
    input,
    reviewFields,
    ["fieldPath", "message", "severity"],
    "provider review issue",
  );
  return {
    id: `review-${issueIndex + 1}`,
    fieldPath: requiredText(issue.fieldPath, "Provider review field path"),
    message: requiredText(issue.message, "Provider review message"),
    severity: enumValue(
      issue.severity,
      reviewSeverities,
      "provider review severity",
    ),
  };
}

function fallbackTitle(
  type: ProviderServiceType,
  hotelDetails: DraftRecord | null,
  transferDetails: DraftRecord | null,
  activityDetails: DraftRecord | null,
): string {
  if (type === "hotel") {
    return hotelDetails?.hotelName as string | undefined ?? "Hotel";
  }
  if (type === "transfer") {
    if (transferDetails) {
      return `${transferDetails.pickup} to ${transferDetails.dropoff}`;
    }
    return "Transfer";
  }
  if (type === "activity") {
    return activityDetails?.activityName as string | undefined ?? "Activity";
  }
  return {
    meal: "Meal",
    sightseeing: "Sightseeing",
    free_time: "Free time",
    other: "Other service",
  }[type];
}

function sparseRecord<K extends string>(
  value: unknown,
  allowedFields: readonly K[],
  requiredFields: readonly K[],
  label: string,
  rejectAdditional = true,
): DraftRecord {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      value instanceof Date) {
    invalid(`${label} must be an object.`);
  }
  const record = value as DraftRecord;
  if (rejectAdditional && Object.keys(record).some((key) =>
    !allowedFields.includes(key as K))) {
    invalid(`${label} contains unsupported fields.`);
  }
  if (requiredFields.some((field) => !has(record, field))) {
    invalid(`${label} is missing required fields.`);
  }
  return record;
}

function optionalArray(
  record: DraftRecord,
  field: string,
  label: string,
): readonly unknown[] {
  if (!has(record, field)) return [];
  return requiredArray(record[field], label);
}

function requiredArray(value: unknown, label: string): readonly unknown[] {
  if (!Array.isArray(value)) invalid(`${label} must be an array.`);
  return value;
}

function optionalTextArray(
  record: DraftRecord,
  field: string,
  label: string,
): readonly string[] {
  if (!has(record, field)) return [];
  return requiredArray(record[field], label).map((value) =>
    requiredText(value, label));
}

function optionalString(
  record: DraftRecord,
  field: string,
  label: string,
): string | null {
  if (!has(record, field)) return null;
  return requiredText(record[field], label);
}

function optionalInteger(
  record: DraftRecord,
  field: string,
  label: string,
): number | null {
  if (!has(record, field)) return null;
  return requiredInteger(record[field], label);
}

function requiredText(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    invalid(`${label} must be non-empty text.`);
  }
  return value.trim();
}

function requiredInteger(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    invalid(`${label} must be an integer.`);
  }
  return value;
}

function enumValue<T extends string>(
  value: unknown,
  allowed: ReadonlySet<T>,
  label: string,
): T {
  if (typeof value !== "string" || !allowed.has(value as T)) {
    invalid(`Unknown ${label}.`);
  }
  return value as T;
}

function has(record: DraftRecord, field: string): boolean {
  return Object.prototype.hasOwnProperty.call(record, field);
}

function invalid(message: string): never {
  throw new DraftBoundaryError("INVALID_EXTRACTION_RESULT", message);
}
