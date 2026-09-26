import 'itinerary_model_validation.dart';

enum KayraItineraryReviewSeverity {
  warning('warning'),
  blocker('blocker');

  const KayraItineraryReviewSeverity(this.value);
  final String value;

  static KayraItineraryReviewSeverity parse(Object? value) => values.firstWhere(
    (severity) => severity.value == value,
    orElse: () =>
        throw const FormatException('Invalid itinerary review severity.'),
  );
}

final class KayraItineraryReviewIssue {
  KayraItineraryReviewIssue({
    required String id,
    required String fieldPath,
    required String message,
    required this.severity,
  }) : id = ItineraryModelValidation.id(id, 'review issue'),
       fieldPath = ItineraryModelValidation.requiredText(
         fieldPath,
         'Review field path',
       ),
       message = ItineraryModelValidation.requiredText(
         message,
         'Review message',
       );

  factory KayraItineraryReviewIssue.fromMap(Map<String, Object?> data) {
    ItineraryModelValidation.fields(data, {
      'id',
      'fieldPath',
      'message',
      'severity',
    });
    return KayraItineraryReviewIssue(
      id: ItineraryModelValidation.string(data['id']),
      fieldPath: ItineraryModelValidation.string(data['fieldPath']),
      message: ItineraryModelValidation.string(data['message']),
      severity: KayraItineraryReviewSeverity.parse(data['severity']),
    );
  }

  final String id;
  final String fieldPath;
  final String message;
  final KayraItineraryReviewSeverity severity;

  Map<String, Object?> toMap() => {
    'id': id,
    'fieldPath': fieldPath,
    'message': message,
    'severity': severity.value,
  };
}
