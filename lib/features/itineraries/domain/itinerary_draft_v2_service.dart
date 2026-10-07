part of 'itinerary_draft_v2.dart';

/// V2-only timeline values keep the legacy V1 reader/writer contract closed.
final class ItineraryDraftV2Day {
  const ItineraryDraftV2Day._({
    required this.dayNumber,
    required this.date,
    required this.title,
    required this.summary,
    required this.notes,
    required this.services,
  });
  final int dayNumber;
  final DateTime? date;
  final String title;
  final String? summary, notes;
  final List<ItineraryDraftV2Service> services;
  Map<String, Object?> toMap() => {
    'dayNumber': dayNumber,
    'date': date,
    'title': title,
    'summary': summary,
    'notes': notes,
    'services': services.map((s) => s.toMap()).toList(),
  };
}

final class ItineraryDraftV2ServiceCondition {
  const ItineraryDraftV2ServiceCondition._(this.kind, this.value);
  final SupplierExtractionConditionKind kind;
  final String value;
  Map<String, Object?> toMap() => {'kind': kind.value, 'value': value};
}

final class ItineraryDraftV2Service {
  const ItineraryDraftV2Service._({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.city,
    required this.notes,
    required this.inclusions,
    required this.exclusions,
    required this.conditions,
    required this.hotelDetails,
    required this.transferDetails,
    required this.activityDetails,
    required this.sourceReference,
  });
  final String id, title;
  final KayraItineraryServiceType type;
  final String? description, startTime, endTime, location, city, notes;
  final List<String> inclusions, exclusions;

  /// Null means the optional field was absent in a historical V2 document.
  final List<ItineraryDraftV2ServiceCondition>? conditions;
  final ItineraryDraftV2TimelineHotelDetails? hotelDetails;
  final KayraItineraryTransferDetails? transferDetails;
  final KayraItineraryActivityDetails? activityDetails;
  final KayraItinerarySourceReference? sourceReference;
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.value,
    'title': title,
    'description': description,
    'startTime': startTime,
    'endTime': endTime,
    'location': location,
    'city': city,
    'notes': notes,
    'inclusions': inclusions.toList(),
    'exclusions': exclusions.toList(),
    if (conditions != null)
      'conditions': conditions!.map((c) => c.toMap()).toList(),
    'hotelDetails': hotelDetails?.toMap(),
    'transferDetails': transferDetails?.toMap(),
    'activityDetails': activityDetails?.toMap(),
    'sourceReference': sourceReference?.toMap(),
  };
}

final class ItineraryDraftV2TimelineHotelDetails {
  const ItineraryDraftV2TimelineHotelDetails._({
    required this.hotelName,
    required this.checkInDate,
    required this.checkOutDate,
    required this.roomType,
    required this.mealPlan,
    required this.numberOfRooms,
    required this.supplierStarRating,
    required this.city,
    required this.orSimilar,
    required this.nightCount,
    required Set<String> present,
  }) : _present = present;
  final String hotelName;
  final DateTime? checkInDate, checkOutDate;
  final String? roomType, mealPlan, supplierStarRating, city;
  final int? numberOfRooms, nightCount;
  final bool? orSimilar;
  final Set<String> _present;
  Map<String, Object?> toMap() => {
    'hotelName': hotelName,
    'checkInDate': checkInDate,
    'checkOutDate': checkOutDate,
    'roomType': roomType,
    'mealPlan': mealPlan,
    'numberOfRooms': numberOfRooms,
    'supplierStarRating': supplierStarRating,
    if (_present.contains('city')) 'city': city,
    if (_present.contains('orSimilar')) 'orSimilar': orSimilar,
    if (_present.contains('nightCount')) 'nightCount': nightCount,
  };
}
