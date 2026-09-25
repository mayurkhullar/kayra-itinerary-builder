import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/supplier_source_file.dart';
import '../domain/supplier_source_package.dart';
import '../domain/supplier_source_validation.dart';

abstract class SupplierSourceRepository {
  /// The UID must come from the authenticated session, not form input.
  Future<String> createPackage({
    required String tripId,
    required String currentUserUid,
    String? supplierId,
    String? supplierNameSnapshot,
  });
  Future<String> createFileMetadata({
    required String tripId,
    required String packageId,
    required String originalFileName,
    required String storageFileName,
    required String contentType,
    required int sizeBytes,
    required String currentUserUid,
  });
  Future<SupplierSourcePackage?> getPackage(String tripId, String packageId);
  Future<SupplierSourceFile?> getFile(String tripId, String fileId);
  Future<List<SupplierSourcePackage>> listPackagesForTrip(String tripId);
  Future<List<SupplierSourceFile>> listFilesForPackage(
    String tripId,
    String packageId,
  );
  Future<void> updatePackageAfterUpload({
    required String tripId,
    required String packageId,
    required List<String> fileIds,
    required SupplierSourcePackageStatus status,
  });
}

/// Metadata foundation only. Not wired to UI; Firestore rules remain unchanged.
/// No Storage operations or normal file-metadata mutations are exposed.
class FirestoreSupplierSourceRepository implements SupplierSourceRepository {
  FirestoreSupplierSourceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _packages(String tripId) {
    SupplierSourceValidation.id(tripId);
    return _firestore.collection('trips/$tripId/supplier_source_packages');
  }

  CollectionReference<Map<String, dynamic>> _files(String tripId) {
    SupplierSourceValidation.id(tripId);
    return _firestore.collection('trips/$tripId/supplier_source_files');
  }

  @override
  Future<String> createPackage({
    required String tripId,
    required String currentUserUid,
    String? supplierId,
    String? supplierNameSnapshot,
  }) async {
    SupplierSourceValidation.id(currentUserUid);
    SupplierSourcePackage.validateSupplierLink(
      supplierId,
      supplierNameSnapshot,
    );
    final reference = _packages(tripId).doc();
    await reference.set({
      'tripId': tripId,
      'supplierId': supplierId,
      'supplierNameSnapshot': supplierNameSnapshot,
      'fileIds': <String>[],
      'uploadedByUid': currentUserUid,
      'status': SupplierSourcePackageStatus.uploading.value,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  @override
  Future<String> createFileMetadata({
    required String tripId,
    required String packageId,
    required String originalFileName,
    required String storageFileName,
    required String contentType,
    required int sizeBytes,
    required String currentUserUid,
  }) async {
    SupplierSourceValidation.id(packageId);
    SupplierSourceValidation.id(currentUserUid);
    SupplierSourceValidation.id(storageFileName);
    SupplierSourceFile.validateMetadata(
      originalFileName: originalFileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
    );
    final reference = _files(tripId).doc();
    await reference.set({
      'tripId': tripId,
      'packageId': packageId,
      'originalFileName': originalFileName,
      'storagePath': SupplierSourceFile.buildStoragePath(
        tripId: tripId,
        fileId: reference.id,
        storageFileName: storageFileName,
      ),
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'uploadedByUid': currentUserUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  @override
  Future<SupplierSourcePackage?> getPackage(
    String tripId,
    String packageId,
  ) async {
    SupplierSourceValidation.id(packageId);
    final snapshot = await _packages(tripId)
        .doc(packageId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return snapshot.exists ? _readPackage(snapshot, tripId) : null;
  }

  @override
  Future<SupplierSourceFile?> getFile(String tripId, String fileId) async {
    SupplierSourceValidation.id(fileId);
    final snapshot = await _files(tripId)
        .doc(fileId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return snapshot.exists ? _readFile(snapshot, tripId) : null;
  }

  @override
  Future<List<SupplierSourcePackage>> listPackagesForTrip(String tripId) async {
    final snapshot = await _packages(tripId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return List.unmodifiable(
      snapshot.docs.map((doc) => _readPackage(doc, tripId)),
    );
  }

  /// Package.fileIds is the authoritative source order once upload completes.
  @override
  Future<List<SupplierSourceFile>> listFilesForPackage(
    String tripId,
    String packageId,
  ) async {
    SupplierSourceValidation.id(packageId);
    final snapshot = await _files(tripId)
        .where('packageId', isEqualTo: packageId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return List.unmodifiable(
      snapshot.docs.map((doc) => _readFile(doc, tripId)),
    );
  }

  @override
  Future<void> updatePackageAfterUpload({
    required String tripId,
    required String packageId,
    required List<String> fileIds,
    required SupplierSourcePackageStatus status,
  }) async {
    SupplierSourceValidation.id(packageId);
    if (status == SupplierSourcePackageStatus.uploading) {
      throw const FormatException('Upload outcome must be uploaded or failed.');
    }
    final orderedIds = SupplierSourcePackage.validateFileIds(fileIds, status);
    // Update does not upsert or overwrite Supplier linkage or creation metadata.
    await _packages(tripId).doc(packageId).update({
      'fileIds': orderedIds,
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  SupplierSourcePackage _readPackage(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String tripId,
  ) => SupplierSourcePackage.fromMap(
    _readData(snapshot, ['createdAt', 'updatedAt']),
    documentId: snapshot.id,
    expectedTripId: tripId,
  );

  SupplierSourceFile _readFile(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String tripId,
  ) => SupplierSourceFile.fromMap(
    _readData(snapshot, ['createdAt']),
    documentId: snapshot.id,
    expectedTripId: tripId,
  );

  Map<String, Object?> _readData(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    List<String> timestampFields,
  ) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const FormatException('Source metadata is unavailable.');
    }
    final converted = Map<String, Object?>.from(data);
    for (final field in timestampFields) {
      final value = data[field];
      if (value is! Timestamp) {
        throw FormatException('Invalid source $field timestamp.');
      }
      converted[field] = value.toDate().toUtc();
    }
    return converted;
  }
}
