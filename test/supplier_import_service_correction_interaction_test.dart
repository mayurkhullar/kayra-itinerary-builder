import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/staged_service_correction.dart';

import 'support/supplier_import_day_review_fixture.dart';
import 'support/supplier_import_review_fixture.dart';
import 'support/supplier_import_service_correction_fixture.dart';

void main() {
  late ServiceCorrectionHarness ui;
  setUp(() => ui = ServiceCorrectionHarness());
  tearDown(() => ui.h.dispose());

  for (final state in [
    'not-started',
    'active',
    'finalized',
    'excluded',
    'unassigned',
  ]) {
    testWidgets('$state gates service correction controls', (tester) async {
      if (state == 'not-started') {
        ui.h.resolutions.value = const SupplierImportResolutionNotStarted();
      }
      if (state == 'finalized') {
        ui.h.resolutions.value = reviewResolution(finalized: true, revision: 2);
      }
      if (state == 'excluded') {
        ui.h.resolutions.value = dayReviewResolution(
          decisions: [
            serviceCorrectionDecision(
              exclude: true,
              overrides: const SupplierImportServiceOverrides(
                notes: SupplierImportSetOverride('Kept correction'),
              ),
            ),
          ],
        );
      }
      await ui.show(tester);
      if (state == 'active' || state == 'excluded' || state == 'unassigned') {
        await ui.tap(
          tester,
          'service-review-action-staged-service-${state == 'unassigned' ? 3 : 1}',
        );
        expect(
          serviceKey('correct-service-title'),
          state == 'active' ? findsOneWidget : findsNothing,
        );
        if (state == 'excluded') {
          expect(find.text('Kept correction'), findsWidgets);
          expect(
            find.textContaining(
              'Corrections are kept while this service is excluded.',
            ),
            findsWidgets,
          );
        }
      } else {
        expect(serviceActions(), findsNothing);
      }
      expect(ui.h.mutations.requests, isEmpty);
    });
  }

  for (final type in [
    'hotel',
    'transfer',
    'activity',
    'other',
    'meal',
    'sightseeing',
    'free_time',
  ]) {
    testWidgets(
      '$type exposes only authoritative compatible common/detail fields',
      (tester) async {
        final number = type == 'transfer'
            ? 3
            : type == 'activity'
            ? 2
            : 1;
        if (!['hotel', 'transfer', 'activity'].contains(type)) {
          ui.h.snapshots.value = serviceCorrectionSnapshot(
            service1: {'serviceType': type, 'hotelDetails': null},
          );
        }
        if (number == 3) {
          ui.h.resolutions.value = dayReviewResolution(
            decisions: [
              serviceCorrectionDecision(
                id: 'staged-service-3',
                day: 'staged-day-1',
              ),
            ],
          );
        }
        await ui.show(tester);
        await ui.tap(tester, 'service-review-action-staged-service-$number');
        for (final field in StagedServiceCorrectionField.values) {
          expect(
            serviceKey('correct-service-${field.name}'),
            field.branch == null || field.branch == type
                ? findsOneWidget
                : findsNothing,
          );
        }
        for (final forbidden in [
          'Price',
          'Margin',
          'Payment',
          'Finalize',
          'Approve import',
          'Create itinerary',
          'Add service',
          'Add day',
          'Correct conditions',
          'Correct sources',
        ]) {
          expect(find.text(forbidden), findsNothing);
        }
      },
    );
  }

  testWidgets(
    'untouched editors provide source context without prefilling or saving',
    (tester) async {
      await ui.show(tester);
      await ui.tap(tester, 'service-review-action-staged-service-1');
      for (final field in StagedServiceCorrectionField.values.where(
        (f) => f.branch == null || f.branch == 'hotel',
      )) {
        await ui.tap(tester, 'correct-service-${field.name}');
        expect(find.text('Supplier source'), findsOneWidget);
        expect(find.text('Untouched · use supplier value'), findsOneWidget);
        expect(serviceKey('service-correction-reset'), findsNothing);
        if (serviceKey('service-correction-value').evaluate().isNotEmpty) {
          expect(
            tester
                .widget<TextFormField>(serviceKey('service-correction-value'))
                .controller!
                .text,
            isEmpty,
          );
        }
        if (serviceKey('service-correction-choice').evaluate().isNotEmpty) {
          expect(
            tester
                .widget<DropdownButtonFormField<Object>>(
                  serviceKey('service-correction-choice'),
                )
                .initialValue,
            isNull,
          );
        }
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(ui.h.mutations.requests, isEmpty);
    },
  );

  for (final field in [
    StagedServiceCorrectionField.notes,
    StagedServiceCorrectionField.inclusions,
    StagedServiceCorrectionField.roomType,
    StagedServiceCorrectionField.checkInDate,
  ]) {
    testWidgets(
      '${field.name} explicit clear then reset preserves moved decision and siblings',
      (tester) async {
        final old = serviceCorrectionDecision(
          day: 'staged-day-2',
          order: 9,
          overrides: const SupplierImportServiceOverrides(
            title: SupplierImportSetOverride('Existing title'),
            hotel: SupplierImportHotelOverrides(
              mealPlan: SupplierImportSetOverride('Half board'),
            ),
          ),
        );
        ui.h.resolutions.value = dayReviewResolution(decisions: [old]);
        ui.apply();
        await ui.show(tester);
        await ui.open(tester, field.name);
        await ui.tap(tester, 'service-correction-clear');
        await ui.tap(tester, 'save-service-decision');
        expect(field.overrideIn(ui.requested.overrides)!.toMap(), {
          'operation': 'clear',
        });
        expect(ui.requested.day!.toMap(), old.day!.toMap());
        expect(ui.requested.canonicalOrder, 9);
        await ui.open(tester, field.name);
        await ui.tap(tester, 'service-correction-reset');
        await ui.tap(tester, 'save-service-decision');
        expect(ui.requested.toMutationMap(), old.toMutationMap());
        expect(
          ui.h.mutations.requests.every(
            (r) => r.mutation is SupplierImportSetDecisionCommand,
          ),
          isTrue,
        );
      },
    );
  }

  testWidgets(
    'current set prefills, source stays separate, reset retains explicit retain, whole revert removes',
    (tester) async {
      ui.h.resolutions.value = dayReviewResolution(
        decisions: [
          serviceCorrectionDecision(
            overrides: const SupplierImportServiceOverrides(
              title: SupplierImportSetOverride('Corrected title'),
            ),
          ),
        ],
      );
      ui.apply();
      await ui.show(tester);
      expect(servicePanelText('Corrected title'), findsOneWidget);
      expect(
        find.descendant(
          of: serviceKey('review-service-staged-service-1'),
          matching: find.text('Hotel stay'),
        ),
        findsOneWidget,
      );
      await ui.open(tester, 'title');
      expect(
        tester
            .widget<TextFormField>(serviceKey('service-correction-value'))
            .controller!
            .text,
        'Corrected title',
      );
      expect(find.text('Hotel stay'), findsWidgets);
      await ui.tap(tester, 'service-correction-reset');
      await ui.tap(tester, 'save-service-decision');
      expect(ui.requested.overrides.toMap(), isEmpty);
      expect(ui.requested.disposition, SupplierImportRetainDisposition.retain);
      await ui.tap(tester, 'service-review-action-staged-service-1');
      await ui.tap(tester, 'service-action-revert');
      expect(
        find.textContaining(
          'placement, disposition, order and all field corrections',
        ),
        findsOneWidget,
      );
      await ui.tap(tester, 'save-service-decision');
      expect(
        ui.h.mutations.requests.last.mutation,
        isA<SupplierImportRemoveDecisionCommand>(),
      );
    },
  );

  for (final list in ['inclusions', 'exclusions']) {
    testWidgets(
      '$list preserves item boundaries, omits blanks, rejects duplicates, stays service-scoped',
      (tester) async {
        ui.apply();
        await ui.show(tester);
        await ui.open(tester, list);
        if (list == 'inclusions') {
          expect(
            find.descendant(
              of: serviceKey('service-decision-dialog'),
              matching: find.text('Quantity'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: serviceKey('service-decision-dialog'),
              matching: find.text('Frequency'),
            ),
            findsOneWidget,
          );
        }
        for (final value in [' First\n item ', '  Second item  ', '   ']) {
          await ui.tap(tester, 'service-list-add');
          await tester.enterText(find.byType(TextFormField).last, value);
        }
        await ui.tap(tester, 'save-service-decision');
        expect(ui.requested.overrides.toMap()[list], {
          'operation': 'set',
          'value': ['First item', 'Second item'],
        });
        expect(ui.requested.targetEntityId, 'staged-service-1');
        await ui.open(tester, list);
        await ui.tap(tester, 'service-list-add');
        await tester.enterText(find.byType(TextFormField).last, 'First item');
        await ui.tap(tester, 'save-service-decision');
        expect(ui.h.mutations.requests.length, 1);
        expect(find.text('Use each item once.'), findsNWidgets(2));
      },
    );
    testWidgets('$list explicit empty replacement differs from clear', (
      tester,
    ) async {
      ui.apply();
      await ui.show(tester);
      await ui.open(tester, list);
      await ui.tap(tester, 'save-service-decision');
      expect(ui.requested.overrides.toMap()[list], {
        'operation': 'set',
        'value': <String>[],
      });
    });
  }

  testWidgets('invalid/empty text never clears or exposes backend content', (
    tester,
  ) async {
    await ui.show(tester);
    await ui.open(tester, 'title');
    for (final input in ['', 'price', 'x' * 2001]) {
      await tester.enterText(serviceKey('service-correction-value'), input);
      await ui.tap(tester, 'save-service-decision');
      expect(ui.h.mutations.requests, isEmpty);
    }
    expect(serviceKey('service-correction-clear'), findsNothing);
  });
  testWidgets(
    'hotel type change cannot silently discard existing source details',
    (tester) async {
      await ui.show(tester);
      await ui.open(tester, 'serviceType');
      await ui.tap(tester, 'service-correction-choice');
      await tester.tap(find.text('Transfer').last);
      await tester.pumpAndSettle();
      await ui.tap(tester, 'save-service-decision');
      expect(ui.h.mutations.requests, isEmpty);
      expect(
        find.textContaining('compatible with the supplier details'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'safe generic type override and reset use typed contract without gaining detail editors',
    (tester) async {
      ui.h.snapshots.value = serviceCorrectionSnapshot(
        service1: {'serviceType': 'other', 'hotelDetails': null},
      );
      ui.apply();
      await ui.show(tester);
      await ui.open(tester, 'serviceType');
      await ui.tap(tester, 'service-correction-choice');
      await tester.tap(find.text('Hotel').last);
      await tester.pumpAndSettle();
      await ui.tap(tester, 'save-service-decision');
      expect(ui.requested.overrides.serviceType!.toMap(), {
        'operation': 'set',
        'value': 'hotel',
      });
      await ui.tap(tester, 'service-review-action-staged-service-1');
      expect(serviceKey('correct-service-roomType'), findsNothing);
      await ui.tap(tester, 'correct-service-serviceType');
      await ui.tap(tester, 'service-correction-reset');
      await ui.tap(tester, 'save-service-decision');
      expect(ui.requested.overrides.serviceType, isNull);
    },
  );
  testWidgets(
    'hotel date correction neither infers nights nor changes day dates',
    (tester) async {
      ui.apply();
      await ui.show(tester);
      await ui.open(tester, 'checkInDate');
      await tester.enterText(
        serviceKey('service-correction-value'),
        '2027-04-12',
      );
      await ui.tap(tester, 'save-service-decision');
      expect(ui.h.mutations.requests, isEmpty);
      expect(
        find.textContaining('Check-out must be after check-in.'),
        findsOneWidget,
      );
      await tester.enterText(
        serviceKey('service-correction-value'),
        '2027-04-11',
      );
      await ui.tap(tester, 'save-service-decision');
      expect(ui.requested.overrides.toMap(), {
        'hotel': {
          'checkInDate': {'operation': 'set', 'value': '2027-04-11'},
        },
      });
      expect(ui.h.snapshots.value.days.first.date, DateTime.utc(2027, 4, 10));
    },
  );

  testWidgets(
    'one pending correction blocks all actions and duplicate save; source remains visible',
    (tester) async {
      final pending = Completer<SupplierImportResolutionMutationOutcome>();
      ui.h.mutations.onExecute = (_) => pending.future;
      await ui.show(tester);
      await ui.open(tester, 'title');
      await tester.enterText(
        serviceKey('service-correction-value'),
        'Pending title',
      );
      final save = tester
          .widget<FilledButton>(serviceKey('save-service-decision'))
          .onPressed!;
      save();
      save();
      await tester.pump(const Duration(seconds: 1));
      expect(ui.h.mutations.requests.length, 1);
      expect(serviceActions(), findsNothing);
      expect(find.text('Saving decision…'), findsOneWidget);
      expect(servicePanelText('Pending title'), findsNothing);
      expect(
        find.descendant(
          of: serviceKey('review-service-staged-service-1'),
          matching: find.text('Hotel stay'),
        ),
        findsOneWidget,
      );
      ui.h.resolutions.value = dayReviewResolution(
        decisions: [ui.requested],
        revision: 2,
      );
      pending.complete(reviewOutcome('applied'));
      await tester.pumpAndSettle();
      expect(serviceActions(), findsNWidgets(5));
    },
  );
  for (final outcome in ['applied', 'already_applied']) {
    testWidgets(
      '$outcome waits for authoritative reload without optimistic corrections',
      (tester) async {
        final pending = Completer<SupplierImportResolutionReadResult>();
        ui.h.mutations.onExecute = (_) {
          ui.h.resolutions.onRead = () => pending.future;
          return reviewOutcome(outcome);
        };
        await ui.show(tester);
        await ui.open(tester, 'title');
        await tester.enterText(
          serviceKey('service-correction-value'),
          'Submitted title',
        );
        await ui.tap(tester, 'save-service-decision', settle: false);
        expect(servicePanelText('Submitted title'), findsNothing);
        expect(serviceActions(), findsNothing);
        pending.complete(
          dayReviewResolution(
            decisions: [
              serviceCorrectionDecision(
                overrides: const SupplierImportServiceOverrides(
                  title: SupplierImportSetOverride('Authoritative title'),
                ),
              ),
            ],
            revision: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(servicePanelText('Authoritative title'), findsOneWidget);
        expect(servicePanelText('Submitted title'), findsNothing);
      },
    );
  }
  testWidgets(
    'conflict closes stale editor, no auto-resubmit, next explicit edit uses latest moved decision',
    (tester) async {
      ui.h.mutations.onExecute = (_) {
        ui.h.resolutions.value = dayReviewResolution(
          decisions: [
            serviceCorrectionDecision(
              day: 'staged-day-2',
              order: 9,
              overrides: const SupplierImportServiceOverrides(
                notes: SupplierImportSetOverride('Latest notes'),
              ),
            ),
          ],
          revision: 3,
        );
        return reviewOutcome('resolution_conflict', revision: 3);
      };
      await ui.show(tester);
      await ui.open(tester, 'title');
      await tester.enterText(
        serviceKey('service-correction-value'),
        'Stale title',
      );
      await ui.tap(tester, 'save-service-decision');
      expect(serviceKey('service-decision-dialog'), findsNothing);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      expect(ui.h.mutations.requests.length, 1);
      ui.apply();
      await ui.open(tester, 'title');
      await tester.enterText(
        serviceKey('service-correction-value'),
        'Fresh title',
      );
      await ui.tap(tester, 'save-service-decision');
      expect(ui.h.mutations.requests.last.expectedRevision, 3);
      expect(ui.requested.canonicalOrder, 9);
      expect(ui.requested.day!.toMap(), {
        'kind': 'staged_day',
        'dayId': 'staged-day-2',
      });
      expect(ui.requested.overrides.notes!.toMap(), {
        'operation': 'set',
        'value': 'Latest notes',
      });
    },
  );
  testWidgets('ambiguous retry retains identical command and commandId', (
    tester,
  ) async {
    ui.h.mutations.error = const SupplierImportMutationFailure(
      SupplierImportMutationFailureKind.unavailable,
    );
    await ui.show(tester);
    await ui.open(tester, 'notes');
    await tester.enterText(
      serviceKey('service-correction-value'),
      'Updated notes',
    );
    await ui.tap(tester, 'save-service-decision');
    final request = ui.h.mutations.requests.single;
    expect(serviceActions(), findsNothing);
    ui.h.mutations.error = null;
    ui.apply(outcome: 'already_applied');
    await ui.tap(tester, 'retry-review-request');
    expect(ui.h.mutations.requests.length, 2);
    expect(ui.h.mutations.requests.last, same(request));
    expect(ui.h.mutations.requests.last.commandId, request.commandId);
    expect(servicePanelText('Updated notes'), findsOneWidget);
  });
  testWidgets('unknown failure never exposes raw backend details', (
    tester,
  ) async {
    ui.h.mutations.error = StateError('PRIVATE Firebase payload');
    await ui.show(tester);
    await ui.open(tester, 'title');
    await tester.enterText(
      serviceKey('service-correction-value'),
      'Safe title',
    );
    await ui.tap(tester, 'save-service-decision');
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(find.textContaining('Firebase'), findsNothing);
    expect(serviceActions(), findsNothing);
  });

  for (final width in [375.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
    testWidgets(
      '${width.toInt()}px long descriptions/lists and detail fields have reachable stable footer',
      (tester) async {
        ui.h.snapshots.value = serviceCorrectionSnapshot(
          service1: {
            'description': List.filled(
              15,
              'Supplier description with operating instructions.',
            ).join(' '),
          },
        );
        ui.h.resolutions.value = dayReviewResolution(
          decisions: [
            serviceCorrectionDecision(
              overrides: SupplierImportServiceOverrides(
                inclusions: SupplierImportSetOverride(
                  List.generate(
                    14,
                    (i) => 'Inclusion item ${i + 1} with explanatory detail',
                  ),
                ),
              ),
            ),
          ],
        );
        await ui.show(tester, width: width);
        await ui.open(tester, 'description');
        await tester.enterText(
          serviceKey('service-correction-value'),
          'Long description ' * 30,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await ui.tap(tester, 'correct-service-inclusions');
        await tester.ensureVisible(find.byType(TextFormField).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final bounds = tester.getRect(serviceKey('service-decision-dialog'));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
        final footer = tester.getRect(serviceKey('save-service-decision'));
        expect(footer.height, greaterThanOrEqualTo(48));
        expect(footer.bottom, lessThanOrEqualTo(950));
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await ui.tap(tester, 'correct-service-supplierStarRating');
        expect(tester.takeException(), isNull);
        expect(ui.h.mutations.requests, isEmpty);
      },
    );
  }
  testWidgets(
    'large text/mobile keyboard keep labelled actions reachable; Escape cancels',
    (tester) async {
      await ui.show(tester, width: 390, scale: 1.5);
      await ui.open(tester, 'notes');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(
        serviceKey('service-correction-value'),
        'Readable notes',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(serviceKey('save-service-decision')).bottom,
        lessThanOrEqualTo(650),
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Clear value'), findsOneWidget);
      semantics.dispose();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(serviceKey('service-decision-dialog'), findsNothing);
      expect(ui.h.mutations.requests, isEmpty);
    },
  );
  testWidgets('keyboard traversal selects reset and Enter submits text', (
    tester,
  ) async {
    ui.apply();
    await ui.show(tester);
    await ui.open(tester, 'title');
    await tester.enterText(
      serviceKey('service-correction-value'),
      'Keyboard title',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(ui.requested.overrides.title!.value, 'Keyboard title');
    await ui.open(tester, 'title');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Remove only the title correction'),
      findsOneWidget,
    );
  });
}
