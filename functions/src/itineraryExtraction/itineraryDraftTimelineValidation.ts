import type {ItineraryDraftV2Day, ItineraryDraftV2Service, ItineraryDraftV2HotelDetails} from "./itineraryDraftV2";
import type {
  ValidatedActivityDetails, ValidatedReviewIssue, ValidatedSourceReference,
  ValidatedTransferDetails,
} from "./draftValidation";
import {
  array, dateRange, enumValue, exact, identity, invalid, nullablePositiveInteger,
  nullableText, positiveInteger, serviceTypes, sourceLabel, text, timelineDate,
} from "./itineraryDraftValidationPrimitives";

// Reuse V1 value types, not its provider/trusted-package validator. This boundary
// validates canonical maps and internal linkage; it cannot authenticate sources.
export function parseTimeline(
  input: unknown, packageIds: readonly string[],
): readonly ItineraryDraftV2Day[] {
  let previous = 0;
  return array(input, "Days").map((value) => {
    const data = exact(value, ["dayNumber", "date", "title", "summary", "services", "notes"], "Day");
    const dayNumber = positiveInteger(data.dayNumber, "Day number");
    if (dayNumber <= previous) invalid("Days must be in unique ascending day-number order.");
    previous = dayNumber;
    // As in V1, services use array order and positive day numbers may have gaps.
    // Unlike V1's provider validator, canonical V2 rejects unsorted input.
    return {
      dayNumber, date: timelineDate(data.date, "Day date"),
      title: text(data.title, "Day title"), summary: optionalTimelineText(data.summary, "Day summary"),
      services: array(data.services, "Services").map((item) => service(item, packageIds)),
      notes: optionalTimelineText(data.notes, "Day notes"),
    };
  });
}

function service(input: unknown, packageIds: readonly string[]): ItineraryDraftV2Service {
  const data = exactOptional(input, [
    "id", "type", "title", "description", "startTime", "endTime", "location", "city",
    "inclusions", "exclusions", "notes", "hotelDetails", "transferDetails", "activityDetails", "sourceReference",
  ], ["conditions"], "Service");
  const type = enumValue(data.type, serviceTypes, "Service type");
  const hotelDetails = data.hotelDetails === null ? null : hotel(data.hotelDetails);
  const transferDetails = data.transferDetails === null ? null : transfer(data.transferDetails);
  const activityDetails = data.activityDetails === null ? null : activity(data.activityDetails);
  if ((hotelDetails !== null && type !== "hotel") ||
      (transferDetails !== null && type !== "transfer") ||
      (activityDetails !== null && type !== "activity")) {
    invalid("Service type and details are incompatible.");
  }
  return {
    id: identity(data.id, "Service"), type, title: text(data.title, "Service title"),
    description: optionalTimelineText(data.description, "Service description"),
    startTime: optionalTimelineText(data.startTime, "Start time"),
    endTime: optionalTimelineText(data.endTime, "End time"),
    location: optionalTimelineText(data.location, "Location"),
    city: optionalTimelineText(data.city, "City"),
    inclusions: timelineTextList(data.inclusions, "Service inclusions"),
    exclusions: timelineTextList(data.exclusions, "Service exclusions"),
    ...(Object.prototype.hasOwnProperty.call(data, "conditions") ? {conditions: array(data.conditions, "Service conditions").map((value) => {
      const condition = exact(value, ["kind", "value"], "Service condition");
      const kind = enumValue(condition.kind, ["operating_basis", "vehicle", "class", "ticket_scope", "availability", "payment_basis", "guide", "other"], "Condition kind");
      return {kind, value: text(condition.value, "Condition value", kind === "payment_basis")};
    })} : {}),
    notes: optionalTimelineText(data.notes, "Service notes"),
    hotelDetails, transferDetails, activityDetails,
    sourceReference: data.sourceReference === null ? null : source(data.sourceReference, packageIds),
  };
}

function hotel(input: unknown): ItineraryDraftV2HotelDetails {
  const data = exactOptional(input, [
    "hotelName", "checkInDate", "checkOutDate", "roomType", "mealPlan", "numberOfRooms", "supplierStarRating",
  ], ["city", "orSimilar", "nightCount"], "Hotel details");
  const checkInDate = timelineDate(data.checkInDate, "Check-in");
  const checkOutDate = timelineDate(data.checkOutDate, "Check-out");
  dateRange(checkInDate?.toISOString() ?? null, checkOutDate?.toISOString() ?? null);
  return {
    hotelName: text(data.hotelName, "Hotel name"), checkInDate, checkOutDate,
    ...(Object.prototype.hasOwnProperty.call(data, "city") ? {city: nullableText(data.city, "Hotel city")} : {}),
    ...(Object.prototype.hasOwnProperty.call(data, "orSimilar") ? {orSimilar: nullableBoolean(data.orSimilar)} : {}),
    ...(Object.prototype.hasOwnProperty.call(data, "nightCount") ? {nightCount: nullablePositiveInteger(data.nightCount, "Night count")} : {}),
    roomType: optionalTimelineText(data.roomType, "Room type"),
    mealPlan: optionalTimelineText(data.mealPlan, "Meal plan"),
    numberOfRooms: nullablePositiveInteger(data.numberOfRooms, "Room count"),
    supplierStarRating: optionalTimelineText(data.supplierStarRating, "Supplier star rating"),
  };
}

function transfer(input: unknown): ValidatedTransferDetails {
  const data = exact(input, ["pickup", "dropoff", "vehicleType", "transferType"], "Transfer details");
  return {
    pickup: text(data.pickup, "Pickup"), dropoff: text(data.dropoff, "Dropoff"),
    vehicleType: optionalTimelineText(data.vehicleType, "Vehicle type"),
    transferType: data.transferType === null ? null : enumValue(data.transferType,
      ["private", "shared", "scheduled", "other"], "Transfer type"),
  };
}

function activity(input: unknown): ValidatedActivityDetails {
  const data = exact(input, ["activityName", "duration", "activityType"], "Activity details");
  return {
    activityName: text(data.activityName, "Activity name"),
    duration: optionalTimelineText(data.duration, "Duration"),
    activityType: optionalTimelineText(data.activityType, "Activity type"),
  };
}

function source(input: unknown, packageIds: readonly string[]): ValidatedSourceReference {
  const data = exact(input, ["supplierSourcePackageId", "supplierSourceFileId", "sourceLabel"], "Source reference");
  const supplierSourcePackageId = identity(data.supplierSourcePackageId, "Source package");
  if (!packageIds.includes(supplierSourcePackageId)) invalid("Service references an unlisted package.");
  return {
    supplierSourcePackageId,
    supplierSourceFileId: data.supplierSourceFileId === null ? null : identity(data.supplierSourceFileId, "Source file"),
    sourceLabel: sourceLabel(optionalTimelineText(data.sourceLabel, "Source label")),
  };
}

export function parseReviewIssues(input: unknown): readonly ValidatedReviewIssue[] {
  return array(input, "Review issues").map((item) => {
    const data = exact(item, ["id", "fieldPath", "message", "severity"], "Review issue");
    return {
      id: identity(data.id, "Review issue"), fieldPath: text(data.fieldPath, "Review field path"),
      message: text(data.message, "Review message"),
      severity: enumValue(data.severity, ["warning", "blocker"], "Review severity"),
    };
  });
}

// Preserve legacy optional-text trimming and list order/duplicates. Package
// statements are stricter structured facts and never use this blank filtering.
function optionalTimelineText(value: unknown, label: string): string | null {
  if (typeof value === "string" && value.trim() === "") return null;
  return nullableText(value, label);
}

function timelineTextList(value: unknown, label: string): readonly string[] {
  return array(value, label).map((item) => {
    if (typeof item !== "string") invalid(`${label} must contain text.`);
    return item.trim() === "" ? "" : text(item, label);
  }).filter((item) => item !== "");
}

function exactOptional(input: unknown, required: readonly string[], optional: readonly string[], label: string): Record<string, unknown> {
  return exact(input, [...required, ...optional.filter((key) => input !== null && typeof input === "object" && Object.prototype.hasOwnProperty.call(input, key))], label);
}
function nullableBoolean(value: unknown): boolean | null {
  if (value !== null && typeof value !== "boolean") invalid("Or-similar must be boolean or null.");
  return value;
}
