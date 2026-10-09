import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_draft_v2.dart';
import 'itinerary_draft_v2_fixture.dart';

Map<String, dynamic> finalizedCanonicalMap({String commandId = 'intent-1'}) {
  final data = itineraryDraftV2Fixture();
  data['title'] = 'Reviewed coastal journey';
  void lineage(Object? value) {
    if (value is Map) {
      if (value.containsKey('evaluatedRevision')) {
        value['evaluatedRevision'] = 2;
      }
      for (final child in value.values) {
        lineage(child);
      }
    } else if (value is List) {
      for (final child in value) {
        lineage(child);
      }
    }
  }

  lineage(data);
  v2At(data, ['importResult']).addAll({
    'policyVersion': optionalChronologyImportPolicy,
    'finalizationId': commandId,
  });
  final day = v2At(data, ['days', 0]);
  day['title'] = 'Coastal arrival';
  day['summary'] = 'Explore the waterfront.';
  day['notes'] = 'Keep the afternoon flexible.';
  final hotel = v2At(data, ['days', 0, 'services', 0]);
  hotel['title'] = 'Harbour stay';
  hotel['description'] = 'A quiet base near the promenade.';
  hotel['startTime'] = '14:00';
  hotel['endTime'] = '15:00';
  hotel['location'] = 'Waterfront district';
  hotel['city'] = 'Service city';
  hotel['inclusions'] = ['Welcome drink'];
  hotel['exclusions'] = ['Laundry'];
  hotel['notes'] = 'Bring identification.';
  hotel['conditions'] = [
    {'kind': 'availability', 'value': 'Subject to availability'},
  ];
  (hotel['hotelDetails'] as Map<String, dynamic>).addAll({
    'city': 'Hotel city',
    'orSimilar': true,
    'nightCount': 2,
  });
  v2At(data, ['days', 0, 'services', 1])['title'] = 'Arrival transfer';
  v2At(data, ['days', 0, 'services', 2])['title'] = 'Museum experience';
  data['unscheduledServices'] = [
    canonicalServiceMap('included-1', 'Garden walk'),
    canonicalServiceMap('included-2', 'Old town visit'),
  ];
  return data;
}

Map<String, Object?> canonicalServiceMap(
  String id,
  String title, {
  String type = 'other',
}) => {
  'id': id,
  'type': type,
  'title': title,
  'description': null,
  'startTime': null,
  'endTime': null,
  'location': null,
  'city': null,
  'notes': null,
  'inclusions': <String>[],
  'exclusions': <String>[],
  'hotelDetails': null,
  'transferDetails': null,
  'activityDetails': null,
  'sourceReference': null,
};

ItineraryDraftV2 finalizedCanonicalDraft(Map<String, dynamic> data) =>
    ItineraryDraftV2.fromFirestore(data, documentId: 'draft-1');
