import 'itinerary_model_validation.dart';
import 'kayra_itinerary_details.dart';

enum KayraItineraryServiceType {
  hotel('hotel'),
  transfer('transfer'),
  activity('activity'),
  meal('meal'),
  sightseeing('sightseeing'),
  freeTime('free_time'),
  other('other');

  const KayraItineraryServiceType(this.value);
  final String value;

  static KayraItineraryServiceType parse(Object? value) => values.firstWhere(
    (type) => type.value == value,
    orElse: () =>
        throw const FormatException('Invalid itinerary service type.'),
  );
}

final class KayraItinerarySourceReference {
  KayraItinerarySourceReference({
    required String supplierSourcePackageId,
    String? supplierSourceFileId,
    String? sourceLabel,
  }) : supplierSourcePackageId = ItineraryModelValidation.id(
         supplierSourcePackageId,
         'supplier source package',
       ),
       supplierSourceFileId = supplierSourceFileId == null
           ? null
           : ItineraryModelValidation.id(
               supplierSourceFileId,
               'supplier source file',
             ),
       sourceLabel = ItineraryModelValidation.optionalText(sourceLabel);

  factory KayraItinerarySourceReference.fromMap(Map<String, Object?> data) {
    ItineraryModelValidation.fields(data, {
      'supplierSourcePackageId',
      'supplierSourceFileId',
      'sourceLabel',
    });
    return KayraItinerarySourceReference(
      supplierSourcePackageId: ItineraryModelValidation.string(
        data['supplierSourcePackageId'],
      ),
      supplierSourceFileId: ItineraryModelValidation.nullableString(
        data['supplierSourceFileId'],
      ),
      sourceLabel: ItineraryModelValidation.nullableString(data['sourceLabel']),
    );
  }

  final String supplierSourcePackageId;
  final String? supplierSourceFileId;
  final String? sourceLabel;

  Map<String, Object?> toMap() => {
    'supplierSourcePackageId': supplierSourcePackageId,
    'supplierSourceFileId': supplierSourceFileId,
    'sourceLabel': sourceLabel,
  };
}

final class KayraItineraryService {
  KayraItineraryService({
    required String id,
    required this.type,
    required String title,
    String? description,
    String? startTime,
    String? endTime,
    String? location,
    String? city,
    List<String> inclusions = const [],
    List<String> exclusions = const [],
    String? notes,
    this.hotelDetails,
    this.transferDetails,
    this.activityDetails,
    this.sourceReference,
  }) : id = ItineraryModelValidation.id(id, 'itinerary service'),
       title = ItineraryModelValidation.requiredText(title, 'Service title'),
       description = ItineraryModelValidation.optionalText(description),
       startTime = ItineraryModelValidation.optionalText(startTime),
       endTime = ItineraryModelValidation.optionalText(endTime),
       location = ItineraryModelValidation.optionalText(location),
       city = ItineraryModelValidation.optionalText(city),
       inclusions = ItineraryModelValidation.textList(inclusions),
       exclusions = ItineraryModelValidation.textList(exclusions),
       notes = ItineraryModelValidation.optionalText(notes) {
    if (hotelDetails != null && type != KayraItineraryServiceType.hotel) {
      throw const FormatException('Hotel details require a hotel service.');
    }
    if (transferDetails != null && type != KayraItineraryServiceType.transfer) {
      throw const FormatException(
        'Transfer details require a transfer service.',
      );
    }
    if (activityDetails != null && type != KayraItineraryServiceType.activity) {
      throw const FormatException(
        'Activity details require an activity service.',
      );
    }
  }

  factory KayraItineraryService.fromMap(Map<String, Object?> data) {
    ItineraryModelValidation.fields(data, {
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
    return KayraItineraryService(
      id: ItineraryModelValidation.string(data['id']),
      type: KayraItineraryServiceType.parse(data['type']),
      title: ItineraryModelValidation.string(data['title']),
      description: ItineraryModelValidation.nullableString(data['description']),
      startTime: ItineraryModelValidation.nullableString(data['startTime']),
      endTime: ItineraryModelValidation.nullableString(data['endTime']),
      location: ItineraryModelValidation.nullableString(data['location']),
      city: ItineraryModelValidation.nullableString(data['city']),
      inclusions: ItineraryModelValidation.strings(data['inclusions']),
      exclusions: ItineraryModelValidation.strings(data['exclusions']),
      notes: ItineraryModelValidation.nullableString(data['notes']),
      hotelDetails: _optionalMap(
        data['hotelDetails'],
        KayraItineraryHotelDetails.fromMap,
      ),
      transferDetails: _optionalMap(
        data['transferDetails'],
        KayraItineraryTransferDetails.fromMap,
      ),
      activityDetails: _optionalMap(
        data['activityDetails'],
        KayraItineraryActivityDetails.fromMap,
      ),
      sourceReference: _optionalMap(
        data['sourceReference'],
        KayraItinerarySourceReference.fromMap,
      ),
    );
  }

  final String id;
  final KayraItineraryServiceType type;
  final String title;
  final String? description;
  final String? startTime;
  final String? endTime;
  final String? location;
  final String? city;
  final List<String> inclusions;
  final List<String> exclusions;
  final String? notes;
  final KayraItineraryHotelDetails? hotelDetails;
  final KayraItineraryTransferDetails? transferDetails;
  final KayraItineraryActivityDetails? activityDetails;
  final KayraItinerarySourceReference? sourceReference;

  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.value,
    'title': title,
    'description': description,
    'startTime': startTime,
    'endTime': endTime,
    'location': location,
    'city': city,
    'inclusions': inclusions.toList(),
    'exclusions': exclusions.toList(),
    'notes': notes,
    'hotelDetails': hotelDetails?.toMap(),
    'transferDetails': transferDetails?.toMap(),
    'activityDetails': activityDetails?.toMap(),
    'sourceReference': sourceReference?.toMap(),
  };
}

T? _optionalMap<T>(
  Object? value,
  T Function(Map<String, Object?> data) parse,
) => value == null ? null : parse(ItineraryModelValidation.map(value));
