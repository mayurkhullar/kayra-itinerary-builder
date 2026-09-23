import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';

class WorkspacePreview extends StatelessWidget {
  const WorkspacePreview({super.key, required this.onPreviewAction});

  final VoidCallback onPreviewAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return KayraContentFrame(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final split =
              constraints.maxWidth >= AppLayout.workspaceSplitBreakpoint &&
              MediaQuery.textScalerOf(context).scale(16) <= 20;

          return Padding(
            padding: EdgeInsets.symmetric(
              vertical: split ? AppSpacing.s32 : AppSpacing.s24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Workspace preview',
                        style: textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s20),
                    const Expanded(child: Divider()),
                  ],
                ),
                SizedBox(height: split ? AppSpacing.s24 : AppSpacing.s20),
                if (split)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(flex: 3, child: _SearchPreview()),
                      const SizedBox(width: AppSpacing.s64),
                      Expanded(
                        flex: 2,
                        child: _ActionPreview(
                          framed: true,
                          onPressed: onPreviewAction,
                        ),
                      ),
                    ],
                  )
                else ...[
                  const _SearchPreview(),
                  const SizedBox(height: AppSpacing.s24),
                  _ActionPreview(framed: false, onPressed: onPreviewAction),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SearchPreview extends StatelessWidget {
  const _SearchPreview();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Find anything quickly', style: textTheme.titleLarge),
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'Search trips, clients, destinations and quotations.',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s24),
        const TextField(
          decoration: InputDecoration(
            labelText: 'Search',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ],
    );
  }
}

class _ActionPreview extends StatelessWidget {
  const _ActionPreview({required this.framed, required this.onPressed});

  final bool framed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: onPressed,
          child: const Text(
            'Create New Itinerary',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        OutlinedButton(
          onPressed: onPressed,
          child: const Text(
            'Browse Reusable Itineraries',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    if (!framed) return actions;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.navyTint.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: actions,
      ),
    );
  }
}
