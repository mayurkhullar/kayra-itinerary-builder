import 'supplier_source_validation.dart';

enum SupplierSourcePackageStatus {
  uploading('uploading'),
  uploaded('uploaded'),
  failed('failed');

  const SupplierSourcePackageStatus(this.value);
  final String value;

  static SupplierSourcePackageStatus parse(Object? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => throw const FormatException('Invalid source package status.'),
  );
}

final class SupplierSourcePackage {
  SupplierSourcePackage({
    required String id,
    required String tripId,
    this.supplierId,
    this.supplierNameSnapshot,
    List<String> fileIds = const [],
    required String uploadedByUid,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.status = SupplierSourcePackageStatus.uploading,
  }) : id = SupplierSourceValidation.id(id),
       tripId = SupplierSourceValidation.id(tripId),
       fileIds = validateFileIds(fileIds, status),
       uploadedByUid = SupplierSourceValidation.id(uploadedByUid),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    validateSupplierLink(supplierId, supplierNameSnapshot);
  }

  /// Firestore timestamps are converted by the repository before parsing.
  factory SupplierSourcePackage.fromMap(
    Map<String, Object?> data, {
    required String documentId,
    required String expectedTripId,
  }) {
    SupplierSourceValidation.fields(data, {
      'tripId',
      'supplierId',
      'supplierNameSnapshot',
      'fileIds',
      'uploadedByUid',
      'createdAt',
      'updatedAt',
      'status',
    });
    return SupplierSourcePackage(
      id: documentId,
      tripId: SupplierSourceValidation.scopedTrip(
        data['tripId'],
        expectedTripId,
      ),
      supplierId: SupplierSourceValidation.nullableString(data['supplierId']),
      supplierNameSnapshot: SupplierSourceValidation.nullableString(
        data['supplierNameSnapshot'],
      ),
      fileIds: SupplierSourceValidation.strings(data['fileIds']),
      uploadedByUid: SupplierSourceValidation.string(data['uploadedByUid']),
      createdAt: SupplierSourceValidation.dateTime(data['createdAt']),
      updatedAt: SupplierSourceValidation.dateTime(data['updatedAt']),
      status: SupplierSourcePackageStatus.parse(data['status']),
    );
  }

  final String id;
  final String tripId;
  final String? supplierId;
  final String? supplierNameSnapshot;
  final List<String> fileIds;
  final String uploadedByUid;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SupplierSourcePackageStatus status;

  static void validateSupplierLink(String? id, String? name) {
    if ((id == null) != (name == null)) {
      throw const FormatException(
        'Supplier identity and snapshot must be paired.',
      );
    }
    if (id != null) SupplierSourceValidation.id(id);
    if (name != null) SupplierSourceValidation.requiredText(name);
  }

  static List<String> validateFileIds(
    List<String> values,
    SupplierSourcePackageStatus status,
  ) {
    final ids = values.map(SupplierSourceValidation.id).toList();
    if (ids.toSet().length != ids.length) {
      throw const FormatException('Duplicate source file identities.');
    }
    if (status == SupplierSourcePackageStatus.uploaded && ids.isEmpty) {
      throw const FormatException('An uploaded package must contain a file.');
    }
    return List.unmodifiable(ids);
  }

  Map<String, Object?> toMap() => {
    'tripId': tripId,
    'supplierId': supplierId,
    'supplierNameSnapshot': supplierNameSnapshot,
    'fileIds': fileIds.toList(),
    'uploadedByUid': uploadedByUid,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'status': status.value,
  };
}
