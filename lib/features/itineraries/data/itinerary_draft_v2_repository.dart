import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/itinerary_draft_v2.dart';

enum ItineraryDraftV2RepositoryFailureKind {
  notFound,
  malformed,
  unsupportedVersion,
  identityMismatch,
  permissionDenied,
  readFailed,
}

final class ItineraryDraftV2RepositoryFailure implements Exception {
  const ItineraryDraftV2RepositoryFailure(this.kind);
  final ItineraryDraftV2RepositoryFailureKind kind;
  String get userMessage => switch (kind) {
    ItineraryDraftV2RepositoryFailureKind.notFound =>
      'The itinerary draft could not be found.',
    ItineraryDraftV2RepositoryFailureKind.unsupportedVersion =>
      'This itinerary draft version is not supported.',
    ItineraryDraftV2RepositoryFailureKind.permissionDenied =>
      'You do not have access to this itinerary draft.',
    ItineraryDraftV2RepositoryFailureKind.readFailed =>
      'The itinerary draft could not be loaded.',
    _ => 'The stored itinerary draft is invalid.',
  };
  @override
  String toString() => userMessage;
}

abstract interface class ItineraryDraftV2Repository {
  Future<ItineraryDraftV2> getDraft(String tripId, String draftId);
}

final class FirestoreItineraryDraftV2Repository
    implements ItineraryDraftV2Repository {
  FirestoreItineraryDraftV2Repository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  @override
  Future<ItineraryDraftV2> getDraft(String tripId, String draftId) async {
    try {
      for (final id in [tripId, draftId]) {
        if (id.isEmpty ||
            id.trim() != id ||
            id == '.' ||
            id == '..' ||
            RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(id)) {
          throw const ItineraryDraftV2RepositoryFailure(
            ItineraryDraftV2RepositoryFailureKind.identityMismatch,
          );
        }
      }
      final doc = await _firestore
          .collection('trips/$tripId/itinerary_drafts')
          .doc(draftId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 30));
      if (!doc.exists) {
        throw const ItineraryDraftV2RepositoryFailure(
          ItineraryDraftV2RepositoryFailureKind.notFound,
        );
      }
      final data = doc.data();
      if (data == null) throw const FormatException('Missing itinerary data.');
      if (doc.id != draftId ||
          (data['tripId'] is String && data['tripId'] != tripId)) {
        throw const ItineraryDraftV2RepositoryFailure(
          ItineraryDraftV2RepositoryFailureKind.identityMismatch,
        );
      }
      return ItineraryDraftV2.fromFirestore(data, documentId: doc.id);
    } on ItineraryDraftV2RepositoryFailure {
      rethrow;
    } on UnsupportedItineraryDraftV2Schema {
      throw const ItineraryDraftV2RepositoryFailure(
        ItineraryDraftV2RepositoryFailureKind.unsupportedVersion,
      );
    } on FormatException {
      throw const ItineraryDraftV2RepositoryFailure(
        ItineraryDraftV2RepositoryFailureKind.malformed,
      );
    } on FirebaseException catch (error) {
      throw ItineraryDraftV2RepositoryFailure(
        error.code == 'permission-denied'
            ? ItineraryDraftV2RepositoryFailureKind.permissionDenied
            : ItineraryDraftV2RepositoryFailureKind.readFailed,
      );
    } catch (_) {
      throw const ItineraryDraftV2RepositoryFailure(
        ItineraryDraftV2RepositoryFailureKind.readFailed,
      );
    }
  }
}
