import 'package:cloud_firestore/cloud_firestore.dart';

import '../../clients/data/client_repository.dart';
import '../../clients/domain/kayra_client.dart';
import '../domain/kayra_trip.dart';

abstract class TripRepository {
  /// UID comes from the authenticated session, never a user-editable brief.
  Future<String> createTrip({
    required String clientId,
    required TripBrief brief,
    required String currentUserUid,
  });
  Future<KayraTrip?> getTripById(String tripId);
  Future<void> updateTrip({required String tripId, required TripBrief brief});
  Future<List<KayraTrip>> listOwnedTrips(String ownerUid);
  Future<List<KayraTrip>> listAllTripsForAdmin();
}

/// Foundation only: not wired to UI; Trip authorization rules are a separate task.
class FirestoreTripRepository implements TripRepository {
  FirestoreTripRepository({
    FirebaseFirestore? firestore,
    ClientRepository? clientRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _clients =
           clientRepository ?? FirestoreClientRepository(firestore: firestore);

  final FirebaseFirestore _firestore;
  final ClientRepository _clients;

  @override
  Future<String> createTrip({
    required String clientId,
    required TripBrief brief,
    required String currentUserUid,
  }) async {
    TripValidation.id(currentUserUid);
    final client = await _requireClient(clientId);
    brief.validateClientCompany(client.company);
    final reference = _firestore.collection('trips').doc();
    await reference.set({
      ..._briefPayload(brief),
      'clientId': client.id,
      'clientFirstName': client.firstName,
      'clientLastName': client.lastName,
      'tripName': brief.tripNameFor(client.firstName, client.lastName),
      'status': TripStatus.draft.value,
      'ownerUid': currentUserUid,
      'createdByUid': currentUserUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  @override
  Future<KayraTrip?> getTripById(String tripId) async {
    TripValidation.id(tripId);
    final snapshot = await _firestore
        .collection('trips')
        .doc(tripId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return snapshot.exists ? _readTrip(snapshot) : null;
  }

  @override
  Future<void> updateTrip({
    required String tripId,
    required TripBrief brief,
  }) async {
    final trip = await getTripById(tripId);
    if (trip == null) throw StateError('Trip does not exist.');
    final client = await _requireClient(trip.clientId);
    brief.validateClientCompany(client.company);
    // Keep the Client link and original name snapshot immutable for now.
    // Protected metadata is omitted, including when ownership/status changed
    // concurrently; update never recreates a missing document.
    await _firestore.collection('trips').doc(tripId).update({
      ..._briefPayload(brief),
      'tripName': brief.tripNameFor(trip.clientFirstName, trip.clientLastName),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<KayraTrip>> listOwnedTrips(String ownerUid) {
    TripValidation.id(ownerUid);
    return _listTrips(
      _firestore.collection('trips').where('ownerUid', isEqualTo: ownerUid),
    );
  }

  @override
  Future<List<KayraTrip>> listAllTripsForAdmin() =>
      _listTrips(_firestore.collection('trips'));

  Future<List<KayraTrip>> _listTrips(Query<Map<String, dynamic>> query) async {
    final snapshot = await query
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return List.unmodifiable(snapshot.docs.map(_readTrip));
  }

  Future<KayraClient> _requireClient(String clientId) async {
    TripValidation.id(clientId);
    final client = await _clients.getClientById(clientId);
    if (client == null || client.id != clientId) {
      throw const FormatException('An existing Client is required.');
    }
    return client;
  }

  Map<String, Object?> _briefPayload(TripBrief brief) => {
    ...brief.toMap(),
    'travelStartDate': Timestamp.fromDate(brief.travelStartDate),
  };

  KayraTrip _readTrip(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const FormatException('Trip data is unavailable.');
    }
    final converted = Map<String, Object?>.from(data);
    for (final field in ['travelStartDate', 'createdAt', 'updatedAt']) {
      final value = data[field];
      if (value is! Timestamp) {
        throw FormatException('Invalid trip $field timestamp.');
      }
      converted[field] = value.toDate().toUtc();
    }
    return KayraTrip.fromMap(converted, documentId: snapshot.id);
  }
}
