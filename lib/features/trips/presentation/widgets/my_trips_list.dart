import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/kayra_trip.dart';

String tripDateLabel(DateTime date) {
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
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class MyTripsList extends StatelessWidget {
  const MyTripsList({
    super.key,
    required this.trips,
    required this.failed,
    required this.onRetry,
    required this.onCreate,
    this.active = true,
  });
  final List<KayraTrip>? trips;
  final bool failed;
  final bool active;
  final VoidCallback onRetry;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (!active) return const Text('Trip access is unavailable.');
    if (failed || trips == null || trips!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Semantics(
            liveRegion: true,
            child: Column(
              children: [
                if (!failed && trips == null) ...[
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 16),
                  const Text('Loading trips…'),
                ] else ...[
                  Text(
                    failed ? 'Trip data couldn’t be loaded.' : 'No trips yet',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (!failed) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Create your first itinerary to start building a journey.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: failed ? onRetry : onCreate,
                    child: Text(
                      failed ? 'Try again' : 'Create New Itinerary',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1000 &&
            MediaQuery.textScalerOf(context).scale(16) <= 20) {
          return Card(
            clipBehavior: Clip.antiAlias,
            child: DataTable(
              horizontalMargin: 20,
              columnSpacing: 24,
              dataRowMinHeight: 88,
              dataRowMaxHeight: double.infinity,
              headingRowColor: const WidgetStatePropertyAll(
                AppColors.background,
              ),
              columns: [
                for (final column in {
                  'Trip': 3.0,
                  'Travel': 2.4,
                  'Travellers': 1.2,
                  'Status': 1.2,
                  'Updated': 1.3,
                }.entries)
                  DataColumn(
                    label: Text(column.key),
                    columnWidth: FlexColumnWidth(column.value),
                  ),
              ],
              rows: [
                for (final trip in trips!)
                  DataRow(
                    key: ValueKey('trip-${trip.id}'),
                    cells: [
                      DataCell(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            trip.tripName,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
                      DataCell(_travel(context, trip)),
                      DataCell(Text(_travellers(trip))),
                      DataCell(_status(context, trip)),
                      DataCell(Text(tripDateLabel(trip.updatedAt.toLocal()))),
                    ],
                  ),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final trip in trips!)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  key: ValueKey('trip-${trip.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          trip.tripName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _travel(context, trip),
                        const SizedBox(height: 12),
                        Text(_travellers(trip)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _status(context, trip),
                            Text(
                              'Updated ${tripDateLabel(trip.updatedAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _travellers(KayraTrip trip) =>
      '${trip.adults}A · ${trip.children}C · ${trip.infants}I';
  Widget _travel(BuildContext context, KayraTrip trip) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(trip.destinations.join(' · ')),
      const SizedBox(height: 4),
      Text(
        '${tripDateLabel(trip.travelStartDate)} · ${trip.numberOfNights} ${trip.numberOfNights == 1 ? 'night' : 'nights'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
  Widget _status(BuildContext context, KayraTrip trip) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.navyTint,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      trip.status.label,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: AppColors.navy),
    ),
  );
}
