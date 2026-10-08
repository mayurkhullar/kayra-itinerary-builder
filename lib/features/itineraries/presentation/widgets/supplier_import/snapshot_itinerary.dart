import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import '../../../domain/supplier_extraction_values.dart';
import 'review_components.dart';

class SnapshotItinerary extends StatelessWidget {
  const SnapshotItinerary({
    super.key,
    required this.snapshot,
    this.serviceReviewBuilder,
    this.dayReviewBuilder,
  });
  final SupplierExtractionSnapshot snapshot;
  final Widget Function(SupplierExtractionServiceFact)? serviceReviewBuilder;
  final Widget Function(SupplierExtractionStagedDay)? dayReviewBuilder;
  @override
  Widget build(BuildContext context) {
    final services = snapshot.facts.whereType<SupplierExtractionServiceFact>();
    final unassigned = services
        .where((service) => service.scope is SupplierExtractionUnassignedScope)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewSection(
          key: const ValueKey('review-itinerary'),
          title: 'Day-by-day itinerary',
          subtitle: 'Chronology as stated in the supplier source.',
          child: snapshot.days.isEmpty
              ? const ReviewPanel(
                  child: Text(
                    'No day-by-day chronology was provided. Unassigned and package facts remain available below.',
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final day in snapshot.days) ...[
                      ReviewPanel(
                        key: ValueKey('review-day-${day.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: AppSpacing.s12,
                              runSpacing: AppSpacing.s8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ReviewBadge(
                                  day.sourceDayNumber == null
                                      ? 'Source day'
                                      : 'Source day ${day.sourceDayNumber}',
                                ),
                                if (day.date != null)
                                  Text(
                                    reviewDate(day.date)!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                              ],
                            ),
                            if (day.title != null) ...[
                              const SizedBox(height: AppSpacing.s12),
                              Semantics(
                                header: true,
                                child: Text(
                                  day.title!,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                            ],
                            ReviewText(
                              day.summary == day.title ? null : day.summary,
                            ),
                            ReviewText(day.notes, label: 'Day notes'),
                            ReviewSources(day.sources),
                            ?dayReviewBuilder?.call(day),
                            for (final service in services.where(
                              (service) =>
                                  service.scope is SupplierExtractionDayScope &&
                                  (service.scope as SupplierExtractionDayScope)
                                          .dayId ==
                                      day.id,
                            )) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: AppSpacing.s20,
                                ),
                                child: Divider(),
                              ),
                              SnapshotService(
                                service: service,
                                review: serviceReviewBuilder?.call(service),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                    ],
                  ],
                ),
        ),
        if (unassigned.isNotEmpty)
          ReviewSection(
            key: const ValueKey('review-unassigned'),
            title: 'Unscheduled services',
            subtitle:
                'Services without a supplied day. Scheduling is optional.',
            child: ReviewPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: reviewSeparated(
                  unassigned.map(
                    (service) => SnapshotService(
                      service: service,
                      review: serviceReviewBuilder?.call(service),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SnapshotService extends StatelessWidget {
  const SnapshotService({super.key, required this.service, this.review});
  final SupplierExtractionServiceFact service;
  final Widget? review;
  @override
  Widget build(BuildContext context) {
    final title =
        service.title ??
        service.hotelDetails?.hotelName ??
        service.activityDetails?.activityName;
    return Column(
      key: ValueKey('review-service-${service.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          service.serviceType == null
              ? 'Type needs review'
              : reviewLabel(service.serviceType!.value),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        if (title != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
        ReviewText(service.description == title ? null : service.description),
        ReviewFields([
          ('Start time', service.startTime),
          ('End time', service.endTime),
          ('City', service.city),
          ('Location', service.location),
        ]),
        if (service.hotelDetails case final hotel?)
          SnapshotHotelDetails(hotel, omitValues: {?title, ?service.city}),
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
          ReviewFields(
            [
              ('Activity', activity.activityName),
              ('Duration', activity.duration),
              ('Activity type', activity.activityType),
            ],
            omitValues: {?title},
          ),
        if (service.inclusions.isNotEmpty)
          _Statements('Service inclusions', service.inclusions),
        if (service.exclusions.isNotEmpty)
          _Statements('Service exclusions', service.exclusions),
        if (service.conditions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s16),
          Text(
            'Service conditions',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.s8),
          ...reviewSeparated(service.conditions.map(ReviewCondition.new)),
        ],
        ReviewText(service.notes, label: 'Service notes'),
        ReviewSources(service.sources),
        ?review,
      ],
    );
  }
}

class SnapshotHotelDetails extends StatelessWidget {
  const SnapshotHotelDetails(
    this.hotel, {
    super.key,
    this.omitValues = const {},
  });
  final SupplierExtractionHotelDetails hotel;
  final Set<String> omitValues;
  @override
  Widget build(BuildContext context) => ReviewFields([
    ('Hotel', hotel.hotelName),
    ('City', hotel.city),
    (
      'Or similar',
      hotel.orSimilar == null
          ? null
          : hotel.orSimilar!
          ? 'Yes'
          : 'No',
    ),
    ('Check-in', reviewDate(hotel.checkInDate)),
    ('Check-out', reviewDate(hotel.checkOutDate)),
    ('Nights', hotel.nightCount?.toString()),
    ('Room type', hotel.roomType),
    ('Meal plan', hotel.mealPlan),
    ('Rooms', hotel.numberOfRooms?.toString()),
    ('Supplier star category', hotel.supplierStarRating),
  ], omitValues: omitValues);
}

class _Statements extends StatelessWidget {
  const _Statements(this.title, this.statements);
  final String title;
  final List<SupplierExtractionStatement> statements;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.s8),
        ...reviewSeparated(statements.map(ReviewStatement.new)),
      ],
    ),
  );
}
