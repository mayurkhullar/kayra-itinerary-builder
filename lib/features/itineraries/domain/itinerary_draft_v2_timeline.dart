part of 'itinerary_draft_v2.dart';

List<ItineraryDraftV2Day> _parseV2Timeline(
  Object? input,
  List<String> packages,
) {
  var previous = 0;
  return _V2.list(input, (value) {
    final m = _V2.record(value, {
      'dayNumber',
      'date',
      'title',
      'summary',
      'services',
      'notes',
    });
    final number = _V2.positive(m['dayNumber']);
    if (number <= previous) _V2.invalid();
    previous = number;
    return ItineraryDraftV2Day._(
      dayNumber: number,
      date: _V2.timelineDate(m['date']),
      title: _V2.text(m['title']),
      summary: _V2.optionalText(m['summary']),
      notes: _V2.optionalText(m['notes']),
      services: _V2.list(m['services'], (s) => _parseV2Service(s, packages)),
    );
  });
}

ItineraryDraftV2Service _parseV2Service(Object? value, List<String> packages) {
  final m = _V2.optionalRecord(
    value,
    {
      'id',
      'type',
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
      'sourceReference',
    },
    {'conditions'},
  );
  List<String> texts(Object? value) => _V2
      .list(value, (v) {
        if (v is String && v.trim().isEmpty) return '';
        return _V2.text(v);
      })
      .where((v) => v.isNotEmpty)
      .toList(growable: false);
  final type = KayraItineraryServiceType.parse(m['type']);
  if ((m['hotelDetails'] != null && type != KayraItineraryServiceType.hotel) ||
      (m['transferDetails'] != null &&
          type != KayraItineraryServiceType.transfer) ||
      (m['activityDetails'] != null &&
          type != KayraItineraryServiceType.activity)) {
    _V2.invalid();
  }
  return ItineraryDraftV2Service._(
    id: _V2.id(m['id']),
    type: KayraItineraryServiceType.parse(m['type']),
    title: _V2.text(m['title']),
    description: _V2.optionalText(m['description']),
    startTime: _V2.optionalText(m['startTime']),
    endTime: _V2.optionalText(m['endTime']),
    location: _V2.optionalText(m['location']),
    city: _V2.optionalText(m['city']),
    notes: _V2.optionalText(m['notes']),
    conditions: m.containsKey('conditions')
        ? _V2.list(m['conditions'], (v) {
            final c = _V2.record(v, {'kind', 'value'});
            final kind = _V2.enumeration(
              c['kind'],
              SupplierExtractionConditionKind.values,
              (k) => k.value,
            );
            return ItineraryDraftV2ServiceCondition._(
              kind,
              _V2.text(
                c['value'],
                directPayment:
                    kind == SupplierExtractionConditionKind.paymentBasis,
              ),
            );
          })
        : null,
    inclusions: List.unmodifiable(texts(m['inclusions'])),
    exclusions: List.unmodifiable(texts(m['exclusions'])),
    hotelDetails: m['hotelDetails'] == null
        ? null
        : _parseV2Hotel(m['hotelDetails']),
    transferDetails: m['transferDetails'] == null
        ? null
        : _parseV2Transfer(m['transferDetails']),
    activityDetails: m['activityDetails'] == null
        ? null
        : _parseV2Activity(m['activityDetails']),
    sourceReference: m['sourceReference'] == null
        ? null
        : _parseV2Source(m['sourceReference'], packages),
  );
}

ItineraryDraftV2TimelineHotelDetails _parseV2Hotel(Object? value) {
  final m = _V2.optionalRecord(
    value,
    {
      'hotelName',
      'checkInDate',
      'checkOutDate',
      'roomType',
      'mealPlan',
      'numberOfRooms',
      'supplierStarRating',
    },
    {'city', 'orSimilar', 'nightCount'},
  );
  final start = _V2.timelineDate(m['checkInDate']);
  final end = _V2.timelineDate(m['checkOutDate']);
  if (start != null && end != null && !end.isAfter(start)) _V2.invalid();
  return ItineraryDraftV2TimelineHotelDetails._(
    hotelName: _V2.text(m['hotelName']),
    city: _V2.nullableText(m['city']),
    orSimilar: _V2.nullableBoolean(m['orSimilar']),
    nightCount: _V2.nullablePositive(m['nightCount']),
    present: Set.unmodifiable(
      m.keys.where({'city', 'orSimilar', 'nightCount'}.contains),
    ),
    checkInDate: _V2.timelineDate(m['checkInDate']),
    checkOutDate: _V2.timelineDate(m['checkOutDate']),
    roomType: _V2.optionalText(m['roomType']),
    mealPlan: _V2.optionalText(m['mealPlan']),
    numberOfRooms: _V2.nullablePositive(m['numberOfRooms']),
    supplierStarRating: _V2.optionalText(m['supplierStarRating']),
  );
}

KayraItineraryTransferDetails _parseV2Transfer(Object? value) {
  final m = _V2.record(value, {
    'pickup',
    'dropoff',
    'vehicleType',
    'transferType',
  });
  return KayraItineraryTransferDetails(
    pickup: _V2.text(m['pickup']),
    dropoff: _V2.text(m['dropoff']),
    vehicleType: _V2.optionalText(m['vehicleType']),
    transferType: m['transferType'] == null
        ? null
        : KayraItineraryTransferType.parse(m['transferType']),
  );
}

KayraItineraryActivityDetails _parseV2Activity(Object? value) {
  final m = _V2.record(value, {'activityName', 'duration', 'activityType'});
  return KayraItineraryActivityDetails(
    activityName: _V2.text(m['activityName']),
    duration: _V2.optionalText(m['duration']),
    activityType: _V2.optionalText(m['activityType']),
  );
}

KayraItinerarySourceReference _parseV2Source(
  Object? value,
  List<String> packages,
) {
  final m = _V2.record(value, {
    'supplierSourcePackageId',
    'supplierSourceFileId',
    'sourceLabel',
  });
  final package = _V2.id(m['supplierSourcePackageId']);
  if (!packages.contains(package)) _V2.invalid();
  return KayraItinerarySourceReference(
    supplierSourcePackageId: package,
    supplierSourceFileId: m['supplierSourceFileId'] == null
        ? null
        : _V2.id(m['supplierSourceFileId']),
    sourceLabel: _V2.label(_V2.optionalText(m['sourceLabel'])),
  );
}
