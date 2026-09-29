import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_extraction_repository.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_repository.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';

import 'support/supplier_extraction_fixture.dart';

const _rootCollection = 'trips/trip-1/supplier_extractions';
const _rootPath = '$_rootCollection/extraction-1';

void main() {
  late _FakeFirestore firestore;
  late _Sources sources;
  late FirestoreSupplierExtractionRepository repository;

  setUp(() {
    firestore = _FakeFirestore();
    sources = _Sources()..packages['package-1'] = _uploadedPackage();
    repository = FirestoreSupplierExtractionRepository(
      firestore: firestore,
      sourceRepository: sources,
    );
  });

  test('reads one complete Snapshot from the exact hierarchy', () async {
    _storeCompleteFixture(firestore);

    final snapshot = await repository.getCompleteSnapshot(
      tripId: 'trip-1',
      extractionId: 'extraction-1',
    );

    expect(snapshot.extractionId, 'extraction-1');
    expect(snapshot.days.map((day) => day.id), [
      'staged-day-1',
      'staged-day-2',
    ]);
    expect(snapshot.facts.first.id, 'staged-service-1');
    expect(snapshot.reviewIssues.length, 6);
    expect(sources.reads, [(tripId: 'trip-1', packageId: 'package-1')]);
    expect(firestore.documentReads, [_rootPath]);
    expect(firestore.queryReads, [
      '$_rootPath/days',
      '$_rootPath/facts',
      '$_rootPath/review_issues',
    ]);
    expect(firestore.orderFields, [
      'snapshotOrder',
      'snapshotOrder',
      'snapshotOrder',
    ]);
    expect(
      firestore.readOptions.every(
        (options) => options?.source == Source.server,
      ),
      isTrue,
    );
    expect(firestore.writeCount, 0);
  });

  test(
    'repository ordering is deterministic despite shuffled storage',
    () async {
      _storeCompleteFixture(firestore, reversed: true);

      final snapshot = await repository.getCompleteSnapshot(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      );

      expect(snapshot.days.map((day) => day.snapshotOrder), [1, 2]);
      expect(
        snapshot.facts.map((fact) => fact.snapshotOrder),
        List<int>.generate(10, (index) => index + 1),
      );
      expect(
        snapshot.reviewIssues.map((issue) => issue.snapshotOrder),
        List<int>.generate(6, (index) => index + 1),
      );
    },
  );

  test('missing root is distinct and stops before dependent reads', () async {
    await expectLater(
      repository.getCompleteSnapshot(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      ),
      throwsA(
        isA<SupplierExtractionRepositoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          SupplierExtractionRepositoryFailureKind.notFound,
        ),
      ),
    );

    expect(sources.reads, isEmpty);
    expect(firestore.queryReads, isEmpty);
  });

  test('writing root is unavailable and children are never exposed', () async {
    firestore.documents[_rootPath] = _toFirestoreMap(
      supplierExtractionRoot(persistenceState: 'writing'),
    );

    await expectLater(
      repository.getCompleteSnapshot(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      ),
      throwsA(
        isA<SupplierExtractionRepositoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          SupplierExtractionRepositoryFailureKind.unavailable,
        ),
      ),
    );

    expect(sources.reads, isEmpty);
    expect(firestore.queryReads, isEmpty);
  });

  test('missing or non-uploaded trusted package is malformed', () async {
    firestore.documents[_rootPath] = _toFirestoreMap(supplierExtractionRoot());
    sources.packages.clear();

    await expectLater(
      repository.getCompleteSnapshot(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      ),
      _throwsKind(SupplierExtractionRepositoryFailureKind.malformed),
    );

    sources.packages['package-1'] = _uploadedPackage(
      status: SupplierSourcePackageStatus.failed,
    );
    await expectLater(
      repository.getCompleteSnapshot(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      ),
      _throwsKind(SupplierExtractionRepositoryFailureKind.malformed),
    );
    expect(firestore.queryReads, isEmpty);
  });

  test(
    'malformed stored Snapshot is reported without leaking details',
    () async {
      _storeCompleteFixture(firestore);
      firestore.documents['$_rootPath/days/staged-day-1']!['unexpected'] = true;

      await expectLater(
        repository.getCompleteSnapshot(
          tripId: 'trip-1',
          extractionId: 'extraction-1',
        ),
        throwsA(
          isA<SupplierExtractionRepositoryFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                SupplierExtractionRepositoryFailureKind.malformed,
              )
              .having(
                (failure) => failure.userMessage,
                'userMessage',
                'The stored Supplier Extraction Snapshot is invalid.',
              ),
        ),
      );
    },
  );

  test('permission denial is reported as unavailable', () async {
    firestore.readError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'private backend detail',
    );

    await expectLater(
      repository.getCompleteSnapshot(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      ),
      throwsA(
        isA<SupplierExtractionRepositoryFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              SupplierExtractionRepositoryFailureKind.unavailable,
            )
            .having(
              (failure) => failure.userMessage,
              'userMessage',
              'The Supplier Extraction Snapshot is unavailable.',
            ),
      ),
    );
  });

  test('other read failures use a stable sanitized failure', () async {
    firestore.readError = StateError('private backend detail');

    await expectLater(
      repository.getCompleteSnapshot(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      ),
      throwsA(
        isA<SupplierExtractionRepositoryFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              SupplierExtractionRepositoryFailureKind.readFailed,
            )
            .having(
              (failure) => failure.userMessage,
              'userMessage',
              'The Supplier Extraction Snapshot could not be loaded.',
            ),
      ),
    );
  });

  test('public repository contract exposes no mutation operations', () {
    final dynamic readOnly = repository;

    expect(() => readOnly.create(), throwsNoSuchMethodError);
    expect(() => readOnly.update(), throwsNoSuchMethodError);
    expect(() => readOnly.delete(), throwsNoSuchMethodError);
    expect(firestore.writeCount, 0);
  });
}

Matcher _throwsKind(SupplierExtractionRepositoryFailureKind kind) => throwsA(
  isA<SupplierExtractionRepositoryFailure>().having(
    (failure) => failure.kind,
    'kind',
    kind,
  ),
);

SupplierSourcePackage _uploadedPackage({
  SupplierSourcePackageStatus status = SupplierSourcePackageStatus.uploaded,
}) => SupplierSourcePackage(
  id: 'package-1',
  tripId: 'trip-1',
  fileIds: status == SupplierSourcePackageStatus.uploaded
      ? const ['file-1']
      : const [],
  uploadedByUid: 'agent-1',
  createdAt: supplierExtractionCreatedAt,
  updatedAt: supplierExtractionCreatedAt,
  status: status,
);

void _storeCompleteFixture(_FakeFirestore firestore, {bool reversed = false}) {
  firestore.documents[_rootPath] = _toFirestoreMap(
    supplierExtractionRoot(createdAt: supplierExtractionCreatedAt),
  );
  final childGroups = {
    'days': supplierExtractionDayDocuments(),
    'facts': supplierExtractionFactDocuments(),
    'review_issues': supplierExtractionReviewIssueDocuments(),
  };
  for (final entry in childGroups.entries) {
    final documents = reversed ? entry.value.reversed : entry.value;
    for (final document in documents) {
      firestore.documents['$_rootPath/${entry.key}/${document.documentId}'] =
          _toFirestoreMap(document.data);
    }
  }
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
  final documentReads = <String>[];
  final queryReads = <String>[];
  final readOptions = <GetOptions?>[];
  final orderFields = <Object>[];
  Object? readError;
  int writeCount = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  void beforeRead(String path, GetOptions? options, {required bool query}) {
    (query ? queryReads : documentReads).add(path);
    readOptions.add(options);
    if (readError != null) throw readError!;
  }

  List<MapEntry<String, Map<String, dynamic>>> children(String path) =>
      documents.entries
          .where(
            (entry) =>
                entry.key.startsWith('$path/') &&
                !entry.key.substring(path.length + 1).contains('/'),
          )
          .toList();
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
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Reference(firestore, '${this.path}/$path');

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    firestore.orderFields.add(field);
    return _OrderedQuery(firestore, path, field, descending);
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
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(firestore, '${this.path}/$path');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    firestore.beforeRead(path, options, query: false);
    return _Snapshot(id, firestore.documents[path]);
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
    firestore.beforeRead(path, options, query: true);
    final entries = firestore.children(path);
    entries.sort((left, right) {
      final leftValue = left.value[field] as int;
      final rightValue = right.value[field] as int;
      final comparison = leftValue.compareTo(rightValue);
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

Map<String, dynamic> _toFirestoreMap(Map<String, Object?> data) =>
    data.map((key, value) => MapEntry(key, _toFirestoreValue(value)));

Object? _toFirestoreValue(Object? value) {
  if (value is DateTime) return Timestamp.fromDate(value.toUtc());
  if (value is List) return value.map(_toFirestoreValue).toList();
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key as String, _toFirestoreValue(nested)),
    );
  }
  return value;
}
