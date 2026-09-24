import 'package:flutter/material.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import 'kayra_logo.dart';

class KayraAppHeader extends StatelessWidget {
  const KayraAppHeader({
    super.key,
    required this.displayName,
    required this.email,
    required this.photoURL,
    required this.roleLabel,
    required this.onSignOut,
    required this.onPreviewAction,
    this.isSigningOut = false,
    this.maxContentWidth = AppLayout.maxContentWidth,
  });

  final String? displayName;
  final String? email;
  final String? photoURL;
  final String roleLabel;
  final VoidCallback onSignOut;
  final VoidCallback onPreviewAction;
  final bool isSigningOut;
  final double maxContentWidth;

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
                constraints: BoxConstraints(maxWidth: maxContentWidth),
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
                          tooltip: 'Notifications',
                          onPressed: onPreviewAction,
                          icon: const Icon(Icons.notifications_none_rounded),
                        ),
                        SizedBox(
                          width: isDesktop ? AppSpacing.s12 : AppSpacing.s4,
                        ),
                        _AccountMenu(
                          displayName: displayName,
                          email: email,
                          photoURL: photoURL,
                          roleLabel: roleLabel,
                          showName: isDesktop,
                          isSigningOut: isSigningOut,
                          onSignOut: onSignOut,
                        ),
                        if (!showNavigation) ...[
                          const SizedBox(width: AppSpacing.s4),
                          IconButton(
                            tooltip: 'Menu',
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

enum _AccountAction { signOut }

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.displayName,
    required this.email,
    required this.photoURL,
    required this.roleLabel,
    required this.showName,
    required this.isSigningOut,
    required this.onSignOut,
  });

  final String? displayName;
  final String? email;
  final String? photoURL;
  final String roleLabel;
  final bool showName;
  final bool isSigningOut;
  final VoidCallback onSignOut;

  String get _name {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? 'Kayra account' : name;
  }

  String get _initials {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) {
      final address = email?.trim();
      return address == null || address.isEmpty
          ? 'K'
          : address.characters.take(2).toString().toUpperCase();
    }
    final words = name.split(RegExp(r'\s+'));
    return '${words.first.characters.first}'
            '${words.length > 1 ? words.last.characters.first : ''}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PopupMenuButton<_AccountAction>(
      tooltip: isSigningOut ? 'Signing out' : 'Account menu',
      enabled: !isSigningOut,
      position: PopupMenuPosition.under,
      color: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.r12)),
        side: BorderSide(color: AppColors.border),
      ),
      onSelected: (action) {
        if (action == _AccountAction.signOut && !isSigningOut) onSignOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<_AccountAction>(
          enabled: false,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Signed in as', style: textTheme.bodySmall),
              const SizedBox(height: AppSpacing.s4),
              Text(email ?? 'Email unavailable', style: textTheme.bodyMedium),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_AccountAction>(
          value: _AccountAction.signOut,
          enabled: !isSigningOut,
          height: AppSpacing.s48,
          child: Text('Sign out', style: textTheme.labelLarge),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.s48,
          minHeight: AppSpacing.s48,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSigningOut)
                const SizedBox.square(
                  dimension: AppLayout.avatarSize,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.s8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                _AccountAvatar(photoURL: photoURL, initials: _initials),
              if (showName) ...[
                const SizedBox(width: AppSpacing.s12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelLarge,
                      ),
                      Text(roleLabel, style: textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.photoURL, required this.initials});

  final String? photoURL;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: AppColors.navyTint,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initials,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
      ),
    );
    final photo = photoURL?.trim();

    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: AppLayout.avatarSize,
          child: photo == null || photo.isEmpty
              ? fallback
              : Image.network(
                  photo,
                  fit: BoxFit.cover,
                  frameBuilder: (context, child, frame, synchronouslyLoaded) =>
                      frame == null ? fallback : child,
                  errorBuilder: (context, error, stackTrace) => fallback,
                ),
        ),
      ),
    );
  }
}
