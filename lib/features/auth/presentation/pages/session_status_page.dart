import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/kayra_logo.dart';

class SessionStatusPage extends StatelessWidget {
  const SessionStatusPage({
    super.key,
    this.message,
    this.onRetry,
    this.onSignOut,
    this.isSigningOut = false,
  });

  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;
  final bool isSigningOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const KayraLogo(),
                  const SizedBox(height: 32),
                  if (message == null)
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Opening your Kayra workspace',
                      ),
                    )
                  else ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (onRetry != null)
                      FilledButton(
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    if (onSignOut != null)
                      TextButton(
                        onPressed: isSigningOut ? null : onSignOut,
                        child: Text(isSigningOut ? 'Signing out…' : 'Sign out'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
