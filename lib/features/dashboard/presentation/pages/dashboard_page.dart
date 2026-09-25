import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../trips/data/trip_repository.dart';
import '../../../../shared/widgets/kayra_app_header.dart';
import '../../../clients/data/client_repository.dart';
import '../../../suppliers/data/supplier_repository.dart';
import '../../../suppliers/presentation/pages/suppliers_page.dart';
import '../../../clients/presentation/pages/clients_page.dart';
import '../../../users/domain/kayra_user.dart';
import '../../../users/data/user_profile_repository.dart';
import '../../../admin/presentation/pages/user_management_page.dart';
import '../../../trips/presentation/widgets/trips_workspace.dart';

/// The authenticated operational shell.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.user,
    required this.onSignOut,
    required this.userProfileRepository,
    this.isSigningOut = false,
    this.clientRepository,
    this.tripRepository,
    this.supplierRepository,
  });

  final KayraUser user;
  final VoidCallback onSignOut;
  final bool isSigningOut;
  final UserProfileRepository userProfileRepository;
  final ClientRepository? clientRepository;
  final TripRepository? tripRepository;
  final SupplierRepository? supplierRepository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

enum _WorkspacePage { myTrips, clients, suppliers, admin }

class _DashboardPageState extends State<DashboardPage> {
  _WorkspacePage _page = _WorkspacePage.myTrips;
  late final ClientRepository _clients =
      widget.clientRepository ?? FirestoreClientRepository();

  late final SupplierRepository _suppliers =
      widget.supplierRepository ?? FirestoreSupplierRepository();

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
              onSuppliers: () =>
                  setState(() => _page = _WorkspacePage.suppliers),
              isSuppliersSelected: _page == _WorkspacePage.suppliers,
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
                  : _page == _WorkspacePage.suppliers
                  ? SuppliersPage(currentUser: user, repository: _suppliers)
                  : TripsWorkspace(
                      currentUser: user,
                      tripRepository: widget.tripRepository,
                      clientRepository: widget.clientRepository,
                      onBrowse: () => _showUnavailableMessage(context),
                      onClients: () =>
                          setState(() => _page = _WorkspacePage.clients),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
