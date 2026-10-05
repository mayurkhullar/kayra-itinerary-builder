import '../../data/supplier_extraction_repository.dart';
import '../../data/supplier_import_resolution_mutation_client.dart';
import '../../data/supplier_import_resolution_repository.dart';

enum SupplierImportReviewErrorKind {
  snapshotLoad,
  resolutionLoad,
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

  final SupplierImportReviewErrorKind kind;
  final SupplierExtractionRepositoryFailureKind? snapshotFailureKind;
  final SupplierImportResolutionRepositoryFailureKind? resolutionFailureKind;
  final SupplierImportMutationFailureKind? mutationFailureKind;

  String get userMessage => switch (kind) {
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
