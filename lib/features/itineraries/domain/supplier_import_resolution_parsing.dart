import 'supplier_extraction_parsing.dart';

abstract final class SupplierImportResolutionParsing {
  static Map<String, Object?> record(Object? value, String label) =>
      SupplierExtractionParsing.record(value, label);

  static List<Object?> list(Object? value, String label) =>
      SupplierExtractionParsing.list(value, label);

  static Map<String, Object?> exact(
    Object? value,
    Set<String> fields,
    String label,
  ) => SupplierExtractionParsing.exactRecord(value, fields, label);

  static Map<String, Object?> closed(
    Object? value, {
    required Set<String> allowed,
    required Set<String> required,
    required String label,
  }) {
    final data = SupplierExtractionParsing.record(value, label);
    if (!required.every(data.containsKey) || !allowed.containsAll(data.keys)) {
      throw FormatException('$label fields are invalid.');
    }
    return data;
  }

  static String id(Object? value, String label) =>
      SupplierExtractionParsing.id(value, label);

  static String? nullableId(Object? value, String label) =>
      value == null ? null : id(value, label);

  static String text(Object? value, String label) =>
      SupplierExtractionParsing.semanticText(value, label);

  static String? nullableText(Object? value, String label) =>
      SupplierExtractionParsing.nullableSemanticText(value, label);

  static int positiveInt(Object? value, String label) =>
      SupplierExtractionParsing.positiveInteger(value, label);

  static int nonNegativeInt(Object? value, String label) =>
      SupplierExtractionParsing.nonNegativeInteger(value, label);

  static int? nullablePositiveInt(Object? value, String label) =>
      SupplierExtractionParsing.nullablePositiveInteger(value, label);

  static bool boolean(Object? value, String label) =>
      SupplierExtractionParsing.boolean(value, label);

  static DateTime timestamp(Object? value, String label) =>
      SupplierExtractionParsing.timestamp(value, label);

  static DateTime? nullableTimestamp(Object? value, String label) =>
      value == null ? null : timestamp(value, label);

  static String date(Object? value, String label) {
    SupplierExtractionParsing.nullableDate(value, label);
    return value as String;
  }

  static String? nullableDate(Object? value, String label) =>
      value == null ? null : date(value, label);

  static String time(Object? value, String label) {
    final parsed = SupplierExtractionParsing.nullableTime(value, label);
    if (parsed == null) throw FormatException('$label is required.');
    return parsed;
  }

  static String? nullableTime(Object? value, String label) =>
      SupplierExtractionParsing.nullableTime(value, label);

  static List<String> textList(Object? value, String label) {
    final values = SupplierExtractionParsing.list(
      value,
      label,
    ).map((item) => text(item, label)).toList();
    SupplierExtractionParsing.unique(values, label);
    return List.unmodifiable(values);
  }

  static T enumValue<T extends Enum>(
    Object? value,
    Iterable<T> values,
    String Function(T value) persisted,
    String label,
  ) => SupplierExtractionParsing.enumValue(value, values, persisted, label);

  static void unique(Iterable<Object?> values, String label) =>
      SupplierExtractionParsing.unique(values, label);
}
