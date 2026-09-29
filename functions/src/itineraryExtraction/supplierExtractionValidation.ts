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
  SupplierExtractionTitle,
  TrustedSnapshotSourceReference,
  supplierExtractionSnapshotSchemaVersion,
} from "./supplierExtractionSnapshot";
import {
  TrustedSupplierSourcePackage,
  validSourceIdentity,
} from "./sourceReaderValidation";

export type SupplierExtractionSnapshotErrorCode =
  "INVALID_SUPPLIER_EXTRACTION";

export class SupplierExtractionSnapshotError extends Error {
  constructor(
    readonly code: SupplierExtractionSnapshotErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "SupplierExtractionSnapshotError";
  }
}

export interface SupplierExtractionNormalizationContext {
  extractionId: string;
  tripId: string;
  sourcePackageId: string;
  jobId: string;
  requestedByUid: string;
  createdAt: Date;
  providerVersion?: string | null;
  trustedPackage: TrustedSupplierSourcePackage;
}

type RecordValue = Record<string, unknown>;

interface NormalizationIndex {
  dayIds: readonly string[];
  assignedServiceIds: readonly (readonly string[])[];
  unassignedServiceIds: readonly string[];
  packageFactIds: Readonly<{
    accommodation: readonly string[];
    inclusion: readonly string[];
    exclusion: readonly string[];
    condition: readonly string[];
  }>;
  ancillaryFactIds: Readonly<{
    flight: readonly string[];
    visa: readonly string[];
  }>;
}

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

const rootFields = [
  "title", "days", "unassignedServices", "packageFacts", "ancillaryFacts",
  "reviewIssues", "commercialContent",
] as const;
const titleFields = ["text", "basis", "sources"] as const;
const dayFields = [
  "sourceDayNumber", "date", "title", "summary", "notes", "services", "sources",
] as const;
const serviceFields = [
  "type", "title", "description", "startTime", "endTime", "location", "city",
  "inclusions", "exclusions", "conditions", "notes", "hotelDetails",
  "transferDetails", "activityDetails", "sources",
] as const;
const hotelFields = [
  "hotelName", "city", "orSimilar", "checkInDate", "checkOutDate",
  "nightCount", "roomType", "mealPlan", "numberOfRooms",
  "supplierStarRating",
] as const;
const transferFields = [
  "pickup", "dropoff", "vehicleType", "transferType",
] as const;
const activityFields = ["activityName", "duration", "activityType"] as const;
const statementFields = [
  "category", "text", "quantity", "frequency", "appliesTo", "sources",
] as const;
const conditionFields = ["kind", "value", "sources"] as const;
const packageConditionFields = [
  "kind", "value", "appliesTo", "sources",
] as const;
const packageFactsFields = [
  "accommodations", "inclusions", "exclusions", "conditions",
] as const;
const ancillaryFields = ["flights", "visas"] as const;
const flightFields = [
  "airline", "flightNumber", "origin", "destination", "departureDate",
  "departureTime", "arrivalDate", "arrivalTime", "cabinClass", "bookingClass",
  "notes", "conditions", "sources",
] as const;
const visaFields = ["disposition", "text", "sources"] as const;
const commercialFields = ["present", "categories", "sources"] as const;
const sourceFields = ["fileIndex", "sourceLabel"] as const;
const reviewFields = [
  "code", "severity", "message", "target", "resolutionRequired", "sources",
] as const;

export function normalizeSupplierExtractionSnapshot(
  input: unknown,
  context: SupplierExtractionNormalizationContext,
): SupplierExtractionSnapshot {
  validateContext(context);
  const root = sparseRecord(input, rootFields, ["title"], "supplier extraction");
  const facts: SupplierExtractionFact[] = [];
  const dayIds: string[] = [];
  const assignedServiceIds: string[][] = [];
  const unassignedServiceIds: string[] = [];
  const packageFactIds = {
    accommodation: [] as string[],
    inclusion: [] as string[],
    exclusion: [] as string[],
    condition: [] as string[],
  };
  const ancillaryFactIds = {
    flight: [] as string[],
    visa: [] as string[],
  };
  let serviceIndex = 0;

  const days = optionalArray(root, "days", "Staged days").map((value, dayIndex) => {
    const dayId = `staged-day-${dayIndex + 1}`;
    dayIds.push(dayId);
    const result = normalizeDay(value, dayId, dayIndex + 1, context, () => {
      serviceIndex += 1;
      return `staged-service-${serviceIndex}`;
    });
    assignedServiceIds.push([...result.day.assignedServiceIds]);
    facts.push(...result.services);
    return result.day;
  });

  for (const value of optionalArray(
    root,
    "unassignedServices",
    "Unassigned services",
  )) {
    serviceIndex += 1;
    const id = `staged-service-${serviceIndex}`;
    unassignedServiceIds.push(id);
    facts.push(normalizeService(
      value,
      id,
      serviceIndex,
      Object.freeze({kind: "unassigned"}),
      context,
    ));
  }

  const packageRecord = has(root, "packageFacts") ? sparseRecord(
    root.packageFacts,
    packageFactsFields,
    [],
    "Package facts",
  ) : {};
  let packageIndex = 0;
  for (const value of optionalArray(
    packageRecord,
    "accommodations",
    "Package accommodations",
  )) {
    packageIndex += 1;
    const id = `package-fact-${packageIndex}`;
    packageFactIds.accommodation.push(id);
    facts.push(normalizePackageAccommodation(value, id, packageIndex, context));
  }
  for (const [field, factKind, target] of [
    ["inclusions", "package_inclusion", packageFactIds.inclusion],
    ["exclusions", "package_exclusion", packageFactIds.exclusion],
  ] as const) {
    for (const value of optionalArray(packageRecord, field, `Package ${field}`)) {
      packageIndex += 1;
      const id = `package-fact-${packageIndex}`;
      target.push(id);
      facts.push(normalizePackageStatement(value, id, packageIndex, factKind, context));
    }
  }
  for (const value of optionalArray(
    packageRecord,
    "conditions",
    "Package conditions",
  )) {
    packageIndex += 1;
    const id = `package-fact-${packageIndex}`;
    packageFactIds.condition.push(id);
    facts.push(normalizePackageCondition(value, id, packageIndex, context));
  }

  const ancillaryRecord = has(root, "ancillaryFacts") ? sparseRecord(
    root.ancillaryFacts,
    ancillaryFields,
    [],
    "Ancillary facts",
  ) : {};
  const flights = optionalArray(ancillaryRecord, "flights", "Flight facts");
  flights.forEach((value, index) => {
    const id = `ancillary-flight-${index + 1}`;
    ancillaryFactIds.flight.push(id);
    facts.push(normalizeFlight(value, id, index + 1, context));
  });
  const visas = optionalArray(ancillaryRecord, "visas", "Visa facts");
  visas.forEach((value, index) => {
    const id = `ancillary-visa-${index + 1}`;
    ancillaryFactIds.visa.push(id);
    facts.push(normalizeVisa(value, id, index + 1, context));
  });

  let commercialIndicators = 0;
  if (has(root, "commercialContent")) {
    const fact = normalizeCommercial(root.commercialContent, context);
    if (fact !== null) {
      commercialIndicators = 1;
      facts.push(fact);
    }
  }

  const index: NormalizationIndex = {
    dayIds,
    assignedServiceIds,
    unassignedServiceIds,
    packageFactIds,
    ancillaryFactIds,
  };
  const reviewIssues = optionalArray(root, "reviewIssues", "Review issues")
    .map((value, issueIndex) => normalizeReviewIssue(
      value,
      `review-${issueIndex + 1}`,
      index,
      context,
    ));

  const createdAt = normalizeCreatedAt(context.createdAt);
  const providerVersion = context.providerVersion === undefined ||
      context.providerVersion === null ? null :
    requiredText(context.providerVersion, "Provider version");
  const title = normalizeTitle(root.title, context);
  const snapshot: SupplierExtractionSnapshot = {
    schemaVersion: supplierExtractionSnapshotSchemaVersion,
    extractionId: context.extractionId,
    tripId: context.tripId,
    sourcePackageId: context.sourcePackageId,
    jobId: context.jobId,
    requestedByUid: context.requestedByUid,
    createdAt,
    providerVersion,
    title,
    days,
    facts,
    reviewIssues,
    counts: {
      days: days.length,
      assignedServices: assignedServiceIds.flat().length,
      unassignedServices: unassignedServiceIds.length,
      packageFacts: packageIndex,
      ancillaryFlights: flights.length,
      ancillaryVisas: visas.length,
      commercialIndicators,
      reviewIssues: reviewIssues.length,
    },
  };
  requireUnique(facts.map((fact) => fact.id), "staged fact identities");
  requireUnique(reviewIssues.map((issue) => issue.id), "review issue identities");
  assertSupplierExtractionSnapshotInvariants(snapshot, context.trustedPackage);
  return deepFreeze(snapshot);
}

export function assertSupplierExtractionSnapshotInvariants(
  snapshot: SupplierExtractionSnapshot,
  trustedPackage: TrustedSupplierSourcePackage,
): void {
  if (snapshot.schemaVersion !== supplierExtractionSnapshotSchemaVersion) {
    invalid("Supplier extraction schema version is invalid.");
  }
  for (const [value, label] of [
    [snapshot.extractionId, "Supplier extraction"],
    [snapshot.tripId, "Trip"],
    [snapshot.sourcePackageId, "Supplier Source package"],
    [snapshot.jobId, "Extraction job"],
    [snapshot.requestedByUid, "Requesting user"],
  ] as const) {
    if (!validSourceIdentity(value)) invalid(`${label} identity is invalid.`);
  }
  if (trustedPackage.tripId !== snapshot.tripId ||
      trustedPackage.packageId !== snapshot.sourcePackageId) {
    invalid("Snapshot metadata does not match the trusted package.");
  }
  if (!Array.isArray(snapshot.days) || !Array.isArray(snapshot.facts) ||
      !Array.isArray(snapshot.reviewIssues)) {
    invalid("Snapshot collections are invalid.");
  }
  const createdAt = typeof snapshot.createdAt === "string" ?
    new Date(snapshot.createdAt) : null;
  if (createdAt === null || Number.isNaN(createdAt.getTime()) ||
      createdAt.toISOString() !== snapshot.createdAt) {
    invalid("Snapshot creation time is invalid.");
  }

  const dayIds = snapshot.days.map((day) => day.id);
  const factIds = snapshot.facts.map((fact) => fact.id);
  const issueIds = snapshot.reviewIssues.map((issue) => issue.id);
  requireUnique(dayIds, "staged day identities");
  requireUnique(factIds, "staged fact identities");
  requireUnique(issueIds, "review issue identities");

  const daysById = new Map(snapshot.days.map((day) => [day.id, day]));
  const factsById = new Map(snapshot.facts.map((fact) => [fact.id, fact]));
  const trustedFileIds = new Set(
    trustedPackage.files.map((file) => file.sourceFileId),
  );
  validateTrustedSources(snapshot.title.sources, snapshot, trustedFileIds);

  for (const day of snapshot.days) {
    if (!validSourceIdentity(day.id) || !Array.isArray(day.assignedServiceIds)) {
      invalid("Staged day identity or service references are invalid.");
    }
    requireUnique(day.assignedServiceIds, "assigned service references");
    validateTrustedSources(day.sources, snapshot, trustedFileIds);
    for (const serviceId of day.assignedServiceIds) {
      const fact = factsById.get(serviceId);
      if (!fact || fact.factKind !== "service" || fact.scope.kind !== "day" ||
          fact.scope.dayId !== day.id) {
        invalid("Staged day points to an incompatible or missing service.");
      }
    }
  }

  for (const fact of snapshot.facts) {
    if (!validSourceIdentity(fact.id)) invalid("Staged fact identity is invalid.");
    validateTrustedSources(fact.sources, snapshot, trustedFileIds);
    if (fact.factKind === "service") {
      if (fact.scope.kind === "day") {
        const day = daysById.get(fact.scope.dayId);
        if (!day || !day.assignedServiceIds.includes(fact.id)) {
          invalid("Assigned service points to a missing staged day.");
        }
      } else if (fact.scope.kind !== "unassigned") {
        invalid("Staged service scope is invalid.");
      }
      validateNestedSources(fact.inclusions, snapshot, trustedFileIds);
      validateNestedSources(fact.exclusions, snapshot, trustedFileIds);
      validateNestedSources(fact.conditions, snapshot, trustedFileIds);
    } else if (fact.factKind === "flight") {
      if (fact.scope.kind !== "ancillary") invalid("Flight scope is invalid.");
      validateNestedSources(fact.conditions, snapshot, trustedFileIds);
    } else if (fact.factKind === "visa") {
      if (fact.scope.kind !== "ancillary") invalid("Visa scope is invalid.");
    } else if (fact.scope.kind !== "package") {
      invalid("Package fact scope is invalid.");
    }
  }

  for (const issue of snapshot.reviewIssues) {
    if (!validSourceIdentity(issue.id)) invalid("Review issue identity is invalid.");
    validateTrustedSources(issue.sources, snapshot, trustedFileIds);
    const entityId = issue.target.entityId;
    if (issue.target.kind === "snapshot") {
      if (entityId !== null) invalid("Snapshot review target is invalid.");
    } else if (entityId === null) {
      invalid("Entity review target requires an identity.");
    } else if (issue.target.kind === "day") {
      if (!daysById.has(entityId)) invalid("Review issue targets a missing day.");
    } else {
      const fact = factsById.get(entityId);
      if (!fact ||
          (issue.target.kind === "service" && fact.factKind !== "service") ||
          (issue.target.kind === "package_fact" &&
            !fact.factKind.startsWith("package_")) ||
          (issue.target.kind === "ancillary_fact" &&
            fact.factKind !== "flight" && fact.factKind !== "visa")) {
        invalid("Review issue targets a missing or incompatible entity.");
      }
    }
  }

  const expectedCounts = {
    days: snapshot.days.length,
    assignedServices: snapshot.facts.filter((fact) =>
      fact.factKind === "service" && fact.scope.kind === "day").length,
    unassignedServices: snapshot.facts.filter((fact) =>
      fact.factKind === "service" && fact.scope.kind === "unassigned").length,
    packageFacts: snapshot.facts.filter((fact) =>
      fact.factKind.startsWith("package_")).length,
    ancillaryFlights: snapshot.facts.filter((fact) =>
      fact.factKind === "flight").length,
    ancillaryVisas: snapshot.facts.filter((fact) =>
      fact.factKind === "visa").length,
    commercialIndicators: snapshot.facts.filter((fact) =>
      fact.factKind === "commercial_presence").length,
    reviewIssues: snapshot.reviewIssues.length,
  };
  if (JSON.stringify(snapshot.counts) !== JSON.stringify(expectedCounts)) {
    invalid("Snapshot derived counts are inconsistent.");
  }
}

function validateNestedSources(
  values: readonly {sources: readonly TrustedSnapshotSourceReference[]}[],
  snapshot: SupplierExtractionSnapshot,
  trustedFileIds: ReadonlySet<string>,
): void {
  for (const value of values) {
    validateTrustedSources(value.sources, snapshot, trustedFileIds);
  }
}

function validateTrustedSources(
  sources: readonly TrustedSnapshotSourceReference[],
  snapshot: SupplierExtractionSnapshot,
  trustedFileIds: ReadonlySet<string>,
): void {
  if (!Array.isArray(sources) || sources.length === 0) {
    invalid("Trusted source references are required.");
  }
  for (const source of sources) {
    if (source.supplierSourcePackageId !== snapshot.sourcePackageId ||
        (source.supplierSourceFileId !== null &&
          !trustedFileIds.has(source.supplierSourceFileId))) {
      invalid("Trusted source reference is outside the snapshot package.");
    }
  }
}

function normalizeTitle(
  input: unknown,
  context: SupplierExtractionNormalizationContext,
): SupplierExtractionTitle {
  const data = sparseRecord(input, titleFields, ["text", "basis"], "Staged title");
  const basis = enumValue(
    data.basis,
    new Set(["explicit_supplier", "neutral_supported"] as const),
    "title basis",
  );
  return {
    text: requiredSemanticText(data.text, "Staged title text"),
    basis,
    sources: normalizeSources(data, context),
  };
}

function normalizeDay(
  input: unknown,
  id: string,
  order: number,
  context: SupplierExtractionNormalizationContext,
  allocateServiceId: () => string,
): {day: StagedDay; services: readonly StagedServiceFact[]} {
  const data = sparseRecord(input, dayFields, [], "Staged day");
  const sourceDayNumber = optionalPositiveInteger(
    data,
    "sourceDayNumber",
    "Source day number",
  );
  const date = optionalDate(data, "date", "Staged day date");
  const title = optionalSemanticText(data, "title", "Staged day title");
  if (sourceDayNumber === null && date === null && title === null) {
    invalid("Staged day requires a source day number, date, or title.");
  }
  const serviceValues = optionalArray(data, "services", "Assigned services");
  const services: StagedServiceFact[] = [];
  const serviceIds: string[] = [];
  for (const value of serviceValues) {
    const serviceId = allocateServiceId();
    serviceIds.push(serviceId);
    services.push(normalizeService(
      value,
      serviceId,
      services.length + 1,
      Object.freeze({kind: "day", dayId: id}),
      context,
    ));
  }
  return {
    day: {
      id,
      order,
      sourceDayNumber,
      date,
      title,
      summary: optionalSemanticText(data, "summary", "Staged day summary"),
      notes: optionalSemanticText(data, "notes", "Staged day notes"),
      assignedServiceIds: serviceIds,
      sources: normalizeSources(data, context),
    },
    services,
  };
}

function normalizeService(
  input: unknown,
  id: string,
  order: number,
  scope: StagedServiceScope,
  context: SupplierExtractionNormalizationContext,
): StagedServiceFact {
  const data = sparseRecord(input, serviceFields, [], "Staged service");
  const serviceType = has(data, "type") ?
    enumValue(data.type, serviceTypes, "service type") : null;
  const hotelDetails = has(data, "hotelDetails") ?
    normalizeHotelDetails(data.hotelDetails, "Staged hotel details") : null;
  const transferDetails = has(data, "transferDetails") ?
    normalizeTransferDetails(data.transferDetails) : null;
  const activityDetails = has(data, "activityDetails") ?
    normalizeActivityDetails(data.activityDetails) : null;
  if (hotelDetails !== null && serviceType !== "hotel") {
    invalid("Hotel details require a hotel service.");
  }
  if (transferDetails !== null && serviceType !== "transfer") {
    invalid("Transfer details require a transfer service.");
  }
  if (activityDetails !== null && serviceType !== "activity") {
    invalid("Activity details require an activity service.");
  }
  const title = optionalSemanticText(data, "title", "Staged service title");
  if (title === null && hotelDetails === null &&
      transferDetails === null && activityDetails === null) {
    invalid("Staged service requires a title or identifying typed details.");
  }
  return {
    id,
    factKind: "service",
    order,
    scope,
    serviceType,
    title,
    description: optionalSemanticText(
      data,
      "description",
      "Staged service description",
    ),
    startTime: optionalTime(data, "startTime", "Service start time"),
    endTime: optionalTime(data, "endTime", "Service end time"),
    location: optionalSemanticText(data, "location", "Service location"),
    city: optionalSemanticText(data, "city", "Service city"),
    inclusions: normalizeStatements(
      data,
      "inclusions",
      `${id}-inclusion`,
      context,
    ),
    exclusions: normalizeStatements(
      data,
      "exclusions",
      `${id}-exclusion`,
      context,
    ),
    conditions: normalizeConditions(
      data,
      "conditions",
      `${id}-condition`,
      context,
    ),
    notes: optionalSemanticText(data, "notes", "Staged service notes"),
    hotelDetails,
    transferDetails,
    activityDetails,
    sources: normalizeSources(data, context),
  };
}

function normalizeHotelDetails(input: unknown, label: string): StagedHotelDetails {
  const data = sparseRecord(input, hotelFields, [], label);
  const checkInDate = optionalDate(data, "checkInDate", "Hotel check-in date");
  const checkOutDate = optionalDate(data, "checkOutDate", "Hotel check-out date");
  if (checkInDate !== null && checkOutDate !== null &&
      checkOutDate <= checkInDate) {
    invalid("Hotel check-out must follow check-in.");
  }
  const details: StagedHotelDetails = {
    hotelName: optionalSemanticText(data, "hotelName", "Hotel name"),
    city: optionalSemanticText(data, "city", "Hotel city"),
    orSimilar: optionalBoolean(data, "orSimilar", "Hotel or-similar qualifier"),
    checkInDate,
    checkOutDate,
    nightCount: optionalPositiveInteger(data, "nightCount", "Hotel night count"),
    roomType: optionalSemanticText(data, "roomType", "Hotel room type"),
    mealPlan: optionalSemanticText(data, "mealPlan", "Hotel meal plan"),
    numberOfRooms: optionalPositiveInteger(
      data,
      "numberOfRooms",
      "Hotel room count",
    ),
    supplierStarRating: optionalSemanticText(
      data,
      "supplierStarRating",
      "Supplier star rating",
    ),
  };
  if (Object.values(details).every((value) => value === null)) {
    invalid(`${label} requires at least one supported fact.`);
  }
  return details;
}

function normalizeTransferDetails(input: unknown): StagedTransferDetails {
  const data = sparseRecord(input, transferFields, [], "Staged transfer details");
  const details: StagedTransferDetails = {
    pickup: optionalSemanticText(data, "pickup", "Transfer pickup"),
    dropoff: optionalSemanticText(data, "dropoff", "Transfer drop-off"),
    vehicleType: optionalSemanticText(data, "vehicleType", "Transfer vehicle"),
    transferType: has(data, "transferType") ?
      enumValue(data.transferType, transferTypes, "transfer type") : null,
  };
  if (Object.values(details).every((value) => value === null)) {
    invalid("Staged transfer details require at least one supported fact.");
  }
  return details;
}

function normalizeActivityDetails(input: unknown): StagedActivityDetails {
  const data = sparseRecord(input, activityFields, [], "Staged activity details");
  const details: StagedActivityDetails = {
    activityName: optionalSemanticText(data, "activityName", "Activity name"),
    duration: optionalSemanticText(data, "duration", "Activity duration"),
    activityType: optionalSemanticText(data, "activityType", "Activity type"),
  };
  if (Object.values(details).every((value) => value === null)) {
    invalid("Staged activity details require at least one supported fact.");
  }
  return details;
}

function normalizeStatements(
  record: RecordValue,
  field: string,
  idPrefix: string,
  context: SupplierExtractionNormalizationContext,
): readonly StagedStatement[] {
  return optionalArray(record, field, field).map((value, index) =>
    normalizeStatement(value, `${idPrefix}-${index + 1}`, context));
}

function normalizeStatement(
  input: unknown,
  id: string,
  context: SupplierExtractionNormalizationContext,
): StagedStatement {
  const data = sparseRecord(
    input,
    statementFields,
    ["category", "text"],
    "Staged statement",
  );
  const appliesTo = optionalArray(data, "appliesTo", "Statement applicability")
    .map((value) => enumValue(
      value,
      serviceTypes,
      "statement service type",
    ));
  requireUnique(appliesTo, "statement service types");
  return {
    id,
    category: enumValue(data.category, statementCategories, "statement category"),
    text: requiredSemanticText(data.text, "Statement text"),
    quantity: optionalPositiveInteger(data, "quantity", "Statement quantity"),
    frequency: optionalSemanticText(data, "frequency", "Statement frequency"),
    appliesTo,
    sources: normalizeSources(data, context),
  };
}

function normalizeConditions(
  record: RecordValue,
  field: string,
  idPrefix: string,
  context: SupplierExtractionNormalizationContext,
): readonly StagedCondition[] {
  return optionalArray(record, field, field).map((value, index) =>
    normalizeCondition(value, `${idPrefix}-${index + 1}`, context));
}

function normalizeCondition(
  input: unknown,
  id: string,
  context: SupplierExtractionNormalizationContext,
): StagedCondition {
  const data = sparseRecord(
    input,
    conditionFields,
    ["kind", "value"],
    "Staged condition",
  );
  return {
    id,
    kind: enumValue(data.kind, conditionKinds, "condition kind"),
    value: requiredSemanticText(data.value, "Condition value"),
    sources: normalizeSources(data, context),
  };
}

function normalizePackageAccommodation(
  input: unknown,
  id: string,
  order: number,
  context: SupplierExtractionNormalizationContext,
): PackageAccommodationFact {
  const data = sparseRecord(
    input,
    [...hotelFields, "sources"],
    [],
    "Package accommodation",
  );
  const detailsInput = Object.fromEntries(
    hotelFields.filter((field) => has(data, field)).map((field) => [field, data[field]]),
  );
  return {
    id,
    factKind: "package_accommodation",
    order,
    scope: Object.freeze({kind: "package"}),
    details: normalizeHotelDetails(detailsInput, "Package accommodation"),
    sources: normalizeSources(data, context),
  };
}

function normalizePackageStatement(
  input: unknown,
  id: string,
  order: number,
  factKind: "package_inclusion" | "package_exclusion",
  context: SupplierExtractionNormalizationContext,
): PackageStatementFact {
  const statement = normalizeStatement(input, id, context);
  return {
    id,
    factKind,
    order,
    scope: Object.freeze({kind: "package"}),
    category: statement.category,
    text: statement.text,
    quantity: statement.quantity,
    frequency: statement.frequency,
    appliesTo: statement.appliesTo,
    sources: statement.sources,
  };
}

function normalizePackageCondition(
  input: unknown,
  id: string,
  order: number,
  context: SupplierExtractionNormalizationContext,
): PackageConditionFact {
  const data = sparseRecord(
    input,
    packageConditionFields,
    ["kind", "value"],
    "Package condition",
  );
  const appliesTo = optionalArray(data, "appliesTo", "Condition applicability")
    .map((value) => enumValue(value, serviceTypes, "condition service type"));
  requireUnique(appliesTo, "condition service types");
  return {
    id,
    factKind: "package_condition",
    order,
    scope: Object.freeze({kind: "package"}),
    kind: enumValue(data.kind, conditionKinds, "condition kind"),
    value: requiredSemanticText(data.value, "Condition value"),
    appliesTo,
    sources: normalizeSources(data, context),
  };
}

function normalizeFlight(
  input: unknown,
  id: string,
  order: number,
  context: SupplierExtractionNormalizationContext,
): AncillaryFlightFact {
  const data = sparseRecord(input, flightFields, [], "Flight fact");
  const airline = optionalSemanticText(data, "airline", "Flight airline");
  const flightNumber = optionalSemanticText(
    data,
    "flightNumber",
    "Flight number",
  );
  const origin = optionalSemanticText(data, "origin", "Flight origin");
  const destination = optionalSemanticText(
    data,
    "destination",
    "Flight destination",
  );
  if ([airline, flightNumber, origin, destination].every((value) => value === null)) {
    invalid("Flight fact requires an airline, flight number, origin, or destination.");
  }
  return {
    id,
    factKind: "flight",
    order,
    scope: Object.freeze({kind: "ancillary"}),
    airline,
    flightNumber,
    origin,
    destination,
    departureDate: optionalDate(data, "departureDate", "Flight departure date"),
    departureTime: optionalTime(data, "departureTime", "Flight departure time"),
    arrivalDate: optionalDate(data, "arrivalDate", "Flight arrival date"),
    arrivalTime: optionalTime(data, "arrivalTime", "Flight arrival time"),
    cabinClass: optionalSemanticText(data, "cabinClass", "Flight cabin class"),
    bookingClass: optionalSemanticText(
      data,
      "bookingClass",
      "Flight booking class",
    ),
    notes: optionalSemanticText(data, "notes", "Flight notes"),
    conditions: normalizeConditions(
      data,
      "conditions",
      `${id}-condition`,
      context,
    ),
    sources: normalizeSources(data, context),
  };
}

function normalizeVisa(
  input: unknown,
  id: string,
  order: number,
  context: SupplierExtractionNormalizationContext,
): AncillaryVisaFact {
  const data = sparseRecord(input, visaFields, ["disposition"], "Visa fact");
  const disposition = enumValue(
    data.disposition,
    visaDispositions,
    "visa disposition",
  );
  const text = optionalSemanticText(data, "text", "Visa fact text");
  if ((disposition === "requirement" || disposition === "unclear") && text === null) {
    invalid(`Visa ${disposition} requires explanatory text.`);
  }
  return {
    id,
    factKind: "visa",
    order,
    scope: Object.freeze({kind: "ancillary"}),
    disposition,
    text,
    sources: normalizeSources(data, context),
  };
}

function normalizeCommercial(
  input: unknown,
  context: SupplierExtractionNormalizationContext,
): CommercialPresenceFact | null {
  const data = sparseRecord(
    input,
    commercialFields,
    ["present"],
    "Commercial-content indicator",
  );
  const present = requiredBoolean(data.present, "Commercial-content presence");
  const categories = optionalArray(
    data,
    "categories",
    "Commercial-content categories",
  ).map((value) => enumValue(
    value,
    commercialCategories,
    "commercial-content category",
  ));
  requireUnique(categories, "commercial-content categories");
  if (!present) {
    if (categories.length > 0 || has(data, "sources")) {
      invalid("Absent commercial content cannot contain categories or sources.");
    }
    return null;
  }
  if (categories.length === 0) {
    invalid("Present commercial content requires a controlled category.");
  }
  return {
    id: "commercial-presence-1",
    factKind: "commercial_presence",
    order: 1,
    scope: Object.freeze({kind: "package"}),
    categories,
    sources: normalizeSources(data, context),
  };
}

function normalizeReviewIssue(
  input: unknown,
  id: string,
  index: NormalizationIndex,
  context: SupplierExtractionNormalizationContext,
): StagedReviewIssue {
  const data = sparseRecord(
    input,
    reviewFields,
    ["code", "severity", "message", "target", "resolutionRequired"],
    "Review issue",
  );
  return {
    id,
    code: enumValue(data.code, reviewCodes, "review code"),
    severity: enumValue(data.severity, reviewSeverities, "review severity"),
    message: requiredSemanticText(data.message, "Review message"),
    target: normalizeReviewTarget(data.target, index),
    resolutionRequired: requiredBoolean(
      data.resolutionRequired,
      "Review resolution requirement",
    ),
    sources: normalizeSources(data, context),
  };
}

function normalizeReviewTarget(
  input: unknown,
  index: NormalizationIndex,
): StagedReviewTarget {
  const base = sparseRecord(input, [
    "kind", "dayIndex", "scope", "serviceIndex", "factType", "factIndex",
  ], ["kind"], "Review target");
  const kind = requiredText(base.kind, "Review target kind");
  if (kind === "snapshot") {
    requireOnlyFields(base, ["kind"], "Snapshot review target");
    return {kind: "snapshot", entityId: null};
  }
  if (kind === "day") {
    requireOnlyFields(base, ["kind", "dayIndex"], "Day review target");
    const id = indexedValue(index.dayIds, base.dayIndex, "Review day index");
    return {kind: "day", entityId: id};
  }
  if (kind === "service") {
    const scope = requiredText(base.scope, "Review service scope");
    if (scope === "day") {
      requireOnlyFields(
        base,
        ["kind", "scope", "dayIndex", "serviceIndex"],
        "Assigned-service review target",
      );
      const dayIndex = requiredOneBasedIndex(base.dayIndex, "Review day index");
      const ids = index.assignedServiceIds[dayIndex - 1];
      if (!ids) invalid("Review target points to a missing staged day.");
      const id = indexedValue(ids, base.serviceIndex, "Review service index");
      return {kind: "service", entityId: id};
    }
    if (scope === "unassigned") {
      requireOnlyFields(
        base,
        ["kind", "scope", "serviceIndex"],
        "Unassigned-service review target",
      );
      const id = indexedValue(
        index.unassignedServiceIds,
        base.serviceIndex,
        "Review service index",
      );
      return {kind: "service", entityId: id};
    }
    invalid("Unknown review service scope.");
  }
  if (kind === "package_fact") {
    requireOnlyFields(
      base,
      ["kind", "factType", "factIndex"],
      "Package-fact review target",
    );
    const factType = enumValue(
      base.factType,
      new Set(["accommodation", "inclusion", "exclusion", "condition"] as const),
      "package fact type",
    );
    const id = indexedValue(
      index.packageFactIds[factType],
      base.factIndex,
      "Review package fact index",
    );
    return {kind: "package_fact", entityId: id};
  }
  if (kind === "ancillary_fact") {
    requireOnlyFields(
      base,
      ["kind", "factType", "factIndex"],
      "Ancillary-fact review target",
    );
    const factType = enumValue(
      base.factType,
      new Set(["flight", "visa"] as const),
      "ancillary fact type",
    );
    const id = indexedValue(
      index.ancillaryFactIds[factType],
      base.factIndex,
      "Review ancillary fact index",
    );
    return {kind: "ancillary_fact", entityId: id};
  }
  invalid("Unknown review target kind.");
}

function normalizeSources(
  record: RecordValue,
  context: SupplierExtractionNormalizationContext,
): readonly TrustedSnapshotSourceReference[] {
  if (!has(record, "sources")) {
    return [defaultSourceReference(context)];
  }
  const inputs = requiredArray(record.sources, "Source locators");
  if (inputs.length === 0) invalid("Source locators cannot be empty.");
  const result = inputs.map((value) => normalizeSource(value, context));
  const keys = result.map((value) => [
    value.supplierSourcePackageId,
    value.supplierSourceFileId ?? "",
    value.sourceLabel ?? "",
  ].join("\u0000"));
  requireUnique(keys, "source references");
  return result;
}

function normalizeSource(
  input: unknown,
  context: SupplierExtractionNormalizationContext,
): TrustedSnapshotSourceReference {
  const data = sparseRecord(input, sourceFields, [], "Provider source locator");
  const sourceLabel = optionalCompactSourceLabel(data);
  let fileId = context.trustedPackage.files.length === 1 ?
    context.trustedPackage.files[0].sourceFileId : null;
  if (has(data, "fileIndex")) {
    const fileIndex = requiredOneBasedIndex(data.fileIndex, "Source file index");
    const file = context.trustedPackage.files[fileIndex - 1];
    if (!file) invalid("Source file index is outside the trusted package.");
    fileId = file.sourceFileId;
  }
  return {
    supplierSourcePackageId: context.sourcePackageId,
    supplierSourceFileId: fileId,
    sourceLabel,
  };
}

function optionalCompactSourceLabel(record: RecordValue): string | null {
  if (!has(record, "sourceLabel")) return null;
  const value = requiredSemanticText(record.sourceLabel, "Source label");
  if (value.length > 160 || /[\r\n]/.test(value)) {
    invalid("Source label must be compact single-line text.");
  }
  return value;
}

function defaultSourceReference(
  context: SupplierExtractionNormalizationContext,
): TrustedSnapshotSourceReference {
  return {
    supplierSourcePackageId: context.sourcePackageId,
    supplierSourceFileId: context.trustedPackage.files.length === 1 ?
      context.trustedPackage.files[0].sourceFileId : null,
    sourceLabel: null,
  };
}

function validateContext(context: SupplierExtractionNormalizationContext): void {
  for (const [value, label] of [
    [context.extractionId, "Supplier extraction"],
    [context.tripId, "Trip"],
    [context.sourcePackageId, "Supplier Source package"],
    [context.jobId, "Extraction job"],
    [context.requestedByUid, "Requesting user"],
  ] as const) {
    if (!validSourceIdentity(value)) invalid(`${label} identity is invalid.`);
  }
  if (context.trustedPackage.tripId !== context.tripId ||
      context.trustedPackage.packageId !== context.sourcePackageId ||
      context.trustedPackage.files.length === 0) {
    invalid("Trusted Supplier Source package does not match snapshot context.");
  }
  requireUnique(
    context.trustedPackage.files.map((file) => file.sourceFileId),
    "trusted source file identities",
  );
  normalizeCreatedAt(context.createdAt);
}

function normalizeCreatedAt(value: Date): string {
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) {
    invalid("Snapshot creation time is invalid.");
  }
  return value.toISOString();
}

function sparseRecord<K extends string>(
  value: unknown,
  allowedFields: readonly K[],
  requiredFields: readonly K[],
  label: string,
): RecordValue {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      value instanceof Date) {
    invalid(`${label} must be an object.`);
  }
  const data = value as RecordValue;
  if (Object.keys(data).some((key) => !allowedFields.includes(key as K))) {
    invalid(`${label} contains unsupported fields.`);
  }
  if (requiredFields.some((field) => !has(data, field))) {
    invalid(`${label} is missing required fields.`);
  }
  return data;
}

function requireOnlyFields(
  record: RecordValue,
  allowed: readonly string[],
  label: string,
): void {
  if (Object.keys(record).some((key) => !allowed.includes(key))) {
    invalid(`${label} contains unsupported fields.`);
  }
  if (allowed.some((field) => !has(record, field))) {
    invalid(`${label} is missing required fields.`);
  }
}

function optionalArray(
  record: RecordValue,
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

function requiredText(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    invalid(`${label} must be non-empty text.`);
  }
  return value.trim();
}

const currencyCode = "(?:INR|USD|EUR|GBP|AED|AUD|CAD|CHF|JPY|SGD|THB)";
const commercialValuePattern = new RegExp([
  `(?:[$€£₹]\\s*\\d)`,
  `(?:\\d[\\d,.]*\\s*(?:[$€£₹]|${currencyCode}\\b))`,
  `(?:\\b${currencyCode}\\s*\\d)`,
  "(?:\\b(?:price|pricing|cost|total|amount|rate|supplement|margin|payment)" +
    "\\b[^.!?\\n]{0,32}\\d)",
  "(?:\\d[^.!?\\n]{0,32}\\b(?:price|pricing|cost|total|amount|rate|" +
    "supplement|margin|payment)\\b)",
].join("|"), "i");

function requiredSemanticText(value: unknown, label: string): string {
  const text = requiredText(value, label);
  if (commercialValuePattern.test(text)) {
    invalid(`${label} must not contain a commercial amount or currency.`);
  }
  return text;
}

function optionalSemanticText(
  record: RecordValue,
  field: string,
  label: string,
): string | null {
  if (!has(record, field)) return null;
  return requiredSemanticText(record[field], label);
}

function optionalDate(
  record: RecordValue,
  field: string,
  label: string,
): string | null {
  if (!has(record, field)) return null;
  const value = requiredText(record[field], label);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) invalid(`${label} must use YYYY-MM-DD.`);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day) {
    invalid(`${label} is not a valid calendar date.`);
  }
  return value;
}

function optionalTime(
  record: RecordValue,
  field: string,
  label: string,
): string | null {
  if (!has(record, field)) return null;
  const value = requiredText(record[field], label);
  if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value)) {
    invalid(`${label} must use 24-hour HH:mm.`);
  }
  return value;
}

function optionalPositiveInteger(
  record: RecordValue,
  field: string,
  label: string,
): number | null {
  if (!has(record, field)) return null;
  const value = requiredInteger(record[field], label);
  if (value < 1) invalid(`${label} must be positive.`);
  return value;
}

function requiredInteger(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    invalid(`${label} must be an integer.`);
  }
  return value;
}

function requiredOneBasedIndex(value: unknown, label: string): number {
  const index = requiredInteger(value, label);
  if (index < 1) invalid(`${label} must be one-based and positive.`);
  return index;
}

function requiredBoolean(value: unknown, label: string): boolean {
  if (typeof value !== "boolean") invalid(`${label} must be a boolean.`);
  return value;
}

function optionalBoolean(
  record: RecordValue,
  field: string,
  label: string,
): boolean | null {
  if (!has(record, field)) return null;
  return requiredBoolean(record[field], label);
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

function indexedValue(
  values: readonly string[],
  rawIndex: unknown,
  label: string,
): string {
  const index = requiredOneBasedIndex(rawIndex, label);
  const value = values[index - 1];
  if (!value) invalid(`${label} points to a missing entity.`);
  return value;
}

function requireUnique(values: readonly string[], label: string): void {
  if (new Set(values).size !== values.length) {
    invalid(`Duplicate ${label}.`);
  }
}

function has(record: RecordValue, field: string): boolean {
  return Object.prototype.hasOwnProperty.call(record, field);
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
