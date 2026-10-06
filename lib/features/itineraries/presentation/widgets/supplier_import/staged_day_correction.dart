import '../../../domain/supplier_extraction_snapshot.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import '../../../domain/supplier_import_resolution_parsing.dart';

/// Editor choices only; persistence uses the existing typed day overrides.
enum StagedDayCorrectionField {
  title('Title'),
  date('Date'),
  summary('Summary'),
  notes('Notes');

  const StagedDayCorrectionField(this.label);
  final String label;
  bool get canClear => this != title;
  bool get multiline => this == summary || this == notes;

  String? sourceValue(SupplierExtractionStagedDay day) => switch (this) {
    title => day.title,
    date => day.date?.toIso8601String().substring(0, 10),
    summary => day.summary,
    notes => day.notes,
  };

  SupplierImportFieldOverride<String>? overrideIn(
    SupplierImportDayOverrides? overrides,
  ) => switch (this) {
    title => overrides?.title,
    date => overrides?.date,
    summary => overrides?.summary,
    notes => overrides?.notes,
  };
}

String dayCorrectionLabel(SupplierImportFieldOverride<String>? value) =>
    switch (value) {
      SupplierImportSetOverride<String>(:final value) => value,
      SupplierImportClearOverride<String>() => 'Cleared for import',
      null => 'Untouched · use supplier value',
    };

String normalizeDayCorrection(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// UX preflight mirrors the server's text constraints, then uses the domain
/// parser as well. Neither this nor the editor replaces backend validation.
String? validateDayCorrection(StagedDayCorrectionField field, String input) {
  final value = normalizeDayCorrection(input);
  if (value.isEmpty) return 'Enter a ${field.label.toLowerCase()} value.';
  if (value.length > 2000) return 'Use 2,000 characters or fewer.';
  if (RegExp(
    r'(?:\b(?:price|amount|currency|supplement|markup|margin|discount|payment)\b|[$€£₹])',
    caseSensitive: false,
  ).hasMatch(value)) {
    return 'Use a non-commercial value for this correction.';
  }
  try {
    if (field == StagedDayCorrectionField.date) {
      SupplierImportResolutionParsing.date(value, 'Day date');
    } else {
      SupplierImportResolutionParsing.text(value, 'Day correction');
    }
  } on FormatException {
    return field == StagedDayCorrectionField.date
        ? 'Enter a valid date as YYYY-MM-DD.'
        : 'Use a non-commercial value for this correction.';
  }
  return null;
}
