import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/trips/domain/kayra_trip.dart';

TripBrief _brief({
  List<String>? destinations,
  DateTime? date,
  int nights = 4,
  int adults = 2,
  int children = 1,
  int infants = 0,
  TripType type = TripType.fit,
}) => TripBrief(
  destinations: destinations ?? ['Dubai'],
  travelStartDate: date ?? DateTime(2026, 12, 29, 18),
  numberOfNights: nights,
  adults: adults,
  children: children,
  infants: infants,
  hotelCategory: HotelCategory.fiveStar,
  tripType: type,
);
KayraTrip _trip({
  TripBrief? brief,
  String clientId = 'client-1',
  String first = ' Mayur ',
  String last = ' Sharma ',
  String? company,
}) => KayraTrip.create(
  id: 'trip-1',
  clientId: clientId,
  clientFirstName: first,
  clientLastName: last,
  clientCompany: company,
  brief: brief ?? _brief(),
  currentUserUid: 'agent-1',
  createdAt: DateTime.utc(2026, 9),
);

void main() {
  test('new trip is Draft and owner is original creator', () {
    final trip = _trip();
    expect(trip.status, TripStatus.draft);
    expect(trip.ownerUid, 'agent-1');
    expect(trip.createdByUid, trip.ownerUid);
    expect(trip.createdAt, trip.updatedAt);
    expect(trip.clientFirstName, 'Mayur');
    expect(trip.clientLastName, 'Sharma');
    expect(trip.tripName, 'Mayur Sharma – Dubai – Dec 2026');
  });
  test(
    'destinations trim, remove blanks, retain order and resist mutation',
    () {
      final source = [' Abu Dhabi ', ' ', 'Dubai', '', 'Abu Dhabi'];
      final brief = _brief(destinations: source);
      source.clear();
      expect(brief.destinations, ['Abu Dhabi', 'Dubai', 'Abu Dhabi']);
      expect(() => brief.destinations.add('Paris'), throwsUnsupportedError);
      expect(
        brief.tripNameFor(' Mayur ', ' Sharma '),
        'Mayur Sharma – Abu Dhabi & Dubai & Abu Dhabi – Dec 2026',
      );
    },
  );
  for (final destinations in <List<String>>[
    [],
    [' ', '\n'],
  ]) {
    test(
      'rejects empty destinations $destinations',
      () => expect(
        () => _brief(destinations: destinations),
        throwsFormatException,
      ),
    );
  }
  for (final id in ['', ' ', 'clients/one', '.', '..']) {
    test(
      'rejects invalid client ID $id',
      () => expect(() => _trip(clientId: id), throwsFormatException),
    );
  }
  test('requires both client names', () {
    expect(() => _trip(first: ' '), throwsFormatException);
    expect(() => _trip(last: ' '), throwsFormatException);
  });
  for (final value in [-1, 0]) {
    test('rejects nights $value and adults $value', () {
      expect(() => _brief(nights: value), throwsFormatException);
      expect(() => _brief(adults: value), throwsFormatException);
    });
  }
  test('rejects negative child and infant counts', () {
    expect(() => _brief(children: -1), throwsFormatException);
    expect(() => _brief(infants: -1), throwsFormatException);
  });
  test('accepts minimum counts and derives total travellers', () {
    expect(
      _brief(nights: 1, adults: 1, children: 0, infants: 0).totalTravellerCount,
      1,
    );
    expect(
      _trip(
        brief: _brief(adults: 2, children: 3, infants: 1),
      ).totalTravellerCount,
      6,
    );
  });
  for (final type in TripType.values) {
    test(
      '${type.label} company requirement is contextual and not persisted',
      () {
        final brief = _brief(type: type);
        if (type == TripType.corporate || type == TripType.groups) {
          for (final company in <String?>[null, '', ' \n ']) {
            expect(
              () => _trip(brief: brief, company: company),
              throwsFormatException,
            );
          }
        } else {
          expect(_trip(brief: brief).tripType, type);
        }
        final trip = _trip(brief: brief, company: ' Company ');
        expect(trip.toMap().containsKey('company'), isFalse);
        // Reading a Corporate/Groups record does not fabricate company context.
        expect(
          KayraTrip.fromMap(trip.toMap(), documentId: trip.id).tripType,
          type,
        );
      },
    );
  }
  test('date-only values use the entered calendar day at UTC midnight', () {
    final trip = _trip();
    expect(trip.travelStartDate, DateTime.utc(2026, 12, 29));
    expect(trip.tripEndDate, DateTime.utc(2027, 1, 2));
    expect(
      _brief(date: DateTime.utc(2028, 2, 28), nights: 2).tripEndDate,
      DateTime.utc(2028, 3, 1),
    );
    expect(
      _brief(date: DateTime(2026, 3, 28, 23), nights: 2).tripEndDate,
      DateTime.utc(2026, 3, 30),
    );
    expect(trip.toMap().containsKey('tripEndDate'), isFalse);
    expect(trip.toMap().containsKey('totalTravellerCount'), isFalse);
    expect(trip.toMap().containsKey('id'), isFalse);
  });
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  for (var index = 0; index < months.length; index++) {
    test('trip name uses English ${months[index]} and correct year', () {
      final trip = _trip(
        brief: _brief(
          date: DateTime.utc(2027, index + 1),
          destinations: [' Dubai ', ' Abu Dhabi '],
        ),
      );
      expect(
        trip.tripName,
        'Mayur Sharma – Dubai & Abu Dhabi – ${months[index]} 2027',
      );
    });
  }
  test('enums have stable persisted values and separate labels', () {
    expect(HotelCategory.values.map((e) => e.value), [
      '3_star',
      '4_star',
      '5_star',
      'luxury',
    ]);
    expect(HotelCategory.values.map((e) => e.label), [
      '3 Star',
      '4 Star',
      '5 Star',
      'Luxury',
    ]);
    expect(TripType.values.map((e) => e.value), [
      'fit',
      'business',
      'corporate',
      'groups',
    ]);
    expect(TripType.values.map((e) => e.label), [
      'FIT',
      'Business',
      'Corporate',
      'Groups',
    ]);
    expect(TripStatus.values.map((e) => e.value), [
      'draft',
      'quote_prepared',
      'sent_to_client',
      'under_discussion',
      'revised',
      'client_approved',
      'on_hold',
      'confirmed',
      'cancelled',
      'lost',
      'travel_completed',
    ]);
    for (final value in HotelCategory.values) {
      expect(HotelCategory.parse(value.value), value);
    }
    for (final value in TripType.values) {
      expect(TripType.parse(value.value), value);
    }
    for (final value in TripStatus.values) {
      final record = {..._trip().toMap(), 'status': value.value};
      expect(KayraTrip.fromMap(record, documentId: 'trip-1').status, value);
    }
  });
  for (final field in ['hotelCategory', 'tripType', 'status']) {
    for (final value in [null, '', 'unknown', 3, true]) {
      test('rejects malformed enum $field=$value', () {
        expect(
          () => KayraTrip.fromMap({
            ..._trip().toMap(),
            field: value,
          }, documentId: 'trip-1'),
          throwsFormatException,
        );
      });
    }
  }
  for (final field in ['numberOfNights', 'adults', 'children', 'infants']) {
    for (final value in [null, -1, 1.5, 2.0, '2', true]) {
      test('rejects malformed count $field=$value', () {
        expect(
          () => KayraTrip.fromMap({
            ..._trip().toMap(),
            field: value,
          }, documentId: 'trip-1'),
          throwsFormatException,
        );
      });
    }
  }
  test('every persisted field is required with no fabricated defaults', () {
    for (final field in _trip().toMap().keys) {
      expect(
        () => KayraTrip.fromMap(
          _trip().toMap()..remove(field),
          documentId: 'trip-1',
        ),
        throwsFormatException,
        reason: field,
      );
    }
  });
  test(
    'rejects malformed identity, names, dates, destinations and generated name',
    () {
      for (final field in [
        'clientId',
        'clientFirstName',
        'clientLastName',
        'tripName',
        'ownerUid',
        'createdByUid',
        'createdAt',
        'updatedAt',
        'travelStartDate',
        'destinations',
      ]) {
        for (final value in [null, '', false, 123]) {
          expect(
            () => KayraTrip.fromMap({
              ..._trip().toMap(),
              field: value,
            }, documentId: 'trip-1'),
            throwsFormatException,
            reason: '$field=$value',
          );
        }
      }
      expect(
        () => KayraTrip.fromMap({
          ..._trip().toMap(),
          'destinations': ['Dubai', 1],
        }, documentId: 'trip-1'),
        throwsFormatException,
      );
      expect(
        () => KayraTrip.fromMap({
          ..._trip().toMap(),
          'tripName': 'Manual title',
        }, documentId: 'trip-1'),
        throwsFormatException,
      );
      expect(
        () => KayraTrip.fromMap({
          ..._trip().toMap(),
          'price': 100,
        }, documentId: 'trip-1'),
        throwsFormatException,
      );
    },
  );
  test(
    'domain serialization round trips and preserves separately assigned owner',
    () {
      final data = {..._trip().toMap(), 'ownerUid': 'new-agent'};
      final trip = KayraTrip.fromMap(data, documentId: 'trip-2');
      expect(trip.id, 'trip-2');
      expect(trip.toMap(), data);
      expect(trip.ownerUid, 'new-agent');
      expect(trip.createdByUid, 'agent-1');
    },
  );
}
