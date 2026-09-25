import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_app_header.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../../../clients/data/client_repository.dart';
import '../../../clients/presentation/pages/clients_page.dart';
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
    this.clientRepository,
  });

  final KayraUser user;
  final VoidCallback onSignOut;
  final bool isSigningOut;
  final UserProfileRepository userProfileRepository;
  final ClientRepository? clientRepository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

enum _WorkspacePage { myTrips, clients, admin }

class _DashboardPageState extends State<DashboardPage> {
  _WorkspacePage _page = _WorkspacePage.myTrips;
  late final ClientRepository _clients =
      widget.clientRepository ?? FirestoreClientRepository();

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        (_page == _WorkspacePage.admin && !widget.user.isActiveAdmin)) {
      _page = _WorkspacePage.myTrips;
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
              onMyTrips: () => setState(() => _page = _WorkspacePage.myTrips),
              onClients: () => setState(() => _page = _WorkspacePage.clients),
              isClientsSelected: _page == _WorkspacePage.clients,
              onAdmin: user.isActiveAdmin
                  ? () => setState(() => _page = _WorkspacePage.admin)
                  : null,
              isAdminSelected:
                  _page == _WorkspacePage.admin && user.isActiveAdmin,
              maxContentWidth: AppLayout.dashboardMaxContentWidth,
              onPreviewAction: () => _showUnavailableMessage(context),
            ),
            Expanded(
              child: _page == _WorkspacePage.admin && user.isActiveAdmin
                  ? UserManagementPage(
                      currentUser: user,
                      repository: widget.userProfileRepository,
                    )
                  : _page == _WorkspacePage.clients
                  ? ClientsPage(currentUser: user, repository: _clients)
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
