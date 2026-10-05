import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import 'review_components.dart';

class ReviewSummary extends StatelessWidget {
  const ReviewSummary({super.key, required this.snapshot});
  final SupplierExtractionSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final counts = snapshot.counts;
    final blockers = snapshot.reviewIssues
        .where(
          (issue) => issue.severity == SupplierExtractionReviewSeverity.blocker,
        )
        .length;
    final rows = <(String, int)>[
      ('Days', counts.days),
      ('Services', counts.assignedServices + counts.unassignedServices),
      ('Unassigned services', counts.unassignedServices),
      ('Package facts', counts.packageFacts),
      ('Flights', counts.ancillaryFlights),
      ('Visa facts', counts.ancillaryVisas),
      ('Review issues', counts.reviewIssues),
      ('Blockers', blockers),
      ('Warnings', snapshot.reviewIssues.length - blockers),
    ];
    return ReviewPanel(
      key: const ValueKey('review-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Extraction summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Original supplier content',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s16),
          for (final (label, count) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: Semantics(
                label: '$label: $count',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Expanded(child: Text(label)),
                    const SizedBox(width: AppSpacing.s12),
                    Text(
                      '$count',
                      key: ValueKey('review-count-$label'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SnapshotReviewIssues extends StatelessWidget {
  const SnapshotReviewIssues({super.key, required this.snapshot});
  final SupplierExtractionSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final issues = [...snapshot.reviewIssues]
      ..sort((a, b) {
        final severity = b.severity.index.compareTo(a.severity.index);
        return severity != 0
            ? severity
            : a.snapshotOrder.compareTo(b.snapshotOrder);
      });
    return ReviewSection(
      key: const ValueKey('review-issues'),
      title: 'Needs attention',
      child: ReviewPanel(
        child: issues.isEmpty
            ? const Text('No review issues were flagged in this extraction.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: reviewSeparated(
                  issues.map(
                    (issue) => Column(
                      key: ValueKey('review-issue-${issue.id}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: AppSpacing.s8,
                          runSpacing: AppSpacing.s8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ReviewBadge(
                              reviewLabel(issue.severity.value),
                              strong:
                                  issue.severity ==
                                  SupplierExtractionReviewSeverity.blocker,
                            ),
                            if (issue.resolutionRequired)
                              Text(
                                'Resolution required',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        Text(issue.message),
                        ReviewFields([
                          (
                            'Context',
                            reviewEntityLabel(snapshot, issue.target.entityId),
                          ),
                          ('Issue', reviewLabel(issue.code.value)),
                        ]),
                        ReviewSources(issue.sources),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

String reviewEntityLabel(SupplierExtractionSnapshot snapshot, String? id) {
  if (id == null) return 'Whole extraction';
  if (id == 'title') return 'Itinerary title';
  for (final day in snapshot.days) {
    if (day.id == id) {
      return day.title ??
          (day.sourceDayNumber == null
              ? 'Source day'
              : 'Source day ${day.sourceDayNumber}');
    }
  }
  for (final fact in snapshot.facts) {
    if (fact.id != id) continue;
    return switch (fact) {
      SupplierExtractionServiceFact() =>
        fact.title ??
            fact.hotelDetails?.hotelName ??
            fact.activityDetails?.activityName ??
            'Service',
      SupplierExtractionPackageAccommodationFact() =>
        fact.details.hotelName ?? 'Package accommodation',
      SupplierExtractionPackageStatementFact() =>
        fact.factKind == SupplierExtractionFactKind.packageInclusion
            ? 'Package inclusion'
            : 'Package exclusion',
      SupplierExtractionPackageConditionFact() => 'Package condition',
      SupplierExtractionFlightFact() =>
        fact.flightNumber ?? fact.airline ?? 'Flight',
      SupplierExtractionVisaFact() => 'Visa',
      SupplierExtractionCommercialPresenceFact() => 'Commercial information',
    };
  }
  return 'Review issue';
}
