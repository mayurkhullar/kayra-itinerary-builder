import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../dashboard/presentation/widgets/travel_route_motif.dart';
import '../widgets/google_sign_in_button.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({
    super.key,
    required this.onSignIn,
    this.isSigningIn = false,
    this.errorMessage,
  });

  final VoidCallback onSignIn;
  final bool isSigningIn;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop =
                constraints.maxWidth >= AppLayout.desktopBreakpoint;
            final outerSpace = ((constraints.maxWidth - 1440) / 2).clamp(
              0.0,
              double.infinity,
            );
            final authentication = _AuthenticationContent(
              isDesktop: isDesktop,
              onSignIn: onSignIn,
              isSigningIn: isSigningIn,
              errorMessage: errorMessage,
            );

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: isDesktop
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Extend the panel colors while keeping the actual
                            // composition within 1440px on large screens.
                            if (outerSpace > 0)
                              SizedBox(
                                width: outerSpace,
                                child: const ColoredBox(color: AppColors.navy),
                              ),
                            const Expanded(
                              flex: 47,
                              child: _EditorialPanel(isDesktop: true),
                            ),
                            Expanded(flex: 53, child: authentication),
                            if (outerSpace > 0) SizedBox(width: outerSpace),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _EditorialPanel(isDesktop: false),
                          authentication,
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EditorialPanel extends StatelessWidget {
  const _EditorialPanel({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Journeys, beautifully organised.',
          style: textTheme.headlineLarge?.copyWith(
            color: AppColors.inkOnNavy,
            fontSize: isDesktop ? 42 : 30,
            height: 1.2,
            letterSpacing: isDesktop ? -1.2 : -0.75,
          ),
        ),
        if (isDesktop) ...[
          const SizedBox(height: AppSpacing.s20),
          Text(
            'Build, review and manage exceptional travel itineraries from one Kayra workspace.',
            style: textTheme.bodyLarge?.copyWith(color: AppColors.subtleOnNavy),
          ),
          const SizedBox(height: AppSpacing.s40),
          const Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: 300, child: TravelRouteMotif()),
          ),
        ],
      ],
    );

    return ColoredBox(
      color: AppColors.navy,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 212),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? AppSpacing.s64 : AppSpacing.s20,
            vertical: isDesktop ? AppSpacing.s48 : AppSpacing.s24,
          ),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: isDesktop
                  ? Center(child: copy)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: AppSpacing.s64,
                            child: TravelRouteMotif(compact: true),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s24),
                        copy,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthenticationContent extends StatelessWidget {
  const _AuthenticationContent({
    required this.isDesktop,
    required this.onSignIn,
    required this.isSigningIn,
    required this.errorMessage,
  });

  final bool isDesktop;
  final VoidCallback onSignIn;
  final bool isSigningIn;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final logoWidth = isDesktop ? 208.0 : 176.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? AppSpacing.s48 : AppSpacing.s20,
        vertical: isDesktop ? AppSpacing.s48 : AppSpacing.s32,
      ),
      child: Align(
        alignment: isDesktop ? Alignment.center : Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/brand/kayra_logo.png',
                  width: logoWidth,
                  height: logoWidth * 323 / 777,
                  fit: BoxFit.contain,
                  semanticLabel: 'Kayra Holiday Maps',
                ),
              ),
              SizedBox(height: isDesktop ? AppSpacing.s40 : AppSpacing.s32),
              GoogleSignInButton(onPressed: onSignIn, isSigningIn: isSigningIn),
              if (errorMessage != null) ...[
                const SizedBox(height: AppSpacing.s16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    errorMessage!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s16),
              Text(
                'Access is restricted to authorised @kholidaymaps.com accounts.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
