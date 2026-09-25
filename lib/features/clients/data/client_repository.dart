import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/kayra_client.dart';

abstract class ClientRepository {
  /// Caller supplies the current authenticated user's UID, never form input.
  /// Returns the generated ID once the write is acknowledged by Firestore.
  Future<String> createClient({
    required ClientDetails details,
    required String currentUserUid,
  });
  Future<KayraClient?> getClientById(String clientId);
  Future<void> updateClient({
    required String clientId,
    required ClientDetails details,
  });

  /// Agents pass their authenticated UID. Firestore enforces ownership.
  Future<List<KayraClient>> listOwnedClients(String ownerUid);

  /// Firestore permits this unrestricted query only for active Admins.
  Future<List<KayraClient>> listAllClientsForAdmin();
}

/// Explicit query scopes; server rules remain the authorization boundary.
class FirestoreClientRepository implements ClientRepository {
  FirestoreClientRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<String> createClient({
    required ClientDetails details,
    required String currentUserUid,
  }) async {
    if (!KayraClient.isValidId(currentUserUid)) {
      throw const FormatException('Invalid authenticated user UID.');
    }
    final reference = _firestore.collection('clients').doc();
    await reference.set({
      ...details.toMap(),
      'createdByUid': currentUserUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Avoid a post-create read whose failure could prompt duplicate creation.
    return reference.id;
  }

  @override
  Future<KayraClient?> getClientById(String clientId) async {
    _validateId(clientId);
    final snapshot = await _firestore
        .collection('clients')
        .doc(clientId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return snapshot.exists ? _readClient(snapshot) : null;
  }

  @override
  Future<void> updateClient({
    required String clientId,
    required ClientDetails details,
  }) async {
    _validateId(clientId);
    // A profile-only payload cannot overwrite identity or creation metadata.
    // update also fails for a missing document rather than creating one.
    await _firestore.collection('clients').doc(clientId).update({
      ...details.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<KayraClient>> listOwnedClients(String ownerUid) async {
    if (!KayraClient.isValidId(ownerUid)) {
      throw const FormatException('Invalid owner UID.');
    }
    return _listClients(
      _firestore
          .collection('clients')
          .where('createdByUid', isEqualTo: ownerUid),
    );
  }

  @override
  Future<List<KayraClient>> listAllClientsForAdmin() =>
      _listClients(_firestore.collection('clients'));

  Future<List<KayraClient>> _listClients(
    Query<Map<String, dynamic>> query,
  ) async {
    final snapshot = await query
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return List.unmodifiable(snapshot.docs.map(_readClient));
  }

  KayraClient _readClient(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const FormatException('Client data is unavailable.');
    }
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    if (createdAt is! Timestamp || updatedAt is! Timestamp) {
      throw const FormatException('Client timestamps are unavailable.');
    }
    return KayraClient.fromMap({
      ...data,
      'createdAt': createdAt.toDate().toUtc(),
      'updatedAt': updatedAt.toDate().toUtc(),
    }, documentId: snapshot.id);
  }

  void _validateId(String clientId) {
    if (!KayraClient.isValidId(clientId)) {
      throw const FormatException('Invalid client ID.');
    }
  }
}
