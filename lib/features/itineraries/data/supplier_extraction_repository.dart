import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../supplier_sources/data/supplier_source_repository.dart';
import '../../supplier_sources/domain/supplier_source_package.dart';
import '../domain/itinerary_model_validation.dart';
import '../domain/supplier_extraction_snapshot.dart';

enum SupplierExtractionRepositoryFailureKind {
  notFound,
  unavailable,
  malformed,
  readFailed,
}

final class SupplierExtractionRepositoryFailure implements Exception {
  const SupplierExtractionRepositoryFailure(this.kind, this.userMessage);

  final SupplierExtractionRepositoryFailureKind kind;
  final String userMessage;

  @override
  String toString() => userMessage;
}

abstract interface class SupplierExtractionRepository {
  Future<SupplierExtractionSnapshot> getCompleteSnapshot({
    required String tripId,
    required String extractionId,
  });
}

final class FirestoreSupplierExtractionRepository
    implements SupplierExtractionRepository {
  FirestoreSupplierExtractionRepository({
    FirebaseFirestore? firestore,
    SupplierSourceRepository? sourceRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _sources =
           sourceRepository ??
           FirestoreSupplierSourceRepository(firestore: firestore);

  final FirebaseFirestore _firestore;
  final SupplierSourceRepository _sources;

  @override
  Future<SupplierExtractionSnapshot> getCompleteSnapshot({
    required String tripId,
    required String extractionId,
  }) async {
    ItineraryModelValidation.id(tripId, 'trip');
    ItineraryModelValidation.id(extractionId, 'supplier extraction');
    final rootReference = _firestore
        .collection('trips/$tripId/supplier_extractions')
        .doc(extractionId);
    try {
      final rootSnapshot = await rootReference
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 30));
      final rawRoot = rootSnapshot.data();
      if (!rootSnapshot.exists || rawRoot == null) {
        throw const SupplierExtractionRepositoryFailure(
          SupplierExtractionRepositoryFailureKind.notFound,
          'The Supplier Extraction Snapshot could not be found.',
        );
      }
      final root = _fromFirestoreMap(rawRoot);
      if (root['persistenceState'] != 'complete') {
        throw const SupplierExtractionRepositoryFailure(
          SupplierExtractionRepositoryFailureKind.unavailable,
          'The Supplier Extraction Snapshot is not ready.',
        );
      }

      final sourcePackageId = root['sourcePackageId'];
      if (sourcePackageId is! String) {
        throw const SupplierExtractionRepositoryFailure(
          SupplierExtractionRepositoryFailureKind.malformed,
          'The stored Supplier Extraction Snapshot is invalid.',
        );
      }
      final sourcePackage = await _sources.getPackage(tripId, sourcePackageId);
      if (sourcePackage == null ||
          sourcePackage.tripId != tripId ||
          sourcePackage.id != sourcePackageId ||
          sourcePackage.status != SupplierSourcePackageStatus.uploaded) {
        throw const SupplierExtractionRepositoryFailure(
          SupplierExtractionRepositoryFailureKind.malformed,
          'The stored Supplier Extraction Snapshot is invalid.',
        );
      }

      final childSnapshots = await Future.wait([
        _readChildren(rootReference, 'days'),
        _readChildren(rootReference, 'facts'),
        _readChildren(rootReference, 'review_issues'),
      ]);
      return SupplierExtractionSnapshot.fromStoredDocuments(
        expectedTripId: tripId,
        expectedExtractionId: extractionId,
        root: root,
        dayDocuments: childSnapshots[0],
        factDocuments: childSnapshots[1],
        reviewIssueDocuments: childSnapshots[2],
        trustedSourceFileIds: sourcePackage.fileIds,
      );
    } on SupplierExtractionRepositoryFailure {
      rethrow;
    } on SupplierExtractionIncompleteException {
      throw const SupplierExtractionRepositoryFailure(
        SupplierExtractionRepositoryFailureKind.unavailable,
        'The Supplier Extraction Snapshot is not ready.',
      );
    } on FormatException {
      throw const SupplierExtractionRepositoryFailure(
        SupplierExtractionRepositoryFailureKind.malformed,
        'The stored Supplier Extraction Snapshot is invalid.',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const SupplierExtractionRepositoryFailure(
          SupplierExtractionRepositoryFailureKind.unavailable,
          'The Supplier Extraction Snapshot is unavailable.',
        );
      }
      throw const SupplierExtractionRepositoryFailure(
        SupplierExtractionRepositoryFailureKind.readFailed,
        'The Supplier Extraction Snapshot could not be loaded.',
      );
    } on TimeoutException {
      throw const SupplierExtractionRepositoryFailure(
        SupplierExtractionRepositoryFailureKind.readFailed,
        'The Supplier Extraction Snapshot could not be loaded.',
      );
    } catch (_) {
      throw const SupplierExtractionRepositoryFailure(
        SupplierExtractionRepositoryFailureKind.readFailed,
        'The Supplier Extraction Snapshot could not be loaded.',
      );
    }
  }

  Future<List<SupplierExtractionStoredDocument>> _readChildren(
    DocumentReference<Map<String, dynamic>> root,
    String collectionName,
  ) async {
    final snapshot = await root
        .collection(collectionName)
        .orderBy('snapshotOrder')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return List.unmodifiable(
      snapshot.docs.map(
        (document) =>
            (documentId: document.id, data: _fromFirestoreMap(document.data())),
      ),
    );
  }
}

Map<String, Object?> _fromFirestoreMap(Map<String, dynamic> data) =>
    data.map((key, value) => MapEntry(key, _fromFirestoreValue(value)));

Object? _fromFirestoreValue(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) {
    throw const FormatException(
      'Invalid Supplier Extraction Firestore timestamp value.',
    );
  }
  if (value is List) return value.map(_fromFirestoreValue).toList();
  if (value is Map) {
    return value.map((key, nested) {
      if (key is! String) {
        throw const FormatException(
          'Invalid Supplier Extraction Firestore map key.',
        );
      }
      return MapEntry(key, _fromFirestoreValue(nested));
    });
  }
  return value;
}
