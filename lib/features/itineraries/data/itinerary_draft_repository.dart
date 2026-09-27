import 'package:cloud_firestore/cloud_firestore.dart';

import '../../supplier_sources/data/supplier_source_repository.dart';
import '../../supplier_sources/domain/supplier_source_package.dart';
import '../domain/itinerary_model_validation.dart';
import '../domain/kayra_itinerary_day.dart';
import '../domain/kayra_itinerary_draft.dart';
import '../domain/kayra_itinerary_review_issue.dart';

abstract class ItineraryDraftRepository {
  Future<String> createDraft({
    required String tripId,
    required String title,
    List<KayraItineraryDay> days = const [],
    List<String> sourcePackageIds = const [],
    List<KayraItineraryReviewIssue> reviewIssues = const [],
    required String currentUserUid,
  });

  Future<KayraItineraryDraft?> getDraft(String tripId, String draftId);

  Future<List<KayraItineraryDraft>> listDraftsForTrip(String tripId);

  Future<void> updateDraft({
    required String tripId,
    required KayraItineraryDraft draft,
  });
}

final class FirestoreItineraryDraftRepository
    implements ItineraryDraftRepository {
  FirestoreItineraryDraftRepository({
    FirebaseFirestore? firestore,
    SupplierSourceRepository? sourceRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _sources =
           sourceRepository ??
           FirestoreSupplierSourceRepository(firestore: firestore);

  final FirebaseFirestore _firestore;
  final SupplierSourceRepository _sources;

  CollectionReference<Map<String, dynamic>> _drafts(String tripId) {
    ItineraryModelValidation.id(tripId, 'trip');
    return _firestore.collection('trips/$tripId/itinerary_drafts');
  }

  @override
  Future<String> createDraft({
    required String tripId,
    required String title,
    List<KayraItineraryDay> days = const [],
    List<String> sourcePackageIds = const [],
    List<KayraItineraryReviewIssue> reviewIssues = const [],
    required String currentUserUid,
  }) async {
    ItineraryModelValidation.id(currentUserUid, 'creator');
    final reference = _drafts(tripId).doc();
    final now = DateTime.now().toUtc();
    final draft = KayraItineraryDraft(
      id: reference.id,
      tripId: tripId,
      title: title,
      days: days,
      sourcePackageIds: sourcePackageIds,
      reviewIssues: reviewIssues,
      createdByUid: currentUserUid,
      createdAt: now,
      updatedAt: now,
    );
    await _requireUploadedSourcePackages(draft);
    final payload = _toFirestoreMap(draft.toMap())
      ..['createdAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await reference.set(payload);
    return reference.id;
  }

  @override
  Future<KayraItineraryDraft?> getDraft(String tripId, String draftId) async {
    ItineraryModelValidation.id(draftId, 'itinerary draft');
    final snapshot = await _drafts(tripId)
        .doc(draftId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return snapshot.exists ? _readDraft(snapshot, tripId) : null;
  }

  @override
  Future<List<KayraItineraryDraft>> listDraftsForTrip(String tripId) async {
    final snapshot = await _drafts(tripId)
        .orderBy('createdAt')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return List.unmodifiable(
      snapshot.docs.map((snapshot) => _readDraft(snapshot, tripId)),
    );
  }

  @override
  Future<void> updateDraft({
    required String tripId,
    required KayraItineraryDraft draft,
  }) async {
    ItineraryModelValidation.id(tripId, 'trip');
    if (draft.tripId != tripId) {
      throw const FormatException('An itinerary draft cannot move Trips.');
    }
    final existing = await getDraft(tripId, draft.id);
    if (existing == null) {
      throw StateError('Itinerary draft does not exist.');
    }
    if (draft.createdByUid != existing.createdByUid ||
        draft.createdAt != existing.createdAt) {
      throw const FormatException(
        'Itinerary draft creation metadata is immutable.',
      );
    }
    await _requireUploadedSourcePackages(draft);
    final serialized = _toFirestoreMap(draft.toMap());
    await _drafts(tripId).doc(draft.id).update({
      'title': serialized['title'],
      'days': serialized['days'],
      'sourcePackageIds': serialized['sourcePackageIds'],
      'reviewIssues': serialized['reviewIssues'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _requireUploadedSourcePackages(KayraItineraryDraft draft) async {
    for (final packageId in draft.sourcePackageIds) {
      final package = await _sources.getPackage(draft.tripId, packageId);
      if (package == null || package.tripId != draft.tripId) {
        throw const FormatException(
          'An existing Supplier Source package from this Trip is required.',
        );
      }
      if (package.status != SupplierSourcePackageStatus.uploaded) {
        throw const FormatException(
          'Only uploaded Supplier Source packages may be attached.',
        );
      }
    }
  }

  KayraItineraryDraft _readDraft(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String tripId,
  ) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const FormatException('Itinerary draft data is unavailable.');
    }
    final converted = _fromFirestoreMap(data);
    if (converted['tripId'] != tripId) {
      throw const FormatException('Itinerary draft belongs to another Trip.');
    }
    return KayraItineraryDraft.fromMap(converted, documentId: snapshot.id);
  }
}

Map<String, dynamic> _toFirestoreMap(Map<String, Object?> data) =>
    data.map((key, value) => MapEntry(key, _toFirestoreValue(value)));

Object? _toFirestoreValue(Object? value) {
  if (value is DateTime) return Timestamp.fromDate(value.toUtc());
  if (value is List) return value.map(_toFirestoreValue).toList();
  if (value is Map) {
    return ItineraryModelValidation.map(
      value,
    ).map((key, nested) => MapEntry(key, _toFirestoreValue(nested)));
  }
  return value;
}

Map<String, Object?> _fromFirestoreMap(Map<String, dynamic> data) =>
    data.map((key, value) => MapEntry(key, _fromFirestoreValue(value)));

Object? _fromFirestoreValue(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) {
    throw const FormatException('Invalid itinerary Firestore timestamp value.');
  }
  if (value is List) return value.map(_fromFirestoreValue).toList();
  if (value is Map) {
    return ItineraryModelValidation.map(
      value,
    ).map((key, nested) => MapEntry(key, _fromFirestoreValue(nested)));
  }
  return value;
}
