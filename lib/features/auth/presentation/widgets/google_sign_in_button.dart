import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isSigningIn = false,
  });

  final VoidCallback onPressed;
  final bool isSigningIn;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: isSigningIn,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: isSigningIn ? null : onPressed,
          style:
              OutlinedButton.styleFrom(
                foregroundColor: AppColors.white,
                backgroundColor: AppColors.navy,
                disabledForegroundColor: AppColors.subtleOnNavy,
                disabledBackgroundColor: AppColors.slate,
                overlayColor: AppColors.white,
                minimumSize: const Size(AppSpacing.s48, 52),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s20,
                  vertical: AppSpacing.s12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.r10),
                ),
              ).copyWith(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return AppColors.slate;
                  }
                  if (states.contains(WidgetState.pressed)) {
                    return AppColors.navyDeep;
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return AppColors.slate;
                  }
                  return AppColors.navy;
                }),
                side: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.focused)) {
                    return const BorderSide(
                      color: AppColors.subtleOnNavy,
                      width: 2,
                    );
                  }
                  return BorderSide.none;
                }),
              ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isSigningIn) ...[
                const ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: AppSpacing.s16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.subtleOnNavy,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
              ],
              Flexible(
                child: Text(
                  isSigningIn ? 'Signing in…' : 'Continue with Google',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
