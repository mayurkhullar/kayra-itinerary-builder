import type {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import type {SupplierImportResolutionAggregate} from "./supplierImportResolution";
import {assembleSupplierImportV2} from "./supplierImportV2Assembly";
import {itineraryDraftV2ImportPolicy} from "./itineraryDraftV2";
import type {SupplierImportFinalizationAssessment, SupplierImportV2AssemblyContext} from "./supplierImportV2AssemblyTypes";
export type {
  FinalizationBlockerCode, FinalizationWarningCode, FinalizationInformationalCode,
  FinalizationFinding, FinalizationTargetKind, SupplierImportFinalizationAssessment,
} from "./supplierImportV2AssemblyTypes";

/** Compatibility assessment. The validation-only envelope is never returned or
 * persisted. A future writer must supply its own trusted context to assembly.
 * Both entry points run the exact same policy and authoritative V2 validator. */
export function assessSupplierImportFinalization(
  snapshot: SupplierExtractionSnapshot,
  resolution: SupplierImportResolutionAggregate,
  context?: SupplierImportV2AssemblyContext,
): SupplierImportFinalizationAssessment {
  const {candidate: _candidate, accounting: _accounting, ...assessment} =
    assembleSupplierImportV2(snapshot, resolution, context ?? {
      draftId: "assessment-only",
      tripId: resolution?.root?.tripId,
      actorUid: resolution?.root?.updatedByUid,
      finalizationId: "assessment-only",
      createdAt: resolution?.root?.createdAt,
      updatedAt: resolution?.root?.updatedAt,
      policyVersion: itineraryDraftV2ImportPolicy,
    });
  return Object.freeze(assessment);
}
