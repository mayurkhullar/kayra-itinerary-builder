import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/itinerary_draft_v2.dart';
import '../../../domain/kayra_itinerary_service.dart';
import '../supplier_import/review_components.dart';
import 'canonical_hotel_details.dart';

class CanonicalPackageContent extends StatelessWidget {
  const CanonicalPackageContent({super.key, required this.content});
  final ItineraryDraftV2PackageContent content;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (content.accommodations.isNotEmpty)
        ReviewSection(
          title: 'Package accommodation',
          child: ReviewPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: reviewSeparated(
                content.accommodations.map(
                  (stay) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (stay.selection ==
                          ItineraryDraftV2AccommodationSelection.alternatives)
                        Text(
                          'Accommodation alternatives — one of the following',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      for (final (index, option) in stay.options.indexed) ...[
                        if (index > 0) ...[
                          const SizedBox(height: AppSpacing.s16),
                          Text(
                            'or',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                        CanonicalHotelDetails(
                          name: option.details.hotelName,
                          city: option.details.city,
                          orSimilar: option.details.orSimilar,
                          checkIn: _date(option.details.checkInDate),
                          checkOut: _date(option.details.checkOutDate),
                          nights: option.details.nightCount,
                          roomType: option.details.roomType,
                          mealPlan: option.details.mealPlan,
                          rooms: option.details.numberOfRooms,
                          starRating: option.details.supplierStarRating,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      if (content.inclusions.isNotEmpty)
        _Statements('Inclusions', content.inclusions),
      if (content.exclusions.isNotEmpty)
        _Statements('Exclusions', content.exclusions),
      if (content.conditions.isNotEmpty)
        ReviewSection(
          title: 'Package conditions',
          child: ReviewPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: reviewSeparated(
                content.conditions.map(
                  (condition) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        reviewLabel(condition.kind.value),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(condition.value),
                      ReviewFields([
                        ('Applies to', _appliesTo(condition.appliesTo)),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

String? _date(String? value) =>
    value == null ? null : reviewDate(DateTime.parse('${value}T00:00:00Z'));
String? _appliesTo(List<KayraItineraryServiceType> types) => types.isEmpty
    ? null
    : types.map((type) => reviewLabel(type.value)).join(' · ');

class _Statements extends StatelessWidget {
  const _Statements(this.title, this.statements);
  final String title;
  final List<ItineraryDraftV2Statement> statements;

  @override
  Widget build(BuildContext context) => ReviewSection(
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
                  ('Applies to', _appliesTo(statement.appliesTo)),
                ]),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
