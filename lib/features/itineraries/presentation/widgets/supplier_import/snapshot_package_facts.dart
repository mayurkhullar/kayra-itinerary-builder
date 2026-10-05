import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import 'review_components.dart';
import 'snapshot_itinerary.dart';

class SnapshotPackageFacts extends StatelessWidget {
  const SnapshotPackageFacts({super.key, required this.snapshot});
  final SupplierExtractionSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final hotels = snapshot.facts
        .whereType<SupplierExtractionPackageAccommodationFact>()
        .toList();
    final inclusions = snapshot.facts
        .whereType<SupplierExtractionPackageStatementFact>()
        .where(
          (fact) =>
              fact.factKind == SupplierExtractionFactKind.packageInclusion,
        )
        .toList();
    final exclusions = snapshot.facts
        .whereType<SupplierExtractionPackageStatementFact>()
        .where(
          (fact) =>
              fact.factKind == SupplierExtractionFactKind.packageExclusion,
        )
        .toList();
    final conditions = snapshot.facts
        .whereType<SupplierExtractionPackageConditionFact>()
        .toList();
    final flights = snapshot.facts
        .whereType<SupplierExtractionFlightFact>()
        .toList();
    final visas = snapshot.facts
        .whereType<SupplierExtractionVisaFact>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hotels.isNotEmpty)
          ReviewSection(
            key: const ValueKey('review-package-accommodation'),
            title: 'Package accommodation',
            subtitle:
                'Accommodation stated for the package, without a day assignment.',
            child: ReviewPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: reviewSeparated(
                  hotels.map(
                    (hotel) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          hotel.details.hotelName ?? 'Package accommodation',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SnapshotHotelDetails(
                          hotel.details,
                          omitValues: {
                            if (hotel.details.hotelName != null)
                              hotel.details.hotelName!,
                          },
                        ),
                        ReviewSources(hotel.sources),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (inclusions.isNotEmpty)
          _PackageStatements(
            'Package inclusions',
            'review-package-inclusions',
            inclusions,
          ),
        if (exclusions.isNotEmpty)
          _PackageStatements(
            'Package exclusions',
            'review-package-exclusions',
            exclusions,
          ),
        if (conditions.isNotEmpty)
          ReviewSection(
            key: const ValueKey('review-package-conditions'),
            title: 'Package conditions',
            child: ReviewPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: reviewSeparated(
                  conditions.map(
                    (condition) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          reviewLabel(condition.kind.value),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(condition.value),
                        ReviewFields([
                          ('Applies to', reviewAppliesTo(condition.appliesTo)),
                        ]),
                        ReviewSources(condition.sources),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (flights.isNotEmpty)
          ReviewSection(
            key: const ValueKey('review-flights'),
            title: 'Flights',
            subtitle:
                'Flight facts are kept separately from itinerary services.',
            child: ReviewPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: reviewSeparated(
                  flights.map(
                    (flight) => Column(
                      key: ValueKey('review-flight-${flight.id}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          [
                                flight.airline,
                                flight.flightNumber,
                              ].whereType<String>().join(' · ').isEmpty
                              ? 'Flight'
                              : [
                                  flight.airline,
                                  flight.flightNumber,
                                ].whereType<String>().join(' · '),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        ReviewFields([
                          ('From', flight.origin),
                          ('To', flight.destination),
                          ('Departure date', reviewDate(flight.departureDate)),
                          ('Departure time', flight.departureTime),
                          ('Arrival date', reviewDate(flight.arrivalDate)),
                          ('Arrival time', flight.arrivalTime),
                          ('Cabin class', flight.cabinClass),
                          ('Booking class', flight.bookingClass),
                        ]),
                        ReviewText(flight.notes, label: 'Flight notes'),
                        if (flight.conditions.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.s16),
                          ...reviewSeparated(
                            flight.conditions.map(ReviewCondition.new),
                          ),
                        ],
                        ReviewSources(flight.sources),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (visas.isNotEmpty)
          ReviewSection(
            key: const ValueKey('review-visas'),
            title: 'Visa',
            child: ReviewPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: reviewSeparated(
                  visas.map(
                    (visa) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          reviewLabel(visa.disposition.value),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        ReviewText(visa.text),
                        ReviewSources(visa.sources),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (snapshot.facts
            .whereType<SupplierExtractionCommercialPresenceFact>()
            .isNotEmpty)
          const ReviewSection(
            key: ValueKey('review-commercial-notice'),
            title: 'Commercial information',
            child: ReviewPanel(
              child: Text(
                'Commercial information was detected in the supplier source and is intentionally not included in this extraction review.',
              ),
            ),
          ),
      ],
    );
  }
}

class _PackageStatements extends StatelessWidget {
  const _PackageStatements(this.title, this.sectionKey, this.statements);
  final String title;
  final String sectionKey;
  final List<SupplierExtractionPackageStatementFact> statements;
  @override
  Widget build(BuildContext context) => ReviewSection(
    key: ValueKey(sectionKey),
    title: title,
    child: ReviewPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: reviewSeparated(
          statements.map(
            (statement) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(statement.text),
                ReviewFields([
                  ('Category', reviewLabel(statement.category.value)),
                  ('Quantity', statement.quantity?.toString()),
                  ('Frequency', statement.frequency),
                  ('Applies to', reviewAppliesTo(statement.appliesTo)),
                ]),
                ReviewSources(statement.sources),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
