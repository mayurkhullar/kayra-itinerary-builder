import 'supplier_extraction_parsing.dart';
import 'supplier_extraction_values.dart';

enum SupplierExtractionFactKind {
  service('service'),
  packageAccommodation('package_accommodation'),
  packageInclusion('package_inclusion'),
  packageExclusion('package_exclusion'),
  packageCondition('package_condition'),
  flight('flight'),
  visa('visa'),
  commercialPresence('commercial_presence');

  const SupplierExtractionFactKind(this.value);
  final String value;
}

sealed class SupplierExtractionFact {
  SupplierExtractionFact({
    required this.id,
    required this.factKind,
    required this.snapshotOrder,
    required this.order,
    required List<SupplierExtractionSourceReference> sources,
  }) : sources = SupplierExtractionParsing.immutableList(sources);

  final String id;
  final SupplierExtractionFactKind factKind;
  final int snapshotOrder;
  final int order;
  final List<SupplierExtractionSourceReference> sources;
}

final class SupplierExtractionServiceFact extends SupplierExtractionFact {
  SupplierExtractionServiceFact._({
    required super.id,
    required super.snapshotOrder,
    required super.order,
    required this.scope,
    required this.serviceType,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.city,
    required List<SupplierExtractionStatement> inclusions,
    required List<SupplierExtractionStatement> exclusions,
    required List<SupplierExtractionCondition> conditions,
    required this.notes,
    required this.hotelDetails,
    required this.transferDetails,
    required this.activityDetails,
    required super.sources,
  }) : inclusions = SupplierExtractionParsing.immutableList(inclusions),
       exclusions = SupplierExtractionParsing.immutableList(exclusions),
       conditions = SupplierExtractionParsing.immutableList(conditions),
       super(factKind: SupplierExtractionFactKind.service);

  factory SupplierExtractionServiceFact.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
  }) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'factKind',
      'order',
      'scope',
      'serviceType',
      'title',
      'description',
      'startTime',
      'endTime',
      'location',
      'city',
      'inclusions',
      'exclusions',
      'conditions',
      'notes',
      'hotelDetails',
      'transferDetails',
      'activityDetails',
      'sources',
    }, 'Stored service fact');
    _requireLiteral(value['factKind'], 'service', 'service fact kind');
    final serviceType = SupplierExtractionParsing.nullableEnum(
      value['serviceType'],
      SupplierExtractionServiceType.values,
      (type) => type.value,
      'service type',
    );
    final hotelDetails = value['hotelDetails'] == null
        ? null
        : SupplierExtractionHotelDetails.fromMap(
            SupplierExtractionParsing.record(
              value['hotelDetails'],
              'Stored hotel details',
            ),
          );
    final transferDetails = value['transferDetails'] == null
        ? null
        : SupplierExtractionTransferDetails.fromMap(
            SupplierExtractionParsing.record(
              value['transferDetails'],
              'Stored transfer details',
            ),
          );
    final activityDetails = value['activityDetails'] == null
        ? null
        : SupplierExtractionActivityDetails.fromMap(
            SupplierExtractionParsing.record(
              value['activityDetails'],
              'Stored activity details',
            ),
          );
    if ((hotelDetails != null &&
            serviceType != SupplierExtractionServiceType.hotel) ||
        (transferDetails != null &&
            serviceType != SupplierExtractionServiceType.transfer) ||
        (activityDetails != null &&
            serviceType != SupplierExtractionServiceType.activity)) {
      throw const FormatException(
        'Stored service details are incompatible with the service type.',
      );
    }
    final title = SupplierExtractionParsing.nullableSemanticText(
      value['title'],
      'Stored service title',
    );
    if (title == null &&
        hotelDetails == null &&
        transferDetails == null &&
        activityDetails == null) {
      throw const FormatException(
        'Stored service requires an identifying fact.',
      );
    }
    return SupplierExtractionServiceFact._(
      id: SupplierExtractionParsing.id(value['id'], 'Staged service'),
      snapshotOrder: snapshotOrder,
      order: SupplierExtractionParsing.positiveInteger(
        value['order'],
        'Staged service order',
      ),
      scope: SupplierExtractionServiceScope.fromMap(
        SupplierExtractionParsing.record(
          value['scope'],
          'Stored service scope',
        ),
      ),
      serviceType: serviceType,
      title: title,
      description: SupplierExtractionParsing.nullableSemanticText(
        value['description'],
        'Service description',
      ),
      startTime: SupplierExtractionParsing.nullableTime(
        value['startTime'],
        'Service start time',
      ),
      endTime: SupplierExtractionParsing.nullableTime(
        value['endTime'],
        'Service end time',
      ),
      location: SupplierExtractionParsing.nullableSemanticText(
        value['location'],
        'Service location',
      ),
      city: SupplierExtractionParsing.nullableSemanticText(
        value['city'],
        'Service city',
      ),
      inclusions: _statements(value['inclusions'], 'Service inclusions'),
      exclusions: _statements(value['exclusions'], 'Service exclusions'),
      conditions: _conditions(value['conditions'], 'Service conditions'),
      notes: SupplierExtractionParsing.nullableSemanticText(
        value['notes'],
        'Service notes',
      ),
      hotelDetails: hotelDetails,
      transferDetails: transferDetails,
      activityDetails: activityDetails,
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final SupplierExtractionServiceScope scope;
  final SupplierExtractionServiceType? serviceType;
  final String? title;
  final String? description;
  final String? startTime;
  final String? endTime;
  final String? location;
  final String? city;
  final List<SupplierExtractionStatement> inclusions;
  final List<SupplierExtractionStatement> exclusions;
  final List<SupplierExtractionCondition> conditions;
  final String? notes;
  final SupplierExtractionHotelDetails? hotelDetails;
  final SupplierExtractionTransferDetails? transferDetails;
  final SupplierExtractionActivityDetails? activityDetails;
}

final class SupplierExtractionPackageAccommodationFact
    extends SupplierExtractionFact {
  SupplierExtractionPackageAccommodationFact._({
    required super.id,
    required super.snapshotOrder,
    required super.order,
    required this.details,
    required super.sources,
  }) : super(factKind: SupplierExtractionFactKind.packageAccommodation);

  factory SupplierExtractionPackageAccommodationFact.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
  }) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'factKind',
      'order',
      'scope',
      'details',
      'sources',
    }, 'Stored package accommodation');
    _requireLiteral(
      value['factKind'],
      'package_accommodation',
      'package fact kind',
    );
    _requireScope(value['scope'], 'package');
    return SupplierExtractionPackageAccommodationFact._(
      id: SupplierExtractionParsing.id(value['id'], 'Package accommodation'),
      snapshotOrder: snapshotOrder,
      order: SupplierExtractionParsing.positiveInteger(
        value['order'],
        'Package fact order',
      ),
      details: SupplierExtractionHotelDetails.fromMap(
        SupplierExtractionParsing.record(
          value['details'],
          'Stored hotel details',
        ),
      ),
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final SupplierExtractionHotelDetails details;
}

final class SupplierExtractionPackageStatementFact
    extends SupplierExtractionFact {
  SupplierExtractionPackageStatementFact._({
    required super.id,
    required super.factKind,
    required super.snapshotOrder,
    required super.order,
    required this.category,
    required this.text,
    required this.quantity,
    required this.frequency,
    required List<SupplierExtractionServiceType> appliesTo,
    required super.sources,
  }) : appliesTo = SupplierExtractionParsing.immutableList(appliesTo);

  factory SupplierExtractionPackageStatementFact.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
    required SupplierExtractionFactKind factKind,
  }) {
    if (factKind != SupplierExtractionFactKind.packageInclusion &&
        factKind != SupplierExtractionFactKind.packageExclusion) {
      throw const FormatException('Stored package statement kind is invalid.');
    }
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'factKind',
      'order',
      'scope',
      'category',
      'text',
      'quantity',
      'frequency',
      'appliesTo',
      'sources',
    }, 'Stored package statement');
    _requireLiteral(
      value['factKind'],
      factKind.value,
      'package statement kind',
    );
    _requireScope(value['scope'], 'package');
    final appliesTo = _serviceTypes(
      value['appliesTo'],
      'Statement applicability',
    );
    return SupplierExtractionPackageStatementFact._(
      id: SupplierExtractionParsing.id(value['id'], 'Package statement'),
      factKind: factKind,
      snapshotOrder: snapshotOrder,
      order: SupplierExtractionParsing.positiveInteger(
        value['order'],
        'Package fact order',
      ),
      category: SupplierExtractionParsing.enumValue(
        value['category'],
        SupplierExtractionStatementCategory.values,
        (category) => category.value,
        'statement category',
      ),
      text: SupplierExtractionParsing.semanticText(
        value['text'],
        'Package statement text',
      ),
      quantity: SupplierExtractionParsing.nullablePositiveInteger(
        value['quantity'],
        'Statement quantity',
      ),
      frequency: SupplierExtractionParsing.nullableSemanticText(
        value['frequency'],
        'Statement frequency',
      ),
      appliesTo: appliesTo,
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final SupplierExtractionStatementCategory category;
  final String text;
  final int? quantity;
  final String? frequency;
  final List<SupplierExtractionServiceType> appliesTo;
}

final class SupplierExtractionPackageConditionFact
    extends SupplierExtractionFact {
  SupplierExtractionPackageConditionFact._({
    required super.id,
    required super.snapshotOrder,
    required super.order,
    required this.kind,
    required this.value,
    required List<SupplierExtractionServiceType> appliesTo,
    required super.sources,
  }) : appliesTo = SupplierExtractionParsing.immutableList(appliesTo),
       super(factKind: SupplierExtractionFactKind.packageCondition);

  factory SupplierExtractionPackageConditionFact.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
  }) {
    final parsed = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'factKind',
      'order',
      'scope',
      'kind',
      'value',
      'appliesTo',
      'sources',
    }, 'Stored package condition');
    _requireLiteral(
      parsed['factKind'],
      'package_condition',
      'package condition kind',
    );
    _requireScope(parsed['scope'], 'package');
    return SupplierExtractionPackageConditionFact._(
      id: SupplierExtractionParsing.id(parsed['id'], 'Package condition'),
      snapshotOrder: snapshotOrder,
      order: SupplierExtractionParsing.positiveInteger(
        parsed['order'],
        'Package fact order',
      ),
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
      appliesTo: _serviceTypes(parsed['appliesTo'], 'Condition applicability'),
      sources: parseSupplierExtractionSources(parsed['sources']),
    );
  }

  final SupplierExtractionConditionKind kind;
  final String value;
  final List<SupplierExtractionServiceType> appliesTo;
}

final class SupplierExtractionFlightFact extends SupplierExtractionFact {
  SupplierExtractionFlightFact._({
    required super.id,
    required super.snapshotOrder,
    required super.order,
    required this.airline,
    required this.flightNumber,
    required this.origin,
    required this.destination,
    required this.departureDate,
    required this.departureTime,
    required this.arrivalDate,
    required this.arrivalTime,
    required this.cabinClass,
    required this.bookingClass,
    required this.notes,
    required List<SupplierExtractionCondition> conditions,
    required super.sources,
  }) : conditions = SupplierExtractionParsing.immutableList(conditions),
       super(factKind: SupplierExtractionFactKind.flight);

  factory SupplierExtractionFlightFact.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
  }) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'factKind',
      'order',
      'scope',
      'airline',
      'flightNumber',
      'origin',
      'destination',
      'departureDate',
      'departureTime',
      'arrivalDate',
      'arrivalTime',
      'cabinClass',
      'bookingClass',
      'notes',
      'conditions',
      'sources',
    }, 'Stored flight fact');
    _requireLiteral(value['factKind'], 'flight', 'flight fact kind');
    _requireScope(value['scope'], 'ancillary');
    final airline = SupplierExtractionParsing.nullableSemanticText(
      value['airline'],
      'Flight airline',
    );
    final flightNumber = SupplierExtractionParsing.nullableSemanticText(
      value['flightNumber'],
      'Flight number',
    );
    final origin = SupplierExtractionParsing.nullableSemanticText(
      value['origin'],
      'Flight origin',
    );
    final destination = SupplierExtractionParsing.nullableSemanticText(
      value['destination'],
      'Flight destination',
    );
    if ([
      airline,
      flightNumber,
      origin,
      destination,
    ].every((value) => value == null)) {
      throw const FormatException(
        'Stored flight requires an identifying fact.',
      );
    }
    return SupplierExtractionFlightFact._(
      id: SupplierExtractionParsing.id(value['id'], 'Ancillary flight'),
      snapshotOrder: snapshotOrder,
      order: SupplierExtractionParsing.positiveInteger(
        value['order'],
        'Flight order',
      ),
      airline: airline,
      flightNumber: flightNumber,
      origin: origin,
      destination: destination,
      departureDate: SupplierExtractionParsing.nullableDate(
        value['departureDate'],
        'Flight departure date',
      ),
      departureTime: SupplierExtractionParsing.nullableTime(
        value['departureTime'],
        'Flight departure time',
      ),
      arrivalDate: SupplierExtractionParsing.nullableDate(
        value['arrivalDate'],
        'Flight arrival date',
      ),
      arrivalTime: SupplierExtractionParsing.nullableTime(
        value['arrivalTime'],
        'Flight arrival time',
      ),
      cabinClass: SupplierExtractionParsing.nullableSemanticText(
        value['cabinClass'],
        'Flight cabin class',
      ),
      bookingClass: SupplierExtractionParsing.nullableSemanticText(
        value['bookingClass'],
        'Flight booking class',
      ),
      notes: SupplierExtractionParsing.nullableSemanticText(
        value['notes'],
        'Flight notes',
      ),
      conditions: _conditions(value['conditions'], 'Flight conditions'),
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final String? airline;
  final String? flightNumber;
  final String? origin;
  final String? destination;
  final DateTime? departureDate;
  final String? departureTime;
  final DateTime? arrivalDate;
  final String? arrivalTime;
  final String? cabinClass;
  final String? bookingClass;
  final String? notes;
  final List<SupplierExtractionCondition> conditions;
}

final class SupplierExtractionVisaFact extends SupplierExtractionFact {
  SupplierExtractionVisaFact._({
    required super.id,
    required super.snapshotOrder,
    required super.order,
    required this.disposition,
    required this.text,
    required super.sources,
  }) : super(factKind: SupplierExtractionFactKind.visa);

  factory SupplierExtractionVisaFact.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
  }) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'factKind',
      'order',
      'scope',
      'disposition',
      'text',
      'sources',
    }, 'Stored visa fact');
    _requireLiteral(value['factKind'], 'visa', 'visa fact kind');
    _requireScope(value['scope'], 'ancillary');
    final disposition = SupplierExtractionParsing.enumValue(
      value['disposition'],
      SupplierExtractionVisaDisposition.values,
      (item) => item.value,
      'visa disposition',
    );
    final text = SupplierExtractionParsing.nullableSemanticText(
      value['text'],
      'Visa fact text',
    );
    if ((disposition == SupplierExtractionVisaDisposition.requirement ||
            disposition == SupplierExtractionVisaDisposition.unclear) &&
        text == null) {
      throw const FormatException(
        'Stored visa requirement or uncertainty requires text.',
      );
    }
    return SupplierExtractionVisaFact._(
      id: SupplierExtractionParsing.id(value['id'], 'Ancillary visa'),
      snapshotOrder: snapshotOrder,
      order: SupplierExtractionParsing.positiveInteger(
        value['order'],
        'Visa order',
      ),
      disposition: disposition,
      text: text,
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final SupplierExtractionVisaDisposition disposition;
  final String? text;
}

final class SupplierExtractionCommercialPresenceFact
    extends SupplierExtractionFact {
  SupplierExtractionCommercialPresenceFact._({
    required super.id,
    required super.snapshotOrder,
    required super.order,
    required List<SupplierExtractionCommercialCategory> categories,
    required super.sources,
  }) : categories = SupplierExtractionParsing.immutableList(categories),
       super(factKind: SupplierExtractionFactKind.commercialPresence);

  factory SupplierExtractionCommercialPresenceFact.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
  }) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'factKind',
      'order',
      'scope',
      'categories',
      'sources',
    }, 'Stored commercial indicator');
    _requireLiteral(
      value['factKind'],
      'commercial_presence',
      'commercial fact kind',
    );
    _requireScope(value['scope'], 'package');
    final categories =
        SupplierExtractionParsing.list(
              value['categories'],
              'Commercial categories',
            )
            .map(
              (item) => SupplierExtractionParsing.enumValue(
                item,
                SupplierExtractionCommercialCategory.values,
                (category) => category.value,
                'commercial category',
              ),
            )
            .toList();
    if (categories.isEmpty) {
      throw const FormatException('Stored commercial categories are empty.');
    }
    SupplierExtractionParsing.unique(categories, 'commercial categories');
    return SupplierExtractionCommercialPresenceFact._(
      id: SupplierExtractionParsing.id(value['id'], 'Commercial indicator'),
      snapshotOrder: snapshotOrder,
      order: SupplierExtractionParsing.positiveInteger(
        value['order'],
        'Commercial indicator order',
      ),
      categories: categories,
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final List<SupplierExtractionCommercialCategory> categories;
}

SupplierExtractionFact parseSupplierExtractionFact(
  Map<String, Object?> data, {
  required int snapshotOrder,
}) {
  final kind = data['factKind'];
  return switch (kind) {
    'service' => SupplierExtractionServiceFact.fromMap(
      data,
      snapshotOrder: snapshotOrder,
    ),
    'package_accommodation' =>
      SupplierExtractionPackageAccommodationFact.fromMap(
        data,
        snapshotOrder: snapshotOrder,
      ),
    'package_inclusion' => SupplierExtractionPackageStatementFact.fromMap(
      data,
      snapshotOrder: snapshotOrder,
      factKind: SupplierExtractionFactKind.packageInclusion,
    ),
    'package_exclusion' => SupplierExtractionPackageStatementFact.fromMap(
      data,
      snapshotOrder: snapshotOrder,
      factKind: SupplierExtractionFactKind.packageExclusion,
    ),
    'package_condition' => SupplierExtractionPackageConditionFact.fromMap(
      data,
      snapshotOrder: snapshotOrder,
    ),
    'flight' => SupplierExtractionFlightFact.fromMap(
      data,
      snapshotOrder: snapshotOrder,
    ),
    'visa' => SupplierExtractionVisaFact.fromMap(
      data,
      snapshotOrder: snapshotOrder,
    ),
    'commercial_presence' => SupplierExtractionCommercialPresenceFact.fromMap(
      data,
      snapshotOrder: snapshotOrder,
    ),
    _ => throw const FormatException('Stored staged fact kind is invalid.'),
  };
}

List<SupplierExtractionStatement> _statements(Object? value, String label) =>
    SupplierExtractionParsing.immutableList(
      SupplierExtractionParsing.list(value, label).map(
        (item) => SupplierExtractionStatement.fromMap(
          SupplierExtractionParsing.record(item, 'Stored statement'),
        ),
      ),
    );

List<SupplierExtractionCondition> _conditions(Object? value, String label) =>
    SupplierExtractionParsing.immutableList(
      SupplierExtractionParsing.list(value, label).map(
        (item) => SupplierExtractionCondition.fromMap(
          SupplierExtractionParsing.record(item, 'Stored condition'),
        ),
      ),
    );

List<SupplierExtractionServiceType> _serviceTypes(Object? value, String label) {
  final values = SupplierExtractionParsing.list(value, label)
      .map(
        (item) => SupplierExtractionParsing.enumValue(
          item,
          SupplierExtractionServiceType.values,
          (type) => type.value,
          'service type',
        ),
      )
      .toList();
  SupplierExtractionParsing.unique(values, label);
  return SupplierExtractionParsing.immutableList(values);
}

void _requireScope(Object? value, String expected) {
  final scope = SupplierExtractionParsing.exactRecord(value, {
    'kind',
  }, 'Stored $expected scope');
  _requireLiteral(scope['kind'], expected, '$expected scope');
}

void _requireLiteral(Object? value, String expected, String label) {
  if (value != expected) throw FormatException('Stored $label is invalid.');
}
