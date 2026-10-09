import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/kayra_content_frame.dart';
import '../../../domain/itinerary_draft_v2.dart';
import '../supplier_import/review_components.dart';
import 'canonical_package_content.dart';
import 'canonical_service.dart';

/// Internal read-only handoff. The controller verifies the draft before entry.
/// This is not a public/proposal projection and performs no data access.
class FinalizedCanonicalView extends StatelessWidget {
  const FinalizedCanonicalView({
    super.key,
    required this.draft,
    required this.onBack,
    required this.onRefresh,
  });
  final ItineraryDraftV2 draft;
  final VoidCallback onBack, onRefresh;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('finalized-canonical-scroll'),
    child: KayraContentFrame(
      maxWidth: 960,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.s16,
              runSpacing: AppSpacing.s12,
              children: [
                TextButton.icon(
                  key: const ValueKey('back-to-trip-workspace'),
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to Trip Workspace'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('refresh-supplier-review'),
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s24),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                'Itinerary finalized',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            const Text(
              'This is the itinerary created from the reviewed supplier information. Read-only.',
            ),
            const SizedBox(height: AppSpacing.s32),
            Semantics(
              header: true,
              child: Text(
                draft.title,
                key: const ValueKey('canonical-title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            if (draft.days.isNotEmpty)
              ReviewSection(
                title: 'Day-wise itinerary',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final day in draft.days) ...[
                      _CanonicalDay(day),
                      const SizedBox(height: AppSpacing.s16),
                    ],
                  ],
                ),
              ),
            if (draft.unscheduledServices case final services?
                when services.isNotEmpty)
              ReviewSection(
                title: 'Included Services',
                child: ReviewPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: reviewSeparated(
                      services.map(
                        (service) => CanonicalService(service: service),
                      ),
                    ),
                  ),
                ),
              ),
            CanonicalPackageContent(content: draft.packageContent),
          ],
        ),
      ),
    ),
  );
}

class _CanonicalDay extends StatelessWidget {
  const _CanonicalDay(this.day);
  final ItineraryDraftV2Day day;

  @override
  Widget build(BuildContext context) => ReviewPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.s12,
          runSpacing: AppSpacing.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ReviewBadge('Day ${day.dayNumber}'),
            if (day.date != null) Text(reviewDate(day.date)!),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        Semantics(
          header: true,
          child: Text(day.title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ReviewText(day.summary),
        ReviewText(day.notes, label: 'Day notes'),
        for (final service in day.services) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s20),
            child: Divider(),
          ),
          CanonicalService(service: service),
        ],
      ],
    ),
  );
}
