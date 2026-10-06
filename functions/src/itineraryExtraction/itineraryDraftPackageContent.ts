import type {ItineraryServiceType} from "./draftValidation";
import type {
  StagedConditionKind,
  StagedHotelDetails,
  StagedStatementCategory,
} from "./supplierExtractionSnapshot";

export const maxItineraryPackageRecords = 256;

export type PackageHotelDetails = Readonly<StagedHotelDetails>;
export type PackageHotelField = keyof PackageHotelDetails;
export type PackageStatementField =
  "category" | "text" | "quantity" | "frequency" | "appliesTo";
export type PackageConditionField = "kind" | "value" | "appliesTo";

export interface SupplierFactProvenance<Field extends string> {
  readonly origin: "supplier";
  readonly extractionId: string;
  readonly sourcePackageId: string;
  readonly contributors: readonly Readonly<{
    stagedFactId: string;
    sources: readonly Readonly<{
      supplierSourceFileId: string | null;
      sourceLabel: string | null;
    }>[];
  }>[];
  readonly resolutionId: string;
  readonly evaluatedRevision: number;
  readonly decisionIds: readonly string[];
  readonly fieldChanges: readonly Readonly<{
    field: Field;
    operation: "set" | "clear";
  }>[];
}

export interface AccommodationOption {
  readonly id: string;
  readonly order: number;
  readonly details: PackageHotelDetails;
  readonly provenance: SupplierFactProvenance<PackageHotelField>;
}

export interface PackageAccommodation {
  readonly id: string;
  readonly order: number;
  readonly selection: "single" | "alternatives";
  readonly options: readonly AccommodationOption[];
}

export interface PackageStatement {
  readonly id: string;
  readonly order: number;
  readonly category: StagedStatementCategory;
  readonly text: string;
  readonly quantity: number | null;
  readonly frequency: string | null;
  readonly appliesTo: readonly ItineraryServiceType[];
  readonly provenance: SupplierFactProvenance<PackageStatementField>;
}

export interface PackageCondition {
  readonly id: string;
  readonly order: number;
  readonly kind: StagedConditionKind;
  readonly value: string;
  readonly appliesTo: readonly ItineraryServiceType[];
  readonly provenance: SupplierFactProvenance<PackageConditionField>;
}

export interface ItineraryDraftPackageContent {
  readonly accommodations: readonly PackageAccommodation[];
  readonly inclusions: readonly PackageStatement[];
  readonly exclusions: readonly PackageStatement[];
  readonly conditions: readonly PackageCondition[];
}
