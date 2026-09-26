import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../trips/data/trip_repository.dart';
import '../../../../shared/widgets/kayra_app_header.dart';
import '../../../clients/data/client_repository.dart';
import '../../../suppliers/data/supplier_repository.dart';
import '../../../suppliers/presentation/pages/suppliers_page.dart';
import '../../../supplier_sources/data/supplier_source_repository.dart';
import '../../../clients/presentation/pages/clients_page.dart';
import '../../../users/domain/kayra_user.dart';
import '../../../users/data/user_profile_repository.dart';
import '../../../admin/presentation/pages/user_management_page.dart';
import '../../../trips/presentation/widgets/trips_workspace.dart';
import '../../../trips/presentation/pages/trip_workspace_page.dart';

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
    this.supplierSourceRepository,
  });

  final KayraUser user;
  final VoidCallback onSignOut;
  final bool isSigningOut;
  final UserProfileRepository userProfileRepository;
  final ClientRepository? clientRepository;
  final TripRepository? tripRepository;
  final SupplierRepository? supplierRepository;
  final SupplierSourceRepository? supplierSourceRepository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

enum _WorkspacePage { myTrips, clients, suppliers, admin }

class _DashboardPageState extends State<DashboardPage> {
  _WorkspacePage _page = _WorkspacePage.myTrips;
  String? _selectedTripId;
  late final ClientRepository _clients =
      widget.clientRepository ?? FirestoreClientRepository();

  TripRepository? _defaultTrips;
  TripRepository get _trips =>
      widget.tripRepository ??
      (_defaultTrips ??= FirestoreTripRepository(clientRepository: _clients));

  late final SupplierRepository _suppliers =
      widget.supplierRepository ?? FirestoreSupplierRepository();

  SupplierSourceRepository? _defaultSupplierSources;
  SupplierSourceRepository get _supplierSources =>
      widget.supplierSourceRepository ??
      (_defaultSupplierSources ??= FirestoreSupplierSourceRepository());

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.user.role != widget.user.role ||
        oldWidget.user.status != widget.user.status ||
        (_page == _WorkspacePage.admin && !widget.user.isActiveAdmin)) {
      _page = _WorkspacePage.myTrips;
      _selectedTripId = null;
    }
  }

  void _showMyTrips() => setState(() {
    _page = _WorkspacePage.myTrips;
    _selectedTripId = null;
  });

  void _showPage(_WorkspacePage page) => setState(() {
    _page = page;
    _selectedTripId = null;
  });

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
              onMyTrips: _showMyTrips,
              onClients: () => _showPage(_WorkspacePage.clients),
              onSuppliers: () => _showPage(_WorkspacePage.suppliers),
              isSuppliersSelected: _page == _WorkspacePage.suppliers,
              isClientsSelected: _page == _WorkspacePage.clients,
              onAdmin: user.isActiveAdmin
                  ? () => _showPage(_WorkspacePage.admin)
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
                  : _selectedTripId != null
                  ? TripWorkspacePage(
                      tripId: _selectedTripId!,
                      tripRepository: _trips,
                      supplierSourceRepository: _supplierSources,
                      onBack: _showMyTrips,
                    )
                  : TripsWorkspace(
                      currentUser: user,
                      tripRepository: _trips,
                      clientRepository: widget.clientRepository,
                      onBrowse: () => _showUnavailableMessage(context),
                      onClients: () => _showPage(_WorkspacePage.clients),
                      onOpenTrip: (tripId) =>
                          setState(() => _selectedTripId = tripId),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
