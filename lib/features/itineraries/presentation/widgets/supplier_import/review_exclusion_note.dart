import '../../../domain/supplier_import_resolution_overrides.dart';

/// Immediate input feedback only; semantic validation remains server-owned.
String? validateReviewExclusionNote(
  String note,
  SupplierImportExclusionReason? reason, {
  required String subject,
}) {
  if (note.isEmpty) {
    return reason == SupplierImportExclusionReason.other
        ? 'Explain why this $subject is being excluded.'
        : null;
  }
  if (note.length > 2000) return 'Use 2,000 characters or fewer.';
  if (RegExp(
    r'(?:\b(?:price|amount|currency|supplement|markup|margin|discount|payment)\b|[$€£₹])',
    caseSensitive: false,
  ).hasMatch(note)) {
    return 'Use a non-commercial explanation for this exclusion.';
  }
  return null;
}
