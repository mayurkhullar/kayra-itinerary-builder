import 'package:flutter/material.dart';

import '../supplier_import/review_components.dart';

/// Shared display fields only: dates/nights are supplied, never inferred.
class CanonicalHotelDetails extends StatelessWidget {
  const CanonicalHotelDetails({
    super.key,
    this.name,
    this.city,
    this.orSimilar,
    this.checkIn,
    this.checkOut,
    this.nights,
    this.roomType,
    this.mealPlan,
    this.rooms,
    this.starRating,
  });

  final String? name, city, checkIn, checkOut, roomType, mealPlan, starRating;
  final bool? orSimilar;
  final int? nights, rooms;

  @override
  Widget build(BuildContext context) => ReviewFields([
    (
      'Hotel',
      name == null ? null : '$name${orSimilar == true ? ' or similar' : ''}',
    ),
    if (name == null && orSimilar == true)
      ('Accommodation qualifier', 'or similar'),
    ('City', city),
    ('Check-in', checkIn),
    ('Check-out', checkOut),
    ('Nights', nights?.toString()),
    ('Room type', roomType),
    ('Meal plan', mealPlan),
    ('Rooms', rooms?.toString()),
    ('Star category', starRating),
  ]);
}
