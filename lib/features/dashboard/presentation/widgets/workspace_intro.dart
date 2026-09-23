import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import 'travel_route_motif.dart';

class WorkspaceIntro extends StatelessWidget {
  const WorkspaceIntro({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.navy,
      child: KayraContentFrame(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide =
                constraints.maxWidth >= AppLayout.workspaceSplitBreakpoint;

            return Padding(
              padding: EdgeInsets.symmetric(
                vertical: isWide ? AppSpacing.s40 : AppSpacing.s24,
              ),
              child: isWide
                  ? Row(
                      children: [
                        const Expanded(
                          flex: 3,
                          child: _Introduction(isWide: true),
                        ),
                        const SizedBox(width: AppSpacing.s64),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: AppLayout.maxRouteMotifWidth,
                              ),
                              child: const TravelRouteMotif(),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const _Introduction(isWide: false),
            );
          },
        ),
      ),
    );
  }
}

class _Introduction extends StatelessWidget {
  const _Introduction({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'KAYRA WORKSPACE',
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.subtleOnNavy,
                ),
              ),
            ),
            if (!isWide) ...[
              const SizedBox(width: AppSpacing.s16),
              const SizedBox(
                width: AppSpacing.s64,
                child: TravelRouteMotif(compact: true),
              ),
            ],
          ],
        ),
        SizedBox(height: isWide ? AppSpacing.s24 : AppSpacing.s16),
        Semantics(
          header: true,
          child: Text(
            'Good to see you.',
            style: (isWide ? textTheme.headlineLarge : textTheme.headlineMedium)
                ?.copyWith(color: AppColors.inkOnNavy),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.maxIntroCopyWidth,
          ),
          child: Text(
            'Everything you need to build, review and manage remarkable journeys.',
            style: textTheme.bodyLarge?.copyWith(color: AppColors.subtleOnNavy),
          ),
        ),
      ],
    );
  }
}
