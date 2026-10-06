import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_draft_v2.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_service.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_values.dart';

import 'support/itinerary_draft_v2_fixture.dart';

ItineraryDraftV2 parse(Map<String, dynamic> data, {String id = 'draft-1'}) =>
    ItineraryDraftV2.fromFirestore(data, documentId: id);

void main() {
  test(
    'minimal backend-generated stored V2 parses without inventing content',
    () {
      final d = parse(itineraryDraftV2Fixture(full: false));
      expect(d.id, 'draft-1');
      expect(d.tripId, 'trip-1');
      expect(d.schemaVersion, itineraryDraftV2SchemaVersion);
      expect(d.days, isEmpty);
      expect(d.reviewIssues, isEmpty);
      expect(d.packageContent.accommodations, isEmpty);
      expect(d.importResult.policyVersion, itineraryDraftV2ImportPolicy);
      expect(d.importResult.finalizationId, 'finalize-1');
      expect(d.importResult.evaluatedRevision, 3);
      expect(d.createdAt, DateTime.utc(2026, 10, 6, 10));
    },
  );
  test(
    'full backend fixture preserves typed timeline and distinct package sections',
    () {
      final d = parse(itineraryDraftV2Fixture());
      expect(d.days.single.date, DateTime.utc(2027, 1, 10));
      expect(d.days.single.services.map((s) => s.type), [
        KayraItineraryServiceType.hotel,
        KayraItineraryServiceType.transfer,
        KayraItineraryServiceType.activity,
      ]);
      expect(
        d.days.single.services[0].hotelDetails!.checkOutDate,
        DateTime.utc(2027, 1, 12),
      );
      expect(d.days.single.services[1].transferDetails!.pickup, 'Airport');
      expect(d.days.single.services[2].activityDetails!.duration, '2 hours');
      final h = d.packageContent.accommodations.single.options.single.details;
      expect(h.hotelName, 'Example Hotel');
      expect(h.city, 'Dubai');
      expect(h.orSimilar, isTrue);
      expect(h.checkInDate, isNull);
      expect(h.checkOutDate, isNull);
      expect(h.nightCount, 3);
      expect(h.roomType, 'Deluxe');
      expect(h.mealPlan, 'Breakfast');
      expect(h.numberOfRooms, 2);
      expect(h.supplierStarRating, '5 Star');
      expect(d.packageContent.inclusions.single.text, 'Lunches');
      expect(d.packageContent.inclusions.single.quantity, 5);
      expect(d.packageContent.exclusions.single.text, 'Dinners');
      expect(d.packageContent.exclusions.single.quantity, 3);
      expect(
        d.packageContent.conditions.single.kind,
        SupplierExtractionConditionKind.operatingBasis,
      );
      expect(d.packageContent.conditions.single.appliesTo, [
        KayraItineraryServiceType.transfer,
      ]);
      final p = d.packageContent.inclusions.single.provenance;
      expect(p.origin, 'supplier');
      expect(p.extractionId, d.importResult.extractionId);
      expect(
        p.contributors.single.sources.single.supplierSourceFileId,
        'file-1',
      );
      expect(p.contributors.single.sources.single.sourceLabel, 'Page 2');
    },
  );
  for (final version in [
    null,
    'itinerary_draft_v1',
    'itinerary_draft_v3',
    '',
    2,
  ]) {
    test('rejects unsupported version $version', () {
      final data = itineraryDraftV2Fixture()..['schemaVersion'] = version;
      expect(
        () => parse(data),
        throwsA(isA<UnsupportedItineraryDraftV2Schema>()),
      );
    });
  }
  for (final key in itineraryDraftV2Fixture().keys) {
    test('requires root $key', () {
      final data = itineraryDraftV2Fixture()..remove(key);
      expect(
        () => parse(data),
        key == 'schemaVersion'
            ? throwsA(isA<UnsupportedItineraryDraftV2Schema>())
            : throwsFormatException,
      );
    });
  }
  for (final id in ['', '..', '.', ' padded', 'a/b', r'a\b', 'a\n']) {
    test(
      'rejects malformed identity $id',
      () => expect(
        () => parse(itineraryDraftV2Fixture(), id: id),
        throwsFormatException,
      ),
    );
  }
  final invalid = <String, void Function(Map<String, dynamic>)>{
    'root receipt': (d) => d['receipt'] = {},
    'root commercial field': (d) => d['supplierRate'] = 100,
    'stored root id': (d) => d['id'] = 'other',
    'wrong title type': (d) => d['title'] = 1,
    'commercial title': (d) => d['title'] = 'INR 500',
    'missing source membership': (d) => d['sourcePackageIds'] = ['other'],
    'duplicate packages': (d) =>
        d['sourcePackageIds'] = ['package-1', 'package-1'],
    'non-list days': (d) => d['days'] = {},
    'day float': (d) => v2At(d, ['days', 0])['dayNumber'] = 1.5,
    'day string': (d) => v2At(d, ['days', 0])['dayNumber'] = '1',
    'day zero': (d) => v2At(d, ['days', 0])['dayNumber'] = 0,
    'unsafe integer': (d) =>
        v2At(d, ['days', 0])['dayNumber'] = 9007199254740992,
    'duplicate day': (d) => (d['days'] as List).add({
      ...v2At(d, ['days', 0]),
      'services': [],
    }),
    'unsorted days': (d) {
      v2At(d, ['days', 0])['dayNumber'] = 3;
      (d['days'] as List).add({
        ...v2At(d, ['days', 0]),
        'dayNumber': 2,
        'services': [],
      });
    },
    'duplicate service across days': (d) => (d['days'] as List).add({
      ...v2At(d, ['days', 0]),
      'dayNumber': 2,
    }),
    'type mismatch': (d) =>
        v2At(d, ['days', 0, 'services', 0])['type'] = 'meal',
    'unknown type': (d) =>
        v2At(d, ['days', 0, 'services', 0])['type'] = 'future',
    'room negative': (d) =>
        v2At(d, ['days', 0, 'services', 0, 'hotelDetails'])['numberOfRooms'] =
            -1,
    'transfer missing endpoint': (d) =>
        v2At(d, ['days', 0, 'services', 1, 'transferDetails'])['pickup'] = null,
    'transfer enum': (d) =>
        v2At(d, ['days', 0, 'services', 1, 'transferDetails'])['transferType'] =
            'future',
    'activity empty name': (d) =>
        v2At(d, ['days', 0, 'services', 2, 'activityDetails'])['activityName'] =
            '',
    'unknown service field': (d) =>
        v2At(d, ['days', 0, 'services', 0])['cost'] = 1,
    'foreign timeline package': (d) => v2At(d, [
      'days',
      0,
      'services',
      0,
      'sourceReference',
    ])['supplierSourcePackageId'] = 'foreign',
    'source URL': (d) =>
        v2At(d, ['days', 0, 'services', 0, 'sourceReference'])['sourceLabel'] =
            'gs://private/path',
    'review enum': (d) => v2At(d, ['reviewIssues', 0])['severity'] = 'future',
    'review id collides with root': (d) =>
        v2At(d, ['reviewIssues', 0])['id'] = 'draft-1',
    'created DateTime': (d) => d['createdAt'] = DateTime.utc(2026),
    'created string': (d) => d['createdAt'] = '2026-10-06T10:00:00.000Z',
    'sub-ms Timestamp': (d) => d['createdAt'] = Timestamp(1000, 1),
    'updated before created': (d) => d['updatedAt'] = Timestamp(0, 0),
    'timeline string date': (d) => v2At(d, ['days', 0])['date'] = '2027-01-10',
    'timeline non-midnight': (d) => v2At(d, ['days', 0])['date'] =
        Timestamp.fromDate(DateTime.utc(2027, 1, 10, 1)),
    'hotel timeline string': (d) =>
        v2At(d, ['days', 0, 'services', 0, 'hotelDetails'])['checkInDate'] =
            '2027-01-10',
    'package Timestamp': (d) => v2Hotel(d)['checkInDate'] = Timestamp(0, 0),
    'package impossible date': (d) => v2Hotel(d)['checkInDate'] = '2027-02-30',
    'package short date': (d) => v2Hotel(d)['checkInDate'] = '2027-1-1',
    'package stay conflict': (d) => v2Hotel(d).addAll({
      'checkInDate': '2027-01-01',
      'checkOutDate': '2027-01-03',
      'nightCount': 3,
    }),
    'package orSimilar not boolean': (d) => v2Hotel(d)['orSimilar'] = 1,
    'package empty attributes': (d) => v2Hotel(d).updateAll((k, v) => null),
    'package blank room': (d) => v2Hotel(d)['roomType'] = '',
    'package negative nights': (d) => v2Hotel(d)['nightCount'] = -1,
    'package unknown field': (d) => v2Hotel(d)['supplierName'] = 'private',
    'single no options': (d) =>
        v2At(d, ['packageContent', 'accommodations', 0])['options'] = [],
    'alternatives too few': (d) =>
        v2At(d, ['packageContent', 'accommodations', 0])['selection'] =
            'alternatives',
    'package order': (d) =>
        v2At(d, ['packageContent', 'inclusions', 0])['order'] = 2,
    'duplicate inclusion order': (d) =>
        (v2Package(d)['inclusions'] as List).add({
          ...v2At(d, ['packageContent', 'inclusions', 0]),
          'id': 'second',
        }),
    'package cross-section id': (d) =>
        v2At(d, ['packageContent', 'exclusions', 0])['id'] = 'inclusion-1',
    'category enum': (d) =>
        v2At(d, ['packageContent', 'inclusions', 0])['category'] = 'future',
    'quantity string': (d) =>
        v2At(d, ['packageContent', 'inclusions', 0])['quantity'] = '2',
    'duplicate applicability': (d) =>
        v2At(d, ['packageContent', 'inclusions', 0])['appliesTo'] = [
          'meal',
          'meal',
        ],
    'applicability enum': (d) =>
        v2At(d, ['packageContent', 'inclusions', 0])['appliesTo'] = ['future'],
    'condition enum': (d) =>
        v2At(d, ['packageContent', 'conditions', 0])['kind'] = 'future',
    'lineage foreign source': (d) =>
        v2Provenance(d)['sourcePackageId'] = 'other',
    'lineage foreign extraction': (d) =>
        v2Provenance(d)['extractionId'] = 'other',
    'lineage foreign resolution': (d) =>
        v2Provenance(d)['resolutionId'] = 'other',
    'lineage revision': (d) => v2Provenance(d)['evaluatedRevision'] = 4,
    'lineage origin': (d) => v2Provenance(d)['origin'] = 'consultant',
    'lineage no contributors': (d) => v2Provenance(d)['contributors'] = [],
    'lineage no source': (d) => v2At(d, [
      'packageContent',
      'inclusions',
      0,
      'provenance',
      'contributors',
      0,
    ])['sources'] = [],
    'lineage duplicate contributor': (d) =>
        (v2Provenance(d)['contributors'] as List).add(
          v2At(d, [
            'packageContent',
            'inclusions',
            0,
            'provenance',
            'contributors',
            0,
          ]),
        ),
    'lineage duplicate decisions': (d) =>
        v2Provenance(d)['decisionIds'] = ['a', 'a'],
    'lineage unlinked correction': (d) => v2Provenance(d)['fieldChanges'] = [
      {'field': 'text', 'operation': 'set'},
    ],
    'lineage wrong field': (d) => v2Provenance(d).addAll({
      'decisionIds': ['a'],
      'fieldChanges': [
        {'field': 'hotelName', 'operation': 'set'},
      ],
    }),
    'lineage clear required': (d) => v2Provenance(d).addAll({
      'decisionIds': ['a'],
      'fieldChanges': [
        {'field': 'text', 'operation': 'clear'},
      ],
    }),
    'lineage duplicate changes': (d) => v2Provenance(d).addAll({
      'decisionIds': ['a'],
      'fieldChanges': [
        {'field': 'text', 'operation': 'set'},
        {'field': 'text', 'operation': 'set'},
      ],
    }),
    'import foreign resolution': (d) =>
        v2At(d, ['importResult'])['resolutionId'] = 'other',
    'import revision string': (d) =>
        v2At(d, ['importResult'])['evaluatedRevision'] = '3',
    'import unknown policy': (d) =>
        v2At(d, ['importResult'])['policyVersion'] = 'future',
    'import long finalization': (d) =>
        v2At(d, ['importResult'])['finalizationId'] = 'a' * 129,
    'import receipt smuggling': (d) =>
        v2At(d, ['importResult'])['receipt'] = {},
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}', () {
      final data = itineraryDraftV2Fixture();
      entry.value(data);
      expect(() => parse(data), throwsFormatException);
    });
  }
  test('valid package dates stay strings with no inferred night count', () {
    final data = itineraryDraftV2Fixture();
    v2Hotel(data).addAll({
      'checkInDate': '2028-02-28',
      'checkOutDate': '2028-03-01',
      'nightCount': null,
    });
    final h = parse(
      data,
    ).packageContent.accommodations.single.options.single.details;
    expect(h.checkInDate, '2028-02-28');
    expect(h.checkOutDate, '2028-03-01');
    expect(h.nightCount, isNull);
  });
  test(
    'valid alternatives preserve option identities, order and orSimilar',
    () {
      final data = itineraryDraftV2Fixture(),
          a = v2At(data, ['packageContent', 'accommodations', 0]);
      a['selection'] = 'alternatives';
      (a['options'] as List).add({
        ...v2At(data, ['packageContent', 'accommodations', 0, 'options', 0]),
        'id': 'second-hotel',
        'order': 2,
      });
      final parsed = parse(data).packageContent.accommodations.single;
      expect(
        parsed.selection,
        ItineraryDraftV2AccommodationSelection.alternatives,
      );
      expect(parsed.options.map((o) => o.order), [1, 2]);
    },
  );
  test('valid sparse set/clear lineage and inclusion order are preserved', () {
    final data = itineraryDraftV2Fixture();
    v2Provenance(data).addAll({
      'decisionIds': ['a'],
      'fieldChanges': [
        {'field': 'text', 'operation': 'set'},
        {'field': 'quantity', 'operation': 'clear'},
      ],
    });
    (v2Package(data)['inclusions'] as List).add({
      ...v2At(data, ['packageContent', 'inclusions', 0]),
      'id': 'second',
      'order': 2,
    });
    final items = parse(data).packageContent.inclusions;
    expect(items.map((i) => i.id), ['inclusion-1', 'second']);
    expect(
      items.first.provenance.fieldChanges.last.operation,
      ItineraryDraftV2FieldOperation.clear,
    );
  });
  test('operational direct payment is allowed only in its condition kind', () {
    final data = itineraryDraftV2Fixture();
    v2At(data, [
      'packageContent',
      'conditions',
      0,
    ]).addAll({'kind': 'payment_basis', 'value': 'Direct payment'});
    expect(
      parse(data).packageContent.conditions.single.value,
      'Direct payment',
    );
    v2At(data, ['packageContent', 'conditions', 0])['value'] =
        'Direct payment INR 500';
    expect(() => parse(data), throwsFormatException);
  });
  test(
    'nested and root lists are unmodifiable and detached from source maps',
    () {
      final data = itineraryDraftV2Fixture(),
          d = parse(data),
          content = d.packageContent,
          p = content.inclusions.single.provenance;
      for (final list in <List>[
        d.days,
        d.sourcePackageIds,
        d.reviewIssues,
        d.days.single.services,
        d.days.single.services.first.inclusions,
        content.accommodations,
        content.accommodations.single.options,
        content.inclusions,
        content.exclusions,
        content.conditions,
        content.inclusions.single.appliesTo,
        p.contributors,
        p.contributors.single.sources,
        p.decisionIds,
        p.fieldChanges,
      ]) {
        expect(list.clear, throwsUnsupportedError);
      }
      v2Hotel(data)['hotelName'] = 'Changed';
      v2At(data, ['importResult'])['extractionId'] = 'changed';
      expect(
        content.accommodations.single.options.single.details.hotelName,
        'Example Hotel',
      );
      expect(d.importResult.extractionId, 'extraction-1');
    },
  );
  test(
    'reading twice gives deterministic values without introducing new equality semantics',
    () {
      final a = parse(itineraryDraftV2Fixture()),
          b = parse(itineraryDraftV2Fixture());
      expect(a.days.map((d) => d.toMap()), b.days.map((d) => d.toMap()));
      expect(
        a.packageContent.inclusions.single.text,
        b.packageContent.inclusions.single.text,
      );
      expect(a.importResult.finalizationId, b.importResult.finalizationId);
    },
  );
  test(
    'package record count includes envelopes/options and rejects overflow',
    () {
      final data = itineraryDraftV2Fixture(full: false),
          full = itineraryDraftV2Fixture();
      v2Package(data)['inclusions'] = List.generate(
        256,
        (i) => {
          ...v2At(full, ['packageContent', 'inclusions', 0]),
          'id': 'item-$i',
          'order': i + 1,
        },
      );
      expect(parse(data).packageContent.inclusions.length, 256);
      (v2Package(data)['inclusions'] as List).add({
        ...v2At(full, ['packageContent', 'inclusions', 0]),
        'id': 'overflow',
        'order': 257,
      });
      expect(() => parse(data), throwsFormatException);
    },
  );
}
