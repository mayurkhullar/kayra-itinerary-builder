import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_fact.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_values.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_state.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/staged_service_decision_dialog.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/staged_service_review_data.dart';

import 'support/supplier_extraction_fixture.dart';
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
  Finder getActions() => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'service-review-action-',
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
    String value, {
    bool settle = true,
  }) async {
    final finder = key(value);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester, [int service = 1]) =>
      tap(tester, 'service-review-action-staged-service-$service');
  Future<void> retain(WidgetTester tester, {bool settle = true}) async {
    await open(tester);
    await tap(tester, 'service-action-retain');
    await tap(tester, 'save-service-decision', settle: settle);
  }

  void applyFromRequest({String outcome = 'applied', int revision = 2}) {
    h.mutations.onExecute = (request) {
      final command = request.mutation;
      h.resolutions.value = _resolution(
        revision: revision,
        decisions: command is SupplierImportSetDecisionCommand
            ? [command.decision]
            : [],
      );
      return reviewOutcome(outcome, revision: revision);
    };
  }

  Map<String, Object?> sentDecision() =>
      (h.mutations.requests.single.mutation as SupplierImportSetDecisionCommand)
          .decision
          .toMutationMap();

  for (final status in ['not-started', 'active', 'finalized']) {
    testWidgets('$status gates service controls and preserves source content', (
      tester,
    ) async {
      h.resolutions.value = status == 'not-started'
          ? const SupplierImportResolutionNotStarted()
          : reviewResolution(
              finalized: status == 'finalized',
              revision: status == 'finalized' ? 2 : 1,
            );
      await show(tester);
      expect(
        getActions(),
        status == 'active' ? findsNWidgets(3) : findsNothing,
      );
      expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
      expect(
        inside('review-day-staged-day-2', 'Kyoto city tour'),
        findsOneWidget,
      );
      expect(inside('review-unassigned', 'Airport transfer'), findsOneWidget);
      expect(
        find.text('Start review'),
        status == 'not-started' ? findsOneWidget : findsNothing,
      );
      expect(h.mutations.requests, isEmpty);
    });
  }

  testWidgets(
    'source placement labels use supplier chronology, not local renumbering',
    (tester) async {
      await show(tester);
      expect(
        inside(
          'review-service-staged-service-1',
          'Day 3 · Tokyo arrival · 10 Apr 2027',
        ),
        findsOneWidget,
      );
      expect(
        inside('review-service-staged-service-3', 'No day assigned in source'),
        findsOneWidget,
      );
      expect(find.text('Consultant decision'), findsNothing);
    },
  );

  testWidgets(
    'retain uses exact typed payload and current revision with no duplicate source',
    (tester) async {
      h.resolutions.value = reviewResolution(revision: 4);
      applyFromRequest(revision: 5);
      final original = h.snapshots.value;
      await show(tester);
      await retain(tester);
      final request = h.mutations.requests.single;
      expect(request.tripId, 'trip-1');
      expect(request.extractionId, 'extraction-1');
      expect(request.expectedRevision, 4);
      expect(sentDecision(), _service().toMutationMap());
      expect(sentDecision().containsKey('day'), isFalse);
      expect(sentDecision().containsKey('canonicalOrder'), isFalse);
      expect(
        inside('review-service-staged-service-1', 'Accepted as extracted'),
        findsOneWidget,
      );
      expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
      expect(h.snapshots.value, same(original));
      expect(h.snapshots.readCount, 1);
    },
  );

  for (final service in [1, 3]) {
    testWidgets(
      '${service == 1 ? 'move' : 'assign'} requires explicit staged day and preserves original source section',
      (tester) async {
        applyFromRequest();
        final original = h.snapshots.value;
        await show(tester);
        await open(tester, service);
        expect(key('service-action-revert'), findsNothing);
        expect(
          key('service-action-retain'),
          service == 1 ? findsOneWidget : findsNothing,
        );
        await tap(tester, 'service-action-assign');
        expect(
          tester.widget<FilledButton>(key('save-service-decision')).onPressed,
          isNull,
        );
        expect(h.mutations.requests, isEmpty);
        if (service == 1) {
          expect(key('service-target-staged-day-1'), findsNothing);
        }
        await tap(tester, 'service-target-staged-day-2');
        await tap(tester, 'save-service-decision');
        expect(
          sentDecision(),
          _service(
            id: 'staged-service-$service',
            day: 'staged-day-2',
            order: 2,
          ).toMutationMap(),
        );
        expect(
          inside(
            'review-service-staged-service-$service',
            '${service == 1 ? 'Moved' : 'Assigned'} to Day 7 · Kyoto discovery · 12 Apr 2027',
          ),
          findsOneWidget,
        );
        expect(
          inside(
            service == 1 ? 'review-day-staged-day-1' : 'review-unassigned',
            service == 1 ? 'Hotel stay' : 'Airport transfer',
          ),
          findsOneWidget,
        );
        expect(
          inside(
            'review-day-staged-day-2',
            service == 1 ? 'Hotel stay' : 'Airport transfer',
          ),
          findsNothing,
        );
        expect(h.snapshots.value, same(original));
        expect(
          (original.facts
              .whereType<SupplierExtractionServiceFact>()
              .last
              .scope),
          isA<SupplierExtractionUnassignedScope>(),
        );
      },
    );
  }

  testWidgets(
    'chooser preserves source order, explicit date only, no raw IDs or manual days',
    (tester) async {
      h.snapshots.value = SupplierExtractionSnapshot.fromStoredDocuments(
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
                    if (doc.documentId == 'staged-day-2') 'date': null,
                  },
                },
              ),
            )
            .toList(),
        factDocuments: supplierExtractionFactDocuments(),
        reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
        trustedSourceFileIds: const ['file-1'],
      );
      h.resolutions.value = _resolution(manual: [supplierImportManualDay()]);
      await show(tester);
      await open(tester, 3);
      await tap(tester, 'service-action-assign');
      final dialog = key('service-decision-dialog');
      final labels = find
          .descendant(of: dialog, matching: find.byType(Text))
          .evaluate()
          .map((element) => (element.widget as Text).data ?? '')
          .toList();
      expect(
        labels,
        containsAllInOrder([
          'Day 3 · Tokyo arrival · 10 Apr 2027',
          'Day 7 · Kyoto discovery',
        ]),
      );
      expect(labels.join(' '), isNot(contains('staged-day-')));
      expect(labels.join(' '), isNot(contains('consultant-day-')));
      expect(labels.join(' '), isNot(contains('12 Apr 2027')));
      expect(labels, isNot(contains('Consultant day')));
      expect(
        tester
            .widget<RadioGroup<SupplierExtractionStagedDay>>(
              find.byType(RadioGroup<SupplierExtractionStagedDay>),
            )
            .groupValue,
        isNull,
      );
    },
  );

  testWidgets(
    'explicitly excluded staged day is not offered, source is still visible',
    (tester) async {
      h.resolutions.value = _resolution(
        decisions: [_excludedDay('staged-day-2')],
      );
      await show(tester);
      await open(tester, 3);
      await tap(tester, 'service-action-assign');
      expect(key('service-target-staged-day-1'), findsOneWidget);
      expect(key('service-target-staged-day-2'), findsNothing);
      expect(
        inside('review-day-staged-day-2', 'Kyoto discovery'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'no eligible days exposes exclusion without inventing an assignment',
    (tester) async {
      h.resolutions.value = _resolution(
        decisions: [_excludedDay('staged-day-1'), _excludedDay('staged-day-2')],
      );
      await show(tester);
      await open(tester, 3);
      expect(key('service-action-assign'), findsNothing);
      expect(key('service-action-retain'), findsNothing);
      expect(key('service-action-exclude'), findsOneWidget);
      expect(
        find.text('No retained source days are available for assignment.'),
        findsOneWidget,
      );
      expect(h.mutations.requests, isEmpty);
    },
  );

  for (final reason in SupplierImportExclusionReason.values) {
    testWidgets(
      'exclude with ${reason.value} records exact controlled reason and optional/required note',
      (tester) async {
        applyFromRequest();
        await show(tester);
        await open(tester, 3);
        await tap(tester, 'service-action-exclude');
        expect(
          tester.widget<FilledButton>(key('save-service-decision')).onPressed,
          isNull,
        );
        await tap(tester, 'service-reason-${reason.value}');
        if (reason == SupplierImportExclusionReason.other) {
          await tap(tester, 'save-service-decision');
          expect(
            find.text('Explain why this service is being excluded.'),
            findsOneWidget,
          );
          expect(h.mutations.requests, isEmpty);
          await tester.enterText(
            key('service-exclusion-note'),
            '  Not   requested\nby consultant  ',
          );
        }
        await tap(tester, 'save-service-decision');
        final expected = _service(
          id: 'staged-service-3',
          exclude: reason,
          note: reason == SupplierImportExclusionReason.other
              ? 'Not requested by consultant'
              : null,
        );
        expect(sentDecision(), expected.toMutationMap());
        expect(
          inside('review-service-staged-service-3', 'Excluded from import'),
          findsOneWidget,
        );
        expect(inside('review-unassigned', 'Airport transfer'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'exclusion note rejects commercial content and length before submitting',
    (tester) async {
      await show(tester);
      await open(tester);
      await tap(tester, 'service-action-exclude');
      await tap(tester, 'service-reason-other');
      for (final note in ['Payment is not included', '₹ 200', 'x' * 2001]) {
        await tester.enterText(key('service-exclusion-note'), note);
        await tap(tester, 'save-service-decision');
        expect(h.mutations.requests, isEmpty);
        expect(
          find.text(
            note.length > 2000
                ? 'Use 2,000 characters or fewer.'
                : 'Use a non-commercial explanation for this exclusion.',
          ),
          findsOneWidget,
        );
      }
      expect(
        validateServiceExclusionNote(
          'x' * 2000,
          SupplierImportExclusionReason.other,
        ),
        isNull,
      );
    },
  );

  testWidgets('cancel does not mutate and next editor has no stale selection', (
    tester,
  ) async {
    await show(tester);
    await open(tester, 3);
    await tap(tester, 'service-action-assign');
    await tap(tester, 'service-target-staged-day-1');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await open(tester, 3);
    expect(
      tester.widget<FilledButton>(key('save-service-decision')).onPressed,
      isNull,
    );
    expect(h.mutations.requests, isEmpty);
  });

  for (final action in ['retain', 'assign', 'exclude']) {
    testWidgets(
      '$action preserves existing sparse field corrections without exposing editors',
      (tester) async {
        final corrected = SupplierImportServiceDecision.fromStoredMap(
          supplierImportServiceDecision(),
        );
        h.resolutions.value = _resolution(decisions: [corrected]);
        applyFromRequest();
        await show(tester);
        expect(
          inside(
            'review-service-staged-service-1',
            'Source placement retained',
          ),
          findsOneWidget,
        );
        expect(
          inside('review-service-staged-service-1', 'Accepted as extracted'),
          findsNothing,
        );
        await open(tester);
        expect(
          find.text('Existing field corrections will be kept.'),
          findsOneWidget,
        );
        await tap(tester, 'service-action-$action');
        if (action == 'assign') {
          await tap(tester, 'service-target-staged-day-2');
        }
        if (action == 'exclude') await tap(tester, 'service-reason-duplicate');
        expect(
          find.byType(TextFormField),
          action == 'exclude' ? findsOneWidget : findsNothing,
        );
        await tap(tester, 'save-service-decision');
        expect(sentDecision()['overrides'], corrected.overrides.toMap());
      },
    );
  }

  testWidgets(
    'revert removes current deterministic decision only and reloads audit history',
    (tester) async {
      h.resolutions.value = _resolution(decisions: [_service()], revision: 2);
      final old = h.resolutions.value as SupplierImportResolutionLoaded;
      final original = h.snapshots.value;
      applyFromRequest(revision: 3);
      await show(tester);
      await open(tester);
      await tap(tester, 'service-action-revert');
      await tap(tester, 'save-service-decision');
      expect(
        h.mutations.requests.single.mutation,
        isA<SupplierImportRemoveDecisionCommand>(),
      );
      expect(h.mutations.requests.single.mutation.toMap(), {
        'action': 'remove_decision',
        'decisionId': 'staged-service-1',
      });
      expect(find.text('Accepted as extracted'), findsNothing);
      expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
      expect(find.text('Review history (3)'), findsOneWidget);
      expect(old.resolution.auditEvents.length, 2);
      expect(old.resolution.decisions.length, 1);
      expect(h.snapshots.value, same(original));
      await open(tester);
      expect(key('service-action-revert'), findsNothing);
    },
  );

  testWidgets(
    'history never masquerades as a current decision for another identity',
    (tester) async {
      h.resolutions.value = _resolution(
        decisions: [
          _service(
            id: 'staged-service-3',
            exclude: SupplierImportExclusionReason.duplicate,
          ),
        ],
        revision: 4,
      );
      await show(tester);
      expect(
        inside('review-service-staged-service-1', 'Excluded from import'),
        findsNothing,
      );
      expect(
        inside('review-service-staged-service-3', 'Excluded from import'),
        findsOneWidget,
      );
      await open(tester);
      expect(key('service-action-revert'), findsNothing);
    },
  );

  testWidgets(
    'one in-flight mutation hides all actions, keeps source, and ignores rapid double tap',
    (tester) async {
      final pending = Completer<SupplierImportResolutionMutationOutcome>();
      h.mutations.onExecute = (_) => pending.future;
      await show(tester);
      final action = key('service-review-action-staged-service-1');
      await tester.ensureVisible(action);
      final onPressed = tester.widget<OutlinedButton>(action).onPressed!;
      onPressed();
      onPressed();
      await tester.pumpAndSettle();
      expect(key('service-decision-dialog'), findsOneWidget);
      await tap(tester, 'service-action-retain');
      final save = key('save-service-decision');
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));
      expect(h.mutations.requests.length, 1);
      expect(getActions(), findsNothing);
      expect(find.text('Saving decision…'), findsOneWidget);
      expect(find.text('Accepted as extracted'), findsNothing);
      expect(inside('review-day-staged-day-1', 'Hotel stay'), findsOneWidget);
      h.resolutions.value = _resolution(decisions: [_service()], revision: 2);
      pending.complete(reviewOutcome('applied'));
      await tester.pumpAndSettle();
      expect(getActions(), findsNWidgets(3));
    },
  );

  for (final outcome in ['applied', 'already_applied']) {
    testWidgets(
      '$outcome renders authoritative reload, not a locally fabricated decision',
      (tester) async {
        final reload = Completer<SupplierImportResolutionReadResult>();
        h.mutations.onExecute = (_) {
          h.resolutions.onRead = () => reload.future;
          return reviewOutcome(outcome);
        };
        await show(tester);
        await retain(tester, settle: false);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Accepted as extracted'), findsNothing);
        expect(getActions(), findsNothing);
        reload.complete(
          _resolution(
            decisions: [_service(day: 'staged-day-2', order: 3)],
            revision: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Moved to Day 7 · Kyoto discovery · 12 Apr 2027'),
          findsOneWidget,
        );
        expect(find.text('Accepted as extracted'), findsNothing);
        expect(h.resolutions.readCount, 2);
        expect(h.mutations.requests.length, 1);
      },
    );
  }

  testWidgets(
    'conflict dismisses editor, reloads latest state, requires new explicit choice',
    (tester) async {
      h.mutations.onExecute = (_) {
        h.resolutions.value = _resolution(
          decisions: [
            _service(exclude: SupplierImportExclusionReason.duplicate),
          ],
          revision: 3,
        );
        return reviewOutcome('resolution_conflict', revision: 3);
      };
      await show(tester);
      await retain(tester);
      expect(key('service-decision-dialog'), findsNothing);
      expect(find.text('Excluded from import'), findsOneWidget);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      expect(h.mutations.requests.length, 1);
      expect(getActions(), findsNWidgets(3));
      applyFromRequest(revision: 4);
      await retain(tester);
      expect(h.mutations.requests.length, 2);
      expect(h.mutations.requests.last.expectedRevision, 3);
      expect(
        h.mutations.requests.last.commandId,
        isNot(h.mutations.requests.first.commandId),
      );
      expect(find.text('Accepted as extracted'), findsOneWidget);
    },
  );

  testWidgets(
    'ambiguous save uses only page retry with identical command and revision',
    (tester) async {
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.unavailable,
      );
      await show(tester);
      await retain(tester);
      expect(getActions(), findsNothing);
      expect(find.text('Retry same request'), findsOneWidget);
      expect(
        find.text('Awaiting review confirmation. See the review notice above.'),
        findsOneWidget,
      );
      expect(find.text('Accepted as extracted'), findsNothing);
      final first = h.mutations.requests.single;
      h.mutations.error = null;
      applyFromRequest(outcome: 'already_applied');
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(h.mutations.requests.length, 2);
      expect(h.mutations.requests.last, same(first));
      expect(h.mutations.requests.last.toMap(), first.toMap());
      expect(find.text('Accepted as extracted'), findsOneWidget);
    },
  );

  for (final (kind, message) in [
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
      '$kind uses safe notice and blocks new service mutation until refreshed',
      (tester) async {
        h.mutations.error = SupplierImportMutationFailure(kind);
        await show(tester);
        await retain(tester);
        expect(find.text(message), findsOneWidget);
        expect(getActions(), findsNothing);
        expect(find.text('Accepted as extracted'), findsNothing);
        expect(find.textContaining('Firebase'), findsNothing);
        expect(key('service-decision-dialog'), findsNothing);
        await tap(tester, 'refresh-supplier-review');
        expect(getActions(), findsNWidgets(3));
        expect(h.mutations.requests.length, 1);
      },
    );
  }

  testWidgets(
    'refresh keeps source visible and suspends controls until authoritative read',
    (tester) async {
      await show(tester);
      final pending = Completer<SupplierImportResolutionReadResult>();
      h.resolutions.onRead = () => pending.future;
      await tap(tester, 'refresh-supplier-review', settle: false);
      expect(getActions(), findsNothing);
      expect(inside('review-unassigned', 'Airport transfer'), findsOneWidget);
      pending.complete(reviewResolution());
      await tester.pumpAndSettle();
      expect(getActions(), findsNWidgets(3));
      expect(h.mutations.requests, isEmpty);
    },
  );

  testWidgets(
    'failed authoritative reload does not fabricate success or unlock controls',
    (tester) async {
      h.mutations.onExecute = (_) {
        h.resolutions.error = StateError('private backend text');
        return reviewOutcome('applied');
      };
      await show(tester);
      await retain(tester);
      expect(getActions(), findsNothing);
      expect(find.text('Accepted as extracted'), findsNothing);
      expect(find.textContaining('private backend text'), findsNothing);
      expect(find.text('Retry same request'), findsNothing);
      h.resolutions.error = null;
      h.resolutions.value = _resolution(decisions: [_service()], revision: 2);
      await tap(tester, 'refresh-supplier-review');
      expect(find.text('Accepted as extracted'), findsOneWidget);
      expect(h.mutations.requests.length, 1);
    },
  );

  for (final width in [375.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
    testWidgets(
      'service, target chooser and exclusion form fit ${width.toInt()}px with reachable footer',
      (tester) async {
        await show(tester, width: width, height: 844);
        for (final service in [1, 3]) {
          await tester.ensureVisible(
            key('review-service-staged-service-$service'),
          );
          expect(tester.takeException(), isNull);
        }
        await open(tester, 3);
        await tap(tester, 'service-action-assign');
        await tap(tester, 'service-target-staged-day-2');
        expect(tester.takeException(), isNull);
        await tap(tester, 'service-action-exclude');
        await tap(tester, 'service-reason-other');
        await tester.ensureVisible(key('service-exclusion-note'));
        await tester.enterText(
          key('service-exclusion-note'),
          'Supplier service is not requested',
        );
        expect(tester.takeException(), isNull);
        final save = tester.getRect(key('save-service-decision'));
        expect(save.bottom, lessThanOrEqualTo(844));
        expect(save.left, greaterThanOrEqualTo(0));
        expect(save.right, lessThanOrEqualTo(width));
        expect(save.height, greaterThanOrEqualTo(48));
        expect(
          tester.getSize(key('service-decision-dialog')).width,
          lessThanOrEqualTo(width),
        );
        expect(h.mutations.requests, isEmpty);
      },
    );
  }

  testWidgets(
    'large text and keyboard inset keep exclusion footer reachable at 390px',
    (tester) async {
      await show(tester, width: 390, height: 844, scale: 1.5);
      await open(tester, 3);
      await tap(tester, 'service-action-exclude');
      await tap(tester, 'service-reason-other');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('service-exclusion-note'));
      await tester.enterText(key('service-exclusion-note'), 'Not requested');
      await tester.pumpAndSettle();
      expect(
        tester.getRect(key('save-service-decision')).bottom,
        lessThanOrEqualTo(544),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard selection and semantic labels retain accessible radio interaction',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester);
      await open(tester, 3);
      await tap(tester, 'service-action-assign');
      final group = find.byType(RadioGroup<SupplierExtractionStagedDay>);
      expect(
        tester
            .widget<RadioGroup<SupplierExtractionStagedDay>>(group)
            .groupValue,
        isNull,
      );
      await tester.ensureVisible(key('service-target-staged-day-1'));
      // RadioGroup uses the platform's focus/arrow-key single-selection behavior.
      await tester.tap(key('service-target-staged-day-1'));
      for (var step = 0; step < 10; step++) {
        if (FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<
                  RadioListTile<SupplierExtractionStagedDay>
                >() !=
            null) {
          break;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<
              RadioListTile<SupplierExtractionStagedDay>
            >(),
        isNotNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<SupplierExtractionStagedDay>>(group)
            .groupValue
            ?.id,
        'staged-day-2',
      );
      expect(
        find.bySemanticsLabel(RegExp('Day 7.*Kyoto discovery')),
        findsWidgets,
      );
      expect(find.bySemanticsLabel('Save decision'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'only staged-service controls exist and all other source sections remain read-only',
    (tester) async {
      await show(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(getActions(), findsNWidgets(3));
      for (final text in [
        'Package accommodation',
        'Package inclusions',
        'Flights',
        'Visa',
        'Review issues',
      ]) {
        expect(find.text(text), findsWidgets);
      }
      for (final text in [
        'Finalize',
        'Approve import',
        'Create itinerary',
        'Add day',
        'Add service',
        'Edit day',
        'Edit service',
        'Acknowledge',
      ]) {
        expect(find.text(text), findsNothing);
      }
      await open(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(h.mutations.requests, isEmpty);
    },
  );

  test(
    'presentation has no direct writes, non-service mutations, or readiness/finalization API',
    () {
      final directory = Directory(
        'lib/features/itineraries/presentation/widgets/supplier_import',
      );
      final files = directory.listSync().whereType<File>().where(
        (file) => file.path.contains('staged_service_'),
      );
      for (final file in files) {
        final source = file.readAsStringSync();
        for (final forbidden in [
          'FirebaseFirestore',
          'FirebaseFunctions',
          'canFinalize',
          'upsertManualItem(',
          'finalize(',
          'SupplierImportSetDecisionCommand(SupplierImportDayDecision',
        ]) {
          expect(source, isNot(contains(forbidden)), reason: file.path);
        }
      }
    },
  );

  testWidgets(
    'equal source titles still resolve decisions by deterministic identity',
    (tester) async {
      h.snapshots.value = _withSourceText(
        serviceTitle: 'Shared supplier title',
      );
      h.resolutions.value = _resolution(
        decisions: [
          _service(
            id: 'staged-service-3',
            exclude: SupplierImportExclusionReason.duplicate,
          ),
        ],
      );
      await show(tester);
      expect(
        inside('review-service-staged-service-1', 'Shared supplier title'),
        findsOneWidget,
      );
      expect(
        inside('review-service-staged-service-3', 'Shared supplier title'),
        findsOneWidget,
      );
      expect(
        inside('review-service-staged-service-1', 'Excluded from import'),
        findsNothing,
      );
      expect(
        inside('review-service-staged-service-3', 'Excluded from import'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'title-only day uses source position without invented dates or day numbers',
    (tester) async {
      h.snapshots.value = _withSourceText(bareDay: true);
      await show(tester);
      await open(tester, 3);
      await tap(tester, 'service-action-assign');
      expect(
        inside(
          'service-target-staged-day-2',
          'Source position 2 · Kyoto discovery',
        ),
        findsOneWidget,
      );
      expect(inside('service-target-staged-day-2', 'Day 2'), findsNothing);
      expect(h.mutations.requests, isEmpty);
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets('long source and chooser titles wrap at ${width.toInt()}px', (
      tester,
    ) async {
      h.snapshots.value = _withSourceText(
        serviceTitle:
            'A supplier service with a long descriptive title that needs to wrap within its source section and review dialog',
        dayTitle:
            'A day with a long supplier title describing the arrival and surrounding city itinerary',
      );
      await show(tester, width: width, height: 844);
      await tester.ensureVisible(key('review-service-staged-service-3'));
      expect(tester.takeException(), isNull);
      await open(tester, 3);
      await tap(tester, 'service-action-assign');
      await tap(tester, 'service-target-staged-day-2');
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(key('save-service-decision')).bottom,
        lessThanOrEqualTo(844),
      );
    });
  }

  testWidgets(
    'dialog opened in a replaced session cannot submit into the new controller',
    (tester) async {
      await show(tester);
      await open(tester);
      await tap(tester, 'service-action-retain');
      dependencies = SupplierImportReviewDependencies(
        snapshots: h.snapshots,
        resolutions: h.resolutions,
        mutations: h.mutations,
      );
      await show(tester);
      await tap(tester, 'save-service-decision');
      expect(h.mutations.requests, isEmpty);
      expect(key('service-decision-dialog'), findsNothing);
      expect(getActions(), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'append order accounts for current retained decisions, manual services and accommodation without reordering them',
    () {
      final resolution = _resolution(
        decisions: [
          _service(id: 'staged-service-1', day: 'staged-day-2', order: 5),
          SupplierImportPackageAccommodationDecision.fromStoredMap({
            ...supplierImportAccommodationDecision(),
            'disposition': 'map_to_day_service',
            'day': {'kind': 'staged_day', 'dayId': 'staged-day-2'},
            'canonicalOrder': 7,
          }),
        ],
        manual: [
          {
            ...supplierImportManualService(),
            'day': {'kind': 'staged_day', 'dayId': 'staged-day-2'},
            'canonicalOrder': 9,
          },
        ],
      );
      final snapshot = h.snapshots.value;
      final data = StagedServiceReviewData(
        SupplierImportReviewActive(snapshot, resolution.resolution),
      );
      final service = snapshot.facts
          .whereType<SupplierExtractionServiceFact>()
          .last;
      final decision = data.assign(service, snapshot.days.last);
      expect(decision.canonicalOrder, 10);
      expect(
        resolution.resolution.manualItems.single.payload
            .toMutationMap()['canonicalOrder'],
        9,
      );
      expect(snapshot.days.last.order, 2);
    },
  );

  test(
    'excluded services do not consume append order and current moved decision is not counted twice',
    () {
      final snapshot = h.snapshots.value;
      final resolution = _resolution(
        decisions: [
          _service(
            id: 'staged-service-2',
            exclude: SupplierImportExclusionReason.duplicate,
          ),
          _service(id: 'staged-service-3', day: 'staged-day-2', order: 8),
        ],
      );
      final data = StagedServiceReviewData(
        SupplierImportReviewActive(snapshot, resolution.resolution),
      );
      expect(
        data
            .assign(
              snapshot.facts.whereType<SupplierExtractionServiceFact>().last,
              snapshot.days.last,
            )
            .canonicalOrder,
        1,
      );
    },
  );
}

SupplierImportServiceDecision _service({
  String id = 'staged-service-1',
  String? day,
  int? order,
  SupplierImportExclusionReason? exclude,
  String? note,
}) => SupplierImportServiceDecision(
  targetEntityId: id,
  disposition: exclude == null
      ? SupplierImportRetainDisposition.retain
      : SupplierImportRetainDisposition.exclude,
  overrides: const SupplierImportServiceOverrides(),
  exclusionReason: exclude,
  exclusionNote: note,
  day: day == null ? null : SupplierImportStagedDayReference(day),
  canonicalOrder: order,
);

SupplierImportDayDecision _excludedDay(String id) =>
    SupplierImportDayDecision.fromStoredMap({
      ...supplierImportDayDecision(target: id),
      'disposition': 'exclude',
      'overrides': <String, Object?>{},
      'exclusionReason': 'duplicate',
      'exclusionNote': null,
    });

SupplierExtractionSnapshot _withSourceText({
  String? serviceTitle,
  String? dayTitle,
  bool bareDay = false,
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
              'title': ?dayTitle,
              if (bareDay && doc.documentId == 'staged-day-2') ...{
                'date': null,
                'sourceDayNumber': null,
              },
            },
          },
        ),
      )
      .toList(),
  factDocuments: supplierExtractionFactDocuments()
      .map(
        (doc) => (
          documentId: doc.documentId,
          data: {
            ...doc.data,
            'value': {
              ...doc.data['value']! as Map<String, Object?>,
              if (serviceTitle != null &&
                  doc.documentId.startsWith('staged-service-'))
                'title': serviceTitle,
            },
          },
        ),
      )
      .toList(),
  reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
  trustedSourceFileIds: const ['file-1'],
);

SupplierImportResolutionLoaded _resolution({
  List<SupplierImportDecisionPayload> decisions = const [],
  List<Map<String, Object?>> manual = const [],
  int revision = 1,
}) => SupplierImportResolutionLoaded(
  SupplierImportResolutionAggregate.fromStoredDocuments(
    expectedTripId: 'trip-1',
    expectedExtractionId: 'extraction-1',
    rootDocumentId: 'extraction-1',
    rootData: supplierImportResolutionRoot(revision: revision),
    decisionDocuments: [
      for (final decision in decisions)
        (
          documentId: decision.targetEntityId,
          data: {
            ...supplierImportDecisionMetadata(
              decisionId: decision.targetEntityId,
              decisionKind: decision.decisionKind,
              targetEntityId: decision.targetEntityId,
            ),
            ...decision.toMutationMap(),
          },
        ),
    ],
    manualItemDocuments: [
      for (final item in manual)
        (
          documentId:
              (item['manualDayId'] ?? item['manualServiceId'])! as String,
          data: item,
        ),
    ],
    eventDocuments: List.generate(
      revision,
      (index) => (
        documentId: 'command-${index + 1}',
        data: {
          ...supplierImportAuditEvent(previousRevision: index),
          if (index > 0) ...{
            'action': 'set_service_decision',
            'targetKind': 'service',
            'targetId': 'staged-service-1',
            'metadata': {
              'kind': 'decision',
              'disposition': 'retain',
              'changedFields': <String>[],
              'exclusionReason': null,
              'referencedIds': <String>[],
            },
          },
        },
      ),
    ),
  ),
);
