import 'package:flutter/foundation.dart';

import '../../data/itinerary_extraction_dependencies.dart';
import '../../domain/kayra_itinerary_extraction_job.dart';
import 'itinerary_extraction_controller.dart';
import 'supplier_import_review_controller.dart';
import 'supplier_import_review_state.dart';

/// An explicit replacement attempt; never edits the original review identity.
final class SupplierImportReextractionController extends ChangeNotifier {
  SupplierImportReextractionController({
    required this.review,
    required this.dependencies,
  }) : extraction = ItineraryExtractionController(
         tripId: review.tripId,
         jobs: dependencies.jobs,
         requests: dependencies.requests,
       ) {
    review.addListener(_reviewChanged);
    extraction.addListener(_changed);
    _reviewChanged();
  }

  final SupplierImportReviewController review;
  final ItineraryExtractionDependencies dependencies;
  final ItineraryExtractionController extraction;
  bool _checked = false;
  bool _verified = false;
  bool _disposed = false;
  bool _confirming = false;
  bool _started = false;
  String? _packageId;

  bool get canRequest =>
      !_disposed &&
      !_confirming &&
      !_started &&
      _verified &&
      _reviewAllowsRequest;
  bool get _reviewAllowsRequest =>
      review.state is SupplierImportReviewNotStarted ||
      review.state is SupplierImportReviewActive;
  bool get hasReviewChanges {
    final state = review.state;
    return state is SupplierImportReviewActive &&
        (state.resolution.decisions.isNotEmpty ||
            state.resolution.manualItems.isNotEmpty);
  }

  String? get packageId => _packageId;
  ItineraryExtractionPackageState? get replacement =>
      _started ? extraction.stateForPackage(_packageId!) : null;

  void _reviewChanged() {
    final loaded = review.state.loaded;
    if (!_checked && loaded != null && _reviewAllowsRequest) {
      _checked = true;
      _packageId = loaded.snapshot.sourcePackageId;
      _verify(loaded.snapshot.jobId);
    }
    _changed();
  }

  Future<void> _verify(String jobId) async {
    try {
      final job = await dependencies.jobs.getJob(review.tripId, jobId);
      if (_disposed) return;
      _verified =
          job != null &&
          job.id == jobId &&
          job.tripId == review.tripId &&
          job.sourcePackageId == _packageId &&
          job.status == KayraItineraryExtractionStatus.completed &&
          job.resultType ==
              KayraItineraryExtractionResultType.supplierExtraction &&
          job.resultingExtractionId == review.extractionId;
    } catch (_) {
      // Fail closed. Ordinary review remains available without this action.
    }
    _changed();
  }

  /// Called only after the consultant confirms. Refresh prevents requesting
  /// against a review that has become finalized since it was displayed.
  Future<void> requestConfirmed() async {
    if (!canRequest) return;
    _confirming = true;
    _changed();
    await review.refresh();
    if (_disposed) return;
    _confirming = false;
    if (!_reviewAllowsRequest) {
      _changed();
      return;
    }
    _started = true;
    await extraction.request(_packageId!);
  }

  Future<void> retry() async {
    if (_disposed || !_started) return;
    final kind = replacement?.kind;
    if (kind != ItineraryExtractionPackageStateKind.failed &&
        kind != ItineraryExtractionPackageStateKind.error &&
        kind != ItineraryExtractionPackageStateKind.longRunning) {
      return;
    }
    await extraction.request(_packageId!);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    review.removeListener(_reviewChanged);
    extraction.removeListener(_changed);
    extraction.dispose();
    super.dispose();
  }
}
