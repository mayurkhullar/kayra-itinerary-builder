import '../../domain/supplier_extraction_snapshot.dart';
import '../../domain/supplier_import_resolution.dart';
import '../../domain/supplier_import_resolution_mutation.dart';
import 'supplier_import_review_error.dart';

sealed class SupplierImportReviewState {
  const SupplierImportReviewState();

  SupplierImportReviewLoaded? get loaded => null;
  SupplierImportResolutionMutationRequest? get pendingMutation => null;
}

final class SupplierImportReviewInitial extends SupplierImportReviewState {
  const SupplierImportReviewInitial();
}

sealed class SupplierImportReviewLoaded extends SupplierImportReviewState {
  const SupplierImportReviewLoaded(this.snapshot);

  final SupplierExtractionSnapshot snapshot;

  @override
  SupplierImportReviewLoaded get loaded => this;
}

final class SupplierImportReviewNotStarted extends SupplierImportReviewLoaded {
  const SupplierImportReviewNotStarted(super.snapshot);
}

final class SupplierImportReviewActive extends SupplierImportReviewLoaded {
  SupplierImportReviewActive(super.snapshot, this.resolution) {
    if (resolution.root.status != SupplierImportResolutionStatus.active) {
      throw ArgumentError('An active resolution is required.');
    }
  }

  final SupplierImportResolutionAggregate resolution;
}

final class SupplierImportReviewFinalized extends SupplierImportReviewLoaded {
  SupplierImportReviewFinalized(super.snapshot, this.resolution) {
    if (resolution.root.status != SupplierImportResolutionStatus.finalized) {
      throw ArgumentError('A finalized resolution is required.');
    }
  }

  final SupplierImportResolutionAggregate resolution;
}

final class SupplierImportReviewLoading extends SupplierImportReviewState {
  const SupplierImportReviewLoading({this.loaded, this.pendingMutation});

  @override
  final SupplierImportReviewLoaded? loaded;
  @override
  final SupplierImportResolutionMutationRequest? pendingMutation;
}

/// Covers the callable and its subsequent authoritative read.
final class SupplierImportReviewSaving extends SupplierImportReviewState {
  const SupplierImportReviewSaving(this.loaded, this.pendingMutation);

  @override
  final SupplierImportReviewLoaded loaded;
  @override
  final SupplierImportResolutionMutationRequest pendingMutation;
}

final class SupplierImportReviewConflict extends SupplierImportReviewState {
  const SupplierImportReviewConflict(this.loaded, this.currentRevision);

  @override
  final SupplierImportReviewLoaded loaded;
  final int currentRevision;
}

enum SupplierImportReviewRecovery { refresh, retryPendingMutation }

final class SupplierImportReviewFailed extends SupplierImportReviewState {
  const SupplierImportReviewFailed({
    required this.error,
    required this.recovery,
    this.loaded,
    this.pendingMutation,
    this.outcomeAwaitingRefresh,
  });

  final SupplierImportReviewError error;
  final SupplierImportReviewRecovery recovery;
  @override
  final SupplierImportReviewLoaded? loaded;
  @override
  final SupplierImportResolutionMutationRequest? pendingMutation;

  /// Preserves a conflict or confirmed outcome if its follow-up read fails.
  final SupplierImportResolutionMutationOutcome? outcomeAwaitingRefresh;
}
