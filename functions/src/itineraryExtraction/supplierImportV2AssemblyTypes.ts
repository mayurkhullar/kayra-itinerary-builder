import type {ItineraryDraftV2, itineraryDraftV2ImportPolicy} from "./itineraryDraftV2";
import type {PackageServiceDestination} from "./supplierImportResolution";
import type {SupplierExtractionFact, TrustedSnapshotSourceReference} from "./supplierExtractionSnapshot";

export type FinalizationBlockerCode =
  "resolution_already_finalized" |
  "missing_day_title" |
  "duplicate_day_order" |
  "unresolved_unassigned_service" |
  "missing_service_day" |
  "missing_service_order" |
  "missing_service_type" |
  "missing_service_title" |
  "missing_required_service_details" |
  "duplicate_service_order" |
  "unsupported_service_content" |
  "unresolved_package_accommodation" |
  "incomplete_package_accommodation" |
  "unsupported_package_accommodation_content" |
  "package_level_destination_unavailable" |
  "unresolved_package_fact" |
  "unresolved_ancillary_fact" |
  "unresolved_review_issue" |
  "structural_review_issue_unresolved" |
  "invalid_snapshot" | "invalid_resolution" | "invalid_assembly_context" |
  "unsupported_package_mapping" | "package_record_limit_exceeded" |
  "canonical_validation_failed";

export type FinalizationWarningCode =
  "review_issue_override_available" |
  "snapshot_warning_open" |
  "snapshot_warning_acknowledged" |
  "review_issue_overridden";

export type FinalizationInformationalCode =
  "commercial_presence" |
  "resolution_finalized";

export type FinalizationTargetKind =
  "resolution" | "day" | "service" | "package_fact" |
  "ancillary_fact" | "review_issue" | "commercial_fact";

export interface FinalizationFinding<Code extends string = string> {
  code: Code;
  targetKind: FinalizationTargetKind;
  targetId: string | null;
}

export interface SupplierImportFinalizationAssessment {
  resolutionId: string;
  evaluatedRevision: number;
  canFinalize: boolean;
  blockers: readonly FinalizationFinding<FinalizationBlockerCode>[];
  warnings: readonly FinalizationFinding<FinalizationWarningCode>[];
  informational: readonly FinalizationFinding<FinalizationInformationalCode>[];
}

/** Backend-owned values; no clock, identity allocation or persistence here. */
export interface SupplierImportV2AssemblyContext {
  readonly draftId: string;
  readonly tripId: string;
  readonly actorUid: string;
  readonly finalizationId: string;
  readonly createdAt: string;
  readonly updatedAt: string;
  readonly policyVersion: typeof itineraryDraftV2ImportPolicy;
}

export type ImportAccountingOutcome = "auto_retained" | "explicit_retained" |
  "mapped" | "excluded" | "blocked" | "manual" | "handled_separately" |
  "routed" | "informational" | "review_resolved" | "review_derived" | "review_overridden" |
  "review_open_warning" | "review_acknowledged";

/** Private finalizer input, separate from the canonical candidate. Never a receipt. */
export interface SupplierImportAccounting {
  readonly entityId: string;
  readonly entityKind: SupplierExtractionFact["factKind"] | "title" | "day" | "consultant_day" | "consultant_service" | "review_issue";
  readonly origin: "supplier" | "consultant";
  readonly outcome: ImportAccountingOutcome;
  readonly outputIds: readonly string[];
  /** Timeline days have dayNumber, not an invented canonical document ID. */
  readonly outputDayNumber: number | null;
  readonly mappingDestination: PackageServiceDestination | null;
  readonly sources: readonly TrustedSnapshotSourceReference[];
  readonly decisionIds: readonly string[];
  readonly fieldChanges: readonly {field: string; operation: "set" | "clear"}[];
}

export type SupplierImportV2AssemblyResult = SupplierImportFinalizationAssessment & {
  readonly accounting: readonly SupplierImportAccounting[];
} & (
  {readonly canFinalize: true; readonly candidate: ItineraryDraftV2} |
  {readonly canFinalize: false; readonly candidate: null}
);
