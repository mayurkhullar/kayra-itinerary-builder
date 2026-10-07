import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/itinerary_draft_v2_repository.dart';
import '../../data/supplier_extraction_repository.dart';
import '../../data/supplier_import_finalization_client.dart';
import '../../data/supplier_import_resolution_mutation_client.dart';
import '../../data/supplier_import_resolution_repository.dart';
import '../../domain/supplier_extraction_snapshot.dart';
import '../../domain/supplier_import_finalization.dart';
import '../../domain/supplier_import_resolution.dart';
import '../../domain/supplier_import_resolution_decision.dart';
import '../../domain/supplier_import_resolution_manual_item.dart';
import '../../domain/supplier_import_resolution_mutation.dart';
import '../../domain/supplier_import_resolution_parsing.dart';
import 'supplier_import_review_error.dart';
import 'supplier_import_review_finalization_state.dart';
import 'supplier_import_review_state.dart';

part 'supplier_import_review_finalization.dart';

/// One review session. No method changes its Trip or extraction identity.
/// Actions return a sanitized error on failure/rejection, and null on success.
final class SupplierImportReviewController extends ChangeNotifier {
  SupplierImportReviewController({
    required String tripId,
    required String extractionId,
    required SupplierExtractionRepository snapshots,
    required SupplierImportResolutionRepository resolutions,
    required SupplierImportResolutionMutationClient mutations,
    String Function()? generateCommandId,
    SupplierImportFinalizationClient? finalizations,
    ItineraryDraftV2Repository? drafts,
  }) : tripId = SupplierImportResolutionParsing.id(tripId, 'Trip'),
       extractionId = SupplierImportResolutionParsing.id(
         extractionId,
         'Extraction',
       ),
       _snapshots = snapshots,
       _resolutions = resolutions,
       _mutations = mutations,
       _finalizations = finalizations,
       _drafts = drafts,
       _generateCommandId =
           generateCommandId ?? SupplierImportCommandIdGenerator().generate;

  final String tripId;
  final String extractionId;
  final SupplierExtractionRepository _snapshots;
  final SupplierImportResolutionRepository _resolutions;
  final SupplierImportResolutionMutationClient _mutations;
  final String Function() _generateCommandId;
  final SupplierImportFinalizationClient? _finalizations;
  final ItineraryDraftV2Repository? _drafts;
  SupplierImportReviewFinalizationState? _finalization;

  /// Lifecycle availability only; readiness remains server-owned.
  bool get canFinalizeReview => _canBeginFinalization;
  bool get canRetryPendingFinalization => _canRetryFinalization;
  bool get supportsFinalization => _finalizations != null && _drafts != null;

  Future<SupplierImportReviewError?> finalizeReview() => _beginFinalization();
  Future<SupplierImportReviewError?> retryPendingFinalization() =>
      _retryFinalization();

  SupplierImportReviewState _state = const SupplierImportReviewInitial();
  SupplierImportReviewState get state => _state;
  SupplierExtractionSnapshot? _snapshot;
  SupplierImportResolutionMutationRequest? _pending;
  SupplierImportResolutionMutationOutcome? _outcomeAwaitingRefresh;
  bool _disposed = false;
  int _operation = 0;

  static const _invalidAction = SupplierImportReviewError(
    SupplierImportReviewErrorKind.invalidLocalAction,
  );
  static const _malformed = SupplierImportReviewError(
    SupplierImportReviewErrorKind.malformedData,
  );

  Future<SupplierImportReviewError?> load() => refresh();

  /// Reuses the immutable Snapshot once loaded. A read alone cannot establish
  /// whether an unconfirmed command was applied, so it preserves that request.
  Future<SupplierImportReviewError?> refresh() async {
    if (_disposed ||
        _state is SupplierImportReviewSaving ||
        _state is SupplierImportReviewFinalizing) {
      return _invalidAction;
    }
    final operation = ++_operation;
    final previous = _state.loaded;
    _emit(
      SupplierImportReviewLoading(
        loaded: previous,
        pendingMutation: _pending,
        finalization: _finalization,
      ),
    );
    if (!_isCurrent(operation)) return _invalidAction;
    if (_snapshot == null) {
      SupplierExtractionSnapshot snapshot;
      try {
        snapshot = await _snapshots.getCompleteSnapshot(
          tripId: tripId,
          extractionId: extractionId,
        );
      } catch (error) {
        if (!_isCurrent(operation)) return _invalidAction;
        return _fail(SupplierImportReviewError.snapshot(error), previous);
      }
      if (!_isCurrent(operation)) return _invalidAction;
      if (snapshot.tripId != tripId ||
          snapshot.extractionId != extractionId ||
          snapshot.persistenceState != 'complete') {
        return _fail(_malformed, previous);
      }
      _snapshot = snapshot;
    }
    return _reloadResolution(operation, previous);
  }

  Future<SupplierImportReviewError?> startReview() =>
      _submit(() => const SupplierImportStartReviewCommand(), start: true);

  Future<SupplierImportReviewError?> setDecision(
    SupplierImportDecisionPayload decision,
  ) => _submit(() => SupplierImportSetDecisionCommand(decision));

  Future<SupplierImportReviewError?> removeDecision(String decisionId) =>
      _submit(() => SupplierImportRemoveDecisionCommand(decisionId));

  Future<SupplierImportReviewError?> upsertManualItem(
    SupplierImportManualItemPayload item,
  ) => _submit(() => SupplierImportUpsertManualItemCommand(item));

  Future<SupplierImportReviewError?> removeManualItem(String manualItemId) =>
      _submit(() => SupplierImportRemoveManualItemCommand(manualItemId));

  Future<SupplierImportReviewError?> _submit(
    SupplierImportResolutionMutationCommand Function() command, {
    bool start = false,
  }) async {
    final loaded = _state.loaded;
    final available =
        _state is SupplierImportReviewLoaded ||
        _state is SupplierImportReviewConflict;
    if (_disposed ||
        !available ||
        _pending != null ||
        _finalization?.request != null ||
        (start
            ? loaded is! SupplierImportReviewNotStarted
            : loaded is! SupplierImportReviewActive)) {
      return _invalidAction;
    }
    final revision = loaded is SupplierImportReviewActive
        ? loaded.resolution.root.revision
        : 0;
    try {
      final mutation = command();
      _finalization = null; // Prior findings describe the old revision.
      _pending = SupplierImportResolutionMutationRequest(
        tripId: tripId,
        extractionId: extractionId,
        expectedRevision: revision,
        commandId: _generateCommandId(),
        mutation: mutation,
      );
    } on FormatException {
      return _fail(
        const SupplierImportReviewError(
          SupplierImportReviewErrorKind.invalidMutation,
        ),
        loaded,
      );
    } catch (_) {
      return _fail(
        const SupplierImportReviewError(
          SupplierImportReviewErrorKind.unexpected,
        ),
        loaded,
      );
    }
    return _executePending(loaded!);
  }

  Future<SupplierImportReviewError?> retryPendingMutation() async {
    final current = _state;
    if (_disposed ||
        current is! SupplierImportReviewFailed ||
        current.recovery != SupplierImportReviewRecovery.retryPendingMutation ||
        _pending == null ||
        _outcomeAwaitingRefresh != null ||
        current.loaded == null) {
      return _invalidAction;
    }
    return _executePending(current.loaded!);
  }

  Future<SupplierImportReviewError?> _executePending(
    SupplierImportReviewLoaded previous,
  ) async {
    final request = _pending!;
    final operation = ++_operation;
    _emit(SupplierImportReviewSaving(previous, request));
    if (!_isCurrent(operation)) return _invalidAction;
    SupplierImportResolutionMutationOutcome outcome;
    try {
      outcome = await _mutations.execute(request);
    } on SupplierImportMutationFailure catch (error) {
      if (!_isCurrent(operation)) return _invalidAction;
      // Internal/unknown failures may also follow a committed write. Retain
      // their idempotency identity instead of permitting a fresh intent.
      final ambiguous =
          error.kind == SupplierImportMutationFailureKind.unavailable ||
          error.kind == SupplierImportMutationFailureKind.internal;
      if (!ambiguous) _pending = null;
      return _fail(
        SupplierImportReviewError.mutation(error),
        previous,
        recovery: ambiguous
            ? SupplierImportReviewRecovery.retryPendingMutation
            : SupplierImportReviewRecovery.refresh,
      );
    } on TimeoutException {
      if (!_isCurrent(operation)) return _invalidAction;
      return _fail(
        const SupplierImportReviewError(
          SupplierImportReviewErrorKind.ambiguousNetwork,
        ),
        previous,
        recovery: SupplierImportReviewRecovery.retryPendingMutation,
      );
    } catch (_) {
      if (!_isCurrent(operation)) return _invalidAction;
      return _fail(
        const SupplierImportReviewError(
          SupplierImportReviewErrorKind.unexpected,
        ),
        previous,
        recovery: SupplierImportReviewRecovery.retryPendingMutation,
      );
    }
    if (!_isCurrent(operation)) return _invalidAction;
    if (outcome.resolutionId != extractionId) {
      return _fail(
        _malformed,
        previous,
        recovery: SupplierImportReviewRecovery.retryPendingMutation,
      );
    }
    _outcomeAwaitingRefresh = outcome;
    switch (outcome) {
      case SupplierImportMutationApplied() ||
          SupplierImportMutationAlreadyApplied():
        break; // Keep the request until the authoritative read succeeds.
      case SupplierImportMutationConflict() ||
          SupplierImportMutationNotStarted() ||
          SupplierImportMutationFinalized():
        _pending = null;
    }
    return _reloadResolution(operation, previous);
  }

  Future<SupplierImportReviewError?> _reloadResolution(
    int operation,
    SupplierImportReviewLoaded? previous,
  ) async {
    SupplierImportResolutionReadResult result;
    try {
      result = await _resolutions.getResolution(
        tripId: tripId,
        extractionId: extractionId,
      );
    } catch (error) {
      if (!_isCurrent(operation)) return _invalidAction;
      return _fail(SupplierImportReviewError.resolution(error), previous);
    }
    if (!_isCurrent(operation)) return _invalidAction;
    final snapshot = _snapshot!;
    SupplierImportReviewLoaded loaded;
    switch (result) {
      case SupplierImportResolutionNotStarted():
        loaded = SupplierImportReviewNotStarted(snapshot);
      case SupplierImportResolutionLoaded(:final resolution):
        final root = resolution.root;
        if (root.tripId != tripId ||
            root.extractionId != extractionId ||
            root.resolutionId != extractionId ||
            root.sourcePackageId != snapshot.sourcePackageId ||
            root.snapshotSchemaVersion != snapshot.schemaVersion) {
          return _fail(_malformed, previous);
        }
        loaded = switch (root.status) {
          SupplierImportResolutionStatus.active => SupplierImportReviewActive(
            snapshot,
            resolution,
          ),
          SupplierImportResolutionStatus.finalized =>
            SupplierImportReviewFinalized(snapshot, resolution),
        };
    }
    try {
      _verifyFinalizationResolution(loaded);
    } on FormatException {
      return _fail(
        _malformed,
        loaded is SupplierImportReviewFinalized ? loaded : previous,
      );
    }
    if (loaded is SupplierImportReviewFinalized && _drafts != null) {
      try {
        loaded = await _readFinalizedDraft(loaded);
      } catch (error) {
        if (!_isCurrent(operation)) return _invalidAction;
        return _fail(SupplierImportReviewError.draft(error), loaded);
      }
      if (!_isCurrent(operation)) return _invalidAction;
    }
    final outcome = _outcomeAwaitingRefresh;
    // A confirmed save must be visible before the pending request is cleared.
    // Revision comparisons use only server values, never a local increment.
    final confirmedRevision = switch (outcome) {
      SupplierImportMutationApplied(:final revision) ||
      SupplierImportMutationAlreadyApplied(:final revision) ||
      SupplierImportMutationFinalized(:final revision) => revision,
      _ => null,
    };
    final loadedRevision = switch (loaded) {
      SupplierImportReviewActive(:final resolution) ||
      SupplierImportReviewFinalized(
        :final resolution,
      ) => resolution.root.revision,
      SupplierImportReviewNotStarted() => 0,
    };
    if ((confirmedRevision != null && loadedRevision < confirmedRevision) ||
        (outcome is SupplierImportMutationFinalized &&
            loaded is! SupplierImportReviewFinalized)) {
      return _fail(_malformed, previous);
    }
    if (outcome != null || loaded is SupplierImportReviewFinalized) {
      _pending = null;
    }
    _outcomeAwaitingRefresh = null;
    if (_pending != null) {
      return _fail(
        const SupplierImportReviewError(
          SupplierImportReviewErrorKind.ambiguousNetwork,
        ),
        loaded,
        recovery: SupplierImportReviewRecovery.retryPendingMutation,
      );
    }
    final finalization = _finalization;
    if (finalization?.phase ==
        SupplierImportReviewFinalizationPhase.ambiguous) {
      return _fail(
        const SupplierImportReviewError(
          SupplierImportReviewErrorKind.ambiguousNetwork,
        ),
        loaded,
        recovery: SupplierImportReviewRecovery.retryPendingFinalization,
      );
    }
    if (finalization?.phase ==
        SupplierImportReviewFinalizationPhase.awaitingReload) {
      _finalization = SupplierImportReviewFinalizationState.result(
        finalization!.outcome!,
        attemptedRevision: finalization.attemptedRevision,
      );
    }
    loaded = _withFinalization(loaded);
    final finalOutcome = _finalization?.outcome;
    _emit(
      finalOutcome is SupplierImportFinalizationConflict &&
              loaded is! SupplierImportReviewFinalized
          ? SupplierImportReviewConflict(
              loaded,
              finalOutcome.currentRevision,
              finalization: _finalization,
            )
          : outcome is SupplierImportMutationConflict
          ? SupplierImportReviewConflict(loaded, outcome.currentRevision)
          : loaded,
    );
    return null;
  }

  SupplierImportReviewError _fail(
    SupplierImportReviewError error,
    SupplierImportReviewLoaded? previous, {
    SupplierImportReviewRecovery recovery =
        SupplierImportReviewRecovery.refresh,
  }) {
    _emit(
      SupplierImportReviewFailed(
        error: error,
        recovery:
            _finalization?.phase ==
                SupplierImportReviewFinalizationPhase.ambiguous
            ? SupplierImportReviewRecovery.retryPendingFinalization
            : recovery,
        loaded: previous,
        pendingMutation: _pending,
        outcomeAwaitingRefresh: _outcomeAwaitingRefresh,
        finalization: _finalization,
      ),
    );
    return error;
  }

  bool _isCurrent(int operation) => !_disposed && operation == _operation;

  void _emit(SupplierImportReviewState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    super.dispose();
  }
}
