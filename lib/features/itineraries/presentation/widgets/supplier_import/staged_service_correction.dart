import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_values.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import 'review_components.dart';

enum ServiceCorrectionInput {
  text,
  multiline,
  date,
  time,
  count,
  boolean,
  serviceType,
  transferType,
  list,
}

/// Closed presentation catalog of the existing staged-service override contract.
enum StagedServiceCorrectionField {
  serviceType(
    'serviceType',
    'Service type',
    ServiceCorrectionInput.serviceType,
  ),
  title('title', 'Title'),
  description('description', 'Description', ServiceCorrectionInput.multiline),
  startTime('startTime', 'Start time', ServiceCorrectionInput.time),
  endTime('endTime', 'End time', ServiceCorrectionInput.time),
  location('location', 'Location'),
  city('city', 'City'),
  inclusions('inclusions', 'Inclusions', ServiceCorrectionInput.list),
  exclusions('exclusions', 'Exclusions', ServiceCorrectionInput.list),
  notes('notes', 'Notes', ServiceCorrectionInput.multiline),
  hotelName('hotelName', 'Hotel name', ServiceCorrectionInput.text, 'hotel'),
  hotelCity('city', 'Hotel city', ServiceCorrectionInput.text, 'hotel'),
  orSimilar('orSimilar', 'Or similar', ServiceCorrectionInput.boolean, 'hotel'),
  checkInDate(
    'checkInDate',
    'Check-in date',
    ServiceCorrectionInput.date,
    'hotel',
  ),
  checkOutDate(
    'checkOutDate',
    'Check-out date',
    ServiceCorrectionInput.date,
    'hotel',
  ),
  nightCount(
    'nightCount',
    'Night count',
    ServiceCorrectionInput.count,
    'hotel',
  ),
  roomType('roomType', 'Room type', ServiceCorrectionInput.text, 'hotel'),
  mealPlan('mealPlan', 'Meal plan', ServiceCorrectionInput.text, 'hotel'),
  numberOfRooms(
    'numberOfRooms',
    'Number of rooms',
    ServiceCorrectionInput.count,
    'hotel',
  ),
  supplierStarRating(
    'supplierStarRating',
    'Supplier star rating',
    ServiceCorrectionInput.text,
    'hotel',
  ),
  pickup('pickup', 'Pickup', ServiceCorrectionInput.text, 'transfer'),
  dropoff('dropoff', 'Dropoff', ServiceCorrectionInput.text, 'transfer'),
  vehicleType(
    'vehicleType',
    'Vehicle type',
    ServiceCorrectionInput.text,
    'transfer',
  ),
  transferType(
    'transferType',
    'Transfer type',
    ServiceCorrectionInput.transferType,
    'transfer',
  ),
  activityName(
    'activityName',
    'Activity name',
    ServiceCorrectionInput.text,
    'activity',
  ),
  duration('duration', 'Duration', ServiceCorrectionInput.text, 'activity'),
  activityType(
    'activityType',
    'Activity type',
    ServiceCorrectionInput.text,
    'activity',
  );

  const StagedServiceCorrectionField(
    this.wireKey,
    this.label, [
    this.input = ServiceCorrectionInput.text,
    this.branch,
  ]);
  final String wireKey;
  final String label;
  final ServiceCorrectionInput input;
  final String? branch;
  bool get canClear => this != title && this != serviceType;

  bool supportsSource(SupplierExtractionServiceFact source) =>
      branch == null || branch == source.serviceType?.value;

  SupplierImportFieldOverride<Object?>? overrideIn(
    SupplierImportServiceOverrides? o,
  ) => switch (this) {
    serviceType => o?.serviceType,
    title => o?.title,
    description => o?.description,
    startTime => o?.startTime,
    endTime => o?.endTime,
    location => o?.location,
    city => o?.city,
    inclusions => o?.inclusions,
    exclusions => o?.exclusions,
    notes => o?.notes,
    hotelName => o?.hotel?.hotelName,
    hotelCity => o?.hotel?.city,
    orSimilar => o?.hotel?.orSimilar,
    checkInDate => o?.hotel?.checkInDate,
    checkOutDate => o?.hotel?.checkOutDate,
    nightCount => o?.hotel?.nightCount,
    roomType => o?.hotel?.roomType,
    mealPlan => o?.hotel?.mealPlan,
    numberOfRooms => o?.hotel?.numberOfRooms,
    supplierStarRating => o?.hotel?.supplierStarRating,
    pickup => o?.transfer?.pickup,
    dropoff => o?.transfer?.dropoff,
    vehicleType => o?.transfer?.vehicleType,
    transferType => o?.transfer?.transferType,
    activityName => o?.activity?.activityName,
    duration => o?.activity?.duration,
    activityType => o?.activity?.activityType,
  };

  Object? sourceValue(SupplierExtractionServiceFact s) => switch (this) {
    serviceType => s.serviceType,
    title => s.title,
    description => s.description,
    startTime => s.startTime,
    endTime => s.endTime,
    location => s.location,
    city => s.city,
    inclusions => s.inclusions,
    exclusions => s.exclusions,
    notes => s.notes,
    hotelName => s.hotelDetails?.hotelName,
    hotelCity => s.hotelDetails?.city,
    orSimilar => s.hotelDetails?.orSimilar,
    checkInDate => s.hotelDetails?.checkInDate,
    checkOutDate => s.hotelDetails?.checkOutDate,
    nightCount => s.hotelDetails?.nightCount,
    roomType => s.hotelDetails?.roomType,
    mealPlan => s.hotelDetails?.mealPlan,
    numberOfRooms => s.hotelDetails?.numberOfRooms,
    supplierStarRating => s.hotelDetails?.supplierStarRating,
    pickup => s.transferDetails?.pickup,
    dropoff => s.transferDetails?.dropoff,
    vehicleType => s.transferDetails?.vehicleType,
    transferType => s.transferDetails?.transferType,
    activityName => s.activityDetails?.activityName,
    duration => s.activityDetails?.duration,
    activityType => s.activityDetails?.activityType,
  };

  /// Clone one closed, known field; retain all other sparse overrides verbatim.
  SupplierImportServiceOverrides replaceIn(
    SupplierImportServiceOverrides current,
    SupplierImportFieldOverride<Object?>? value,
  ) {
    final result = current.toMap();
    final fields = branch == null
        ? result
        : Map<String, Object?>.from((result[branch] as Map?) ?? const {});
    if (value == null) {
      fields.remove(wireKey);
    } else {
      fields[wireKey] = value.toMap();
    }
    if (branch != null) {
      if (fields.isEmpty) {
        result.remove(branch);
      } else {
        result[branch!] = fields;
      }
    }
    return SupplierImportServiceOverrides.fromMap(result);
  }
}

String serviceCorrectionValueLabel(Object? value) => switch (value) {
  null => 'Not provided',
  DateTime() => value.toIso8601String().substring(0, 10),
  SupplierExtractionServiceType() => reviewLabel(value.value),
  SupplierExtractionTransferType() => reviewLabel(value.value),
  bool() => value ? 'Yes' : 'No',
  List() =>
    value.isEmpty
        ? 'Empty list'
        : value
              .map((item) => '• ${serviceCorrectionValueLabel(item)}')
              .join('\n'),
  SupplierExtractionStatement() => value.text,
  _ => value.toString(),
};

String serviceCorrectionLabel(SupplierImportFieldOverride<Object?>? value) =>
    switch (value) {
      SupplierImportSetOverride(:final value) => serviceCorrectionValueLabel(
        value,
      ),
      SupplierImportClearOverride() => 'Cleared for import',
      null => 'Untouched · use supplier value',
    };
