import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/supplier_import_resolution.dart';
import '../domain/supplier_import_resolution_parsing.dart';

enum SupplierImportResolutionRepositoryFailureKind {
  permissionDenied,
  malformed,
  readFailed,
}

final class SupplierImportResolutionRepositoryFailure implements Exception {
  const SupplierImportResolutionRepositoryFailure(this.kind, this.userMessage);

  final SupplierImportResolutionRepositoryFailureKind kind;
  final String userMessage;

  @override
  String toString() => userMessage;
}

abstract interface class SupplierImportResolutionRepository {
  Future<SupplierImportResolutionReadResult> getResolution({
    required String tripId,
    required String extractionId,
  });
}

abstract interface class SupplierImportResolutionReadStore {
  Future<SupplierImportResolutionStoredDocument?> readRoot(
    String tripId,
    String extractionId,
  );

  Future<List<SupplierImportResolutionStoredDocument>> readChildren(
    String tripId,
    String extractionId,
    String collection,
  );
}

final class FirestoreSupplierImportResolutionRepository
    implements SupplierImportResolutionRepository {
  FirestoreSupplierImportResolutionRepository({
    FirebaseFirestore? firestore,
    SupplierImportResolutionReadStore? store,
  }) : _store =
           store ??
           _FirestoreResolutionReadStore(
             firestore ?? FirebaseFirestore.instance,
           );

  final SupplierImportResolutionReadStore _store;

  @override
  Future<SupplierImportResolutionReadResult> getResolution({
    required String tripId,
    required String extractionId,
  }) async {
    try {
      SupplierImportResolutionParsing.id(tripId, 'Trip');
      SupplierImportResolutionParsing.id(extractionId, 'Extraction');
      final root = await _store
          .readRoot(tripId, extractionId)
          .timeout(const Duration(seconds: 30));
      if (root == null) return const SupplierImportResolutionNotStarted();
      final children = await Future.wait([
        _store.readChildren(tripId, extractionId, 'decisions'),
        _store.readChildren(tripId, extractionId, 'manual_items'),
        _store.readChildren(tripId, extractionId, 'events'),
      ]).timeout(const Duration(seconds: 30));
      return SupplierImportResolutionLoaded(
        SupplierImportResolutionAggregate.fromStoredDocuments(
          expectedTripId: tripId,
          expectedExtractionId: extractionId,
          rootDocumentId: root.documentId,
          rootData: root.data,
          decisionDocuments: children[0],
          manualItemDocuments: children[1],
          eventDocuments: children[2],
        ),
      );
    } on SupplierImportResolutionRepositoryFailure {
      rethrow;
    } on FormatException {
      throw const SupplierImportResolutionRepositoryFailure(
        SupplierImportResolutionRepositoryFailureKind.malformed,
        'The stored Supplier Import Resolution is invalid.',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const SupplierImportResolutionRepositoryFailure(
          SupplierImportResolutionRepositoryFailureKind.permissionDenied,
          'You do not have access to this Supplier Import Resolution.',
        );
      }
      throw const SupplierImportResolutionRepositoryFailure(
        SupplierImportResolutionRepositoryFailureKind.readFailed,
        'The Supplier Import Resolution could not be loaded.',
      );
    } on TimeoutException {
      throw const SupplierImportResolutionRepositoryFailure(
        SupplierImportResolutionRepositoryFailureKind.readFailed,
        'The Supplier Import Resolution could not be loaded.',
      );
    } catch (_) {
      throw const SupplierImportResolutionRepositoryFailure(
        SupplierImportResolutionRepositoryFailureKind.readFailed,
        'The Supplier Import Resolution could not be loaded.',
      );
    }
  }
}

final class _FirestoreResolutionReadStore
    implements SupplierImportResolutionReadStore {
  const _FirestoreResolutionReadStore(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _root(
    String tripId,
    String extractionId,
  ) => _firestore
      .collection(
        'trips/$tripId/supplier_extractions/$extractionId/resolutions',
      )
      .doc(extractionId);

  @override
  Future<SupplierImportResolutionStoredDocument?> readRoot(
    String tripId,
    String extractionId,
  ) async {
    final snapshot = await _root(
      tripId,
      extractionId,
    ).get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return (documentId: snapshot.id, data: _fromFirestoreMap(data));
  }

  @override
  Future<List<SupplierImportResolutionStoredDocument>> readChildren(
    String tripId,
    String extractionId,
    String collection,
  ) async {
    final snapshot = await _root(
      tripId,
      extractionId,
    ).collection(collection).get(const GetOptions(source: Source.server));
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
    throw const FormatException('Resolution timestamp is invalid.');
  }
  if (value is List) return value.map(_fromFirestoreValue).toList();
  if (value is Map) {
    return value.map((key, nested) {
      if (key is! String) {
        throw const FormatException('Resolution map key is invalid.');
      }
      return MapEntry(key, _fromFirestoreValue(nested));
    });
  }
  return value;
}
