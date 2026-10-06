part of 'itinerary_draft_v2.dart';

List<KayraItineraryDay> _parseV2Timeline(Object? input, List<String> packages) {
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
    return KayraItineraryDay(
      dayNumber: number,
      date: _V2.timelineDate(m['date']),
      title: _V2.text(m['title']),
      summary: _V2.optionalText(m['summary']),
      notes: _V2.optionalText(m['notes']),
      services: _V2.list(m['services'], (s) => _parseV2Service(s, packages)),
    );
  });
}

KayraItineraryService _parseV2Service(Object? value, List<String> packages) {
  final m = _V2.record(value, {
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
  });
  List<String> texts(Object? value) => _V2
      .list(value, (v) {
        if (v is String && v.trim().isEmpty) return '';
        return _V2.text(v);
      })
      .where((v) => v.isNotEmpty)
      .toList();
  return KayraItineraryService(
    id: _V2.id(m['id']),
    type: KayraItineraryServiceType.parse(m['type']),
    title: _V2.text(m['title']),
    description: _V2.optionalText(m['description']),
    startTime: _V2.optionalText(m['startTime']),
    endTime: _V2.optionalText(m['endTime']),
    location: _V2.optionalText(m['location']),
    city: _V2.optionalText(m['city']),
    notes: _V2.optionalText(m['notes']),
    inclusions: texts(m['inclusions']),
    exclusions: texts(m['exclusions']),
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

KayraItineraryHotelDetails _parseV2Hotel(Object? value) {
  final m = _V2.record(value, {
    'hotelName',
    'checkInDate',
    'checkOutDate',
    'roomType',
    'mealPlan',
    'numberOfRooms',
    'supplierStarRating',
  });
  return KayraItineraryHotelDetails(
    hotelName: _V2.text(m['hotelName']),
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
