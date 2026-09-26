import 'itinerary_model_validation.dart';
import 'kayra_itinerary_day.dart';
import 'kayra_itinerary_review_issue.dart';

final class KayraItineraryDraft {
  KayraItineraryDraft({
    required String id,
    required String tripId,
    required String title,
    List<KayraItineraryDay> days = const [],
    List<String> sourcePackageIds = const [],
    List<KayraItineraryReviewIssue> reviewIssues = const [],
    required String createdByUid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : id = ItineraryModelValidation.id(id, 'itinerary draft'),
       tripId = ItineraryModelValidation.id(tripId, 'trip'),
       title = ItineraryModelValidation.requiredText(title, 'Itinerary title'),
       days = _orderedDays(days),
       sourcePackageIds = _sourcePackageIds(sourcePackageIds),
       reviewIssues = _reviewIssues(reviewIssues),
       createdByUid = ItineraryModelValidation.id(createdByUid, 'creator'),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  /// A future repository converts Firestore Timestamp values before parsing.
  factory KayraItineraryDraft.fromMap(
    Map<String, Object?> data, {
    required String documentId,
  }) {
    ItineraryModelValidation.fields(data, {
      'tripId',
      'title',
      'days',
      'sourcePackageIds',
      'reviewIssues',
      'createdByUid',
      'createdAt',
      'updatedAt',
    });
    return KayraItineraryDraft(
      id: documentId,
      tripId: ItineraryModelValidation.string(data['tripId']),
      title: ItineraryModelValidation.string(data['title']),
      days: ItineraryModelValidation.list(data['days'])
          .map(ItineraryModelValidation.map)
          .map(KayraItineraryDay.fromMap)
          .toList(),
      sourcePackageIds: ItineraryModelValidation.strings(
        data['sourcePackageIds'],
      ),
      reviewIssues: ItineraryModelValidation.list(data['reviewIssues'])
          .map(ItineraryModelValidation.map)
          .map(KayraItineraryReviewIssue.fromMap)
          .toList(),
      createdByUid: ItineraryModelValidation.string(data['createdByUid']),
      createdAt: ItineraryModelValidation.dateTime(data['createdAt']),
      updatedAt: ItineraryModelValidation.dateTime(data['updatedAt']),
    );
  }

  final String id;
  final String tripId;
  final String title;
  final List<KayraItineraryDay> days;
  final List<String> sourcePackageIds;
  final List<KayraItineraryReviewIssue> reviewIssues;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'tripId': tripId,
    'title': title,
    'days': days.map((day) => day.toMap()).toList(),
    'sourcePackageIds': sourcePackageIds.toList(),
    'reviewIssues': reviewIssues.map((issue) => issue.toMap()).toList(),
    'createdByUid': createdByUid,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  static List<KayraItineraryDay> _orderedDays(List<KayraItineraryDay> values) {
    final ordered = List<KayraItineraryDay>.of(values)
      ..sort((left, right) => left.dayNumber.compareTo(right.dayNumber));
    if (ordered.map((day) => day.dayNumber).toSet().length != ordered.length) {
      throw const FormatException('Duplicate itinerary day numbers.');
    }
    return List.unmodifiable(ordered);
  }

  static List<String> _sourcePackageIds(List<String> values) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final value in values) {
      final id = ItineraryModelValidation.normalizedId(
        value,
        'supplier source package',
      );
      if (seen.add(id)) normalized.add(id);
    }
    return List.unmodifiable(normalized);
  }

  static List<KayraItineraryReviewIssue> _reviewIssues(
    List<KayraItineraryReviewIssue> values,
  ) {
    if (values.map((issue) => issue.id).toSet().length != values.length) {
      throw const FormatException(
        'Duplicate itinerary review issue identities.',
      );
    }
    return List.unmodifiable(values);
  }
}
