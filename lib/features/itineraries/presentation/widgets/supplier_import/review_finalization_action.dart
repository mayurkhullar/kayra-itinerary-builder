import 'package:flutter/material.dart';

import '../../../../../core/layout/app_layout.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/kayra_content_frame.dart';
import '../../../domain/supplier_import_finalization.dart';
import '../../controllers/supplier_import_review_finalization_state.dart';
import '../../controllers/supplier_import_review_state.dart';
import 'finalization_finding_label.dart';

/// Presentation of controller-owned outcomes. No reads or readiness assessment.
class ReviewFinalizationAction extends StatelessWidget {
  const ReviewFinalizationAction({
    super.key,
    required this.state,
    required this.canFinalize,
    required this.canRetry,
    required this.onFinalize,
    required this.onRetry,
  });
  final SupplierImportReviewState state;
  final bool canFinalize;
  final bool canRetry;
  final VoidCallback onFinalize;
  final VoidCallback onRetry;

  static bool ownsNotice(SupplierImportReviewState state) =>
      state is SupplierImportReviewFinalizing ||
      state is SupplierImportReviewFinalized && state.draft != null ||
      state.finalization != null &&
          (state is SupplierImportReviewFailed ||
              state is SupplierImportReviewConflict);

  @override
  Widget build(BuildContext context) {
    final loaded = state.loaded;
    final finalizing = state is SupplierImportReviewFinalizing;
    final ambiguous =
        state.finalization?.phase ==
        SupplierImportReviewFinalizationPhase.ambiguous;
    final success =
        state is SupplierImportReviewFinalized &&
        (state as SupplierImportReviewFinalized).draft != null &&
        !ambiguous;
    final outcome = state.finalization?.outcome;
    // A previous assessment is not authoritative for a newer revision or while
    // the controller is reloading/mutating the review.
    final findings =
        state is SupplierImportReviewActive &&
            outcome is SupplierImportFinalizationNotReady &&
            outcome.evaluatedRevision ==
                (state as SupplierImportReviewActive).resolution.root.revision
        ? outcome
        : null;
    String? message;
    if (success) {
      message =
          'Supplier content is now a structured itinerary. This review is read-only.';
    } else if (ambiguous) {
      message =
          "We couldn't confirm whether finalization completed. Retry safely to check the same request.";
    } else if (state is SupplierImportReviewFailed &&
        state.finalization != null) {
      message = (state as SupplierImportReviewFailed).error.userMessage;
    } else if (state is SupplierImportReviewConflict &&
        outcome is SupplierImportFinalizationConflict) {
      message =
          'The review changed before finalization. Check the updated items and finalize again.';
    } else if (outcome is SupplierImportFinalizationCapacityExceeded &&
        loaded is SupplierImportReviewActive &&
        state.finalization?.attemptedRevision ==
            loaded.resolution.root.revision) {
      message = 'This itinerary is too large to finalize safely.';
    }
    if (loaded == null ||
        (!canFinalize &&
            !finalizing &&
            !ambiguous &&
            !success &&
            message == null)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: KayraContentFrame(
          maxWidth: AppLayout.dashboardMaxContentWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (findings != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${findings.blockers.length} ${findings.blockers.length == 1 ? 'item needs' : 'items need'} attention',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .18,
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('finalization-findings'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final finding in findings.blockers)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.s8,
                              ),
                              child: Text(
                                finalizationFindingLabel(finding.code.value),
                              ),
                            ),
                          if (findings.warnings.isNotEmpty) ...[
                            Text(
                              'Also worth checking',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            for (final warning in findings.warnings)
                              Text(
                                finalizationFindingLabel(warning.code.value),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                ],
                if (success)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Itinerary finalized',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                if (message != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(message, style: theme.textTheme.bodyMedium),
                  ),
                  if (canFinalize || ambiguous)
                    const SizedBox(height: AppSpacing.s12),
                ],
                if (canFinalize || finalizing || ambiguous)
                  Align(
                    alignment: Alignment.centerRight,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SizedBox(
                          width: constraints.maxWidth < 600
                              ? double.infinity
                              : null,
                          child: FilledButton(
                            key: const ValueKey('finalize-itinerary'),
                            onPressed: finalizing
                                ? null
                                : ambiguous
                                ? (canRetry ? onRetry : null)
                                : (canFinalize ? onFinalize : null),
                            child: Text(
                              finalizing
                                  ? 'Finalizing…'
                                  : ambiguous
                                  ? 'Retry finalization'
                                  : 'Finalize itinerary',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
