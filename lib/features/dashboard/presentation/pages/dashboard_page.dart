import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_app_header.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../../../users/domain/kayra_user.dart';
import '../../../users/data/user_profile_repository.dart';
import '../../../admin/presentation/pages/user_management_page.dart';
import '../widgets/dashboard_command_area.dart';
import '../widgets/dashboard_sections.dart';

/// The authenticated operational shell, ready for future trip data.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.user,
    required this.onSignOut,
    required this.userProfileRepository,
    this.isSigningOut = false,
  });

  final KayraUser user;
  final VoidCallback onSignOut;
  final bool isSigningOut;
  final UserProfileRepository userProfileRepository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _showAdmin = false;

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid || !widget.user.isActiveAdmin) {
      _showAdmin = false;
    }
  }

  void _showUnavailableMessage(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('This feature is not available yet.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            KayraAppHeader(
              displayName: user.displayName,
              email: user.email,
              photoURL: user.photoUrl,
              roleLabel: user.role.label,
              onSignOut: widget.onSignOut,
              isSigningOut: widget.isSigningOut,
              onMyTrips: () => setState(() => _showAdmin = false),
              onAdmin: user.isActiveAdmin
                  ? () => setState(() => _showAdmin = true)
                  : null,
              isAdminSelected: _showAdmin && user.isActiveAdmin,
              maxContentWidth: AppLayout.dashboardMaxContentWidth,
              onPreviewAction: () => _showUnavailableMessage(context),
            ),
            Expanded(
              child: _showAdmin && user.isActiveAdmin
                  ? UserManagementPage(
                      currentUser: user,
                      repository: widget.userProfileRepository,
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DashboardCommandArea(
                            displayName: user.displayName,
                            onCreateItinerary: () =>
                                _showUnavailableMessage(context),
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
