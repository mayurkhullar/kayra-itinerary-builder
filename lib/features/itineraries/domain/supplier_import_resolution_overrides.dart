import 'supplier_extraction_values.dart';
import 'supplier_import_resolution_parsing.dart';

sealed class SupplierImportFieldOverride<T> {
  const SupplierImportFieldOverride();

  Map<String, Object?> toMap();
}

final class SupplierImportSetOverride<T>
    extends SupplierImportFieldOverride<T> {
  const SupplierImportSetOverride(this.value);

  final T value;

  @override
  Map<String, Object?> toMap() => {
    'operation': 'set',
    'value': supplierImportWireValue(value),
  };
}

final class SupplierImportClearOverride<T>
    extends SupplierImportFieldOverride<T> {
  const SupplierImportClearOverride();

  @override
  Map<String, Object?> toMap() => const {'operation': 'clear'};
}

typedef SupplierImportValueParser<T> = T Function(Object? value, String label);

SupplierImportFieldOverride<T> parseSupplierImportOverride<T>(
  Object? input,
  SupplierImportValueParser<T> parser,
  String label, {
  bool setOnly = false,
}) {
  final data = SupplierImportResolutionParsing.closed(
    input,
    allowed: const {'operation', 'value'},
    required: const {'operation'},
    label: '$label override',
  );
  if (data['operation'] == 'clear' && !setOnly) {
    if (data.length != 1) {
      throw FormatException('$label clear override is invalid.');
    }
    return SupplierImportClearOverride<T>();
  }
  if (data['operation'] != 'set' ||
      data.length != 2 ||
      !data.containsKey('value')) {
    throw FormatException('$label set override is invalid.');
  }
  return SupplierImportSetOverride<T>(parser(data['value'], label));
}

enum SupplierImportExclusionReason {
  duplicate('duplicate'),
  extractedInError('extracted_in_error'),
  irrelevantSupplierContent('irrelevant_supplier_content'),
  notPartOfRequestedItinerary('not_part_of_requested_itinerary'),
  replacedByConsultantContent('replaced_by_consultant_content'),
  other('other');

  const SupplierImportExclusionReason(this.value);
  final String value;
}

SupplierImportExclusionReason? parseSupplierImportExclusionReason(
  Object? value,
  String label,
) => value == null
    ? null
    : SupplierImportResolutionParsing.enumValue(
        value,
        SupplierImportExclusionReason.values,
        (item) => item.value,
        label,
      );

sealed class SupplierImportDayReference {
  const SupplierImportDayReference();

  factory SupplierImportDayReference.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {'kind', 'dayId', 'manualDayId'},
      required: const {'kind'},
      label: 'Resolution day reference',
    );
    if (data['kind'] == 'staged_day' && data.length == 2) {
      return SupplierImportStagedDayReference(
        SupplierImportResolutionParsing.id(data['dayId'], 'Staged day'),
      );
    }
    if (data['kind'] == 'consultant_day' && data.length == 2) {
      return SupplierImportManualDayReference(
        SupplierImportResolutionParsing.id(
          data['manualDayId'],
          'Consultant day',
        ),
      );
    }
    throw const FormatException('Resolution day reference is invalid.');
  }

  Map<String, Object?> toMap();
}

final class SupplierImportStagedDayReference
    extends SupplierImportDayReference {
  const SupplierImportStagedDayReference(this.dayId);
  final String dayId;

  @override
  Map<String, Object?> toMap() => {'kind': 'staged_day', 'dayId': dayId};
}

final class SupplierImportManualDayReference
    extends SupplierImportDayReference {
  const SupplierImportManualDayReference(this.manualDayId);
  final String manualDayId;

  @override
  Map<String, Object?> toMap() => {
    'kind': 'consultant_day',
    'manualDayId': manualDayId,
  };
}

sealed class SupplierImportServiceReference {
  const SupplierImportServiceReference();

  factory SupplierImportServiceReference.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {'kind', 'serviceId', 'manualServiceId'},
      required: const {'kind'},
      label: 'Resolution service reference',
    );
    if (data['kind'] == 'staged_service' && data.length == 2) {
      return SupplierImportStagedServiceReference(
        SupplierImportResolutionParsing.id(data['serviceId'], 'Staged service'),
      );
    }
    if (data['kind'] == 'consultant_service' && data.length == 2) {
      return SupplierImportManualServiceReference(
        SupplierImportResolutionParsing.id(
          data['manualServiceId'],
          'Consultant service',
        ),
      );
    }
    throw const FormatException('Resolution service reference is invalid.');
  }

  Map<String, Object?> toMap();
}

final class SupplierImportStagedServiceReference
    extends SupplierImportServiceReference {
  const SupplierImportStagedServiceReference(this.serviceId);
  final String serviceId;

  @override
  Map<String, Object?> toMap() => {
    'kind': 'staged_service',
    'serviceId': serviceId,
  };
}

final class SupplierImportManualServiceReference
    extends SupplierImportServiceReference {
  const SupplierImportManualServiceReference(this.manualServiceId);
  final String manualServiceId;

  @override
  Map<String, Object?> toMap() => {
    'kind': 'consultant_service',
    'manualServiceId': manualServiceId,
  };
}

final class SupplierImportHotelOverrides {
  const SupplierImportHotelOverrides({
    this.hotelName,
    this.city,
    this.orSimilar,
    this.checkInDate,
    this.checkOutDate,
    this.nightCount,
    this.roomType,
    this.mealPlan,
    this.numberOfRooms,
    this.supplierStarRating,
  });

  factory SupplierImportHotelOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: _hotelFields,
      required: const {},
      label: 'Hotel overrides',
    );
    return SupplierImportHotelOverrides(
      hotelName: supplierImportOptionalOverride(
        data,
        'hotelName',
        SupplierImportResolutionParsing.text,
      ),
      city: supplierImportOptionalOverride(
        data,
        'city',
        SupplierImportResolutionParsing.text,
      ),
      orSimilar: supplierImportOptionalOverride(
        data,
        'orSimilar',
        SupplierImportResolutionParsing.boolean,
      ),
      checkInDate: supplierImportOptionalOverride(
        data,
        'checkInDate',
        SupplierImportResolutionParsing.date,
      ),
      checkOutDate: supplierImportOptionalOverride(
        data,
        'checkOutDate',
        SupplierImportResolutionParsing.date,
      ),
      nightCount: supplierImportOptionalOverride(
        data,
        'nightCount',
        SupplierImportResolutionParsing.positiveInt,
      ),
      roomType: supplierImportOptionalOverride(
        data,
        'roomType',
        SupplierImportResolutionParsing.text,
      ),
      mealPlan: supplierImportOptionalOverride(
        data,
        'mealPlan',
        SupplierImportResolutionParsing.text,
      ),
      numberOfRooms: supplierImportOptionalOverride(
        data,
        'numberOfRooms',
        SupplierImportResolutionParsing.positiveInt,
      ),
      supplierStarRating: supplierImportOptionalOverride(
        data,
        'supplierStarRating',
        SupplierImportResolutionParsing.text,
      ),
    );
  }

  final SupplierImportFieldOverride<String>? hotelName;
  final SupplierImportFieldOverride<String>? city;
  final SupplierImportFieldOverride<bool>? orSimilar;
  final SupplierImportFieldOverride<String>? checkInDate;
  final SupplierImportFieldOverride<String>? checkOutDate;
  final SupplierImportFieldOverride<int>? nightCount;
  final SupplierImportFieldOverride<String>? roomType;
  final SupplierImportFieldOverride<String>? mealPlan;
  final SupplierImportFieldOverride<int>? numberOfRooms;
  final SupplierImportFieldOverride<String>? supplierStarRating;

  Map<String, Object?> toMap() => supplierImportOverrideMap({
    'hotelName': hotelName,
    'city': city,
    'orSimilar': orSimilar,
    'checkInDate': checkInDate,
    'checkOutDate': checkOutDate,
    'nightCount': nightCount,
    'roomType': roomType,
    'mealPlan': mealPlan,
    'numberOfRooms': numberOfRooms,
    'supplierStarRating': supplierStarRating,
  });
}

const _hotelFields = {
  'hotelName',
  'city',
  'orSimilar',
  'checkInDate',
  'checkOutDate',
  'nightCount',
  'roomType',
  'mealPlan',
  'numberOfRooms',
  'supplierStarRating',
};

final class SupplierImportTransferOverrides {
  const SupplierImportTransferOverrides({
    this.pickup,
    this.dropoff,
    this.vehicleType,
    this.transferType,
  });

  factory SupplierImportTransferOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {'pickup', 'dropoff', 'vehicleType', 'transferType'},
      required: const {},
      label: 'Transfer overrides',
    );
    return SupplierImportTransferOverrides(
      pickup: supplierImportOptionalOverride(
        data,
        'pickup',
        SupplierImportResolutionParsing.text,
      ),
      dropoff: supplierImportOptionalOverride(
        data,
        'dropoff',
        SupplierImportResolutionParsing.text,
      ),
      vehicleType: supplierImportOptionalOverride(
        data,
        'vehicleType',
        SupplierImportResolutionParsing.text,
      ),
      transferType: supplierImportOptionalOverride(
        data,
        'transferType',
        _transferType,
      ),
    );
  }

  final SupplierImportFieldOverride<String>? pickup;
  final SupplierImportFieldOverride<String>? dropoff;
  final SupplierImportFieldOverride<String>? vehicleType;
  final SupplierImportFieldOverride<SupplierExtractionTransferType>?
  transferType;

  Map<String, Object?> toMap() => supplierImportOverrideMap({
    'pickup': pickup,
    'dropoff': dropoff,
    'vehicleType': vehicleType,
    'transferType': transferType,
  });
}

final class SupplierImportActivityOverrides {
  const SupplierImportActivityOverrides({
    this.activityName,
    this.duration,
    this.activityType,
  });

  factory SupplierImportActivityOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {'activityName', 'duration', 'activityType'},
      required: const {},
      label: 'Activity overrides',
    );
    return SupplierImportActivityOverrides(
      activityName: supplierImportOptionalOverride(
        data,
        'activityName',
        SupplierImportResolutionParsing.text,
      ),
      duration: supplierImportOptionalOverride(
        data,
        'duration',
        SupplierImportResolutionParsing.text,
      ),
      activityType: supplierImportOptionalOverride(
        data,
        'activityType',
        SupplierImportResolutionParsing.text,
      ),
    );
  }

  final SupplierImportFieldOverride<String>? activityName;
  final SupplierImportFieldOverride<String>? duration;
  final SupplierImportFieldOverride<String>? activityType;

  Map<String, Object?> toMap() => supplierImportOverrideMap({
    'activityName': activityName,
    'duration': duration,
    'activityType': activityType,
  });
}

SupplierImportFieldOverride<T>? supplierImportOptionalOverride<T>(
  Map<String, Object?> data,
  String field,
  SupplierImportValueParser<T> parser, {
  bool setOnly = false,
}) => !data.containsKey(field)
    ? null
    : parseSupplierImportOverride(data[field], parser, field, setOnly: setOnly);

Map<String, Object?> supplierImportOverrideMap(
  Map<String, SupplierImportFieldOverride<Object?>?> values,
) => Map.unmodifiable({
  for (final entry in values.entries)
    if (entry.value != null) entry.key: entry.value!.toMap(),
});

Object? supplierImportWireValue(Object? value) {
  if (value is Enum) {
    final dynamic typed = value;
    return typed.value as String;
  }
  if (value is List) {
    return value.map(supplierImportWireValue).toList(growable: false);
  }
  if (value is SupplierImportResolutionCondition) return value.toMap();
  return value;
}

SupplierExtractionTransferType _transferType(Object? value, String label) =>
    SupplierImportResolutionParsing.enumValue(
      value,
      SupplierExtractionTransferType.values,
      (item) => item.value,
      label,
    );

final class SupplierImportResolutionCondition {
  const SupplierImportResolutionCondition({
    required this.kind,
    required this.value,
  });

  factory SupplierImportResolutionCondition.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.exact(input, const {
      'kind',
      'value',
    }, 'Resolution condition');
    return SupplierImportResolutionCondition(
      kind: SupplierImportResolutionParsing.enumValue(
        data['kind'],
        SupplierExtractionConditionKind.values,
        (item) => item.value,
        'Condition kind',
      ),
      value: SupplierImportResolutionParsing.text(
        data['value'],
        'Condition value',
      ),
    );
  }

  final SupplierExtractionConditionKind kind;
  final String value;

  Map<String, Object?> toMap() => {'kind': kind.value, 'value': value};
}
