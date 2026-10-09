import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/itinerary_draft_v2.dart';
import '../supplier_import/review_components.dart';
import 'canonical_hotel_details.dart';

/// The same full canonical service presentation for either placement.
/// Deliberately allowlists content; never renders sourceReference or IDs.
class CanonicalService extends StatelessWidget {
  const CanonicalService({super.key, required this.service});
  final ItineraryDraftV2Service service;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        reviewLabel(service.type.value),
        style: Theme.of(context).textTheme.labelSmall,
      ),
      const SizedBox(height: AppSpacing.s4),
      Semantics(
        header: true,
        child: Text(
          service.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      ReviewText(service.description),
      ReviewFields([
        ('Start time', service.startTime),
        ('End time', service.endTime),
        ('City', service.city),
        ('Location', service.location),
      ]),
      if (service.hotelDetails case final hotel?)
        CanonicalHotelDetails(
          name: hotel.hotelName,
          city: hotel.city,
          orSimilar: hotel.orSimilar,
          checkIn: reviewDate(hotel.checkInDate),
          checkOut: reviewDate(hotel.checkOutDate),
          nights: hotel.nightCount,
          roomType: hotel.roomType,
          mealPlan: hotel.mealPlan,
          rooms: hotel.numberOfRooms,
          starRating: hotel.supplierStarRating,
        ),
      if (service.transferDetails case final transfer?)
        ReviewFields([
          ('Pickup', transfer.pickup),
          ('Drop-off', transfer.dropoff),
          ('Vehicle', transfer.vehicleType),
          (
            'Transfer type',
            transfer.transferType == null
                ? null
                : reviewLabel(transfer.transferType!.value),
          ),
        ]),
      if (service.activityDetails case final activity?)
        ReviewFields([
          ('Activity', activity.activityName),
          ('Duration', activity.duration),
          ('Activity type', activity.activityType),
        ]),
      if (service.inclusions.isNotEmpty)
        _ServiceTextGroup('Service inclusions', service.inclusions),
      if (service.exclusions.isNotEmpty)
        _ServiceTextGroup('Service exclusions', service.exclusions),
      if (service.conditions case final conditions?
          when conditions.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.s16),
        Semantics(
          header: true,
          child: Text(
            'Service conditions',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final condition in conditions)
          ReviewText(condition.value, label: reviewLabel(condition.kind.value)),
      ],
      ReviewText(service.notes, label: 'Service notes'),
    ],
  );
}

class _ServiceTextGroup extends StatelessWidget {
  const _ServiceTextGroup(this.title, this.values);
  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final value in values) ReviewText(value),
      ],
    ),
  );
}
