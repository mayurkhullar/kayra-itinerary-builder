import 'itinerary_model_validation.dart';
import 'kayra_itinerary_service.dart';

final class KayraItineraryDay {
  KayraItineraryDay({
    required int dayNumber,
    DateTime? date,
    required String title,
    String? summary,
    List<KayraItineraryService> services = const [],
    String? notes,
  }) : dayNumber = _positiveDayNumber(dayNumber),
       date = date == null ? null : ItineraryModelValidation.dateOnly(date),
       title = ItineraryModelValidation.requiredText(title, 'Day title'),
       summary = ItineraryModelValidation.optionalText(summary),
       services = _services(services),
       notes = ItineraryModelValidation.optionalText(notes);

  factory KayraItineraryDay.fromMap(Map<String, Object?> data) {
    ItineraryModelValidation.fields(data, {
      'dayNumber',
      'date',
      'title',
      'summary',
      'services',
      'notes',
    });
    return KayraItineraryDay(
      dayNumber: ItineraryModelValidation.integer(data['dayNumber']),
      date: ItineraryModelValidation.nullableDate(data['date']),
      title: ItineraryModelValidation.string(data['title']),
      summary: ItineraryModelValidation.nullableString(data['summary']),
      services: ItineraryModelValidation.list(data['services'])
          .map(ItineraryModelValidation.map)
          .map(KayraItineraryService.fromMap)
          .toList(),
      notes: ItineraryModelValidation.nullableString(data['notes']),
    );
  }

  final int dayNumber;
  final DateTime? date;
  final String title;
  final String? summary;
  final List<KayraItineraryService> services;
  final String? notes;

  Map<String, Object?> toMap() => {
    'dayNumber': dayNumber,
    'date': date,
    'title': title,
    'summary': summary,
    'services': services.map((service) => service.toMap()).toList(),
    'notes': notes,
  };

  static int _positiveDayNumber(int value) {
    if (value < 1) {
      throw const FormatException('Itinerary day number must be positive.');
    }
    return value;
  }

  static List<KayraItineraryService> _services(
    List<KayraItineraryService> values,
  ) {
    final ids = values.map((service) => service.id).toSet();
    if (ids.length != values.length) {
      throw const FormatException('Duplicate itinerary service identities.');
    }
    return List.unmodifiable(values);
  }
}
