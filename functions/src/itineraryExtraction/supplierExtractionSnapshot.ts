export const supplierExtractionSnapshotSchemaVersion =
  "supplier_extraction_snapshot_v1" as const;

export type StagedServiceType =
  "hotel" | "transfer" | "activity" | "meal" |
  "sightseeing" | "free_time" | "other";

export type StagedTransferType =
  "private" | "shared" | "scheduled" | "other";

export type StagedStatementCategory =
  "accommodation" | "meal" | "guide" | "water" | "entrance" |
  "transport" | "visa" | "other";

export type StagedConditionKind =
  "operating_basis" | "vehicle" | "class" | "ticket_scope" |
  "availability" | "payment_basis" | "guide" | "other";

export type CommercialContentCategory =
  "package_price" | "per_person_price" | "supplement" | "visa_price" |
  "payment_terms" | "other_commercial_terms";

export type StagedVisaDisposition =
  "included" | "excluded" | "requirement" | "mentioned" | "unclear";

export type StagedReviewSeverity = "warning" | "blocker";

export type StagedReviewCode =
  "chronology_unknown" | "accommodation_span_unknown" |
  "classification_ambiguous" | "conflicting_dates" |
  "global_mapping_required" | "source_conflict" | "other";

export interface ProviderSourceLocator {
  fileIndex?: number;
  sourceLabel?: string;
}

export interface TrustedSnapshotSourceReference {
  supplierSourcePackageId: string;
  supplierSourceFileId: string | null;
  sourceLabel: string | null;
}

export interface SupplierExtractionTitle {
  text: string;
  basis: "explicit_supplier" | "neutral_supported";
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface StagedDay {
  id: string;
  order: number;
  sourceDayNumber: number | null;
  date: string | null;
  title: string | null;
  summary: string | null;
  notes: string | null;
  assignedServiceIds: readonly string[];
  sources: readonly TrustedSnapshotSourceReference[];
}

export type StagedServiceScope =
  Readonly<{kind: "day"; dayId: string}> |
  Readonly<{kind: "unassigned"}>;

export interface StagedStatement {
  id: string;
  category: StagedStatementCategory;
  text: string;
  quantity: number | null;
  frequency: string | null;
  appliesTo: readonly StagedServiceType[];
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface StagedCondition {
  id: string;
  kind: StagedConditionKind;
  value: string;
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface StagedHotelDetails {
  hotelName: string | null;
  city: string | null;
  orSimilar: boolean | null;
  checkInDate: string | null;
  checkOutDate: string | null;
  nightCount: number | null;
  roomType: string | null;
  mealPlan: string | null;
  numberOfRooms: number | null;
  supplierStarRating: string | null;
}

export interface StagedTransferDetails {
  pickup: string | null;
  dropoff: string | null;
  vehicleType: string | null;
  transferType: StagedTransferType | null;
}

export interface StagedActivityDetails {
  activityName: string | null;
  duration: string | null;
  activityType: string | null;
}

export interface StagedServiceFact {
  id: string;
  factKind: "service";
  order: number;
  scope: StagedServiceScope;
  serviceType: StagedServiceType | null;
  title: string | null;
  description: string | null;
  startTime: string | null;
  endTime: string | null;
  location: string | null;
  city: string | null;
  inclusions: readonly StagedStatement[];
  exclusions: readonly StagedStatement[];
  conditions: readonly StagedCondition[];
  notes: string | null;
  hotelDetails: StagedHotelDetails | null;
  transferDetails: StagedTransferDetails | null;
  activityDetails: StagedActivityDetails | null;
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface PackageAccommodationFact {
  id: string;
  factKind: "package_accommodation";
  order: number;
  scope: Readonly<{kind: "package"}>;
  details: StagedHotelDetails;
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface PackageStatementFact {
  id: string;
  factKind: "package_inclusion" | "package_exclusion";
  order: number;
  scope: Readonly<{kind: "package"}>;
  category: StagedStatementCategory;
  text: string;
  quantity: number | null;
  frequency: string | null;
  appliesTo: readonly StagedServiceType[];
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface PackageConditionFact {
  id: string;
  factKind: "package_condition";
  order: number;
  scope: Readonly<{kind: "package"}>;
  kind: StagedConditionKind;
  value: string;
  appliesTo: readonly StagedServiceType[];
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface AncillaryFlightFact {
  id: string;
  factKind: "flight";
  order: number;
  scope: Readonly<{kind: "ancillary"}>;
  airline: string | null;
  flightNumber: string | null;
  origin: string | null;
  destination: string | null;
  departureDate: string | null;
  departureTime: string | null;
  arrivalDate: string | null;
  arrivalTime: string | null;
  cabinClass: string | null;
  bookingClass: string | null;
  notes: string | null;
  conditions: readonly StagedCondition[];
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface AncillaryVisaFact {
  id: string;
  factKind: "visa";
  order: number;
  scope: Readonly<{kind: "ancillary"}>;
  disposition: StagedVisaDisposition;
  text: string | null;
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface CommercialPresenceFact {
  id: string;
  factKind: "commercial_presence";
  order: number;
  scope: Readonly<{kind: "package"}>;
  categories: readonly CommercialContentCategory[];
  sources: readonly TrustedSnapshotSourceReference[];
}

export type SupplierExtractionFact =
  StagedServiceFact |
  PackageAccommodationFact |
  PackageStatementFact |
  PackageConditionFact |
  AncillaryFlightFact |
  AncillaryVisaFact |
  CommercialPresenceFact;

export type StagedReviewTarget =
  Readonly<{kind: "snapshot"; entityId: null}> |
  Readonly<{kind: "day"; entityId: string}> |
  Readonly<{kind: "service"; entityId: string}> |
  Readonly<{kind: "package_fact"; entityId: string}> |
  Readonly<{kind: "ancillary_fact"; entityId: string}>;

export type ReviewStructureBasis = "absence_only" | "explicit_relationship";
export interface StagedReviewIssue {
  /** Optional extracted evidence, validated and normalized by the backend.
   * Missing means unknown, never absence-only. No prose-based inference. */
  structureBasis?: ReviewStructureBasis;
  id: string;
  code: StagedReviewCode;
  severity: StagedReviewSeverity;
  message: string;
  target: StagedReviewTarget;
  resolutionRequired: boolean;
  sources: readonly TrustedSnapshotSourceReference[];
}

export interface SupplierExtractionSnapshotCounts {
  days: number;
  assignedServices: number;
  unassignedServices: number;
  packageFacts: number;
  ancillaryFlights: number;
  ancillaryVisas: number;
  commercialIndicators: number;
  reviewIssues: number;
}

export interface SupplierExtractionSnapshot {
  schemaVersion: typeof supplierExtractionSnapshotSchemaVersion;
  extractionId: string;
  tripId: string;
  sourcePackageId: string;
  jobId: string;
  requestedByUid: string;
  createdAt: string;
  providerVersion: string | null;
  title: SupplierExtractionTitle;
  days: readonly StagedDay[];
  facts: readonly SupplierExtractionFact[];
  reviewIssues: readonly StagedReviewIssue[];
  counts: SupplierExtractionSnapshotCounts;
}

export function serializeSupplierExtractionSnapshot(
  snapshot: SupplierExtractionSnapshot,
): string {
  return JSON.stringify(snapshot);
}
