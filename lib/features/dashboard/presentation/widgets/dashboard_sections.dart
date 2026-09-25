import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class NeedsAttentionSection extends StatelessWidget {
  const NeedsAttentionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(
          title: 'Needs Attention',
          description:
              'Items that may need action before your upcoming journeys move forward.',
          // Preserve the heading rhythm; the optional action slot can be used
          // when real attention items and a View all action are available.
          action: null,
          minTitleHeight: AppSpacing.s48,
        ),
        const SizedBox(height: AppSpacing.s16),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s24,
              vertical: AppSpacing.s20,
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 28),
                const SizedBox(width: AppSpacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nothing needs your attention',
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        'You’re all caught up for now.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MyTripsSection extends StatelessWidget {
  const MyTripsSection({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(
          title: 'My Trips',
          description: 'Your upcoming and active journeys.',
        ),
        const SizedBox(height: AppSpacing.s16),
        child,
      ],
    );
  }
}

class ReusableItinerariesPanel extends StatelessWidget {
  const ReusableItinerariesPanel({
    super.key,
    required this.onBrowseItineraries,
  });

  final VoidCallback onBrowseItineraries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < AppLayout.mobileBreakpoint ||
            MediaQuery.textScalerOf(context).scale(16) > 20;
        const heading = _SectionHeading(
          title: 'Reusable Itineraries',
          description:
              'Start faster by adapting a previously approved itinerary.',
        );
        final action = TextButton(
          onPressed: onBrowseItineraries,
          child: const Text('Browse Library'),
        );

        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s16),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: AppSpacing.s8),
                    action,
                  ],
                )
              : Row(
                  children: [
                    const Expanded(child: heading),
                    const SizedBox(width: AppSpacing.s24),
                    action,
                  ],
                ),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.description,
    this.action,
    this.minTitleHeight = 0,
  });

  final String title;
  final String description;
  final Widget? action;
  final double minTitleHeight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minTitleHeight),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: textTheme.titleLarge),
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: AppSpacing.s8),
                action!,
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          description,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
