import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../controllers/supplier_import_review_state.dart';
import 'review_components.dart';
import 'staged_day_corrections.dart';
import 'staged_day_review_data.dart';
import 'staged_service_review_data.dart';

class StagedDayDecisionPanel extends StatelessWidget {
  const StagedDayDecisionPanel({
    super.key,
    required this.day,
    required this.review,
    required this.onReview,
  });
  final SupplierExtractionStagedDay day;
  final StagedDayReviewData review;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final decision = review.decisionFor(day);
    return Column(
      key: ValueKey('day-decision-panel-${day.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewFields([
          ('Source position', '${day.order}'),
          ('Consultant decision', review.decisionLabel(day)),
          if (decision?.disposition == SupplierImportRetainDisposition.retain &&
              decision?.canonicalOrder != null)
            ('Consultant order', '${decision!.canonicalOrder}'),
          if (decision?.exclusionReason case final reason?)
            ('Exclusion reason', exclusionReasonLabel(reason)),
          ('Exclusion note', decision?.exclusionNote),
        ]),
        StagedDayCorrections(day: day, review: review),
        if (review.isPending(day))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                review.review.state is SupplierImportReviewSaving
                    ? 'Saving day decision…'
                    : 'Awaiting review confirmation. See the review notice above.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        if (review.review.canReview)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: OutlinedButton(
                key: ValueKey('day-review-action-${day.id}'),
                onPressed: onReview,
                child: const Text('Review day'),
              ),
            ),
          ),
      ],
    );
  }
}
