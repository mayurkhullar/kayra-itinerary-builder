enum SupplierSourceUploadFailureKind {
  validation,
  packagePreparation,
  upload,
  finalization,
  rollbackIncomplete,
}

enum SupplierSourceUploadValidationIssue {
  unsupportedType,
  emptyFile,
  tooLarge,
  changedDuringSelection,
  unknown,
}

/// Safe for UI consumption: no SDK messages, filenames or document contents.
final class SupplierSourceUploadFailure implements Exception {
  SupplierSourceUploadFailure(
    this.kind, {
    this.packageId,
    this.originalKind,
    List<String> cleanupFailedFileIds = const [],
    this.packageFailureUnconfirmed = false,
    this.validationIssue,
  }) : cleanupFailedFileIds = List.unmodifiable(cleanupFailedFileIds);

  final SupplierSourceUploadFailureKind kind;
  final String? packageId;
  final SupplierSourceUploadFailureKind? originalKind;
  final List<String> cleanupFailedFileIds;
  final bool packageFailureUnconfirmed;
  final SupplierSourceUploadValidationIssue? validationIssue;

  String get message => switch (kind) {
    SupplierSourceUploadFailureKind.validation =>
      'Choose supported, non-empty files of at most 25 MB each.',
    SupplierSourceUploadFailureKind.packagePreparation =>
      'The source upload could not be prepared.',
    SupplierSourceUploadFailureKind.upload =>
      'The source files could not be uploaded.',
    SupplierSourceUploadFailureKind.finalization =>
      'The source package could not be completed.',
    SupplierSourceUploadFailureKind.rollbackIncomplete =>
      'The upload did not complete and some cleanup remains unresolved.',
  };

  @override
  String toString() => message;
}
