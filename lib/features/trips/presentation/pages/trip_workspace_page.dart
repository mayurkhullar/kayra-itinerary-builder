import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../../../supplier_sources/data/supplier_source_repository.dart';
import '../../../supplier_sources/presentation/widgets/supplier_sources_section.dart';
import '../../data/trip_repository.dart';
import '../../domain/kayra_trip.dart';

class TripWorkspacePage extends StatefulWidget {
  const TripWorkspacePage({
    super.key,
    required this.tripId,
    required this.tripRepository,
    required this.supplierSourceRepository,
    required this.onBack,
  });

  final String tripId;
  final TripRepository tripRepository;
  final SupplierSourceRepository supplierSourceRepository;
  final VoidCallback onBack;

  @override
  State<TripWorkspacePage> createState() => _TripWorkspacePageState();
}

class _TripWorkspacePageState extends State<TripWorkspacePage> {
  KayraTrip? _trip;
  bool _loading = true;
  bool _unavailable = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TripWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId ||
        oldWidget.tripRepository != widget.tripRepository) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _trip = null;
      _loading = true;
      _unavailable = false;
    });
    try {
      final trip = await widget.tripRepository.getTripById(widget.tripId);
      if (!mounted || request != _request) return;
      setState(() {
        _trip = trip;
        _loading = false;
        _unavailable = trip == null;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _unavailable = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('trip-workspace-scroll'),
    child: KayraContentFrame(
      maxWidth: AppLayout.maxContentWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('back-to-my-trips'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back to My Trips'),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            if (_loading)
              const _WorkspaceState(
                key: ValueKey('trip-workspace-loading'),
                loading: true,
                title: 'Loading trip workspace…',
              )
            else if (_unavailable)
              _WorkspaceState(
                key: const ValueKey('trip-workspace-unavailable'),
                title: 'Trip unavailable',
                subtitle:
                    'This trip could not be loaded or you no longer have access to it.',
                action: OutlinedButton(
                  onPressed: widget.onBack,
                  child: const Text('Back to My Trips'),
                ),
              )
            else ...[
              TripWorkspaceHeader(trip: _trip!),
              const SizedBox(height: AppSpacing.s40),
              SupplierSourcesSection(
                tripId: widget.tripId,
                repository: widget.supplierSourceRepository,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class TripWorkspaceHeader extends StatelessWidget {
  const TripWorkspaceHeader({super.key, required this.trip});

  final KayraTrip trip;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: AppSpacing.s16,
        runSpacing: AppSpacing.s12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            trip.tripName,
            key: const ValueKey('trip-workspace-title'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          _TripStatus(status: trip.status),
        ],
      ),
      const SizedBox(height: AppSpacing.s8),
      Text(
        '${trip.clientFirstName} ${trip.clientLastName} · ${travelDateRange(trip)} · ${_nights(trip.numberOfNights)} · ${travellerSummary(trip)}',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.s24),
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.r12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - AppSpacing.s24 * (columns - 1)) /
                  columns;
              final details = [
                ('Destinations', trip.destinations.join(' · ')),
                ('Travel Date', travelDateRange(trip)),
                ('Number of Nights', _nights(trip.numberOfNights)),
                ('Travellers', travellerSummary(trip)),
                ('Hotel Category', trip.hotelCategory.label),
                ('Trip Type', trip.tripType.label),
              ];
              return Wrap(
                spacing: AppSpacing.s24,
                runSpacing: AppSpacing.s20,
                children: [
                  for (final detail in details)
                    SizedBox(
                      width: width,
                      child: _SummaryDetail(label: detail.$1, value: detail.$2),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ],
  );
}

class _SummaryDetail extends StatelessWidget {
  const _SummaryDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: AppSpacing.s4),
      Text(value, style: Theme.of(context).textTheme.titleSmall),
    ],
  );
}

class _TripStatus extends StatelessWidget {
  const _TripStatus({required this.status});

  final TripStatus status;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.navyTint,
      borderRadius: BorderRadius.circular(AppRadius.r8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      child: Text(
        status.label,
        key: const ValueKey('trip-workspace-status'),
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.navy),
      ),
    ),
  );
}

class _WorkspaceState extends StatelessWidget {
  const _WorkspaceState({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.loading = false,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.s40),
      child: Semantics(
        liveRegion: true,
        child: Column(
          children: [
            if (loading) ...[
              const SizedBox.square(
                dimension: AppSpacing.s24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: AppSpacing.s16),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s16),
              action!,
            ],
          ],
        ),
      ),
    ),
  );
}

String travellerSummary(KayraTrip trip) =>
    '${trip.adults} ${trip.adults == 1 ? 'Adult' : 'Adults'} · '
    '${trip.children} ${trip.children == 1 ? 'Child' : 'Children'} · '
    '${trip.infants} ${trip.infants == 1 ? 'Infant' : 'Infants'}';

String travelDateRange(KayraTrip trip) {
  final start = trip.travelStartDate;
  final end = trip.tripEndDate;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}–${end.day} ${months[end.month - 1]} ${end.year}';
  }
  if (start.year == end.year) {
    return '${start.day} ${months[start.month - 1]} – '
        '${end.day} ${months[end.month - 1]} ${end.year}';
  }
  return '${start.day} ${months[start.month - 1]} ${start.year} – '
      '${end.day} ${months[end.month - 1]} ${end.year}';
}

String _nights(int count) => '$count ${count == 1 ? 'night' : 'nights'}';
