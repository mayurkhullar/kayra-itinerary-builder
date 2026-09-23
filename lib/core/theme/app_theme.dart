import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';

abstract final class AppTheme {
  static final ThemeData light = _buildLight();

  static ThemeData _buildLight() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: Brightness.light,
      primary: AppColors.navy,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.navyTint,
      onPrimaryContainer: AppColors.navy,
      secondary: AppColors.slate,
      onSecondary: AppColors.white,
      secondaryContainer: AppColors.navyTint,
      onSecondaryContainer: AppColors.navy,
      tertiary: AppColors.navyDeep,
      onTertiary: AppColors.white,
      tertiaryContainer: AppColors.navyTint,
      onTertiaryContainer: AppColors.navy,
      surface: AppColors.white,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.white,
      surfaceContainerLow: AppColors.background,
      surfaceContainer: AppColors.background,
      surfaceContainerHigh: AppColors.navyTint,
      surfaceContainerHighest: AppColors.navyTint,
      surfaceTint: Colors.transparent,
      outline: AppColors.textSecondary,
      outlineVariant: AppColors.border,
      inverseSurface: AppColors.navyDeep,
      onInverseSurface: AppColors.inkOnNavy,
      inversePrimary: AppColors.navyTint,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final textTheme = base.textTheme
        .merge(
          const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 40,
              height: 1.16,
              fontWeight: FontWeight.w500,
              letterSpacing: -1.3,
            ),
            headlineMedium: TextStyle(
              fontSize: 30,
              height: 1.22,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.75,
            ),
            headlineSmall: TextStyle(
              fontSize: 24,
              height: 1.3,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
            titleLarge: TextStyle(
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.45,
            ),
            titleMedium: TextStyle(
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: TextStyle(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: TextStyle(fontSize: 16, height: 1.65),
            bodyMedium: TextStyle(fontSize: 14, height: 1.6),
            labelLarge: TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
            labelMedium: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .merge(
          const TextTheme(
            bodySmall: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
            labelSmall: TextStyle(
              fontSize: 11,
              height: 1.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: AppColors.navy,
            ),
          ),
        );
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.r8)),
    );
    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.r10)),
      borderSide: BorderSide(color: AppColors.border),
    );

    return base.copyWith(
      textTheme: textTheme,
      dividerColor: AppColors.border,
      focusColor: AppColors.navy.withValues(alpha: 0.12),
      hoverColor: AppColors.navy.withValues(alpha: 0.04),
      appBarTheme: const AppBarThemeData(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.r12)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: AppColors.white,
              minimumSize: const Size(AppSpacing.s48, AppSpacing.s48),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              shape: buttonShape,
              elevation: 0,
              textStyle: textTheme.labelLarge,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? const BorderSide(color: AppColors.navyTint, width: 2)
                    : BorderSide.none,
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: AppColors.navy,
              backgroundColor: AppColors.white,
              minimumSize: const Size(AppSpacing.s48, AppSpacing.s48),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              shape: buttonShape,
              textStyle: textTheme.labelLarge,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? const BorderSide(color: AppColors.navy, width: 2)
                    : const BorderSide(color: AppColors.border),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: AppColors.navy,
              minimumSize: const Size(AppSpacing.s48, AppSpacing.s48),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s12,
              ),
              shape: buttonShape,
              textStyle: textTheme.labelLarge,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? const BorderSide(color: AppColors.navy, width: 1.5)
                    : BorderSide.none,
              ),
            ),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.navy,
        size: AppSpacing.s20,
      ),
      iconButtonTheme: IconButtonThemeData(
        style:
            IconButton.styleFrom(
              foregroundColor: AppColors.navy,
              minimumSize: const Size(AppSpacing.s48, AppSpacing.s48),
              shape: buttonShape,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? const BorderSide(color: AppColors.navy, width: 1.5)
                    : BorderSide.none,
              ),
            ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s16,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.navy,
        ),
        prefixIconColor: AppColors.textSecondary,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.navy, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.navy,
        selectionColor: AppColors.navy.withValues(alpha: 0.16),
        selectionHandleColor: AppColors.navy,
      ),
    );
  }
}
