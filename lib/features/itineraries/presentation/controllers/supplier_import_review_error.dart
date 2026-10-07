import '../../data/itinerary_draft_v2_repository.dart';
import '../../data/supplier_extraction_repository.dart';
import '../../data/supplier_import_finalization_client.dart';
import '../../data/supplier_import_resolution_mutation_client.dart';
import '../../data/supplier_import_resolution_repository.dart';

enum SupplierImportReviewErrorKind {
  snapshotLoad,
  resolutionLoad,
  draftLoad,
  sessionExpired,
  permissionDenied,
  malformedData,
  invalidLocalAction,
  invalidMutation,
  serverPrecondition,
  ambiguousNetwork,
  unexpected,
}

final class SupplierImportReviewError {
  const SupplierImportReviewError(
    this.kind, {
    this.snapshotFailureKind,
    this.resolutionFailureKind,
    this.mutationFailureKind,
    this.finalizationFailureKind,
    this.draftFailureKind,
  });

  factory SupplierImportReviewError.snapshot(Object error) =>
      SupplierImportReviewError(
        error is SupplierExtractionRepositoryFailure &&
                error.kind == SupplierExtractionRepositoryFailureKind.malformed
            ? SupplierImportReviewErrorKind.malformedData
            : SupplierImportReviewErrorKind.snapshotLoad,
        snapshotFailureKind: error is SupplierExtractionRepositoryFailure
            ? error.kind
            : null,
      );

  factory SupplierImportReviewError.resolution(
    Object error,
  ) => SupplierImportReviewError(
    error is SupplierImportResolutionRepositoryFailure
        ? switch (error.kind) {
            SupplierImportResolutionRepositoryFailureKind.permissionDenied =>
              SupplierImportReviewErrorKind.permissionDenied,
            SupplierImportResolutionRepositoryFailureKind.malformed =>
              SupplierImportReviewErrorKind.malformedData,
            SupplierImportResolutionRepositoryFailureKind.readFailed =>
              SupplierImportReviewErrorKind.resolutionLoad,
          }
        : SupplierImportReviewErrorKind.resolutionLoad,
    resolutionFailureKind: error is SupplierImportResolutionRepositoryFailure
        ? error.kind
        : null,
  );

  factory SupplierImportReviewError.mutation(
    SupplierImportMutationFailure error,
  ) => SupplierImportReviewError(switch (error.kind) {
    SupplierImportMutationFailureKind.sessionExpired =>
      SupplierImportReviewErrorKind.sessionExpired,
    SupplierImportMutationFailureKind.permissionDenied =>
      SupplierImportReviewErrorKind.permissionDenied,
    SupplierImportMutationFailureKind.invalidMutation =>
      SupplierImportReviewErrorKind.invalidMutation,
    SupplierImportMutationFailureKind.invalidState =>
      SupplierImportReviewErrorKind.serverPrecondition,
    SupplierImportMutationFailureKind.internal =>
      SupplierImportReviewErrorKind.unexpected,
    SupplierImportMutationFailureKind.unavailable =>
      SupplierImportReviewErrorKind.ambiguousNetwork,
  }, mutationFailureKind: error.kind);

  factory SupplierImportReviewError.finalization(
    SupplierImportFinalizationFailure error,
  ) => SupplierImportReviewError(switch (error.kind) {
    SupplierImportFinalizationFailureKind.sessionExpired =>
      SupplierImportReviewErrorKind.sessionExpired,
    SupplierImportFinalizationFailureKind.permissionDenied =>
      SupplierImportReviewErrorKind.permissionDenied,
    SupplierImportFinalizationFailureKind.invalidRequest =>
      SupplierImportReviewErrorKind.invalidMutation,
    SupplierImportFinalizationFailureKind.invalidState =>
      SupplierImportReviewErrorKind.serverPrecondition,
    SupplierImportFinalizationFailureKind.internal =>
      SupplierImportReviewErrorKind.unexpected,
    SupplierImportFinalizationFailureKind.unavailable =>
      SupplierImportReviewErrorKind.ambiguousNetwork,
  }, finalizationFailureKind: error.kind);
  factory SupplierImportReviewError.draft(Object error) =>
      SupplierImportReviewError(
        SupplierImportReviewErrorKind.draftLoad,
        draftFailureKind: error is ItineraryDraftV2RepositoryFailure
            ? error.kind
            : null,
      );
  final SupplierImportFinalizationFailureKind? finalizationFailureKind;
  final ItineraryDraftV2RepositoryFailureKind? draftFailureKind;
  final SupplierImportReviewErrorKind kind;
  final SupplierExtractionRepositoryFailureKind? snapshotFailureKind;
  final SupplierImportResolutionRepositoryFailureKind? resolutionFailureKind;
  final SupplierImportMutationFailureKind? mutationFailureKind;

  String get userMessage => switch (kind) {
    SupplierImportReviewErrorKind.draftLoad =>
      'The finalized itinerary could not be loaded safely. Please refresh.',
    SupplierImportReviewErrorKind.snapshotLoad =>
      'The Supplier Extraction Snapshot could not be loaded. Please try again.',
    SupplierImportReviewErrorKind.resolutionLoad =>
      'The Supplier Import review could not be loaded. Please refresh.',
    SupplierImportReviewErrorKind.sessionExpired =>
      'Your session has expired. Please sign in again.',
    SupplierImportReviewErrorKind.permissionDenied =>
      'You do not have access to this Supplier Import review.',
    SupplierImportReviewErrorKind.malformedData =>
      'The stored Supplier Import review could not be read safely.',
    SupplierImportReviewErrorKind.invalidLocalAction =>
      'This action is not available in the current review state.',
    SupplierImportReviewErrorKind.invalidMutation =>
      'This Supplier Import review change is invalid.',
    SupplierImportReviewErrorKind.serverPrecondition =>
      'This Supplier Import review cannot be changed in its current state.',
    SupplierImportReviewErrorKind.ambiguousNetwork =>
      'The change could not be confirmed. You can safely retry the same change.',
    SupplierImportReviewErrorKind.unexpected =>
      'The Supplier Import review could not be updated. Please try again.',
  };
}
