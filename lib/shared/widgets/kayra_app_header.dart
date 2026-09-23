import 'package:flutter/material.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import 'kayra_logo.dart';

class KayraAppHeader extends StatelessWidget {
  const KayraAppHeader({super.key, required this.onPreviewAction});

  final VoidCallback onPreviewAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppLayout.mobileBreakpoint;
        final isDesktop = constraints.maxWidth >= AppLayout.desktopBreakpoint;
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final showNavigation =
            isDesktop &&
            textScale <= 1.25 &&
            constraints.maxWidth >= AppLayout.desktopBreakpoint * textScale;
        final padding = isMobile ? AppSpacing.s20 : AppSpacing.s40;

        return DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppLayout.maxContentWidth,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: isMobile
                        ? AppLayout.compactHeaderHeight
                        : AppLayout.desktopHeaderHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s4,
                    ),
                    child: Row(
                      children: [
                        KayraLogo(compact: isMobile),
                        if (showNavigation) ...[
                          SizedBox(
                            width:
                                constraints.maxWidth < AppLayout.maxContentWidth
                                ? AppSpacing.s24
                                : AppSpacing.s48,
                          ),
                          _NavigationPreview(onPressed: onPreviewAction),
                        ],
                        const Spacer(),
                        const SizedBox(width: AppSpacing.s8),
                        IconButton(
                          tooltip: 'Notifications preview',
                          onPressed: onPreviewAction,
                          icon: const Icon(Icons.notifications_none_rounded),
                        ),
                        if (isDesktop) ...[
                          const SizedBox(width: AppSpacing.s20),
                          const _AgentPlaceholder(),
                        ],
                        if (!showNavigation) ...[
                          const SizedBox(width: AppSpacing.s4),
                          IconButton(
                            tooltip: 'Menu preview',
                            onPressed: onPreviewAction,
                            icon: const Icon(Icons.menu_rounded),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavigationPreview extends StatelessWidget {
  const _NavigationPreview({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _NavigationTab(label: 'My Trips', selected: true, onPressed: onPressed),
        const SizedBox(width: AppSpacing.s12),
        _NavigationTab(
          label: 'Reusable Itineraries',
          selected: false,
          onPressed: onPressed,
        ),
      ],
    );
  }
}

class _NavigationTab extends StatelessWidget {
  const _NavigationTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.navy : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: selected
                ? AppColors.navy
                : AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
            minimumSize: const Size(AppSpacing.s48, AppSpacing.s48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.r8),
            ),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _AgentPlaceholder extends StatelessWidget {
  const _AgentPlaceholder();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: 'Agent profile placeholder',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: AppLayout.avatarSize / 2,
            backgroundColor: AppColors.navyTint,
            foregroundColor: AppColors.navy,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('KA', style: textTheme.labelSmall),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kayra Agent', style: textTheme.labelLarge),
              Text(
                'Agent',
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
