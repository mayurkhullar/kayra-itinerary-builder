import 'supplier_extraction_values.dart';
import 'supplier_import_resolution_overrides.dart';
import 'supplier_import_resolution_parsing.dart';

final class SupplierImportManualItemMetadata {
  const SupplierImportManualItemMetadata({
    required this.createdByUid,
    required this.createdAt,
    required this.updatedByUid,
    required this.updatedAt,
    required this.lastRevision,
  });

  factory SupplierImportManualItemMetadata.fromMap(Map<String, Object?> data) {
    if (data['origin'] != 'consultant') {
      throw const FormatException('Manual item origin is invalid.');
    }
    return SupplierImportManualItemMetadata(
      createdByUid: SupplierImportResolutionParsing.id(
        data['createdByUid'],
        'Manual item creator',
      ),
      createdAt: SupplierImportResolutionParsing.timestamp(
        data['createdAt'],
        'Manual item creation time',
      ),
      updatedByUid: SupplierImportResolutionParsing.id(
        data['updatedByUid'],
        'Manual item updater',
      ),
      updatedAt: SupplierImportResolutionParsing.timestamp(
        data['updatedAt'],
        'Manual item update time',
      ),
      lastRevision: SupplierImportResolutionParsing.positiveInt(
        data['lastRevision'],
        'Manual item revision',
      ),
    );
  }

  final String createdByUid;
  final DateTime createdAt;
  final String updatedByUid;
  final DateTime updatedAt;
  final int lastRevision;
}

final class SupplierImportStoredManualItem {
  const SupplierImportStoredManualItem({
    required this.metadata,
    required this.payload,
  });

  factory SupplierImportStoredManualItem.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.record(
      input,
      'Stored manual item',
    );
    return SupplierImportStoredManualItem(
      metadata: SupplierImportManualItemMetadata.fromMap(data),
      payload: SupplierImportManualItemPayload.fromStoredMap(data),
    );
  }

  final SupplierImportManualItemMetadata metadata;
  final SupplierImportManualItemPayload payload;

  String get itemId => payload.itemId;
}

sealed class SupplierImportManualItemPayload {
  const SupplierImportManualItemPayload();

  factory SupplierImportManualItemPayload.fromStoredMap(
    Map<String, Object?> data,
  ) => switch (data['itemKind']) {
    'consultant_day' => SupplierImportManualDay.fromStoredMap(data),
    'consultant_service' => SupplierImportManualService.fromStoredMap(data),
    _ => throw const FormatException('Stored manual item kind is invalid.'),
  };

  String get itemKind;
  String get itemId;
  Map<String, Object?> toMutationMap();
}

const _metadataFields = {
  'origin',
  'createdByUid',
  'createdAt',
  'updatedByUid',
  'updatedAt',
  'lastRevision',
};

final class SupplierImportManualDay extends SupplierImportManualItemPayload {
  const SupplierImportManualDay({
    required this.manualDayId,
    required this.canonicalOrder,
    required this.date,
    required this.title,
    required this.summary,
    required this.notes,
  });

  factory SupplierImportManualDay.fromStoredMap(Map<String, Object?> input) {
    final data = SupplierImportResolutionParsing.exact(input, {
      'itemKind',
      'manualDayId',
      'canonicalOrder',
      'date',
      'title',
      'summary',
      'notes',
      ..._metadataFields,
    }, 'Consultant day');
    if (data['itemKind'] != 'consultant_day') {
      throw const FormatException('Consultant day kind is invalid.');
    }
    final id = SupplierImportResolutionParsing.id(
      data['manualDayId'],
      'Consultant day',
    );
    if (!id.startsWith('consultant-day-')) {
      throw const FormatException('Consultant day identity is invalid.');
    }
    return SupplierImportManualDay(
      manualDayId: id,
      canonicalOrder: SupplierImportResolutionParsing.positiveInt(
        data['canonicalOrder'],
        'Consultant day order',
      ),
      date: SupplierImportResolutionParsing.nullableDate(
        data['date'],
        'Consultant day date',
      ),
      title: SupplierImportResolutionParsing.text(
        data['title'],
        'Consultant day title',
      ),
      summary: SupplierImportResolutionParsing.nullableText(
        data['summary'],
        'Consultant day summary',
      ),
      notes: SupplierImportResolutionParsing.nullableText(
        data['notes'],
        'Consultant day notes',
      ),
    );
  }

  final String manualDayId;
  final int canonicalOrder;
  final String? date;
  final String title;
  final String? summary;
  final String? notes;

  @override
  String get itemKind => 'consultant_day';
  @override
  String get itemId => manualDayId;

  @override
  Map<String, Object?> toMutationMap() => {
    'itemKind': itemKind,
    'manualDayId': manualDayId,
    'canonicalOrder': canonicalOrder,
    'date': date,
    'title': title,
    'summary': summary,
    'notes': notes,
  };
}

final class SupplierImportManualHotelDetails {
  const SupplierImportManualHotelDetails({
    required this.hotelName,
    required this.checkInDate,
    required this.checkOutDate,
    required this.roomType,
    required this.mealPlan,
    required this.numberOfRooms,
    required this.supplierStarRating,
  });

  factory SupplierImportManualHotelDetails.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.exact(input, const {
      'hotelName',
      'checkInDate',
      'checkOutDate',
      'roomType',
      'mealPlan',
      'numberOfRooms',
      'supplierStarRating',
    }, 'Manual hotel details');
    final checkIn = SupplierImportResolutionParsing.nullableDate(
      data['checkInDate'],
      'Manual hotel check-in',
    );
    final checkOut = SupplierImportResolutionParsing.nullableDate(
      data['checkOutDate'],
      'Manual hotel check-out',
    );
    if (checkIn != null &&
        checkOut != null &&
        DateTime.parse(checkOut).compareTo(DateTime.parse(checkIn)) <= 0) {
      throw const FormatException('Manual hotel dates are invalid.');
    }
    return SupplierImportManualHotelDetails(
      hotelName: SupplierImportResolutionParsing.text(
        data['hotelName'],
        'Manual hotel name',
      ),
      checkInDate: checkIn,
      checkOutDate: checkOut,
      roomType: SupplierImportResolutionParsing.nullableText(
        data['roomType'],
        'Manual room type',
      ),
      mealPlan: SupplierImportResolutionParsing.nullableText(
        data['mealPlan'],
        'Manual meal plan',
      ),
      numberOfRooms: SupplierImportResolutionParsing.nullablePositiveInt(
        data['numberOfRooms'],
        'Manual room count',
      ),
      supplierStarRating: SupplierImportResolutionParsing.nullableText(
        data['supplierStarRating'],
        'Manual star rating',
      ),
    );
  }

  final String hotelName;
  final String? checkInDate;
  final String? checkOutDate;
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
}

final class SupplierImportManualTransferDetails {
  const SupplierImportManualTransferDetails({
    required this.pickup,
    required this.dropoff,
    required this.vehicleType,
    required this.transferType,
  });

  factory SupplierImportManualTransferDetails.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.exact(input, const {
      'pickup',
      'dropoff',
      'vehicleType',
      'transferType',
    }, 'Manual transfer details');
    return SupplierImportManualTransferDetails(
      pickup: SupplierImportResolutionParsing.text(
        data['pickup'],
        'Manual transfer pickup',
      ),
      dropoff: SupplierImportResolutionParsing.text(
        data['dropoff'],
        'Manual transfer drop-off',
      ),
      vehicleType: SupplierImportResolutionParsing.nullableText(
        data['vehicleType'],
        'Manual vehicle type',
      ),
      transferType: data['transferType'] == null
          ? null
          : SupplierImportResolutionParsing.enumValue(
              data['transferType'],
              SupplierExtractionTransferType.values,
              (item) => item.value,
              'Manual transfer type',
            ),
    );
  }

  final String pickup;
  final String dropoff;
  final String? vehicleType;
  final SupplierExtractionTransferType? transferType;

  Map<String, Object?> toMap() => {
    'pickup': pickup,
    'dropoff': dropoff,
    'vehicleType': vehicleType,
    'transferType': transferType?.value,
  };
}

final class SupplierImportManualActivityDetails {
  const SupplierImportManualActivityDetails({
    required this.activityName,
    required this.duration,
    required this.activityType,
  });

  factory SupplierImportManualActivityDetails.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.exact(input, const {
      'activityName',
      'duration',
      'activityType',
    }, 'Manual activity details');
    return SupplierImportManualActivityDetails(
      activityName: SupplierImportResolutionParsing.text(
        data['activityName'],
        'Manual activity name',
      ),
      duration: SupplierImportResolutionParsing.nullableText(
        data['duration'],
        'Manual activity duration',
      ),
      activityType: SupplierImportResolutionParsing.nullableText(
        data['activityType'],
        'Manual activity type',
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

final class SupplierImportManualService
    extends SupplierImportManualItemPayload {
  SupplierImportManualService({
    required this.manualServiceId,
    required this.day,
    required this.canonicalOrder,
    required this.serviceType,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.city,
    required List<String> inclusions,
    required List<String> exclusions,
    required this.notes,
    required this.hotelDetails,
    required this.transferDetails,
    required this.activityDetails,
  }) : inclusions = List.unmodifiable(inclusions),
       exclusions = List.unmodifiable(exclusions) {
    final compatible = switch (serviceType) {
      SupplierExtractionServiceType.hotel =>
        hotelDetails != null &&
            transferDetails == null &&
            activityDetails == null,
      SupplierExtractionServiceType.transfer =>
        hotelDetails == null &&
            transferDetails != null &&
            activityDetails == null,
      SupplierExtractionServiceType.activity ||
      SupplierExtractionServiceType.sightseeing =>
        hotelDetails == null &&
            transferDetails == null &&
            activityDetails != null,
      _ =>
        hotelDetails == null &&
            transferDetails == null &&
            activityDetails == null,
    };
    if (!compatible) {
      throw const FormatException('Manual service details are incompatible.');
    }
  }

  factory SupplierImportManualService.fromStoredMap(
    Map<String, Object?> input,
  ) {
    final fields = {
      'itemKind',
      'manualServiceId',
      'day',
      'canonicalOrder',
      'serviceType',
      'title',
      'description',
      'startTime',
      'endTime',
      'location',
      'city',
      'inclusions',
      'exclusions',
      'notes',
      'hotelDetails',
      'transferDetails',
      'activityDetails',
      ..._metadataFields,
    };
    final data = SupplierImportResolutionParsing.exact(
      input,
      fields,
      'Consultant service',
    );
    final id = SupplierImportResolutionParsing.id(
      data['manualServiceId'],
      'Consultant service',
    );
    if (data['itemKind'] != 'consultant_service' ||
        !id.startsWith('consultant-service-')) {
      throw const FormatException('Consultant service identity is invalid.');
    }
    return SupplierImportManualService(
      manualServiceId: id,
      day: SupplierImportDayReference.fromMap(data['day']),
      canonicalOrder: SupplierImportResolutionParsing.positiveInt(
        data['canonicalOrder'],
        'Consultant service order',
      ),
      serviceType: SupplierImportResolutionParsing.enumValue(
        data['serviceType'],
        SupplierExtractionServiceType.values,
        (item) => item.value,
        'Manual service type',
      ),
      title: SupplierImportResolutionParsing.text(
        data['title'],
        'Manual service title',
      ),
      description: SupplierImportResolutionParsing.nullableText(
        data['description'],
        'Manual service description',
      ),
      startTime: SupplierImportResolutionParsing.nullableTime(
        data['startTime'],
        'Manual service start time',
      ),
      endTime: SupplierImportResolutionParsing.nullableTime(
        data['endTime'],
        'Manual service end time',
      ),
      location: SupplierImportResolutionParsing.nullableText(
        data['location'],
        'Manual service location',
      ),
      city: SupplierImportResolutionParsing.nullableText(
        data['city'],
        'Manual service city',
      ),
      inclusions: SupplierImportResolutionParsing.textList(
        data['inclusions'],
        'Manual service inclusions',
      ),
      exclusions: SupplierImportResolutionParsing.textList(
        data['exclusions'],
        'Manual service exclusions',
      ),
      notes: SupplierImportResolutionParsing.nullableText(
        data['notes'],
        'Manual service notes',
      ),
      hotelDetails: data['hotelDetails'] == null
          ? null
          : SupplierImportManualHotelDetails.fromMap(data['hotelDetails']),
      transferDetails: data['transferDetails'] == null
          ? null
          : SupplierImportManualTransferDetails.fromMap(
              data['transferDetails'],
            ),
      activityDetails: data['activityDetails'] == null
          ? null
          : SupplierImportManualActivityDetails.fromMap(
              data['activityDetails'],
            ),
    );
  }

  final String manualServiceId;
  final SupplierImportDayReference day;
  final int canonicalOrder;
  final SupplierExtractionServiceType serviceType;
  final String title;
  final String? description;
  final String? startTime;
  final String? endTime;
  final String? location;
  final String? city;
  final List<String> inclusions;
  final List<String> exclusions;
  final String? notes;
  final SupplierImportManualHotelDetails? hotelDetails;
  final SupplierImportManualTransferDetails? transferDetails;
  final SupplierImportManualActivityDetails? activityDetails;

  @override
  String get itemKind => 'consultant_service';
  @override
  String get itemId => manualServiceId;

  @override
  Map<String, Object?> toMutationMap() => {
    'itemKind': itemKind,
    'manualServiceId': manualServiceId,
    'day': day.toMap(),
    'canonicalOrder': canonicalOrder,
    'serviceType': serviceType.value,
    'title': title,
    'description': description,
    'startTime': startTime,
    'endTime': endTime,
    'location': location,
    'city': city,
    'inclusions': inclusions,
    'exclusions': exclusions,
    'notes': notes,
    'hotelDetails': hotelDetails?.toMap(),
    'transferDetails': transferDetails?.toMap(),
    'activityDetails': activityDetails?.toMap(),
  };
}
