import type {ItineraryDraftImportResult} from "./itineraryDraftV2";
import {
  AccommodationOption,
  ItineraryDraftPackageContent,
  PackageAccommodation,
  PackageCondition,
  PackageHotelDetails,
  PackageStatement,
  SupplierFactProvenance,
  maxItineraryPackageRecords,
} from "./itineraryDraftPackageContent";
import {
  array, dateRange, enumValue, exact, identity, invalid, nullableDateOnly,
  nullablePositiveInteger, nullableText, positiveInteger, serviceTypes, sourceLabel,
  text, unique,
} from "./itineraryDraftValidationPrimitives";

const hotelFields = [
  "hotelName", "city", "orSimilar", "checkInDate", "checkOutDate", "nightCount",
  "roomType", "mealPlan", "numberOfRooms", "supplierStarRating",
] as const;
const statementFields = ["category", "text", "quantity", "frequency", "appliesTo"] as const;
const conditionFields = ["kind", "value", "appliesTo"] as const;

/** Internal parser; the root validator freezes the complete copied aggregate. */
export function parsePackageContent(
  input: unknown, imported: ItineraryDraftImportResult,
): ItineraryDraftPackageContent {
  const data = exact(input, [
    "accommodations", "inclusions", "exclusions", "conditions",
  ], "Package content");
  const accommodations = array(data.accommodations, "Accommodations");
  const inclusions = array(data.inclusions, "Inclusions");
  const exclusions = array(data.exclusions, "Exclusions");
  const conditions = array(data.conditions, "Conditions");
  let count = accommodations.length + inclusions.length + exclusions.length + conditions.length;
  for (const accommodation of accommodations) {
    const item = exact(accommodation, ["id", "order", "selection", "options"], "Accommodation");
    count += array(item.options, "Accommodation options").length;
  }
  if (count > maxItineraryPackageRecords) invalid("Package record capacity exceeded.");
  // Firestore's 768 KiB root / 256 KiB package budgets are NOT JSON byte counts.
  // The future persistence boundary must measure its complete encoded documents,
  // paths, metadata and index effects. This pure boundary enforces count only.
  return {
    accommodations: accommodations.map((item, index) => accommodation(item, index, imported)),
    inclusions: inclusions.map((item, index) => statement(item, index, imported)),
    exclusions: exclusions.map((item, index) => statement(item, index, imported)),
    conditions: conditions.map((item, index) => condition(item, index, imported)),
  };
}

function position(value: unknown, index: number): number {
  const order = positiveInteger(value, "Package order");
  if (order !== index + 1) invalid("Package order must be contiguous and match array position.");
  return order;
}

function accommodation(
  input: unknown, index: number, imported: ItineraryDraftImportResult,
): PackageAccommodation {
  const data = exact(input, ["id", "order", "selection", "options"], "Accommodation");
  const selection = enumValue(data.selection, ["single", "alternatives"], "Hotel selection");
  const options = array(data.options, "Accommodation options")
    .map((item, i) => option(item, i, imported));
  if ((selection === "single" && options.length !== 1) ||
      (selection === "alternatives" && options.length < 2)) {
    invalid("Accommodation selection and option count are incompatible.");
  }
  // Shape validation does not infer/approve an alternative relationship. A later
  // trusted finalizer must verify its explicit audited grouping decision.
  return {id: identity(data.id, "Accommodation"), order: position(data.order, index), selection, options};
}

function option(
  input: unknown, index: number, imported: ItineraryDraftImportResult,
): AccommodationOption {
  const data = exact(input, ["id", "order", "details", "provenance"], "Accommodation option");
  return {
    id: identity(data.id, "Accommodation option"), order: position(data.order, index),
    details: hotel(data.details),
    provenance: provenance(data.provenance, imported, hotelFields, hotelFields),
  };
}

function hotel(input: unknown): PackageHotelDetails {
  const data = exact(input, hotelFields, "Package hotel details");
  const checkInDate = nullableDateOnly(data.checkInDate, "Check-in date");
  const checkOutDate = nullableDateOnly(data.checkOutDate, "Check-out date");
  dateRange(checkInDate, checkOutDate);
  const nightCount = nullablePositiveInteger(data.nightCount, "Night count");
  if (checkInDate !== null && checkOutDate !== null && nightCount !== null &&
      (Date.parse(`${checkOutDate}T00:00:00.000Z`) -
       Date.parse(`${checkInDate}T00:00:00.000Z`)) / 86_400_000 !== nightCount) {
    invalid("Explicit night count conflicts with explicit stay dates.");
  }
  if (data.orSimilar !== null && typeof data.orSimilar !== "boolean") {
    invalid("Or-similar must be boolean or null.");
  }
  const result: PackageHotelDetails = {
    hotelName: nullableText(data.hotelName, "Hotel name"),
    city: nullableText(data.city, "Hotel city"), orSimilar: data.orSimilar,
    checkInDate, checkOutDate, nightCount,
    roomType: nullableText(data.roomType, "Room type"),
    mealPlan: nullableText(data.mealPlan, "Meal plan"),
    numberOfRooms: nullablePositiveInteger(data.numberOfRooms, "Room count"),
    supplierStarRating: nullableText(data.supplierStarRating, "Supplier star rating"),
  };
  if (Object.values(result).every((value) => value === null)) {
    invalid("Package accommodation needs at least one supplied attribute.");
  }
  return result;
}

function appliesTo(value: unknown): PackageStatement["appliesTo"] {
  const result = array(value, "Applicability")
    .map((item) => enumValue(item, serviceTypes, "Applicable service type"));
  unique(result, "Applicable service types");
  return result;
}

function statement(
  input: unknown, index: number, imported: ItineraryDraftImportResult,
): PackageStatement {
  const data = exact(input, ["id", "order", ...statementFields, "provenance"], "Package statement");
  return {
    id: identity(data.id, "Package statement"), order: position(data.order, index),
    category: enumValue(data.category, [
      "accommodation", "meal", "guide", "water", "entrance", "transport", "visa", "other",
    ], "Statement category"),
    text: text(data.text, "Statement text"),
    quantity: nullablePositiveInteger(data.quantity, "Statement quantity"),
    frequency: nullableText(data.frequency, "Statement frequency"),
    appliesTo: appliesTo(data.appliesTo),
    provenance: provenance(data.provenance, imported, statementFields, ["quantity", "frequency", "appliesTo"]),
  };
}

function condition(
  input: unknown, index: number, imported: ItineraryDraftImportResult,
): PackageCondition {
  const data = exact(input, ["id", "order", ...conditionFields, "provenance"], "Package condition");
  const kind = enumValue(data.kind, [
    "operating_basis", "vehicle", "class", "ticket_scope", "availability", "payment_basis", "guide", "other",
  ], "Condition kind");
  return {
    id: identity(data.id, "Package condition"), order: position(data.order, index), kind,
    value: text(data.value, "Condition value", kind === "payment_basis"),
    appliesTo: appliesTo(data.appliesTo),
    provenance: provenance(data.provenance, imported, conditionFields, ["appliesTo"]),
  };
}

function provenance<Field extends string>(
  input: unknown, imported: ItineraryDraftImportResult,
  fields: readonly Field[], clearable: readonly Field[],
): SupplierFactProvenance<Field> {
  const data = exact(input, [
    "origin", "extractionId", "sourcePackageId", "contributors", "resolutionId",
    "evaluatedRevision", "decisionIds", "fieldChanges",
  ], "Supplier fact provenance");
  const origin = enumValue(data.origin, ["supplier"], "Provenance origin");
  const extractionId = identity(data.extractionId, "Extraction");
  const sourcePackageId = identity(data.sourcePackageId, "Source package");
  const resolutionId = identity(data.resolutionId, "Resolution");
  const evaluatedRevision = positiveInteger(data.evaluatedRevision, "Evaluated revision");
  if (extractionId !== imported.extractionId || sourcePackageId !== imported.sourcePackageId ||
      resolutionId !== imported.resolutionId || evaluatedRevision !== imported.evaluatedRevision) {
    invalid("Fact provenance does not match import result.");
  }
  const contributors = array(data.contributors, "Contributors").map((item) => {
    const contributor = exact(item, ["stagedFactId", "sources"], "Contributor");
    const stagedFactId = identity(contributor.stagedFactId, "Staged fact");
    const sources = array(contributor.sources, "Contributor sources").map((source) => {
      const ref = exact(source, ["supplierSourceFileId", "sourceLabel"], "Source locator");
      const supplierSourceFileId = ref.supplierSourceFileId === null ? null :
        identity(ref.supplierSourceFileId, "Source file");
      return {supplierSourceFileId, sourceLabel: sourceLabel(ref.sourceLabel)};
    });
    if (sources.length === 0) invalid("Contributor sources are required.");
    unique(sources.map((ref) => JSON.stringify(ref)), "Source locators");
    return {stagedFactId, sources};
  });
  if (contributors.length === 0) invalid("Supplier contributors are required.");
  unique(contributors.map((item) => item.stagedFactId), "Contributor identities");
  const decisionIds = array(data.decisionIds, "Decision identities")
    .map((item) => identity(item, "Decision"));
  unique(decisionIds, "Decision identities");
  const fieldChanges = array(data.fieldChanges, "Field changes").map((item) => {
    const change = exact(item, ["field", "operation"], "Field change");
    const field = enumValue(change.field, fields, "Changed field");
    const operation = enumValue(change.operation, ["set", "clear"], "Field operation");
    if (operation === "clear" && !clearable.includes(field)) {
      invalid("Required package fields cannot be cleared.");
    }
    return {field, operation};
  });
  unique(fieldChanges.map((item) => item.field), "Changed fields");
  if (fieldChanges.length > 0 && decisionIds.length === 0) {
    invalid("Field corrections require decision linkage.");
  }
  // No lookup or claims of authority here. The eventual trusted finalizer must
  // verify all IDs, file membership, source labels and decisions against evidence.
  return {origin, extractionId, sourcePackageId, contributors, resolutionId,
    evaluatedRevision, decisionIds, fieldChanges};
}
