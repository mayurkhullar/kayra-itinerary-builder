import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../../../clients/data/client_repository.dart';
import '../../../dashboard/presentation/widgets/dashboard_command_area.dart';
import '../../../dashboard/presentation/widgets/dashboard_sections.dart';
import '../../../users/domain/kayra_user.dart';
import '../../data/trip_repository.dart';
import '../../domain/kayra_trip.dart';
import 'create_trip_form.dart';
import 'my_trips_list.dart';

class TripsWorkspace extends StatefulWidget {
  const TripsWorkspace({
    super.key,
    required this.currentUser,
    this.tripRepository,
    this.clientRepository,
    required this.onBrowse,
    required this.onClients,
  });
  final KayraUser currentUser;
  final TripRepository? tripRepository;
  final ClientRepository? clientRepository;
  final VoidCallback onBrowse;
  final VoidCallback onClients;
  @override
  State<TripsWorkspace> createState() => _TripsWorkspaceState();
}

class _TripsWorkspaceState extends State<TripsWorkspace> {
  TripRepository? _defaultTrips;
  ClientRepository? _defaultClients;
  TripRepository get _repository =>
      widget.tripRepository ?? (_defaultTrips ??= FirestoreTripRepository());
  ClientRepository get _clients =>
      widget.clientRepository ??
      (_defaultClients ??= FirestoreClientRepository());
  List<KayraTrip>? _trips;
  bool _failed = false;
  int _request = 0;
  DialogRoute<bool>? _formRoute;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TripsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.uid != widget.currentUser.uid ||
        oldWidget.currentUser.role != widget.currentUser.role ||
        oldWidget.currentUser.status != widget.currentUser.status ||
        oldWidget.tripRepository != widget.tripRepository ||
        oldWidget.clientRepository != widget.clientRepository) {
      _dismissForm();
      _load();
    }
  }

  void _dismissForm() {
    final route = _formRoute;
    _formRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    });
  }

  @override
  void dispose() {
    _dismissForm();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _trips = null;
      _failed = false;
    });
    if (!widget.currentUser.isActive) return;
    try {
      final trips = widget.currentUser.isActiveAdmin
          ? await _repository.listAllTripsForAdmin()
          : await _repository.listOwnedTrips(widget.currentUser.uid);
      if (!mounted || request != _request) return;
      final now = DateTime.now();
      final today = DateTime.utc(now.year, now.month, now.day);
      final sorted = List<KayraTrip>.of(trips)
        ..sort((a, b) {
          final aPast = a.travelStartDate.isBefore(today);
          final bPast = b.travelStartDate.isBefore(today);
          if (aPast != bPast) return aPast ? 1 : -1;
          final date = a.travelStartDate.compareTo(b.travelStartDate);
          return date == 0 ? a.id.compareTo(b.id) : date;
        });
      setState(() => _trips = sorted);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  Future<void> _create() async {
    if (_formRoute != null || !widget.currentUser.isActive) return;
    final request = _request;
    final user = widget.currentUser;
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateTripForm(
        currentUser: user,
        clientRepository: _clients,
        onClients: () {
          if (!mounted || request != _request) return;
          _dismissForm();
          widget.onClients();
        },
        onCreate: (client, brief) async {
          if (!mounted ||
              request != _request ||
              !widget.currentUser.isActive ||
              (!user.isActiveAdmin && client.createdByUid != user.uid)) {
            throw StateError('Session changed');
          }
          await _repository.createTrip(
            clientId: client.id,
            brief: brief,
            currentUserUid: user.uid,
          );
        },
      ),
    );
    _formRoute = route;
    final created = await Navigator.of(context).push(route);
    if (_formRoute == route) _formRoute = null;
    if (created == true && mounted && request == _request) await _load();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardCommandArea(
          displayName: widget.currentUser.displayName,
          onCreateItinerary: _create,
          onBrowseItineraries: widget.onBrowse,
        ),
        KayraContentFrame(
          maxWidth: AppLayout.dashboardMaxContentWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NeedsAttentionSection(),
                const SizedBox(height: AppSpacing.s32),
                MyTripsSection(
                  child: MyTripsList(
                    trips: _trips,
                    failed: _failed,
                    active: widget.currentUser.isActive,
                    onRetry: _load,
                    onCreate: _create,
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),
                ReusableItinerariesPanel(onBrowseItineraries: widget.onBrowse),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
