import 'itinerary_model_validation.dart';

abstract final class SupplierExtractionParsing {
  static final RegExp _commercialPattern = RegExp(
    r'(?:[$€£₹]\s*\d)|'
    r'(?:\d[\d,.]*\s*(?:[$€£₹]|(?:INR|USD|EUR|GBP|AED|AUD|CAD|CHF|JPY|SGD|THB)\b))|'
    r'(?:\b(?:INR|USD|EUR|GBP|AED|AUD|CAD|CHF|JPY|SGD|THB)\s*\d)|'
    r'(?:\b(?:price|pricing|cost|total|amount|rate|supplement|margin|payment)\b[^.!?\n]{0,32}\d)|'
    r'(?:\d[^.!?\n]{0,32}\b(?:price|pricing|cost|total|amount|rate|supplement|margin|payment)\b)',
    caseSensitive: false,
  );

  static Map<String, Object?> record(Object? value, String label) {
    if (value is! Map) throw FormatException('$label must be an object.');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('$label contains an invalid key.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static Map<String, Object?> exactRecord(
    Object? value,
    Set<String> fields,
    String label,
  ) {
    final data = record(value, label);
    if (data.length != fields.length ||
        !fields.every(data.containsKey) ||
        !fields.containsAll(data.keys)) {
      throw FormatException('$label fields are invalid.');
    }
    return data;
  }

  static List<Object?> list(Object? value, String label) {
    if (value is! List) throw FormatException('$label must be a list.');
    return List<Object?>.from(value);
  }

  static String text(Object? value, String label) {
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw FormatException('$label must be normalized non-empty text.');
    }
    return value;
  }

  static String semanticText(Object? value, String label) {
    final result = text(value, label);
    if (_commercialPattern.hasMatch(result)) {
      throw FormatException('$label contains commercial data.');
    }
    return result;
  }

  static String? nullableText(Object? value, String label) =>
      value == null ? null : text(value, label);

  static String? nullableSemanticText(Object? value, String label) =>
      value == null ? null : semanticText(value, label);

  static String id(Object? value, String label) =>
      ItineraryModelValidation.id(text(value, label), label);

  static int integer(Object? value, String label) {
    if (value is! int) throw FormatException('$label must be an integer.');
    return value;
  }

  static int positiveInteger(Object? value, String label) {
    final result = integer(value, label);
    if (result < 1) throw FormatException('$label must be positive.');
    return result;
  }

  static int nonNegativeInteger(Object? value, String label) {
    final result = integer(value, label);
    if (result < 0) throw FormatException('$label cannot be negative.');
    return result;
  }

  static int? nullablePositiveInteger(Object? value, String label) =>
      value == null ? null : positiveInteger(value, label);

  static bool boolean(Object? value, String label) {
    if (value is! bool) throw FormatException('$label must be a boolean.');
    return value;
  }

  static bool? nullableBoolean(Object? value, String label) =>
      value == null ? null : boolean(value, label);

  static DateTime timestamp(Object? value, String label) {
    if (value is! DateTime) throw FormatException('$label is invalid.');
    return value.toUtc();
  }

  static DateTime? nullableDate(Object? value, String label) {
    if (value == null) return null;
    final textValue = text(value, label);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(textValue);
    if (match == null) throw FormatException('$label must use YYYY-MM-DD.');
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final result = DateTime.utc(year, month, day);
    if (result.year != year || result.month != month || result.day != day) {
      throw FormatException('$label is not a valid date.');
    }
    return result;
  }

  static String? nullableTime(Object? value, String label) {
    if (value == null) return null;
    final result = text(value, label);
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(result)) {
      throw FormatException('$label must use HH:mm.');
    }
    return result;
  }

  static T enumValue<T extends Enum>(
    Object? value,
    Iterable<T> values,
    String Function(T value) persistedValue,
    String label,
  ) {
    for (final item in values) {
      if (persistedValue(item) == value) return item;
    }
    throw FormatException('Unknown $label.');
  }

  static T? nullableEnum<T extends Enum>(
    Object? value,
    Iterable<T> values,
    String Function(T value) persistedValue,
    String label,
  ) => value == null ? null : enumValue(value, values, persistedValue, label);

  static List<T> immutableList<T>(Iterable<T> values) =>
      List<T>.unmodifiable(values);

  static void unique(Iterable<Object?> values, String label) {
    final list = values.toList();
    if (list.toSet().length != list.length) {
      throw FormatException('Duplicate $label.');
    }
  }
}
