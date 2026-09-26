import 'itinerary_model_validation.dart';

enum KayraItineraryTransferType {
  private('private'),
  shared('shared'),
  scheduled('scheduled'),
  other('other');

  const KayraItineraryTransferType(this.value);
  final String value;

  static KayraItineraryTransferType parse(Object? value) => values.firstWhere(
    (type) => type.value == value,
    orElse: () =>
        throw const FormatException('Invalid itinerary transfer type.'),
  );
}

final class KayraItineraryHotelDetails {
  KayraItineraryHotelDetails({
    required String hotelName,
    DateTime? checkInDate,
    DateTime? checkOutDate,
    String? roomType,
    String? mealPlan,
    int? numberOfRooms,
    String? supplierStarRating,
  }) : hotelName = ItineraryModelValidation.requiredText(
         hotelName,
         'Hotel name',
       ),
       checkInDate = checkInDate == null
           ? null
           : ItineraryModelValidation.dateOnly(checkInDate),
       checkOutDate = checkOutDate == null
           ? null
           : ItineraryModelValidation.dateOnly(checkOutDate),
       roomType = ItineraryModelValidation.optionalText(roomType),
       mealPlan = ItineraryModelValidation.optionalText(mealPlan),
       numberOfRooms = _positiveRoomCount(numberOfRooms),
       supplierStarRating = ItineraryModelValidation.optionalText(
         supplierStarRating,
       ) {
    if (this.checkInDate != null &&
        this.checkOutDate != null &&
        !this.checkOutDate!.isAfter(this.checkInDate!)) {
      throw const FormatException('Hotel check-out must follow check-in.');
    }
  }

  factory KayraItineraryHotelDetails.fromMap(Map<String, Object?> data) {
    ItineraryModelValidation.fields(data, {
      'hotelName',
      'checkInDate',
      'checkOutDate',
      'roomType',
      'mealPlan',
      'numberOfRooms',
      'supplierStarRating',
    });
    return KayraItineraryHotelDetails(
      hotelName: ItineraryModelValidation.string(data['hotelName']),
      checkInDate: ItineraryModelValidation.nullableDate(data['checkInDate']),
      checkOutDate: ItineraryModelValidation.nullableDate(data['checkOutDate']),
      roomType: ItineraryModelValidation.nullableString(data['roomType']),
      mealPlan: ItineraryModelValidation.nullableString(data['mealPlan']),
      numberOfRooms: ItineraryModelValidation.nullableInteger(
        data['numberOfRooms'],
      ),
      supplierStarRating: ItineraryModelValidation.nullableString(
        data['supplierStarRating'],
      ),
    );
  }

  final String hotelName;
  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final String? roomType;
  final String? mealPlan;
  final int? numberOfRooms;
  final String? supplierStarRating;

  Map<String, Object?> toMap() => {
    'hotelName': hotelName,
    'checkInDate': checkInDate,
    'checkOutDate': checkOutDate,
    'roomType': roomType,
    'mealPlan': mealPlan,
    'numberOfRooms': numberOfRooms,
    'supplierStarRating': supplierStarRating,
  };

  static int? _positiveRoomCount(int? value) {
    if (value != null && value < 1) {
      throw const FormatException('Number of rooms must be positive.');
    }
    return value;
  }
}

final class KayraItineraryTransferDetails {
  KayraItineraryTransferDetails({
    required String pickup,
    required String dropoff,
    String? vehicleType,
    this.transferType,
  }) : pickup = ItineraryModelValidation.requiredText(pickup, 'Pickup'),
       dropoff = ItineraryModelValidation.requiredText(dropoff, 'Dropoff'),
       vehicleType = ItineraryModelValidation.optionalText(vehicleType);

  factory KayraItineraryTransferDetails.fromMap(Map<String, Object?> data) {
    ItineraryModelValidation.fields(data, {
      'pickup',
      'dropoff',
      'vehicleType',
      'transferType',
    });
    final transferType = data['transferType'];
    return KayraItineraryTransferDetails(
      pickup: ItineraryModelValidation.string(data['pickup']),
      dropoff: ItineraryModelValidation.string(data['dropoff']),
      vehicleType: ItineraryModelValidation.nullableString(data['vehicleType']),
      transferType: transferType == null
          ? null
          : KayraItineraryTransferType.parse(transferType),
    );
  }

  final String pickup;
  final String dropoff;
  final String? vehicleType;
  final KayraItineraryTransferType? transferType;

  Map<String, Object?> toMap() => {
    'pickup': pickup,
    'dropoff': dropoff,
    'vehicleType': vehicleType,
    'transferType': transferType?.value,
  };
}

final class KayraItineraryActivityDetails {
  KayraItineraryActivityDetails({
    required String activityName,
    String? duration,
    String? activityType,
  }) : activityName = ItineraryModelValidation.requiredText(
         activityName,
         'Activity name',
       ),
       duration = ItineraryModelValidation.optionalText(duration),
       activityType = ItineraryModelValidation.optionalText(activityType);

  factory KayraItineraryActivityDetails.fromMap(Map<String, Object?> data) {
    ItineraryModelValidation.fields(data, {
      'activityName',
      'duration',
      'activityType',
    });
    return KayraItineraryActivityDetails(
      activityName: ItineraryModelValidation.string(data['activityName']),
      duration: ItineraryModelValidation.nullableString(data['duration']),
      activityType: ItineraryModelValidation.nullableString(
        data['activityType'],
      ),
    );
  }

  final String activityName;
  final String? duration;
  final String? activityType;

  Map<String, Object?> toMap() => {
    'activityName': activityName,
    'duration': duration,
    'activityType': activityType,
  };
}
