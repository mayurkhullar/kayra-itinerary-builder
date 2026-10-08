import 'dart:async';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_draft_v2_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_finalization_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_draft_v2.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_finalization.dart';
import 'package:kayra_crm_v1/features/itineraries/presentation/controllers/supplier_import_review_controller.dart';
import 'supplier_import_review_fixture.dart';
import 'itinerary_draft_v2_fixture.dart';

const finalizationOutcomes = [
  'applied',
  'already_applied',
  'not_ready',
  'resolution_conflict',
  'resolution_not_started',
  'resolution_finalized',
  'persistence_capacity_exceeded',
];
SupplierImportFinalizationRequest finalizationRequest({
  int revision = 2,
  String commandId = 'intent-1',
}) => SupplierImportFinalizationRequest(
  tripId: 'trip-1',
  extractionId: 'extraction-1',
  commandId: commandId,
  expectedRevision: revision,
);
Map<String, Object?> finalizationResponse(
  String outcome, {
  int revision = 3,
  String draftId = 'draft-1',
}) => {
  'outcome': outcome,
  if (outcome == 'not_ready')
    'assessment': {
      'resolutionId': 'extraction-1',
      'evaluatedRevision': revision - 1,
      'canFinalize': false,
      'blockers': [
        {
          'code': 'unresolved_unassigned_service',
          'targetKind': 'service',
          'targetId': 'staged-service-1',
        },
      ],
      'warnings': [
        {
          'code': 'snapshot_warning_open',
          'targetKind': 'review_issue',
          'targetId': 'review-1',
        },
      ],
    },
  if (outcome != 'not_ready') 'resolutionId': 'extraction-1',
  if (outcome == 'applied' ||
      outcome == 'already_applied' ||
      outcome == 'resolution_finalized')
    'revision': revision,
  if (outcome == 'applied' || outcome == 'already_applied')
    'resultingDraftId': draftId,
  if (outcome == 'resolution_conflict') 'currentRevision': revision,
  if (outcome == 'resolution_not_started') 'revision': 0,
  if (outcome == 'persistence_capacity_exceeded') 'boundary': 'receipt',
};
SupplierImportFinalizationOutcome finalizationOutcome(
  String name, {
  int revision = 3,
  String draftId = 'draft-1',
}) => SupplierImportFinalizationOutcome.fromMap(
  finalizationResponse(name, revision: revision, draftId: draftId),
);
ItineraryDraftV2 finalizationDraft({
  int evaluatedRevision = 2,
  String commandId = 'intent-1',
  String tripId = 'trip-1',
  String draftId = 'draft-1',
  String extractionId = 'extraction-1',
  String packageId = 'package-1',
}) {
  final m = itineraryDraftV2Fixture(full: false);
  m['tripId'] = tripId;
  m['sourcePackageIds'] = [packageId];
  (m['importResult'] as Map<String, dynamic>).addAll({
    'evaluatedRevision': evaluatedRevision,
    'policyVersion': optionalChronologyImportPolicy,
    'finalizationId': commandId,
    'extractionId': extractionId,
    'resolutionId': extractionId,
    'sourcePackageId': packageId,
  });
  return ItineraryDraftV2.fromFirestore(m, documentId: draftId);
}

final class FinalizationHarness {
  FinalizationHarness() {
    controller = SupplierImportReviewController(
      tripId: 'trip-1',
      extractionId: 'extraction-1',
      snapshots: snapshots,
      resolutions: resolutions,
      mutations: mutations,
      finalizations: finalizations,
      drafts: drafts,
      generateCommandId: () => 'intent-${++generatedIds}',
    );
    resolutions.value = reviewResolution(revision: 2);
  }
  final calls = <String>[];
  late final snapshots = ReviewSnapshots(calls);
  late final resolutions = ReviewResolutions(calls);
  late final mutations = ReviewMutations(calls);
  late final finalizations = ReviewFinalizations(calls);
  late final drafts = ReviewDrafts(calls);
  late final SupplierImportReviewController controller;
  int generatedIds = 0;
  bool disposed = false;
  void dispose() {
    if (!disposed) {
      disposed = true;
      controller.dispose();
    }
  }

  void seal() {
    resolutions.value = reviewResolution(revision: 3, finalized: true);
  }
}

final class ReviewFinalizations implements SupplierImportFinalizationClient {
  ReviewFinalizations(this.calls);
  final List<String> calls;
  final requests = <SupplierImportFinalizationRequest>[];
  Object? error;
  SupplierImportFinalizationOutcome outcome = finalizationOutcome('applied');
  FutureOr<SupplierImportFinalizationOutcome> Function(
    SupplierImportFinalizationRequest,
  )?
  onExecute;
  @override
  Future<SupplierImportFinalizationOutcome> execute(
    SupplierImportFinalizationRequest request,
  ) async {
    calls.add('finalize');
    requests.add(request);
    if (error != null) throw error!;
    return onExecute == null ? outcome : await onExecute!(request);
  }
}

final class ReviewDrafts implements ItineraryDraftV2Repository {
  ReviewDrafts(this.calls);
  final List<String> calls;
  ItineraryDraftV2 value = finalizationDraft();
  Object? error;
  Future<ItineraryDraftV2> Function()? onRead;
  @override
  Future<ItineraryDraftV2> getDraft(String tripId, String draftId) async {
    calls.add('draft:$tripId/$draftId');
    if (error != null) throw error!;
    return onRead == null ? value : await onRead!();
  }
}
