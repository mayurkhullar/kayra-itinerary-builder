import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_draft_v2.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_values.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'support/itinerary_draft_v2_fixture.dart';
import 'support/supplier_import_service_correction_fixture.dart';
import 'support/supplier_import_review_fixture.dart';

void main() {
  late ServiceCorrectionHarness ui;
  setUp(() => ui = ServiceCorrectionHarness());
  tearDown(() => ui.h.dispose());
  void generic() {
    ui.h.snapshots.value = serviceCorrectionSnapshot(
      service1: {'serviceType': 'other', 'hotelDetails': null},
    );
    ui.apply();
  }

  Future<void> changeType(WidgetTester t, String label) async {
    await ui.open(t, 'serviceType');
    await ui.tap(t, 'service-correction-choice');
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
    await ui.tap(t, 'save-service-decision');
  }

  for (final (type, field) in [
    ('Hotel', 'hotelName'),
    ('Transfer', 'pickup'),
    ('Activity', 'activityName'),
  ]) {
    testWidgets(
      'other to $type exposes empty typed editor after authoritative reload',
      (t) async {
        generic();
        await ui.show(t);
        await changeType(t, type);
        expect(ui.h.mutations.requests, hasLength(1));
        await ui.open(t, field);
        expect(
          t
              .widget<TextFormField>(serviceKey('service-correction-value'))
              .controller!
              .text,
          isEmpty,
        );
        expect(find.text('Not provided'), findsWidgets);
        await t.enterText(
          serviceKey('service-correction-value'),
          'Consultant detail',
        );
        await ui.tap(t, 'save-service-decision');
        expect(ui.h.mutations.requests, hasLength(2));
        expect(ui.requested.overrides.toMap()[type.toLowerCase()], {
          field: {'operation': 'set', 'value': 'Consultant detail'},
        });
      },
    );
  }
  testWidgets(
    'reset refuses orphan typed corrections until explicitly removed, then hides hotel fields',
    (t) async {
      generic();
      await ui.show(t);
      await changeType(t, 'Hotel');
      await ui.open(t, 'hotelName');
      await t.enterText(
        serviceKey('service-correction-value'),
        'Consultant Hotel',
      );
      await ui.tap(t, 'save-service-decision');
      await ui.open(t, 'serviceType');
      await ui.tap(t, 'service-correction-reset');
      await ui.tap(t, 'save-service-decision');
      expect(ui.h.mutations.requests, hasLength(2));
      expect(
        find.textContaining('compatible with the supplier details'),
        findsOneWidget,
      );
      await t.tap(find.text('Back'));
      await t.pumpAndSettle();
      await ui.tap(t, 'correct-service-hotelName');
      await ui.tap(t, 'service-correction-reset');
      await ui.tap(t, 'save-service-decision');
      await ui.open(t, 'serviceType');
      await ui.tap(t, 'service-correction-reset');
      await ui.tap(t, 'save-service-decision');
      expect(ui.requested.overrides.toMap(), isEmpty);
      await ui.tap(t, 'service-review-action-staged-service-1');
      expect(serviceKey('correct-service-hotelName'), findsNothing);
      expect(serviceKey('correct-service-pickup'), findsNothing);
    },
  );
  testWidgets(
    'condition set clear and reset use only existing service edit mutations',
    (t) async {
      ui.apply();
      await ui.show(t);
      await ui.open(t, 'conditions');
      // Source rows are retained; adding a row never invents its kind/value.
      await ui.tap(t, 'service-condition-add');
      final dropdown = find
          .byType(DropdownButtonFormField<SupplierExtractionConditionKind>)
          .last;
      expect(
        t
            .widget<DropdownButtonFormField<SupplierExtractionConditionKind>>(
              dropdown,
            )
            .initialValue,
        isNull,
      );
      await t.ensureVisible(dropdown);
      await t.tap(dropdown);
      await t.pumpAndSettle();
      await t.tap(find.text('Availability').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.byType(TextFormField).last,
        'Subject to availability',
      );
      await ui.tap(t, 'save-service-decision');
      expect(
        ui.requested.overrides.conditions,
        isA<
          SupplierImportSetOverride<List<SupplierImportResolutionCondition>>
        >(),
      );
      expect(
        (ui.requested.overrides.conditions
                as SupplierImportSetOverride<
                  List<SupplierImportResolutionCondition>
                >)
            .value
            .last
            .value,
        'Subject to availability',
      );
      await ui.open(t, 'conditions');
      await ui.tap(t, 'service-correction-clear');
      await ui.tap(t, 'save-service-decision');
      expect(
        ui.requested.overrides.conditions,
        isA<SupplierImportClearOverride>(),
      );
      await ui.open(t, 'conditions');
      await ui.tap(t, 'service-correction-reset');
      await ui.tap(t, 'save-service-decision');
      expect(ui.requested.overrides.conditions, isNull);
      expect(ui.h.mutations.requests, hasLength(3));
    },
  );
  testWidgets(
    'source hotel facts and safe conditions remain visible with no approval control',
    (t) async {
      await ui.show(t);
      final service = serviceFact(ui.h.snapshots.value);
      expect(find.text(service.hotelDetails!.city!), findsWidgets);
      expect(find.text('Or similar'), findsWidgets);
      expect(find.text('Nights'), findsWidgets);
      expect(find.text('Service conditions'), findsWidgets);
      expect(find.text('Approve conditions'), findsNothing);
      expect(ui.h.mutations.requests, isEmpty);
    },
  );
  testWidgets(
    'finalized fidelity facts have no editing or second finalization',
    (t) async {
      ui.h.resolutions.value = reviewResolution(finalized: true, revision: 2);
      await ui.show(t);
      expect(serviceActions(), findsNothing);
      expect(serviceKey('correct-service-conditions'), findsNothing);
      expect(find.text('Finalize itinerary'), findsNothing);
    },
  );
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
    testWidgets('typed condition editor fits $width', (t) async {
      await ui.show(t, width: width);
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
  testWidgets('condition editor supports large mobile text', (t) async {
    await ui.show(t, width: 390, scale: 2);
    await ui.open(t, 'conditions');
    await ui.tap(t, 'service-condition-add');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  test(
    'V2 old and new optional fidelity fields parse immutably without V1 schema changes',
    () {
      final old = itineraryDraftV2Fixture();
      final original = ItineraryDraftV2.fromFirestore(
        old,
        documentId: 'draft-1',
      );
      expect(original.days.first.services.first.conditions, isNull);
      expect(
        original.days.first.services.first.hotelDetails!.toMap().containsKey(
          'orSimilar',
        ),
        isFalse,
      );
      final raw = v2At(old, ['days', 0, 'services', 0]);
      raw['conditions'] = [
        {'kind': 'availability', 'value': 'Subject to availability'},
        {'kind': 'ticket_scope', 'value': 'Entry only'},
      ];
      (raw['hotelDetails'] as Map<String, Object?>).addAll({
        'city': 'Kyoto',
        'orSimilar': false,
        'nightCount': 3,
      });
      final v = ItineraryDraftV2.fromFirestore(
        old,
        documentId: 'draft-1',
      ).days.first.services.first;
      expect(v.conditions!.map((c) => c.value), [
        'Subject to availability',
        'Entry only',
      ]);
      expect(v.hotelDetails!.city, 'Kyoto');
      expect(v.hotelDetails!.orSimilar, false);
      expect(v.hotelDetails!.nightCount, 3);
      expect(() => v.conditions!.clear(), throwsUnsupportedError);
      expect(v.toMap()['conditions'], raw['conditions']);
    },
  );
  for (final value in ['Commission 12%', 'CNY 500', 'Supplement INR 500']) {
    test('V2 condition/city rejects $value', () {
      for (final field in ['conditions', 'city']) {
        final m = itineraryDraftV2Fixture();
        final s = v2At(m, ['days', 0, 'services', 0]);
        if (field == 'conditions') {
          s[field] = [
            {'kind': 'other', 'value': value},
          ];
        } else {
          (s['hotelDetails'] as Map)['city'] = value;
        }
        expect(
          () => ItineraryDraftV2.fromFirestore(m, documentId: 'draft-1'),
          throwsFormatException,
        );
      }
    });
  }
  for (final entry in <String, Object?>{
    'conditions': null,
    'orSimilar': 'yes',
    'nightCount': 0,
    'city': 12,
  }.entries) {
    test('V2 rejects malformed optional ${entry.key}', () {
      final m = itineraryDraftV2Fixture();
      final s = v2At(m, ['days', 0, 'services', 0]);
      (entry.key == 'conditions' ? s : s['hotelDetails'] as Map)[entry.key] =
          entry.value;
      expect(
        () => ItineraryDraftV2.fromFirestore(m, documentId: 'draft-1'),
        throwsFormatException,
      );
    });
  }
}
