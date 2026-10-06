import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/staged_day_correction.dart';

import 'support/supplier_extraction_fixture.dart';
import 'support/supplier_import_day_review_fixture.dart';
import 'support/supplier_import_review_fixture.dart';

const _originalOverrides = SupplierImportDayOverrides(
  title: SupplierImportSetOverride('Consultant title'),
  date: SupplierImportSetOverride('2028-02-29'),
  summary: SupplierImportSetOverride('Consultant summary'),
  notes: SupplierImportSetOverride('Consultant notes'),
);

void main() {
  late ReviewHarness h;
  late SupplierImportReviewDependencies dependencies;
  setUp(() {
    h = ReviewHarness();
    h.resolutions.value = reviewResolution();
    dependencies = SupplierImportReviewDependencies(
      snapshots: h.snapshots,
      resolutions: h.resolutions,
      mutations: h.mutations,
    );
  });
  tearDown(() => h.dispose());
  Finder key(String name) => find.byKey(ValueKey(name));
  Finder panelText(String value) => find.descendant(
    of: key('day-decision-panel-staged-day-1'),
    matching: find.text(value),
  );
  Finder sourceTitle() => find.descendant(
    of: key('review-day-staged-day-1'),
    matching: find.text('Tokyo arrival'),
  );
  Finder actions() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.contains('-review-action-'),
  );
  Future<void> show(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 950);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SupplierImportReviewPage(
            tripId: 'trip-1',
            extractionId: 'extraction-1',
            dependencies: dependencies,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    String name, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(key(name));
    await tester.tap(key(name));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester, String field) async {
    await tap(tester, 'day-review-action-staged-day-1');
    await tap(tester, 'correct-day-$field');
  }

  SupplierImportDayDecision requestDecision() =>
      (h.mutations.requests.last.mutation as SupplierImportSetDecisionCommand)
              .decision
          as SupplierImportDayDecision;
  void apply({String outcome = 'applied'}) {
    h.mutations.onExecute = (request) {
      final old =
          (h.resolutions.value as SupplierImportResolutionLoaded).resolution;
      final mutation = request.mutation;
      final target = switch (mutation) {
        SupplierImportSetDecisionCommand(:final decision) =>
          decision.targetEntityId,
        SupplierImportRemoveDecisionCommand(:final decisionId) => decisionId,
        _ => throw StateError('Unexpected command'),
      };
      h.resolutions.value = dayReviewResolution(
        revision: old.root.revision + 1,
        decisions: [
          ...old.decisions
              .where((d) => d.payload.targetEntityId != target)
              .map((d) => d.payload),
          if (mutation is SupplierImportSetDecisionCommand) mutation.decision,
        ],
      );
      return reviewOutcome(outcome, revision: old.root.revision + 1);
    };
  }

  for (final state in ['not-started', 'active', 'finalized']) {
    testWidgets('$state gates corrections and keeps source read-only', (
      tester,
    ) async {
      h.resolutions.value = state == 'not-started'
          ? const SupplierImportResolutionNotStarted()
          : reviewResolution(
              finalized: state == 'finalized',
              revision: state == 'finalized' ? 2 : 1,
            );
      await show(tester);
      if (state == 'active') {
        await tap(tester, 'day-review-action-staged-day-1');
        for (final field in StagedDayCorrectionField.values) {
          expect(key('correct-day-${field.name}'), findsOneWidget);
        }
      } else {
        expect(key('day-review-action-staged-day-1'), findsNothing);
        expect(find.text('Correct title'), findsNothing);
      }
      expect(h.mutations.requests, isEmpty);
    });
  }

  testWidgets('opening and leaving every editor creates no implicit override', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'day-review-action-staged-day-1');
    for (final field in StagedDayCorrectionField.values) {
      await tap(tester, 'correct-day-${field.name}');
      expect(
        tester
            .widget<TextFormField>(key('day-correction-value'))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Supplier source'), findsOneWidget);
      expect(find.text('Untouched · use supplier value'), findsOneWidget);
      expect(key('correction-action-reset'), findsNothing);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.mutations.requests, isEmpty);
  });

  for (final field in StagedDayCorrectionField.values) {
    testWidgets(
      '${field.name} set preserves all other overrides, order, identity and services',
      (tester) async {
        final service = dayReviewService(
          id: 'staged-service-3',
          day: 'staged-day-1',
        );
        final oldDay = dayReviewDecision(
          order: 5,
          overrides: _originalOverrides,
        );
        h.resolutions.value = dayReviewResolution(
          decisions: [oldDay, service],
          revision: 4,
        );
        final source = h.snapshots.value;
        apply();
        await show(tester);
        await open(tester, field.name);
        expect(
          tester
              .widget<TextFormField>(key('day-correction-value'))
              .controller!
              .text,
          (field.overrideIn(_originalOverrides)
                  as SupplierImportSetOverride<String>)
              .value,
        );
        expect(
          key('correction-action-clear'),
          field.canClear ? findsOneWidget : findsNothing,
        );
        final value = field == StagedDayCorrectionField.date
            ? '2029-03-15'
            : '  Corrected   ${field.name}\nvalue  ';
        await tester.enterText(key('day-correction-value'), value);
        await tap(tester, 'save-day-decision');
        final expected = {
          ...oldDay.toMutationMap(),
          'overrides': {
            ..._originalOverrides.toMap(),
            field.name: {
              'operation': 'set',
              'value': normalizeDayCorrection(value),
            },
          },
        };
        expect(requestDecision().toMutationMap(), expected);
        expect(h.mutations.requests.single.expectedRevision, 4);
        expect(h.mutations.requests.single.tripId, 'trip-1');
        expect(h.snapshots.value, same(source));
        expect(source.days[0].sourceDayNumber, 3);
        expect(source.days[0].date, DateTime.utc(2027, 4, 10));
        expect(source.days[1].date, DateTime.utc(2027, 4, 12));
        expect(source.days.map((d) => d.order), [1, 2]);
        expect(panelText(normalizeDayCorrection(value)), findsOneWidget);
        expect(panelText('Consultant corrections'), findsOneWidget);
        expect(sourceTitle(), findsOneWidget);
        final stored = (h.resolutions.value as SupplierImportResolutionLoaded)
            .resolution
            .decisions;
        expect(
          stored
              .singleWhere(
                (d) => d.payload.targetEntityId == service.targetEntityId,
              )
              .payload
              .toMutationMap(),
          service.toMutationMap(),
        );
        expect(h.snapshots.readCount, 1);
      },
    );

    testWidgets('${field.name} empty set is rejected, never silently cleared', (
      tester,
    ) async {
      await show(tester);
      await open(tester, field.name);
      await tester.enterText(key('day-correction-value'), '   ');
      await tap(tester, 'save-day-decision');
      expect(find.text('Enter a ${field.name} value.'), findsOneWidget);
      expect(h.mutations.requests, isEmpty);
    });

    testWidgets(
      '${field.name} reset removes only that override, not the decision',
      (tester) async {
        final original = dayReviewDecision(
          order: 5,
          overrides: _originalOverrides,
        );
        h.resolutions.value = dayReviewResolution(decisions: [original]);
        apply();
        await show(tester);
        await open(tester, field.name);
        await tap(tester, 'correction-action-reset');
        expect(
          find.textContaining('Remove only the ${field.name} correction'),
          findsOneWidget,
        );
        await tap(tester, 'save-day-decision');
        final expected = {..._originalOverrides.toMap()}..remove(field.name);
        expect(requestDecision().toMutationMap(), {
          ...original.toMutationMap(),
          'overrides': expected,
        });
        expect(
          h.mutations.requests.single.mutation,
          isA<SupplierImportSetDecisionCommand>(),
        );
        await open(tester, field.name);
        expect(key('correction-action-reset'), findsNothing);
      },
    );
  }

  for (final field in StagedDayCorrectionField.values.where(
    (f) => f.canClear,
  )) {
    testWidgets(
      '${field.name} explicit clear is typed and can return to untouched',
      (tester) async {
        final old = dayReviewDecision(order: 5, overrides: _originalOverrides);
        h.resolutions.value = dayReviewResolution(decisions: [old]);
        apply();
        await show(tester);
        await open(tester, field.name);
        await tap(tester, 'correction-action-clear');
        await tap(tester, 'save-day-decision');
        expect(requestDecision().toMutationMap(), {
          ...old.toMutationMap(),
          'overrides': {
            ..._originalOverrides.toMap(),
            field.name: {'operation': 'clear'},
          },
        });
        expect(panelText('Cleared for import'), findsOneWidget);
        await open(tester, field.name);
        expect(key('day-correction-value'), findsNothing);
        await tap(tester, 'correction-action-reset');
        await tap(tester, 'save-day-decision');
        expect(
          requestDecision().overrides.toMap().containsKey(field.name),
          isFalse,
        );
        expect(requestDecision().canonicalOrder, 5);
      },
    );
  }

  testWidgets(
    'last-field reset preserves meaningful explicit retain; Revert removes whole decision',
    (tester) async {
      h.resolutions.value = dayReviewResolution(
        decisions: [
          dayReviewDecision(
            overrides: const SupplierImportDayOverrides(
              title: SupplierImportSetOverride('Corrected heading'),
            ),
          ),
        ],
      );
      apply();
      await show(tester);
      await open(tester, 'title');
      await tap(tester, 'correction-action-reset');
      await tap(tester, 'save-day-decision');
      expect(
        requestDecision().toMutationMap(),
        dayReviewDecision().toMutationMap(),
      );
      expect(panelText('Accepted as extracted'), findsOneWidget);
      await tap(tester, 'day-review-action-staged-day-1');
      await tap(tester, 'day-action-revert');
      expect(
        find.textContaining('Remove the current day decision'),
        findsOneWidget,
      );
      await tap(tester, 'save-day-decision');
      expect(h.mutations.requests.last.mutation.toMap(), {
        'action': 'remove_decision',
        'decisionId': 'staged-day-1',
      });
      expect(sourceTitle(), findsOneWidget);
    },
  );

  testWidgets(
    'excluded corrections stay read-only and survive explicit reactivation',
    (tester) async {
      final original = dayReviewDecision(
        order: 5,
        overrides: _originalOverrides,
        exclude: SupplierImportExclusionReason.other,
        note: 'Outside this journey',
      );
      h.resolutions.value = dayReviewResolution(
        decisions: [original, dayReviewService(exclude: true)],
      );
      await show(tester);
      await tap(tester, 'day-review-action-staged-day-1');
      for (final field in StagedDayCorrectionField.values) {
        expect(key('correct-day-${field.name}'), findsNothing);
      }
      expect(find.text('Consultant title'), findsNWidgets(2));
      expect(h.mutations.requests, isEmpty);
      expect(
        (h.resolutions.value as SupplierImportResolutionLoaded)
            .resolution
            .decisions
            .first
            .payload
            .toMutationMap(),
        original.toMutationMap(),
      );
      apply();
      await tap(tester, 'day-action-retain');
      await tap(tester, 'save-day-decision');
      expect(requestDecision().overrides.toMap(), _originalOverrides.toMap());
      expect(requestDecision().canonicalOrder, 5);
      await open(tester, 'title');
      expect(
        tester
            .widget<TextFormField>(key('day-correction-value'))
            .controller!
            .text,
        'Consultant title',
      );
    },
  );

  testWidgets(
    'new correction stores only selected override and preserves service target eligibility',
    (tester) async {
      apply();
      await show(tester);
      await open(tester, 'title');
      await tester.enterText(key('day-correction-value'), 'Kyoto discovery');
      await tap(tester, 'save-day-decision');
      expect(requestDecision().overrides.toMap(), {
        'title': {'operation': 'set', 'value': 'Kyoto discovery'},
      });
      expect(requestDecision().canonicalOrder, isNull);
      await tap(tester, 'service-review-action-staged-service-3');
      await tap(tester, 'service-action-assign');
      expect(key('service-target-staged-day-1'), findsOneWidget);
      expect(key('service-target-staged-day-2'), findsOneWidget);
      expect(h.mutations.requests.length, 1);
    },
  );

  testWidgets(
    'absent source date is not inferred; picker cancel stays empty; explicit selection sets ISO date',
    (tester) async {
      h.snapshots.value = _snapshot(dateAbsent: true);
      apply();
      await show(tester);
      await open(tester, 'date');
      expect(find.text('Not provided'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(key('day-correction-value'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.byTooltip('Choose date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(key('day-correction-value'))
            .controller!
            .text,
        isEmpty,
      );
      expect(h.mutations.requests, isEmpty);
      await tester.enterText(key('day-correction-value'), '2031-05-20');
      await tester.tap(find.byTooltip('Choose date'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .initialDate,
        DateTime(2031, 5, 20),
      );
      await tester.tap(find.text('21'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tap(tester, 'save-day-decision');
      expect(requestDecision().overrides.date!.toMap(), {
        'operation': 'set',
        'value': '2031-05-21',
      });
      expect(h.snapshots.value.days.first.date, isNull);
      expect(h.snapshots.value.days.last.date, DateTime.utc(2027, 4, 12));
      expect(h.mutations.requests.length, 1);
    },
  );

  for (final invalid in [
    '2027-02-29',
    '2028-02-30',
    '2027-13-10',
    '2027-00-10',
    '10/04/2027',
    'tomorrow',
  ]) {
    test(
      'date correction rejects $invalid',
      () => expect(
        validateDayCorrection(StagedDayCorrectionField.date, invalid),
        isNotNull,
      ),
    );
  }
  testWidgets('invalid date has a safe inline error and no command', (
    tester,
  ) async {
    await show(tester);
    await open(tester, 'date');
    await tester.enterText(key('day-correction-value'), '2027-02-29');
    await tap(tester, 'save-day-decision');
    expect(find.text('Enter a valid date as YYYY-MM-DD.'), findsOneWidget);
    expect(h.mutations.requests, isEmpty);
  });
  for (final text in [
    'price',
    'amount',
    'currency',
    'supplement',
    'markup',
    'margin',
    'discount',
    'payment',
    '₹',
    'USD 20',
    'cost 50',
  ]) {
    test(
      'correction preflight rejects commercial content $text',
      () => expect(
        validateDayCorrection(StagedDayCorrectionField.notes, text),
        isNotNull,
      ),
    );
  }
  testWidgets(
    'text normalization and length/commercial validation match submission constraints',
    (tester) async {
      apply();
      await show(tester);
      await open(tester, 'notes');
      for (final value in ['x' * 2001, 'Supplier margin', 'USD 300']) {
        await tester.enterText(key('day-correction-value'), value);
        await tap(tester, 'save-day-decision');
        expect(h.mutations.requests, isEmpty);
      }
      final valid = 'a' * 2000;
      await tester.enterText(key('day-correction-value'), '  $valid  ');
      await tap(tester, 'save-day-decision');
      expect(requestDecision().overrides.notes!.toMap(), {
        'operation': 'set',
        'value': valid,
      });
    },
  );

  testWidgets(
    'saving correction gates day and service controls and duplicate save submits once',
    (tester) async {
      final pending = Completer<SupplierImportResolutionMutationOutcome>();
      h.mutations.onExecute = (_) => pending.future;
      await show(tester);
      await open(tester, 'title');
      await tester.enterText(key('day-correction-value'), 'Pending title');
      final save = tester
          .widget<FilledButton>(key('save-day-decision'))
          .onPressed!;
      save();
      save();
      await tester.pump(const Duration(seconds: 1));
      expect(h.mutations.requests.length, 1);
      expect(actions(), findsNothing);
      expect(find.text('Saving day decision…'), findsOneWidget);
      expect(sourceTitle(), findsOneWidget);
      expect(panelText('Pending title'), findsNothing);
      h.resolutions.value = dayReviewResolution(
        decisions: [requestDecision()],
        revision: 2,
      );
      pending.complete(reviewOutcome('applied'));
      await tester.pumpAndSettle();
      expect(actions(), findsNWidgets(5));
    },
  );
  for (final outcome in ['applied', 'already_applied']) {
    testWidgets('$outcome waits for and renders authoritative correction', (
      tester,
    ) async {
      final pending = Completer<SupplierImportResolutionReadResult>();
      h.mutations.onExecute = (_) {
        h.resolutions.onRead = () => pending.future;
        return reviewOutcome(outcome);
      };
      await show(tester);
      await open(tester, 'title');
      await tester.enterText(key('day-correction-value'), 'Submitted title');
      await tap(tester, 'save-day-decision', settle: false);
      expect(panelText('Submitted title'), findsNothing);
      expect(actions(), findsNothing);
      pending.complete(
        dayReviewResolution(
          decisions: [
            dayReviewDecision(
              overrides: const SupplierImportDayOverrides(
                title: SupplierImportSetOverride('Authoritative title'),
              ),
            ),
          ],
          revision: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(panelText('Authoritative title'), findsOneWidget);
      expect(panelText('Submitted title'), findsNothing);
    });
  }
  testWidgets(
    'conflict closes correction editor and next intent composes latest state',
    (tester) async {
      h.mutations.onExecute = (_) {
        h.resolutions.value = dayReviewResolution(
          decisions: [
            dayReviewDecision(
              order: 8,
              overrides: const SupplierImportDayOverrides(
                notes: SupplierImportSetOverride('Latest notes'),
              ),
            ),
          ],
          revision: 3,
        );
        return reviewOutcome('resolution_conflict', revision: 3);
      };
      await show(tester);
      await open(tester, 'title');
      await tester.enterText(key('day-correction-value'), 'Stale title');
      await tap(tester, 'save-day-decision');
      expect(key('day-decision-dialog'), findsNothing);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      expect(h.mutations.requests.length, 1);
      expect(panelText('Stale title'), findsNothing);
      apply();
      await open(tester, 'title');
      await tester.enterText(key('day-correction-value'), 'Fresh title');
      await tap(tester, 'save-day-decision');
      expect(h.mutations.requests.last.expectedRevision, 3);
      expect(requestDecision().canonicalOrder, 8);
      expect(requestDecision().overrides.notes!.toMap(), {
        'operation': 'set',
        'value': 'Latest notes',
      });
    },
  );
  testWidgets(
    'ambiguous correction retry reuses exact pending command identity',
    (tester) async {
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.unavailable,
      );
      await show(tester);
      await open(tester, 'summary');
      await tester.enterText(key('day-correction-value'), 'Updated summary');
      await tap(tester, 'save-day-decision');
      final request = h.mutations.requests.single;
      expect(find.text('Retry same request'), findsOneWidget);
      expect(actions(), findsNothing);
      h.mutations.error = null;
      apply(outcome: 'already_applied');
      await tap(tester, 'retry-review-request');
      expect(h.mutations.requests.length, 2);
      expect(h.mutations.requests.last, same(request));
      expect(panelText('Updated summary'), findsOneWidget);
    },
  );
  testWidgets(
    'backend invalid mutation is sanitized and gates corrections until refresh',
    (tester) async {
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.invalidMutation,
      );
      await show(tester);
      await open(tester, 'title');
      await tester.enterText(key('day-correction-value'), 'Safe title');
      await tap(tester, 'save-day-decision');
      expect(
        find.text('This Supplier Import review change is invalid.'),
        findsOneWidget,
      );
      expect(actions(), findsNothing);
      expect(panelText('Safe title'), findsNothing);
      await tap(tester, 'refresh-supplier-review');
      expect(actions(), findsNWidgets(5));
      expect(h.mutations.requests.length, 1);
    },
  );
  testWidgets('raw exception data is absent from correction failure UI', (
    tester,
  ) async {
    h.mutations.error = StateError('PRIVATE Firebase payload');
    await show(tester);
    await open(tester, 'title');
    await tester.enterText(key('day-correction-value'), 'Safe title');
    await tap(tester, 'save-day-decision');
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(find.textContaining('Firebase'), findsNothing);
    expect(actions(), findsNothing);
  });
  testWidgets(
    'replaced review session discards stale correction editor result',
    (tester) async {
      await show(tester);
      await open(tester, 'title');
      await tester.enterText(key('day-correction-value'), 'Stale title');
      dependencies = SupplierImportReviewDependencies(
        snapshots: h.snapshots,
        resolutions: h.resolutions,
        mutations: h.mutations,
      );
      await show(tester);
      await tap(tester, 'save-day-decision');
      expect(h.mutations.requests, isEmpty);
    },
  );

  for (final width in [375.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
    testWidgets(
      'corrections and date picker fit ${width.toInt()}px with long source and reachable footer',
      (tester) async {
        h.snapshots.value = _snapshot(longText: true);
        await show(tester, width: width);
        await open(tester, 'notes');
        await tester.ensureVisible(key('day-correction-value'));
        await tester.enterText(key('day-correction-value'), 'Corrected notes');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final bounds = tester.getRect(key('day-decision-dialog'));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
        final footer = tester.getRect(key('save-day-decision'));
        expect(footer.height, greaterThanOrEqualTo(48));
        expect(footer.bottom, lessThanOrEqualTo(950));
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await tap(tester, 'correct-day-date');
        await tester.ensureVisible(key('day-correction-value'));
        await tester.tap(find.byTooltip('Choose date'));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(h.mutations.requests, isEmpty);
      },
    );
  }
  testWidgets(
    'enlarged text and keyboard preserve correction action accessibility',
    (tester) async {
      await show(tester, width: 390, scale: 1.5);
      await open(tester, 'summary');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('day-correction-value'));
      await tester.enterText(key('day-correction-value'), 'Readable summary');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(key('save-day-decision')).bottom,
        lessThanOrEqualTo(650),
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Clear value'), findsOneWidget);
      semantics.dispose();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tap(tester, 'correct-day-date');
      await tester.ensureVisible(key('day-correction-value'));
      await tester.tap(find.byTooltip('Choose date'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    },
  );
  testWidgets(
    'keyboard reset selection, Enter submission and Escape cancellation work',
    (tester) async {
      apply();
      await show(tester);
      await open(tester, 'title');
      await tester.enterText(key('day-correction-value'), 'Keyboard title');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(requestDecision().overrides.title!.value, 'Keyboard title');
      await open(tester, 'title');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Remove only the title correction'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(key('day-decision-dialog'), findsNothing);
      expect(h.mutations.requests.length, 1);
    },
  );
  testWidgets('only supported day fields have correction controls', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'day-review-action-staged-day-1');
    final corrections = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('correct-day-'),
    );
    expect(corrections, findsNWidgets(4));
    for (final label in [
      'Edit service',
      'Add day',
      'Add service',
      'Finalize',
      'Approve import',
      'Create itinerary',
      'Acknowledge',
      'Price',
      'Margin',
      'Payment',
    ]) {
      expect(find.text(label), findsNothing);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tap(tester, 'service-review-action-staged-service-1');
    expect(find.text('Corrections'), findsNothing);
    expect(find.text('Correct title'), findsNothing);
  });
  test(
    'correction presentation has no direct transport, Trip date access, AI or finalization',
    () {
      for (final file
          in Directory(
            'lib/features/itineraries/presentation/widgets/supplier_import',
          ).listSync().whereType<File>().where(
            (f) => f.path.contains('staged_day_correction'),
          )) {
        final source = file.readAsStringSync();
        for (final forbidden in [
          'FirebaseFirestore',
          'FirebaseFunctions',
          'travelStartDate',
          'canFinalize',
          'upsertManualItem',
          'removeDecision(',
          'Gemini',
        ]) {
          expect(source, isNot(contains(forbidden)), reason: file.path);
        }
      }
    },
  );
}

SupplierExtractionSnapshot _snapshot({
  bool dateAbsent = false,
  bool longText = false,
}) => SupplierExtractionSnapshot.fromStoredDocuments(
  expectedTripId: 'trip-1',
  expectedExtractionId: 'extraction-1',
  root: supplierExtractionRoot(),
  dayDocuments: supplierExtractionDayDocuments()
      .map(
        (doc) => (
          documentId: doc.documentId,
          data: {
            ...doc.data,
            'value': {
              ...doc.data['value']! as Map<String, Object?>,
              if (dateAbsent && doc.documentId == 'staged-day-1') 'date': null,
              if (longText)
                'notes': List.filled(
                  12,
                  'A detailed supplier note about arrival arrangements and the surrounding sightseeing schedule.',
                ).join(' '),
            },
          },
        ),
      )
      .toList(),
  factDocuments: supplierExtractionFactDocuments(),
  reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
  trustedSourceFileIds: const ['file-1'],
);
