import type {
  ValidatedItineraryDay,
  ValidatedReviewIssue,
} from "./draftValidation";
import type {ItineraryDraftPackageContent} from "./itineraryDraftPackageContent";

export const itineraryDraftV2SchemaVersion = "itinerary_draft_v2" as const;
export const itineraryDraftV2ImportPolicy = "supplier_import_exception_review_v1" as const;

// Dates retain the existing canonical timeline semantics. The validator exposes
// defensive Date copies through getters, since Object.freeze(Date) alone does
// not prevent setTime/setUTCDate from mutating its internal value.
export type ImmutableDraftValue<T> = T extends Date ? Date :
  T extends readonly (infer Item)[] ? readonly ImmutableDraftValue<Item>[] :
  T extends object ? {readonly [Key in keyof T]: ImmutableDraftValue<T[Key]>} : T;

export type ItineraryDraftV2Day = ImmutableDraftValue<ValidatedItineraryDay>;

export interface ItineraryDraftImportResult {
  readonly extractionId: string;
  readonly resolutionId: string;
  readonly evaluatedRevision: number;
  readonly sourcePackageId: string;
  readonly finalizationId: string;
  readonly policyVersion: typeof itineraryDraftV2ImportPolicy;
}

export interface ItineraryDraftV2 {
  /** Document identity supplied separately to fromMap; never stored in its map. */
  readonly id: string;
  readonly tripId: string;
  readonly schemaVersion: typeof itineraryDraftV2SchemaVersion;
  readonly title: string;
  readonly days: readonly ItineraryDraftV2Day[];
  readonly sourcePackageIds: readonly string[];
  readonly reviewIssues: readonly Readonly<ValidatedReviewIssue>[];
  readonly createdByUid: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
  readonly packageContent: ItineraryDraftPackageContent;
  // Required for this initial Supplier Import contract. Manual/reuse origins
  // require a future explicit contract, not null or fabricated import linkage.
  readonly importResult: ItineraryDraftImportResult;
}
