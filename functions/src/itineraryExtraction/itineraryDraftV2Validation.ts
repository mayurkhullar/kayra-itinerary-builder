import {
  ItineraryDraftImportResult, ItineraryDraftV2,
  itineraryDraftImportPolicies, itineraryDraftV2SchemaVersion,
} from "./itineraryDraftV2";
import {parsePackageContent} from "./itineraryDraftPackageContentValidation";
import {parseReviewIssues, parseTimeline, parseV2Service} from "./itineraryDraftTimelineValidation";
import {
  array, enumValue, exact, identity, immutable, invalid, positiveInteger, text,
  timestamp, unique,
} from "./itineraryDraftValidationPrimitives";

export {ItineraryDraftV2Error} from "./itineraryDraftValidationPrimitives";

/** Pure canonical map boundary, NOT a provider-output or authorization boundary.
 * The future finalizer must establish trustworthy provenance before calling it.
 * id is external document identity; UTC timestamps/date strings are map values,
 * not Firestore Timestamps. No capacity approval for persistence is implied.
 */
export function validateItineraryDraftV2(id: unknown, input: unknown): ItineraryDraftV2 {
  const draftId = identity(id, "Draft");
  const data = exact(input, [
    "tripId", "schemaVersion", "title", "days", "sourcePackageIds", "reviewIssues",
    "createdByUid", "createdAt", "updatedAt", "packageContent", "importResult",
    ...(input && typeof input === "object" && Object.prototype.hasOwnProperty.call(input, "unscheduledServices") ? ["unscheduledServices"] : []),
  ], "Itinerary draft v2");
  const schemaVersion = enumValue(data.schemaVersion, [itineraryDraftV2SchemaVersion], "Draft version");
  const imported = importResult(data.importResult);
  const sourcePackageIds = array(data.sourcePackageIds, "Source packages")
    .map((item) => identity(item, "Source package"));
  unique(sourcePackageIds, "Source packages");
  if (!sourcePackageIds.includes(imported.sourcePackageId)) {
    invalid("Source packages must include the imported package.");
  }
  const days = parseTimeline(data.days, sourcePackageIds);
  const unscheduled = Object.prototype.hasOwnProperty.call(data, "unscheduledServices") ?
    {unscheduledServices: array(data.unscheduledServices, "Unscheduled services").map((value) => parseV2Service(value, sourcePackageIds))} : {};
  const reviewIssues = parseReviewIssues(data.reviewIssues);
  const packageContent = parsePackageContent(data.packageContent, imported);
  const ids = [draftId, ...(unscheduled.unscheduledServices ?? []).map((service) => service.id), ...reviewIssues.map((issue) => issue.id)];
  for (const day of days) ids.push(...day.services.map((service) => service.id));
  for (const accommodation of packageContent.accommodations) {
    ids.push(accommodation.id, ...accommodation.options.map((option) => option.id));
  }
  ids.push(...[...packageContent.inclusions, ...packageContent.exclusions, ...packageContent.conditions]
    .map((item) => item.id));
  unique(ids, "Canonical identities across the draft");
  const createdAt = timestamp(data.createdAt, "Created at");
  const updatedAt = timestamp(data.updatedAt, "Updated at");
  if (updatedAt < createdAt) invalid("Updated time cannot precede creation time.");
  return immutable({
    id: draftId, tripId: identity(data.tripId, "Trip"), schemaVersion,
    title: text(data.title, "Itinerary title"), days, ...unscheduled, sourcePackageIds, reviewIssues,
    createdByUid: identity(data.createdByUid, "Creator"), createdAt, updatedAt,
    packageContent, importResult: imported,
  });
}

function importResult(input: unknown): ItineraryDraftImportResult {
  const data = exact(input, [
    "extractionId", "resolutionId", "evaluatedRevision", "sourcePackageId", "finalizationId", "policyVersion",
  ], "Import result");
  const extractionId = identity(data.extractionId, "Extraction");
  const resolutionId = identity(data.resolutionId, "Resolution");
  if (resolutionId !== extractionId) invalid("Resolution identity must equal extraction identity.");
  const finalizationId = identity(data.finalizationId, "Finalization");
  if (finalizationId.length > 128) invalid("Finalization command identity is too long.");
  return {
    extractionId, resolutionId,
    evaluatedRevision: positiveInteger(data.evaluatedRevision, "Evaluated revision"),
    sourcePackageId: identity(data.sourcePackageId, "Imported source package"), finalizationId,
    policyVersion: enumValue(data.policyVersion, itineraryDraftImportPolicies, "Import policy"),
  };
}

export const itineraryDraftV2FromMap = validateItineraryDraftV2;

/** A plain transport map, not a Firestore encoder. Dates are deliberately
 * converted here; the future persistence layer retains legacy Timestamp fields.
 * The result is detached and frozen, with stable key insertion/array ordering.
 */
export function itineraryDraftV2ToMap(draft: ItineraryDraftV2): Readonly<Record<string, unknown>> {
  // Revalidate so a structurally forged typed object cannot serialize unknown
  // fields or invalid values. Validation also fixes object-key ordering.
  const normalized = validateItineraryDraftV2(draft.id, mapData(draft));
  return immutable(mapData(normalized));
}

function mapData(draft: ItineraryDraftV2): Record<string, unknown> {
  const {id, ...data} = draft;
  return {
    ...data,
    createdAt: timestampMap(draft.createdAt), updatedAt: timestampMap(draft.updatedAt),
    ...(draft.unscheduledServices === undefined ? {} : {unscheduledServices: draft.unscheduledServices.map(serviceMap)}),
    days: draft.days.map((day) => ({
      ...day, date: dateMap(day.date),
      services: day.services.map(serviceMap),
    })),
  };
}

export function serializeItineraryDraftV2(draft: ItineraryDraftV2): string {
  return JSON.stringify(itineraryDraftV2ToMap(draft));
}

function timestampMap(value: Date): string {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) invalid("Invalid domain timestamp.");
  return value.toISOString();
}

function dateMap(value: Date | null): string | null {
  if (value === null) return null;
  const iso = timestampMap(value);
  if (!iso.endsWith("T00:00:00.000Z")) invalid("Timeline date must be UTC midnight.");
  return iso.slice(0, 10);
}

function serviceMap(service: ItineraryDraftV2["days"][number]["services"][number]): object {
  return {...service, hotelDetails: service.hotelDetails === null ? null : {
    ...service.hotelDetails, checkInDate: dateMap(service.hotelDetails.checkInDate),
    checkOutDate: dateMap(service.hotelDetails.checkOutDate),
  }};
}
