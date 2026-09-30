import {
  StagedConditionKind,
  StagedServiceType,
  StagedStatementCategory,
  StagedTransferType,
  StagedVisaDisposition,
  supplierExtractionSnapshotSchemaVersion,
} from "./supplierExtractionSnapshot";

export const supplierImportResolutionSchemaVersion =
  "supplier_import_resolution_v1" as const;

export type SupplierImportResolutionStatus = "active" | "finalized";

export interface SupplierImportResolutionRoot {
  schemaVersion: typeof supplierImportResolutionSchemaVersion;
  resolutionId: string;
  tripId: string;
  extractionId: string;
  sourcePackageId: string;
  snapshotSchemaVersion: typeof supplierExtractionSnapshotSchemaVersion;
  status: SupplierImportResolutionStatus;
  revision: number;
  createdByUid: string;
  createdAt: string;
  updatedByUid: string;
  updatedAt: string;
  finalizedByUid: string | null;
  finalizedAt: string | null;
  resultingDraftId: string | null;
}

export type SetFieldOverride<T> = Readonly<{
  operation: "set";
  value: T;
}>;

export type FieldOverride<T> =
  SetFieldOverride<T> |
  Readonly<{operation: "clear"}>;

export type ExclusionReason =
  "duplicate" |
  "extracted_in_error" |
  "irrelevant_supplier_content" |
  "not_part_of_requested_itinerary" |
  "replaced_by_consultant_content" |
  "other";

export type DayReference =
  Readonly<{kind: "staged_day"; dayId: string}> |
  Readonly<{kind: "consultant_day"; manualDayId: string}>;

export type ServiceReference =
  Readonly<{kind: "staged_service"; serviceId: string}> |
  Readonly<{kind: "consultant_service"; manualServiceId: string}>;

export interface DecisionMetadata {
  decisionId: string;
  targetEntityId: string;
  lastRevision: number;
  updatedByUid: string;
  updatedAt: string;
}

export interface TitleDecision extends DecisionMetadata {
  decisionKind: "title";
  disposition: "accept" | "override";
  overrides: Readonly<{title?: SetFieldOverride<string>}>;
}

export interface DayOverrides {
  date?: FieldOverride<string>;
  title?: SetFieldOverride<string>;
  summary?: FieldOverride<string>;
  notes?: FieldOverride<string>;
}

export interface StagedDayDecision extends DecisionMetadata {
  decisionKind: "day";
  disposition: "retain" | "exclude";
  canonicalOrder?: number;
  overrides: Readonly<DayOverrides>;
  exclusionReason: ExclusionReason | null;
  exclusionNote: string | null;
}

export interface HotelOverrides {
  hotelName?: FieldOverride<string>;
  city?: FieldOverride<string>;
  orSimilar?: FieldOverride<boolean>;
  checkInDate?: FieldOverride<string>;
  checkOutDate?: FieldOverride<string>;
  nightCount?: FieldOverride<number>;
  roomType?: FieldOverride<string>;
  mealPlan?: FieldOverride<string>;
  numberOfRooms?: FieldOverride<number>;
  supplierStarRating?: FieldOverride<string>;
}

export interface TransferOverrides {
  pickup?: FieldOverride<string>;
  dropoff?: FieldOverride<string>;
  vehicleType?: FieldOverride<string>;
  transferType?: FieldOverride<StagedTransferType>;
}

export interface ActivityOverrides {
  activityName?: FieldOverride<string>;
  duration?: FieldOverride<string>;
  activityType?: FieldOverride<string>;
}

export interface ServiceOverrides {
  serviceType?: SetFieldOverride<StagedServiceType>;
  title?: SetFieldOverride<string>;
  description?: FieldOverride<string>;
  startTime?: FieldOverride<string>;
  endTime?: FieldOverride<string>;
  location?: FieldOverride<string>;
  city?: FieldOverride<string>;
  inclusions?: FieldOverride<readonly string[]>;
  exclusions?: FieldOverride<readonly string[]>;
  notes?: FieldOverride<string>;
  hotel?: Readonly<HotelOverrides>;
  transfer?: Readonly<TransferOverrides>;
  activity?: Readonly<ActivityOverrides>;
}

export interface StagedServiceDecision extends DecisionMetadata {
  decisionKind: "service";
  disposition: "retain" | "exclude";
  day?: DayReference;
  canonicalOrder?: number;
  overrides: Readonly<ServiceOverrides>;
  exclusionReason: ExclusionReason | null;
  exclusionNote: string | null;
}

export interface PackageAccommodationDecision extends DecisionMetadata {
  decisionKind: "package_accommodation";
  disposition: "map_to_day_service" | "retain_package_level" | "exclude";
  day: DayReference | null;
  canonicalOrder: number | null;
  overrides: Readonly<HotelOverrides>;
  exclusionReason: ExclusionReason | null;
  exclusionNote: string | null;
}

export type PackageServiceDestination =
  "service_inclusion" |
  "service_exclusion" |
  "service_notes" |
  "transfer_vehicle_type" |
  "transfer_type";

export interface PackageStatementOverrides {
  category?: SetFieldOverride<StagedStatementCategory>;
  text?: SetFieldOverride<string>;
  quantity?: FieldOverride<number>;
  frequency?: FieldOverride<string>;
  appliesTo?: FieldOverride<readonly StagedServiceType[]>;
}

export interface PackageStatementDecision extends DecisionMetadata {
  decisionKind: "package_statement";
  disposition: "retain_package_level" | "map_to_service" | "exclude";
  service: ServiceReference | null;
  destination: PackageServiceDestination | null;
  overrides: Readonly<PackageStatementOverrides>;
  exclusionReason: ExclusionReason | null;
  exclusionNote: string | null;
}

export interface PackageConditionOverrides {
  kind?: SetFieldOverride<StagedConditionKind>;
  value?: SetFieldOverride<string>;
  appliesTo?: FieldOverride<readonly StagedServiceType[]>;
}

export interface PackageConditionDecision extends DecisionMetadata {
  decisionKind: "package_condition";
  disposition: "retain_package_level" | "map_to_service" | "exclude";
  service: ServiceReference | null;
  destination: PackageServiceDestination | null;
  overrides: Readonly<PackageConditionOverrides>;
  exclusionReason: ExclusionReason | null;
  exclusionNote: string | null;
}

export interface FlightOverrides {
  airline?: FieldOverride<string>;
  flightNumber?: FieldOverride<string>;
  origin?: FieldOverride<string>;
  destination?: FieldOverride<string>;
  departureDate?: FieldOverride<string>;
  departureTime?: FieldOverride<string>;
  arrivalDate?: FieldOverride<string>;
  arrivalTime?: FieldOverride<string>;
  cabinClass?: FieldOverride<string>;
  bookingClass?: FieldOverride<string>;
  notes?: FieldOverride<string>;
  conditions?: FieldOverride<readonly ResolutionCondition[]>;
}

export interface ResolutionCondition {
  kind: StagedConditionKind;
  value: string;
}

export interface FlightDecision extends DecisionMetadata {
  decisionKind: "flight";
  disposition: "route_to_flight_workflow" | "handled_separately" | "exclude";
  destinationId: string | null;
  overrides: Readonly<FlightOverrides>;
  exclusionReason: ExclusionReason | null;
  exclusionNote: string | null;
}

export interface VisaOverrides {
  disposition?: SetFieldOverride<StagedVisaDisposition>;
  text?: FieldOverride<string>;
}

export interface VisaDecision extends DecisionMetadata {
  decisionKind: "visa";
  disposition: "route_to_visa_workflow" | "handled_separately" | "exclude";
  destinationId: string | null;
  overrides: Readonly<VisaOverrides>;
  exclusionReason: ExclusionReason | null;
  exclusionNote: string | null;
}

export type ResolutionReference =
  Readonly<{kind: "decision"; decisionId: string}> |
  Readonly<{kind: "manual_item"; manualItemId: string}>;

export interface ReviewIssueDecision extends DecisionMetadata {
  decisionKind: "review_issue";
  outcome: "acknowledged" | "resolved" | "overridden";
  resolutionReferences: readonly ResolutionReference[];
  overrideReason: ExclusionReason | null;
  overrideNote: string | null;
}

export type SupplierImportDecision =
  TitleDecision |
  StagedDayDecision |
  StagedServiceDecision |
  PackageAccommodationDecision |
  PackageStatementDecision |
  PackageConditionDecision |
  FlightDecision |
  VisaDecision |
  ReviewIssueDecision;

export interface ManualItemMetadata {
  origin: "consultant";
  createdByUid: string;
  createdAt: string;
  updatedByUid: string;
  updatedAt: string;
  lastRevision: number;
}

export interface ConsultantDay extends ManualItemMetadata {
  itemKind: "consultant_day";
  manualDayId: string;
  canonicalOrder: number;
  date: string | null;
  title: string;
  summary: string | null;
  notes: string | null;
}

export interface ManualHotelDetails {
  hotelName: string;
  checkInDate: string | null;
  checkOutDate: string | null;
  roomType: string | null;
  mealPlan: string | null;
  numberOfRooms: number | null;
  supplierStarRating: string | null;
}

export interface ManualTransferDetails {
  pickup: string;
  dropoff: string;
  vehicleType: string | null;
  transferType: StagedTransferType | null;
}

export interface ManualActivityDetails {
  activityName: string;
  duration: string | null;
  activityType: string | null;
}

export interface ConsultantService extends ManualItemMetadata {
  itemKind: "consultant_service";
  manualServiceId: string;
  day: DayReference;
  canonicalOrder: number;
  serviceType: StagedServiceType;
  title: string;
  description: string | null;
  startTime: string | null;
  endTime: string | null;
  location: string | null;
  city: string | null;
  inclusions: readonly string[];
  exclusions: readonly string[];
  notes: string | null;
  hotelDetails: ManualHotelDetails | null;
  transferDetails: ManualTransferDetails | null;
  activityDetails: ManualActivityDetails | null;
}

export type SupplierImportManualItem = ConsultantDay | ConsultantService;

export type SupplierImportAuditAction =
  "open_review" |
  "set_title_decision" |
  "revert_title_decision" |
  "set_day_decision" |
  "set_day_order" |
  "set_service_decision" |
  "set_service_order" |
  "set_package_fact_decision" |
  "set_ancillary_decision" |
  "set_review_issue_decision" |
  "upsert_manual_day" |
  "remove_manual_day" |
  "upsert_manual_service" |
  "remove_manual_service" |
  "revert_decision" |
  "finalize";

export type SupplierImportAuditTargetKind =
  "resolution" | "title" | "day" | "service" | "package_fact" |
  "ancillary_fact" | "review_issue" | "manual_day" | "manual_service" |
  "finalization";

export type SupplierImportAuditDisposition =
  "accept" | "override" | "retain" | "exclude" |
  "map_to_day_service" | "retain_package_level" | "map_to_service" |
  "route_to_flight_workflow" | "route_to_visa_workflow" |
  "handled_separately" | "acknowledged" | "resolved" | "overridden";

export type SupplierImportChangedField =
  "title" | "date" | "summary" | "notes" | "canonicalOrder" | "day" |
  "serviceType" | "description" | "startTime" | "endTime" | "location" |
  "city" | "inclusions" | "exclusions" | "hotelName" | "orSimilar" |
  "checkInDate" | "checkOutDate" | "nightCount" | "roomType" | "mealPlan" |
  "numberOfRooms" | "supplierStarRating" | "pickup" | "dropoff" |
  "vehicleType" | "transferType" | "activityName" | "duration" |
  "activityType" | "category" | "text" | "quantity" | "frequency" |
  "appliesTo" | "kind" | "value" | "airline" | "flightNumber" | "origin" |
  "destination" | "departureDate" | "departureTime" | "arrivalDate" |
  "arrivalTime" | "cabinClass" | "bookingClass" | "conditions" |
  "disposition";

export type SupplierImportAuditMetadata =
  Readonly<{
    kind: "lifecycle";
    status: SupplierImportResolutionStatus;
  }> |
  Readonly<{
    kind: "decision";
    disposition: SupplierImportAuditDisposition;
    changedFields: readonly SupplierImportChangedField[];
    exclusionReason: ExclusionReason | null;
    referencedIds: readonly string[];
  }> |
  Readonly<{
    kind: "manual_item";
    itemKind: "consultant_day" | "consultant_service";
    operation: "added" | "updated" | "removed";
  }>;

export interface SupplierImportAuditEvent {
  eventId: string;
  resolutionId: string;
  extractionId: string;
  previousRevision: number;
  resultingRevision: number;
  actorUid: string;
  occurredAt: string;
  action: SupplierImportAuditAction;
  targetKind: SupplierImportAuditTargetKind;
  targetId: string | null;
  commandId: string;
  metadata: SupplierImportAuditMetadata;
}

export interface SupplierImportResolutionAggregate {
  root: SupplierImportResolutionRoot;
  decisions: readonly SupplierImportDecision[];
  manualItems: readonly SupplierImportManualItem[];
  auditEvents: readonly SupplierImportAuditEvent[];
}
