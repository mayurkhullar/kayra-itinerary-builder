import type {ItineraryDraftV2, itineraryDraftV2ImportPolicy, itineraryDraftV2SchemaVersion} from "./itineraryDraftV2";
import type {ImportAccountingOutcome, SupplierImportAccounting} from "./supplierImportV2AssemblyTypes";
import {immutable} from "./itineraryDraftValidationPrimitives";

export const supplierImportFinalizationReceiptSchemaVersion = "supplier_import_finalization_v1" as const;
// Section 25.7: source days/facts/issues, and decisions + manual items, separately.
export const maxReceiptSnapshotEntities = 2000;
export const maxReceiptDecisionsAndManualItems = 2000;

export type ReceiptTargetKind = SupplierImportAccounting["entityKind"];
export type ReceiptOutcomeCode = Exclude<ImportAccountingOutcome, "blocked">;
export const receiptTargetKinds = Object.freeze(["title", "day", "service", "package_accommodation",
  "package_inclusion", "package_exclusion", "package_condition", "flight", "visa",
  "commercial_presence", "consultant_day", "consultant_service", "review_issue"] as const);
export const receiptOutcomeCodes = Object.freeze(["auto_retained", "explicit_retained", "mapped", "excluded",
  "manual", "handled_separately", "routed", "informational", "review_resolved",
  "review_overridden", "review_open_warning", "review_acknowledged"] as const);
export const receiptOutputKinds = Object.freeze(["draft", "day", "service", "package_accommodation",
  "accommodation_option", "package_inclusion", "package_exclusion", "package_condition", "review_issue"] as const);
export const receiptOutputFields = Object.freeze(["entity", "title", "inclusions", "exclusions", "notes",
  "transferDetails.vehicleType", "transferDetails.transferType"] as const);
export type ReceiptOutputField = typeof receiptOutputFields[number];
/** `entity` selects the whole identified canonical entity, never a write path. */
export type ReceiptOutputTarget = Readonly<
  {kind: "day"; dayNumber: number; field: "entity"} |
  {kind: Exclude<typeof receiptOutputKinds[number], "day">; id: string; field: ReceiptOutputField}
>;

export const receiptOperationFields = immutable({
  title: ["title"],
  day: ["date", "title", "summary", "notes", "canonicalOrder"],
  service: ["serviceType", "title", "description", "startTime", "endTime", "location", "city", "inclusions", "exclusions", "notes", "day", "canonicalOrder",
    "hotel.hotelName", "hotel.city", "hotel.orSimilar", "hotel.checkInDate", "hotel.checkOutDate", "hotel.nightCount", "hotel.roomType", "hotel.mealPlan", "hotel.numberOfRooms", "hotel.supplierStarRating",
    "transfer.pickup", "transfer.dropoff", "transfer.vehicleType", "transfer.transferType", "activity.activityName", "activity.duration", "activity.activityType"],
  package_accommodation: ["hotelName", "city", "orSimilar", "checkInDate", "checkOutDate", "nightCount", "roomType", "mealPlan", "numberOfRooms", "supplierStarRating", "day", "canonicalOrder"],
  package_inclusion: ["category", "text", "quantity", "frequency", "appliesTo"],
  package_exclusion: ["category", "text", "quantity", "frequency", "appliesTo"],
  package_condition: ["kind", "value", "appliesTo"],
  flight: ["airline", "flightNumber", "origin", "destination", "departureDate", "departureTime", "arrivalDate", "arrivalTime", "cabinClass", "bookingClass", "notes", "conditions"],
  visa: ["disposition", "text"],
  commercial_presence: [], consultant_day: [], consultant_service: [], review_issue: [],
} as const);
export type ReceiptOperationField = typeof receiptOperationFields[ReceiptTargetKind][number];
export interface ReceiptFieldOperation {
  readonly field: ReceiptOperationField;
  readonly operation: "set" | "clear";
  readonly decisionId: string;
}
export interface SupplierImportReceiptOutcome {
  readonly targetKind: ReceiptTargetKind;
  readonly targetId: string | null;
  readonly outcome: ReceiptOutcomeCode;
  readonly decisionIds: readonly string[];
  readonly outputTargets: readonly ReceiptOutputTarget[];
  readonly fieldOperations: readonly ReceiptFieldOperation[];
}

/** Private immutable initial-result evidence; never embedded in an itinerary. */
export interface SupplierImportFinalizationReceipt {
  readonly schemaVersion: typeof supplierImportFinalizationReceiptSchemaVersion;
  readonly tripId: string;
  readonly extractionId: string;
  readonly resolutionId: string;
  readonly sourcePackageId: string;
  readonly finalizationId: string;
  readonly commandId: string;
  readonly actorUid: string;
  readonly finalizedAt: Date;
  readonly evaluatedRevision: number;
  readonly resultingRevision: number;
  readonly policyVersion: typeof itineraryDraftV2ImportPolicy;
  readonly canonicalSchemaVersion: typeof itineraryDraftV2SchemaVersion;
  readonly resultingDraftId: string;
  readonly requestFingerprint: string;
  readonly contentDigest: string;
  readonly outcomes: readonly SupplierImportReceiptOutcome[];
}

/** Pure trusted finalize-command metadata, not a callable request handler. */
export interface SupplierImportFinalizationReceiptContext {
  readonly tripId: string;
  readonly extractionId: string;
  readonly commandId: string;
  readonly expectedRevision: number;
  readonly policyVersion: typeof itineraryDraftV2ImportPolicy;
  readonly actorUid: string;
  readonly finalizedAt: Date;
}
export type ReceiptCanonicalBinding = ItineraryDraftV2;
export class SupplierImportFinalizationReceiptError extends Error {
  readonly code = "INVALID_SUPPLIER_IMPORT_FINALIZATION_RECEIPT";
  constructor() {
    super("Supplier Import finalization receipt is invalid.");
    this.name = "SupplierImportFinalizationReceiptError";
  }
}
