import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_app_header.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../../../users/domain/kayra_user.dart';
import '../widgets/dashboard_command_area.dart';
import '../widgets/dashboard_sections.dart';

/// The authenticated operational shell, ready for future trip data.
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.user,
    required this.onSignOut,
    this.isSigningOut = false,
  });

  final KayraUser user;
  final VoidCallback onSignOut;
  final bool isSigningOut;

  void _showUnavailableMessage(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('This feature is not available yet.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            KayraAppHeader(
              displayName: user.displayName,
              email: user.email,
              photoURL: user.photoUrl,
              roleLabel: user.role.label,
              onSignOut: onSignOut,
              isSigningOut: isSigningOut,
              maxContentWidth: AppLayout.dashboardMaxContentWidth,
              onPreviewAction: () => _showUnavailableMessage(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DashboardCommandArea(
                      displayName: user.displayName,
                      onCreateItinerary: () => _showUnavailableMessage(context),
                      onBrowseItineraries: () =>
                          _showUnavailableMessage(context),
                    ),
                    KayraContentFrame(
                      maxWidth: AppLayout.dashboardMaxContentWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const NeedsAttentionSection(),
                            const SizedBox(height: AppSpacing.s32),
                            MyTripsSection(
                              onCreateItinerary: () =>
                                  _showUnavailableMessage(context),
                            ),
                            const SizedBox(height: AppSpacing.s16),
                            ReusableItinerariesPanel(
                              onBrowseItineraries: () =>
                                  _showUnavailableMessage(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
