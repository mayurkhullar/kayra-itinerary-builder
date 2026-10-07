part of 'supplier_import_review_controller.dart';

/// Transport orchestration only. No assembly/readiness policy is evaluated here.
extension _FinalizationOrchestration on SupplierImportReviewController {
  bool get _canBeginFinalization {
    final loaded = _state.loaded;
    if (_disposed ||
        _snapshot == null ||
        _finalizations == null ||
        _drafts == null ||
        !(_state is SupplierImportReviewLoaded ||
            _state is SupplierImportReviewConflict) ||
        loaded is! SupplierImportReviewActive ||
        _pending != null ||
        _outcomeAwaitingRefresh != null ||
        _finalization?.request != null) {
      return false;
    }
    if (_finalization?.outcome is SupplierImportFinalizationCapacityExceeded &&
        _finalization?.attemptedRevision == loaded.resolution.root.revision) {
      return false;
    }
    return true;
  }

  bool get _canRetryFinalization {
    final current = _state;
    final pending = _finalization;
    if (_disposed ||
        current is! SupplierImportReviewFailed ||
        current.recovery !=
            SupplierImportReviewRecovery.retryPendingFinalization ||
        pending?.phase != SupplierImportReviewFinalizationPhase.ambiguous ||
        pending?.request == null ||
        current.loaded == null ||
        _pending != null) {
      return false;
    }
    return true;
  }

  Future<SupplierImportReviewError?> _beginFinalization() async {
    if (!canFinalizeReview) {
      return SupplierImportReviewController._invalidAction;
    }
    final loaded = _state.loaded! as SupplierImportReviewActive;
    SupplierImportFinalizationRequest request;
    try {
      request = SupplierImportFinalizationRequest(
        tripId: tripId,
        extractionId: extractionId,
        commandId: _generateCommandId(),
        expectedRevision: loaded.resolution.root.revision,
      );
    } catch (_) {
      _finalization = const SupplierImportReviewFinalizationState.failure();
      return _fail(
        const SupplierImportReviewError(
          SupplierImportReviewErrorKind.invalidMutation,
        ),
        loaded,
      );
    }
    return _executeFinalization(request, loaded);
  }

  Future<SupplierImportReviewError?> _retryFinalization() async {
    if (!canRetryPendingFinalization) {
      return SupplierImportReviewController._invalidAction;
    }
    final current = _state;
    final pending = _finalization;
    return _executeFinalization(pending!.request!, current.loaded!);
  }

  Future<SupplierImportReviewError?> _executeFinalization(
    SupplierImportFinalizationRequest request,
    SupplierImportReviewLoaded previous,
  ) async {
    final operation = ++_operation;
    _finalization = SupplierImportReviewFinalizationState.finalizing(request);
    _emit(
      SupplierImportReviewFinalizing(previous, finalization: _finalization),
    );
    if (!_isCurrent(operation)) {
      return SupplierImportReviewController._invalidAction;
    }
    SupplierImportFinalizationOutcome outcome;
    try {
      outcome = await _finalizations!.execute(request);
    } catch (error) {
      if (!_isCurrent(operation)) {
        return SupplierImportReviewController._invalidAction;
      }
      final failure = error is SupplierImportFinalizationFailure
          ? error
          : const SupplierImportFinalizationFailure(
              SupplierImportFinalizationFailureKind.unavailable,
            );
      _finalization = failure.isAmbiguous
          ? SupplierImportReviewFinalizationState.ambiguous(request)
          : const SupplierImportReviewFinalizationState.failure();
      return _fail(
        SupplierImportReviewError.finalization(failure),
        previous,
        recovery: failure.isAmbiguous
            ? SupplierImportReviewRecovery.retryPendingFinalization
            : SupplierImportReviewRecovery.refresh,
      );
    }
    if (!_isCurrent(operation)) {
      return SupplierImportReviewController._invalidAction;
    }
    if (outcome.resolutionId != extractionId ||
        outcome is SupplierImportFinalizationSuccess &&
            outcome.revision != request.expectedRevision + 1 ||
        outcome is SupplierImportFinalizationNotReady &&
            outcome.evaluatedRevision != request.expectedRevision) {
      // A malformed acknowledgement does not prove that the command failed.
      _finalization = SupplierImportReviewFinalizationState.ambiguous(request);
      return _fail(
        SupplierImportReviewController._malformed,
        previous,
        recovery: SupplierImportReviewRecovery.retryPendingFinalization,
      );
    }
    _finalization = SupplierImportReviewFinalizationState.awaitingReload(
      outcome,
      attemptedRevision: request.expectedRevision,
      request: outcome is SupplierImportFinalizationSuccess ? request : null,
    );
    // Keep all follow-up reads inside the same exclusive operation.
    _emit(
      SupplierImportReviewFinalizing(previous, finalization: _finalization),
    );
    if (!_isCurrent(operation)) {
      return SupplierImportReviewController._invalidAction;
    }
    return _reloadResolution(operation, previous);
  }

  void _verifyFinalizationResolution(SupplierImportReviewLoaded loaded) {
    if (_finalization?.phase !=
        SupplierImportReviewFinalizationPhase.awaitingReload) {
      return;
    }
    final outcome = _finalization?.outcome;
    if (outcome is SupplierImportFinalizationSuccess) {
      if (loaded is! SupplierImportReviewFinalized ||
          loaded.resolution.root.revision != outcome.revision ||
          loaded.resolution.root.resultingDraftId != outcome.resultingDraftId) {
        throw const FormatException('Finalization linkage is inconsistent.');
      }
    } else if (outcome is SupplierImportFinalizationFinalized) {
      if (loaded is! SupplierImportReviewFinalized ||
          loaded.resolution.root.revision != outcome.revision) {
        throw const FormatException('Finalized Resolution is not visible.');
      }
    }
  }

  Future<SupplierImportReviewFinalized> _readFinalizedDraft(
    SupplierImportReviewFinalized loaded,
  ) async {
    final root = loaded.resolution.root;
    final draft = await _drafts!.getDraft(tripId, root.resultingDraftId!);
    final imported = draft.importResult;
    final expected =
        _finalization?.phase ==
                SupplierImportReviewFinalizationPhase.awaitingReload &&
            _finalization?.outcome is SupplierImportFinalizationSuccess
        ? _finalization?.request
        : null;
    if (draft.tripId != tripId ||
        draft.id != root.resultingDraftId ||
        imported.extractionId != extractionId ||
        imported.resolutionId != root.resolutionId ||
        imported.sourcePackageId != root.sourcePackageId ||
        imported.evaluatedRevision != root.revision - 1 ||
        (expected != null &&
            (imported.finalizationId != expected.commandId ||
                imported.evaluatedRevision != expected.expectedRevision ||
                imported.policyVersion != expected.policyVersion))) {
      throw const ItineraryDraftV2RepositoryFailure(
        ItineraryDraftV2RepositoryFailureKind.identityMismatch,
      );
    }
    return SupplierImportReviewFinalized(
      loaded.snapshot,
      loaded.resolution,
      draft: draft,
    );
  }

  SupplierImportReviewLoaded _withFinalization(
    SupplierImportReviewLoaded loaded,
  ) => switch (loaded) {
    SupplierImportReviewNotStarted() => SupplierImportReviewNotStarted(
      loaded.snapshot,
      finalization: _finalization,
    ),
    SupplierImportReviewActive(:final resolution) => SupplierImportReviewActive(
      loaded.snapshot,
      resolution,
      finalization: _finalization,
    ),
    SupplierImportReviewFinalized(:final resolution, :final draft) =>
      SupplierImportReviewFinalized(
        loaded.snapshot,
        resolution,
        draft: draft,
        finalization: _finalization,
      ),
  };
}
