part of 'itinerary_draft_v2.dart';

/// Mirrors the canonical V2 primitives; does not relax the existing V1 parser.
abstract final class _V2 {
  static Never invalid() =>
      throw const FormatException('Invalid canonical itinerary V2 data.');
  static Map<String, Object?> record(Object? v, Set<String> keys) =>
      SupplierExtractionParsing.exactRecord(v, keys, 'Canonical itinerary V2');
  static List<T> list<T>(Object? v, T Function(Object?) parse) =>
      List<T>.unmodifiable(
        SupplierExtractionParsing.list(v, 'Canonical itinerary V2').map(parse),
      );
  static String id(Object? v) {
    if (v is! String ||
        v.isEmpty ||
        v.trim() != v ||
        v == '.' ||
        v == '..' ||
        RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(v)) {
      invalid();
    }
    return v;
  }

  static int positive(Object? v) {
    if (v is! int || v < 1 || v > 9007199254740991) invalid();
    return v;
  }

  static int? nullablePositive(Object? v) => v == null ? null : positive(v);
  static int position(Object? v, int index) {
    final order = positive(v);
    if (order != index + 1) invalid();
    return order;
  }

  static final _valuePattern = RegExp(
    r'(?:[$€£₹]\s*\d)|(?:\d[\d,.]*\s*(?:[$€£₹]|(?:INR|USD|EUR|GBP|AED|AUD|CAD|CHF|JPY|SGD|THB)\b))|'
    r'(?:\b(?:INR|USD|EUR|GBP|AED|AUD|CAD|CHF|JPY|SGD|THB)\s*\d)|'
    r'(?:\b(?:price|pricing|cost|total|amount|rate|supplement|margin|payment)\b[^.!?\n]{0,32}\d)|'
    r'(?:\d[^.!?\n]{0,32}\b(?:price|pricing|cost|total|amount|rate|supplement|margin|payment)\b)',
    caseSensitive: false,
  );
  static final _termPattern = RegExp(
    r'\b(?:price|amount|currency|supplement|markup|margin|discount|payment|pricing|costs?|rates?|selling\s+price|payment\s+schedule)\b|[$€£₹]',
    caseSensitive: false,
  );
  static String text(Object? v, {bool directPayment = false}) {
    if (v is! String || v.trim().isEmpty) invalid();
    final result = v.trim();
    final terms = directPayment
        ? result.replaceAll(
            RegExp(r'\bdirect\s+payment\b', caseSensitive: false),
            '',
          )
        : result;
    if (_valuePattern.hasMatch(result) || _termPattern.hasMatch(terms)) {
      invalid();
    }
    return result;
  }

  static String? nullableText(Object? v) => v == null ? null : text(v);
  static String? optionalText(Object? v) =>
      v is String && v.trim().isEmpty ? null : nullableText(v);
  static String? label(Object? v) {
    final result = nullableText(v);
    if (result != null &&
        (result.length > 160 ||
            RegExp(
              r'(?:[a-z][a-z\d+.-]*://|^/|\\|\btrips/)',
              caseSensitive: false,
            ).hasMatch(result))) {
      invalid();
    }
    return result;
  }

  static DateTime timestamp(Object? v, {bool dateOnly = false}) {
    if (v is! Timestamp || v.nanoseconds % 1000000 != 0) invalid();
    final date = v.toDate().toUtc();
    if (date.year < 0 ||
        date.year > 9999 ||
        (dateOnly &&
            (date.hour != 0 ||
                date.minute != 0 ||
                date.second != 0 ||
                date.millisecond != 0))) {
      invalid();
    }
    return date;
  }

  static DateTime? timelineDate(Object? v) =>
      v == null ? null : timestamp(v, dateOnly: true);
  static String? packageDate(Object? v) {
    if (v == null) return null;
    if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) invalid();
    final date = DateTime.tryParse('${v}T00:00:00.000Z');
    if (date == null || date.toIso8601String().substring(0, 10) != v) invalid();
    return v;
  }

  static void range(String? start, String? end) {
    if (start != null && end != null && end.compareTo(start) <= 0) invalid();
  }

  static void unique(Iterable<Object?> v) =>
      SupplierExtractionParsing.unique(v, 'canonical identities or values');
  static T enumeration<T extends Enum>(
    Object? v,
    Iterable<T> values,
    String Function(T) name,
  ) => SupplierExtractionParsing.enumValue(v, values, name, 'canonical enum');
  static List<KayraItineraryServiceType> appliesTo(Object? v) {
    final result = list(v, KayraItineraryServiceType.parse);
    unique(result);
    return result;
  }
}
