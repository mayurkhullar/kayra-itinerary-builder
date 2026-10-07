import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_fact.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_finalization.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'support/supplier_extraction_fixture.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/ancillary_decision_panel.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/snapshot_package_facts.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/staged_service_review_data.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/review_finalization_action.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/finalization_finding_label.dart';
import 'support/supplier_import_finalization_fixture.dart';
import 'support/supplier_import_review_fixture.dart';
import 'support/supplier_import_resolution_fixture.dart';

void main() {
  late FinalizationHarness h;
  final decisions = <String, SupplierImportDecisionPayload>{};
  int revision = 2;
  void reload() {
    h.resolutions.value = SupplierImportResolutionLoaded(
      SupplierImportResolutionAggregate.fromStoredDocuments(
        expectedTripId: 'trip-1',
        expectedExtractionId: 'extraction-1',
        rootDocumentId: 'extraction-1',
        rootData: supplierImportResolutionRoot(revision: revision),
        decisionDocuments: [
          for (final d in decisions.values)
            (
              documentId: d.targetEntityId,
              data: {
                ...supplierImportDecisionMetadata(
                  decisionId: d.targetEntityId,
                  decisionKind: d.decisionKind,
                  targetEntityId: d.targetEntityId,
                ),
                ...d.toMutationMap(),
                'lastRevision': revision,
              },
            ),
        ],
        manualItemDocuments: const [],
        eventDocuments: List.generate(
          revision,
          (i) => (
            documentId: 'command-${i + 1}',
            data: supplierImportAuditEvent(previousRevision: i),
          ),
        ),
      ),
    );
  }

  setUp(() {
    h = FinalizationHarness();
    decisions.clear();
    revision = 2;
    h.mutations.onExecute = (request) {
      switch (request.mutation) {
        case SupplierImportSetDecisionCommand(:final decision):
          decisions[decision.targetEntityId] = decision;
        case SupplierImportRemoveDecisionCommand(:final decisionId):
          decisions.remove(decisionId);
        default:
          fail('Unexpected ancillary mutation');
      }
      revision++;
      reload();
      return reviewOutcome('applied', revision: revision);
    };
  });
  tearDown(() => h.dispose());
  Future<void> show(
    WidgetTester tester, {
    double width = 1440,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await h.controller.load();
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
          body: AnimatedBuilder(
            animation: h.controller,
            builder: (context, _) => Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SnapshotPackageFacts(
                        snapshot: h.controller.state.loaded!.snapshot,
                        ancillaryReviewBuilder: (fact) =>
                            AncillaryDecisionPanel(
                              key: ValueKey(fact.id),
                              fact: fact,
                              review: StagedServiceReviewData(
                                h.controller.state,
                              ),
                              onSet: h.controller.setDecision,
                              onRemove: h.controller.removeDecision,
                            ),
                      ),
                    ),
                  ),
                ),
                ReviewFinalizationAction(
                  state: h.controller.state,
                  canFinalize: h.controller.canFinalizeReview,
                  canRetry: h.controller.canRetryPendingFinalization,
                  onFinalize: h.controller.finalizeReview,
                  onRetry: h.controller.retryPendingFinalization,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder panel(String kind) => find.byKey(ValueKey('ancillary-$kind-1'));
  Finder action(String kind, String label) =>
      find.descendant(of: panel(kind), matching: find.text(label));
  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  for (final kind in ['flight', 'visa']) {
    testWidgets(
      '$kind explicit handling uses exact identity/revision and one mutation',
      (tester) async {
        await show(tester);
        expect(action(kind, 'Handle separately'), findsOneWidget);
        expect(action(kind, 'Exclude'), findsOneWidget);
        expect(action(kind, 'Handled separately'), findsNothing);
        await tap(tester, action(kind, 'Handle separately'));
        final request = h.mutations.requests.single;
        expect(request.expectedRevision, 2);
        expect(request.commandId, 'intent-1');
        final payload = (request.mutation as SupplierImportSetDecisionCommand)
            .decision
            .toMutationMap();
        expect(payload, {
          'decisionKind': kind,
          'targetEntityId': 'ancillary-$kind-1',
          'disposition': 'handled_separately',
          'destinationId': null,
          'overrides': <String, Object?>{},
          'exclusionReason': null,
          'exclusionNote': null,
        });
        expect(action(kind, 'Handled separately'), findsOneWidget);
        expect(action(kind, 'Handle separately'), findsNothing);
        expect(h.finalizations.requests, isEmpty);
        expect(h.snapshots.readCount, 1);
        expect(find.text('Finalize itinerary'), findsOneWidget);
      },
    );
    testWidgets('$kind change and revert use single existing commands', (
      tester,
    ) async {
      await show(tester);
      await tap(tester, action(kind, 'Handle separately'));
      await tap(tester, action(kind, 'Change'));
      await tap(tester, action(kind, 'Exclude'));
      await tap(
        tester,
        find.descendant(
          of: panel(kind),
          matching: find.byKey(ValueKey('ancillary-reason-ancillary-$kind-1')),
        ),
      );
      await tester.tap(find.text('Duplicate').last);
      await tester.pumpAndSettle();
      await tap(tester, action(kind, 'Save exclusion'));
      expect(h.mutations.requests, hasLength(2));
      expect(action(kind, 'Excluded from itinerary import'), findsOneWidget);
      await tap(tester, action(kind, 'Revert decision'));
      expect(h.mutations.requests, hasLength(3));
      expect(
        h.mutations.requests.last.mutation,
        isA<SupplierImportRemoveDecisionCommand>(),
      );
      expect(action(kind, 'Handle separately'), findsOneWidget);
      expect(h.finalizations.requests, isEmpty);
    });
    testWidgets('$kind failure keeps prior authoritative decision', (
      tester,
    ) async {
      await show(tester);
      await tap(tester, action(kind, 'Handle separately'));
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.permissionDenied,
      );
      await tap(tester, action(kind, 'Revert decision'));
      expect(action(kind, 'Handled separately'), findsOneWidget);
      expect(action(kind, 'Handle separately'), findsNothing);
    });
    testWidgets('$kind conflict reloads without auto retry', (tester) async {
      h.mutations.onExecute = (_) =>
          reviewOutcome('resolution_conflict', revision: 2);
      await show(tester);
      await tap(tester, action(kind, 'Handle separately'));
      expect(action(kind, 'Handled separately'), findsNothing);
      expect(h.mutations.requests, hasLength(1));
      expect(h.resolutions.readCount, 2);
    });
  }
  testWidgets('mutation in flight locks all ancillary actions', (tester) async {
    final pending = Completer<SupplierImportResolutionMutationOutcome>();
    h.mutations.onExecute = (_) => pending.future;
    await show(tester);
    final button = action('flight', 'Handle separately');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Handle separately'), findsNothing);
    expect(find.text('Saving review…'), findsNWidgets(2));
    expect(find.text('Finalize itinerary'), findsNothing);
    expect(h.mutations.requests, hasLength(1));
    pending.complete(reviewOutcome('resolution_conflict', revision: 2));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'successful decision clears stale blockers without auto finalizing',
    (tester) async {
      h.finalizations.outcome = finalizationOutcome('not_ready');
      await show(tester);
      await tester.tap(find.text('Finalize itinerary'));
      await tester.pumpAndSettle();
      expect(find.text('1 item needs attention'), findsOneWidget);
      await tap(tester, action('flight', 'Handle separately'));
      expect(find.text('1 item needs attention'), findsNothing);
      expect(h.finalizations.requests, hasLength(1));
    },
  );
  testWidgets('finalized is read only', (tester) async {
    h.seal();
    await show(tester);
    expect(find.text('Handle separately'), findsNothing);
    expect(find.text('Exclude'), findsNothing);
    expect(find.text('Change'), findsNothing);
    expect(find.text('Revert decision'), findsNothing);
  });
  testWidgets('source facts remain visible with no raw identities', (
    tester,
  ) async {
    await show(tester);
    for (final text in [
      'Example Air · EA 101',
      'DEL',
      'NRT',
      '22:15',
      '08:30',
      'Visa required before travel.',
    ]) {
      expect(find.text(text), findsWidgets);
    }
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    for (final secret in [
      'ancillary-flight-1',
      'ancillary-visa-1',
      'package-1',
      'file-1',
      'agent-1',
      'route_to_',
      'handled_separately',
    ]) {
      expect(texts, isNot(contains(secret)));
    }
    expect(find.byType(Checkbox), findsNothing);
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
    testWidgets('ancillary actions and exclusion fit $width with large text', (
      tester,
    ) async {
      await show(tester, width: width, scale: 2);
      await tap(tester, action('flight', 'Exclude'));
      expect(tester.takeException(), isNull);
      await tap(tester, action('flight', 'Save exclusion'));
      expect(find.text('Choose a reason.'), findsOneWidget);
      expect(h.mutations.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  SupplierExtractionSnapshot snapshotWith(List<Map<String, Object?>> facts) =>
      SupplierExtractionSnapshot.fromStoredDocuments(
        expectedTripId: 'trip-1',
        expectedExtractionId: 'extraction-1',
        root: supplierExtractionRoot(
          counts: supplierExtractionCounts(
            days: 0,
            assignedServices: 0,
            unassignedServices: 0,
            packageFacts: 0,
            ancillaryFlights: facts
                .where((f) => f['factKind'] == 'flight')
                .length,
            ancillaryVisas: facts.where((f) => f['factKind'] == 'visa').length,
            commercialIndicators: 0,
            reviewIssues: 0,
          ),
        ),
        dayDocuments: const [],
        factDocuments: [
          for (var i = 0; i < facts.length; i++)
            supplierExtractionChild(facts[i], i + 1),
        ],
        reviewIssueDocuments: const [],
        trustedSourceFileIds: const ['file-1'],
      );
  testWidgets('no ancillary facts means no ancillary controls or section', (
    tester,
  ) async {
    h.snapshots.value = snapshotWith([]);
    await show(tester);
    expect(find.byType(AncillaryDecisionPanel), findsNothing);
    expect(find.text('Flights'), findsNothing);
    expect(find.text('Visa'), findsNothing);
  });
  testWidgets('missing optional fields create no labels or invented facts', (
    tester,
  ) async {
    final flight = supplierExtractionFlight();
    for (final field in [
      'flightNumber',
      'origin',
      'destination',
      'departureDate',
      'departureTime',
      'arrivalDate',
      'arrivalTime',
      'cabinClass',
      'bookingClass',
      'notes',
    ]) {
      flight[field] = null;
    }
    flight['conditions'] = <Object>[];
    h.snapshots.value = snapshotWith([
      flight,
      {...supplierExtractionVisa(), 'disposition': 'mentioned', 'text': null},
    ]);
    await show(tester);
    for (final label in [
      'From',
      'To',
      'Departure date',
      'Departure time',
      'Arrival date',
      'Arrival time',
      'Flight notes',
      'Country',
      'Not provided',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('Example Air'), findsOneWidget);
  });
  testWidgets('exclusion Other requires explanation and sends one decision', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, action('visa', 'Exclude'));
    await tap(
      tester,
      find.byKey(const ValueKey('ancillary-reason-ancillary-visa-1')),
    );
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    await tap(tester, action('visa', 'Save exclusion'));
    expect(h.mutations.requests, isEmpty);
    expect(
      find.text('Explain why this item is being excluded.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'Outside this itinerary scope',
    );
    await tap(tester, action('visa', 'Save exclusion'));
    final d =
        (h.mutations.requests.single.mutation
                    as SupplierImportSetDecisionCommand)
                .decision
            as SupplierImportVisaDecision;
    expect(d.exclusionReason, SupplierImportExclusionReason.other);
    expect(d.exclusionNote, 'Outside this itinerary scope');
  });
  testWidgets('keyboard activates a normal ancillary button', (tester) async {
    await show(tester);
    final button = action('flight', 'Handle separately');
    await tester.ensureVisible(button);
    Focus.of(tester.element(button)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(h.mutations.requests, hasLength(1));
  });
  testWidgets(
    'replacement preserves existing corrections and clears workflow link',
    (tester) async {
      decisions['ancillary-flight-1'] = const SupplierImportFlightDecision(
        targetEntityId: 'ancillary-flight-1',
        disposition: SupplierImportFlightDisposition.routeToFlightWorkflow,
        destinationId: 'private-workflow',
        overrides: SupplierImportFlightOverrides(
          notes: SupplierImportSetOverride('Existing correction'),
        ),
        exclusionReason: null,
        exclusionNote: null,
      );
      reload();
      await show(tester);
      expect(find.text('Routed to flight workflow'), findsOneWidget);
      expect(find.text('private-workflow'), findsNothing);
      await tap(tester, action('flight', 'Change'));
      await tap(tester, action('flight', 'Handle separately'));
      final d =
          (h.mutations.requests.single.mutation
                      as SupplierImportSetDecisionCommand)
                  .decision
              as SupplierImportFlightDecision;
      expect(d.overrides.notes, isA<SupplierImportSetOverride<String>>());
      expect(
        (d.overrides.notes as SupplierImportSetOverride<String>).value,
        'Existing correction',
      );
      expect(d.destinationId, isNull);
    },
  );
  for (final kind in ['flight', 'visa']) {
    testWidgets(
      '$kind finalization blocker identifies its item and clears after decision',
      (tester) async {
        final response = finalizationResponse('not_ready');
        (response['assessment'] as Map)['blockers'] = [
          {
            'code': 'unresolved_ancillary_fact',
            'targetKind': 'ancillary_fact',
            'targetId': 'ancillary-$kind-1',
          },
        ];
        h.finalizations.outcome = SupplierImportFinalizationOutcome.fromMap(
          response,
        );
        await show(tester);
        await tester.tap(find.text('Finalize itinerary'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            kind == 'flight'
                ? 'Flight needs a decision:'
                : 'Visa needs a decision:',
          ),
          findsOneWidget,
        );
        expect(find.text('unresolved_ancillary_fact'), findsNothing);
        await tap(tester, action(kind, 'Handle separately'));
        expect(find.text('1 item needs attention'), findsNothing);
        expect(h.finalizations.requests, hasLength(1));
      },
    );
  }
  test('flight and visa blocker labels identify trusted facts', () {
    final facts = h.snapshots.value.facts;
    expect(
      ancillaryFindingLabel(
        facts.whereType<SupplierExtractionFlightFact>().first,
      ),
      contains('EA 101'),
    );
    expect(
      ancillaryFindingLabel(
        facts.whereType<SupplierExtractionVisaFact>().first,
      ),
      contains('Visa required before travel.'),
    );
  });
  test('ancillary presentation uses no transports or canonical mappings', () {
    final source = File(
      'lib/features/itineraries/presentation/widgets/supplier_import/ancillary_decision_panel.dart',
    ).readAsStringSync();
    for (final forbidden in [
      'FirebaseFirestore',
      'FirebaseFunctions',
      'httpsCallable',
      'Gemini',
      'Timer.periodic',
      'SupplierImportServiceDecision',
      'SupplierImportPackageStatementDecision',
      'finalizeReview',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });
}
