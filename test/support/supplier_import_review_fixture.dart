import 'dart:async';

import 'package:kayra_crm_v1/features/itineraries/data/supplier_extraction_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_manual_item.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_controller.dart';

import 'supplier_extraction_fixture.dart';
import 'supplier_import_resolution_fixture.dart';

const reviewTitleDecision = SupplierImportTitleDecision(
  disposition: SupplierImportTitleDisposition.accept,
);
const reviewManualDay = SupplierImportManualDay(
  manualDayId: 'consultant-day-1',
  canonicalOrder: 3,
  date: null,
  title: 'Additional day',
  summary: null,
  notes: null,
);

SupplierImportResolutionLoaded reviewResolution({
  int revision = 1,
  bool finalized = false,
  String tripId = 'trip-1',
  String extractionId = 'extraction-1',
  String sourcePackageId = 'package-1',
}) => SupplierImportResolutionLoaded(
  SupplierImportResolutionAggregate.fromStoredDocuments(
    expectedTripId: tripId,
    expectedExtractionId: extractionId,
    rootDocumentId: extractionId,
    rootData: {
      ...supplierImportResolutionRoot(
        tripId: tripId,
        extractionId: extractionId,
        resolutionId: extractionId,
        revision: revision,
        status: finalized ? 'finalized' : 'active',
      ),
      'sourcePackageId': sourcePackageId,
    },
    decisionDocuments: const [],
    manualItemDocuments: const [],
    eventDocuments: List.generate(revision, (index) {
      final isFinal = finalized && index == revision - 1;
      return (
        documentId: 'command-${index + 1}',
        data: {
          ...supplierImportAuditEvent(previousRevision: index),
          'resolutionId': extractionId,
          'extractionId': extractionId,
          'action': index == 0
              ? 'open_review'
              : isFinal
              ? 'finalize'
              : 'set_title_decision',
          'targetKind': index == 0
              ? 'resolution'
              : isFinal
              ? 'finalization'
              : 'title',
          'targetId': index == 0 || isFinal ? extractionId : 'title',
          'metadata': index == 0 || isFinal
              ? {
                  'kind': 'lifecycle',
                  'status': isFinal ? 'finalized' : 'active',
                }
              : {
                  'kind': 'decision',
                  'disposition': 'accept',
                  'changedFields': <String>[],
                  'exclusionReason': null,
                  'referencedIds': <String>[],
                },
        },
      );
    }),
  ),
);

SupplierImportResolutionMutationOutcome reviewOutcome(
  String outcome, {
  int revision = 2,
  String resolutionId = 'extraction-1',
}) => SupplierImportResolutionMutationOutcome.fromMap({
  'outcome': outcome,
  'resolutionId': resolutionId,
  if (outcome == 'resolution_conflict')
    'currentRevision': revision
  else
    'revision': revision,
  if (outcome == 'applied') ...{
    'status': 'active',
    'canFinalize': false,
    'blockerCount': 4,
    'warningCount': 1,
  },
});

final class ReviewHarness {
  ReviewHarness() {
    controller = SupplierImportReviewController(
      tripId: 'trip-1',
      extractionId: 'extraction-1',
      snapshots: snapshots,
      resolutions: resolutions,
      mutations: mutations,
      generateCommandId: () => 'intent-${++generatedIds}',
    );
  }

  final calls = <String>[];
  late final snapshots = ReviewSnapshots(calls);
  late final resolutions = ReviewResolutions(calls);
  late final mutations = ReviewMutations(calls);
  late final SupplierImportReviewController controller;
  int generatedIds = 0;
  bool disposed = false;

  void dispose() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
  }
}

final class ReviewSnapshots implements SupplierExtractionRepository {
  ReviewSnapshots(this.calls);
  final List<String> calls;
  SupplierExtractionSnapshot value = supplierExtractionFixture();
  Object? error;
  Future<SupplierExtractionSnapshot> Function()? onRead;
  int readCount = 0;

  @override
  Future<SupplierExtractionSnapshot> getCompleteSnapshot({
    required String tripId,
    required String extractionId,
  }) async {
    calls.add('snapshot:$tripId/$extractionId');
    readCount++;
    if (error != null) throw error!;
    return onRead == null ? value : await onRead!();
  }
}

final class ReviewResolutions implements SupplierImportResolutionRepository {
  ReviewResolutions(this.calls);
  final List<String> calls;
  SupplierImportResolutionReadResult value =
      const SupplierImportResolutionNotStarted();
  Object? error;
  Future<SupplierImportResolutionReadResult> Function()? onRead;
  int readCount = 0;

  @override
  Future<SupplierImportResolutionReadResult> getResolution({
    required String tripId,
    required String extractionId,
  }) async {
    calls.add('resolution:$tripId/$extractionId');
    readCount++;
    if (error != null) throw error!;
    return onRead == null ? value : await onRead!();
  }
}

final class ReviewMutations implements SupplierImportResolutionMutationClient {
  ReviewMutations(this.calls);
  final List<String> calls;
  final requests = <SupplierImportResolutionMutationRequest>[];
  SupplierImportResolutionMutationOutcome outcome = reviewOutcome('applied');
  Object? error;
  FutureOr<SupplierImportResolutionMutationOutcome> Function(
    SupplierImportResolutionMutationRequest,
  )?
  onExecute;

  @override
  Future<SupplierImportResolutionMutationOutcome> execute(
    SupplierImportResolutionMutationRequest request,
  ) async {
    calls.add('mutation:${request.mutation.action}');
    requests.add(request);
    if (error != null) throw error!;
    return onExecute == null ? outcome : await onExecute!(request);
  }
}
