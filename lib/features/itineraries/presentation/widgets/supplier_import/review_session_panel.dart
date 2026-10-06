import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_import_resolution.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_manual_item.dart';
import '../../controllers/supplier_import_review_error.dart';
import '../../controllers/supplier_import_review_state.dart';
import 'review_components.dart';
import 'review_summary.dart';

String reviewStatusLabel(SupplierImportReviewLoaded loaded) => switch (loaded) {
  SupplierImportReviewNotStarted() => 'Not started',
  SupplierImportReviewActive() => 'Review in progress',
  SupplierImportReviewFinalized() => 'Finalized',
};

class ReviewSessionPanel extends StatelessWidget {
  const ReviewSessionPanel({
    super.key,
    required this.state,
    required this.onStart,
  });
  final SupplierImportReviewState state;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) {
    final loaded = state.loaded!;
    final saving = state is SupplierImportReviewSaving;
    final mayStart =
        state is SupplierImportReviewNotStarted ||
        (state is SupplierImportReviewConflict &&
            loaded is SupplierImportReviewNotStarted);
    final resolution = switch (loaded) {
      SupplierImportReviewActive(:final resolution) ||
      SupplierImportReviewFinalized(:final resolution) => resolution,
      SupplierImportReviewNotStarted() => null,
    };
    return ReviewPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Consultant review',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(switch (loaded) {
            SupplierImportReviewNotStarted() =>
              'Starting review creates the consultant review record. Viewing this page does not.',
            SupplierImportReviewActive() =>
              'Review service placement or exclude a service. Supplier source content stays unchanged.',
            SupplierImportReviewFinalized() =>
              'This review is finalized and locked. Original content and review history remain available.',
          }),
          if (mayStart ||
              (saving && loaded is SupplierImportReviewNotStarted)) ...[
            const SizedBox(height: AppSpacing.s16),
            FilledButton.icon(
              key: const ValueKey('start-supplier-review'),
              onPressed: mayStart && !saving ? onStart : null,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(saving ? 'Starting review…' : 'Start review'),
            ),
          ],
          if (resolution != null) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              '${resolution.decisions.length} recorded decisions · ${resolution.manualItems.length} consultant additions',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class ReviewStateNotice extends StatelessWidget {
  const ReviewStateNotice({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onRetry,
  });
  final SupplierImportReviewState state;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    String? message;
    String? title;
    Widget? action;
    if (state is SupplierImportReviewFailed) {
      final failed = state as SupplierImportReviewFailed;
      final retry =
          failed.recovery ==
              SupplierImportReviewRecovery.retryPendingMutation &&
          failed.pendingMutation != null;
      title = retry ? 'Request not confirmed' : 'Review unavailable';
      message = retry
          ? 'The result could not be confirmed. Retry the same request to check and complete it safely.'
          : switch (failed.error.kind) {
              SupplierImportReviewErrorKind.malformedData =>
                'This extraction cannot be displayed safely. Please reload or contact an administrator.',
              SupplierImportReviewErrorKind.snapshotLoad =>
                'The supplier extraction could not be loaded. Please try reloading.',
              _ => failed.error.userMessage,
            };
      action = OutlinedButton(
        key: ValueKey(retry ? 'retry-review-request' : 'reload-review'),
        onPressed: retry ? onRetry : onRefresh,
        child: Text(retry ? 'Retry same request' : 'Reload review'),
      );
    } else if (state is SupplierImportReviewConflict) {
      title = 'Review updated elsewhere';
      message =
          'This review changed elsewhere. The latest version has been reloaded.';
    } else if (state.loaded is SupplierImportReviewFinalized) {
      title = 'Finalized · Read-only';
      message =
          'This review is locked. You can view the original supplier content and recorded review history.';
    }
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s24),
      child: Semantics(
        liveRegion: true,
        child: ReviewPanel(
          key: const ValueKey('review-state-notice'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.s8),
              Text(message),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.s12),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ReviewHistory extends StatelessWidget {
  const ReviewHistory({super.key, required this.loaded});
  final SupplierImportReviewLoaded loaded;
  @override
  Widget build(BuildContext context) {
    final SupplierImportResolutionAggregate? resolution = switch (loaded) {
      SupplierImportReviewActive(:final resolution) ||
      SupplierImportReviewFinalized(:final resolution) => resolution,
      SupplierImportReviewNotStarted() => null,
    };
    if (resolution == null) return const SizedBox.shrink();
    return ReviewSection(
      key: const ValueKey('review-history'),
      title: 'Recorded review',
      subtitle:
          'Consultant decisions are separate from the original extraction above.',
      child: ReviewPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (resolution.decisions.isEmpty && resolution.manualItems.isEmpty)
              const Text('No consultant decisions have been recorded.'),
            for (final decision in resolution.decisions) ...[
              Text(
                reviewEntityLabel(
                  loaded.snapshot,
                  decision.payload.targetEntityId,
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_decisionStatus(decision.payload)),
              const SizedBox(height: AppSpacing.s12),
            ],
            for (final item in resolution.manualItems) ...[
              Text(switch (item.payload) {
                SupplierImportManualDay(:final title) ||
                SupplierImportManualService(:final title) => title,
              }, style: Theme.of(context).textTheme.titleSmall),
              const Text('Consultant-authored addition'),
              const SizedBox(height: AppSpacing.s12),
            ],
            ExpansionTile(
              key: const ValueKey('review-history-events'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Review history (${resolution.auditEvents.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              children: reviewSeparated(
                resolution.auditEvents.reversed.map(
                  (event) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(reviewLabel(event.action.value)),
                          Text(
                            reviewDate(event.occurredAt.toLocal())!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _decisionStatus(SupplierImportDecisionPayload decision) => reviewLabel(
  switch (decision) {
    SupplierImportTitleDecision() => decision.disposition.value,
    SupplierImportDayDecision() => decision.disposition.value,
    SupplierImportServiceDecision() => decision.disposition.value,
    SupplierImportPackageAccommodationDecision() => decision.disposition.value,
    SupplierImportPackageStatementDecision() => decision.disposition.value,
    SupplierImportPackageConditionDecision() => decision.disposition.value,
    SupplierImportFlightDecision() => decision.disposition.value,
    SupplierImportVisaDecision() => decision.disposition.value,
    SupplierImportReviewIssueDecision() => decision.outcome.value,
    _ => 'Recorded decision',
  },
);
