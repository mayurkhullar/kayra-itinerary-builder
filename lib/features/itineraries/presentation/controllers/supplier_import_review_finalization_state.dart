import '../../domain/supplier_import_finalization.dart';

enum SupplierImportReviewFinalizationPhase {
  finalizing,
  awaitingReload,
  ambiguous,
  outcome,
  failure,
}

/// One immutable finalization intent/result. Business outcomes remain typed;
/// readiness is supplied by the server, never calculated here.
final class SupplierImportReviewFinalizationState {
  const SupplierImportReviewFinalizationState._(
    this.phase,
    this.request,
    this.outcome, {
    this.attemptedRevision,
  });
  const SupplierImportReviewFinalizationState.finalizing(
    SupplierImportFinalizationRequest request,
  ) : this._(SupplierImportReviewFinalizationPhase.finalizing, request, null);
  const SupplierImportReviewFinalizationState.ambiguous(
    SupplierImportFinalizationRequest request,
  ) : this._(SupplierImportReviewFinalizationPhase.ambiguous, request, null);
  const SupplierImportReviewFinalizationState.awaitingReload(
    SupplierImportFinalizationOutcome outcome, {
    SupplierImportFinalizationRequest? request,
    required int attemptedRevision,
  }) : this._(
         SupplierImportReviewFinalizationPhase.awaitingReload,
         request,
         outcome,
         attemptedRevision: attemptedRevision,
       );
  const SupplierImportReviewFinalizationState.result(
    SupplierImportFinalizationOutcome outcome, {
    int? attemptedRevision,
  }) : this._(
         SupplierImportReviewFinalizationPhase.outcome,
         null,
         outcome,
         attemptedRevision: attemptedRevision,
       );
  const SupplierImportReviewFinalizationState.failure()
    : this._(SupplierImportReviewFinalizationPhase.failure, null, null);

  /// Retained only to prevent resubmitting unchanged capacity-blocked content.
  final int? attemptedRevision;
  final SupplierImportReviewFinalizationPhase phase;
  final SupplierImportFinalizationRequest? request;
  final SupplierImportFinalizationOutcome? outcome;
}
