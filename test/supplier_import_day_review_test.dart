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

import 'support/supplier_extraction_fixture.dart';
import 'support/supplier_import_day_review_fixture.dart';
import 'support/supplier_import_resolution_fixture.dart';
import 'support/supplier_import_review_fixture.dart';

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
  Finder key(String value) => find.byKey(ValueKey(value));
  Finder inside(String parent, String text) =>
      find.descendant(of: key(parent), matching: find.text(text));
  Finder actions(String kind) => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          '$kind-review-action-',
        ),
  );

  Future<void> show(
    WidgetTester tester, {
    double width = 1440,
    double height = 1000,
    double scale = 1,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
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
    if (settle) await tester.pumpAndSettle();
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

  Future<void> open(WidgetTester tester, [int day = 1]) =>
      tap(tester, 'day-review-action-staged-day-$day');
  Future<void> retain(WidgetTester tester, {bool settle = true}) async {
    await open(tester);
    await tap(tester, 'day-action-retain');
    await tap(tester, 'save-day-decision', settle: settle);
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  }

  Future<void> order(WidgetTester tester, String value) async {
    await open(tester);
    await tap(tester, 'day-action-order');
    await tester.enterText(key('day-consultant-order'), value);
    await tap(tester, 'save-day-decision');
  }

  Map<String, Object?> lastDecision() =>
      (h.mutations.requests.last.mutation as SupplierImportSetDecisionCommand)
          .decision
          .toMutationMap();

  void applyRequests({String outcome = 'applied'}) {
    h.mutations.onExecute = (request) {
      final old =
          (h.resolutions.value as SupplierImportResolutionLoaded).resolution;
      var decisions = old.decisions.map((stored) => stored.payload).toList();
      switch (request.mutation) {
        case SupplierImportSetDecisionCommand(:final decision):
          decisions = [
            ...decisions.where(
              (item) => item.targetEntityId != decision.targetEntityId,
            ),
            decision,
          ];
        case SupplierImportRemoveDecisionCommand(:final decisionId):
          decisions = decisions
              .where((item) => item.targetEntityId != decisionId)
              .toList();
        default:
          throw StateError('Unexpected command');
      }
      h.resolutions.value = dayReviewResolution(
        decisions: decisions,
        revision: old.root.revision + 1,
      );
      return reviewOutcome(outcome, revision: old.root.revision + 1);
    };
  }

  for (final state in ['not-started', 'active', 'finalized']) {
    testWidgets('$state gates day controls without changing source evidence', (
      tester,
    ) async {
      h.resolutions.value = state == 'not-started'
          ? const SupplierImportResolutionNotStarted()
          : reviewResolution(
              finalized: state == 'finalized',
              revision: state == 'finalized' ? 2 : 1,
            );
      await show(tester);
      expect(
        actions('day'),
        state == 'active' ? findsNWidgets(2) : findsNothing,
      );
      expect(
        find.text('Start review'),
        state == 'not-started' ? findsOneWidget : findsNothing,
      );
      expect(inside('review-day-staged-day-1', 'Source day 3'), findsOneWidget);
      // The source date is visible in both the day heading and source fields.
      expect(
        inside('review-day-staged-day-1', '10 Apr 2027'),
        findsNWidgets(2),
      );
      expect(inside('review-day-staged-day-2', 'Source day 7'), findsOneWidget);
      expect(h.mutations.requests, isEmpty);
    });
  }

  testWidgets(
    'retain uses exact day contract and authoritative revision; source stays intact',
    (tester) async {
      h.resolutions.value = reviewResolution(revision: 4);
      final original = h.snapshots.value;
      applyRequests();
      await show(tester);
      await retain(tester);
      expect(h.mutations.requests.single.expectedRevision, 4);
      expect(h.mutations.requests.single.tripId, 'trip-1');
      expect(h.mutations.requests.single.extractionId, 'extraction-1');
      expect(lastDecision(), dayReviewDecision().toMutationMap());
      expect(lastDecision().containsKey('canonicalOrder'), isFalse);
      expect(
        inside('day-decision-panel-staged-day-1', 'Accepted as extracted'),
        findsOneWidget,
      );
      expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
      expect(inside('review-unassigned', 'Airport transfer'), findsOneWidget);
      expect(h.snapshots.value, same(original));
      expect(h.snapshots.readCount, 1);
    },
  );

  testWidgets(
    'current day decisions use identity, not matching title/date/number or history',
    (tester) async {
      h.snapshots.value = _snapshot(duplicateLabels: true);
      h.resolutions.value = dayReviewResolution(
        decisions: [dayReviewDecision(id: 'staged-day-2')],
        revision: 3,
      );
      await show(tester);
      expect(
        inside('day-decision-panel-staged-day-1', 'Accepted as extracted'),
        findsNothing,
      );
      expect(
        inside('day-decision-panel-staged-day-2', 'Accepted as extracted'),
        findsOneWidget,
      );
      await open(tester);
      expect(key('day-action-revert'), findsNothing);
      expect(find.text('Review history (3)'), findsOneWidget);
    },
  );

  for (final reason in SupplierImportExclusionReason.values) {
    testWidgets(
      'day exclusion ${reason.value} follows typed rationale and preserves services',
      (tester) async {
        final service = dayReviewService(exclude: true);
        h.resolutions.value = dayReviewResolution(decisions: [service]);
        final original = h.snapshots.value;
        applyRequests();
        await show(tester);
        await open(tester);
        await tap(tester, 'day-action-exclude');
        expect(
          tester.widget<FilledButton>(key('save-day-decision')).onPressed,
          isNull,
        );
        await tap(tester, 'day-reason-${reason.value}');
        if (reason == SupplierImportExclusionReason.other) {
          await tap(tester, 'save-day-decision');
          expect(
            find.text('Explain why this day is being excluded.'),
            findsOneWidget,
          );
          expect(h.mutations.requests, isEmpty);
          await tester.enterText(
            key('day-exclusion-note'),
            '  Duplicate   supplier\nsection  ',
          );
        }
        await tap(tester, 'save-day-decision');
        expect(
          lastDecision(),
          dayReviewDecision(
            exclude: reason,
            note: reason == SupplierImportExclusionReason.other
                ? 'Duplicate supplier section'
                : null,
          ).toMutationMap(),
        );
        expect(
          inside('day-decision-panel-staged-day-1', 'Excluded from import'),
          findsOneWidget,
        );
        expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
        expect(h.snapshots.value, same(original));
        final result =
            (h.resolutions.value as SupplierImportResolutionLoaded).resolution;
        expect(
          result.decisions
              .where((d) => d.payload is SupplierImportServiceDecision)
              .single
              .payload
              .toMutationMap(),
          service.toMutationMap(),
        );
        expect(h.mutations.requests.length, 1);
      },
    );
  }

  testWidgets(
    'day exclusion note validates required, length and non-commercial constraints',
    (tester) async {
      h.resolutions.value = dayReviewResolution(
        decisions: [dayReviewService(exclude: true)],
      );
      await show(tester);
      await open(tester);
      await tap(tester, 'day-action-exclude');
      await tap(tester, 'day-reason-other');
      for (final (note, error) in [
        ('', 'Explain why this day is being excluded.'),
        ('x' * 2001, 'Use 2,000 characters or fewer.'),
        (
          'Payment omitted',
          'Use a non-commercial explanation for this exclusion.',
        ),
        ('₹ 370', 'Use a non-commercial explanation for this exclusion.'),
      ]) {
        await tester.enterText(key('day-exclusion-note'), note);
        await tap(tester, 'save-day-decision');
        expect(find.text(error), findsOneWidget);
        expect(h.mutations.requests, isEmpty);
      }
    },
  );

  for (final scenario in [
    'untouched',
    'explicit-retain',
    'incoming-move',
    'incoming-unassigned',
  ]) {
    testWidgets(
      '$scenario effective service blocks exclusion locally without cascading',
      (tester) async {
        final decisions = <SupplierImportDecisionPayload>[
          if (scenario == 'explicit-retain') dayReviewService(),
          if (scenario.startsWith('incoming')) ...[
            dayReviewService(day: 'staged-day-2'),
            dayReviewService(
              id: scenario == 'incoming-move'
                  ? 'staged-service-2'
                  : 'staged-service-3',
              day: 'staged-day-1',
            ),
          ],
        ];
        h.resolutions.value = dayReviewResolution(decisions: decisions);
        await show(tester);
        await open(tester);
        await tap(tester, 'day-action-exclude');
        expect(
          find.text(
            'Move or exclude the services assigned to this day before excluding the day.',
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(key('save-day-decision')).onPressed,
          isNull,
        );
        expect(key('day-exclusion-note'), findsNothing);
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  for (final scenario in ['moved-away', 'excluded', 'unresolved-unassigned']) {
    testWidgets(
      '$scenario does not strand a service or prevent otherwise-valid exclusion',
      (tester) async {
        h.resolutions.value = dayReviewResolution(
          decisions: [
            dayReviewService(
              day: scenario == 'moved-away' ? 'staged-day-2' : null,
              exclude: scenario != 'moved-away',
            ),
            if (scenario == 'unresolved-unassigned')
              dayReviewService(id: 'staged-service-3'),
          ],
        );
        applyRequests();
        await show(tester);
        await open(tester);
        await tap(tester, 'day-action-exclude');
        expect(key('day-decision-blocker'), findsNothing);
        await tap(tester, 'day-reason-duplicate');
        await tap(tester, 'save-day-decision');
        expect(
          h.mutations.requests.single.mutation,
          isA<SupplierImportSetDecisionCommand>(),
        );
        expect(lastDecision()['decisionKind'], 'day');
        expect(inside('review-unassigned', 'Airport transfer'), findsOneWidget);
        expect(
          inside(
            'review-service-staged-service-3',
            'No day assigned in source',
          ),
          findsOneWidget,
        );
      },
    );
  }

  for (final dependency in ['manual-service', 'mapped-accommodation']) {
    testWidgets(
      '$dependency also blocks day exclusion without exposing unrelated controls',
      (tester) async {
        h.resolutions.value = dayReviewResolution(
          decisions: [
            dayReviewService(exclude: true),
            if (dependency == 'mapped-accommodation')
              SupplierImportPackageAccommodationDecision.fromStoredMap({
                ...supplierImportAccommodationDecision(),
                'disposition': 'map_to_day_service',
                'day': {'kind': 'staged_day', 'dayId': 'staged-day-1'},
                'canonicalOrder': 1,
              }),
          ],
          manual: [
            if (dependency == 'manual-service')
              {
                ...supplierImportManualService(),
                'day': {'kind': 'staged_day', 'dayId': 'staged-day-1'},
              },
          ],
        );
        await show(tester);
        await open(tester);
        await tap(tester, 'day-action-exclude');
        expect(
          find.textContaining(
            dependency == 'manual-service'
                ? 'Consultant-added services still use'
                : 'Mapped accommodation still uses',
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(key('save-day-decision')).onPressed,
          isNull,
        );
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  testWidgets(
    'service move, day exclusion and revert refresh shared assignment eligibility',
    (tester) async {
      applyRequests();
      final original = h.snapshots.value;
      await show(tester);
      await tap(tester, 'service-review-action-staged-service-1');
      await tap(tester, 'service-action-assign');
      await tap(tester, 'service-target-staged-day-2');
      await tap(tester, 'save-service-decision');
      await open(tester);
      await tap(tester, 'day-action-exclude');
      await tap(tester, 'day-reason-duplicate');
      await tap(tester, 'save-day-decision');
      await tap(tester, 'service-review-action-staged-service-3');
      await tap(tester, 'service-action-assign');
      expect(key('service-target-staged-day-1'), findsNothing);
      expect(key('service-target-staged-day-2'), findsOneWidget);
      await cancel(tester);
      await open(tester);
      await tap(tester, 'day-action-revert');
      await tap(tester, 'save-day-decision');
      expect(h.mutations.requests.last.mutation.toMap(), {
        'action': 'remove_decision',
        'decisionId': 'staged-day-1',
      });
      expect(
        inside('day-decision-panel-staged-day-1', 'Excluded from import'),
        findsNothing,
      );
      expect(find.text('Review history (4)'), findsOneWidget);
      expect(h.snapshots.value, same(original));
      await tap(tester, 'service-review-action-staged-service-3');
      await tap(tester, 'service-action-assign');
      expect(key('service-target-staged-day-1'), findsOneWidget);
      expect(key('service-target-staged-day-2'), findsOneWidget);
      expect(h.mutations.requests.length, 3);
    },
  );

  testWidgets(
    'single-day order mutation uses integer canonicalOrder and never moves source cards',
    (tester) async {
      applyRequests();
      final original = h.snapshots.value;
      await show(tester);
      await order(tester, '3');
      expect(h.mutations.requests.length, 1);
      expect(lastDecision(), dayReviewDecision(order: 3).toMutationMap());
      expect(lastDecision()['canonicalOrder'], isA<int>());
      expect(
        inside('day-decision-panel-staged-day-1', 'Consultant order'),
        findsOneWidget,
      );
      expect(inside('day-decision-panel-staged-day-1', '3'), findsOneWidget);
      expect(
        inside('day-decision-panel-staged-day-1', 'Source position'),
        findsOneWidget,
      );
      expect(inside('day-decision-panel-staged-day-1', '1'), findsOneWidget);
      expect(inside('review-day-staged-day-1', 'Source day 3'), findsOneWidget);
      expect(
        inside('review-day-staged-day-1', '10 Apr 2027'),
        findsNWidgets(2),
      );
      expect(
        tester.getTopLeft(key('review-day-staged-day-1')).dy,
        lessThan(tester.getTopLeft(key('review-day-staged-day-2')).dy),
      );
      expect(h.snapshots.value, same(original));
      expect(original.days.map((day) => day.order), [1, 2]);
      final resolution =
          (h.resolutions.value as SupplierImportResolutionLoaded).resolution;
      expect(resolution.decisions.length, 1);
      expect(resolution.auditEvents.length, 2);
      expect(resolution.root.revision, 2);
    },
  );

  for (final input in ['', '0', '-1', '1.5', 'abc', '2', '9007199254740992']) {
    testWidgets('order "$input" is rejected before submission', (tester) async {
      await show(tester);
      await order(tester, input);
      expect(key('day-decision-dialog'), findsOneWidget);
      expect(h.mutations.requests, isEmpty);
      expect(
        find.text(
          input == '2'
              ? 'This order is already used by another retained day. Choose an unused number.'
              : input == '9007199254740992'
              ? 'Enter a smaller whole number.'
              : 'Enter a positive whole number.',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('order preflight includes existing consultant day orders', (
    tester,
  ) async {
    h.resolutions.value = dayReviewResolution(
      decisions: [dayReviewDecision(id: 'staged-day-2', order: 7)],
      manual: [
        {...supplierImportManualDay(), 'canonicalOrder': 4},
      ],
    );
    await show(tester);
    await order(tester, '7');
    expect(
      find.textContaining('already used by another retained day'),
      findsOneWidget,
    );
    await tester.enterText(key('day-consultant-order'), '4');
    await tap(tester, 'save-day-decision');
    expect(
      find.textContaining('already used by a consultant-added day'),
      findsOneWidget,
    );
    expect(h.mutations.requests, isEmpty);
  });

  testWidgets(
    'excluded day does not reserve its order; other days are never renumbered',
    (tester) async {
      h.resolutions.value = dayReviewResolution(
        decisions: [
          dayReviewService(id: 'staged-service-2', exclude: true),
          dayReviewDecision(
            id: 'staged-day-2',
            exclude: SupplierImportExclusionReason.duplicate,
          ),
        ],
      );
      applyRequests();
      await show(tester);
      await order(tester, '2');
      expect(h.mutations.requests.length, 1);
      expect(lastDecision(), dayReviewDecision(order: 2).toMutationMap());
      expect(
        inside('day-decision-panel-staged-day-2', 'Excluded from import'),
        findsOneWidget,
      );
    },
  );

  for (final action in ['retain', 'order', 'exclude']) {
    testWidgets(
      '$action preserves previously recorded day corrections and independent order',
      (tester) async {
        final corrections = SupplierImportDayOverrides.fromMap({
          'title': {'operation': 'set', 'value': 'Consultant title'},
          'date': {'operation': 'clear'},
        });
        h.resolutions.value = dayReviewResolution(
          decisions: [
            dayReviewDecision(order: 5, overrides: corrections),
            dayReviewService(exclude: true),
          ],
        );
        applyRequests();
        await show(tester);
        expect(
          inside('day-decision-panel-staged-day-1', 'Accepted as extracted'),
          findsNothing,
        );
        await open(tester);
        expect(
          find.text('Existing field corrections will be kept.'),
          findsOneWidget,
        );
        await tap(tester, 'day-action-$action');
        if (action == 'order') {
          await tester.enterText(key('day-consultant-order'), '7');
        }
        if (action == 'exclude') await tap(tester, 'day-reason-duplicate');
        await tap(tester, 'save-day-decision');
        expect(lastDecision()['overrides'], corrections.toMap());
        expect(lastDecision()['canonicalOrder'], action == 'order' ? 7 : 5);
        expect(
          inside('review-day-staged-day-1', 'Tokyo arrival'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'revert removes only current day decision and preserves source and existing audit objects',
    (tester) async {
      h.resolutions.value = dayReviewResolution(
        decisions: [dayReviewDecision(order: 5)],
        revision: 2,
      );
      final old =
          (h.resolutions.value as SupplierImportResolutionLoaded).resolution;
      applyRequests();
      await show(tester);
      await open(tester);
      await tap(tester, 'day-action-revert');
      await tap(tester, 'save-day-decision');
      expect(h.mutations.requests.single.mutation.toMap(), {
        'action': 'remove_decision',
        'decisionId': 'staged-day-1',
      });
      expect(
        inside('day-decision-panel-staged-day-1', 'Consultant order'),
        findsNothing,
      );
      expect(find.text('Review history (3)'), findsOneWidget);
      expect(old.auditEvents.length, 2);
      expect(old.decisions.length, 1);
      expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
      await open(tester);
      expect(key('day-action-revert'), findsNothing);
    },
  );

  for (final action in ['retain', 'revert']) {
    testWidgets(
      '$action cannot restore an occupied order after day exclusion',
      (tester) async {
        h.resolutions.value = dayReviewResolution(
          decisions: [
            dayReviewService(exclude: true),
            dayReviewDecision(exclude: SupplierImportExclusionReason.duplicate),
            dayReviewDecision(id: 'staged-day-2', order: 1),
          ],
        );
        await show(tester);
        await open(tester);
        await tap(tester, 'day-action-$action');
        expect(key('day-decision-blocker'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(key('save-day-decision')).onPressed,
          isNull,
        );
        expect(h.mutations.requests, isEmpty);
        applyRequests();
        await tap(tester, 'day-action-order');
        await tester.enterText(key('day-consultant-order'), '3');
        await tap(tester, 'save-day-decision');
        expect(lastDecision(), dayReviewDecision(order: 3).toMutationMap());
      },
    );
  }

  testWidgets(
    'one day mutation in flight blocks both day and service actions, including double tap',
    (tester) async {
      final pending = Completer<SupplierImportResolutionMutationOutcome>();
      h.mutations.onExecute = (_) => pending.future;
      await show(tester);
      await tester.ensureVisible(key('day-review-action-staged-day-1'));
      final callback = tester
          .widget<OutlinedButton>(key('day-review-action-staged-day-1'))
          .onPressed!;
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(key('day-decision-dialog'), findsOneWidget);
      await tap(tester, 'day-action-retain');
      await tester.tap(key('save-day-decision'));
      await tester.tap(key('save-day-decision'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));
      expect(actions('day'), findsNothing);
      expect(actions('service'), findsNothing);
      expect(find.text('Saving day decision…'), findsOneWidget);
      expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
      expect(
        inside('day-decision-panel-staged-day-1', 'Accepted as extracted'),
        findsNothing,
      );
      expect(h.mutations.requests.length, 1);
      h.resolutions.value = dayReviewResolution(
        decisions: [dayReviewDecision()],
        revision: 2,
      );
      pending.complete(reviewOutcome('applied'));
      await tester.pumpAndSettle();
      expect(actions('day'), findsNWidgets(2));
      expect(actions('service'), findsNWidgets(3));
    },
  );

  testWidgets('a service save also gates all day entry points', (tester) async {
    final pending = Completer<SupplierImportResolutionMutationOutcome>();
    h.mutations.onExecute = (_) => pending.future;
    await show(tester);
    await tap(tester, 'service-review-action-staged-service-1');
    await tap(tester, 'service-action-retain');
    await tap(tester, 'save-service-decision', settle: false);
    expect(actions('day'), findsNothing);
    expect(actions('service'), findsNothing);
    h.resolutions.value = dayReviewResolution(
      decisions: [dayReviewService()],
      revision: 2,
    );
    pending.complete(reviewOutcome('applied'));
    await tester.pumpAndSettle();
    expect(actions('day'), findsNWidgets(2));
  });

  for (final outcome in ['applied', 'already_applied']) {
    testWidgets(
      '$outcome waits for authoritative day reload instead of fabricating the submitted decision',
      (tester) async {
        final pending = Completer<SupplierImportResolutionReadResult>();
        h.mutations.onExecute = (_) {
          h.resolutions.onRead = () => pending.future;
          return reviewOutcome(outcome);
        };
        await show(tester);
        await retain(tester, settle: false);
        expect(actions('day'), findsNothing);
        expect(
          inside('day-decision-panel-staged-day-1', 'Accepted as extracted'),
          findsNothing,
        );
        pending.complete(
          dayReviewResolution(
            decisions: [dayReviewDecision(order: 9)],
            revision: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(inside('day-decision-panel-staged-day-1', '9'), findsOneWidget);
        expect(h.mutations.requests.length, 1);
        expect(h.resolutions.readCount, 2);
      },
    );
  }

  testWidgets(
    'day conflict closes the editor, refreshes, and requires a new explicit choice',
    (tester) async {
      h.mutations.onExecute = (_) {
        h.resolutions.value = dayReviewResolution(
          decisions: [dayReviewDecision(order: 4)],
          revision: 3,
        );
        return reviewOutcome('resolution_conflict', revision: 3);
      };
      await show(tester);
      await retain(tester);
      expect(key('day-decision-dialog'), findsNothing);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      expect(inside('day-decision-panel-staged-day-1', '4'), findsOneWidget);
      expect(h.mutations.requests.length, 1);
      applyRequests();
      await order(tester, '6');
      expect(h.mutations.requests.length, 2);
      expect(h.mutations.requests.last.expectedRevision, 3);
      expect(
        h.mutations.requests.last.commandId,
        isNot(h.mutations.requests.first.commandId),
      );
    },
  );

  testWidgets(
    'ambiguous day result uses only page retry with identical pending request',
    (tester) async {
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.unavailable,
      );
      await show(tester);
      await retain(tester);
      final request = h.mutations.requests.single;
      expect(actions('day'), findsNothing);
      expect(actions('service'), findsNothing);
      expect(find.text('Retry same request'), findsOneWidget);
      expect(
        find.text('Awaiting review confirmation. See the review notice above.'),
        findsOneWidget,
      );
      h.mutations.error = null;
      applyRequests(outcome: 'already_applied');
      await tap(tester, 'retry-review-request');
      expect(h.mutations.requests.last, same(request));
      expect(h.mutations.requests.length, 2);
      expect(
        inside('day-decision-panel-staged-day-1', 'Accepted as extracted'),
        findsOneWidget,
      );
    },
  );

  for (final (failure, message) in [
    (
      SupplierImportMutationFailureKind.invalidMutation,
      'This Supplier Import review change is invalid.',
    ),
    (
      SupplierImportMutationFailureKind.permissionDenied,
      'You do not have access to this Supplier Import review.',
    ),
  ]) {
    testWidgets(
      '$failure uses safe errors and gates day controls until refreshed',
      (tester) async {
        h.mutations.error = SupplierImportMutationFailure(failure);
        await show(tester);
        await retain(tester);
        expect(find.text(message), findsOneWidget);
        expect(actions('day'), findsNothing);
        expect(find.textContaining('Firebase'), findsNothing);
        expect(
          inside('day-decision-panel-staged-day-1', 'Accepted as extracted'),
          findsNothing,
        );
        await tap(tester, 'refresh-supplier-review');
        expect(actions('day'), findsNWidgets(2));
        expect(h.mutations.requests.length, 1);
      },
    );
  }

  testWidgets(
    'reload errors and replaced sessions cannot submit stale day decisions',
    (tester) async {
      await show(tester);
      await open(tester);
      await tap(tester, 'day-action-retain');
      dependencies = SupplierImportReviewDependencies(
        snapshots: h.snapshots,
        resolutions: h.resolutions,
        mutations: h.mutations,
      );
      h.resolutions.error = StateError('private Firebase payload');
      await show(tester);
      await tap(tester, 'save-day-decision');
      expect(h.mutations.requests, isEmpty);
      expect(actions('day'), findsNothing);
      expect(find.textContaining('private Firebase'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [375.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
    testWidgets(
      'day status, long titles, order and exclusion dialog fit ${width.toInt()}px',
      (tester) async {
        h.snapshots.value = _snapshot(longTitle: true);
        h.resolutions.value = dayReviewResolution(
          decisions: [
            dayReviewService(exclude: true),
            dayReviewDecision(order: 4),
          ],
        );
        await show(tester, width: width, height: 844);
        await tester.ensureVisible(key('day-decision-panel-staged-day-1'));
        expect(tester.takeException(), isNull);
        await open(tester);
        await tap(tester, 'day-action-order');
        await tester.enterText(key('day-consultant-order'), '7');
        expect(tester.takeException(), isNull);
        await tap(tester, 'day-action-exclude');
        await tap(tester, 'day-reason-other');
        await tester.enterText(
          key('day-exclusion-note'),
          'Duplicated source section',
        );
        expect(tester.takeException(), isNull);
        final footer = tester.getRect(key('save-day-decision'));
        expect(footer.bottom, lessThanOrEqualTo(844));
        expect(footer.left, greaterThanOrEqualTo(0));
        expect(footer.right, lessThanOrEqualTo(width));
        expect(footer.height, greaterThanOrEqualTo(48));
      },
    );
  }

  testWidgets('keyboard inset and enlarged text keep day footer reachable', (
    tester,
  ) async {
    h.resolutions.value = dayReviewResolution(
      decisions: [dayReviewService(exclude: true)],
    );
    await show(tester, width: 390, height: 844, scale: 1.5);
    await open(tester);
    await tap(tester, 'day-action-exclude');
    await tap(tester, 'day-reason-other');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('day-exclusion-note'));
    await tester.enterText(
      key('day-exclusion-note'),
      'Duplicated supplier section',
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(key('save-day-decision')).bottom,
      lessThanOrEqualTo(544),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'day controls are keyboard accessible and cancellation produces no mutation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester);
      await open(tester);
      expect(find.bySemanticsLabel('Retain day'), findsOneWidget);
      expect(find.bySemanticsLabel('Change consultant order'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(key('save-day-decision')).onPressed,
        isNotNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(key('day-decision-dialog'), findsNothing);
      expect(h.mutations.requests, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'no field corrections, manual content, other fact decisions, or finalization are exposed',
    (tester) async {
      await show(tester);
      expect(find.byType(TextFormField), findsNothing);
      for (final text in [
        'Edit title',
        'Edit date',
        'Edit summary',
        'Edit notes',
        'Add day',
        'Add service',
        'Finalize',
        'Approve import',
        'Create itinerary',
        'Acknowledge',
      ]) {
        expect(find.text(text), findsNothing);
      }
      await open(tester);
      expect(find.byType(TextFormField), findsNothing);
      await tap(tester, 'day-action-order');
      expect(find.byType(TextFormField), findsOneWidget);
      expect(key('day-consultant-order'), findsOneWidget);
      final labels = find
          .descendant(
            of: key('day-decision-dialog'),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .join(' ');
      expect(labels, isNot(contains('staged-day-')));
      expect(labels, isNot(contains('staged-service-')));
      expect(labels, isNot(contains('extraction-1')));
    },
  );

  test(
    'day presentation adds no direct transport, finalization or bulk mutation path',
    () {
      for (final file
          in Directory(
            'lib/features/itineraries/presentation/widgets/supplier_import',
          ).listSync().whereType<File>().where(
            (f) => f.path.contains('staged_day_'),
          )) {
        final source = file.readAsStringSync();
        for (final forbidden in [
          'FirebaseFirestore',
          'FirebaseFunctions',
          'canFinalize',
          'finalize(',
          'upsertManualItem(',
          'Future.wait',
          'batch(',
        ]) {
          expect(source, isNot(contains(forbidden)), reason: file.path);
        }
      }
    },
  );
}

SupplierExtractionSnapshot _snapshot({
  bool duplicateLabels = false,
  bool longTitle = false,
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
              if (duplicateLabels) ...{
                'title': 'Same source title',
                'sourceDayNumber': 3,
                'date': '2027-04-10',
              },
              if (longTitle)
                'title':
                    'A long supplier day heading describing arrival, surrounding city sightseeing and a relaxed evening itinerary',
            },
          },
        ),
      )
      .toList(),
  factDocuments: supplierExtractionFactDocuments(),
  reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
  trustedSourceFileIds: const ['file-1'],
);
