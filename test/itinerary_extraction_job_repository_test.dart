import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_extraction_job_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_repository.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';

const _jobs = 'trips/trip-1/itinerary_extraction_jobs';
final _createdAt = DateTime.utc(2026, 9, 27, 8);
final _updatedAt = DateTime.utc(2026, 9, 27, 9);

SupplierSourcePackage _package({
  String id = 'package-1',
  String tripId = 'trip-1',
  SupplierSourcePackageStatus status = SupplierSourcePackageStatus.uploaded,
}) => SupplierSourcePackage(
  id: id,
  tripId: tripId,
  fileIds: status == SupplierSourcePackageStatus.uploaded
      ? ['file-1']
      : const [],
  uploadedByUid: 'agent-1',
  createdAt: _createdAt,
  updatedAt: _updatedAt,
  status: status,
);

Map<String, dynamic> _record({
  String tripId = 'trip-1',
  String packageId = 'package-1',
  KayraItineraryExtractionStatus status = KayraItineraryExtractionStatus.queued,
  bool versioned = false,
  KayraItineraryExtractionContractVersion contractVersion =
      KayraItineraryExtractionContractVersion.itineraryDraftV1,
  KayraItineraryExtractionResultType resultType =
      KayraItineraryExtractionResultType.itineraryDraft,
  String? resultingDraftId,
  String? resultingExtractionId,
  KayraItineraryExtractionFailureCode? failureCode,
  DateTime? createdAt,
}) => {
  'tripId': tripId,
  'sourcePackageId': packageId,
  'status': status.value,
  'requestedByUid': 'agent-1',
  if (versioned) 'extractionContractVersion': contractVersion.value,
  if (versioned) 'resultType': resultType.value,
  'resultingDraftId': resultingDraftId,
  if (versioned) 'resultingExtractionId': resultingExtractionId,
  'failureCode': failureCode?.value,
  'createdAt': Timestamp.fromDate(createdAt ?? _createdAt),
  'updatedAt': Timestamp.fromDate(_updatedAt),
};

void main() {
  late _FakeFirestore firestore;
  late _Sources sources;
  late FirestoreItineraryExtractionJobRepository repository;

  setUp(() {
    firestore = _FakeFirestore();
    sources = _Sources()..packages['package-1'] = _package();
    repository = FirestoreItineraryExtractionJobRepository(
      firestore: firestore,
      sourceRepository: sources,
    );
    addTearDown(firestore.dispose);
  });

  test(
    'uploaded package allows queued job creation with allocated ID',
    () async {
      final id = await repository.createQueuedJob(
        tripId: 'trip-1',
        sourcePackageId: 'package-1',
        currentUserUid: 'agent-1',
      );

      expect(id, 'generated-1');
      expect(sources.reads, [(tripId: 'trip-1', packageId: 'package-1')]);
      expect(firestore.sets.single.path, '$_jobs/generated-1');
      expect(firestore.sets.single.data, {
        'tripId': 'trip-1',
        'sourcePackageId': 'package-1',
        'status': 'queued',
        'requestedByUid': 'agent-1',
        'resultingDraftId': null,
        'failureCode': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    },
  );

  for (final status in [
    SupplierSourcePackageStatus.uploading,
    SupplierSourcePackageStatus.failed,
  ]) {
    test('${status.value} package is rejected', () async {
      sources.packages['package-1'] = _package(status: status);
      await expectLater(
        repository.createQueuedJob(
          tripId: 'trip-1',
          sourcePackageId: 'package-1',
          currentUserUid: 'agent-1',
        ),
        throwsFormatException,
      );
      expect(firestore.sets, isEmpty);
    });
  }

  test('missing and cross-Trip packages are rejected', () async {
    sources.packages.clear();
    await expectLater(
      repository.createQueuedJob(
        tripId: 'trip-1',
        sourcePackageId: 'package-1',
        currentUserUid: 'agent-1',
      ),
      throwsFormatException,
    );
    sources.packages['package-1'] = _package(tripId: 'trip-2');
    await expectLater(
      repository.createQueuedJob(
        tripId: 'trip-1',
        sourcePackageId: 'package-1',
        currentUserUid: 'agent-1',
      ),
      throwsFormatException,
    );
    expect(firestore.sets, isEmpty);
  });

  test('get round trips and list is newest first within one Trip', () async {
    firestore.documents.addAll({
      '$_jobs/older': _record(createdAt: DateTime.utc(2026, 9, 20)),
      '$_jobs/newer': _record(createdAt: DateTime.utc(2026, 9, 28)),
      'trips/trip-2/itinerary_extraction_jobs/other': _record(tripId: 'trip-2'),
    });

    final job = await repository.getJob('trip-1', 'older');
    expect(job!.id, 'older');
    expect(job.status, KayraItineraryExtractionStatus.queued);
    final jobs = await repository.listJobsForTrip('trip-1');
    expect(jobs.map((job) => job.id), ['newer', 'older']);
    expect(firestore.orders.single, (field: 'createdAt', descending: true));
    expect(() => jobs.clear(), throwsUnsupportedError);
  });

  test(
    'observe one job deserializes live snapshots with the domain model',
    () async {
      final values = repository
          .observeJob('trip-1', 'job-live')
          .take(2)
          .toList();
      firestore.emit(
        '$_jobs/job-live',
        _record(status: KayraItineraryExtractionStatus.processing),
      );
      firestore.emit('$_jobs/job-live', null);

      final observed = await values;
      expect(observed.first, isA<KayraItineraryExtractionJob>());
      expect(observed.first!.id, 'job-live');
      expect(observed.first!.status, KayraItineraryExtractionStatus.processing);
      expect(observed.last, isNull);
      expect(firestore.sets, isEmpty);
      expect(firestore.transactionUpdates, isEmpty);
    },
  );

  test(
    'repository deserializes a completed supplier extraction result',
    () async {
      firestore.documents['$_jobs/v3-completed'] = _record(
        versioned: true,
        contractVersion:
            KayraItineraryExtractionContractVersion.supplierExtractionV1,
        resultType: KayraItineraryExtractionResultType.supplierExtraction,
        status: KayraItineraryExtractionStatus.completed,
        resultingExtractionId: 'extraction-1',
      );

      final job = await repository.getJob('trip-1', 'v3-completed');
      expect(
        job!.resultType,
        KayraItineraryExtractionResultType.supplierExtraction,
      );
      expect(job.resultingExtractionId, 'extraction-1');
      expect(job.resultingDraftId, isNull);
    },
  );

  test('queued to processing succeeds transactionally', () async {
    firestore.documents['$_jobs/job-1'] = _record();
    await repository.markProcessing(tripId: 'trip-1', jobId: 'job-1');
    expect(firestore.transactionRuns, 1);
    expect(firestore.documents['$_jobs/job-1']!['status'], 'processing');
    expect(firestore.transactionUpdates.single.data.keys, {
      'status',
      'resultingDraftId',
      'failureCode',
      'updatedAt',
    });
  });

  test('processing to completed stores resulting draft ID', () async {
    firestore.documents['$_jobs/job-1'] = _record(
      status: KayraItineraryExtractionStatus.processing,
    );
    await repository.markCompleted(
      tripId: 'trip-1',
      jobId: 'job-1',
      resultingDraftId: 'draft-1',
    );
    final data = firestore.documents['$_jobs/job-1']!;
    expect(data['status'], 'completed');
    expect(data['resultingDraftId'], 'draft-1');
    expect(data['failureCode'], isNull);
  });

  test('processing to failed stores stable failure code', () async {
    firestore.documents['$_jobs/job-1'] = _record(
      status: KayraItineraryExtractionStatus.processing,
    );
    await repository.markFailed(
      tripId: 'trip-1',
      jobId: 'job-1',
      failureCode: KayraItineraryExtractionFailureCode.invalidExtractionResult,
    );
    final data = firestore.documents['$_jobs/job-1']!;
    expect(data['status'], 'failed');
    expect(data['resultingDraftId'], isNull);
    expect(data['failureCode'], 'invalid_extraction_result');
  });

  test('queued cannot jump directly to completed or failed', () async {
    firestore.documents['$_jobs/job-1'] = _record();
    await expectLater(
      repository.markCompleted(
        tripId: 'trip-1',
        jobId: 'job-1',
        resultingDraftId: 'draft-1',
      ),
      throwsStateError,
    );
    await expectLater(
      repository.markFailed(
        tripId: 'trip-1',
        jobId: 'job-1',
        failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
      ),
      throwsStateError,
    );
    expect(firestore.transactionUpdates, isEmpty);
  });

  test('completed and failed jobs are terminal', () async {
    firestore.documents['$_jobs/completed'] = _record(
      status: KayraItineraryExtractionStatus.completed,
      resultingDraftId: 'draft-1',
    );
    firestore.documents['$_jobs/failed'] = _record(
      status: KayraItineraryExtractionStatus.failed,
      failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
    );
    for (final id in ['completed', 'failed']) {
      await expectLater(
        repository.markProcessing(tripId: 'trip-1', jobId: id),
        throwsStateError,
      );
    }
    expect(firestore.transactionUpdates, isEmpty);
  });

  test('processing cannot return to queued and no unrestricted APIs exist', () {
    final dynamic dynamicRepository = repository;
    expect(
      () => dynamicRepository.markQueued(tripId: 'trip-1', jobId: 'job-1'),
      throwsNoSuchMethodError,
    );
    expect(
      () => dynamicRepository.updateJob('trip-1', 'job-1', <String, Object?>{}),
      throwsNoSuchMethodError,
    );
    expect(
      () => dynamicRepository.deleteJob('trip-1', 'job-1'),
      throwsNoSuchMethodError,
    );
  });

  test('missing job is not upserted by a transition', () async {
    await expectLater(
      repository.markProcessing(tripId: 'trip-1', jobId: 'missing'),
      throwsStateError,
    );
    expect(firestore.transactionUpdates, isEmpty);
  });
}

class _Sources extends Fake implements SupplierSourceRepository {
  final packages = <String, SupplierSourcePackage>{};
  final reads = <({String tripId, String packageId})>[];

  @override
  Future<SupplierSourcePackage?> getPackage(
    String tripId,
    String packageId,
  ) async {
    reads.add((tripId: tripId, packageId: packageId));
    return packages[packageId];
  }
}

class _FakeFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final sets = <({String path, Map<String, dynamic> data})>[];
  final transactionUpdates = <({String path, Map<String, dynamic> data})>[];
  final orders = <({Object field, bool descending})>[];
  int transactionRuns = 0;
  int _nextId = 0;
  final streams =
      <String, StreamController<DocumentSnapshot<Map<String, dynamic>>>>{};

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactionRuns++;
    return transactionHandler(_Transaction(this));
  }

  List<MapEntry<String, Map<String, dynamic>>> children(String path) =>
      documents.entries
          .where(
            (entry) =>
                entry.key.startsWith('$path/') &&
                !entry.key.substring(path.length + 1).contains('/'),
          )
          .toList();

  void emit(String path, Map<String, dynamic>? data) {
    streams
        .putIfAbsent(path, StreamController.broadcast)
        .add(_Snapshot(path.split('/').last, data));
  }

  Future<void> dispose() async {
    await Future.wait(streams.values.map((stream) => stream.close()));
  }
}

// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.firestore, this.path);
  @override
  final _FakeFirestore firestore;
  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _Reference(
    firestore,
    '${this.path}/${path ?? 'generated-${++firestore._nextId}'}',
  );

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    firestore.orders.add((field: field, descending: descending));
    return _OrderedQuery(firestore, path, field, descending);
  }
}

// ignore: subtype_of_sealed_class
class _OrderedQuery extends Fake implements Query<Map<String, dynamic>> {
  _OrderedQuery(this.firestore, this.path, this.field, this.descending);
  @override
  final _FakeFirestore firestore;
  final String path;
  final Object field;
  final bool descending;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final entries = firestore.children(path);
    entries.sort((left, right) {
      final comparison = (left.value[field] as Timestamp).compareTo(
        right.value[field] as Timestamp,
      );
      return descending ? -comparison : comparison;
    });
    return _QuerySnapshot(
      entries
          .map(
            (entry) => _QueryDocument(entry.key.split('/').last, entry.value),
          )
          .toList(),
    );
  }
}

// ignore: subtype_of_sealed_class
class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.firestore, this.path);
  @override
  final _FakeFirestore firestore;
  @override
  final String path;
  @override
  String get id => path.split('/').last;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    firestore.sets.add((path: path, data: Map.of(data)));
    firestore.documents[path] = Map.of(data);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot(id, firestore.documents[path]);

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => firestore.streams.putIfAbsent(path, StreamController.broadcast).stream;
}

// ignore: subtype_of_sealed_class
class _Transaction extends Fake implements Transaction {
  _Transaction(this.firestore);
  final _FakeFirestore firestore;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async =>
      _Snapshot(
            documentReference.id,
            firestore.documents[documentReference.path],
          )
          as DocumentSnapshot<T>;

  @override
  Transaction update(
    DocumentReference<Object?> documentReference,
    Map<Object, Object?> data,
  ) {
    final existing = firestore.documents[documentReference.path];
    if (existing == null) throw StateError('Missing document');
    final converted = Map<String, dynamic>.from(data);
    firestore.transactionUpdates.add((
      path: documentReference.path,
      data: converted,
    ));
    existing.addAll(converted);
    return this;
  }
}

// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic>? _data;
  @override
  bool get exists => _data != null;
  @override
  Map<String, dynamic>? data() => _data == null ? null : Map.of(_data);
}

// ignore: subtype_of_sealed_class
class _QueryDocument extends _Snapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(super.id, super.data);
  @override
  Map<String, dynamic> data() => super.data()!;
}

// ignore: subtype_of_sealed_class
class _QuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}
