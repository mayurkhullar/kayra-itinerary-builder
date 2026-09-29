import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';

final supplierExtractionCreatedAt = DateTime.utc(2026, 9, 29, 8);

Map<String, Object?> supplierExtractionSource({
  String packageId = 'package-1',
  String? fileId = 'file-1',
  String? label = 'Page 1',
}) => {
  'supplierSourcePackageId': packageId,
  'supplierSourceFileId': fileId,
  'sourceLabel': label,
};

List<Map<String, Object?>> supplierExtractionSources() => [
  supplierExtractionSource(),
];

Map<String, Object?> supplierExtractionCounts({
  int days = 2,
  int assignedServices = 2,
  int unassignedServices = 1,
  int packageFacts = 4,
  int ancillaryFlights = 1,
  int ancillaryVisas = 1,
  int commercialIndicators = 1,
  int reviewIssues = 6,
}) => {
  'days': days,
  'assignedServices': assignedServices,
  'unassignedServices': unassignedServices,
  'packageFacts': packageFacts,
  'ancillaryFlights': ancillaryFlights,
  'ancillaryVisas': ancillaryVisas,
  'commercialIndicators': commercialIndicators,
  'reviewIssues': reviewIssues,
};

Map<String, Object?> supplierExtractionRoot({
  String persistenceState = 'complete',
  String schemaVersion = 'supplier_extraction_snapshot_v1',
  String extractionId = 'extraction-1',
  String tripId = 'trip-1',
  String sourcePackageId = 'package-1',
  Object? createdAt,
  Map<String, Object?>? counts,
}) => {
  'persistenceState': persistenceState,
  'schemaVersion': schemaVersion,
  'extractionId': extractionId,
  'tripId': tripId,
  'sourcePackageId': sourcePackageId,
  'jobId': 'job-1',
  'requestedByUid': 'agent-1',
  'createdAt': createdAt ?? supplierExtractionCreatedAt,
  'providerVersion': 'kayra_itinerary_extraction_v3_staging',
  'title': {
    'text': 'Japan Discovery',
    'basis': 'explicit_supplier',
    'sources': supplierExtractionSources(),
  },
  'counts': counts ?? supplierExtractionCounts(),
};

Map<String, Object?> supplierExtractionDay({
  required int number,
  required List<String> assignedServiceIds,
}) => {
  'id': 'staged-day-$number',
  'order': number,
  'sourceDayNumber': number == 1 ? 3 : 7,
  'date': number == 1 ? '2027-04-10' : '2027-04-12',
  'title': number == 1 ? 'Tokyo arrival' : 'Kyoto discovery',
  'summary': number == 1 ? 'Arrival and hotel check-in.' : null,
  'notes': number == 2 ? 'Operating order is supplier supplied.' : null,
  'assignedServiceIds': assignedServiceIds,
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionHotelDetails({
  String? checkInDate = '2027-04-10',
  String? checkOutDate = '2027-04-12',
}) => {
  'hotelName': 'Example Tokyo Hotel',
  'city': 'Tokyo',
  'orSimilar': true,
  'checkInDate': checkInDate,
  'checkOutDate': checkOutDate,
  'nightCount': 2,
  'roomType': 'Deluxe Room',
  'mealPlan': 'Breakfast',
  'numberOfRooms': 2,
  'supplierStarRating': '4 Star',
};

Map<String, Object?> supplierExtractionStatement({
  String id = 'staged-service-1-inclusion-1',
  String category = 'meal',
  String text = 'Daily breakfast',
}) => {
  'id': id,
  'category': category,
  'text': text,
  'quantity': 2,
  'frequency': 'daily',
  'appliesTo': ['hotel'],
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionCondition({
  String id = 'staged-service-1-condition-1',
  String kind = 'availability',
  String value = 'Subject to availability',
}) => {
  'id': id,
  'kind': kind,
  'value': value,
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionService({
  required String id,
  required int order,
  required Map<String, Object?> scope,
  String? serviceType = 'hotel',
  String? title = 'Hotel stay',
  Map<String, Object?>? hotelDetails,
  Map<String, Object?>? transferDetails,
  Map<String, Object?>? activityDetails,
}) => {
  'id': id,
  'factKind': 'service',
  'order': order,
  'scope': scope,
  'serviceType': serviceType,
  'title': title,
  'description': 'Supplier-supported service description.',
  'startTime': '10:30',
  'endTime': '12:00',
  'location': 'Central district',
  'city': 'Tokyo',
  'inclusions': [supplierExtractionStatement()],
  'exclusions': <Map<String, Object?>>[],
  'conditions': [supplierExtractionCondition()],
  'notes': 'Keep supplier operating notes.',
  'hotelDetails': hotelDetails,
  'transferDetails': transferDetails,
  'activityDetails': activityDetails,
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionPackageAccommodation() => {
  'id': 'package-fact-1',
  'factKind': 'package_accommodation',
  'order': 1,
  'scope': {'kind': 'package'},
  'details': supplierExtractionHotelDetails(
    checkInDate: null,
    checkOutDate: null,
  ),
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionPackageStatement({
  required String id,
  required int order,
  required String factKind,
  required String text,
}) => {
  'id': id,
  'factKind': factKind,
  'order': order,
  'scope': {'kind': 'package'},
  'category': 'meal',
  'text': text,
  'quantity': 3,
  'frequency': 'per stay',
  'appliesTo': ['hotel', 'meal'],
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionPackageCondition() => {
  'id': 'package-fact-4',
  'factKind': 'package_condition',
  'order': 4,
  'scope': {'kind': 'package'},
  'kind': 'operating_basis',
  'value': 'Shared basis',
  'appliesTo': ['transfer', 'sightseeing'],
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionFlight() => {
  'id': 'ancillary-flight-1',
  'factKind': 'flight',
  'order': 1,
  'scope': {'kind': 'ancillary'},
  'airline': 'Example Air',
  'flightNumber': 'EA 101',
  'origin': 'DEL',
  'destination': 'NRT',
  'departureDate': '2027-04-09',
  'departureTime': '22:15',
  'arrivalDate': '2027-04-10',
  'arrivalTime': '08:30',
  'cabinClass': 'Economy',
  'bookingClass': 'Y',
  'notes': 'Direct sector',
  'conditions': [
    supplierExtractionCondition(
      id: 'ancillary-flight-1-condition-1',
      kind: 'class',
      value: 'Economy class',
    ),
  ],
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionVisa() => {
  'id': 'ancillary-visa-1',
  'factKind': 'visa',
  'order': 1,
  'scope': {'kind': 'ancillary'},
  'disposition': 'requirement',
  'text': 'Visa required before travel.',
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionCommercialPresence() => {
  'id': 'commercial-presence-1',
  'factKind': 'commercial_presence',
  'order': 1,
  'scope': {'kind': 'package'},
  'categories': ['package_price', 'payment_terms'],
  'sources': supplierExtractionSources(),
};

Map<String, Object?> supplierExtractionReviewIssue({
  required int number,
  required String targetKind,
  String? entityId,
}) => {
  'id': 'review-$number',
  'code': number == 1 ? 'chronology_unknown' : 'global_mapping_required',
  'severity': number.isEven ? 'blocker' : 'warning',
  'message': 'Consultant review is required.',
  'target': {'kind': targetKind, 'entityId': entityId},
  'resolutionRequired': number.isEven,
  'sources': supplierExtractionSources(),
};

SupplierExtractionStoredDocument supplierExtractionChild(
  Map<String, Object?> value,
  int snapshotOrder,
) => (
  documentId: value['id']! as String,
  data: {'snapshotOrder': snapshotOrder, 'value': value},
);

List<SupplierExtractionStoredDocument> supplierExtractionDayDocuments() => [
  supplierExtractionChild(
    supplierExtractionDay(number: 1, assignedServiceIds: ['staged-service-1']),
    1,
  ),
  supplierExtractionChild(
    supplierExtractionDay(number: 2, assignedServiceIds: ['staged-service-2']),
    2,
  ),
];

List<SupplierExtractionStoredDocument> supplierExtractionFactDocuments() => [
  supplierExtractionChild(
    supplierExtractionService(
      id: 'staged-service-1',
      order: 1,
      scope: {'kind': 'day', 'dayId': 'staged-day-1'},
      hotelDetails: supplierExtractionHotelDetails(),
    ),
    1,
  ),
  supplierExtractionChild(
    supplierExtractionService(
      id: 'staged-service-2',
      order: 1,
      scope: {'kind': 'day', 'dayId': 'staged-day-2'},
      serviceType: 'activity',
      title: 'Kyoto city tour',
      activityDetails: {
        'activityName': 'Kyoto city tour',
        'duration': '4 hours',
        'activityType': 'Sightseeing',
      },
    ),
    2,
  ),
  supplierExtractionChild(
    supplierExtractionService(
      id: 'staged-service-3',
      order: 3,
      scope: {'kind': 'unassigned'},
      serviceType: 'transfer',
      title: 'Airport transfer',
      transferDetails: {
        'pickup': 'Narita Airport',
        'dropoff': 'Tokyo hotel',
        'vehicleType': 'Coach',
        'transferType': 'shared',
      },
    ),
    3,
  ),
  supplierExtractionChild(supplierExtractionPackageAccommodation(), 4),
  supplierExtractionChild(
    supplierExtractionPackageStatement(
      id: 'package-fact-2',
      order: 2,
      factKind: 'package_inclusion',
      text: 'Three dinners',
    ),
    5,
  ),
  supplierExtractionChild(
    supplierExtractionPackageStatement(
      id: 'package-fact-3',
      order: 3,
      factKind: 'package_exclusion',
      text: 'Lunches not stated as included',
    ),
    6,
  ),
  supplierExtractionChild(supplierExtractionPackageCondition(), 7),
  supplierExtractionChild(supplierExtractionFlight(), 8),
  supplierExtractionChild(supplierExtractionVisa(), 9),
  supplierExtractionChild(supplierExtractionCommercialPresence(), 10),
];

List<SupplierExtractionStoredDocument>
supplierExtractionReviewIssueDocuments() => [
  supplierExtractionChild(
    supplierExtractionReviewIssue(number: 1, targetKind: 'snapshot'),
    1,
  ),
  supplierExtractionChild(
    supplierExtractionReviewIssue(
      number: 2,
      targetKind: 'day',
      entityId: 'staged-day-1',
    ),
    2,
  ),
  supplierExtractionChild(
    supplierExtractionReviewIssue(
      number: 3,
      targetKind: 'service',
      entityId: 'staged-service-1',
    ),
    3,
  ),
  supplierExtractionChild(
    supplierExtractionReviewIssue(
      number: 4,
      targetKind: 'service',
      entityId: 'staged-service-3',
    ),
    4,
  ),
  supplierExtractionChild(
    supplierExtractionReviewIssue(
      number: 5,
      targetKind: 'package_fact',
      entityId: 'package-fact-1',
    ),
    5,
  ),
  supplierExtractionChild(
    supplierExtractionReviewIssue(
      number: 6,
      targetKind: 'ancillary_fact',
      entityId: 'ancillary-flight-1',
    ),
    6,
  ),
];

SupplierExtractionSnapshot supplierExtractionFixture() =>
    SupplierExtractionSnapshot.fromStoredDocuments(
      expectedTripId: 'trip-1',
      expectedExtractionId: 'extraction-1',
      root: supplierExtractionRoot(),
      dayDocuments: supplierExtractionDayDocuments(),
      factDocuments: supplierExtractionFactDocuments(),
      reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
      trustedSourceFileIds: const ['file-1'],
    );
