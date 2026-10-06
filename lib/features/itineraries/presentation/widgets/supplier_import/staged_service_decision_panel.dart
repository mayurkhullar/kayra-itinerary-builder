import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../controllers/supplier_import_review_state.dart';
import 'review_components.dart';
import 'staged_service_corrections.dart';
import 'staged_service_review_data.dart';

/// Consultant intent stays separate from the immutable source content above.
class StagedServiceDecisionPanel extends StatelessWidget {
  const StagedServiceDecisionPanel({
    super.key,
    required this.service,
    required this.review,
    required this.onReview,
  });
  final SupplierExtractionServiceFact service;
  final StagedServiceReviewData review;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final decision = review.decisionFor(service.id);
    final pending = review.isPending(service.id);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewFields([
            ('Source placement', review.sourcePlacement(service)),
            ('Consultant decision', review.decisionLabel(service)),
            if (decision?.exclusionReason case final reason?)
              ('Exclusion reason', exclusionReasonLabel(reason)),
            ('Exclusion note', decision?.exclusionNote),
          ]),
          StagedServiceCorrections(service: service, review: review),
          if (pending)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s8),
                child: Text(
                  review.state is SupplierImportReviewSaving
                      ? 'Saving decision…'
                      : 'Awaiting review confirmation. See the review notice above.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          if (review.canReview)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s8),
                child: OutlinedButton(
                  key: ValueKey('service-review-action-${service.id}'),
                  onPressed: onReview,
                  child: Text(
                    review.sourceDayId(service) == null && decision == null
                        ? 'Assign or exclude'
                        : 'Review service',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
