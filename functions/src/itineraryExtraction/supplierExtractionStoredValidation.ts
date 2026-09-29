import {
  AncillaryFlightFact,
  AncillaryVisaFact,
  CommercialContentCategory,
  CommercialPresenceFact,
  PackageAccommodationFact,
  PackageConditionFact,
  PackageStatementFact,
  StagedActivityDetails,
  StagedCondition,
  StagedConditionKind,
  StagedDay,
  StagedHotelDetails,
  StagedReviewCode,
  StagedReviewIssue,
  StagedReviewSeverity,
  StagedReviewTarget,
  StagedServiceFact,
  StagedServiceScope,
  StagedServiceType,
  StagedStatement,
  StagedStatementCategory,
  StagedTransferDetails,
  StagedTransferType,
  StagedVisaDisposition,
  SupplierExtractionFact,
  SupplierExtractionSnapshot,
  SupplierExtractionSnapshotCounts,
  SupplierExtractionTitle,
  TrustedSnapshotSourceReference,
  supplierExtractionSnapshotSchemaVersion,
} from "./supplierExtractionSnapshot";
import {
  SupplierExtractionSnapshotError,
  assertSupplierExtractionSnapshotInvariants,
} from "./supplierExtractionValidation";
import {TrustedSupplierSourcePackage, validSourceIdentity} from
  "./sourceReaderValidation";

type RecordValue = Record<string, unknown>;

const serviceTypes = new Set<StagedServiceType>([
  "hotel", "transfer", "activity", "meal", "sightseeing", "free_time", "other",
]);
const transferTypes = new Set<StagedTransferType>([
  "private", "shared", "scheduled", "other",
]);
const statementCategories = new Set<StagedStatementCategory>([
  "accommodation", "meal", "guide", "water", "entrance", "transport",
  "visa", "other",
]);
const conditionKinds = new Set<StagedConditionKind>([
  "operating_basis", "vehicle", "class", "ticket_scope", "availability",
  "payment_basis", "guide", "other",
]);
const commercialCategories = new Set<CommercialContentCategory>([
  "package_price", "per_person_price", "supplement", "visa_price",
  "payment_terms", "other_commercial_terms",
]);
const visaDispositions = new Set<StagedVisaDisposition>([
  "included", "excluded", "requirement", "mentioned", "unclear",
]);
const reviewSeverities = new Set<StagedReviewSeverity>(["warning", "blocker"]);
const reviewCodes = new Set<StagedReviewCode>([
  "chronology_unknown", "accommodation_span_unknown",
  "classification_ambiguous", "conflicting_dates",
  "global_mapping_required", "source_conflict", "other",
]);
const titleBases = new Set(["explicit_supplier", "neutral_supported"] as const);

const sourceFields = [
  "supplierSourcePackageId", "supplierSourceFileId", "sourceLabel",
] as const;
const hotelFields = [
  "hotelName", "city", "orSimilar", "checkInDate", "checkOutDate",
  "nightCount", "roomType", "mealPlan", "numberOfRooms",
  "supplierStarRating",
] as const;
const statementFields = [
  "id", "category", "text", "quantity", "frequency", "appliesTo", "sources",
] as const;
const conditionFields = ["id", "kind", "value", "sources"] as const;

export function parseStoredSupplierExtractionSnapshot(
  input: unknown,
  trustedPackage: TrustedSupplierSourcePackage,
): SupplierExtractionSnapshot {
  const data = completeRecord(input, [
    "schemaVersion", "extractionId", "tripId", "sourcePackageId", "jobId",
    "requestedByUid", "createdAt", "providerVersion", "title", "days",
    "facts", "reviewIssues", "counts",
  ], "Stored Supplier Extraction Snapshot");
  if (data.schemaVersion !== supplierExtractionSnapshotSchemaVersion) {
    invalid("Stored Supplier Extraction schema version is invalid.");
  }
  const snapshot: SupplierExtractionSnapshot = {
    schemaVersion: supplierExtractionSnapshotSchemaVersion,
    extractionId: identity(data.extractionId, "Supplier extraction"),
    tripId: identity(data.tripId, "Trip"),
    sourcePackageId: identity(data.sourcePackageId, "Supplier Source package"),
    jobId: identity(data.jobId, "Extraction job"),
    requestedByUid: identity(data.requestedByUid, "Requesting user"),
    createdAt: isoTimestamp(data.createdAt, "Snapshot creation time"),
    providerVersion: nullableText(data.providerVersion, "Provider version"),
    title: parseTitle(data.title),
    days: array(data.days, "Staged days").map(parseDay),
    facts: array(data.facts, "Staged facts").map(parseFact),
    reviewIssues: array(data.reviewIssues, "Review issues").map(parseReviewIssue),
    counts: parseCounts(data.counts),
  };
  assertDeterministicIdentities(snapshot);
  assertSupplierExtractionSnapshotInvariants(snapshot, trustedPackage);
  return deepFreeze(snapshot);
}

function parseTitle(input: unknown): SupplierExtractionTitle {
  const data = completeRecord(input, ["text", "basis", "sources"], "Stored title");
  return {
    text: semanticText(data.text, "Stored title text"),
    basis: enumValue(data.basis, titleBases, "stored title basis"),
    sources: parseSources(data.sources),
  };
}

function parseDay(input: unknown, index: number): StagedDay {
  const data = completeRecord(input, [
    "id", "order", "sourceDayNumber", "date", "title", "summary", "notes",
    "assignedServiceIds", "sources",
  ], "Stored staged day");
  const order = positiveInteger(data.order, "Staged day order");
  if (order !== index + 1) invalid("Staged day order is not deterministic.");
  const sourceDayNumber = nullablePositiveInteger(
    data.sourceDayNumber,
    "Source day number",
  );
  const date = nullableDate(data.date, "Staged day date");
  const title = nullableSemanticText(data.title, "Staged day title");
  if (sourceDayNumber === null && date === null && title === null) {
    invalid("Stored staged day requires identifying chronology or a title.");
  }
  return {
    id: identity(data.id, "Staged day"),
    order,
    sourceDayNumber,
    date,
    title,
    summary: nullableSemanticText(data.summary, "Staged day summary"),
    notes: nullableSemanticText(data.notes, "Staged day notes"),
    assignedServiceIds: stringArray(
      data.assignedServiceIds,
      "Assigned service identities",
    ).map((value) => identity(value, "Assigned service")),
    sources: parseSources(data.sources),
  };
}

function parseFact(input: unknown): SupplierExtractionFact {
  const raw = record(input, "Stored staged fact");
  const factKind = requiredText(raw.factKind, "Stored fact kind");
  switch (factKind) {
  case "service": return parseService(raw);
  case "package_accommodation": return parsePackageAccommodation(raw);
  case "package_inclusion":
  case "package_exclusion": return parsePackageStatement(raw, factKind);
  case "package_condition": return parsePackageCondition(raw);
  case "flight": return parseFlight(raw);
  case "visa": return parseVisa(raw);
  case "commercial_presence": return parseCommercial(raw);
  default: invalid("Stored staged fact kind is invalid.");
  }
}

function parseService(input: unknown): StagedServiceFact {
  const data = completeRecord(input, [
    "id", "factKind", "order", "scope", "serviceType", "title",
    "description", "startTime", "endTime", "location", "city", "inclusions",
    "exclusions", "conditions", "notes", "hotelDetails", "transferDetails",
    "activityDetails", "sources",
  ], "Stored service fact");
  if (data.factKind !== "service") invalid("Stored service kind is invalid.");
  const serviceType = nullableEnum(data.serviceType, serviceTypes, "service type");
  const hotelDetails = data.hotelDetails === null ? null :
    parseHotelDetails(data.hotelDetails);
  const transferDetails = data.transferDetails === null ? null :
    parseTransferDetails(data.transferDetails);
  const activityDetails = data.activityDetails === null ? null :
    parseActivityDetails(data.activityDetails);
  if ((hotelDetails !== null && serviceType !== "hotel") ||
      (transferDetails !== null && serviceType !== "transfer") ||
      (activityDetails !== null && serviceType !== "activity")) {
    invalid("Stored service details are incompatible with the service type.");
  }
  const title = nullableSemanticText(data.title, "Stored service title");
  if (title === null && hotelDetails === null && transferDetails === null &&
      activityDetails === null) {
    invalid("Stored service requires an identifying fact.");
  }
  return {
    id: identity(data.id, "Staged service"),
    factKind: "service",
    order: positiveInteger(data.order, "Staged service order"),
    scope: parseServiceScope(data.scope),
    serviceType,
    title,
    description: nullableSemanticText(data.description, "Service description"),
    startTime: nullableTime(data.startTime, "Service start time"),
    endTime: nullableTime(data.endTime, "Service end time"),
    location: nullableSemanticText(data.location, "Service location"),
    city: nullableSemanticText(data.city, "Service city"),
    inclusions: array(data.inclusions, "Service inclusions").map(parseStatement),
    exclusions: array(data.exclusions, "Service exclusions").map(parseStatement),
    conditions: array(data.conditions, "Service conditions").map(parseCondition),
    notes: nullableSemanticText(data.notes, "Service notes"),
    hotelDetails,
    transferDetails,
    activityDetails,
    sources: parseSources(data.sources),
  };
}

function parseServiceScope(input: unknown): StagedServiceScope {
  const data = record(input, "Stored service scope");
  if (data.kind === "unassigned") {
    exactKeys(data, ["kind"], "Stored unassigned scope");
    return {kind: "unassigned"};
  }
  if (data.kind === "day") {
    exactKeys(data, ["kind", "dayId"], "Stored day scope");
    return {kind: "day", dayId: identity(data.dayId, "Staged day")};
  }
  return invalid("Stored service scope is invalid.");
}

function parseStatement(input: unknown): StagedStatement {
  const data = completeRecord(input, statementFields, "Stored statement");
  return {
    id: identity(data.id, "Statement"),
    category: enumValue(data.category, statementCategories, "statement category"),
    text: semanticText(data.text, "Statement text"),
    quantity: nullablePositiveInteger(data.quantity, "Statement quantity"),
    frequency: nullableSemanticText(data.frequency, "Statement frequency"),
    appliesTo: parseServiceTypes(data.appliesTo, "Statement applicability"),
    sources: parseSources(data.sources),
  };
}

function parseCondition(input: unknown): StagedCondition {
  const data = completeRecord(input, conditionFields, "Stored condition");
  return {
    id: identity(data.id, "Condition"),
    kind: enumValue(data.kind, conditionKinds, "condition kind"),
    value: semanticText(data.value, "Condition value"),
    sources: parseSources(data.sources),
  };
}

function parseHotelDetails(input: unknown): StagedHotelDetails {
  const data = completeRecord(input, hotelFields, "Stored hotel details");
  const details: StagedHotelDetails = {
    hotelName: nullableSemanticText(data.hotelName, "Hotel name"),
    city: nullableSemanticText(data.city, "Hotel city"),
    orSimilar: nullableBoolean(data.orSimilar, "Hotel or-similar qualifier"),
    checkInDate: nullableDate(data.checkInDate, "Hotel check-in date"),
    checkOutDate: nullableDate(data.checkOutDate, "Hotel check-out date"),
    nightCount: nullablePositiveInteger(data.nightCount, "Hotel night count"),
    roomType: nullableSemanticText(data.roomType, "Hotel room type"),
    mealPlan: nullableSemanticText(data.mealPlan, "Hotel meal plan"),
    numberOfRooms: nullablePositiveInteger(data.numberOfRooms, "Hotel room count"),
    supplierStarRating: nullableSemanticText(
      data.supplierStarRating,
      "Supplier star rating",
    ),
  };
  if (Object.values(details).every((value) => value === null)) {
    invalid("Stored hotel details require a supported fact.");
  }
  if (details.checkInDate !== null && details.checkOutDate !== null &&
      details.checkOutDate <= details.checkInDate) {
    invalid("Stored hotel check-out must follow check-in.");
  }
  return details;
}

function parseTransferDetails(input: unknown): StagedTransferDetails {
  const data = completeRecord(input, [
    "pickup", "dropoff", "vehicleType", "transferType",
  ], "Stored transfer details");
  const details: StagedTransferDetails = {
    pickup: nullableSemanticText(data.pickup, "Transfer pickup"),
    dropoff: nullableSemanticText(data.dropoff, "Transfer drop-off"),
    vehicleType: nullableSemanticText(data.vehicleType, "Transfer vehicle"),
    transferType: nullableEnum(data.transferType, transferTypes, "transfer type"),
  };
  if (Object.values(details).every((value) => value === null)) {
    invalid("Stored transfer details require a supported fact.");
  }
  return details;
}

function parseActivityDetails(input: unknown): StagedActivityDetails {
  const data = completeRecord(input, [
    "activityName", "duration", "activityType",
  ], "Stored activity details");
  const details: StagedActivityDetails = {
    activityName: nullableSemanticText(data.activityName, "Activity name"),
    duration: nullableSemanticText(data.duration, "Activity duration"),
    activityType: nullableSemanticText(data.activityType, "Activity type"),
  };
  if (Object.values(details).every((value) => value === null)) {
    invalid("Stored activity details require a supported fact.");
  }
  return details;
}

function parsePackageAccommodation(input: unknown): PackageAccommodationFact {
  const data = completeRecord(input, [
    "id", "factKind", "order", "scope", "details", "sources",
  ], "Stored package accommodation");
  requireLiteral(data.factKind, "package_accommodation", "package fact kind");
  parseLiteralScope(data.scope, "package");
  return {
    id: identity(data.id, "Package accommodation"),
    factKind: "package_accommodation",
    order: positiveInteger(data.order, "Package fact order"),
    scope: {kind: "package"},
    details: parseHotelDetails(data.details),
    sources: parseSources(data.sources),
  };
}

function parsePackageStatement(
  input: unknown,
  factKind: "package_inclusion" | "package_exclusion",
): PackageStatementFact {
  const data = completeRecord(input, [
    "id", "factKind", "order", "scope", "category", "text", "quantity",
    "frequency", "appliesTo", "sources",
  ], "Stored package statement");
  requireLiteral(data.factKind, factKind, "package statement kind");
  parseLiteralScope(data.scope, "package");
  return {
    id: identity(data.id, "Package statement"),
    factKind,
    order: positiveInteger(data.order, "Package fact order"),
    scope: {kind: "package"},
    category: enumValue(data.category, statementCategories, "statement category"),
    text: semanticText(data.text, "Package statement text"),
    quantity: nullablePositiveInteger(data.quantity, "Statement quantity"),
    frequency: nullableSemanticText(data.frequency, "Statement frequency"),
    appliesTo: parseServiceTypes(data.appliesTo, "Statement applicability"),
    sources: parseSources(data.sources),
  };
}

function parsePackageCondition(input: unknown): PackageConditionFact {
  const data = completeRecord(input, [
    "id", "factKind", "order", "scope", "kind", "value", "appliesTo",
    "sources",
  ], "Stored package condition");
  requireLiteral(data.factKind, "package_condition", "package condition kind");
  parseLiteralScope(data.scope, "package");
  return {
    id: identity(data.id, "Package condition"),
    factKind: "package_condition",
    order: positiveInteger(data.order, "Package fact order"),
    scope: {kind: "package"},
    kind: enumValue(data.kind, conditionKinds, "condition kind"),
    value: semanticText(data.value, "Condition value"),
    appliesTo: parseServiceTypes(data.appliesTo, "Condition applicability"),
    sources: parseSources(data.sources),
  };
}

function parseFlight(input: unknown): AncillaryFlightFact {
  const data = completeRecord(input, [
    "id", "factKind", "order", "scope", "airline", "flightNumber", "origin",
    "destination", "departureDate", "departureTime", "arrivalDate",
    "arrivalTime", "cabinClass", "bookingClass", "notes", "conditions",
    "sources",
  ], "Stored flight fact");
  requireLiteral(data.factKind, "flight", "flight fact kind");
  parseLiteralScope(data.scope, "ancillary");
  const flight: AncillaryFlightFact = {
    id: identity(data.id, "Ancillary flight"),
    factKind: "flight",
    order: positiveInteger(data.order, "Flight order"),
    scope: {kind: "ancillary"},
    airline: nullableSemanticText(data.airline, "Flight airline"),
    flightNumber: nullableSemanticText(data.flightNumber, "Flight number"),
    origin: nullableSemanticText(data.origin, "Flight origin"),
    destination: nullableSemanticText(data.destination, "Flight destination"),
    departureDate: nullableDate(data.departureDate, "Flight departure date"),
    departureTime: nullableTime(data.departureTime, "Flight departure time"),
    arrivalDate: nullableDate(data.arrivalDate, "Flight arrival date"),
    arrivalTime: nullableTime(data.arrivalTime, "Flight arrival time"),
    cabinClass: nullableSemanticText(data.cabinClass, "Flight cabin class"),
    bookingClass: nullableSemanticText(data.bookingClass, "Flight booking class"),
    notes: nullableSemanticText(data.notes, "Flight notes"),
    conditions: array(data.conditions, "Flight conditions").map(parseCondition),
    sources: parseSources(data.sources),
  };
  if ([flight.airline, flight.flightNumber, flight.origin, flight.destination]
    .every((value) => value === null)) {
    invalid("Stored flight requires an identifying fact.");
  }
  return flight;
}

function parseVisa(input: unknown): AncillaryVisaFact {
  const data = completeRecord(input, [
    "id", "factKind", "order", "scope", "disposition", "text", "sources",
  ], "Stored visa fact");
  requireLiteral(data.factKind, "visa", "visa fact kind");
  parseLiteralScope(data.scope, "ancillary");
  const disposition = enumValue(
    data.disposition,
    visaDispositions,
    "visa disposition",
  );
  const text = nullableSemanticText(data.text, "Visa fact text");
  if ((disposition === "requirement" || disposition === "unclear") &&
      text === null) {
    invalid("Stored visa requirement or uncertainty requires text.");
  }
  return {
    id: identity(data.id, "Ancillary visa"),
    factKind: "visa",
    order: positiveInteger(data.order, "Visa order"),
    scope: {kind: "ancillary"},
    disposition,
    text,
    sources: parseSources(data.sources),
  };
}

function parseCommercial(input: unknown): CommercialPresenceFact {
  const data = completeRecord(input, [
    "id", "factKind", "order", "scope", "categories", "sources",
  ], "Stored commercial indicator");
  requireLiteral(data.factKind, "commercial_presence", "commercial fact kind");
  parseLiteralScope(data.scope, "package");
  const categories = stringArray(data.categories, "Commercial categories")
    .map((value) => enumValue(
      value,
      commercialCategories,
      "commercial category",
    ));
  if (categories.length === 0) invalid("Stored commercial categories are empty.");
  unique(categories, "commercial categories");
  return {
    id: identity(data.id, "Commercial indicator"),
    factKind: "commercial_presence",
    order: positiveInteger(data.order, "Commercial indicator order"),
    scope: {kind: "package"},
    categories,
    sources: parseSources(data.sources),
  };
}

function parseReviewIssue(input: unknown): StagedReviewIssue {
  const data = completeRecord(input, [
    "id", "code", "severity", "message", "target", "resolutionRequired",
    "sources",
  ], "Stored review issue");
  return {
    id: identity(data.id, "Review issue"),
    code: enumValue(data.code, reviewCodes, "review code"),
    severity: enumValue(data.severity, reviewSeverities, "review severity"),
    message: semanticText(data.message, "Review message"),
    target: parseReviewTarget(data.target),
    resolutionRequired: booleanValue(
      data.resolutionRequired,
      "Review resolution requirement",
    ),
    sources: parseSources(data.sources),
  };
}

function parseReviewTarget(input: unknown): StagedReviewTarget {
  const data = record(input, "Stored review target");
  if (data.kind === "snapshot") {
    exactKeys(data, ["kind", "entityId"], "Snapshot review target");
    if (data.entityId !== null) invalid("Snapshot review target is invalid.");
    return {kind: "snapshot", entityId: null};
  }
  if (!["day", "service", "package_fact", "ancillary_fact"].includes(
    String(data.kind),
  )) {
    return invalid("Stored review target kind is invalid.");
  }
  exactKeys(data, ["kind", "entityId"], "Entity review target");
  return {
    kind: data.kind as Exclude<StagedReviewTarget["kind"], "snapshot">,
    entityId: identity(data.entityId, "Review target entity"),
  };
}

function parseCounts(input: unknown): SupplierExtractionSnapshotCounts {
  const fields = [
    "days", "assignedServices", "unassignedServices", "packageFacts",
    "ancillaryFlights", "ancillaryVisas", "commercialIndicators", "reviewIssues",
  ] as const;
  const data = completeRecord(input, fields, "Stored snapshot counts");
  return Object.fromEntries(fields.map((field) => [
    field,
    nonNegativeInteger(data[field], `Snapshot ${field} count`),
  ])) as unknown as SupplierExtractionSnapshotCounts;
}

function parseSources(input: unknown): readonly TrustedSnapshotSourceReference[] {
  const sources = array(input, "Trusted source references").map((value) => {
    const data = completeRecord(value, sourceFields, "Trusted source reference");
    return {
      supplierSourcePackageId: identity(
        data.supplierSourcePackageId,
        "Trusted source package",
      ),
      supplierSourceFileId: data.supplierSourceFileId === null ? null :
        identity(data.supplierSourceFileId, "Trusted source file"),
      sourceLabel: nullableSemanticText(data.sourceLabel, "Source label"),
    };
  });
  if (sources.length === 0) invalid("Trusted source references are required.");
  unique(sources.map((source) => [
    source.supplierSourcePackageId,
    source.supplierSourceFileId ?? "",
    source.sourceLabel ?? "",
  ].join("\u0000")), "trusted source references");
  return sources;
}

function parseServiceTypes(input: unknown, label: string): readonly StagedServiceType[] {
  const values = stringArray(input, label).map((value) =>
    enumValue(value, serviceTypes, "service type"));
  unique(values, label);
  return values;
}

function parseLiteralScope(input: unknown, kind: "package" | "ancillary"): void {
  const data = completeRecord(input, ["kind"], `Stored ${kind} scope`);
  requireLiteral(data.kind, kind, `${kind} scope`);
}

function assertDeterministicIdentities(snapshot: SupplierExtractionSnapshot): void {
  snapshot.days.forEach((day, index) => {
    if (day.id !== `staged-day-${index + 1}`) {
      invalid("Stored staged day identity is not deterministic.");
    }
  });
  let serviceIndex = 0;
  let packageIndex = 0;
  let flightIndex = 0;
  let visaIndex = 0;
  for (const fact of snapshot.facts) {
    if (fact.factKind === "service") {
      serviceIndex += 1;
      if (fact.id !== `staged-service-${serviceIndex}`) {
        invalid("Stored service identity is not deterministic.");
      }
    } else if (fact.factKind.startsWith("package_")) {
      packageIndex += 1;
      if (fact.id !== `package-fact-${packageIndex}` || fact.order !== packageIndex) {
        invalid("Stored package fact identity or order is not deterministic.");
      }
    } else if (fact.factKind === "flight") {
      flightIndex += 1;
      if (fact.id !== `ancillary-flight-${flightIndex}` || fact.order !== flightIndex) {
        invalid("Stored flight identity or order is not deterministic.");
      }
    } else if (fact.factKind === "visa") {
      visaIndex += 1;
      if (fact.id !== `ancillary-visa-${visaIndex}` || fact.order !== visaIndex) {
        invalid("Stored visa identity or order is not deterministic.");
      }
    } else if (fact.id !== "commercial-presence-1" || fact.order !== 1) {
      invalid("Stored commercial indicator identity is not deterministic.");
    }
  }
  snapshot.reviewIssues.forEach((issue, index) => {
    if (issue.id !== `review-${index + 1}`) {
      invalid("Stored review issue identity is not deterministic.");
    }
  });
}

function completeRecord<K extends string>(
  input: unknown,
  fields: readonly K[],
  label: string,
): RecordValue {
  const data = record(input, label);
  exactKeys(data, fields, label);
  return data;
}

function record(input: unknown, label: string): RecordValue {
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      input instanceof Date) {
    invalid(`${label} must be an object.`);
  }
  return input as RecordValue;
}

function exactKeys(
  data: RecordValue,
  fields: readonly string[],
  label: string,
): void {
  const keys = Object.keys(data);
  if (keys.length !== fields.length ||
      fields.some((field) => !Object.prototype.hasOwnProperty.call(data, field)) ||
      keys.some((key) => !fields.includes(key))) {
    invalid(`${label} fields are invalid.`);
  }
}

function array(input: unknown, label: string): readonly unknown[] {
  if (!Array.isArray(input)) invalid(`${label} must be an array.`);
  return input;
}

function stringArray(input: unknown, label: string): readonly string[] {
  return array(input, label).map((value) => requiredText(value, label));
}

function identity(input: unknown, label: string): string {
  if (!validSourceIdentity(input)) invalid(`${label} identity is invalid.`);
  return input;
}

function requiredText(input: unknown, label: string): string {
  if (typeof input !== "string" || input.trim().length === 0 ||
      input.trim() !== input) {
    invalid(`${label} must be normalized non-empty text.`);
  }
  return input;
}

const currencyCode = "(?:INR|USD|EUR|GBP|AED|AUD|CAD|CHF|JPY|SGD|THB)";
const commercialPattern = new RegExp([
  `(?:[$€£₹]\\s*\\d)`,
  `(?:\\d[\\d,.]*\\s*(?:[$€£₹]|${currencyCode}\\b))`,
  `(?:\\b${currencyCode}\\s*\\d)`,
  "(?:\\b(?:price|pricing|cost|total|amount|rate|supplement|margin|payment)" +
    "\\b[^.!?\\n]{0,32}\\d)",
  "(?:\\d[^.!?\\n]{0,32}\\b(?:price|pricing|cost|total|amount|rate|" +
    "supplement|margin|payment)\\b)",
].join("|"), "i");

function semanticText(input: unknown, label: string): string {
  const value = requiredText(input, label);
  if (commercialPattern.test(value)) {
    invalid(`${label} contains commercial data.`);
  }
  return value;
}

function nullableText(input: unknown, label: string): string | null {
  return input === null ? null : requiredText(input, label);
}

function nullableSemanticText(input: unknown, label: string): string | null {
  return input === null ? null : semanticText(input, label);
}

function nullableDate(input: unknown, label: string): string | null {
  if (input === null) return null;
  const value = requiredText(input, label);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) invalid(`${label} must use YYYY-MM-DD.`);
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (date.getUTCFullYear() !== Number(match[1]) ||
      date.getUTCMonth() !== Number(match[2]) - 1 ||
      date.getUTCDate() !== Number(match[3])) {
    invalid(`${label} is not a valid date.`);
  }
  return value;
}

function nullableTime(input: unknown, label: string): string | null {
  if (input === null) return null;
  const value = requiredText(input, label);
  if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value)) {
    invalid(`${label} must use HH:mm.`);
  }
  return value;
}

function isoTimestamp(input: unknown, label: string): string {
  const value = requiredText(input, label);
  const date = new Date(value);
  if (Number.isNaN(date.getTime()) || date.toISOString() !== value) {
    invalid(`${label} is invalid.`);
  }
  return value;
}

function positiveInteger(input: unknown, label: string): number {
  const value = integer(input, label);
  if (value < 1) invalid(`${label} must be positive.`);
  return value;
}

function nonNegativeInteger(input: unknown, label: string): number {
  const value = integer(input, label);
  if (value < 0) invalid(`${label} must not be negative.`);
  return value;
}

function nullablePositiveInteger(input: unknown, label: string): number | null {
  return input === null ? null : positiveInteger(input, label);
}

function integer(input: unknown, label: string): number {
  if (typeof input !== "number" || !Number.isSafeInteger(input)) {
    invalid(`${label} must be an integer.`);
  }
  return input;
}

function booleanValue(input: unknown, label: string): boolean {
  if (typeof input !== "boolean") invalid(`${label} must be a boolean.`);
  return input;
}

function nullableBoolean(input: unknown, label: string): boolean | null {
  return input === null ? null : booleanValue(input, label);
}

function enumValue<T extends string>(
  input: unknown,
  allowed: ReadonlySet<T>,
  label: string,
): T {
  if (typeof input !== "string" || !allowed.has(input as T)) {
    invalid(`Unknown ${label}.`);
  }
  return input as T;
}

function nullableEnum<T extends string>(
  input: unknown,
  allowed: ReadonlySet<T>,
  label: string,
): T | null {
  return input === null ? null : enumValue(input, allowed, label);
}

function requireLiteral(input: unknown, expected: string, label: string): void {
  if (input !== expected) invalid(`Stored ${label} is invalid.`);
}

function unique(values: readonly string[], label: string): void {
  if (new Set(values).size !== values.length) invalid(`Duplicate ${label}.`);
}

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    for (const nested of Object.values(value as Record<string, unknown>)) {
      deepFreeze(nested);
    }
    Object.freeze(value);
  }
  return value;
}

function invalid(message: string): never {
  throw new SupplierExtractionSnapshotError(
    "INVALID_SUPPLIER_EXTRACTION",
    message,
  );
}
