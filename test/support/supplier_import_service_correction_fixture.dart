import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/core/theme/app_theme.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_fact.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_state.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/pages/supplier_import_review_page.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/widgets/supplier_import/staged_service_review_data.dart';

import 'supplier_extraction_fixture.dart';
import 'supplier_import_day_review_fixture.dart';
import 'supplier_import_review_fixture.dart';

SupplierImportServiceDecision serviceCorrectionDecision({
  String id = 'staged-service-1',
  String? day,
  int? order,
  bool exclude = false,
  SupplierImportServiceOverrides overrides =
      const SupplierImportServiceOverrides(),
}) => SupplierImportServiceDecision(
  targetEntityId: id,
  disposition: exclude
      ? SupplierImportRetainDisposition.exclude
      : SupplierImportRetainDisposition.retain,
  day: day == null ? null : SupplierImportStagedDayReference(day),
  canonicalOrder: order,
  overrides: overrides,
  exclusionReason: exclude ? SupplierImportExclusionReason.other : null,
  exclusionNote: exclude ? 'Outside itinerary scope' : null,
);

StagedServiceReviewData serviceCorrectionReview(
  SupplierImportServiceDecision decision, {
  SupplierExtractionSnapshot? snapshot,
}) => StagedServiceReviewData(
  SupplierImportReviewActive(
    snapshot ?? supplierExtractionFixture(),
    dayReviewResolution(decisions: [decision]).resolution,
  ),
);

SupplierExtractionServiceFact serviceFact(
  SupplierExtractionSnapshot snapshot, [
  int number = 1,
]) => snapshot.facts.whereType<SupplierExtractionServiceFact>().singleWhere(
  (s) => s.id == 'staged-service-$number',
);

SupplierExtractionSnapshot serviceCorrectionSnapshot({
  Map<String, Object?> service1 = const {},
}) => SupplierExtractionSnapshot.fromStoredDocuments(
  expectedTripId: 'trip-1',
  expectedExtractionId: 'extraction-1',
  root: supplierExtractionRoot(),
  dayDocuments: supplierExtractionDayDocuments(),
  factDocuments: [
    for (final doc in supplierExtractionFactDocuments())
      (
        documentId: doc.documentId,
        data: {
          ...doc.data,
          if (doc.documentId == 'staged-service-1')
            'value': {
              ...doc.data['value']! as Map<String, Object?>,
              ...service1,
            },
        },
      ),
  ],
  reviewIssueDocuments: supplierExtractionReviewIssueDocuments(),
  trustedSourceFileIds: const ['file-1'],
);

Finder serviceKey(String name) => find.byKey(ValueKey(name));
Finder serviceActions() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.contains('-review-action-'),
);
Finder servicePanelText(String value) => find.descendant(
  of: serviceKey('service-corrections-staged-service-1'),
  matching: find.text(value),
);

class ServiceCorrectionHarness {
  ServiceCorrectionHarness() {
    h.resolutions.value = reviewResolution();
  }
  final h = ReviewHarness();
  late var dependencies = SupplierImportReviewDependencies(
    snapshots: h.snapshots,
    resolutions: h.resolutions,
    mutations: h.mutations,
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
    String key, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(serviceKey(key));
    await tester.tap(serviceKey(key));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> open(
    WidgetTester tester,
    String field, {
    int service = 1,
  }) async {
    await tap(tester, 'service-review-action-staged-service-$service');
    await tap(tester, 'correct-service-$field');
  }

  SupplierImportServiceDecision get requested =>
      (h.mutations.requests.last.mutation as SupplierImportSetDecisionCommand)
              .decision
          as SupplierImportServiceDecision;

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
}
