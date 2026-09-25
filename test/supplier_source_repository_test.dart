import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_repository.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';

const _packages = 'trips/trip-1/supplier_source_packages';
const _files = 'trips/trip-1/supplier_source_files';
final _time = Timestamp.fromDate(DateTime.utc(2026, 9, 25));

Map<String, dynamic> _package({String tripId = 'trip-1'}) => {
  'tripId': tripId,
  'supplierId': 'supplier-1',
  'supplierNameSnapshot': 'Example DMC',
  'fileIds': <String>[],
  'uploadedByUid': 'agent-1',
  'status': 'uploading',
  'createdAt': _time,
  'updatedAt': _time,
};

Map<String, dynamic> _file({
  String tripId = 'trip-1',
  String packageId = 'package-1',
  String fileId = 'file-1',
}) => {
  'tripId': tripId,
  'packageId': packageId,
  'originalFileName': 'Supplier quote.pdf',
  'storagePath': 'trips/$tripId/supplier_sources/$fileId/quote.pdf',
  'contentType': 'application/pdf',
  'sizeBytes': 1024,
  'uploadedByUid': 'agent-1',
  'createdAt': _time,
};

void main() {
  late _FakeFirestore firestore;
  late FirestoreSupplierSourceRepository repository;
  setUp(() {
    firestore = _FakeFirestore();
    repository = FirestoreSupplierSourceRepository(firestore: firestore);
  });

  Future<String> createFile({
    String tripId = 'trip-1',
    String packageId = 'package-1',
    String currentUserUid = 'signed-in-agent',
    String originalFileName = 'Supplier quote.pdf',
    String storageFileName = 'quote.pdf',
    String contentType = 'application/pdf',
    int sizeBytes = 1024,
  }) => repository.createFileMetadata(
    tripId: tripId,
    packageId: packageId,
    currentUserUid: currentUserUid,
    originalFileName: originalFileName,
    storageFileName: storageFileName,
    contentType: contentType,
    sizeBytes: sizeBytes,
  );

  test(
    'creates uploading package with generated ID and server audit timestamps',
    () async {
      final id = await repository.createPackage(
        tripId: 'trip-1',
        currentUserUid: 'signed-in-agent',
      );
      expect(id, 'generated-1');
      expect(firestore.requestedIds, [null]);
      expect(firestore.sets.single.path, '$_packages/$id');
      expect(firestore.sets.single.data, {
        'tripId': 'trip-1',
        'supplierId': null,
        'supplierNameSnapshot': null,
        'fileIds': <String>[],
        'uploadedByUid': 'signed-in-agent',
        'status': 'uploading',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      expect(firestore.readOptions, isEmpty);
    },
  );
  test(
    'stores known Supplier snapshot without creating or querying Supplier',
    () async {
      final id = await repository.createPackage(
        tripId: 'trip-1',
        currentUserUid: 'agent-1',
        supplierId: 'supplier-1',
        supplierNameSnapshot: 'Example DMC',
      );
      expect(
        firestore.documents['$_packages/$id']!['supplierId'],
        'supplier-1',
      );
      expect(
        firestore.documents['$_packages/$id']!['supplierNameSnapshot'],
        'Example DMC',
      );
      expect(firestore.collections, [_packages]);
      expect(firestore.documents, hasLength(1));
      expect(firestore.readOptions, isEmpty);
    },
  );
  test(
    'file uses generated ID, deterministic Storage path and server creation time',
    () async {
      final id = await createFile();
      expect(id, 'generated-1');
      expect(firestore.sets.single.path, '$_files/$id');
      expect(firestore.sets.single.data, {
        ..._file(fileId: id),
        'uploadedByUid': 'signed-in-agent',
        'createdAt': FieldValue.serverTimestamp(),
      });
      expect(firestore.requestedIds, [null]);
      expect(firestore.collections, [_files]);
      expect(firestore.readOptions, isEmpty);
    },
  );
  test(
    'identical filenames receive distinct generated IDs and paths',
    () async {
      final first = await createFile();
      final second = await createFile();
      expect(first, isNot(second));
      expect(firestore.requestedIds, [null, null]);
      expect(
        firestore.documents['$_files/$first']!['storagePath'],
        isNot(firestore.documents['$_files/$second']!['storagePath']),
      );
    },
  );
  for (final status in [
    SupplierSourcePackageStatus.uploaded,
    SupplierSourcePackageStatus.failed,
  ]) {
    test(
      '$status update preserves Supplier, Trip and creation metadata',
      () async {
        final original = _package();
        firestore.documents['$_packages/package-1'] = Map.of(original);
        await repository.updatePackageAfterUpload(
          tripId: 'trip-1',
          packageId: 'package-1',
          fileIds: ['file-3', 'file-1', 'file-2'],
          status: status,
        );
        expect(firestore.updates.single.path, '$_packages/package-1');
        expect(firestore.updates.single.data, {
          'fileIds': ['file-3', 'file-1', 'file-2'],
          'status': status.value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final updated = firestore.documents['$_packages/package-1']!;
        for (final field in [
          'tripId',
          'supplierId',
          'supplierNameSnapshot',
          'uploadedByUid',
          'createdAt',
        ]) {
          expect(updated[field], original[field]);
        }
        expect(firestore.sets, isEmpty);
      },
    );
  }
  test('failed package may contain no files', () async {
    firestore.documents['$_packages/package-1'] = _package();
    await repository.updatePackageAfterUpload(
      tripId: 'trip-1',
      packageId: 'package-1',
      fileIds: [],
      status: SupplierSourcePackageStatus.failed,
    );
    expect(firestore.updates.single.data['status'], 'failed');
    expect(firestore.updates.single.data['fileIds'], isEmpty);
  });
  test('completion does not upsert a missing package', () async {
    await expectLater(
      repository.updatePackageAfterUpload(
        tripId: 'trip-1',
        packageId: 'missing',
        fileIds: ['file-1'],
        status: SupplierSourcePackageStatus.uploaded,
      ),
      throwsStateError,
    );
    expect(firestore.documents, isEmpty);
    expect(firestore.sets, isEmpty);
  });
  test(
    'get uses snapshot ID, converts timestamps and returns null for missing records',
    () async {
      firestore.documents['$_packages/package-1'] = _package();
      firestore.documents['$_files/file-1'] = _file();
      final package = (await repository.getPackage('trip-1', 'package-1'))!;
      final file = (await repository.getFile('trip-1', 'file-1'))!;
      expect(package.id, 'package-1');
      expect(package.createdAt, _time.toDate().toUtc());
      expect(package.updatedAt, _time.toDate().toUtc());
      expect(file.id, 'file-1');
      expect(file.createdAt, _time.toDate().toUtc());
      expect(package.uploadedByUid, 'agent-1');
      expect(file.uploadedByUid, 'agent-1');
      expect(await repository.getPackage('trip-1', 'missing'), isNull);
      expect(await repository.getFile('trip-1', 'missing'), isNull);
      expect(
        firestore.readOptions.every(
          (option) => option?.source == Source.server,
        ),
        isTrue,
      );
    },
  );
  test(
    'lists scope by Trip path and package filter without collection-group reads',
    () async {
      expect(await repository.listPackagesForTrip('trip-1'), isEmpty);
      expect(
        await repository.listFilesForPackage('trip-1', 'package-1'),
        isEmpty,
      );
      firestore.documents.addAll({
        '$_packages/package-1': _package(),
        '$_packages/package-2': _package(),
        'trips/trip-2/supplier_source_packages/package-3': _package(
          tripId: 'trip-2',
        ),
        '$_files/file-1': _file(),
        '$_files/file-2': _file(fileId: 'file-2'),
        '$_files/file-3': _file(fileId: 'file-3', packageId: 'package-2'),
        'trips/trip-2/supplier_source_files/file-4': _file(
          tripId: 'trip-2',
          fileId: 'file-4',
        ),
      });
      final packages = await repository.listPackagesForTrip('trip-1');
      final files = await repository.listFilesForPackage('trip-1', 'package-1');
      expect(packages.map((item) => item.id), ['package-1', 'package-2']);
      expect(files.map((item) => item.id), ['file-1', 'file-2']);
      expect(() => packages.clear(), throwsUnsupportedError);
      expect(() => files.clear(), throwsUnsupportedError);
      expect(firestore.collections, [_packages, _files, _packages, _files]);
      expect(
        firestore.filters,
        everyElement((field: 'packageId', equals: 'package-1')),
      );
      expect(
        firestore.readOptions.every(
          (option) => option?.source == Source.server,
        ),
        isTrue,
      );
    },
  );
  test('file metadata exposes no normal update, replace or delete API', () {
    final dynamic dynamicRepository = repository;
    expect(() => dynamicRepository.updateSourceFile(), throwsNoSuchMethodError);
    expect(() => dynamicRepository.deleteSourceFile(), throwsNoSuchMethodError);
    expect(
      () => dynamicRepository.replaceSourceFile(),
      throwsNoSuchMethodError,
    );
    expect(firestore.collections, isEmpty);
  });

  for (final field in ['createdAt', 'updatedAt']) {
    test('rejects malformed Firestore $field on get and list', () async {
      for (final value in [null, '2026-09-25', DateTime.utc(2026), 123]) {
        firestore.documents['$_packages/package-1'] = {
          ..._package(),
          field: value,
        };
        await expectLater(
          repository.getPackage('trip-1', 'package-1'),
          throwsFormatException,
        );
        await expectLater(
          repository.listPackagesForTrip('trip-1'),
          throwsFormatException,
        );
        if (field == 'createdAt') {
          firestore.documents['$_files/file-1'] = {..._file(), field: value};
          await expectLater(
            repository.getFile('trip-1', 'file-1'),
            throwsFormatException,
          );
          await expectLater(
            repository.listFilesForPackage('trip-1', 'package-1'),
            throwsFormatException,
          );
        }
      }
    });
  }
  test(
    'malformed or cross-Trip documents fail reads without being skipped',
    () async {
      for (final data in [
        for (final field in _package().keys) _package()..remove(field),
        {..._package(), 'tripId': 'other'},
        {..._package(), 'status': 'extracting'},
      ]) {
        firestore.documents['$_packages/package-1'] = data;
        await expectLater(
          repository.getPackage('trip-1', 'package-1'),
          throwsFormatException,
        );
        await expectLater(
          repository.listPackagesForTrip('trip-1'),
          throwsFormatException,
        );
      }
      for (final data in [
        for (final field in _file().keys) _file()..remove(field),
        _file(tripId: 'other'),
        _file(fileId: 'other'),
        {..._file(), 'sizeBytes': -1},
        {..._file(), 'contentType': 'invalid'},
      ]) {
        firestore.documents['$_files/file-1'] = data;
        await expectLater(
          repository.getFile('trip-1', 'file-1'),
          throwsFormatException,
        );
        // A missing packageId cannot match the filter; get still rejects it.
        if (data.containsKey('packageId')) {
          await expectLater(
            repository.listFilesForPackage('trip-1', 'package-1'),
            throwsFormatException,
          );
        }
      }
    },
  );
  for (final id in ['', ' ', 'a/b', '.', '..', ' a']) {
    test('rejects invalid IDs before Firestore access: $id', () async {
      final calls = <Future<Object?> Function()>[
        () => repository.createPackage(tripId: id, currentUserUid: 'agent'),
        () => repository.createPackage(tripId: 'trip-1', currentUserUid: id),
        () => createFile(tripId: id),
        () => createFile(packageId: id),
        () => createFile(currentUserUid: id),
        () => createFile(storageFileName: id),
        () => repository.getPackage(id, 'package-1'),
        () => repository.getPackage('trip-1', id),
        () => repository.getFile(id, 'file-1'),
        () => repository.getFile('trip-1', id),
        () => repository.listPackagesForTrip(id),
        () => repository.listFilesForPackage(id, 'package-1'),
        () => repository.listFilesForPackage('trip-1', id),
        () => repository.updatePackageAfterUpload(
          tripId: id,
          packageId: 'package-1',
          fileIds: ['file-1'],
          status: SupplierSourcePackageStatus.uploaded,
        ),
        () => repository.updatePackageAfterUpload(
          tripId: 'trip-1',
          packageId: id,
          fileIds: ['file-1'],
          status: SupplierSourcePackageStatus.uploaded,
        ),
      ];
      for (final call in calls) {
        await expectLater(call(), throwsFormatException);
      }
      expect(firestore.collections, isEmpty);
    });
  }
  test(
    'invalid metadata, linkage and completion cause no Firestore access',
    () async {
      for (final call in <Future<Object?> Function()>[
        () => createFile(originalFileName: ' '),
        () => createFile(contentType: 'application/zip'),
        () => createFile(sizeBytes: 0),
        () => createFile(sizeBytes: -1),
        () => createFile(sizeBytes: 26214401),
        () => repository.createPackage(
          tripId: 'trip-1',
          currentUserUid: 'agent',
          supplierId: 'supplier-1',
        ),
        () => repository.createPackage(
          tripId: 'trip-1',
          currentUserUid: 'agent',
          supplierNameSnapshot: 'DMC',
        ),
        for (final ids in <List<String>>[
          [],
          ['same', 'same'],
          [''],
        ])
          () => repository.updatePackageAfterUpload(
            tripId: 'trip-1',
            packageId: 'package-1',
            fileIds: ids,
            status: SupplierSourcePackageStatus.uploaded,
          ),
        () => repository.updatePackageAfterUpload(
          tripId: 'trip-1',
          packageId: 'package-1',
          fileIds: [],
          status: SupplierSourcePackageStatus.uploading,
        ),
      ]) {
        await expectLater(call(), throwsFormatException);
      }
      expect(firestore.collections, isEmpty);
    },
  );
  test('permission errors propagate without fallback or retries', () async {
    final denied = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    firestore.error = denied;
    for (final call in <Future<Object?> Function()>[
      () => repository.createPackage(tripId: 'trip-1', currentUserUid: 'agent'),
      () => createFile(),
      () => repository.getPackage('trip-1', 'package-1'),
      () => repository.getFile('trip-1', 'file-1'),
      () => repository.listPackagesForTrip('trip-1'),
      () => repository.listFilesForPackage('trip-1', 'package-1'),
      () => repository.updatePackageAfterUpload(
        tripId: 'trip-1',
        packageId: 'package-1',
        fileIds: ['file-1'],
        status: SupplierSourcePackageStatus.uploaded,
      ),
    ]) {
      await expectLater(call(), throwsA(same(denied)));
    }
    expect(firestore.sets, isEmpty);
    expect(firestore.updates, isEmpty);
  });
  testWidgets('bounds all stalled reads', (tester) async {
    final pending = Completer<void>();
    firestore.readWait = pending.future;
    final reads = [
      repository.getPackage('trip-1', 'package-1'),
      repository.getFile('trip-1', 'file-1'),
      repository.listPackagesForTrip('trip-1'),
      repository.listFilesForPackage('trip-1', 'package-1'),
    ];
    final assertions = reads
        .map((read) => expectLater(read, throwsA(isA<TimeoutException>())))
        .toList();
    await tester.pump(const Duration(seconds: 30));
    await Future.wait(assertions);
    pending.complete();
    await tester.pump();
  });
}

class _FakeFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final collections = <String>[];
  final requestedIds = <String?>[];
  final sets = <({String path, Map<String, dynamic> data})>[];
  final updates = <({String path, Map<String, dynamic> data})>[];
  final readOptions = <GetOptions?>[];
  final filters = <({Object field, Object? equals})>[];
  Object? error;
  Future<void>? readWait;
  int _nextId = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    collections.add(path);
    return _Collection(this, path);
  }

  Future<void> beforeRead(GetOptions? options) async {
    readOptions.add(options);
    if (error != null) throw error!;
    await readWait;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> query(
    String path,
    GetOptions? options, {
    Object? field,
    Object? equals,
  }) async {
    await beforeRead(options);
    return _QuerySnapshot(
      documents.entries
          .where(
            (entry) =>
                entry.key.startsWith('$path/') &&
                !entry.key.substring(path.length + 1).contains('/') &&
                (field == null || entry.value[field] == equals),
          )
          .map(
            (entry) => _QueryDocument(entry.key.split('/').last, entry.value),
          )
          .toList(),
    );
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
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    firestore.requestedIds.add(path);
    return _Reference(
      firestore,
      '${this.path}/${path ?? 'generated-${++firestore._nextId}'}',
    );
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      firestore.query(path, options);

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    firestore.filters.add((field: field, equals: isEqualTo));
    return _FilteredQuery(firestore, path, field, isEqualTo);
  }
}

// ignore: subtype_of_sealed_class
class _FilteredQuery extends Fake implements Query<Map<String, dynamic>> {
  _FilteredQuery(this.firestore, this.path, this.field, this.equals);
  @override
  final _FakeFirestore firestore;
  final String path;
  final Object field;
  final Object? equals;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      firestore.query(path, options, field: field, equals: equals);
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
    if (firestore.error != null) throw firestore.error!;
    firestore.sets.add((path: path, data: Map.of(data)));
    firestore.documents[path] = Map.of(data);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    if (firestore.error != null) throw firestore.error!;
    if (!firestore.documents.containsKey(path)) {
      throw StateError('Missing document');
    }
    firestore.updates.add((path: path, data: Map<String, dynamic>.from(data)));
    firestore.documents[path]!.addAll(Map<String, dynamic>.from(data));
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    await firestore.beforeRead(options);
    return _Snapshot(id, firestore.documents[path]);
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
