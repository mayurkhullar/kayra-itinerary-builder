import 'package:flutter/material.dart';
import '../../core/layout/app_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class KayraUserAvatar extends StatelessWidget {
  const KayraUserAvatar({
    super.key,
    required this.photoURL,
    required this.displayName,
    required this.email,
  });

  final String? photoURL;
  final String? displayName;
  final String? email;

  String get initials {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) {
      final address = email?.trim();
      return address == null || address.isEmpty
          ? 'K'
          : address.characters.take(2).toString().toUpperCase();
    }
    final words = name.split(RegExp(r'\s+'));
    return ('${words.first.characters.first}'
            '${words.length > 1 ? words.last.characters.first : ""}')
        .toUpperCase();
  }

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
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.navy),
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
