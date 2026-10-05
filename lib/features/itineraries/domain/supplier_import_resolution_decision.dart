import 'supplier_extraction_values.dart';
import 'supplier_import_resolution_overrides.dart';
import 'supplier_import_resolution_parsing.dart';

enum SupplierImportRetainDisposition {
  retain('retain'),
  exclude('exclude');

  const SupplierImportRetainDisposition(this.value);
  final String value;
}

enum SupplierImportTitleDisposition {
  accept('accept'),
  override('override');

  const SupplierImportTitleDisposition(this.value);
  final String value;
}

enum SupplierImportAccommodationDisposition {
  mapToDayService('map_to_day_service'),
  retainPackageLevel('retain_package_level'),
  exclude('exclude');

  const SupplierImportAccommodationDisposition(this.value);
  final String value;
}

enum SupplierImportPackageDisposition {
  retainPackageLevel('retain_package_level'),
  mapToService('map_to_service'),
  exclude('exclude');

  const SupplierImportPackageDisposition(this.value);
  final String value;
}

enum SupplierImportPackageDestination {
  serviceInclusion('service_inclusion'),
  serviceExclusion('service_exclusion'),
  serviceNotes('service_notes'),
  transferVehicleType('transfer_vehicle_type'),
  transferType('transfer_type');

  const SupplierImportPackageDestination(this.value);
  final String value;
}

enum SupplierImportFlightDisposition {
  routeToFlightWorkflow('route_to_flight_workflow'),
  handledSeparately('handled_separately'),
  exclude('exclude');

  const SupplierImportFlightDisposition(this.value);
  final String value;
}

enum SupplierImportVisaDecisionDisposition {
  routeToVisaWorkflow('route_to_visa_workflow'),
  handledSeparately('handled_separately'),
  exclude('exclude');

  const SupplierImportVisaDecisionDisposition(this.value);
  final String value;
}

enum SupplierImportReviewOutcome {
  acknowledged('acknowledged'),
  resolved('resolved'),
  overridden('overridden');

  const SupplierImportReviewOutcome(this.value);
  final String value;
}

final class SupplierImportDecisionMetadata {
  const SupplierImportDecisionMetadata({
    required this.decisionId,
    required this.lastRevision,
    required this.updatedByUid,
    required this.updatedAt,
  });

  factory SupplierImportDecisionMetadata.fromMap(Map<String, Object?> data) =>
      SupplierImportDecisionMetadata(
        decisionId: SupplierImportResolutionParsing.id(
          data['decisionId'],
          'Decision',
        ),
        lastRevision: SupplierImportResolutionParsing.positiveInt(
          data['lastRevision'],
          'Decision revision',
        ),
        updatedByUid: SupplierImportResolutionParsing.id(
          data['updatedByUid'],
          'Decision updater',
        ),
        updatedAt: SupplierImportResolutionParsing.timestamp(
          data['updatedAt'],
          'Decision update time',
        ),
      );

  final String decisionId;
  final int lastRevision;
  final String updatedByUid;
  final DateTime updatedAt;
}

final class SupplierImportStoredDecision {
  const SupplierImportStoredDecision({
    required this.metadata,
    required this.payload,
  });

  factory SupplierImportStoredDecision.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.record(
      input,
      'Stored resolution decision',
    );
    final payload = SupplierImportDecisionPayload.fromStoredMap(data);
    final metadata = SupplierImportDecisionMetadata.fromMap(data);
    final expectedId = payload is SupplierImportTitleDecision
        ? 'title'
        : payload.targetEntityId;
    if (metadata.decisionId != expectedId) {
      throw const FormatException('Stored decision identity is invalid.');
    }
    return SupplierImportStoredDecision(metadata: metadata, payload: payload);
  }

  final SupplierImportDecisionMetadata metadata;
  final SupplierImportDecisionPayload payload;
}

sealed class SupplierImportDecisionPayload {
  const SupplierImportDecisionPayload({required this.targetEntityId});

  factory SupplierImportDecisionPayload.fromStoredMap(
    Map<String, Object?> data,
  ) => switch (data['decisionKind']) {
    'title' => SupplierImportTitleDecision.fromStoredMap(data),
    'day' => SupplierImportDayDecision.fromStoredMap(data),
    'service' => SupplierImportServiceDecision.fromStoredMap(data),
    'package_accommodation' =>
      SupplierImportPackageAccommodationDecision.fromStoredMap(data),
    'package_statement' => SupplierImportPackageStatementDecision.fromStoredMap(
      data,
    ),
    'package_condition' => SupplierImportPackageConditionDecision.fromStoredMap(
      data,
    ),
    'flight' => SupplierImportFlightDecision.fromStoredMap(data),
    'visa' => SupplierImportVisaDecision.fromStoredMap(data),
    'review_issue' => SupplierImportReviewIssueDecision.fromStoredMap(data),
    _ => throw const FormatException('Stored decision kind is invalid.'),
  };

  final String targetEntityId;
  String get decisionKind;
  Map<String, Object?> toMutationMap();
}

const _decisionMetadataFields = {
  'decisionId',
  'lastRevision',
  'updatedByUid',
  'updatedAt',
};

Set<String> _storedFields(Set<String> semantic) => {
  ...semantic,
  ..._decisionMetadataFields,
};

final class SupplierImportTitleDecision extends SupplierImportDecisionPayload {
  const SupplierImportTitleDecision({
    required this.disposition,
    this.titleOverride,
  }) : super(targetEntityId: 'title');

  factory SupplierImportTitleDecision.fromStoredMap(
    Map<String, Object?> input,
  ) {
    final data = SupplierImportResolutionParsing.exact(
      input,
      _storedFields(const {
        'decisionKind',
        'targetEntityId',
        'disposition',
        'overrides',
      }),
      'Title decision',
    );
    if (data['targetEntityId'] != 'title') {
      throw const FormatException('Title decision target is invalid.');
    }
    final overrides = SupplierImportResolutionParsing.closed(
      data['overrides'],
      allowed: const {'title'},
      required: const {},
      label: 'Title overrides',
    );
    final result = SupplierImportTitleDecision(
      disposition: _enum(
        data['disposition'],
        SupplierImportTitleDisposition.values,
        (item) => item.value,
        'Title disposition',
      ),
      titleOverride:
          supplierImportOptionalOverride(
                overrides,
                'title',
                SupplierImportResolutionParsing.text,
                setOnly: true,
              )
              as SupplierImportSetOverride<String>?,
    );
    if ((result.disposition == SupplierImportTitleDisposition.override) !=
        (result.titleOverride != null)) {
      throw const FormatException('Title override is inconsistent.');
    }
    return result;
  }

  final SupplierImportTitleDisposition disposition;
  final SupplierImportSetOverride<String>? titleOverride;

  @override
  String get decisionKind => 'title';

  @override
  Map<String, Object?> toMutationMap() => {
    'decisionKind': decisionKind,
    'targetEntityId': targetEntityId,
    'disposition': disposition.value,
    'overrides': {if (titleOverride != null) 'title': titleOverride!.toMap()},
  };
}

final class SupplierImportDayOverrides {
  const SupplierImportDayOverrides({
    this.date,
    this.title,
    this.summary,
    this.notes,
  });

  factory SupplierImportDayOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {'date', 'title', 'summary', 'notes'},
      required: const {},
      label: 'Day overrides',
    );
    return SupplierImportDayOverrides(
      date: supplierImportOptionalOverride(
        data,
        'date',
        SupplierImportResolutionParsing.date,
      ),
      title:
          supplierImportOptionalOverride(
                data,
                'title',
                SupplierImportResolutionParsing.text,
                setOnly: true,
              )
              as SupplierImportSetOverride<String>?,
      summary: supplierImportOptionalOverride(
        data,
        'summary',
        SupplierImportResolutionParsing.text,
      ),
      notes: supplierImportOptionalOverride(
        data,
        'notes',
        SupplierImportResolutionParsing.text,
      ),
    );
  }

  final SupplierImportFieldOverride<String>? date;
  final SupplierImportSetOverride<String>? title;
  final SupplierImportFieldOverride<String>? summary;
  final SupplierImportFieldOverride<String>? notes;

  Map<String, Object?> toMap() => supplierImportOverrideMap({
    'date': date,
    'title': title,
    'summary': summary,
    'notes': notes,
  });
}

final class SupplierImportDayDecision extends SupplierImportDecisionPayload {
  const SupplierImportDayDecision({
    required super.targetEntityId,
    required this.disposition,
    required this.overrides,
    required this.exclusionReason,
    required this.exclusionNote,
    this.canonicalOrder,
  });

  factory SupplierImportDayDecision.fromStoredMap(Map<String, Object?> input) {
    final data = _decisionRecord(
      input,
      const {
        'canonicalOrder',
        'overrides',
        'disposition',
        'exclusionReason',
        'exclusionNote',
      },
      const {'overrides', 'disposition', 'exclusionReason', 'exclusionNote'},
      'Day decision',
    );
    return SupplierImportDayDecision(
      targetEntityId: _target(data),
      disposition: _retainDisposition(data['disposition']),
      canonicalOrder: data.containsKey('canonicalOrder')
          ? SupplierImportResolutionParsing.positiveInt(
              data['canonicalOrder'],
              'Day order',
            )
          : null,
      overrides: SupplierImportDayOverrides.fromMap(data['overrides']),
      exclusionReason: parseSupplierImportExclusionReason(
        data['exclusionReason'],
        'Day exclusion reason',
      ),
      exclusionNote: SupplierImportResolutionParsing.nullableText(
        data['exclusionNote'],
        'Day exclusion note',
      ),
    ).._validateExclusion();
  }

  final SupplierImportRetainDisposition disposition;
  final int? canonicalOrder;
  final SupplierImportDayOverrides overrides;
  final SupplierImportExclusionReason? exclusionReason;
  final String? exclusionNote;

  @override
  String get decisionKind => 'day';

  void _validateExclusion() => _requireExclusion(
    disposition == SupplierImportRetainDisposition.exclude,
    exclusionReason,
    exclusionNote,
  );

  @override
  Map<String, Object?> toMutationMap() => {
    'decisionKind': decisionKind,
    'targetEntityId': targetEntityId,
    'disposition': disposition.value,
    if (canonicalOrder != null) 'canonicalOrder': canonicalOrder,
    'overrides': overrides.toMap(),
    'exclusionReason': exclusionReason?.value,
    'exclusionNote': exclusionNote,
  };
}

final class SupplierImportServiceOverrides {
  const SupplierImportServiceOverrides({
    this.serviceType,
    this.title,
    this.description,
    this.startTime,
    this.endTime,
    this.location,
    this.city,
    this.inclusions,
    this.exclusions,
    this.notes,
    this.hotel,
    this.transfer,
    this.activity,
  });

  factory SupplierImportServiceOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {
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
        'hotel',
        'transfer',
        'activity',
      },
      required: const {},
      label: 'Service overrides',
    );
    return SupplierImportServiceOverrides(
      serviceType:
          supplierImportOptionalOverride(
                data,
                'serviceType',
                _serviceType,
                setOnly: true,
              )
              as SupplierImportSetOverride<SupplierExtractionServiceType>?,
      title:
          supplierImportOptionalOverride(
                data,
                'title',
                SupplierImportResolutionParsing.text,
                setOnly: true,
              )
              as SupplierImportSetOverride<String>?,
      description: supplierImportOptionalOverride(
        data,
        'description',
        SupplierImportResolutionParsing.text,
      ),
      startTime: supplierImportOptionalOverride(
        data,
        'startTime',
        SupplierImportResolutionParsing.time,
      ),
      endTime: supplierImportOptionalOverride(
        data,
        'endTime',
        SupplierImportResolutionParsing.time,
      ),
      location: supplierImportOptionalOverride(
        data,
        'location',
        SupplierImportResolutionParsing.text,
      ),
      city: supplierImportOptionalOverride(
        data,
        'city',
        SupplierImportResolutionParsing.text,
      ),
      inclusions: supplierImportOptionalOverride(
        data,
        'inclusions',
        SupplierImportResolutionParsing.textList,
      ),
      exclusions: supplierImportOptionalOverride(
        data,
        'exclusions',
        SupplierImportResolutionParsing.textList,
      ),
      notes: supplierImportOptionalOverride(
        data,
        'notes',
        SupplierImportResolutionParsing.text,
      ),
      hotel: data.containsKey('hotel')
          ? SupplierImportHotelOverrides.fromMap(data['hotel'])
          : null,
      transfer: data.containsKey('transfer')
          ? SupplierImportTransferOverrides.fromMap(data['transfer'])
          : null,
      activity: data.containsKey('activity')
          ? SupplierImportActivityOverrides.fromMap(data['activity'])
          : null,
    );
  }

  final SupplierImportSetOverride<SupplierExtractionServiceType>? serviceType;
  final SupplierImportSetOverride<String>? title;
  final SupplierImportFieldOverride<String>? description;
  final SupplierImportFieldOverride<String>? startTime;
  final SupplierImportFieldOverride<String>? endTime;
  final SupplierImportFieldOverride<String>? location;
  final SupplierImportFieldOverride<String>? city;
  final SupplierImportFieldOverride<List<String>>? inclusions;
  final SupplierImportFieldOverride<List<String>>? exclusions;
  final SupplierImportFieldOverride<String>? notes;
  final SupplierImportHotelOverrides? hotel;
  final SupplierImportTransferOverrides? transfer;
  final SupplierImportActivityOverrides? activity;

  Map<String, Object?> toMap() => {
    ...supplierImportOverrideMap({
      'serviceType': serviceType,
      'title': title,
      'description': description,
      'startTime': startTime,
      'endTime': endTime,
      'location': location,
      'city': city,
      'inclusions': inclusions,
      'exclusions': exclusions,
      'notes': notes,
    }),
    if (hotel != null) 'hotel': hotel!.toMap(),
    if (transfer != null) 'transfer': transfer!.toMap(),
    if (activity != null) 'activity': activity!.toMap(),
  };
}

final class SupplierImportServiceDecision
    extends SupplierImportDecisionPayload {
  const SupplierImportServiceDecision({
    required super.targetEntityId,
    required this.disposition,
    required this.overrides,
    required this.exclusionReason,
    required this.exclusionNote,
    this.day,
    this.canonicalOrder,
  });

  factory SupplierImportServiceDecision.fromStoredMap(
    Map<String, Object?> input,
  ) {
    final data = _decisionRecord(
      input,
      const {
        'disposition',
        'day',
        'canonicalOrder',
        'overrides',
        'exclusionReason',
        'exclusionNote',
      },
      const {'disposition', 'overrides', 'exclusionReason', 'exclusionNote'},
      'Service decision',
    );
    final result = SupplierImportServiceDecision(
      targetEntityId: _target(data),
      disposition: _retainDisposition(data['disposition']),
      day: data.containsKey('day')
          ? SupplierImportDayReference.fromMap(data['day'])
          : null,
      canonicalOrder: data.containsKey('canonicalOrder')
          ? SupplierImportResolutionParsing.positiveInt(
              data['canonicalOrder'],
              'Service order',
            )
          : null,
      overrides: SupplierImportServiceOverrides.fromMap(data['overrides']),
      exclusionReason: parseSupplierImportExclusionReason(
        data['exclusionReason'],
        'Service exclusion reason',
      ),
      exclusionNote: SupplierImportResolutionParsing.nullableText(
        data['exclusionNote'],
        'Service exclusion note',
      ),
    );
    _requireExclusion(
      result.disposition == SupplierImportRetainDisposition.exclude,
      result.exclusionReason,
      result.exclusionNote,
    );
    return result;
  }

  final SupplierImportRetainDisposition disposition;
  final SupplierImportDayReference? day;
  final int? canonicalOrder;
  final SupplierImportServiceOverrides overrides;
  final SupplierImportExclusionReason? exclusionReason;
  final String? exclusionNote;

  @override
  String get decisionKind => 'service';

  @override
  Map<String, Object?> toMutationMap() => {
    'decisionKind': decisionKind,
    'targetEntityId': targetEntityId,
    'disposition': disposition.value,
    if (day != null) 'day': day!.toMap(),
    if (canonicalOrder != null) 'canonicalOrder': canonicalOrder,
    'overrides': overrides.toMap(),
    'exclusionReason': exclusionReason?.value,
    'exclusionNote': exclusionNote,
  };
}

final class SupplierImportPackageAccommodationDecision
    extends SupplierImportDecisionPayload {
  const SupplierImportPackageAccommodationDecision({
    required super.targetEntityId,
    required this.disposition,
    required this.day,
    required this.canonicalOrder,
    required this.overrides,
    required this.exclusionReason,
    required this.exclusionNote,
  });

  factory SupplierImportPackageAccommodationDecision.fromStoredMap(
    Map<String, Object?> input,
  ) {
    final data = _decisionRecord(
      input,
      const {
        'disposition',
        'day',
        'canonicalOrder',
        'overrides',
        'exclusionReason',
        'exclusionNote',
      },
      const {
        'disposition',
        'day',
        'canonicalOrder',
        'overrides',
        'exclusionReason',
        'exclusionNote',
      },
      'Package accommodation decision',
    );
    final disposition = _enum(
      data['disposition'],
      SupplierImportAccommodationDisposition.values,
      (item) => item.value,
      'Accommodation disposition',
    );
    final day = data['day'] == null
        ? null
        : SupplierImportDayReference.fromMap(data['day']);
    final order = data['canonicalOrder'] == null
        ? null
        : SupplierImportResolutionParsing.positiveInt(
            data['canonicalOrder'],
            'Accommodation order',
          );
    if ((disposition ==
            SupplierImportAccommodationDisposition.mapToDayService) !=
        (day != null && order != null)) {
      throw const FormatException('Accommodation mapping is invalid.');
    }
    final result = SupplierImportPackageAccommodationDecision(
      targetEntityId: _target(data),
      disposition: disposition,
      day: day,
      canonicalOrder: order,
      overrides: SupplierImportHotelOverrides.fromMap(data['overrides']),
      exclusionReason: parseSupplierImportExclusionReason(
        data['exclusionReason'],
        'Accommodation exclusion reason',
      ),
      exclusionNote: SupplierImportResolutionParsing.nullableText(
        data['exclusionNote'],
        'Accommodation exclusion note',
      ),
    );
    _requireExclusion(
      disposition == SupplierImportAccommodationDisposition.exclude,
      result.exclusionReason,
      result.exclusionNote,
    );
    return result;
  }

  final SupplierImportAccommodationDisposition disposition;
  final SupplierImportDayReference? day;
  final int? canonicalOrder;
  final SupplierImportHotelOverrides overrides;
  final SupplierImportExclusionReason? exclusionReason;
  final String? exclusionNote;

  @override
  String get decisionKind => 'package_accommodation';

  @override
  Map<String, Object?> toMutationMap() => {
    'decisionKind': decisionKind,
    'targetEntityId': targetEntityId,
    'disposition': disposition.value,
    'day': day?.toMap(),
    'canonicalOrder': canonicalOrder,
    'overrides': overrides.toMap(),
    'exclusionReason': exclusionReason?.value,
    'exclusionNote': exclusionNote,
  };
}

final class SupplierImportStatementOverrides {
  const SupplierImportStatementOverrides({
    this.category,
    this.text,
    this.quantity,
    this.frequency,
    this.appliesTo,
  });

  factory SupplierImportStatementOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {'category', 'text', 'quantity', 'frequency', 'appliesTo'},
      required: const {},
      label: 'Package statement overrides',
    );
    return SupplierImportStatementOverrides(
      category:
          supplierImportOptionalOverride(
                data,
                'category',
                _statementCategory,
                setOnly: true,
              )
              as SupplierImportSetOverride<
                SupplierExtractionStatementCategory
              >?,
      text:
          supplierImportOptionalOverride(
                data,
                'text',
                SupplierImportResolutionParsing.text,
                setOnly: true,
              )
              as SupplierImportSetOverride<String>?,
      quantity: supplierImportOptionalOverride(
        data,
        'quantity',
        SupplierImportResolutionParsing.positiveInt,
      ),
      frequency: supplierImportOptionalOverride(
        data,
        'frequency',
        SupplierImportResolutionParsing.text,
      ),
      appliesTo: supplierImportOptionalOverride(
        data,
        'appliesTo',
        _serviceTypes,
      ),
    );
  }

  final SupplierImportSetOverride<SupplierExtractionStatementCategory>?
  category;
  final SupplierImportSetOverride<String>? text;
  final SupplierImportFieldOverride<int>? quantity;
  final SupplierImportFieldOverride<String>? frequency;
  final SupplierImportFieldOverride<List<SupplierExtractionServiceType>>?
  appliesTo;

  Map<String, Object?> toMap() => supplierImportOverrideMap({
    'category': category,
    'text': text,
    'quantity': quantity,
    'frequency': frequency,
    'appliesTo': appliesTo,
  });
}

final class SupplierImportConditionOverrides {
  const SupplierImportConditionOverrides({
    this.kind,
    this.value,
    this.appliesTo,
  });

  factory SupplierImportConditionOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {'kind', 'value', 'appliesTo'},
      required: const {},
      label: 'Package condition overrides',
    );
    return SupplierImportConditionOverrides(
      kind:
          supplierImportOptionalOverride(
                data,
                'kind',
                _conditionKind,
                setOnly: true,
              )
              as SupplierImportSetOverride<SupplierExtractionConditionKind>?,
      value:
          supplierImportOptionalOverride(
                data,
                'value',
                SupplierImportResolutionParsing.text,
                setOnly: true,
              )
              as SupplierImportSetOverride<String>?,
      appliesTo: supplierImportOptionalOverride(
        data,
        'appliesTo',
        _serviceTypes,
      ),
    );
  }

  final SupplierImportSetOverride<SupplierExtractionConditionKind>? kind;
  final SupplierImportSetOverride<String>? value;
  final SupplierImportFieldOverride<List<SupplierExtractionServiceType>>?
  appliesTo;

  Map<String, Object?> toMap() => supplierImportOverrideMap({
    'kind': kind,
    'value': value,
    'appliesTo': appliesTo,
  });
}

abstract base class _SupplierImportPackageDecision
    extends SupplierImportDecisionPayload {
  const _SupplierImportPackageDecision({
    required super.targetEntityId,
    required this.disposition,
    required this.service,
    required this.destination,
    required this.exclusionReason,
    required this.exclusionNote,
  });

  final SupplierImportPackageDisposition disposition;
  final SupplierImportServiceReference? service;
  final SupplierImportPackageDestination? destination;
  final SupplierImportExclusionReason? exclusionReason;
  final String? exclusionNote;

  Map<String, Object?> commonMap(Object overrides) => {
    'decisionKind': decisionKind,
    'targetEntityId': targetEntityId,
    'disposition': disposition.value,
    'service': service?.toMap(),
    'destination': destination?.value,
    'overrides': overrides,
    'exclusionReason': exclusionReason?.value,
    'exclusionNote': exclusionNote,
  };
}

final class SupplierImportPackageStatementDecision
    extends _SupplierImportPackageDecision {
  const SupplierImportPackageStatementDecision({
    required super.targetEntityId,
    required super.disposition,
    required super.service,
    required super.destination,
    required this.overrides,
    required super.exclusionReason,
    required super.exclusionNote,
  });

  factory SupplierImportPackageStatementDecision.fromStoredMap(
    Map<String, Object?> input,
  ) {
    final data = _packageRecord(input, 'Package statement decision');
    final linkage = _packageLinkage(data);
    return SupplierImportPackageStatementDecision(
      targetEntityId: _target(data),
      disposition: linkage.disposition,
      service: linkage.service,
      destination: linkage.destination,
      overrides: SupplierImportStatementOverrides.fromMap(data['overrides']),
      exclusionReason: linkage.reason,
      exclusionNote: linkage.note,
    );
  }

  final SupplierImportStatementOverrides overrides;
  @override
  String get decisionKind => 'package_statement';
  @override
  Map<String, Object?> toMutationMap() => commonMap(overrides.toMap());
}

final class SupplierImportPackageConditionDecision
    extends _SupplierImportPackageDecision {
  const SupplierImportPackageConditionDecision({
    required super.targetEntityId,
    required super.disposition,
    required super.service,
    required super.destination,
    required this.overrides,
    required super.exclusionReason,
    required super.exclusionNote,
  });

  factory SupplierImportPackageConditionDecision.fromStoredMap(
    Map<String, Object?> input,
  ) {
    final data = _packageRecord(input, 'Package condition decision');
    final linkage = _packageLinkage(data);
    return SupplierImportPackageConditionDecision(
      targetEntityId: _target(data),
      disposition: linkage.disposition,
      service: linkage.service,
      destination: linkage.destination,
      overrides: SupplierImportConditionOverrides.fromMap(data['overrides']),
      exclusionReason: linkage.reason,
      exclusionNote: linkage.note,
    );
  }

  final SupplierImportConditionOverrides overrides;
  @override
  String get decisionKind => 'package_condition';
  @override
  Map<String, Object?> toMutationMap() => commonMap(overrides.toMap());
}

final class SupplierImportFlightOverrides {
  const SupplierImportFlightOverrides({
    this.airline,
    this.flightNumber,
    this.origin,
    this.destination,
    this.departureDate,
    this.departureTime,
    this.arrivalDate,
    this.arrivalTime,
    this.cabinClass,
    this.bookingClass,
    this.notes,
    this.conditions,
  });

  factory SupplierImportFlightOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {
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
      },
      required: const {},
      label: 'Flight overrides',
    );
    SupplierImportFieldOverride<String>? text(String key) =>
        supplierImportOptionalOverride(
          data,
          key,
          SupplierImportResolutionParsing.text,
        );
    return SupplierImportFlightOverrides(
      airline: text('airline'),
      flightNumber: text('flightNumber'),
      origin: text('origin'),
      destination: text('destination'),
      departureDate: supplierImportOptionalOverride(
        data,
        'departureDate',
        SupplierImportResolutionParsing.date,
      ),
      departureTime: supplierImportOptionalOverride(
        data,
        'departureTime',
        SupplierImportResolutionParsing.time,
      ),
      arrivalDate: supplierImportOptionalOverride(
        data,
        'arrivalDate',
        SupplierImportResolutionParsing.date,
      ),
      arrivalTime: supplierImportOptionalOverride(
        data,
        'arrivalTime',
        SupplierImportResolutionParsing.time,
      ),
      cabinClass: text('cabinClass'),
      bookingClass: text('bookingClass'),
      notes: text('notes'),
      conditions: supplierImportOptionalOverride(
        data,
        'conditions',
        _conditions,
      ),
    );
  }

  final SupplierImportFieldOverride<String>? airline;
  final SupplierImportFieldOverride<String>? flightNumber;
  final SupplierImportFieldOverride<String>? origin;
  final SupplierImportFieldOverride<String>? destination;
  final SupplierImportFieldOverride<String>? departureDate;
  final SupplierImportFieldOverride<String>? departureTime;
  final SupplierImportFieldOverride<String>? arrivalDate;
  final SupplierImportFieldOverride<String>? arrivalTime;
  final SupplierImportFieldOverride<String>? cabinClass;
  final SupplierImportFieldOverride<String>? bookingClass;
  final SupplierImportFieldOverride<String>? notes;
  final SupplierImportFieldOverride<List<SupplierImportResolutionCondition>>?
  conditions;

  Map<String, Object?> toMap() => supplierImportOverrideMap({
    'airline': airline,
    'flightNumber': flightNumber,
    'origin': origin,
    'destination': destination,
    'departureDate': departureDate,
    'departureTime': departureTime,
    'arrivalDate': arrivalDate,
    'arrivalTime': arrivalTime,
    'cabinClass': cabinClass,
    'bookingClass': bookingClass,
    'notes': notes,
    'conditions': conditions,
  });
}

final class SupplierImportVisaOverrides {
  const SupplierImportVisaOverrides({this.disposition, this.text});

  factory SupplierImportVisaOverrides.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.closed(
      input,
      allowed: const {'disposition', 'text'},
      required: const {},
      label: 'Visa overrides',
    );
    return SupplierImportVisaOverrides(
      disposition:
          supplierImportOptionalOverride(
                data,
                'disposition',
                _visaDisposition,
                setOnly: true,
              )
              as SupplierImportSetOverride<SupplierExtractionVisaDisposition>?,
      text: supplierImportOptionalOverride(
        data,
        'text',
        SupplierImportResolutionParsing.text,
      ),
    );
  }

  final SupplierImportSetOverride<SupplierExtractionVisaDisposition>?
  disposition;
  final SupplierImportFieldOverride<String>? text;

  Map<String, Object?> toMap() =>
      supplierImportOverrideMap({'disposition': disposition, 'text': text});
}

abstract base class _SupplierImportAncillaryDecision<T extends Enum, O>
    extends SupplierImportDecisionPayload {
  const _SupplierImportAncillaryDecision({
    required super.targetEntityId,
    required this.disposition,
    required this.destinationId,
    required this.overrides,
    required this.exclusionReason,
    required this.exclusionNote,
  });

  final T disposition;
  final String? destinationId;
  final O overrides;
  final SupplierImportExclusionReason? exclusionReason;
  final String? exclusionNote;
}

final class SupplierImportFlightDecision
    extends
        _SupplierImportAncillaryDecision<
          SupplierImportFlightDisposition,
          SupplierImportFlightOverrides
        > {
  const SupplierImportFlightDecision({
    required super.targetEntityId,
    required super.disposition,
    required super.destinationId,
    required super.overrides,
    required super.exclusionReason,
    required super.exclusionNote,
  });

  factory SupplierImportFlightDecision.fromStoredMap(
    Map<String, Object?> input,
  ) {
    final data = _ancillaryRecord(input, 'Flight decision');
    final disposition = _enum(
      data['disposition'],
      SupplierImportFlightDisposition.values,
      (item) => item.value,
      'Flight disposition',
    );
    final destination = SupplierImportResolutionParsing.nullableId(
      data['destinationId'],
      'Flight destination',
    );
    _route(
      destination,
      disposition == SupplierImportFlightDisposition.routeToFlightWorkflow,
    );
    final reason = parseSupplierImportExclusionReason(
      data['exclusionReason'],
      'Flight exclusion reason',
    );
    final note = SupplierImportResolutionParsing.nullableText(
      data['exclusionNote'],
      'Flight exclusion note',
    );
    _requireExclusion(
      disposition == SupplierImportFlightDisposition.exclude,
      reason,
      note,
    );
    return SupplierImportFlightDecision(
      targetEntityId: _target(data),
      disposition: disposition,
      destinationId: destination,
      overrides: SupplierImportFlightOverrides.fromMap(data['overrides']),
      exclusionReason: reason,
      exclusionNote: note,
    );
  }

  @override
  String get decisionKind => 'flight';
  @override
  Map<String, Object?> toMutationMap() => {
    'decisionKind': decisionKind,
    'targetEntityId': targetEntityId,
    'disposition': disposition.value,
    'destinationId': destinationId,
    'overrides': overrides.toMap(),
    'exclusionReason': exclusionReason?.value,
    'exclusionNote': exclusionNote,
  };
}

final class SupplierImportVisaDecision
    extends
        _SupplierImportAncillaryDecision<
          SupplierImportVisaDecisionDisposition,
          SupplierImportVisaOverrides
        > {
  const SupplierImportVisaDecision({
    required super.targetEntityId,
    required super.disposition,
    required super.destinationId,
    required super.overrides,
    required super.exclusionReason,
    required super.exclusionNote,
  });

  factory SupplierImportVisaDecision.fromStoredMap(Map<String, Object?> input) {
    final data = _ancillaryRecord(input, 'Visa decision');
    final disposition = _enum(
      data['disposition'],
      SupplierImportVisaDecisionDisposition.values,
      (item) => item.value,
      'Visa disposition',
    );
    final destination = SupplierImportResolutionParsing.nullableId(
      data['destinationId'],
      'Visa destination',
    );
    _route(
      destination,
      disposition == SupplierImportVisaDecisionDisposition.routeToVisaWorkflow,
    );
    final reason = parseSupplierImportExclusionReason(
      data['exclusionReason'],
      'Visa exclusion reason',
    );
    final note = SupplierImportResolutionParsing.nullableText(
      data['exclusionNote'],
      'Visa exclusion note',
    );
    _requireExclusion(
      disposition == SupplierImportVisaDecisionDisposition.exclude,
      reason,
      note,
    );
    return SupplierImportVisaDecision(
      targetEntityId: _target(data),
      disposition: disposition,
      destinationId: destination,
      overrides: SupplierImportVisaOverrides.fromMap(data['overrides']),
      exclusionReason: reason,
      exclusionNote: note,
    );
  }

  @override
  String get decisionKind => 'visa';
  @override
  Map<String, Object?> toMutationMap() => {
    'decisionKind': decisionKind,
    'targetEntityId': targetEntityId,
    'disposition': disposition.value,
    'destinationId': destinationId,
    'overrides': overrides.toMap(),
    'exclusionReason': exclusionReason?.value,
    'exclusionNote': exclusionNote,
  };
}

sealed class SupplierImportResolutionReference {
  const SupplierImportResolutionReference();
  factory SupplierImportResolutionReference.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.record(
      input,
      'Resolution reference',
    );
    if (data['kind'] == 'decision') {
      final exact = SupplierImportResolutionParsing.exact(data, const {
        'kind',
        'decisionId',
      }, 'Decision reference');
      return SupplierImportDecisionReference(
        SupplierImportResolutionParsing.id(
          exact['decisionId'],
          'Decision reference',
        ),
      );
    }
    if (data['kind'] == 'manual_item') {
      final exact = SupplierImportResolutionParsing.exact(data, const {
        'kind',
        'manualItemId',
      }, 'Manual item reference');
      return SupplierImportManualItemReference(
        SupplierImportResolutionParsing.id(
          exact['manualItemId'],
          'Manual item reference',
        ),
      );
    }
    throw const FormatException('Resolution reference is invalid.');
  }
  String get identity;
  Map<String, Object?> toMap();
}

final class SupplierImportDecisionReference
    extends SupplierImportResolutionReference {
  const SupplierImportDecisionReference(this.decisionId);
  final String decisionId;
  @override
  String get identity => 'decision:$decisionId';
  @override
  Map<String, Object?> toMap() => {
    'kind': 'decision',
    'decisionId': decisionId,
  };
}

final class SupplierImportManualItemReference
    extends SupplierImportResolutionReference {
  const SupplierImportManualItemReference(this.manualItemId);
  final String manualItemId;
  @override
  String get identity => 'manual_item:$manualItemId';
  @override
  Map<String, Object?> toMap() => {
    'kind': 'manual_item',
    'manualItemId': manualItemId,
  };
}

final class SupplierImportReviewIssueDecision
    extends SupplierImportDecisionPayload {
  SupplierImportReviewIssueDecision({
    required super.targetEntityId,
    required this.outcome,
    required List<SupplierImportResolutionReference> resolutionReferences,
    required this.overrideReason,
    required this.overrideNote,
  }) : resolutionReferences = List.unmodifiable(resolutionReferences) {
    SupplierImportResolutionParsing.unique(
      this.resolutionReferences.map((item) => item.identity),
      'resolution references',
    );
    if (outcome == SupplierImportReviewOutcome.resolved &&
        this.resolutionReferences.isEmpty) {
      throw const FormatException(
        'Resolved review issue requires a reference.',
      );
    }
    if (outcome != SupplierImportReviewOutcome.resolved &&
        this.resolutionReferences.isNotEmpty) {
      throw const FormatException(
        'Only resolved review issue may reference state.',
      );
    }
    if ((outcome == SupplierImportReviewOutcome.overridden) !=
        (overrideReason != null && overrideNote != null)) {
      throw const FormatException('Review override rationale is invalid.');
    }
  }

  factory SupplierImportReviewIssueDecision.fromStoredMap(
    Map<String, Object?> input,
  ) {
    final data = _decisionRecord(
      input,
      const {
        'outcome',
        'resolutionReferences',
        'overrideReason',
        'overrideNote',
      },
      const {
        'outcome',
        'resolutionReferences',
        'overrideReason',
        'overrideNote',
      },
      'Review issue decision',
    );
    return SupplierImportReviewIssueDecision(
      targetEntityId: _target(data),
      outcome: _enum(
        data['outcome'],
        SupplierImportReviewOutcome.values,
        (item) => item.value,
        'Review outcome',
      ),
      resolutionReferences: SupplierImportResolutionParsing.list(
        data['resolutionReferences'],
        'Resolution references',
      ).map(SupplierImportResolutionReference.fromMap).toList(),
      overrideReason: parseSupplierImportExclusionReason(
        data['overrideReason'],
        'Review override reason',
      ),
      overrideNote: SupplierImportResolutionParsing.nullableText(
        data['overrideNote'],
        'Review override note',
      ),
    );
  }

  final SupplierImportReviewOutcome outcome;
  final List<SupplierImportResolutionReference> resolutionReferences;
  final SupplierImportExclusionReason? overrideReason;
  final String? overrideNote;
  @override
  String get decisionKind => 'review_issue';
  @override
  Map<String, Object?> toMutationMap() => {
    'decisionKind': decisionKind,
    'targetEntityId': targetEntityId,
    'outcome': outcome.value,
    'resolutionReferences': resolutionReferences
        .map((item) => item.toMap())
        .toList(growable: false),
    'overrideReason': overrideReason?.value,
    'overrideNote': overrideNote,
  };
}

Map<String, Object?> _decisionRecord(
  Map<String, Object?> input,
  Set<String> allowed,
  Set<String> required,
  String label,
) => SupplierImportResolutionParsing.closed(
  input,
  allowed: _storedFields({'decisionKind', 'targetEntityId', ...allowed}),
  required: _storedFields({'decisionKind', 'targetEntityId', ...required}),
  label: label,
);

Map<String, Object?> _packageRecord(Map<String, Object?> input, String label) =>
    _decisionRecord(
      input,
      const {
        'disposition',
        'service',
        'destination',
        'overrides',
        'exclusionReason',
        'exclusionNote',
      },
      const {
        'disposition',
        'service',
        'destination',
        'overrides',
        'exclusionReason',
        'exclusionNote',
      },
      label,
    );

({
  SupplierImportPackageDisposition disposition,
  SupplierImportServiceReference? service,
  SupplierImportPackageDestination? destination,
  SupplierImportExclusionReason? reason,
  String? note,
})
_packageLinkage(Map<String, Object?> data) {
  final disposition = _enum(
    data['disposition'],
    SupplierImportPackageDisposition.values,
    (item) => item.value,
    'Package disposition',
  );
  final service = data['service'] == null
      ? null
      : SupplierImportServiceReference.fromMap(data['service']);
  final destination = data['destination'] == null
      ? null
      : _enum(
          data['destination'],
          SupplierImportPackageDestination.values,
          (item) => item.value,
          'Package destination',
        );
  if ((disposition == SupplierImportPackageDisposition.mapToService) !=
      (service != null && destination != null)) {
    throw const FormatException('Package service linkage is invalid.');
  }
  final reason = parseSupplierImportExclusionReason(
    data['exclusionReason'],
    'Package exclusion reason',
  );
  final note = SupplierImportResolutionParsing.nullableText(
    data['exclusionNote'],
    'Package exclusion note',
  );
  _requireExclusion(
    disposition == SupplierImportPackageDisposition.exclude,
    reason,
    note,
  );
  return (
    disposition: disposition,
    service: service,
    destination: destination,
    reason: reason,
    note: note,
  );
}

Map<String, Object?> _ancillaryRecord(
  Map<String, Object?> input,
  String label,
) => _decisionRecord(
  input,
  const {
    'disposition',
    'destinationId',
    'overrides',
    'exclusionReason',
    'exclusionNote',
  },
  const {
    'disposition',
    'destinationId',
    'overrides',
    'exclusionReason',
    'exclusionNote',
  },
  label,
);

String _target(Map<String, Object?> data) => SupplierImportResolutionParsing.id(
  data['targetEntityId'],
  'Decision target',
);

SupplierImportRetainDisposition _retainDisposition(Object? value) => _enum(
  value,
  SupplierImportRetainDisposition.values,
  (item) => item.value,
  'Retain disposition',
);

T _enum<T extends Enum>(
  Object? value,
  Iterable<T> values,
  String Function(T) persisted,
  String label,
) => SupplierImportResolutionParsing.enumValue(value, values, persisted, label);

SupplierExtractionServiceType _serviceType(Object? value, String label) =>
    _enum(
      value,
      SupplierExtractionServiceType.values,
      (item) => item.value,
      label,
    );

SupplierExtractionStatementCategory _statementCategory(
  Object? value,
  String label,
) => _enum(
  value,
  SupplierExtractionStatementCategory.values,
  (item) => item.value,
  label,
);

SupplierExtractionConditionKind _conditionKind(Object? value, String label) =>
    _enum(
      value,
      SupplierExtractionConditionKind.values,
      (item) => item.value,
      label,
    );

SupplierExtractionVisaDisposition _visaDisposition(
  Object? value,
  String label,
) => _enum(
  value,
  SupplierExtractionVisaDisposition.values,
  (item) => item.value,
  label,
);

List<SupplierExtractionServiceType> _serviceTypes(Object? value, String label) {
  final result = SupplierImportResolutionParsing.list(
    value,
    label,
  ).map((item) => _serviceType(item, label)).toList();
  SupplierImportResolutionParsing.unique(result, label);
  return List.unmodifiable(result);
}

List<SupplierImportResolutionCondition> _conditions(
  Object? value,
  String label,
) => List.unmodifiable(
  SupplierImportResolutionParsing.list(
    value,
    label,
  ).map(SupplierImportResolutionCondition.fromMap),
);

void _requireExclusion(
  bool excluded,
  SupplierImportExclusionReason? reason,
  String? note,
) {
  if (excluded != (reason != null)) {
    throw const FormatException('Exclusion reason is inconsistent.');
  }
  if (!excluded && note != null) {
    throw const FormatException('Exclusion note is inconsistent.');
  }
}

void _route(String? destination, bool routed) {
  if (routed != (destination != null)) {
    throw const FormatException('Workflow destination is inconsistent.');
  }
}
