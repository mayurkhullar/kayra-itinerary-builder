import {
  CommercialContentCategory,
  StagedConditionKind,
  StagedReviewCode,
  StagedReviewSeverity,
  StagedServiceType,
  StagedStatementCategory,
  StagedTransferType,
  StagedVisaDisposition,
  SupplierExtractionSnapshot,
} from "./supplierExtractionSnapshot";
import {
  normalizeSupplierExtractionSnapshot,
  SupplierExtractionNormalizationContext,
} from "./supplierExtractionValidation";
import {
  TrustedSupplierSourcePackage,
} from "./sourceReaderValidation";

export const supplierExtractionV3ProviderVersion =
  "kayra_itinerary_extraction_v3_staging" as const;

export interface ProviderSupplierSourceLocatorV3 {
  fileIndex?: number;
  sourceLabel?: string;
}

export interface ProviderSupplierTitleV3 {
  text: string;
  basis: "explicit_supplier" | "neutral_supported";
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierStatementV3 {
  category: StagedStatementCategory;
  text: string;
  quantity?: number;
  frequency?: string;
  appliesTo?: readonly StagedServiceType[];
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierConditionV3 {
  kind: StagedConditionKind;
  value: string;
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierHotelDetailsV3 {
  hotelName?: string;
  city?: string;
  orSimilar?: boolean;
  checkInDate?: string;
  checkOutDate?: string;
  nightCount?: number;
  roomType?: string;
  mealPlan?: string;
  numberOfRooms?: number;
  supplierStarRating?: string;
}

export interface ProviderSupplierTransferDetailsV3 {
  pickup?: string;
  dropoff?: string;
  vehicleType?: string;
  transferType?: StagedTransferType;
}

export interface ProviderSupplierActivityDetailsV3 {
  activityName?: string;
  duration?: string;
  activityType?: string;
}

export interface ProviderSupplierServiceV3 {
  type?: StagedServiceType;
  title?: string;
  description?: string;
  startTime?: string;
  endTime?: string;
  location?: string;
  city?: string;
  inclusions?: readonly ProviderSupplierStatementV3[];
  exclusions?: readonly ProviderSupplierStatementV3[];
  conditions?: readonly ProviderSupplierConditionV3[];
  notes?: string;
  hotelDetails?: ProviderSupplierHotelDetailsV3;
  transferDetails?: ProviderSupplierTransferDetailsV3;
  activityDetails?: ProviderSupplierActivityDetailsV3;
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierDayV3 {
  sourceDayNumber?: number;
  date?: string;
  title?: string;
  summary?: string;
  notes?: string;
  services?: readonly ProviderSupplierServiceV3[];
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierPackageAccommodationV3 extends
  ProviderSupplierHotelDetailsV3 {
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierPackageConditionV3 {
  kind: StagedConditionKind;
  value: string;
  appliesTo?: readonly StagedServiceType[];
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierPackageFactsV3 {
  accommodations?: readonly ProviderSupplierPackageAccommodationV3[];
  inclusions?: readonly ProviderSupplierStatementV3[];
  exclusions?: readonly ProviderSupplierStatementV3[];
  conditions?: readonly ProviderSupplierPackageConditionV3[];
}

export interface ProviderSupplierFlightV3 {
  airline?: string;
  flightNumber?: string;
  origin?: string;
  destination?: string;
  departureDate?: string;
  departureTime?: string;
  arrivalDate?: string;
  arrivalTime?: string;
  cabinClass?: string;
  bookingClass?: string;
  notes?: string;
  conditions?: readonly ProviderSupplierConditionV3[];
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierVisaV3 {
  disposition: StagedVisaDisposition;
  text?: string;
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierAncillaryFactsV3 {
  flights?: readonly ProviderSupplierFlightV3[];
  visas?: readonly ProviderSupplierVisaV3[];
}

export interface ProviderSupplierCommercialContentV3 {
  present: boolean;
  categories?: readonly CommercialContentCategory[];
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export type ProviderSupplierReviewTargetV3 =
  Readonly<{kind: "snapshot"}> |
  Readonly<{kind: "day"; dayIndex: number}> |
  Readonly<{
    kind: "service";
    scope: "day";
    dayIndex: number;
    serviceIndex: number;
  }> |
  Readonly<{
    kind: "service";
    scope: "unassigned";
    serviceIndex: number;
  }> |
  Readonly<{
    kind: "package_fact";
    factType: "accommodation" | "inclusion" | "exclusion" | "condition";
    factIndex: number;
  }> |
  Readonly<{
    kind: "ancillary_fact";
    factType: "flight" | "visa";
    factIndex: number;
  }>;

export interface ProviderSupplierReviewIssueV3 {
  code: StagedReviewCode;
  severity: StagedReviewSeverity;
  message: string;
  target: ProviderSupplierReviewTargetV3;
  resolutionRequired: boolean;
  sources?: readonly ProviderSupplierSourceLocatorV3[];
}

export interface ProviderSupplierExtractionV3 {
  title?: ProviderSupplierTitleV3;
  days?: readonly ProviderSupplierDayV3[];
  unassignedServices?: readonly ProviderSupplierServiceV3[];
  packageFacts?: ProviderSupplierPackageFactsV3;
  ancillaryFacts?: ProviderSupplierAncillaryFactsV3;
  commercialContent?: ProviderSupplierCommercialContentV3;
  reviewIssues?: readonly ProviderSupplierReviewIssueV3[];
}

export type SupplierExtractionV3NormalizationContext = Omit<
  SupplierExtractionNormalizationContext,
  "providerVersion"
>;

/**
 * Strictly validates a parsed provider response without assigning trusted
 * application metadata or persisting it. The returned DTO retains the sparse
 * provider shape and is deeply frozen.
 */
export function validateProviderSupplierExtractionV3(
  input: unknown,
  trustedPackage: TrustedSupplierSourcePackage,
): ProviderSupplierExtractionV3 {
  normalizeProviderSupplierExtractionV3(input, {
    extractionId: "provider-validation",
    tripId: trustedPackage.tripId,
    sourcePackageId: trustedPackage.packageId,
    jobId: "provider-validation",
    requestedByUid: "provider-validation",
    createdAt: new Date(0),
    trustedPackage,
  });
  return deepFreezeProviderDto(input as ProviderSupplierExtractionV3);
}

/**
 * Converts an untrusted V3 provider response into the trusted immutable
 * Supplier Extraction Snapshot domain. The provider version and every trusted
 * identity come from this backend boundary, never from provider output.
 */
export function normalizeProviderSupplierExtractionV3(
  input: unknown,
  context: SupplierExtractionV3NormalizationContext,
): SupplierExtractionSnapshot {
  return normalizeSupplierExtractionSnapshot(
    withBackendTitleFallback(input),
    {...context, providerVersion: supplierExtractionV3ProviderVersion},
  );
}

function withBackendTitleFallback(input: unknown): unknown {
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      input instanceof Date) {
    return input;
  }
  const record = input as Record<string, unknown>;
  if (Object.prototype.hasOwnProperty.call(record, "title")) return input;
  return {
    ...record,
    title: {
      text: "Supplier itinerary",
      basis: "neutral_supported",
    },
  };
}

function deepFreezeProviderDto<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    for (const nested of Object.values(value as Record<string, unknown>)) {
      deepFreezeProviderDto(nested);
    }
    Object.freeze(value);
  }
  return value;
}
