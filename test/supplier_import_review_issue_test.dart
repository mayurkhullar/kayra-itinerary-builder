import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_finalization.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/review_issue_action.dart';
import 'support/supplier_import_finalization_fixture.dart';
import 'support/supplier_import_review_fixture.dart';

void main() {
  late FinalizationHarness h;
  setUp(() => h = FinalizationHarness());
  tearDown(() => h.dispose());
  SupplierImportFinalizationOutcome assessment({
    bool eligible = true,
    int revision = 2,
  }) {
    final data = finalizationResponse('not_ready', revision: revision + 1);
    final a = data['assessment'] as Map<String, Object?>;
    a['blockers'] = [
      {
        'code': 'unresolved_review_issue',
        'targetKind': 'review_issue',
        'targetId': 'review-1',
      },
    ];
    a['warnings'] = [
      if (eligible)
        {
          'code': 'review_issue_override_available',
          'targetKind': 'review_issue',
          'targetId': 'review-1',
        },
    ];
    return SupplierImportFinalizationOutcome.fromMap(data);
  }

  Future<void> show(
    WidgetTester t, {
    double width = 1440,
    double scale = 1,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 1000);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
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
    await t.pumpAndSettle();
  }

  Future<void> finalize(WidgetTester t) async {
    await t.tap(find.text('Finalize itinerary'));
    await t.pumpAndSettle();
  }

  final action = find.byKey(const ValueKey('override-review-issue-review-1'));
  final ordinaryDecisions = <String, SupplierImportDecisionPayload>{
    'date correction': const SupplierImportDayDecision(
      targetEntityId: 'day-1',
      disposition: SupplierImportRetainDisposition.retain,
      overrides: SupplierImportDayOverrides(
        date: SupplierImportClearOverride<String>(),
      ),
      exclusionReason: null,
      exclusionNote: null,
    ),
    'service assignment': const SupplierImportServiceDecision(
      targetEntityId: 'service-1',
      disposition: SupplierImportRetainDisposition.retain,
      day: SupplierImportStagedDayReference('day-1'),
      canonicalOrder: 1,
      overrides: SupplierImportServiceOverrides(),
      exclusionReason: null,
      exclusionNote: null,
    ),
    'package retention': const SupplierImportPackageAccommodationDecision(
      targetEntityId: 'package-fact-1',
      disposition: SupplierImportAccommodationDisposition.retainPackageLevel,
      day: null,
      canonicalOrder: null,
      overrides: SupplierImportHotelOverrides(),
      exclusionReason: null,
      exclusionNote: null,
    ),
    'ancillary disposition': const SupplierImportVisaDecision(
      targetEntityId: 'visa-1',
      disposition: SupplierImportVisaDecisionDisposition.handledSeparately,
      destinationId: null,
      overrides: SupplierImportVisaOverrides(),
      exclusionReason: null,
      exclusionNote: null,
    ),
  };
  for (final entry in ordinaryDecisions.entries) {
    testWidgets('${entry.key} reload needs no second review mutation', (
      t,
    ) async {
      await h.controller.load();
      h.finalizations.outcome = assessment();
      await h.controller.finalizeReview();
      await t.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: h.controller,
            builder: (_, _) => ReviewIssueAction(
              issueId: 'review-1',
              state: h.controller.state,
              onOverride: (_) => fail('Unexpected second action'),
            ),
          ),
        ),
      );
      expect(action, findsOneWidget);
      h.resolutions.value = reviewResolution(revision: 3);
      h.mutations.outcome = reviewOutcome('applied', revision: 3);
      await h.controller.setDecision(entry.value);
      await t.pumpAndSettle();
      expect(action, findsNothing);
      expect(h.mutations.requests, hasLength(1));
      expect(
        h.mutations.requests.single.toMap().toString(),
        isNot(contains('review_issue')),
      );
      expect(h.finalizations.requests, hasLength(1));
      // Backend reports another outstanding item, but no longer this issue.
      final response = finalizationResponse('not_ready', revision: 4);
      (response['assessment'] as Map<String, Object?>)['warnings'] = <Object>[];
      h.finalizations.outcome = SupplierImportFinalizationOutcome.fromMap(
        response,
      );
      await h.controller.finalizeReview();
      await t.pumpAndSettle();
      expect(action, findsNothing);
      expect(h.mutations.requests, hasLength(1));
    });
  }
  testWidgets(
    'no override or acknowledgement without fresh backend eligibility',
    (t) async {
      await show(t);
      expect(action, findsNothing);
      expect(h.finalizations.requests, isEmpty);
      h.finalizations.outcome = assessment(eligible: false);
      await finalize(t);
      expect(action, findsNothing);
      expect(find.text('Mark resolved'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    },
  );
  testWidgets(
    'one override mutation, no modal, no automatic finalization and stale finding cleared',
    (t) async {
      h.finalizations.outcome = assessment();
      await show(t);
      await finalize(t);
      await t.ensureVisible(action);
      await t.tap(action);
      await t.pumpAndSettle();
      expect(h.mutations.requests, hasLength(1));
      expect(h.finalizations.requests, hasLength(1));
      expect(find.byType(Dialog), findsNothing);
      expect(action, findsNothing);
      final payload = h.mutations.requests.single.toMap().toString();
      expect(payload, contains('set_decision'));
      expect(payload, contains('overridden'));
      expect(
        payload,
        contains('Use reviewed itinerary without changing supplier facts.'),
      );
      expect(find.text('Finalize itinerary'), findsOneWidget);
    },
  );
  testWidgets('in-flight override cannot be sent twice', (t) async {
    final pending = Completer<SupplierImportResolutionMutationOutcome>();
    h.mutations.onExecute = (_) => pending.future;
    h.finalizations.outcome = assessment();
    await show(t);
    await finalize(t);
    await t.ensureVisible(action);
    await t.tap(action);
    await t.pump();
    expect(action, findsNothing);
    expect(h.mutations.requests, hasLength(1));
    pending.complete(reviewOutcome('applied', revision: 3));
    h.resolutions.value = reviewResolution(revision: 3);
    await t.pumpAndSettle();
    expect(action, findsNothing);
    expect(h.finalizations.requests, hasLength(1));
  });
  testWidgets('conflict reload does not reuse eligibility or auto-finalize', (
    t,
  ) async {
    h.mutations.outcome = reviewOutcome('resolution_conflict', revision: 3);
    h.finalizations.outcome = assessment();
    await show(t);
    await finalize(t);
    h.resolutions.value = reviewResolution(revision: 3);
    await t.ensureVisible(action);
    await t.tap(action);
    await t.pumpAndSettle();
    expect(action, findsNothing);
    expect(h.finalizations.requests, hasLength(1));
  });
  testWidgets('finalized review has no override or second finalization', (
    t,
  ) async {
    h.seal();
    h.drafts.value = finalizationDraft();
    await show(t);
    expect(action, findsNothing);
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
    testWidgets('eligible issue fits $width', (t) async {
      h.finalizations.outcome = assessment();
      await show(t, width: width);
      await finalize(t);
      await t.ensureVisible(action);
      await t.pumpAndSettle();
      expect(action, findsOneWidget);
      expect(t.takeException(), isNull);
      expect(find.text('review_issue_override_available'), findsNothing);
    });
  }
  testWidgets('eligible issue fits large text', (t) async {
    h.finalizations.outcome = assessment();
    await show(t, width: 390, scale: 2);
    await finalize(t);
    await t.ensureVisible(action);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  test(
    'issue widget has no direct persistence, callable or policy dependency',
    () {
      final source = File(
        'lib/features/itineraries/presentation/widgets/supplier_import/review_issue_action.dart',
      ).readAsStringSync();
      for (final token in [
        'cloud_firestore',
        'cloud_functions',
        'FirebaseFirestore',
        'FirebaseFunctions',
        'chronology_unknown',
      ]) {
        expect(source, isNot(contains(token)));
      }
    },
  );
}
