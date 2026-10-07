export {concretelyResolves} from "./supplierImportReviewEvidence";
import {permitsReviewOverride, reviewedInterpretationNote, structuralReviewCodes, concretelyResolves} from "./supplierImportReviewEvidence";
import {
  AncillaryFlightFact,
  AncillaryVisaFact,
  PackageAccommodationFact,
  PackageConditionFact,
  PackageStatementFact,
  StagedConditionKind,
  StagedReviewIssue,
  StagedServiceFact,
  StagedServiceType,
  StagedStatementCategory,
  StagedTransferType,
  StagedVisaDisposition,
  SupplierExtractionSnapshot,
  supplierExtractionSnapshotSchemaVersion,
} from "./supplierExtractionSnapshot";
import {
  ActivityOverrides,
  ConsultantDay,
  ConsultantService,
  DayOverrides,
  DayReference,
  DecisionMetadata,
  ExclusionReason,
  FieldOverride,
  FlightDecision,
  FlightOverrides,
  HotelOverrides,
  ManualActivityDetails,
  ManualHotelDetails,
  ManualItemMetadata,
  ManualTransferDetails,
  PackageAccommodationDecision,
  PackageConditionDecision,
  PackageConditionOverrides,
  PackageServiceDestination,
  PackageStatementDecision,
  PackageStatementOverrides,
  ResolutionReference,
  ResolutionCondition,
  ReviewIssueDecision,
  ServiceOverrides,
  ServiceReference,
  SetFieldOverride,
  StagedDayDecision,
  StagedServiceDecision,
  SupplierImportAuditAction,
  SupplierImportAuditDisposition,
  SupplierImportAuditEvent,
  SupplierImportAuditMetadata,
  SupplierImportAuditTargetKind,
  SupplierImportChangedField,
  SupplierImportDecision,
  SupplierImportManualItem,
  SupplierImportResolutionAggregate,
  SupplierImportResolutionRoot,
  TitleDecision,
  TransferOverrides,
  VisaDecision,
  VisaOverrides,
  supplierImportResolutionSchemaVersion,
} from "./supplierImportResolution";
import {validSourceIdentity} from "./sourceReaderValidation";
import {containsCommercialTerm, containsCommercialValue} from "./nonCommercialText";

type RecordValue = Record<string, unknown>;

export class SupplierImportResolutionError extends Error {
  readonly code = "INVALID_SUPPLIER_IMPORT_RESOLUTION";

  constructor(message: string) {
    super(message);
    this.name = "SupplierImportResolutionError";
  }
}

const serviceTypes = values<StagedServiceType>([
  "hotel", "transfer", "activity", "meal", "sightseeing", "free_time", "other",
]);
const transferTypes = values<StagedTransferType>([
  "private", "shared", "scheduled", "other",
]);
const statementCategories = values<StagedStatementCategory>([
  "accommodation", "meal", "guide", "water", "entrance", "transport",
  "visa", "other",
]);
const conditionKinds = values<StagedConditionKind>([
  "operating_basis", "vehicle", "class", "ticket_scope", "availability",
  "payment_basis", "guide", "other",
]);
const visaDispositions = values<StagedVisaDisposition>([
  "included", "excluded", "requirement", "mentioned", "unclear",
]);
const exclusionReasons = values<ExclusionReason>([
  "duplicate", "extracted_in_error", "irrelevant_supplier_content",
  "not_part_of_requested_itinerary", "replaced_by_consultant_content", "other",
]);
const packageDestinations = values<PackageServiceDestination>([
  "service_inclusion", "service_exclusion", "service_notes",
  "transfer_vehicle_type", "transfer_type",
]);
const auditActions = values<SupplierImportAuditAction>([
  "open_review", "set_title_decision", "revert_title_decision",
  "set_day_decision", "set_day_order", "set_service_decision",
  "set_service_order", "set_package_fact_decision", "set_ancillary_decision",
  "set_review_issue_decision", "upsert_manual_day", "remove_manual_day",
  "upsert_manual_service", "remove_manual_service", "revert_decision", "finalize",
]);
const auditTargetKinds = values<SupplierImportAuditTargetKind>([
  "resolution", "title", "day", "service", "package_fact", "ancillary_fact",
  "review_issue", "manual_day", "manual_service", "finalization",
]);
const auditDispositions = values<SupplierImportAuditDisposition>([
  "accept", "override", "retain", "exclude", "map_to_day_service",
  "retain_package_level", "map_to_service", "route_to_flight_workflow",
  "route_to_visa_workflow", "handled_separately", "acknowledged", "resolved",
  "overridden",
]);
const auditChangedFields = values<SupplierImportChangedField>([
  "title", "date", "summary", "notes", "canonicalOrder", "day", "serviceType",
  "description", "startTime", "endTime", "location", "city", "inclusions",
  "exclusions", "hotelName", "orSimilar", "checkInDate", "checkOutDate",
  "nightCount", "roomType", "mealPlan", "numberOfRooms", "supplierStarRating",
  "pickup", "dropoff", "vehicleType", "transferType", "activityName",
  "duration", "activityType", "category", "text", "quantity", "frequency",
  "appliesTo", "kind", "value", "airline", "flightNumber", "origin",
  "destination", "departureDate", "departureTime", "arrivalDate", "arrivalTime",
  "cabinClass", "bookingClass", "conditions", "disposition",
]);

const decisionBaseFields = [
  "decisionId", "decisionKind", "targetEntityId", "lastRevision",
  "updatedByUid", "updatedAt",
] as const;
const exclusionFields = ["exclusionReason", "exclusionNote"] as const;
const hotelOverrideFields = [
  "hotelName", "city", "orSimilar", "checkInDate", "checkOutDate", "nightCount",
  "roomType", "mealPlan", "numberOfRooms", "supplierStarRating",
] as const;

export function validateSupplierImportResolution(
  snapshot: SupplierExtractionSnapshot,
  input: unknown,
): SupplierImportResolutionAggregate {
  const data = strictRecord(input, [
    "root", "decisions", "manualItems", "auditEvents",
  ], ["root", "decisions", "manualItems", "auditEvents"], "resolution aggregate");
  const root = parseRoot(data.root);
  validateRootLinkage(root, snapshot);
  const decisions = array(data.decisions, "Resolution decisions").map(parseDecision);
  const manualItems = array(data.manualItems, "Manual items").map(parseManualItem);
  const auditEvents = array(data.auditEvents, "Audit events").map(parseAuditEvent);

  unique(decisions.map((decision) => decision.decisionId), "decision identities");
  unique(manualItems.map(manualItemId), "manual item identities");
  unique(auditEvents.map((event) => event.eventId), "audit event identities");
  unique(auditEvents.map((event) => event.commandId), "audit command identities");

  const aggregate: SupplierImportResolutionAggregate = {
    root,
    decisions,
    manualItems,
    auditEvents,
  };
  validateRevisions(aggregate);
  validateReferences(snapshot, aggregate);
  return deepFreeze(aggregate);
}

function parseRoot(input: unknown): SupplierImportResolutionRoot {
  const data = exact(input, [
    "schemaVersion", "resolutionId", "tripId", "extractionId", "sourcePackageId",
    "snapshotSchemaVersion", "status", "revision", "createdByUid", "createdAt",
    "updatedByUid", "updatedAt", "finalizedByUid", "finalizedAt",
    "resultingDraftId",
  ], "resolution root");
  if (data.schemaVersion !== supplierImportResolutionSchemaVersion) {
    invalid("Resolution schema version is unsupported.");
  }
  if (data.snapshotSchemaVersion !== supplierExtractionSnapshotSchemaVersion) {
    invalid("Snapshot schema version is unsupported.");
  }
  const status = enumValue(data.status, values(["active", "finalized"]), "status");
  const root: SupplierImportResolutionRoot = {
    schemaVersion: supplierImportResolutionSchemaVersion,
    resolutionId: identity(data.resolutionId, "Resolution"),
    tripId: identity(data.tripId, "Trip"),
    extractionId: identity(data.extractionId, "Extraction"),
    sourcePackageId: identity(data.sourcePackageId, "Source package"),
    snapshotSchemaVersion: supplierExtractionSnapshotSchemaVersion,
    status,
    revision: positiveInteger(data.revision, "Resolution revision"),
    createdByUid: identity(data.createdByUid, "Resolution creator"),
    createdAt: timestamp(data.createdAt, "Resolution creation time"),
    updatedByUid: identity(data.updatedByUid, "Resolution updater"),
    updatedAt: timestamp(data.updatedAt, "Resolution update time"),
    finalizedByUid: nullableIdentity(data.finalizedByUid, "Finalizing user"),
    finalizedAt: nullableTimestamp(data.finalizedAt, "Finalization time"),
    resultingDraftId: nullableIdentity(data.resultingDraftId, "Resulting draft"),
  };
  if (root.resolutionId !== root.extractionId) {
    invalid("Resolution identity must equal extraction identity.");
  }
  if (root.status === "active" &&
      (root.finalizedByUid !== null || root.finalizedAt !== null ||
       root.resultingDraftId !== null)) {
    invalid("Active resolution cannot claim finalization output.");
  }
  if (root.status === "finalized" &&
      (root.finalizedByUid === null || root.finalizedAt === null ||
       root.resultingDraftId === null)) {
    invalid("Finalized resolution requires finalization identities and time.");
  }
  if (root.status === "finalized" && root.revision < 2) {
    invalid("Finalized resolution revision must follow the opening revision.");
  }
  return root;
}

function validateRootLinkage(
  root: SupplierImportResolutionRoot,
  snapshot: SupplierExtractionSnapshot,
): void {
  if (root.tripId !== snapshot.tripId) invalid("Resolution Trip does not match Snapshot.");
  if (root.extractionId !== snapshot.extractionId) {
    invalid("Resolution extraction does not match Snapshot.");
  }
  if (root.sourcePackageId !== snapshot.sourcePackageId) {
    invalid("Resolution source package does not match Snapshot.");
  }
  if (root.snapshotSchemaVersion !== snapshot.schemaVersion) {
    invalid("Resolution Snapshot schema does not match Snapshot.");
  }
}

function parseDecision(input: unknown): SupplierImportDecision {
  const data = record(input, "decision");
  switch (data.decisionKind) {
  case "title": return parseTitleDecision(data);
  case "day": return parseDayDecision(data);
  case "service": return parseServiceDecision(data);
  case "package_accommodation": return parseAccommodationDecision(data);
  case "package_statement": return parsePackageStatementDecision(data);
  case "package_condition": return parsePackageConditionDecision(data);
  case "flight": return parseFlightDecision(data);
  case "visa": return parseVisaDecision(data);
  case "review_issue": return parseReviewDecision(data);
  default: return invalid("Decision kind is unsupported.");
  }
}

function metadata(data: RecordValue): DecisionMetadata {
  return {
    decisionId: identity(data.decisionId, "Decision"),
    targetEntityId: identity(data.targetEntityId, "Decision target"),
    lastRevision: positiveInteger(data.lastRevision, "Decision revision"),
    updatedByUid: identity(data.updatedByUid, "Decision updater"),
    updatedAt: timestamp(data.updatedAt, "Decision update time"),
  };
}

function parseTitleDecision(input: unknown): TitleDecision {
  const data = strictRecord(input,
    [...decisionBaseFields, "disposition", "overrides"],
    [...decisionBaseFields, "disposition", "overrides"], "title decision");
  const disposition = enumValue(
    data.disposition, values(["accept", "override"]), "title disposition",
  );
  const overridesData = strictRecord(data.overrides, ["title"], [], "title overrides");
  const overrides = overridesData.title === undefined ? {} : {
    title: setOverride(overridesData.title, text, "Title override"),
  };
  if (data.decisionId !== "title" || data.targetEntityId !== "title") {
    invalid("Title decision identity is invalid.");
  }
  if ((disposition === "override") !== (overrides.title !== undefined)) {
    invalid("Title override disposition and value must agree.");
  }
  return {...metadata(data), decisionKind: "title", disposition, overrides};
}

function parseDayDecision(input: unknown): StagedDayDecision {
  const data = strictRecord(input,
    [...decisionBaseFields, "disposition", "canonicalOrder", "overrides",
      ...exclusionFields],
    [...decisionBaseFields, "disposition", "overrides", ...exclusionFields],
    "day decision");
  const disposition = enumValue(
    data.disposition, values(["retain", "exclude"]), "day disposition",
  );
  const overrides = parseDayOverrides(data.overrides);
  const exclusion = parseExclusion(data, disposition);
  return {
    ...metadata(data), decisionKind: "day", disposition,
    ...(data.canonicalOrder === undefined ? {} : {
      canonicalOrder: positiveInteger(data.canonicalOrder, "Day order"),
    }),
    overrides, ...exclusion,
  };
}

function parseDayOverrides(input: unknown): DayOverrides {
  const data = strictRecord(input, ["date", "title", "summary", "notes"], [],
    "day overrides");
  return compact({
    date: optionalOverride(data.date, dateText, "Day date"),
    title: optionalSetOverride(data.title, text, "Day title"),
    summary: optionalOverride(data.summary, text, "Day summary"),
    notes: optionalOverride(data.notes, text, "Day notes"),
  });
}

function parseServiceDecision(input: unknown): StagedServiceDecision {
  const data = strictRecord(input,
    [...decisionBaseFields, "disposition", "day", "canonicalOrder", "overrides",
      ...exclusionFields],
    [...decisionBaseFields, "disposition", "overrides", ...exclusionFields],
    "service decision");
  const disposition = enumValue(
    data.disposition, values(["retain", "exclude"]), "service disposition",
  );
  const exclusion = parseExclusion(data, disposition);
  return {
    ...metadata(data), decisionKind: "service", disposition,
    ...(data.day === undefined ? {} : {day: parseDayReference(data.day)}),
    ...(data.canonicalOrder === undefined ? {} : {
      canonicalOrder: positiveInteger(data.canonicalOrder, "Service order"),
    }),
    overrides: parseServiceOverrides(data.overrides), ...exclusion,
  };
}

function parseServiceOverrides(input: unknown): ServiceOverrides {
  const fields = [
    "serviceType", "title", "description", "startTime", "endTime", "location",
    "city", "inclusions", "exclusions", "conditions", "notes", "hotel", "transfer", "activity",
  ];
  const data = strictRecord(input, fields, [], "service overrides");
  return compact({
    serviceType: optionalSetOverride(
      data.serviceType, (value, label) => enumValue(value, serviceTypes, label),
      "Service type",
    ),
    title: optionalSetOverride(data.title, text, "Service title"),
    description: optionalOverride(data.description, text, "Service description"),
    startTime: optionalOverride(data.startTime, timeText, "Service start time"),
    endTime: optionalOverride(data.endTime, timeText, "Service end time"),
    location: optionalOverride(data.location, text, "Service location"),
    city: optionalOverride(data.city, text, "Service city"),
    inclusions: optionalOverride(data.inclusions, textArray, "Service inclusions"),
    exclusions: optionalOverride(data.exclusions, textArray, "Service exclusions"),
    conditions: optionalOverride(data.conditions, conditionArray, "Service conditions"),
    notes: optionalOverride(data.notes, text, "Service notes"),
    hotel: data.hotel === undefined ? undefined : parseHotelOverrides(data.hotel),
    transfer: data.transfer === undefined ? undefined :
      parseTransferOverrides(data.transfer),
    activity: data.activity === undefined ? undefined :
      parseActivityOverrides(data.activity),
  });
}

function parseHotelOverrides(input: unknown): HotelOverrides {
  const data = strictRecord(input, hotelOverrideFields, [], "hotel overrides");
  return compact({
    hotelName: optionalOverride(data.hotelName, text, "Hotel name"),
    city: optionalOverride(data.city, text, "Hotel city"),
    orSimilar: optionalOverride(data.orSimilar, booleanValue, "Or similar"),
    checkInDate: optionalOverride(data.checkInDate, dateText, "Check-in date"),
    checkOutDate: optionalOverride(data.checkOutDate, dateText, "Check-out date"),
    nightCount: optionalOverride(data.nightCount, positiveInteger, "Night count"),
    roomType: optionalOverride(data.roomType, text, "Room type"),
    mealPlan: optionalOverride(data.mealPlan, text, "Meal plan"),
    numberOfRooms: optionalOverride(data.numberOfRooms, positiveInteger,
      "Number of rooms"),
    supplierStarRating: optionalOverride(data.supplierStarRating, text,
      "Supplier star rating"),
  });
}

function parseTransferOverrides(input: unknown): TransferOverrides {
  const data = strictRecord(input,
    ["pickup", "dropoff", "vehicleType", "transferType"], [], "transfer overrides");
  return compact({
    pickup: optionalOverride(data.pickup, text, "Transfer pickup"),
    dropoff: optionalOverride(data.dropoff, text, "Transfer dropoff"),
    vehicleType: optionalOverride(data.vehicleType, text, "Vehicle type"),
    transferType: optionalOverride(
      data.transferType, (value, label) => enumValue(value, transferTypes, label),
      "Transfer type",
    ),
  });
}

function parseActivityOverrides(input: unknown): ActivityOverrides {
  const data = strictRecord(input, ["activityName", "duration", "activityType"], [],
    "activity overrides");
  return compact({
    activityName: optionalOverride(data.activityName, text, "Activity name"),
    duration: optionalOverride(data.duration, text, "Activity duration"),
    activityType: optionalOverride(data.activityType, text, "Activity type"),
  });
}

function parseAccommodationDecision(input: unknown): PackageAccommodationDecision {
  const data = strictRecord(input,
    [...decisionBaseFields, "disposition", "day", "canonicalOrder", "overrides",
      ...exclusionFields],
    [...decisionBaseFields, "disposition", "day", "canonicalOrder", "overrides",
      ...exclusionFields], "package accommodation decision");
  const disposition = enumValue(data.disposition, values([
    "map_to_day_service", "retain_package_level", "exclude",
  ]), "package accommodation disposition");
  const day = data.day === null ? null : parseDayReference(data.day);
  const canonicalOrder = data.canonicalOrder === null ? null :
    positiveInteger(data.canonicalOrder, "Accommodation service order");
  if (disposition === "map_to_day_service" &&
      (day === null || canonicalOrder === null)) {
    invalid("Mapped package accommodation requires day and order.");
  }
  if (disposition !== "map_to_day_service" &&
      (day !== null || canonicalOrder !== null)) {
    invalid("Only mapped package accommodation may name day and order.");
  }
  const exclusion = parseExclusion(data, disposition);
  return {...metadata(data), decisionKind: "package_accommodation", disposition,
    day, canonicalOrder, overrides: parseHotelOverrides(data.overrides), ...exclusion};
}

function parsePackageStatementDecision(input: unknown): PackageStatementDecision {
  const data = packageDecisionRecord(input, "package statement decision");
  const disposition = packageDisposition(data.disposition);
  const linkage = packageLinkage(data, disposition);
  const overridesData = strictRecord(data.overrides,
    ["category", "text", "quantity", "frequency", "appliesTo"], [],
    "package statement overrides");
  const overrides: PackageStatementOverrides = compact({
    category: optionalSetOverride(overridesData.category,
      (value, label) => enumValue(value, statementCategories, label), "Statement category"),
    text: optionalSetOverride(overridesData.text, text, "Statement text"),
    quantity: optionalOverride(overridesData.quantity, positiveInteger,
      "Statement quantity"),
    frequency: optionalOverride(overridesData.frequency, text, "Statement frequency"),
    appliesTo: optionalOverride(overridesData.appliesTo, serviceTypeArray,
      "Statement applicability"),
  });
  return {...metadata(data), decisionKind: "package_statement", disposition,
    ...linkage, overrides, ...parseExclusion(data, disposition)};
}

function parsePackageConditionDecision(input: unknown): PackageConditionDecision {
  const data = packageDecisionRecord(input, "package condition decision");
  const disposition = packageDisposition(data.disposition);
  const linkage = packageLinkage(data, disposition);
  const overridesData = strictRecord(data.overrides,
    ["kind", "value", "appliesTo"], [], "package condition overrides");
  const overrides: PackageConditionOverrides = compact({
    kind: optionalSetOverride(overridesData.kind,
      (value, label) => enumValue(value, conditionKinds, label), "Condition kind"),
    value: optionalSetOverride(overridesData.value, text, "Condition value"),
    appliesTo: optionalOverride(overridesData.appliesTo, serviceTypeArray,
      "Condition applicability"),
  });
  return {...metadata(data), decisionKind: "package_condition", disposition,
    ...linkage, overrides, ...parseExclusion(data, disposition)};
}

function packageDecisionRecord(input: unknown, label: string): RecordValue {
  return strictRecord(input,
    [...decisionBaseFields, "disposition", "service", "destination", "overrides",
      ...exclusionFields],
    [...decisionBaseFields, "disposition", "service", "destination", "overrides",
      ...exclusionFields], label);
}

function packageDisposition(
  input: unknown,
): "retain_package_level" | "map_to_service" | "exclude" {
  return enumValue(input, values([
    "retain_package_level", "map_to_service", "exclude",
  ]), "package fact disposition");
}

function packageLinkage(
  data: RecordValue,
  disposition: "retain_package_level" | "map_to_service" | "exclude",
): {service: ServiceReference | null; destination: PackageServiceDestination | null} {
  const service = data.service === null ? null : parseServiceReference(data.service);
  const destination = data.destination === null ? null :
    enumValue(data.destination, packageDestinations, "package destination");
  if (disposition === "map_to_service" && (service === null || destination === null)) {
    invalid("Mapped package fact requires service and destination.");
  }
  if (disposition !== "map_to_service" && (service !== null || destination !== null)) {
    invalid("Only mapped package fact may name service and destination.");
  }
  return {service, destination};
}

function parseFlightDecision(input: unknown): FlightDecision {
  const data = ancillaryRecord(input, "flight decision");
  const disposition = enumValue(data.disposition, values([
    "route_to_flight_workflow", "handled_separately", "exclude",
  ]), "flight disposition");
  const destinationId = nullableIdentity(data.destinationId, "Flight workflow");
  validateRouteDestination(disposition, destinationId, "route_to_flight_workflow");
  return {...metadata(data), decisionKind: "flight", disposition, destinationId,
    overrides: parseFlightOverrides(data.overrides),
    ...parseExclusion(data, disposition)};
}

function parseFlightOverrides(input: unknown): FlightOverrides {
  const fields = [
    "airline", "flightNumber", "origin", "destination", "departureDate",
    "departureTime", "arrivalDate", "arrivalTime", "cabinClass", "bookingClass",
    "notes", "conditions",
  ];
  const data = strictRecord(input, fields, [], "flight overrides");
  return compact({
    airline: optionalOverride(data.airline, text, "Airline"),
    flightNumber: optionalOverride(data.flightNumber, text, "Flight number"),
    origin: optionalOverride(data.origin, text, "Flight origin"),
    destination: optionalOverride(data.destination, text, "Flight destination"),
    departureDate: optionalOverride(data.departureDate, dateText, "Departure date"),
    departureTime: optionalOverride(data.departureTime, timeText, "Departure time"),
    arrivalDate: optionalOverride(data.arrivalDate, dateText, "Arrival date"),
    arrivalTime: optionalOverride(data.arrivalTime, timeText, "Arrival time"),
    cabinClass: optionalOverride(data.cabinClass, text, "Cabin class"),
    bookingClass: optionalOverride(data.bookingClass, text, "Booking class"),
    notes: optionalOverride(data.notes, text, "Flight notes"),
    conditions: optionalOverride(data.conditions, conditionArray, "Flight conditions"),
  });
}

function parseVisaDecision(input: unknown): VisaDecision {
  const data = ancillaryRecord(input, "visa decision");
  const disposition = enumValue(data.disposition, values([
    "route_to_visa_workflow", "handled_separately", "exclude",
  ]), "visa disposition");
  const destinationId = nullableIdentity(data.destinationId, "Visa workflow");
  validateRouteDestination(disposition, destinationId, "route_to_visa_workflow");
  const raw = strictRecord(data.overrides, ["disposition", "text"], [],
    "visa overrides");
  const overrides: VisaOverrides = compact({
    disposition: optionalSetOverride(raw.disposition,
      (value, label) => enumValue(value, visaDispositions, label), "Visa disposition"),
    text: optionalOverride(raw.text, text, "Visa text"),
  });
  return {...metadata(data), decisionKind: "visa", disposition, destinationId,
    overrides, ...parseExclusion(data, disposition)};
}

function ancillaryRecord(input: unknown, label: string): RecordValue {
  return strictRecord(input,
    [...decisionBaseFields, "disposition", "destinationId", "overrides",
      ...exclusionFields],
    [...decisionBaseFields, "disposition", "destinationId", "overrides",
      ...exclusionFields], label);
}

function validateRouteDestination(
  disposition: string,
  destinationId: string | null,
  routeDisposition: string,
): void {
  if ((disposition === routeDisposition) !== (destinationId !== null)) {
    invalid("Workflow route and destination identity must agree.");
  }
}

function parseReviewDecision(input: unknown): ReviewIssueDecision {
  const data = strictRecord(input,
    [...decisionBaseFields, "outcome", "resolutionReferences", "overrideReason",
      "overrideNote"],
    [...decisionBaseFields, "outcome", "resolutionReferences", "overrideReason",
      "overrideNote"], "review issue decision");
  const outcome = enumValue(data.outcome, values([
    "acknowledged", "resolved", "overridden",
  ]), "review issue outcome");
  const resolutionReferences = array(data.resolutionReferences,
    "Resolution references").map(parseResolutionReference);
  unique(resolutionReferences.map(referenceKey), "resolution references");
  const overrideReason = data.overrideReason === null ? null :
    enumValue(data.overrideReason, exclusionReasons, "override reason");
  const overrideNote = nullableText(data.overrideNote, "Override note");
  if (outcome === "resolved" && resolutionReferences.length === 0) {
    invalid("Resolved review issue requires a concrete reference.");
  }
  if (outcome !== "resolved" && resolutionReferences.length !== 0) {
    invalid("Only resolved review issue may contain resolution references.");
  }
  if (outcome === "overridden") {
    if (overrideReason === null || overrideNote === null) {
      invalid("Overridden review issue requires reason and note.");
    }
  } else if (overrideReason !== null || overrideNote !== null) {
    invalid("Only overridden review issue may contain override rationale.");
  }
  return {...metadata(data), decisionKind: "review_issue", outcome,
    resolutionReferences, overrideReason, overrideNote};
}

function parseManualItem(input: unknown): SupplierImportManualItem {
  const data = record(input, "manual item");
  switch (data.itemKind) {
  case "consultant_day": return parseConsultantDay(data);
  case "consultant_service": return parseConsultantService(data);
  default: return invalid("Manual item kind is unsupported.");
  }
}

const manualMetadataFields = [
  "origin", "createdByUid", "createdAt", "updatedByUid", "updatedAt", "lastRevision",
] as const;

function manualMetadata(data: RecordValue): ManualItemMetadata {
  if (data.origin !== "consultant") invalid("Manual item origin must be consultant.");
  return {
    origin: "consultant",
    createdByUid: identity(data.createdByUid, "Manual item creator"),
    createdAt: timestamp(data.createdAt, "Manual item creation time"),
    updatedByUid: identity(data.updatedByUid, "Manual item updater"),
    updatedAt: timestamp(data.updatedAt, "Manual item update time"),
    lastRevision: positiveInteger(data.lastRevision, "Manual item revision"),
  };
}

function parseConsultantDay(input: unknown): ConsultantDay {
  const data = strictRecord(input,
    ["itemKind", "manualDayId", "canonicalOrder", "date", "title", "summary",
      "notes", ...manualMetadataFields],
    ["itemKind", "manualDayId", "canonicalOrder", "date", "title", "summary",
      "notes", ...manualMetadataFields], "consultant day");
  const manualDayId = manualIdentity(data.manualDayId, "consultant-day-", "Manual day");
  return {...manualMetadata(data), itemKind: "consultant_day", manualDayId,
    canonicalOrder: positiveInteger(data.canonicalOrder, "Manual day order"),
    date: nullableDate(data.date, "Manual day date"),
    title: text(data.title, "Manual day title"),
    summary: nullableText(data.summary, "Manual day summary"),
    notes: nullableText(data.notes, "Manual day notes")};
}

function parseConsultantService(input: unknown): ConsultantService {
  const fields = [
    "itemKind", "manualServiceId", "day", "canonicalOrder", "serviceType", "title",
    "description", "startTime", "endTime", "location", "city", "inclusions",
    "exclusions", "notes", "hotelDetails", "transferDetails", "activityDetails",
    ...manualMetadataFields,
  ];
  const data = strictRecord(input, fields, fields, "consultant service");
  const serviceType = enumValue(data.serviceType, serviceTypes, "manual service type");
  const hotelDetails = data.hotelDetails === null ? null :
    parseManualHotel(data.hotelDetails);
  const transferDetails = data.transferDetails === null ? null :
    parseManualTransfer(data.transferDetails);
  const activityDetails = data.activityDetails === null ? null :
    parseManualActivity(data.activityDetails);
  assertDetailCompatibility(serviceType, hotelDetails, transferDetails, activityDetails);
  return {...manualMetadata(data), itemKind: "consultant_service",
    manualServiceId: manualIdentity(data.manualServiceId, "consultant-service-",
      "Manual service"),
    day: parseDayReference(data.day),
    canonicalOrder: positiveInteger(data.canonicalOrder, "Manual service order"),
    serviceType, title: text(data.title, "Manual service title"),
    description: nullableText(data.description, "Manual service description"),
    startTime: nullableTime(data.startTime, "Manual service start time"),
    endTime: nullableTime(data.endTime, "Manual service end time"),
    location: nullableText(data.location, "Manual service location"),
    city: nullableText(data.city, "Manual service city"),
    inclusions: textArray(data.inclusions, "Manual service inclusions"),
    exclusions: textArray(data.exclusions, "Manual service exclusions"),
    notes: nullableText(data.notes, "Manual service notes"),
    hotelDetails, transferDetails, activityDetails};
}

function parseManualHotel(input: unknown): ManualHotelDetails {
  const data = exact(input, [
    "hotelName", "checkInDate", "checkOutDate", "roomType", "mealPlan",
    "numberOfRooms", "supplierStarRating",
  ], "manual hotel details");
  const checkInDate = nullableDate(data.checkInDate, "Manual hotel check-in");
  const checkOutDate = nullableDate(data.checkOutDate, "Manual hotel check-out");
  validateDateRange(checkInDate, checkOutDate, "Manual hotel");
  return {hotelName: text(data.hotelName, "Manual hotel name"), checkInDate,
    checkOutDate, roomType: nullableText(data.roomType, "Manual room type"),
    mealPlan: nullableText(data.mealPlan, "Manual meal plan"),
    numberOfRooms: nullablePositiveInteger(data.numberOfRooms, "Manual room count"),
    supplierStarRating: nullableText(data.supplierStarRating, "Manual star rating")};
}

function parseManualTransfer(input: unknown): ManualTransferDetails {
  const data = exact(input,
    ["pickup", "dropoff", "vehicleType", "transferType"], "manual transfer details");
  return {pickup: text(data.pickup, "Manual transfer pickup"),
    dropoff: text(data.dropoff, "Manual transfer dropoff"),
    vehicleType: nullableText(data.vehicleType, "Manual vehicle type"),
    transferType: data.transferType === null ? null :
      enumValue(data.transferType, transferTypes, "manual transfer type")};
}

function parseManualActivity(input: unknown): ManualActivityDetails {
  const data = exact(input,
    ["activityName", "duration", "activityType"], "manual activity details");
  return {activityName: text(data.activityName, "Manual activity name"),
    duration: nullableText(data.duration, "Manual activity duration"),
    activityType: nullableText(data.activityType, "Manual activity type")};
}

function parseAuditEvent(input: unknown): SupplierImportAuditEvent {
  const data = exact(input, [
    "eventId", "resolutionId", "extractionId", "previousRevision",
    "resultingRevision", "actorUid", "occurredAt", "action", "targetKind",
    "targetId", "commandId", "metadata",
  ], "audit event");
  const eventId = commandIdentity(data.eventId, "Audit event");
  const commandId = commandIdentity(data.commandId, "Command");
  if (eventId !== commandId) invalid("Audit event identity must equal command identity.");
  const previousRevision = nonNegativeInteger(data.previousRevision,
    "Previous revision");
  const resultingRevision = positiveInteger(data.resultingRevision,
    "Resulting revision");
  if (resultingRevision !== previousRevision + 1) {
    invalid("Audit revision must increment exactly once.");
  }
  return {eventId, resolutionId: identity(data.resolutionId, "Audit resolution"),
    extractionId: identity(data.extractionId, "Audit extraction"), previousRevision,
    resultingRevision, actorUid: identity(data.actorUid, "Audit actor"),
    occurredAt: timestamp(data.occurredAt, "Audit time"),
    action: enumValue(data.action, auditActions, "audit action"),
    targetKind: enumValue(data.targetKind, auditTargetKinds, "audit target kind"),
    targetId: nullableIdentity(data.targetId, "Audit target"), commandId,
    metadata: parseAuditMetadata(data.metadata)};
}

function parseAuditMetadata(input: unknown): SupplierImportAuditMetadata {
  const data = record(input, "audit metadata");
  if (data.kind === "lifecycle") {
    exactKeys(data, ["kind", "status"], "lifecycle audit metadata");
    return {kind: "lifecycle", status: enumValue(data.status,
      values(["active", "finalized"]), "audit lifecycle status")};
  }
  if (data.kind === "manual_item") {
    exactKeys(data, ["kind", "itemKind", "operation"], "manual audit metadata");
    return {kind: "manual_item", itemKind: enumValue(data.itemKind,
      values(["consultant_day", "consultant_service"]), "manual item kind"),
    operation: enumValue(data.operation, values(["added", "updated", "removed"]),
      "manual item operation")};
  }
  if (data.kind === "decision") {
    exactKeys(data, [
      "kind", "disposition", "changedFields", "exclusionReason", "referencedIds",
    ], "decision audit metadata");
    const disposition = enumValue(data.disposition, auditDispositions,
      "audit disposition");
    const changedFields = array(data.changedFields, "Changed fields").map((field) =>
      enumValue(field, auditChangedFields, "audit changed field"));
    const referencedIds = identityArray(data.referencedIds, "Audit references");
    return {kind: "decision", disposition, changedFields,
      exclusionReason: data.exclusionReason === null ? null :
        enumValue(data.exclusionReason, exclusionReasons, "audit exclusion reason"),
      referencedIds};
  }
  return invalid("Audit metadata kind is invalid.");
}

function validateRevisions(aggregate: SupplierImportResolutionAggregate): void {
  for (const decision of aggregate.decisions) {
    if (decision.lastRevision > aggregate.root.revision) {
      invalid("Decision revision exceeds resolution revision.");
    }
  }
  for (const item of aggregate.manualItems) {
    if (item.lastRevision > aggregate.root.revision) {
      invalid("Manual item revision exceeds resolution revision.");
    }
  }
  for (const event of aggregate.auditEvents) {
    if (event.resolutionId !== aggregate.root.resolutionId ||
        event.extractionId !== aggregate.root.extractionId) {
      invalid("Audit event linkage does not match resolution.");
    }
    if (event.resultingRevision > aggregate.root.revision) {
      invalid("Audit event revision exceeds resolution revision.");
    }
  }
}

function validateReferences(
  snapshot: SupplierExtractionSnapshot,
  aggregate: SupplierImportResolutionAggregate,
): void {
  const days = new Map(snapshot.days.map((day) => [day.id, day]));
  const services = factMap<StagedServiceFact>(snapshot, "service");
  const accommodations = factMap<PackageAccommodationFact>(
    snapshot, "package_accommodation",
  );
  const statements = new Map(snapshot.facts.filter((fact): fact is PackageStatementFact =>
    fact.factKind === "package_inclusion" || fact.factKind === "package_exclusion")
    .map((fact) => [fact.id, fact]));
  const conditions = factMap<PackageConditionFact>(snapshot, "package_condition");
  const flights = factMap<AncillaryFlightFact>(snapshot, "flight");
  const visas = factMap<AncillaryVisaFact>(snapshot, "visa");
  const issues = new Map(snapshot.reviewIssues.map((issue) => [issue.id, issue]));
  const manualDays = new Map(aggregate.manualItems.filter(
    (item): item is ConsultantDay => item.itemKind === "consultant_day",
  ).map((item) => [item.manualDayId, item]));
  const manualServices = new Map(aggregate.manualItems.filter(
    (item): item is ConsultantService => item.itemKind === "consultant_service",
  ).map((item) => [item.manualServiceId, item]));
  const decisions = new Map(aggregate.decisions.map((decision) =>
    [decision.decisionId, decision]));

  for (const decision of aggregate.decisions) {
    if (decision.decisionKind !== "title" &&
        decision.decisionId !== decision.targetEntityId) {
      invalid("Decision identity must equal target identity.");
    }
    switch (decision.decisionKind) {
    case "title": break;
    case "day": requireTarget(days, decision.targetEntityId, "staged day"); break;
    case "service": {
      const source = requireTarget(services, decision.targetEntityId, "staged service");
      validateServiceDecisionDetails(source, decision);
      break;
    }
    case "package_accommodation": {
      const source = requireTarget(accommodations, decision.targetEntityId,
        "package accommodation");
      const checkIn = effectiveOverride(source.details.checkInDate,
        decision.overrides.checkInDate);
      const checkOut = effectiveOverride(source.details.checkOutDate,
        decision.overrides.checkOutDate);
      validateDateRange(checkIn, checkOut, "Package accommodation");
      break;
    }
    case "package_statement":
      validateStatementMapping(requireTarget(statements, decision.targetEntityId,
        "package statement"), decision, services, manualServices, decisions);
      break;
    case "package_condition":
      validateConditionMapping(requireTarget(conditions, decision.targetEntityId,
        "package condition"), decision, services, manualServices, decisions);
      break;
    case "flight": requireTarget(flights, decision.targetEntityId, "flight"); break;
    case "visa": requireTarget(visas, decision.targetEntityId, "visa"); break;
    case "review_issue":
      validateReviewDecision(requireTarget(issues, decision.targetEntityId,
        "review issue"), decision, decisions, aggregate.manualItems);
      break;
    }
  }

  const retainedDay = (reference: DayReference): boolean => {
    if (reference.kind === "consultant_day") return manualDays.has(reference.manualDayId);
    if (!days.has(reference.dayId)) invalid("Referenced staged day does not exist.");
    const decision = decisions.get(reference.dayId);
    return decision?.decisionKind !== "day" || decision.disposition !== "exclude";
  };
  for (const decision of aggregate.decisions) {
    if (decision.decisionKind === "service" && decision.disposition === "retain" &&
        decision.day !== undefined && !retainedDay(decision.day)) {
      invalid("Retained service targets an excluded day.");
    }
    if (decision.decisionKind === "package_accommodation" &&
        decision.disposition === "map_to_day_service" &&
        (decision.day === null || !retainedDay(decision.day))) {
      invalid("Mapped accommodation targets an excluded day.");
    }
  }
  for (const service of services.values()) {
    const decision = decisions.get(service.id);
    if (decision?.decisionKind === "service" && decision.disposition === "exclude") {
      continue;
    }
    const reference = decision?.decisionKind === "service" && decision.day ?
      decision.day : service.scope.kind === "day" ?
        {kind: "staged_day" as const, dayId: service.scope.dayId} : null;
    if (reference !== null && !retainedDay(reference)) {
      invalid("Retained service targets an excluded day.");
    }
  }
  for (const item of manualServices.values()) {
    if (!retainedDay(item.day)) invalid("Manual service targets an excluded day.");
  }
  for (const item of manualDays.values()) {
    if (!item.manualDayId.startsWith("consultant-day-")) {
      invalid("Manual day identity has invalid namespace.");
    }
  }
}

function validateServiceDecisionDetails(
  source: StagedServiceFact,
  decision: StagedServiceDecision,
): void {
  const effectiveType = decision.overrides.serviceType?.value ?? source.serviceType;
  if (decision.overrides.hotel !== undefined && effectiveType !== "hotel") {
    invalid("Hotel overrides require an effective hotel service.");
  }
  if (decision.overrides.transfer !== undefined && effectiveType !== "transfer") {
    invalid("Transfer overrides require an effective transfer service.");
  }
  if (decision.overrides.activity !== undefined && effectiveType !== "activity") {
    invalid("Activity overrides require an effective activity service.");
  }
  const checkIn = effectiveOverride(source.hotelDetails?.checkInDate ?? null,
    decision.overrides.hotel?.checkInDate);
  const checkOut = effectiveOverride(source.hotelDetails?.checkOutDate ?? null,
    decision.overrides.hotel?.checkOutDate);
  validateDateRange(checkIn, checkOut, "Service hotel");
}

function validateStatementMapping(
  source: PackageStatementFact,
  decision: PackageStatementDecision,
  services: Map<string, StagedServiceFact>,
  manualServices: Map<string, ConsultantService>,
  decisions: Map<string, SupplierImportDecision>,
): void {
  if (decision.disposition !== "map_to_service") return;
  if (decision.destination === "service_inclusion" &&
      source.factKind !== "package_inclusion") {
    invalid("Package exclusion cannot map to a service inclusion.");
  }
  if (decision.destination === "service_exclusion" &&
      source.factKind !== "package_exclusion") {
    invalid("Package inclusion cannot map to a service exclusion.");
  }
  if (decision.destination === "transfer_type" ||
      decision.destination === "transfer_vehicle_type") {
    invalid("Package statement cannot map to a typed transfer field.");
  }
  requireRetainedService(decision.service, services, manualServices, decisions);
}

function validateConditionMapping(
  source: PackageConditionFact,
  decision: PackageConditionDecision,
  services: Map<string, StagedServiceFact>,
  manualServices: Map<string, ConsultantService>,
  decisions: Map<string, SupplierImportDecision>,
): void {
  if (decision.disposition !== "map_to_service") return;
  const targetType = requireRetainedService(
    decision.service, services, manualServices, decisions,
  );
  const kind = decision.overrides.kind?.value ?? source.kind;
  if ((decision.destination === "transfer_type" && kind !== "operating_basis") ||
      (decision.destination === "transfer_vehicle_type" && kind !== "vehicle")) {
    invalid("Package condition is incompatible with transfer destination.");
  }
  if (decision.destination === "transfer_type") {
    const value = decision.overrides.value?.value ?? source.value;
    if (!transferTypes.has(value as StagedTransferType)) {
      invalid("Mapped transfer type must use a controlled transfer value.");
    }
  }
  if ((decision.destination === "transfer_type" ||
       decision.destination === "transfer_vehicle_type") && targetType !== "transfer") {
    invalid("Typed transfer destination requires a transfer service.");
  }
  if (decision.destination === "service_inclusion" ||
      decision.destination === "service_exclusion") {
    invalid("Package condition cannot map to an inclusion or exclusion.");
  }
}

function requireRetainedService(
  reference: ServiceReference | null,
  services: Map<string, StagedServiceFact>,
  manualServices: Map<string, ConsultantService>,
  decisions: Map<string, SupplierImportDecision>,
): StagedServiceType | null {
  if (reference === null) return invalid("Mapped package fact requires a service.");
  if (reference.kind === "consultant_service") {
    return requireTarget(manualServices, reference.manualServiceId,
      "consultant service").serviceType;
  }
  const source = requireTarget(services, reference.serviceId, "staged service");
  const decision = decisions.get(source.id);
  if (decision?.decisionKind === "service" && decision.disposition === "exclude") {
    invalid("Package fact cannot target an excluded service.");
  }
  return decision?.decisionKind === "service" ?
    decision.overrides.serviceType?.value ?? source.serviceType : source.serviceType;
}

function validateReviewDecision(
  issue: StagedReviewIssue,
  decision: ReviewIssueDecision,
  decisions: Map<string, SupplierImportDecision>,
  manualItems: readonly SupplierImportManualItem[],
): void {
  if (decision.outcome === "acknowledged" &&
      (issue.severity !== "warning" || issue.resolutionRequired)) {
    invalid("Only optional warning may be acknowledged.");
  }
  if (decision.outcome === "overridden" && (!permitsReviewOverride(issue) ||
      issue.code !== "other" && (decision.overrideReason !== "other" || decision.overrideNote !== reviewedInterpretationNote))) {
    invalid("Review issue override is not permitted.");
  }
  if (decision.outcome !== "resolved") return;
  const manualIds = new Set(manualItems.map(manualItemId));
  for (const reference of decision.resolutionReferences) {
    const exists = reference.kind === "decision" ?
      decisions.has(reference.decisionId) : manualIds.has(reference.manualItemId);
    if (!exists) invalid("Review resolution reference does not exist.");
  }
  if (issue.target.entityId !== null &&
      !decision.resolutionReferences.some((reference) =>
        reference.kind === "decision" &&
        decisions.get(reference.decisionId)?.targetEntityId === issue.target.entityId)) {
    invalid("Review resolution does not address its target entity.");
  }
  if (structuralReviewCodes.has(issue.code) &&
      !decision.resolutionReferences.some((reference) =>
        concretelyResolves(issue.code, reference, decisions, manualIds))) {
    invalid("Structural review resolution lacks a concrete correction or mapping.");
  }
}

function parseExclusion(
  data: RecordValue,
  disposition: string,
): {exclusionReason: ExclusionReason | null; exclusionNote: string | null} {
  const exclusionReason = data.exclusionReason === null ? null :
    enumValue(data.exclusionReason, exclusionReasons, "exclusion reason");
  const exclusionNote = nullableText(data.exclusionNote, "Exclusion note");
  if (disposition === "exclude") {
    if (exclusionReason === null) invalid("Exclusion requires a controlled reason.");
    if (exclusionReason === "other" && exclusionNote === null) {
      invalid("Other exclusion requires a note.");
    }
  } else if (exclusionReason !== null || exclusionNote !== null) {
    invalid("Only excluded content may contain exclusion rationale.");
  }
  return {exclusionReason, exclusionNote};
}

function parseDayReference(input: unknown): DayReference {
  const data = record(input, "day reference");
  if (data.kind === "staged_day") {
    exactKeys(data, ["kind", "dayId"], "staged day reference");
    return {kind: "staged_day", dayId: identity(data.dayId, "Staged day")};
  }
  if (data.kind === "consultant_day") {
    exactKeys(data, ["kind", "manualDayId"], "consultant day reference");
    return {kind: "consultant_day", manualDayId: manualIdentity(
      data.manualDayId, "consultant-day-", "Manual day",
    )};
  }
  return invalid("Day reference kind is invalid.");
}

function parseServiceReference(input: unknown): ServiceReference {
  const data = record(input, "service reference");
  if (data.kind === "staged_service") {
    exactKeys(data, ["kind", "serviceId"], "staged service reference");
    return {kind: "staged_service", serviceId: identity(data.serviceId,
      "Staged service")};
  }
  if (data.kind === "consultant_service") {
    exactKeys(data, ["kind", "manualServiceId"], "consultant service reference");
    return {kind: "consultant_service", manualServiceId: manualIdentity(
      data.manualServiceId, "consultant-service-", "Manual service",
    )};
  }
  return invalid("Service reference kind is invalid.");
}

function parseResolutionReference(input: unknown): ResolutionReference {
  const data = record(input, "resolution reference");
  if (data.kind === "decision") {
    exactKeys(data, ["kind", "decisionId"], "decision reference");
    return {kind: "decision", decisionId: identity(data.decisionId, "Decision")};
  }
  if (data.kind === "manual_item") {
    exactKeys(data, ["kind", "manualItemId"], "manual item reference");
    return {kind: "manual_item", manualItemId: identity(data.manualItemId,
      "Manual item")};
  }
  return invalid("Resolution reference kind is invalid.");
}

function conditionArray(input: unknown, label: string): readonly ResolutionCondition[] {
  return array(input, label).map((value) => {
    const data = exact(value, ["kind", "value"], "condition");
    return {kind: enumValue(data.kind, conditionKinds, "condition kind"),
      value: text(data.value, "Condition value")};
  });
}

function assertDetailCompatibility(
  type: StagedServiceType,
  hotel: ManualHotelDetails | null,
  transfer: ManualTransferDetails | null,
  activity: ManualActivityDetails | null,
): void {
  if ((hotel !== null) !== (type === "hotel") ||
      (transfer !== null) !== (type === "transfer") ||
      (activity !== null) !== (type === "activity")) {
    if (["hotel", "transfer", "activity"].includes(type) ||
        hotel !== null || transfer !== null || activity !== null) {
      invalid("Manual service details are incompatible with service type.");
    }
  }
}

function validateDateRange(
  start: string | null,
  end: string | null,
  label: string,
): void {
  if (start !== null && end !== null && end <= start) {
    invalid(`${label} check-out must follow check-in.`);
  }
}

function effectiveOverride<T>(source: T | null, override?: FieldOverride<T>): T | null {
  if (override === undefined) return source;
  return override.operation === "clear" ? null : override.value;
}

function optionalSetOverride<T>(
  input: unknown,
  parser: (input: unknown, label: string) => T,
  label: string,
): SetFieldOverride<T> | undefined {
  return input === undefined ? undefined : setOverride(input, parser, label);
}

function setOverride<T>(
  input: unknown,
  parser: (input: unknown, label: string) => T,
  label: string,
): SetFieldOverride<T> {
  const data = exact(input, ["operation", "value"], label);
  if (data.operation !== "set") invalid(`${label} must use set.`);
  return {operation: "set", value: parser(data.value, label)};
}

function optionalOverride<T>(
  input: unknown,
  parser: (input: unknown, label: string) => T,
  label: string,
): FieldOverride<T> | undefined {
  if (input === undefined) return undefined;
  const data = record(input, label);
  if (data.operation === "clear") {
    exactKeys(data, ["operation"], label);
    return {operation: "clear"};
  }
  return setOverride(input, parser, label);
}

function factMap<T extends {id: string; factKind: string}>(
  snapshot: SupplierExtractionSnapshot,
  kind: T["factKind"],
): Map<string, T> {
  return new Map(snapshot.facts.filter((fact) => fact.factKind === kind)
    .map((fact) => [fact.id, fact as unknown as T]));
}

function requireTarget<T>(map: Map<string, T>, id: string, label: string): T {
  const value = map.get(id);
  if (value === undefined) invalid(`Decision target is not a ${label}.`);
  return value;
}

function manualItemId(item: SupplierImportManualItem): string {
  return item.itemKind === "consultant_day" ? item.manualDayId : item.manualServiceId;
}

function referenceKey(reference: ResolutionReference): string {
  return reference.kind === "decision" ?
    `decision:${reference.decisionId}` : `manual:${reference.manualItemId}`;
}

function strictRecord(
  input: unknown,
  allowed: readonly string[],
  required: readonly string[],
  label: string,
): RecordValue {
  const data = record(input, label);
  exactKeys(data, allowed, label);
  for (const key of required) {
    if (!Object.prototype.hasOwnProperty.call(data, key)) invalid(`${label} is incomplete.`);
  }
  return data;
}

function exact(input: unknown, fields: readonly string[], label: string): RecordValue {
  return strictRecord(input, fields, fields, label);
}

function record(input: unknown, label: string): RecordValue {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    invalid(`${label} must be an object.`);
  }
  return input as RecordValue;
}

function exactKeys(data: RecordValue, fields: readonly string[], label: string): void {
  const allowed = new Set(fields);
  if (Object.keys(data).some((key) => !allowed.has(key))) {
    invalid(`${label} contains unsupported fields.`);
  }
}

function array(input: unknown, label: string): unknown[] {
  if (!Array.isArray(input)) invalid(`${label} must be an array.`);
  return input;
}

function values<const T extends string>(items: readonly T[]): ReadonlySet<T> {
  return new Set(items);
}

function enumValue<T extends string>(
  input: unknown,
  allowed: ReadonlySet<T>,
  label: string,
): T {
  if (typeof input !== "string" || !allowed.has(input as T)) {
    invalid(`${label} is invalid.`);
  }
  return input as T;
}

function identity(input: unknown, label: string): string {
  if (!validSourceIdentity(input)) invalid(`${label} identity is invalid.`);
  return input;
}

function nullableIdentity(input: unknown, label: string): string | null {
  return input === null ? null : identity(input, label);
}

function manualIdentity(input: unknown, prefix: string, label: string): string {
  const value = identity(input, label);
  if (!value.startsWith(prefix) || value.length <= prefix.length) {
    invalid(`${label} identity has invalid namespace.`);
  }
  return value;
}

function commandIdentity(input: unknown, label: string): string {
  const value = identity(input, label);
  if (value.length > 128) invalid(`${label} identity is too long.`);
  return value;
}

function text(input: unknown, label: string): string {
  if (typeof input !== "string") invalid(`${label} must be text.`);
  const value = input.trim().replace(/\s+/gu, " ");
  if (value.length === 0 || value.length > 2000) invalid(`${label} is invalid.`);
  if (containsCommercialValue(value) || containsCommercialTerm(value)) invalid(`${label} contains commercial content.`);
  return value;
}

function nullableText(input: unknown, label: string): string | null {
  return input === null ? null : text(input, label);
}

function dateText(input: unknown, label: string): string {
  const value = text(input, label);
  if (!/^\d{4}-\d{2}-\d{2}$/u.test(value) ||
      new Date(`${value}T00:00:00.000Z`).toISOString().slice(0, 10) !== value) {
    invalid(`${label} must be a valid YYYY-MM-DD date.`);
  }
  return value;
}

function nullableDate(input: unknown, label: string): string | null {
  return input === null ? null : dateText(input, label);
}

function timeText(input: unknown, label: string): string {
  const value = text(input, label);
  if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/u.test(value)) {
    invalid(`${label} must be a valid HH:mm time.`);
  }
  return value;
}

function nullableTime(input: unknown, label: string): string | null {
  return input === null ? null : timeText(input, label);
}

function timestamp(input: unknown, label: string): string {
  if (typeof input !== "string" || !/^\d{4}-\d{2}-\d{2}T/u.test(input) ||
      Number.isNaN(Date.parse(input))) invalid(`${label} is invalid.`);
  return input;
}

function nullableTimestamp(input: unknown, label: string): string | null {
  return input === null ? null : timestamp(input, label);
}

function positiveInteger(input: unknown, label: string): number {
  if (!Number.isInteger(input) || (input as number) < 1) {
    invalid(`${label} must be a positive integer.`);
  }
  return input as number;
}

function nullablePositiveInteger(input: unknown, label: string): number | null {
  return input === null ? null : positiveInteger(input, label);
}

function nonNegativeInteger(input: unknown, label: string): number {
  if (!Number.isInteger(input) || (input as number) < 0) {
    invalid(`${label} must be a non-negative integer.`);
  }
  return input as number;
}

function booleanValue(input: unknown, label: string): boolean {
  if (typeof input !== "boolean") invalid(`${label} must be boolean.`);
  return input;
}

function textArray(input: unknown, label: string): readonly string[] {
  return array(input, label).map((value) => text(value, label));
}

function identityArray(input: unknown, label: string): readonly string[] {
  return array(input, label).map((value) => identity(value, label));
}

function serviceTypeArray(input: unknown, label: string): readonly StagedServiceType[] {
  const result = array(input, label).map((value) => enumValue(value, serviceTypes, label));
  unique(result, label);
  return result;
}

function unique(valuesToCheck: readonly string[], label: string): void {
  if (new Set(valuesToCheck).size !== valuesToCheck.length) {
    invalid(`${label} must be unique.`);
  }
}

function compact<T extends object>(value: T): T {
  return Object.fromEntries(Object.entries(value).filter(([, item]) =>
    item !== undefined)) as T;
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const nested of Object.values(value as Record<string, unknown>)) {
      deepFreeze(nested);
    }
  }
  return value;
}

function invalid(message: string): never {
  throw new SupplierImportResolutionError(message);
}
