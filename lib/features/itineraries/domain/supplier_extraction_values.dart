import 'supplier_extraction_parsing.dart';

enum SupplierExtractionTitleBasis {
  explicitSupplier('explicit_supplier'),
  neutralSupported('neutral_supported');

  const SupplierExtractionTitleBasis(this.value);
  final String value;
}

enum SupplierExtractionServiceType {
  hotel('hotel'),
  transfer('transfer'),
  activity('activity'),
  meal('meal'),
  sightseeing('sightseeing'),
  freeTime('free_time'),
  other('other');

  const SupplierExtractionServiceType(this.value);
  final String value;
}

enum SupplierExtractionTransferType {
  private('private'),
  shared('shared'),
  scheduled('scheduled'),
  other('other');

  const SupplierExtractionTransferType(this.value);
  final String value;
}

enum SupplierExtractionStatementCategory {
  accommodation('accommodation'),
  meal('meal'),
  guide('guide'),
  water('water'),
  entrance('entrance'),
  transport('transport'),
  visa('visa'),
  other('other');

  const SupplierExtractionStatementCategory(this.value);
  final String value;
}

enum SupplierExtractionConditionKind {
  operatingBasis('operating_basis'),
  vehicle('vehicle'),
  travelClass('class'),
  ticketScope('ticket_scope'),
  availability('availability'),
  paymentBasis('payment_basis'),
  guide('guide'),
  other('other');

  const SupplierExtractionConditionKind(this.value);
  final String value;
}

enum SupplierExtractionCommercialCategory {
  packagePrice('package_price'),
  perPersonPrice('per_person_price'),
  supplement('supplement'),
  visaPrice('visa_price'),
  paymentTerms('payment_terms'),
  otherCommercialTerms('other_commercial_terms');

  const SupplierExtractionCommercialCategory(this.value);
  final String value;
}

enum SupplierExtractionVisaDisposition {
  included('included'),
  excluded('excluded'),
  requirement('requirement'),
  mentioned('mentioned'),
  unclear('unclear');

  const SupplierExtractionVisaDisposition(this.value);
  final String value;
}

final class SupplierExtractionSourceReference {
  SupplierExtractionSourceReference._({
    required this.supplierSourcePackageId,
    required this.supplierSourceFileId,
    required this.sourceLabel,
  });

  factory SupplierExtractionSourceReference.fromMap(Map<String, Object?> data) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'supplierSourcePackageId',
      'supplierSourceFileId',
      'sourceLabel',
    }, 'Trusted source reference');
    return SupplierExtractionSourceReference._(
      supplierSourcePackageId: SupplierExtractionParsing.id(
        value['supplierSourcePackageId'],
        'Trusted source package',
      ),
      supplierSourceFileId: value['supplierSourceFileId'] == null
          ? null
          : SupplierExtractionParsing.id(
              value['supplierSourceFileId'],
              'Trusted source file',
            ),
      sourceLabel: SupplierExtractionParsing.nullableSemanticText(
        value['sourceLabel'],
        'Source label',
      ),
    );
  }

  final String supplierSourcePackageId;
  final String? supplierSourceFileId;
  final String? sourceLabel;

  String get identityKey =>
      '$supplierSourcePackageId\u0000${supplierSourceFileId ?? ''}\u0000${sourceLabel ?? ''}';
}

List<SupplierExtractionSourceReference> parseSupplierExtractionSources(
  Object? value,
) {
  final sources =
      SupplierExtractionParsing.list(value, 'Trusted source references')
          .map(
            (item) => SupplierExtractionSourceReference.fromMap(
              SupplierExtractionParsing.record(
                item,
                'Trusted source reference',
              ),
            ),
          )
          .toList();
  if (sources.isEmpty) {
    throw const FormatException('Trusted source references are required.');
  }
  SupplierExtractionParsing.unique(
    sources.map((source) => source.identityKey),
    'trusted source references',
  );
  return SupplierExtractionParsing.immutableList(sources);
}

final class SupplierExtractionTitle {
  SupplierExtractionTitle._({
    required this.text,
    required this.basis,
    required this.sources,
  });

  factory SupplierExtractionTitle.fromMap(Map<String, Object?> data) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'text',
      'basis',
      'sources',
    }, 'Stored title');
    return SupplierExtractionTitle._(
      text: SupplierExtractionParsing.semanticText(
        value['text'],
        'Stored title text',
      ),
      basis: SupplierExtractionParsing.enumValue(
        value['basis'],
        SupplierExtractionTitleBasis.values,
        (item) => item.value,
        'stored title basis',
      ),
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final String text;
  final SupplierExtractionTitleBasis basis;
  final List<SupplierExtractionSourceReference> sources;
}

sealed class SupplierExtractionServiceScope {
  const SupplierExtractionServiceScope();

  factory SupplierExtractionServiceScope.fromMap(Map<String, Object?> data) {
    if (data['kind'] == 'unassigned') {
      SupplierExtractionParsing.exactRecord(data, {
        'kind',
      }, 'Stored unassigned scope');
      return const SupplierExtractionUnassignedScope();
    }
    if (data['kind'] == 'day') {
      final value = SupplierExtractionParsing.exactRecord(data, {
        'kind',
        'dayId',
      }, 'Stored day scope');
      return SupplierExtractionDayScope(
        SupplierExtractionParsing.id(value['dayId'], 'Staged day'),
      );
    }
    throw const FormatException('Stored service scope is invalid.');
  }
}

final class SupplierExtractionDayScope extends SupplierExtractionServiceScope {
  const SupplierExtractionDayScope(this.dayId);
  final String dayId;
}

final class SupplierExtractionUnassignedScope
    extends SupplierExtractionServiceScope {
  const SupplierExtractionUnassignedScope();
}

final class SupplierExtractionStatement {
  SupplierExtractionStatement._({
    required this.id,
    required this.category,
    required this.text,
    required this.quantity,
    required this.frequency,
    required this.appliesTo,
    required this.sources,
  });

  factory SupplierExtractionStatement.fromMap(Map<String, Object?> data) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'category',
      'text',
      'quantity',
      'frequency',
      'appliesTo',
      'sources',
    }, 'Stored statement');
    final appliesTo =
        SupplierExtractionParsing.list(
              value['appliesTo'],
              'Statement applicability',
            )
            .map(
              (item) => SupplierExtractionParsing.enumValue(
                item,
                SupplierExtractionServiceType.values,
                (type) => type.value,
                'service type',
              ),
            )
            .toList();
    SupplierExtractionParsing.unique(appliesTo, 'statement applicability');
    return SupplierExtractionStatement._(
      id: SupplierExtractionParsing.id(value['id'], 'Statement'),
      category: SupplierExtractionParsing.enumValue(
        value['category'],
        SupplierExtractionStatementCategory.values,
        (category) => category.value,
        'statement category',
      ),
      text: SupplierExtractionParsing.semanticText(
        value['text'],
        'Statement text',
      ),
      quantity: SupplierExtractionParsing.nullablePositiveInteger(
        value['quantity'],
        'Statement quantity',
      ),
      frequency: SupplierExtractionParsing.nullableSemanticText(
        value['frequency'],
        'Statement frequency',
      ),
      appliesTo: SupplierExtractionParsing.immutableList(appliesTo),
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final String id;
  final SupplierExtractionStatementCategory category;
  final String text;
  final int? quantity;
  final String? frequency;
  final List<SupplierExtractionServiceType> appliesTo;
  final List<SupplierExtractionSourceReference> sources;
}

final class SupplierExtractionCondition {
  SupplierExtractionCondition._({
    required this.id,
    required this.kind,
    required this.value,
    required this.sources,
  });

  factory SupplierExtractionCondition.fromMap(Map<String, Object?> data) {
    final parsed = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'kind',
      'value',
      'sources',
    }, 'Stored condition');
    return SupplierExtractionCondition._(
      id: SupplierExtractionParsing.id(parsed['id'], 'Condition'),
      kind: SupplierExtractionParsing.enumValue(
        parsed['kind'],
        SupplierExtractionConditionKind.values,
        (kind) => kind.value,
        'condition kind',
      ),
      value: SupplierExtractionParsing.semanticText(
        parsed['value'],
        'Condition value',
      ),
      sources: parseSupplierExtractionSources(parsed['sources']),
    );
  }

  final String id;
  final SupplierExtractionConditionKind kind;
  final String value;
  final List<SupplierExtractionSourceReference> sources;
}

final class SupplierExtractionHotelDetails {
  SupplierExtractionHotelDetails._({
    required this.hotelName,
    required this.city,
    required this.orSimilar,
    required this.checkInDate,
    required this.checkOutDate,
    required this.nightCount,
    required this.roomType,
    required this.mealPlan,
    required this.numberOfRooms,
    required this.supplierStarRating,
  });

  factory SupplierExtractionHotelDetails.fromMap(Map<String, Object?> data) {
    final value = SupplierExtractionParsing.exactRecord(data, {
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
    }, 'Stored hotel details');
    final details = SupplierExtractionHotelDetails._(
      hotelName: SupplierExtractionParsing.nullableSemanticText(
        value['hotelName'],
        'Hotel name',
      ),
      city: SupplierExtractionParsing.nullableSemanticText(
        value['city'],
        'Hotel city',
      ),
      orSimilar: SupplierExtractionParsing.nullableBoolean(
        value['orSimilar'],
        'Hotel or-similar qualifier',
      ),
      checkInDate: SupplierExtractionParsing.nullableDate(
        value['checkInDate'],
        'Hotel check-in date',
      ),
      checkOutDate: SupplierExtractionParsing.nullableDate(
        value['checkOutDate'],
        'Hotel check-out date',
      ),
      nightCount: SupplierExtractionParsing.nullablePositiveInteger(
        value['nightCount'],
        'Hotel night count',
      ),
      roomType: SupplierExtractionParsing.nullableSemanticText(
        value['roomType'],
        'Hotel room type',
      ),
      mealPlan: SupplierExtractionParsing.nullableSemanticText(
        value['mealPlan'],
        'Hotel meal plan',
      ),
      numberOfRooms: SupplierExtractionParsing.nullablePositiveInteger(
        value['numberOfRooms'],
        'Hotel room count',
      ),
      supplierStarRating: SupplierExtractionParsing.nullableSemanticText(
        value['supplierStarRating'],
        'Supplier star rating',
      ),
    );
    if (details.values.every((value) => value == null)) {
      throw const FormatException(
        'Stored hotel details require a supported fact.',
      );
    }
    if (details.checkInDate != null &&
        details.checkOutDate != null &&
        !details.checkOutDate!.isAfter(details.checkInDate!)) {
      throw const FormatException('Hotel check-out must follow check-in.');
    }
    return details;
  }

  final String? hotelName;
  final String? city;
  final bool? orSimilar;
  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final int? nightCount;
  final String? roomType;
  final String? mealPlan;
  final int? numberOfRooms;
  final String? supplierStarRating;

  List<Object?> get values => [
    hotelName,
    city,
    orSimilar,
    checkInDate,
    checkOutDate,
    nightCount,
    roomType,
    mealPlan,
    numberOfRooms,
    supplierStarRating,
  ];
}

final class SupplierExtractionTransferDetails {
  SupplierExtractionTransferDetails._({
    required this.pickup,
    required this.dropoff,
    required this.vehicleType,
    required this.transferType,
  });

  factory SupplierExtractionTransferDetails.fromMap(Map<String, Object?> data) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'pickup',
      'dropoff',
      'vehicleType',
      'transferType',
    }, 'Stored transfer details');
    final details = SupplierExtractionTransferDetails._(
      pickup: SupplierExtractionParsing.nullableSemanticText(
        value['pickup'],
        'Transfer pickup',
      ),
      dropoff: SupplierExtractionParsing.nullableSemanticText(
        value['dropoff'],
        'Transfer drop-off',
      ),
      vehicleType: SupplierExtractionParsing.nullableSemanticText(
        value['vehicleType'],
        'Transfer vehicle',
      ),
      transferType: SupplierExtractionParsing.nullableEnum(
        value['transferType'],
        SupplierExtractionTransferType.values,
        (type) => type.value,
        'transfer type',
      ),
    );
    if ([
      details.pickup,
      details.dropoff,
      details.vehicleType,
      details.transferType,
    ].every((value) => value == null)) {
      throw const FormatException(
        'Stored transfer details require a supported fact.',
      );
    }
    return details;
  }

  final String? pickup;
  final String? dropoff;
  final String? vehicleType;
  final SupplierExtractionTransferType? transferType;
}

final class SupplierExtractionActivityDetails {
  SupplierExtractionActivityDetails._({
    required this.activityName,
    required this.duration,
    required this.activityType,
  });

  factory SupplierExtractionActivityDetails.fromMap(Map<String, Object?> data) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'activityName',
      'duration',
      'activityType',
    }, 'Stored activity details');
    final details = SupplierExtractionActivityDetails._(
      activityName: SupplierExtractionParsing.nullableSemanticText(
        value['activityName'],
        'Activity name',
      ),
      duration: SupplierExtractionParsing.nullableSemanticText(
        value['duration'],
        'Activity duration',
      ),
      activityType: SupplierExtractionParsing.nullableSemanticText(
        value['activityType'],
        'Activity type',
      ),
    );
    if ([
      details.activityName,
      details.duration,
      details.activityType,
    ].every((value) => value == null)) {
      throw const FormatException(
        'Stored activity details require a supported fact.',
      );
    }
    return details;
  }

  final String? activityName;
  final String? duration;
  final String? activityType;
}
