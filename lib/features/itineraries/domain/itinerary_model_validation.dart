abstract final class ItineraryModelValidation {
  static String id(String value, String label) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.contains('/') ||
        value == '.' ||
        value == '..') {
      throw FormatException('Invalid $label identity.');
    }
    return value;
  }

  static String normalizedId(String value, String label) =>
      id(value.trim(), label);

  static String requiredText(String value, String label) {
    final text = value.trim();
    if (text.isEmpty) throw FormatException('$label is required.');
    return text;
  }

  static String? optionalText(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> textList(List<String> values) => List.unmodifiable(
    values.map((value) => value.trim()).where((value) => value.isNotEmpty),
  );

  static void fields(Map<String, Object?> data, Set<String> required) {
    if (!required.every(data.containsKey) || !required.containsAll(data.keys)) {
      throw const FormatException(
        'Incomplete or unsupported itinerary fields.',
      );
    }
  }

  static String string(Object? value) => switch (value) {
    String value => value,
    _ => throw const FormatException('Invalid itinerary text field.'),
  };

  static String? nullableString(Object? value) =>
      value == null ? null : string(value);

  static int integer(Object? value) => switch (value) {
    int value => value,
    _ => throw const FormatException('Invalid itinerary integer field.'),
  };

  static int? nullableInteger(Object? value) =>
      value == null ? null : integer(value);

  static DateTime dateTime(Object? value) => switch (value) {
    DateTime value => value.toUtc(),
    _ => throw const FormatException('Invalid itinerary timestamp.'),
  };

  static DateTime? nullableDate(Object? value) => switch (value) {
    null => null,
    DateTime value => dateOnly(value),
    _ => throw const FormatException('Invalid itinerary date.'),
  };

  static DateTime dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static List<Object?> list(Object? value) => switch (value) {
    List value => List<Object?>.from(value),
    _ => throw const FormatException('Invalid itinerary list field.'),
  };

  static List<String> strings(Object? value) =>
      list(value).map(string).toList();

  static Map<String, Object?> map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid itinerary object field.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid itinerary object key.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}
