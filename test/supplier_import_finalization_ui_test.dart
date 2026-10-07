import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_finalization_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_finalization.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/finalization_finding_label.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/review_finalization_action.dart';

import 'support/supplier_import_finalization_fixture.dart';
import 'support/supplier_import_review_fixture.dart';

void main() {
  late FinalizationHarness h;
  setUp(() => h = FinalizationHarness());
  tearDown(() => h.dispose());
  Future<void> show(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
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
            onBack: () {},
            dependencies: SupplierImportReviewDependencies(
              snapshots: h.snapshots,
              resolutions: h.resolutions,
              mutations: h.mutations,
              finalizations: h.finalizations,
              drafts: h.drafts,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finalize(WidgetTester tester) async {
    await tester.tap(find.text('Finalize itinerary'));
    await tester.pumpAndSettle();
  }

  void expectNoPrivateDetails(WidgetTester tester) {
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    for (final value in [
      'draft-1',
      'extraction-1',
      'intent-1',
      'digest',
      'fingerprint',
      'receipt',
      'gs://',
      'PERMISSION_DENIED',
    ]) {
      expect(text, isNot(contains(value)));
    }
  }

  testWidgets('one persistent action, no preflight, one call and no modal', (
    tester,
  ) async {
    h.finalizations.outcome = finalizationOutcome('not_ready');
    await show(tester);
    expect(find.text('Finalize itinerary'), findsOneWidget);
    expect(h.finalizations.requests, isEmpty);
    expect(h.calls.where((c) => c.startsWith('draft:')), isEmpty);
    final before = List<String>.of(h.calls);
    await finalize(tester);
    expect(h.finalizations.requests, hasLength(1));
    expect(h.calls.skip(before.length).first, 'finalize');
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('1 item needs attention'), findsOneWidget);
    expect(find.text('A service needs a day assignment.'), findsOneWidget);
    expect(find.text('Also worth checking'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('unresolved_unassigned_service'), findsNothing);
    expect(find.text('staged-service-1'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(h.finalizations.requests, hasLength(1));
  });

  testWidgets('not started uses existing start action without finalize', (
    tester,
  ) async {
    h.resolutions.value = const SupplierImportResolutionNotStarted();
    await show(tester);
    expect(find.text('Finalize itinerary'), findsNothing);
    expect(find.text('Start review'), findsOneWidget);
    expect(h.finalizations.requests, isEmpty);
  });

  testWidgets(
    'in flight preserves content, disables refresh and duplicate call',
    (tester) async {
      final pending = Completer<SupplierImportFinalizationOutcome>();
      h.finalizations.onExecute = (_) => pending.future;
      await show(tester);
      await tester.tap(find.text('Finalize itinerary'));
      await tester.pump();
      expect(find.text('Finalizing…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('review-snapshot-title')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('finalize-itinerary')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('refresh-supplier-review')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Finalizing…'));
      expect(h.finalizations.requests, hasLength(1));
      pending.complete(finalizationOutcome('not_ready'));
      await tester.pumpAndSettle();
    },
  );

  for (final outcome in [
    'applied',
    'already_applied',
    'resolution_finalized',
  ]) {
    testWidgets('$outcome shows locked success without IDs', (tester) async {
      h.finalizations.onExecute = (request) {
        h.seal();
        h.drafts.value = finalizationDraft(commandId: request.commandId);
        return finalizationOutcome(outcome);
      };
      await show(tester);
      await finalize(tester);
      expect(find.text('Itinerary finalized'), findsOneWidget);
      expect(find.text('Finalize itinerary'), findsNothing);
      expect(find.text('Review day'), findsNothing);
      expect(find.text('Review service'), findsNothing);
      expect(find.text('Reopen'), findsNothing);
      expectNoPrivateDetails(tester);
      expect(h.finalizations.requests, hasLength(1));
    });
  }

  testWidgets('initial finalized state has no finalization action', (
    tester,
  ) async {
    h.seal();
    await show(tester);
    expect(find.text('Itinerary finalized'), findsOneWidget);
    expect(find.text('Finalize itinerary'), findsNothing);
  });

  testWidgets('ambiguous retry reuses exact request without new action', (
    tester,
  ) async {
    h.finalizations.error = const SupplierImportFinalizationFailure(
      SupplierImportFinalizationFailureKind.unavailable,
    );
    await show(tester);
    await finalize(tester);
    expect(find.text('Retry finalization'), findsOneWidget);
    expect(find.text('Finalize itinerary'), findsNothing);
    final original = h.finalizations.requests.single;
    await tester.pump(const Duration(seconds: 5));
    expect(h.finalizations.requests, hasLength(1));
    h.finalizations.error = null;
    h.finalizations.outcome = finalizationOutcome('not_ready');
    await tester.tap(find.text('Retry finalization'));
    await tester.pumpAndSettle();
    expect(h.finalizations.requests, hasLength(2));
    expect(identical(h.finalizations.requests.last, original), isTrue);
  });

  testWidgets('conflict is explicit and never auto retries', (tester) async {
    h.finalizations.outcome = finalizationOutcome('resolution_conflict');
    await show(tester);
    await finalize(tester);
    expect(
      find.text(
        'The review changed before finalization. Check the updated items and finalize again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Finalize itinerary'), findsOneWidget);
    expect(h.finalizations.requests, hasLength(1));
  });

  testWidgets('capacity has safe copy and no repeated finalize', (
    tester,
  ) async {
    h.finalizations.outcome = finalizationOutcome(
      'persistence_capacity_exceeded',
    );
    await show(tester);
    await finalize(tester);
    expect(
      find.text('This itinerary is too large to finalize safely.'),
      findsOneWidget,
    );
    expect(find.text('Finalize itinerary'), findsNothing);
    expectNoPrivateDetails(tester);
  });

  testWidgets('definitive error uses sanitized copy and existing refresh', (
    tester,
  ) async {
    h.finalizations.error = const SupplierImportFinalizationFailure(
      SupplierImportFinalizationFailureKind.permissionDenied,
    );
    await show(tester);
    await finalize(tester);
    expect(
      find.text('You do not have access to this Supplier Import review.'),
      findsOneWidget,
    );
    expect(find.text('Retry finalization'), findsNothing);
    expectNoPrivateDetails(tester);
  });

  testWidgets('refresh to new revision hides stale not-ready findings', (
    tester,
  ) async {
    h.finalizations.outcome = finalizationOutcome('not_ready');
    await show(tester);
    await finalize(tester);
    h.resolutions.value = reviewResolution(revision: 3);
    await tester.tap(find.byKey(const ValueKey('refresh-supplier-review')));
    await tester.pumpAndSettle();
    expect(find.text('1 item needs attention'), findsNothing);
    expect(find.text('Finalize itinerary'), findsOneWidget);
    expect(h.finalizations.requests, hasLength(1));
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
      testWidgets('footer and findings fit $width at scale $scale', (
        tester,
      ) async {
        h.finalizations.outcome = finalizationOutcome('not_ready');
        await show(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        await finalize(tester);
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(
          find.byKey(const ValueKey('finalize-itinerary')),
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(rect.bottom, lessThanOrEqualTo(900));
        expect(find.byType(ReviewFinalizationAction), findsOneWidget);
      });
    }
  }
  Future<void> controllerFooter(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: h.controller,
            builder: (context, _) => Align(
              alignment: Alignment.bottomCenter,
              child: ReviewFinalizationAction(
                state: h.controller.state,
                canFinalize: h.controller.canFinalizeReview,
                canRetry: h.controller.canRetryPendingFinalization,
                onFinalize: h.controller.finalizeReview,
                onRetry: h.controller.retryPendingFinalization,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'successful mutation clears findings and in-flight mutation locks finalize',
    (tester) async {
      await h.controller.load();
      h.finalizations.outcome = finalizationOutcome('not_ready');
      await h.controller.finalizeReview();
      await controllerFooter(tester);
      expect(find.text('1 item needs attention'), findsOneWidget);
      final pending = Completer<SupplierImportResolutionMutationOutcome>();
      h.mutations.onExecute = (_) => pending.future;
      final operation = h.controller.setDecision(reviewTitleDecision);
      await tester.pump();
      expect(find.text('Finalize itinerary'), findsNothing);
      expect(find.text('1 item needs attention'), findsNothing);
      expect(h.controller.canFinalizeReview, isFalse);
      h.resolutions.value = reviewResolution(revision: 3);
      pending.complete(reviewOutcome('applied', revision: 3));
      await operation;
      await tester.pumpAndSettle();
      expect(find.text('1 item needs attention'), findsNothing);
      expect(find.text('Finalize itinerary'), findsOneWidget);
      expect(h.finalizations.requests, hasLength(1));
    },
  );

  testWidgets('normal keyboard activation invokes finalization once', (
    tester,
  ) async {
    await h.controller.load();
    h.finalizations.outcome = finalizationOutcome('not_ready');
    await controllerFooter(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(h.finalizations.requests, hasLength(1));
  });

  testWidgets('not-ready preserves unrelated expansion state', (tester) async {
    h.finalizations.outcome = finalizationOutcome('not_ready');
    await show(tester);
    final tiles = tester
        .widgetList<ExpansionTile>(find.byType(ExpansionTile))
        .map((tile) => tile.initiallyExpanded)
        .toList();
    await finalize(tester);
    expect(
      tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .map((tile) => tile.initiallyExpanded)
          .toList(),
      tiles,
    );
    expect(find.byType(Dialog), findsNothing);
  });

  test('disposed lifecycle never permits a new attempt or retry', () async {
    await h.controller.load();
    expect(h.controller.canFinalizeReview, isTrue);
    h.dispose();
    expect(h.controller.canFinalizeReview, isFalse);
    expect(h.controller.canRetryPendingFinalization, isFalse);
  });

  test(
    'unknown labels remain safe and every known finding has a human label',
    () {
      expect(
        finalizationFindingLabel('future_code gs://private'),
        'This item needs review before finalizing.',
      );
      for (final code in SupplierImportFinalizationBlockerCode.values) {
        expect(
          finalizationFindingLabel(code.value),
          isNot(contains(code.value)),
        );
        expect(
          finalizationFindingLabel(code.value),
          isNot('This item needs review before finalizing.'),
        );
      }
    },
  );
  test('presentation contains no transport, readiness or new resolution forms', () {
    for (final path in [
      'lib/features/itineraries/presentation/widgets/supplier_import/review_finalization_action.dart',
      'lib/features/itineraries/presentation/widgets/supplier_import/finalization_finding_label.dart',
      'lib/features/itineraries/presentation/pages/supplier_import_review_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final token in [
        'FirebaseFunctions',
        'FirebaseFirestore',
        'httpsCallable',
        'Timer.periodic',
        'assessSupplierImport',
        'TextFormField',
      ]) {
        expect(source, isNot(contains(token)));
      }
    }
  });
}
