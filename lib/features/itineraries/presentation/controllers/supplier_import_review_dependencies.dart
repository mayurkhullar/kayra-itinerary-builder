import '../../data/itinerary_draft_v2_repository.dart';
import '../../data/supplier_extraction_repository.dart';
import '../../data/supplier_import_finalization_client.dart';
import '../../data/supplier_import_resolution_mutation_client.dart';
import '../../data/supplier_import_resolution_repository.dart';
import 'supplier_import_review_controller.dart';

/// Composition only; all reads and mutations retain their existing boundaries.
final class SupplierImportReviewDependencies {
  const SupplierImportReviewDependencies({
    required this.snapshots,
    required this.resolutions,
    required this.mutations,
    this.finalizations,
    this.drafts,
  });

  factory SupplierImportReviewDependencies.firebase() =>
      SupplierImportReviewDependencies(
        snapshots: FirestoreSupplierExtractionRepository(),
        resolutions: FirestoreSupplierImportResolutionRepository(),
        mutations: CallableSupplierImportResolutionMutationClient(),
        finalizations: CallableSupplierImportFinalizationClient(),
        drafts: FirestoreItineraryDraftV2Repository(),
      );

  // Optional only for existing read/mutation-only compositions. Production
  // always provides both; finalization is unavailable without them.
  final SupplierImportFinalizationClient? finalizations;
  final ItineraryDraftV2Repository? drafts;
  final SupplierExtractionRepository snapshots;
  final SupplierImportResolutionRepository resolutions;
  final SupplierImportResolutionMutationClient mutations;

  SupplierImportReviewController createController(
    String tripId,
    String extractionId,
  ) => SupplierImportReviewController(
    tripId: tripId,
    extractionId: extractionId,
    snapshots: snapshots,
    resolutions: resolutions,
    mutations: mutations,
    finalizations: finalizations,
    drafts: drafts,
  );
}
