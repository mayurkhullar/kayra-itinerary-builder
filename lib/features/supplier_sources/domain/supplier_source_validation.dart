/// Shared metadata validation; no Firebase dependency or filename sanitization.
abstract final class SupplierSourceValidation {
  static String id(String value) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.contains('/') ||
        value == '.' ||
        value == '..') {
      throw const FormatException('Invalid source metadata identity.');
    }
    return value;
  }

  static String requiredText(String value) {
    if (value.trim().isEmpty) {
      throw const FormatException('Source metadata text is required.');
    }
    return value;
  }

  static void fields(Map<String, Object?> data, Set<String> required) {
    if (!required.every(data.containsKey) || !required.containsAll(data.keys)) {
      throw const FormatException('Incomplete or unsupported source fields.');
    }
  }

  static String string(Object? value) => switch (value) {
    String value => value,
    _ => throw const FormatException('Invalid source text field.'),
  };

  static String? nullableString(Object? value) =>
      value == null ? null : string(value);

  static List<String> strings(Object? value) => switch (value) {
    List value => value.map(string).toList(),
    _ => throw const FormatException('Invalid source list field.'),
  };

  static DateTime dateTime(Object? value) => switch (value) {
    DateTime value => value.toUtc(),
    _ => throw const FormatException('Invalid source timestamp.'),
  };

  static int integer(Object? value) => switch (value) {
    int value => value,
    _ => throw const FormatException('Invalid source integer field.'),
  };

  static String scopedTrip(Object? value, String expectedTripId) {
    id(expectedTripId);
    final tripId = id(string(value));
    if (tripId != expectedTripId) {
      throw const FormatException('Source metadata belongs to another Trip.');
    }
    return tripId;
  }
}
