import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/kayra_supplier.dart';

abstract class SupplierRepository {
  /// UID comes from the authenticated session, never supplier form input.
  Future<String> createSupplier({
    required SupplierDetails details,
    required String currentUserUid,
  });
  Future<KayraSupplier?> getSupplierById(String supplierId);
  Future<void> updateSupplier({
    required String supplierId,
    required SupplierDetails details,
  });
  Future<List<KayraSupplier>> listSuppliers();
}

/// Shared company master, with no creator/owner query filter.
/// Production access remains denied until Supplier security rules are added.
class FirestoreSupplierRepository implements SupplierRepository {
  FirestoreSupplierRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<String> createSupplier({
    required SupplierDetails details,
    required String currentUserUid,
  }) async {
    SupplierValidation.id(currentUserUid);
    final reference = _firestore.collection('suppliers').doc();
    await reference.set({
      ...details.toMap(),
      'status': SupplierStatus.active.value,
      'createdByUid': currentUserUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  @override
  Future<KayraSupplier?> getSupplierById(String supplierId) async {
    SupplierValidation.id(supplierId);
    final snapshot = await _firestore
        .collection('suppliers')
        .doc(supplierId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return snapshot.exists ? _readSupplier(snapshot) : null;
  }

  @override
  Future<void> updateSupplier({
    required String supplierId,
    required SupplierDetails details,
  }) async {
    SupplierValidation.id(supplierId);
    // Omit status and creation metadata; update never upserts a missing record.
    await _firestore.collection('suppliers').doc(supplierId).update({
      ...details.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<KayraSupplier>> listSuppliers() async {
    final snapshot = await _firestore
        .collection('suppliers')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return List.unmodifiable(snapshot.docs.map(_readSupplier));
  }

  KayraSupplier _readSupplier(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const FormatException('Supplier data is unavailable.');
    }
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    if (createdAt is! Timestamp || updatedAt is! Timestamp) {
      throw const FormatException('Supplier timestamps are unavailable.');
    }
    return KayraSupplier.fromMap({
      ...data,
      'createdAt': createdAt.toDate().toUtc(),
      'updatedAt': updatedAt.toDate().toUtc(),
    }, documentId: snapshot.id);
  }
}
