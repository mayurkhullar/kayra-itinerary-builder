import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_values.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import '../../../domain/supplier_import_resolution_parsing.dart';
import 'staged_service_correction.dart';

String normalizeServiceCorrection(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String? validateServiceCorrectionText(String input) {
  final value = normalizeServiceCorrection(input);
  if (value.isEmpty) return 'Enter a value.';
  if (value.length > 2000) return 'Use 2,000 characters or fewer.';
  if (RegExp(
    r'(?:\b(?:price|amount|currency|supplement|markup|margin|discount|payment)\b|[$€£₹])',
    caseSensitive: false,
  ).hasMatch(value)) {
    return 'Use a non-commercial value for this correction.';
  }
  try {
    SupplierImportResolutionParsing.text(value, 'Service correction');
  } on FormatException {
    return 'Use a non-commercial value for this correction.';
  }
  return null;
}

Object parseServiceCorrection(
  StagedServiceCorrectionField field,
  String input,
) {
  final value = normalizeServiceCorrection(input);
  return switch (field.input) {
    ServiceCorrectionInput.date => SupplierImportResolutionParsing.date(
      value,
      field.label,
    ),
    ServiceCorrectionInput.time => SupplierImportResolutionParsing.time(
      value,
      field.label,
    ),
    ServiceCorrectionInput.count => _count(value),
    _ => SupplierImportResolutionParsing.text(value, field.label),
  };
}

int _count(String value) {
  final count = RegExp(r'^\d+$').hasMatch(value) ? int.tryParse(value) : null;
  if (count == null || count < 1 || count > 9007199254740991) {
    throw const FormatException('Invalid count');
  }
  return count;
}

String? validateServiceCorrectionInput(
  StagedServiceCorrectionField field,
  String input,
) {
  if (field.input == ServiceCorrectionInput.text ||
      field.input == ServiceCorrectionInput.multiline) {
    return validateServiceCorrectionText(input);
  }
  try {
    parseServiceCorrection(field, input);
  } on FormatException {
    return switch (field.input) {
      ServiceCorrectionInput.date => 'Enter a valid date as YYYY-MM-DD.',
      ServiceCorrectionInput.time => 'Enter a time as HH:mm (00:00–23:59).',
      ServiceCorrectionInput.count =>
        'Enter a positive whole number within the supported range.',
      _ => 'Enter a valid value.',
    };
  }
  return null;
}

/// Prevent a type correction from discarding source details or making retained
/// sibling overrides incompatible. Conversion/mapping is outside this editor.
bool serviceTypeCorrectionCompatible(
  SupplierExtractionServiceFact source,
  SupplierImportServiceOverrides overrides,
) {
  final type = overrides.serviceType?.value ?? source.serviceType;
  return (type == SupplierExtractionServiceType.hotel ||
          (source.hotelDetails == null && overrides.hotel == null)) &&
      (type == SupplierExtractionServiceType.transfer ||
          (source.transferDetails == null && overrides.transfer == null)) &&
      (type == SupplierExtractionServiceType.activity ||
          (source.activityDetails == null && overrides.activity == null));
}

String? validateServiceCorrectionComposition(
  SupplierExtractionServiceFact source,
  StagedServiceCorrectionField field,
  SupplierImportServiceOverrides next,
) {
  if (field == StagedServiceCorrectionField.serviceType &&
      !serviceTypeCorrectionCompatible(source, next)) {
    return 'Choose a service type compatible with the supplier details and existing corrections. This editor does not convert detail types.';
  }
  if (field == StagedServiceCorrectionField.checkInDate ||
      field == StagedServiceCorrectionField.checkOutDate) {
    String? effective(
      DateTime? source,
      SupplierImportFieldOverride<String>? override,
    ) => switch (override) {
      SupplierImportSetOverride(:final value) => value,
      SupplierImportClearOverride() => null,
      null => source?.toIso8601String().substring(0, 10),
    };
    final start = effective(
      source.hotelDetails?.checkInDate,
      next.hotel?.checkInDate,
    );
    final end = effective(
      source.hotelDetails?.checkOutDate,
      next.hotel?.checkOutDate,
    );
    if (start != null && end != null && end.compareTo(start) <= 0) {
      return 'Check-out must be after check-in. Correct or explicitly clear the other date separately if needed.';
    }
  }
  return null;
}
