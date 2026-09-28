import 'package:cloud_firestore/cloud_firestore.dart';

import '../../supplier_sources/data/supplier_source_repository.dart';
import '../../supplier_sources/domain/supplier_source_package.dart';
import '../domain/itinerary_model_validation.dart';
import '../domain/kayra_itinerary_extraction_job.dart';

abstract class ItineraryExtractionJobRepository {
  Future<String> createQueuedJob({
    required String tripId,
    required String sourcePackageId,
    required String currentUserUid,
  });

  Future<KayraItineraryExtractionJob?> getJob(String tripId, String jobId);

  Stream<KayraItineraryExtractionJob?> observeJob(String tripId, String jobId);

  Future<List<KayraItineraryExtractionJob>> listJobsForTrip(String tripId);

  Future<void> markProcessing({required String tripId, required String jobId});

  Future<void> markCompleted({
    required String tripId,
    required String jobId,
    required String resultingDraftId,
  });

  Future<void> markFailed({
    required String tripId,
    required String jobId,
    required KayraItineraryExtractionFailureCode failureCode,
  });
}

final class FirestoreItineraryExtractionJobRepository
    implements ItineraryExtractionJobRepository {
  FirestoreItineraryExtractionJobRepository({
    FirebaseFirestore? firestore,
    SupplierSourceRepository? sourceRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _sources =
           sourceRepository ??
           FirestoreSupplierSourceRepository(firestore: firestore);

  final FirebaseFirestore _firestore;
  final SupplierSourceRepository _sources;

  CollectionReference<Map<String, dynamic>> _jobs(String tripId) {
    ItineraryModelValidation.id(tripId, 'trip');
    return _firestore.collection('trips/$tripId/itinerary_extraction_jobs');
  }

  @override
  Future<String> createQueuedJob({
    required String tripId,
    required String sourcePackageId,
    required String currentUserUid,
  }) async {
    ItineraryModelValidation.id(sourcePackageId, 'supplier source package');
    ItineraryModelValidation.id(currentUserUid, 'requester');
    final package = await _sources.getPackage(tripId, sourcePackageId);
    if (package == null || package.tripId != tripId) {
      throw const FormatException(
        'An existing Supplier Source package from this Trip is required.',
      );
    }
    if (package.status != SupplierSourcePackageStatus.uploaded) {
      throw const FormatException(
        'Only an uploaded Supplier Source package may be extracted.',
      );
    }

    final reference = _jobs(tripId).doc();
    final now = DateTime.now().toUtc();
    final job = KayraItineraryExtractionJob(
      id: reference.id,
      tripId: tripId,
      sourcePackageId: sourcePackageId,
      status: KayraItineraryExtractionStatus.queued,
      requestedByUid: currentUserUid,
      createdAt: now,
      updatedAt: now,
    );
    final payload = _toFirestoreMap(job.toMap())
      ..['createdAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await reference.set(payload);
    return reference.id;
  }

  @override
  Future<KayraItineraryExtractionJob?> getJob(
    String tripId,
    String jobId,
  ) async {
    ItineraryModelValidation.id(jobId, 'itinerary extraction job');
    final snapshot = await _jobs(tripId)
        .doc(jobId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return snapshot.exists ? _readJob(snapshot, tripId) : null;
  }

  @override
  Stream<KayraItineraryExtractionJob?> observeJob(String tripId, String jobId) {
    ItineraryModelValidation.id(jobId, 'itinerary extraction job');
    return _jobs(tripId)
        .doc(jobId)
        .snapshots()
        .map((snapshot) => snapshot.exists ? _readJob(snapshot, tripId) : null);
  }

  @override
  Future<List<KayraItineraryExtractionJob>> listJobsForTrip(
    String tripId,
  ) async {
    final snapshot = await _jobs(tripId)
        .orderBy('createdAt', descending: true)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    return List.unmodifiable(
      snapshot.docs.map((snapshot) => _readJob(snapshot, tripId)),
    );
  }

  @override
  Future<void> markProcessing({
    required String tripId,
    required String jobId,
  }) => _transition(
    tripId: tripId,
    jobId: jobId,
    to: KayraItineraryExtractionStatus.processing,
  );

  @override
  Future<void> markCompleted({
    required String tripId,
    required String jobId,
    required String resultingDraftId,
  }) {
    ItineraryModelValidation.id(resultingDraftId, 'itinerary draft');
    return _transition(
      tripId: tripId,
      jobId: jobId,
      to: KayraItineraryExtractionStatus.completed,
      resultingDraftId: resultingDraftId,
    );
  }

  @override
  Future<void> markFailed({
    required String tripId,
    required String jobId,
    required KayraItineraryExtractionFailureCode failureCode,
  }) => _transition(
    tripId: tripId,
    jobId: jobId,
    to: KayraItineraryExtractionStatus.failed,
    failureCode: failureCode,
  );

  Future<void> _transition({
    required String tripId,
    required String jobId,
    required KayraItineraryExtractionStatus to,
    String? resultingDraftId,
    KayraItineraryExtractionFailureCode? failureCode,
  }) async {
    ItineraryModelValidation.id(jobId, 'itinerary extraction job');
    final reference = _jobs(tripId).doc(jobId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw StateError('Itinerary extraction job does not exist.');
      }
      final current = _readJob(snapshot, tripId);
      KayraItineraryExtractionJob.validateTransition(
        from: current.status,
        to: to,
      );
      transaction.update(reference, {
        'status': to.value,
        'resultingDraftId': resultingDraftId,
        'failureCode': failureCode?.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  KayraItineraryExtractionJob _readJob(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String tripId,
  ) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw const FormatException(
        'Itinerary extraction job data is unavailable.',
      );
    }
    final converted = _fromFirestoreMap(data);
    if (converted['tripId'] != tripId) {
      throw const FormatException(
        'Itinerary extraction job belongs to another Trip.',
      );
    }
    return KayraItineraryExtractionJob.fromMap(
      converted,
      documentId: snapshot.id,
    );
  }
}

Map<String, dynamic> _toFirestoreMap(Map<String, Object?> data) =>
    data.map((key, value) => MapEntry(key, _toFirestoreValue(value)));

Object? _toFirestoreValue(Object? value) {
  if (value is DateTime) return Timestamp.fromDate(value.toUtc());
  return value;
}

Map<String, Object?> _fromFirestoreMap(Map<String, dynamic> data) =>
    data.map((key, value) => MapEntry(key, _fromFirestoreValue(value)));

Object? _fromFirestoreValue(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) {
    throw const FormatException(
      'Invalid itinerary extraction Firestore timestamp value.',
    );
  }
  return value;
}
