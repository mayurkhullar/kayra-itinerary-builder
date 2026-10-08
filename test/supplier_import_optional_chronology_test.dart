import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_draft_v2.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'support/itinerary_draft_v2_fixture.dart';
import 'support/supplier_extraction_fixture.dart';
import 'support/supplier_import_review_fixture.dart';
import 'support/supplier_import_service_correction_fixture.dart';

Map<String, dynamic> unscheduledDraft() {
  final m = itineraryDraftV2Fixture();
  m['unscheduledServices'] = (m['days'] as List).single['services'];
  m['days'] = <Object>[];
  (m['importResult'] as Map)['policyVersion'] = optionalChronologyImportPolicy;
  return m;
}

SupplierExtractionSnapshot unscheduledSnapshot({
  bool days = false,
  bool generic = false,
}) => SupplierExtractionSnapshot.fromStoredDocuments(
  expectedTripId: 'trip-1',
  expectedExtractionId: 'extraction-1',
  root: supplierExtractionRoot(
    counts: supplierExtractionCounts(
      days: days ? 2 : 0,
      assignedServices: days ? 2 : 0,
      unassignedServices: 1,
      packageFacts: 0,
      ancillaryFlights: 0,
      ancillaryVisas: 0,
      commercialIndicators: 0,
      reviewIssues: 0,
    ),
  ),
  dayDocuments: days ? supplierExtractionDayDocuments() : [],
  factDocuments: [
    if (days) ...supplierExtractionFactDocuments().take(2),
    supplierExtractionChild(
      supplierExtractionService(
        id: days ? 'staged-service-3' : 'staged-service-1',
        order: 1,
        scope: {'kind': 'unassigned'},
        serviceType: generic ? 'other' : 'hotel',
        hotelDetails: generic ? null : supplierExtractionHotelDetails(),
      )..['inclusions'] = <Object>[],
      days ? 3 : 1,
    ),
  ],
  reviewIssueDocuments: [],
  trustedSourceFileIds: const ['file-1'],
);
void main() {
  test(
    'old absent collection remains absent; explicit empty remains empty',
    () {
      expect(
        ItineraryDraftV2.fromFirestore(
          itineraryDraftV2Fixture(),
          documentId: 'draft-1',
        ).unscheduledServices,
        isNull,
      );
      final m = itineraryDraftV2Fixture()..['unscheduledServices'] = <Object>[];
      expect(
        ItineraryDraftV2.fromFirestore(
          m,
          documentId: 'draft-1',
        ).unscheduledServices,
        isEmpty,
      );
    },
  );
  test(
    'all existing typed service details and Timestamp dates survive immutable unscheduled parsing',
    () {
      final d = ItineraryDraftV2.fromFirestore(
        unscheduledDraft(),
        documentId: 'draft-1',
      );
      expect(d.days, isEmpty);
      expect(d.unscheduledServices, hasLength(3));
      expect(d.importResult.policyVersion, optionalChronologyImportPolicy);
      final s = d.unscheduledServices!;
      expect(s[0].hotelDetails!.checkInDate, DateTime.utc(2027, 1, 10));
      expect(s[1].transferDetails!.pickup, 'Airport');
      expect(s[2].activityDetails!.duration, '2 hours');
      expect(s[0].sourceReference, isNotNull);
      expect(() => s.clear(), throwsUnsupportedError);
    },
  );
  test('unscheduled conditions and hotel qualifiers preserved', () {
    final m = unscheduledDraft();
    final s = (m['unscheduledServices'] as List).first as Map;
    s['conditions'] = [
      {'kind': 'guide', 'value': 'English guide'},
    ];
    (s['hotelDetails'] as Map).addAll(<String, Object?>{
      'city': 'Tokyo',
      'orSimilar': false,
      'nightCount': 2,
    });
    final service = ItineraryDraftV2.fromFirestore(
      m,
      documentId: 'draft-1',
    ).unscheduledServices!.first;
    expect(service.conditions!.single.value, 'English guide');
    expect(service.hotelDetails!.city, 'Tokyo');
    expect(service.hotelDetails!.orSimilar, false);
    expect(service.hotelDetails!.nightCount, 2);
  });
  for (final kind in [
    'duplicate',
    'cross-collection',
    'malformed',
    'commercial',
    'pricing',
  ]) {
    test('reader rejects $kind unscheduled content', () {
      final m = unscheduledDraft();
      final services = m['unscheduledServices'] as List;
      switch (kind) {
        case 'duplicate':
          services.add(services.first);
        case 'cross-collection':
          m['days'] = itineraryDraftV2Fixture()['days'];
        case 'malformed':
          (services.first as Map).remove('title');
        case 'commercial':
          (services.first as Map)['notes'] = 'Commission 12%';
        case 'pricing':
          (services.first as Map)['price'] = 500;
      }
      expect(
        () => ItineraryDraftV2.fromFirestore(m, documentId: 'draft-1'),
        throwsFormatException,
      );
    });
  }
  test('optional structured Snapshot evidence is retained and strict', () {
    final issue = {
      'id': 'review-1',
      'code': 'chronology_unknown',
      'severity': 'blocker',
      'message': 'No message interpretation',
      'target': {'kind': 'service', 'entityId': 'staged-service-1'},
      'resolutionRequired': true,
      'sources': supplierExtractionSources(),
    };
    expect(
      SupplierExtractionReviewIssue.fromMap(
        issue,
        snapshotOrder: 1,
      ).structureBasis,
      isNull,
    );
    issue['structureBasis'] = 'absence_only';
    expect(
      SupplierExtractionReviewIssue.fromMap(
        issue,
        snapshotOrder: 1,
      ).structureBasis,
      'absence_only',
    );
    issue['structureBasis'] = 'arbitrary';
    expect(
      () => SupplierExtractionReviewIssue.fromMap(issue, snapshotOrder: 1),
      throwsFormatException,
    );
  });

  late ServiceCorrectionHarness ui;
  setUp(() {
    ui = ServiceCorrectionHarness();
    ui.h.snapshots.value = unscheduledSnapshot();
    ui.apply();
  });
  tearDown(() => ui.h.dispose());
  testWidgets(
    'safe zero-day service visible without mutations or mandatory assignment controls',
    (t) async {
      await ui.show(t);
      expect(find.text('Unscheduled services'), findsOneWidget);
      for (final text in [
        'Needs day assignment',
        'Assign or exclude',
        'Awaiting day assignment',
        'Add day',
        'Day 0',
        'Unscheduled Day',
      ]) {
        expect(find.text(text), findsNothing);
      }
      expect(serviceKey('review-service-staged-service-1'), findsOneWidget);
      expect(ui.h.mutations.requests, isEmpty);
      await ui.tap(t, 'service-review-action-staged-service-1');
      expect(serviceKey('correct-service-title'), findsOneWidget);
      expect(serviceKey('service-action-assign'), findsNothing);
    },
  );
  for (final field in ['title', 'hotelName', 'city', 'notes']) {
    testWidgets(
      '$field correction remains unscheduled after authoritative reload',
      (t) async {
        await ui.show(t);
        await ui.open(t, field);
        await t.enterText(
          serviceKey('service-correction-value'),
          'Corrected value',
        );
        await ui.tap(t, 'save-service-decision');
        expect(ui.h.mutations.requests, hasLength(1));
        expect(ui.requested.day, isNull);
        expect(ui.requested.canonicalOrder, isNull);
        expect(ui.requested.overrides.toMap(), isNotEmpty);
        await ui.open(t, field);
        expect(
          t
              .widget<TextFormField>(serviceKey('service-correction-value'))
              .controller!
              .text,
          'Corrected value',
        );
      },
    );
  }
  testWidgets(
    'service type and conditions can be corrected without scheduling',
    (t) async {
      ui.h.snapshots.value = unscheduledSnapshot(generic: true);
      await ui.show(t);
      await ui.open(t, 'serviceType');
      await ui.tap(t, 'service-correction-choice');
      await t.tap(find.text('Hotel').last);
      await t.pumpAndSettle();
      await ui.tap(t, 'save-service-decision');
      expect(ui.requested.overrides.serviceType, isNotNull);
      expect(ui.requested.day, isNull);
      await ui.open(t, 'conditions');
      await ui.tap(t, 'service-correction-clear');
      await ui.tap(t, 'save-service-decision');
      expect(
        ui.requested.overrides.conditions,
        isA<SupplierImportClearOverride>(),
      );
      expect(ui.requested.day, isNull);
    },
  );
  testWidgets(
    'optional schedule uses existing decision with one day and order',
    (t) async {
      ui.h.snapshots.value = unscheduledSnapshot(days: true);
      await ui.show(t);
      await ui.tap(t, 'service-review-action-staged-service-3');
      await ui.tap(t, 'service-action-assign');
      await ui.tap(t, 'service-target-staged-day-1');
      await ui.tap(t, 'save-service-decision');
      expect(ui.h.mutations.requests, hasLength(1));
      expect(ui.requested.day, isA<SupplierImportStagedDayReference>());
      expect(ui.requested.canonicalOrder, 2);
    },
  );
  testWidgets('unscheduled exclusion remains available', (t) async {
    await ui.show(t);
    await ui.tap(t, 'service-review-action-staged-service-1');
    expect(serviceKey('service-action-exclude'), findsOneWidget);
    expect(ui.h.mutations.requests, isEmpty);
  });
  testWidgets('finalized unscheduled content remains read-only', (t) async {
    ui.h.resolutions.value = reviewResolution(finalized: true, revision: 2);
    await ui.show(t);
    expect(serviceKey('review-service-staged-service-1'), findsOneWidget);
    expect(serviceActions(), findsNothing);
    expect(find.text('Finalize itinerary'), findsNothing);
  });
  for (final width in [
    375.0,
    390.0,
    430.0,
    768.0,
    1024.0,
    1280.0,
    1440.0,
    1920.0,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('unscheduled editing fits $width at scale $scale', (t) async {
        await ui.show(t, width: width, scale: scale);
        await ui.open(t, 'conditions');
        await ui.tap(t, 'service-condition-add');
        await t.ensureVisible(find.byType(TextFormField).last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final rect = t.getRect(serviceKey('service-decision-dialog'));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(
          t.getRect(serviceKey('save-service-decision')).bottom,
          lessThanOrEqualTo(950),
        );
      });
    }
  }
}
