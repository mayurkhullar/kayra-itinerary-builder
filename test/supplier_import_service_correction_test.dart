import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_values.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/staged_service_correction.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/staged_service_correction_validation.dart';

import 'support/supplier_import_day_review_fixture.dart';
import 'support/supplier_import_service_correction_fixture.dart';

const _cases = <(StagedServiceCorrectionField, Object)>[
  (
    StagedServiceCorrectionField.serviceType,
    SupplierExtractionServiceType.hotel,
  ),
  (StagedServiceCorrectionField.title, 'Consultant title'),
  (StagedServiceCorrectionField.description, 'Consultant description'),
  (StagedServiceCorrectionField.startTime, '09:25'),
  (StagedServiceCorrectionField.endTime, '17:45'),
  (StagedServiceCorrectionField.location, 'Station entrance'),
  (StagedServiceCorrectionField.city, 'Osaka'),
  (StagedServiceCorrectionField.inclusions, ['Museum entry', 'Audio guide']),
  (StagedServiceCorrectionField.exclusions, ['Lunch', 'Evening visit']),
  (StagedServiceCorrectionField.notes, 'Consultant notes'),
  (StagedServiceCorrectionField.hotelName, 'Consultant Hotel'),
  (StagedServiceCorrectionField.hotelCity, 'Kyoto'),
  (StagedServiceCorrectionField.orSimilar, false),
  (StagedServiceCorrectionField.checkInDate, '2027-04-11'),
  (StagedServiceCorrectionField.checkOutDate, '2027-04-13'),
  (StagedServiceCorrectionField.nightCount, 3),
  (StagedServiceCorrectionField.roomType, 'Twin room'),
  (StagedServiceCorrectionField.mealPlan, 'Half board'),
  (StagedServiceCorrectionField.numberOfRooms, 4),
  (StagedServiceCorrectionField.supplierStarRating, 'Five star'),
  (StagedServiceCorrectionField.pickup, 'Station'),
  (StagedServiceCorrectionField.dropoff, 'Hotel lobby'),
  (StagedServiceCorrectionField.vehicleType, 'Minivan'),
  (
    StagedServiceCorrectionField.transferType,
    SupplierExtractionTransferType.shared,
  ),
  (StagedServiceCorrectionField.activityName, 'Garden visit'),
  (StagedServiceCorrectionField.duration, 'Half day'),
  (StagedServiceCorrectionField.activityType, 'Guided visit'),
];

SupplierImportServiceOverrides _siblings(String? branch) =>
    SupplierImportServiceOverrides.fromMap({
      'title': {'operation': 'set', 'value': 'Existing title'},
      'notes': {'operation': 'set', 'value': 'Existing notes'},
      'description': {'operation': 'clear'},
      if (branch == null || branch == 'hotel')
        'hotel': {
          'mealPlan': {'operation': 'set', 'value': 'Breakfast'},
          'roomType': {'operation': 'set', 'value': 'Suite'},
          'orSimilar': {'operation': 'clear'},
        },
      if (branch == 'transfer')
        'transfer': {
          'pickup': {'operation': 'set', 'value': 'Terminal'},
          'vehicleType': {'operation': 'set', 'value': 'Coach'},
        },
      if (branch == 'activity')
        'activity': {
          'activityName': {'operation': 'set', 'value': 'Walk'},
          'duration': {'operation': 'set', 'value': 'Two hours'},
        },
    });

void main() {
  for (final (field, value) in _cases) {
    test(
      '${field.name} set/clear/reset preserves entire moved decision and siblings',
      () {
        final old = serviceCorrectionDecision(
          day: 'staged-day-2',
          order: 8,
          overrides: _siblings(field.branch),
        );
        final review = serviceCorrectionReview(old);
        final source = serviceFact(review.snapshot);
        final original = old.toMutationMap();
        for (final override in <SupplierImportFieldOverride<Object?>?>[
          SupplierImportSetOverride(value),
          if (field.canClear) const SupplierImportClearOverride(),
          null,
        ]) {
          final result = review.correctField(source, field, override);
          final expected = _siblings(field.branch).toMap();
          final target = field.branch == null
              ? expected
              : Map<String, Object?>.from(expected[field.branch]! as Map);
          if (field.branch != null) expected[field.branch!] = target;
          if (override == null) {
            target.remove(field.wireKey);
          } else {
            target[field.wireKey] = override.toMap();
          }
          expect(result.toMutationMap(), {...original, 'overrides': expected});
          expect(old.toMutationMap(), original);
          expect(source, same(serviceFact(review.snapshot)));
        }
      },
    );

    testWidgets(
      '${field.name} saves exact typed set through review controller',
      (tester) async {
        final ui = ServiceCorrectionHarness();
        addTearDown(ui.h.dispose);
        final number = field.branch == 'transfer'
            ? 3
            : field.branch == 'activity'
            ? 2
            : 1;
        final old = serviceCorrectionDecision(
          id: 'staged-service-$number',
          day: number == 3 ? 'staged-day-1' : null,
          order: 8,
          overrides: _siblings(field.branch),
        );
        ui.h.resolutions.value = dayReviewResolution(decisions: [old]);
        final snapshot = ui.h.snapshots.value;
        ui.apply();
        await ui.show(tester);
        await ui.open(tester, field.name, service: number);
        expect(
          serviceKey('service-correction-clear'),
          field.canClear ? findsOneWidget : findsNothing,
        );
        await ui.tap(tester, 'service-correction-set');
        if (value is List<String>) {
          for (final item in value) {
            await ui.tap(tester, 'service-list-add');
            await tester.enterText(
              find.byType(TextFormField).last,
              '  $item  ',
            );
          }
        } else if (value is bool ||
            value is SupplierExtractionServiceType ||
            value is SupplierExtractionTransferType) {
          await ui.tap(tester, 'service-correction-choice');
          await tester.tap(find.text(serviceCorrectionValueLabel(value)).last);
          await tester.pumpAndSettle();
        } else {
          await tester.enterText(
            serviceKey('service-correction-value'),
            '  $value  ',
          );
        }
        await ui.tap(tester, 'save-service-decision');
        expect(ui.h.mutations.requests.length, 1);
        expect(
          field.overrideIn(ui.requested.overrides)!.toMap(),
          SupplierImportSetOverride(value).toMap(),
        );
        expect(ui.requested.canonicalOrder, 8);
        expect(ui.requested.day?.toMap(), old.day?.toMap());
        expect(ui.h.snapshots.value, same(snapshot));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('catalog matches exact contract keys and set-only fields', () {
    expect(
      StagedServiceCorrectionField.values
          .where((f) => f.branch == null)
          .map((f) => f.wireKey),
      [
        'serviceType',
        'title',
        'description',
        'startTime',
        'endTime',
        'location',
        'city',
        'inclusions',
        'exclusions',
        'notes',
      ],
    );
    expect(
      StagedServiceCorrectionField.values
          .where((f) => f.branch == 'hotel')
          .map((f) => f.wireKey),
      [
        'hotelName',
        'city',
        'orSimilar',
        'checkInDate',
        'checkOutDate',
        'nightCount',
        'roomType',
        'mealPlan',
        'numberOfRooms',
        'supplierStarRating',
      ],
    );
    expect(
      StagedServiceCorrectionField.values
          .where((f) => f.branch == 'transfer')
          .map((f) => f.wireKey),
      ['pickup', 'dropoff', 'vehicleType', 'transferType'],
    );
    expect(
      StagedServiceCorrectionField.values
          .where((f) => f.branch == 'activity')
          .map((f) => f.wireKey),
      ['activityName', 'duration', 'activityType'],
    );
    expect(StagedServiceCorrectionField.values.where((f) => !f.canClear), [
      StagedServiceCorrectionField.serviceType,
      StagedServiceCorrectionField.title,
    ]);
  });

  for (final placement in [
    'source',
    'moved',
    'formerly-unassigned',
    'excluded',
  ]) {
    test(
      '$placement retains placement/disposition/order/rationale on single-field reset',
      () {
        final old = serviceCorrectionDecision(
          id: placement == 'formerly-unassigned'
              ? 'staged-service-3'
              : 'staged-service-1',
          day: placement == 'moved'
              ? 'staged-day-2'
              : placement == 'formerly-unassigned'
              ? 'staged-day-1'
              : null,
          order: 11,
          exclude: placement == 'excluded',
          overrides: const SupplierImportServiceOverrides(
            notes: SupplierImportSetOverride('Consultant note'),
          ),
        );
        final review = serviceCorrectionReview(old);
        final result = review.correctField(
          serviceFact(
            review.snapshot,
            placement == 'formerly-unassigned' ? 3 : 1,
          ),
          StagedServiceCorrectionField.notes,
          null,
        );
        expect(result.toMutationMap(), {
          ...old.toMutationMap(),
          'overrides': <String, Object?>{},
        });
        expect(
          review.canCorrect(serviceFact(review.snapshot)),
          placement != 'excluded',
        );
      },
    );
  }

  test(
    'reset last nested override removes only empty branch, retains explicit retain',
    () {
      final old = serviceCorrectionDecision(
        overrides: const SupplierImportServiceOverrides(
          hotel: SupplierImportHotelOverrides(
            roomType: SupplierImportClearOverride(),
          ),
        ),
      );
      final review = serviceCorrectionReview(old);
      final reset = review.correctField(
        serviceFact(review.snapshot),
        StagedServiceCorrectionField.roomType,
        null,
      );
      expect(reset.overrides.toMap(), isEmpty);
      expect(reset.disposition, SupplierImportRetainDisposition.retain);
      expect(reset.targetEntityId, old.targetEntityId);
    },
  );

  for (final value in [
    '',
    '  ',
    'price',
    'amount',
    'currency',
    'supplement',
    'markup',
    'margin',
    'discount',
    'payment',
    '₹30',
    'USD 20',
    'cost 50',
    'x' * 2001,
  ]) {
    test(
      'text rejects invalid/commercial input ${value.length > 40 ? 'overlength' : value}',
      () => expect(validateServiceCorrectionText(value), isNotNull),
    );
  }
  test('text normalizes whitespace and accepts contract limit', () {
    expect(normalizeServiceCorrection('  A\n  B  '), 'A B');
    expect(validateServiceCorrectionText('x' * 2000), isNull);
  });
  for (final (field, invalid) in [
    (
      StagedServiceCorrectionField.startTime,
      ['9:30', '24:00', '10:60', 'afternoon', ''],
    ),
    (
      StagedServiceCorrectionField.checkInDate,
      ['2027-02-29', '2027-13-01', '10/04/2027', ''],
    ),
    (
      StagedServiceCorrectionField.numberOfRooms,
      ['0', '-1', '1.5', 'NaN', '9007199254740992', ''],
    ),
  ]) {
    test('${field.name} rejects invalid typed values', () {
      for (final input in invalid) {
        expect(
          validateServiceCorrectionInput(field, input),
          isNotNull,
          reason: input,
        );
      }
    });
  }
  test(
    'date range checks effective source/corrections including clear and reset',
    () {
      final source = serviceFact(serviceCorrectionSnapshot());
      expect(
        validateServiceCorrectionComposition(
          source,
          StagedServiceCorrectionField.checkInDate,
          const SupplierImportServiceOverrides(
            hotel: SupplierImportHotelOverrides(
              checkInDate: SupplierImportSetOverride('2027-04-12'),
            ),
          ),
        ),
        isNotNull,
      );
      expect(
        validateServiceCorrectionComposition(
          source,
          StagedServiceCorrectionField.checkInDate,
          const SupplierImportServiceOverrides(
            hotel: SupplierImportHotelOverrides(
              checkInDate: SupplierImportSetOverride('2027-04-12'),
              checkOutDate: SupplierImportClearOverride(),
            ),
          ),
        ),
        isNull,
      );
    },
  );
  test(
    'type changes cannot discard source detail or sibling detail corrections',
    () {
      final source = serviceFact(serviceCorrectionSnapshot());
      expect(
        serviceTypeCorrectionCompatible(
          source,
          const SupplierImportServiceOverrides(
            serviceType: SupplierImportSetOverride(
              SupplierExtractionServiceType.transfer,
            ),
          ),
        ),
        isFalse,
      );
      final generic = serviceFact(
        serviceCorrectionSnapshot(
          service1: {'serviceType': 'other', 'hotelDetails': null},
        ),
      );
      expect(
        serviceTypeCorrectionCompatible(
          generic,
          const SupplierImportServiceOverrides(
            serviceType: SupplierImportSetOverride(
              SupplierExtractionServiceType.meal,
            ),
          ),
        ),
        isTrue,
      );
      expect(
        serviceTypeCorrectionCompatible(
          generic,
          const SupplierImportServiceOverrides(
            serviceType: SupplierImportSetOverride(
              SupplierExtractionServiceType.meal,
            ),
            hotel: SupplierImportHotelOverrides(
              roomType: SupplierImportClearOverride(),
            ),
          ),
        ),
        isFalse,
      );
    },
  );
}
