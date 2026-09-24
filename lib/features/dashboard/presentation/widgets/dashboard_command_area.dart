import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';

class DashboardCommandArea extends StatelessWidget {
  const DashboardCommandArea({
    super.key,
    required this.displayName,
    required this.onCreateItinerary,
    required this.onBrowseItineraries,
  });

  final String? displayName;
  final VoidCallback onCreateItinerary;
  final VoidCallback onBrowseItineraries;

  String get _greeting {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return 'Good to see you.';
    final firstName = name.split(RegExp(r'\s+')).first;
    return 'Good to see you, $firstName.';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < AppLayout.mobileBreakpoint;
        final inline =
            constraints.maxWidth >= AppLayout.dashboardCommandBreakpoint &&
            MediaQuery.textScalerOf(context).scale(16) <= 20;
        final actions = _CommandActions(
          onNavy: inline,
          onCreateItinerary: onCreateItinerary,
          onBrowseItineraries: onBrowseItineraries,
        );
        final greeting = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                _greeting,
                style: textTheme.headlineMedium?.copyWith(
                  fontSize: mobile ? 28 : 32,
                  color: AppColors.inkOnNavy,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Here’s what needs your attention and what’s coming up.',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.subtleOnNavy,
              ),
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: AppColors.navy,
              child: KayraContentFrame(
                maxWidth: AppLayout.dashboardMaxContentWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: inline ? 172 : 190),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: inline ? AppSpacing.s16 : AppSpacing.s24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (inline)
                          Row(
                            children: [
                              Expanded(child: greeting),
                              const SizedBox(width: AppSpacing.s24),
                              actions,
                            ],
                          )
                        else
                          greeting,
                        if (!mobile) ...[
                          SizedBox(
                            height: inline ? AppSpacing.s16 : AppSpacing.s24,
                          ),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: _CommandSearch(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!inline)
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: KayraContentFrame(
                  maxWidth: AppLayout.dashboardMaxContentWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mobile) ...[
                          const _CommandSearch(),
                          const SizedBox(height: AppSpacing.s16),
                        ],
                        actions,
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CommandSearch extends StatelessWidget {
  const _CommandSearch();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppLayout.dashboardSearchMaxWidth,
      ),
      child: const TextField(
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search clients, trips, destinations or quote references',
          hintMaxLines: 2,
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
    );
  }
}

class _CommandActions extends StatelessWidget {
  const _CommandActions({
    required this.onNavy,
    required this.onCreateItinerary,
    required this.onBrowseItineraries,
  });

  final bool onNavy;
  final VoidCallback onCreateItinerary;
  final VoidCallback onBrowseItineraries;

  @override
  Widget build(BuildContext context) {
    final primary = FilledButton(
      onPressed: onCreateItinerary,
      style: onNavy
          ? FilledButton.styleFrom(
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.navy,
            )
          : null,
      child: const Text('Create New Itinerary', textAlign: TextAlign.center),
    );
    final secondary = OutlinedButton(
      onPressed: onBrowseItineraries,
      style: onNavy
          ? OutlinedButton.styleFrom(
              foregroundColor: AppColors.white,
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: AppColors.subtleOnNavy),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: AppColors.subtleOnNavy,
                  width: states.contains(WidgetState.focused) ? 2 : 1,
                ),
              ),
            )
          : null,
      child: const Text(
        'Browse Reusable Itineraries',
        textAlign: TextAlign.center,
      ),
    );
    final stack =
        MediaQuery.sizeOf(context).width < AppLayout.mobileBreakpoint ||
        MediaQuery.textScalerOf(context).scale(16) > 20;

    return stack
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: AppSpacing.s12),
              secondary,
            ],
          )
        : onNavy
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              primary,
              const SizedBox(width: AppSpacing.s12),
              secondary,
            ],
          )
        : Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s12,
            children: [primary, secondary],
          );
  }
}
