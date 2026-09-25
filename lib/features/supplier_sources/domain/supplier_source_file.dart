import 'supplier_source_validation.dart';

/// Immutable original-source metadata. Storage access is a separate concern.
final class SupplierSourceFile {
  SupplierSourceFile({
    required String id,
    required String tripId,
    required String packageId,
    required this.originalFileName,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    required String uploadedByUid,
    required DateTime createdAt,
  }) : id = SupplierSourceValidation.id(id),
       tripId = SupplierSourceValidation.id(tripId),
       packageId = SupplierSourceValidation.id(packageId),
       uploadedByUid = SupplierSourceValidation.id(uploadedByUid),
       createdAt = createdAt.toUtc() {
    validateMetadata(
      originalFileName: originalFileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
    );
    final expected = buildStoragePath(
      tripId: tripId,
      fileId: id,
      storageFileName: storagePath.split('/').last,
    );
    if (storagePath != expected) {
      throw const FormatException(
        'Storage path does not match source identity.',
      );
    }
  }

  factory SupplierSourceFile.fromMap(
    Map<String, Object?> data, {
    required String documentId,
    required String expectedTripId,
  }) {
    SupplierSourceValidation.fields(data, {
      'tripId',
      'packageId',
      'originalFileName',
      'storagePath',
      'contentType',
      'sizeBytes',
      'uploadedByUid',
      'createdAt',
    });
    return SupplierSourceFile(
      id: documentId,
      tripId: SupplierSourceValidation.scopedTrip(
        data['tripId'],
        expectedTripId,
      ),
      packageId: SupplierSourceValidation.string(data['packageId']),
      originalFileName: SupplierSourceValidation.string(
        data['originalFileName'],
      ),
      storagePath: SupplierSourceValidation.string(data['storagePath']),
      contentType: SupplierSourceValidation.string(data['contentType']),
      sizeBytes: SupplierSourceValidation.integer(data['sizeBytes']),
      uploadedByUid: SupplierSourceValidation.string(data['uploadedByUid']),
      createdAt: SupplierSourceValidation.dateTime(data['createdAt']),
    );
  }

  static const maxSizeBytes = 25 * 1024 * 1024;
  static const supportedContentTypes = <String>{
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv',
    'text/plain',
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  final String id;
  final String tripId;
  final String packageId;
  final String originalFileName;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final String uploadedByUid;
  final DateTime createdAt;

  static void validateMetadata({
    required String originalFileName,
    required String contentType,
    required int sizeBytes,
  }) {
    SupplierSourceValidation.requiredText(originalFileName);
    if (!supportedContentTypes.contains(contentType)) {
      throw const FormatException('Unsupported source file content type.');
    }
    if (sizeBytes <= 0 || sizeBytes > maxSizeBytes) {
      throw const FormatException(
        'Source file must be between 1 byte and 25 MB.',
      );
    }
  }

  /// Caller supplies an already-sanitized filename; this never rewrites it.
  static String buildStoragePath({
    required String tripId,
    required String fileId,
    required String storageFileName,
  }) {
    SupplierSourceValidation.id(tripId);
    SupplierSourceValidation.id(fileId);
    SupplierSourceValidation.id(storageFileName);
    return 'trips/$tripId/supplier_sources/$fileId/$storageFileName';
  }

  Map<String, Object?> toMap() => {
    'tripId': tripId,
    'packageId': packageId,
    'originalFileName': originalFileName,
    'storagePath': storagePath,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
    'uploadedByUid': uploadedByUid,
    'createdAt': createdAt,
  };
}
