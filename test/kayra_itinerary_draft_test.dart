import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_day.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_details.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_draft.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_review_issue.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_service.dart';

final _createdAt = DateTime.utc(2026, 9, 26, 8);
final _updatedAt = DateTime.utc(2026, 9, 26, 9);

KayraItineraryService _service({
  String id = 'service-1',
  KayraItineraryServiceType type = KayraItineraryServiceType.other,
  String title = 'Welcome assistance',
}) => KayraItineraryService(id: id, type: type, title: title);

KayraItineraryDay _day({
  int number = 1,
  String? serviceId,
  String title = 'Arrival',
}) => KayraItineraryDay(
  dayNumber: number,
  title: title,
  services: [_service(id: serviceId ?? 'service-$number')],
);

KayraItineraryDraft _draft({
  List<KayraItineraryDay>? days,
  List<String> sourcePackageIds = const ['package-1'],
  List<KayraItineraryReviewIssue> reviewIssues = const [],
}) => KayraItineraryDraft(
  id: 'draft-1',
  tripId: 'trip-1',
  title: 'Dubai Escape',
  days: days ?? [_day(number: 1), _day(number: 2)],
  sourcePackageIds: sourcePackageIds,
  reviewIssues: reviewIssues,
  createdByUid: 'agent-1',
  createdAt: _createdAt,
  updatedAt: _updatedAt,
);

void main() {
  test('valid itinerary keeps multiple ordered days and Trip linkage', () {
    final draft = _draft();
    expect(draft.id, 'draft-1');
    expect(draft.tripId, 'trip-1');
    expect(draft.title, 'Dubai Escape');
    expect(draft.days.map((day) => day.dayNumber), [1, 2]);
    expect(draft.createdByUid, 'agent-1');
    expect(draft.createdAt, _createdAt);
    expect(draft.updatedAt, _updatedAt);
    expect(draft.toMap().containsKey('id'), isFalse);
  });

  test(
    'days are sorted deterministically without requiring contiguous values',
    () {
      final input = [_day(number: 4), _day(number: 1), _day(number: 2)];
      final draft = _draft(days: input);
      expect(draft.days.map((day) => day.dayNumber), [1, 2, 4]);
      expect(input.map((day) => day.dayNumber), [4, 1, 2]);
      expect(
        (draft.toMap()['days'] as List).map((day) => (day as Map)['dayNumber']),
        [1, 2, 4],
      );
    },
  );

  test('duplicate and non-positive day numbers are rejected', () {
    expect(
      () => _draft(days: [_day(number: 1), _day(number: 1)]),
      throwsFormatException,
    );
    for (final value in [0, -1]) {
      expect(
        () => KayraItineraryDay(dayNumber: value, title: 'Invalid'),
        throwsFormatException,
      );
    }
  });

  test('Trip, service, and review identities reject malformed values', () {
    for (final value in ['', ' ', ' a', 'a/b', '.', '..']) {
      expect(
        () => KayraItineraryDraft(
          id: 'draft-1',
          tripId: value,
          title: 'Itinerary',
          createdByUid: 'agent-1',
          createdAt: _createdAt,
          updatedAt: _updatedAt,
        ),
        throwsFormatException,
      );
      expect(
        () => KayraItineraryService(
          id: value,
          type: KayraItineraryServiceType.other,
          title: 'Service',
        ),
        throwsFormatException,
      );
      expect(
        () => KayraItineraryReviewIssue(
          id: value,
          fieldPath: 'days[0].title',
          message: 'Review this field.',
          severity: KayraItineraryReviewSeverity.warning,
        ),
        throwsFormatException,
      );
    }
  });

  test('day titles and review issue text reject blanks', () {
    expect(
      () => KayraItineraryDay(dayNumber: 1, title: ' '),
      throwsFormatException,
    );
    expect(
      () => KayraItineraryReviewIssue(
        id: 'issue-1',
        fieldPath: ' ',
        message: 'Review this field.',
        severity: KayraItineraryReviewSeverity.warning,
      ),
      throwsFormatException,
    );
    expect(
      () => KayraItineraryReviewIssue(
        id: 'issue-1',
        fieldPath: 'days[0].title',
        message: '\n',
        severity: KayraItineraryReviewSeverity.blocker,
      ),
      throwsFormatException,
    );
  });

  for (final value in ['', ' ', '\n']) {
    test('root title rejects blank text: ${value.codeUnits}', () {
      expect(
        () => KayraItineraryDraft(
          id: 'draft-1',
          tripId: 'trip-1',
          title: value,
          createdByUid: 'agent-1',
          createdAt: _createdAt,
          updatedAt: _updatedAt,
        ),
        throwsFormatException,
      );
    });

    test('service title rejects blank text: ${value.codeUnits}', () {
      expect(
        () => KayraItineraryService(
          id: 'service-1',
          type: KayraItineraryServiceType.other,
          title: value,
        ),
        throwsFormatException,
      );
    });
  }

  test(
    'source package IDs trim and deduplicate in first-seen deterministic order',
    () {
      final draft = _draft(
        sourcePackageIds: [
          ' package-2 ',
          'package-1',
          'package-2',
          ' package-3 ',
        ],
      );
      expect(draft.sourcePackageIds, ['package-2', 'package-1', 'package-3']);
      expect(
        () => _draft(sourcePackageIds: ['package-1', '  ']),
        throwsFormatException,
      );
    },
  );

  test('service types have explicit stable round-trip values', () {
    expect(KayraItineraryServiceType.values.map((type) => type.value), [
      'hotel',
      'transfer',
      'activity',
      'meal',
      'sightseeing',
      'free_time',
      'other',
    ]);
    for (final type in KayraItineraryServiceType.values) {
      final service = KayraItineraryService(
        id: 'service-${type.value}',
        type: type,
        title: type.value,
      );
      expect(KayraItineraryService.fromMap(service.toMap()).type, type);
    }
  });

  test('transfer types have explicit stable round-trip values', () {
    expect(KayraItineraryTransferType.values.map((type) => type.value), [
      'private',
      'shared',
      'scheduled',
      'other',
    ]);
    for (final type in KayraItineraryTransferType.values) {
      final details = KayraItineraryTransferDetails(
        pickup: 'Airport',
        dropoff: 'Hotel',
        transferType: type,
      );
      expect(
        KayraItineraryTransferDetails.fromMap(details.toMap()).transferType,
        type,
      );
    }
  });

  test('hotel details normalize dates and round trip', () {
    final details = KayraItineraryHotelDetails(
      hotelName: ' Atlantis The Palm ',
      checkInDate: DateTime(2027, 1, 10, 18),
      checkOutDate: DateTime(2027, 1, 13, 11),
      roomType: ' Ocean Room ',
      mealPlan: ' Breakfast ',
      numberOfRooms: 2,
      supplierStarRating: ' 5 Star ',
    );
    final parsed = KayraItineraryHotelDetails.fromMap(details.toMap());
    expect(parsed.toMap(), details.toMap());
    expect(parsed.hotelName, 'Atlantis The Palm');
    expect(parsed.checkInDate, DateTime.utc(2027, 1, 10));
    expect(parsed.checkOutDate, DateTime.utc(2027, 1, 13));
    expect(parsed.supplierStarRating, '5 Star');
  });

  test('transfer details round trip independently of a master record', () {
    final details = KayraItineraryTransferDetails(
      pickup: ' DXB Terminal 3 ',
      dropoff: ' Downtown hotel ',
      vehicleType: ' SUV ',
      transferType: KayraItineraryTransferType.private,
    );
    expect(
      KayraItineraryTransferDetails.fromMap(details.toMap()).toMap(),
      details.toMap(),
    );
  });

  test('activity details round trip independently of a master record', () {
    final details = KayraItineraryActivityDetails(
      activityName: ' Desert Safari ',
      duration: ' 6 hours ',
      activityType: ' Adventure ',
    );
    expect(
      KayraItineraryActivityDetails.fromMap(details.toMap()).toMap(),
      details.toMap(),
    );
  });

  test('service-specific details are rejected on the wrong service type', () {
    expect(
      () => KayraItineraryService(
        id: 'service-1',
        type: KayraItineraryServiceType.meal,
        title: 'Dinner',
        hotelDetails: KayraItineraryHotelDetails(hotelName: 'Hotel'),
      ),
      throwsFormatException,
    );
    expect(
      () => KayraItineraryService(
        id: 'service-1',
        type: KayraItineraryServiceType.other,
        title: 'Other',
        transferDetails: KayraItineraryTransferDetails(
          pickup: 'A',
          dropoff: 'B',
        ),
      ),
      throwsFormatException,
    );
  });

  test('source provenance round trips without Storage information', () {
    final reference = KayraItinerarySourceReference(
      supplierSourcePackageId: 'package-1',
      supplierSourceFileId: 'file-1',
      sourceLabel: ' Page 3 ',
    );
    expect(
      KayraItinerarySourceReference.fromMap(reference.toMap()).toMap(),
      reference.toMap(),
    );
    expect(reference.toMap().keys, {
      'supplierSourcePackageId',
      'supplierSourceFileId',
      'sourceLabel',
    });
  });

  for (final severity in KayraItineraryReviewSeverity.values) {
    test('${severity.value} review issue round trips', () {
      final issue = KayraItineraryReviewIssue(
        id: 'issue-${severity.value}',
        fieldPath: 'days[0].services[0].startTime',
        message: ' Confirm the pickup time. ',
        severity: severity,
      );
      final parsed = KayraItineraryReviewIssue.fromMap(issue.toMap());
      expect(parsed.toMap(), issue.toMap());
      expect(parsed.message, 'Confirm the pickup time.');
      expect(parsed.severity.value, severity.value);
    });
  }

  test('nested full itinerary serialization round trips deterministically', () {
    final hotel = KayraItineraryService(
      id: 'hotel-1',
      type: KayraItineraryServiceType.hotel,
      title: 'Hotel stay',
      description: 'Three nights',
      city: 'Dubai',
      inclusions: [' Breakfast ', '', 'Wi-Fi'],
      exclusions: [' Tourism fee '],
      hotelDetails: KayraItineraryHotelDetails(
        hotelName: 'Atlantis The Palm',
        checkInDate: DateTime.utc(2027, 1, 10),
        checkOutDate: DateTime.utc(2027, 1, 13),
        roomType: 'Ocean Room',
        mealPlan: 'Breakfast',
        numberOfRooms: 2,
        supplierStarRating: '5 Star',
      ),
      sourceReference: KayraItinerarySourceReference(
        supplierSourcePackageId: 'package-1',
        supplierSourceFileId: 'file-1',
        sourceLabel: 'Hotel option A',
      ),
    );
    final transfer = KayraItineraryService(
      id: 'transfer-1',
      type: KayraItineraryServiceType.transfer,
      title: 'Airport transfer',
      startTime: '10:30',
      transferDetails: KayraItineraryTransferDetails(
        pickup: 'DXB',
        dropoff: 'Hotel',
        vehicleType: 'SUV',
        transferType: KayraItineraryTransferType.private,
      ),
    );
    final activity = KayraItineraryService(
      id: 'activity-1',
      type: KayraItineraryServiceType.activity,
      title: 'Desert Safari',
      activityDetails: KayraItineraryActivityDetails(
        activityName: 'Evening Desert Safari',
        duration: '6 hours',
        activityType: 'Adventure',
      ),
    );
    final draft = _draft(
      days: [
        KayraItineraryDay(
          dayNumber: 2,
          date: DateTime(2027, 1, 11, 12),
          title: 'Desert Safari',
          services: [activity],
          notes: 'Carry a light jacket.',
        ),
        KayraItineraryDay(
          dayNumber: 1,
          date: DateTime(2027, 1, 10, 18),
          title: 'Arrival in Dubai',
          summary: 'Airport arrival and hotel check-in.',
          services: [transfer, hotel],
        ),
      ],
      sourcePackageIds: ['package-1', 'package-2'],
      reviewIssues: [
        KayraItineraryReviewIssue(
          id: 'issue-1',
          fieldPath: 'days[0].services[0].startTime',
          message: 'Confirm the pickup time.',
          severity: KayraItineraryReviewSeverity.warning,
        ),
      ],
    );

    final parsed = KayraItineraryDraft.fromMap(
      draft.toMap(),
      documentId: draft.id,
    );
    expect(parsed.toMap(), draft.toMap());
    expect(parsed.days.map((day) => day.dayNumber), [1, 2]);
    expect(parsed.days.first.date, DateTime.utc(2027, 1, 10));
    expect(parsed.days.first.services.last.hotelDetails?.numberOfRooms, 2);
    expect(
      parsed.days.last.services.single.activityDetails?.duration,
      '6 hours',
    );
  });

  test('model lists and constructor inputs are immutable and isolated', () {
    final services = [_service()];
    final day = KayraItineraryDay(
      dayNumber: 1,
      title: 'Arrival',
      services: services,
    );
    final days = [day];
    final packageIds = ['package-1'];
    final issues = [
      KayraItineraryReviewIssue(
        id: 'issue-1',
        fieldPath: 'days[0].title',
        message: 'Review title.',
        severity: KayraItineraryReviewSeverity.warning,
      ),
    ];
    final draft = _draft(
      days: days,
      sourcePackageIds: packageIds,
      reviewIssues: issues,
    );
    services.clear();
    days.clear();
    packageIds.clear();
    issues.clear();

    expect(day.services, hasLength(1));
    expect(draft.days, hasLength(1));
    expect(draft.sourcePackageIds, ['package-1']);
    expect(draft.reviewIssues, hasLength(1));
    expect(() => day.services.clear(), throwsUnsupportedError);
    expect(() => draft.days.clear(), throwsUnsupportedError);
    expect(() => draft.sourcePackageIds.clear(), throwsUnsupportedError);
    expect(() => draft.reviewIssues.clear(), throwsUnsupportedError);

    final map = draft.toMap();
    (map['days'] as List).clear();
    (map['sourcePackageIds'] as List).clear();
    (map['reviewIssues'] as List).clear();
    expect(draft.days, hasLength(1));
    expect(draft.sourcePackageIds, ['package-1']);
    expect(draft.reviewIssues, hasLength(1));
  });

  test('inclusions and exclusions trim values while preserving order', () {
    final service = KayraItineraryService(
      id: 'service-1',
      type: KayraItineraryServiceType.meal,
      title: 'Dinner',
      inclusions: [' Buffet ', '', ' Soft drinks '],
      exclusions: [' Alcohol ', '  '],
    );
    expect(service.inclusions, ['Buffet', 'Soft drinks']);
    expect(service.exclusions, ['Alcohol']);
    expect(() => service.inclusions.clear(), throwsUnsupportedError);
    expect(() => service.exclusions.clear(), throwsUnsupportedError);
  });

  test('unknown persisted enum values are rejected', () {
    expect(
      () => KayraItineraryServiceType.parse('flight'),
      throwsFormatException,
    );
    expect(
      () => KayraItineraryTransferType.parse('exclusive'),
      throwsFormatException,
    );
    expect(
      () => KayraItineraryReviewSeverity.parse('info'),
      throwsFormatException,
    );
    expect(
      () => KayraItineraryService.fromMap({
        ..._service().toMap(),
        'type': 'visa',
      }),
      throwsFormatException,
    );
  });

  test('strict parsing rejects unsupported and malformed root fields', () {
    final valid = _draft().toMap();
    expect(
      () => KayraItineraryDraft.fromMap({
        ...valid,
        'clientEmail': 'client@example.com',
      }, documentId: 'draft-1'),
      throwsFormatException,
    );
    expect(
      () => KayraItineraryDraft.fromMap({
        ...valid,
        'days': 'not-a-list',
      }, documentId: 'draft-1'),
      throwsFormatException,
    );
    expect(
      () => KayraItineraryDraft.fromMap(
        Map<String, Object?>.of(valid)..remove('tripId'),
        documentId: 'draft-1',
      ),
      throwsFormatException,
    );
  });
}
