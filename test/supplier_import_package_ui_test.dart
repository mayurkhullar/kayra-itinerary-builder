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
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/package_exception_panel.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/package_review_data.dart';
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
                        packageReviewBuilder: (fact) => PackageExceptionPanel(
                          key: ValueKey(fact.id),
                          data: PackageReviewData(
                            StagedServiceReviewData(h.controller.state),
                            fact,
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

  Finder panel(String kind) => find.byKey(ValueKey('package-fact-$kind'));
  Finder action(String kind, String label) =>
      find.descendant(of: panel(kind), matching: find.text(label));
  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> block(WidgetTester tester, String number) async {
    final response = finalizationResponse('not_ready');
    (response['assessment'] as Map)['blockers'] = [
      {
        'code': 'unsupported_package_mapping',
        'targetKind': 'package_fact',
        'targetId': 'package-fact-$number',
      },
    ];
    h.finalizations.outcome = SupplierImportFinalizationOutcome.fromMap(
      response,
    );
    await tester.tap(find.text('Finalize itinerary'));
    await tester.pumpAndSettle();
  }

  for (final number in ['1', '2', '3', '4']) {
    final label = number == '1'
        ? 'Keep as package stay'
        : 'Keep at package level';
    testWidgets('package $number untouched has no approval/control', (
      tester,
    ) async {
      await show(tester);
      expect(
        find.descendant(
          of: panel(number),
          matching: find.byType(ButtonStyleButton),
        ),
        findsNothing,
      );
      expect(find.text('Kept as package content'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(h.mutations.requests, isEmpty);
    });
    testWidgets(
      'package $number blocker explicitly retains with exact revision/identity',
      (tester) async {
        await show(tester);
        await block(tester, number);
        expect(action(number, 'Needs attention'), findsOneWidget);
        await tap(tester, action(number, label));
        final r = h.mutations.requests.single;
        final d = (r.mutation as SupplierImportSetDecisionCommand).decision;
        expect(r.expectedRevision, 2);
        expect(r.commandId, 'intent-2');
        expect(d.targetEntityId, 'package-fact-$number');
        expect(d.toMutationMap()['disposition'], 'retain_package_level');
        expect(d.toMutationMap()['overrides'], isEmpty);
        expect(action(number, 'Kept as package content'), findsOneWidget);
        expect(find.text('1 item needs attention'), findsNothing);
        expect(h.finalizations.requests, hasLength(1));
        expect(h.snapshots.readCount, 1);
      },
    );
    testWidgets('package $number excludes with controlled reason and reverts', (
      tester,
    ) async {
      await show(tester);
      await block(tester, number);
      await tap(tester, action(number, 'Exclude'));
      await tap(tester, find.byKey(const ValueKey('package-exclusion-reason')));
      await tester.tap(find.text('Duplicate').last);
      await tester.pumpAndSettle();
      await tap(tester, action(number, 'Save exclusion'));
      expect(action(number, 'Excluded from import'), findsOneWidget);
      expect(
        (h.mutations.requests.single.mutation
                as SupplierImportSetDecisionCommand)
            .decision
            .toMutationMap()['exclusionReason'],
        'duplicate',
      );
      await tap(tester, action(number, 'Revert decision'));
      expect(
        h.mutations.requests.last.mutation,
        isA<SupplierImportRemoveDecisionCommand>(),
      );
      expect(h.mutations.requests.last.expectedRevision, 3);
      expect(action(number, label), findsNothing);
    });
    testWidgets('package $number failed mutation preserves explicit decision', (
      tester,
    ) async {
      await show(tester);
      await block(tester, number);
      await tap(tester, action(number, label));
      h.mutations.error = const SupplierImportMutationFailure(
        SupplierImportMutationFailureKind.permissionDenied,
      );
      await tap(tester, action(number, 'Revert decision'));
      expect(action(number, 'Kept as package content'), findsOneWidget);
      expect(action(number, 'Change'), findsNothing);
    });
  }
  testWidgets('accommodation mapping requires explicit day and order', (
    tester,
  ) async {
    await show(tester);
    await block(tester, '1');
    await tap(tester, action('1', 'Map to day'));
    await tap(tester, action('1', 'Save mapping'));
    expect(h.mutations.requests, isEmpty);
    await tap(tester, find.byKey(const ValueKey('package-map-day')));
    final option = h.snapshots.value.days.first.title!;
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('package-map-order')),
      '3',
    );
    await tap(tester, action('1', 'Save mapping'));
    final d =
        (h.mutations.requests.single.mutation
                    as SupplierImportSetDecisionCommand)
                .decision
            as SupplierImportPackageAccommodationDecision;
    expect(d.day!.toMap(), {'kind': 'staged_day', 'dayId': 'staged-day-1'});
    expect(d.canonicalOrder, 3);
    expect(d.overrides.toMap(), isEmpty);
    expect(action('1', 'Mapped'), findsOneWidget);
  });
  for (final number in ['2', '3']) {
    testWidgets(
      'statement $number mapping preserves polarity with one request',
      (tester) async {
        await show(tester);
        await block(tester, number);
        await tap(tester, action(number, 'Map to service'));
        await tap(
          tester,
          find.byKey(const ValueKey('package-map-destination')),
        );
        await tester.tap(
          find
              .text(number == '2' ? 'Service inclusion' : 'Service exclusion')
              .last,
        );
        await tester.pumpAndSettle();
        final destination = number == '2'
            ? SupplierImportPackageDestination.serviceInclusion
            : SupplierImportPackageDestination.serviceExclusion;
        await tap(
          tester,
          find.byKey(ValueKey('package-map-service-${destination.value}')),
        );
        await tester.tap(find.text('Kyoto city tour').last);
        await tester.pumpAndSettle();
        await tap(tester, action(number, 'Save mapping'));
        final d =
            (h.mutations.requests.single.mutation
                        as SupplierImportSetDecisionCommand)
                    .decision
                as SupplierImportPackageStatementDecision;
        expect(d.destination, destination);
        expect(d.service!.toMap(), {
          'kind': 'staged_service',
          'serviceId': 'staged-service-2',
        });
        expect(h.finalizations.requests, hasLength(1));
      },
    );
  }
  testWidgets('mutation in flight locks package and finalize controls', (
    tester,
  ) async {
    final pending = Completer<SupplierImportResolutionMutationOutcome>();
    h.mutations.onExecute = (_) => pending.future;
    await show(tester);
    await block(tester, '2');
    final b = action('2', 'Keep at package level');
    await tester.ensureVisible(b);
    await tester.tap(b);
    await tester.pump();
    expect(find.text('Saving review…'), findsOneWidget);
    expect(find.text('Finalize itinerary'), findsNothing);
    expect(action('2', 'Keep at package level'), findsNothing);
    pending.complete(reviewOutcome('resolution_conflict', revision: 2));
    await tester.pumpAndSettle();
    expect(h.mutations.requests, hasLength(1));
    expect(h.resolutions.readCount, 3);
  });
  testWidgets('finalized package content remains readable without controls', (
    tester,
  ) async {
    h.seal();
    await show(tester);
    expect(find.text('Three dinners'), findsOneWidget);
    expect(find.text('Keep at package level'), findsNothing);
    expect(find.text('Map to day'), findsNothing);
  });
  testWidgets('source dates absent and or-similar do not require decisions', (
    tester,
  ) async {
    await show(tester);
    final source = h.snapshots.value.facts
        .whereType<SupplierExtractionPackageAccommodationFact>()
        .first;
    expect(source.details.checkInDate, isNull);
    expect(source.details.checkOutDate, isNull);
    expect(
      find.descendant(of: panel('1'), matching: find.byType(ButtonStyleButton)),
      findsNothing,
    );
    expect(h.mutations.requests, isEmpty);
  });
  testWidgets('keyboard explicit retain uses existing command', (tester) async {
    await show(tester);
    await block(tester, '2');
    final b = action('2', 'Keep at package level');
    await tester.ensureVisible(b);
    Focus.of(tester.element(b)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(h.mutations.requests, hasLength(1));
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
    testWidgets('package mapping fits $width at large text', (tester) async {
      await show(tester, width: width, scale: 2);
      await block(tester, '1');
      await tap(tester, action('1', 'Map to day'));
      await tap(tester, action('1', 'Save mapping'));
      expect(tester.takeException(), isNull);
      expect(h.mutations.requests, isEmpty);
      expect(find.text('Choose an existing day.'), findsOneWidget);
    });
  }
  void replacePackage(Map<String, Object?> value) {
    final facts = supplierExtractionFactDocuments();
    final index = facts.indexWhere((d) => d.documentId == value['id']);
    facts[index] = supplierExtractionChild(value, index + 1);
    h.snapshots.value = SupplierExtractionSnapshot.fromStoredDocuments(
      expectedTripId: 'trip-1',
      expectedExtractionId: 'extraction-1',
      root: supplierExtractionRoot(),
      dayDocuments: supplierExtractionDayDocuments(),
      factDocuments: facts,
      reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
      trustedSourceFileIds: const ['file-1'],
    );
  }

  for (final kind in ['other', 'vehicle', 'operating_basis']) {
    testWidgets('condition $kind offers only its supported mapping', (
      tester,
    ) async {
      replacePackage({
        ...supplierExtractionPackageCondition(),
        'kind': kind,
        'value': kind == 'operating_basis'
            ? 'shared'
            : 'Explicit source condition',
        'appliesTo': <String>[],
      });
      await show(tester);
      await block(tester, '4');
      await tap(tester, action('4', 'Map to service'));
      await tap(tester, find.byKey(const ValueKey('package-map-destination')));
      final label = kind == 'other'
          ? 'Service notes'
          : kind == 'vehicle'
          ? 'Transfer vehicle type'
          : 'Transfer type';
      expect(find.text('Service inclusion'), findsNothing);
      expect(find.text('Service exclusion'), findsNothing);
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      final destination = kind == 'other'
          ? 'service_notes'
          : kind == 'vehicle'
          ? 'transfer_vehicle_type'
          : 'transfer_type';
      await tap(
        tester,
        find.byKey(ValueKey('package-map-service-$destination')),
      );
      await tester.tap(find.text('Airport transfer').last);
      await tester.pumpAndSettle();
      await tap(tester, action('4', 'Save mapping'));
      final d =
          (h.mutations.requests.single.mutation
                      as SupplierImportSetDecisionCommand)
                  .decision
              as SupplierImportPackageConditionDecision;
      expect(d.destination!.value, destination);
      expect(d.overrides.toMap(), isEmpty);
    });
  }
  testWidgets(
    'changing explicit decision preserves corrections in one operation',
    (tester) async {
      decisions['package-fact-2'] =
          const SupplierImportPackageStatementDecision(
            targetEntityId: 'package-fact-2',
            disposition: SupplierImportPackageDisposition.retainPackageLevel,
            service: null,
            destination: null,
            overrides: SupplierImportStatementOverrides(
              text: SupplierImportSetOverride('Existing correction'),
            ),
            exclusionReason: null,
            exclusionNote: null,
          );
      reload();
      await show(tester);
      await tap(tester, action('2', 'Change'));
      await tap(tester, action('2', 'Keep at package level'));
      final d =
          (h.mutations.requests.single.mutation
                      as SupplierImportSetDecisionCommand)
                  .decision
              as SupplierImportPackageStatementDecision;
      expect(d.overrides.text!.value, 'Existing correction');
      expect(h.finalizations.requests, isEmpty);
    },
  );
  test(
    'only existing retained targets and polarity-specific destinations',
    () async {
      await h.controller.load();
      final review = StagedServiceReviewData(h.controller.state);
      final facts = h.snapshots.value.facts;
      final inclusion = PackageReviewData(
        review,
        facts.firstWhere((f) => f.id == 'package-fact-2'),
      );
      final exclusion = PackageReviewData(
        review,
        facts.firstWhere((f) => f.id == 'package-fact-3'),
      );
      expect(inclusion.destinations, [
        SupplierImportPackageDestination.serviceInclusion,
      ]);
      expect(exclusion.destinations, [
        SupplierImportPackageDestination.serviceExclusion,
      ]);
      expect(
        inclusion
            .services(inclusion.destinations.single)
            .map((e) => e.$1.toMap()['serviceId']),
        ['staged-service-1', 'staged-service-2', 'staged-service-3'],
      );
    },
  );
  test('excluded day and service never appear as mapping targets', () async {
    decisions['staged-day-2'] = const SupplierImportDayDecision(
      targetEntityId: 'staged-day-2',
      disposition: SupplierImportRetainDisposition.exclude,
      overrides: SupplierImportDayOverrides(),
      exclusionReason: SupplierImportExclusionReason.duplicate,
      exclusionNote: null,
    );
    decisions['staged-service-2'] = const SupplierImportServiceDecision(
      targetEntityId: 'staged-service-2',
      disposition: SupplierImportRetainDisposition.exclude,
      overrides: SupplierImportServiceOverrides(),
      exclusionReason: SupplierImportExclusionReason.duplicate,
      exclusionNote: null,
    );
    reload();
    await h.controller.load();
    final data = PackageReviewData(
      StagedServiceReviewData(h.controller.state),
      h.snapshots.value.facts.firstWhere((f) => f.id == 'package-fact-2'),
    );
    expect(data.days.map((d) => d.$1.toMap()['dayId']), ['staged-day-1']);
    expect(
      data
          .services(SupplierImportPackageDestination.serviceInclusion)
          .map((s) => s.$1.toMap()['serviceId']),
      isNot(contains('staged-service-2')),
    );
  });
  testWidgets(
    'safe or-similar stay is not split and has no hotel-selection controls',
    (tester) async {
      await show(tester);
      final stays = h.snapshots.value.facts
          .whereType<SupplierExtractionPackageAccommodationFact>()
          .toList();
      expect(stays, hasLength(1));
      expect(stays.single.details.orSimilar, isTrue);
      expect(action('1', 'Keep as package stay'), findsNothing);
      expect(find.byType(DropdownButtonFormField), findsNothing);
    },
  );
  test('package labels remain safe for unknown finding', () {
    expect(
      packageFindingLabel('unknown', null),
      'This package item needs review before finalizing.',
    );
    for (final fact in h.snapshots.value.facts.where(
      (f) => f.factKind.value.startsWith('package_'),
    )) {
      final label = packageFindingLabel('unsupported_package_mapping', fact);
      expect(label, isNot(contains(fact.id)));
      expect(label, isNot(contains('unsupported_package_mapping')));
    }
  });
  test('no transport or local assembly/readiness implementation', () {
    for (final name in ['package_exception_panel', 'package_review_data']) {
      final source = File(
        'lib/features/itineraries/presentation/widgets/supplier_import/$name.dart',
      ).readAsStringSync();
      for (final forbidden in [
        'FirebaseFirestore',
        'FirebaseFunctions',
        'httpsCallable',
        'Gemini',
        'Timer.periodic',
        'assembleSupplierImport',
        'assessSupplierImport',
        'finalizeReview',
        'supplierCost',
        'currency',
      ]) {
        expect(source, isNot(contains(forbidden)));
      }
    }
  });
}
