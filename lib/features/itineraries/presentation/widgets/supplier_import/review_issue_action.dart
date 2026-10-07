import 'package:flutter/material.dart';
import '../../../domain/supplier_import_finalization.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import '../../controllers/supplier_import_review_state.dart';

/// Renders only a fresh backend capability. No local evidence/readiness policy.
class ReviewIssueAction extends StatelessWidget {
  const ReviewIssueAction({
    super.key,
    required this.issueId,
    required this.state,
    required this.onOverride,
  });
  final String issueId;
  final SupplierImportReviewState state;
  final ValueChanged<SupplierImportReviewIssueDecision> onOverride;

  @override
  Widget build(BuildContext context) {
    final current = state;
    final outcome = current.finalization?.outcome;
    if (current is! SupplierImportReviewActive ||
        outcome is! SupplierImportFinalizationNotReady ||
        outcome.evaluatedRevision != current.resolution.root.revision ||
        !outcome.blockers.any(
          (f) =>
              f.targetKind ==
                  SupplierImportFinalizationTargetKind.reviewIssue &&
              f.targetId == issueId,
        ) ||
        !outcome.warnings.any(
          (f) =>
              f.code ==
                  SupplierImportFinalizationWarningCode
                      .reviewIssueOverrideAvailable &&
              f.targetId == issueId,
        )) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: ValueKey('override-review-issue-$issueId'),
        onPressed: () => onOverride(
          SupplierImportReviewIssueDecision(
            targetEntityId: issueId,
            outcome: SupplierImportReviewOutcome.overridden,
            resolutionReferences: const [],
            overrideReason: SupplierImportExclusionReason.other,
            overrideNote:
                'Use reviewed itinerary without changing supplier facts.',
          ),
        ),
        child: const Text('Use reviewed itinerary'),
      ),
    );
  }
}
