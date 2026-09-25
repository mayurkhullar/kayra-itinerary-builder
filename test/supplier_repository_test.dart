import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/suppliers/data/supplier_repository.dart';
import 'package:kayra_crm_v1/features/suppliers/domain/kayra_supplier.dart';

SupplierDetails _details() => SupplierDetails(
  name: ' Example DMC ',
  contacts: [SupplierContact(name: ' Jane ', email: ' SALES@EXAMPLE.COM ')],
  destinationCoverage: [' Dubai ', 'dubai', 'Thailand'],
  serviceCategories: [
    SupplierServiceCategory.dmc,
    SupplierServiceCategory.hotels,
  ],
);

Map<String, dynamic> _record() => {
  ..._details().toMap(),
  'status': 'inactive',
  'createdByUid': 'agent-1',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 25)),
};

void main() {
  late _FakeFirestore firestore;
  late FirestoreSupplierRepository repository;
  setUp(() {
    firestore = _FakeFirestore();
    repository = FirestoreSupplierRepository(firestore: firestore);
  });

  test(
    'create auto-generates ID with normalized profile, active status and server audit times',
    () async {
      final id = await repository.createSupplier(
        details: _details(),
        currentUserUid: 'signed-in-agent',
      );
      expect(id, 'generated-1');
      expect(firestore.collections, ['suppliers']);
      expect(firestore.requestedIds, [null]);
      expect(firestore.sets.single.data, {
        'name': 'Example DMC',
        'contacts': [
          {
            'name': 'Jane',
            'phone': null,
            'email': 'sales@example.com',
            'isPrimary': true,
          },
        ],
        'destinationCoverage': ['Dubai', 'Thailand'],
        'serviceCategories': ['dmc', 'hotels'],
        'status': 'active',
        'createdByUid': 'signed-in-agent',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      expect(firestore.readOptions, isEmpty);
    },
  );
  test(
    'identical suppliers receive separate generated IDs without merging',
    () async {
      final first = await repository.createSupplier(
        details: _details(),
        currentUserUid: 'agent',
      );
      final second = await repository.createSupplier(
        details: _details(),
        currentUserUid: 'agent',
      );
      expect(first, isNot(second));
      expect(firestore.requestedIds, [null, null]);
    },
  );
  test(
    'normal update preserves identity, creator, createdAt and inactive status',
    () async {
      firestore.documents['one'] = _record();
      final original = Map.of(firestore.documents['one']!);
      await repository.updateSupplier(
        supplierId: 'one',
        details: SupplierDetails(name: 'Renamed'),
      );
      expect(firestore.updates.single.data, {
        'name': 'Renamed',
        'contacts': [],
        'destinationCoverage': [],
        'serviceCategories': [],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final field in ['createdByUid', 'createdAt', 'status']) {
        expect(firestore.documents['one']![field], original[field]);
        expect(firestore.updates.single.data.containsKey(field), isFalse);
      }
      expect(firestore.documents.keys, ['one']);
      expect(firestore.requestedIds, ['one']);
      expect(firestore.sets, isEmpty);
    },
  );
  test('update does not create a missing supplier', () async {
    await expectLater(
      repository.updateSupplier(supplierId: 'missing', details: _details()),
      throwsStateError,
    );
    expect(firestore.documents, isEmpty);
    expect(firestore.sets, isEmpty);
  });
  test(
    'get converts Firestore timestamps and takes identity from snapshot',
    () async {
      firestore.documents['one'] = _record();
      final supplier = await repository.getSupplierById('one');
      expect(supplier!.id, 'one');
      expect(supplier.createdByUid, 'agent-1');
      expect(supplier.status, SupplierStatus.inactive);
      expect(supplier.createdAt, DateTime.utc(2026, 9, 1));
      expect(supplier.updatedAt, DateTime.utc(2026, 9, 25));
      expect(firestore.readOptions.single?.source, Source.server);
      expect(await repository.getSupplierById('missing'), isNull);
    },
  );
  test(
    'shared list includes all creators/statuses without owner filtering',
    () async {
      expect(await repository.listSuppliers(), isEmpty);
      firestore.documents.addAll({
        'one': _record(),
        'two': {..._record(), 'status': 'active', 'createdByUid': 'agent-2'},
      });
      final suppliers = await repository.listSuppliers();
      expect(suppliers.map((s) => s.id), ['one', 'two']);
      expect(suppliers.map((s) => s.createdByUid), ['agent-1', 'agent-2']);
      expect(() => suppliers.clear(), throwsUnsupportedError);
      expect(firestore.filters, isEmpty);
      expect(firestore.unscopedReads, 2);
      expect(
        firestore.readOptions.every((o) => o?.source == Source.server),
        isTrue,
      );
    },
  );
  test('repository exposes no delete or status-changing method', () {
    final dynamic dynamicRepository = repository;
    expect(
      () => dynamicRepository.deleteSupplier('one'),
      throwsNoSuchMethodError,
    );
    expect(
      () => dynamicRepository.updateSupplierStatus(
        'one',
        SupplierStatus.inactive,
      ),
      throwsNoSuchMethodError,
    );
    expect(firestore.collections, isEmpty);
  });
  for (final field in ['createdAt', 'updatedAt']) {
    for (final value in [null, '2026-09-25', DateTime.utc(2026), 123]) {
      test(
        'rejects non-Firestore Timestamp $field=$value on get and list',
        () async {
          firestore.documents['bad'] = {..._record(), field: value};
          await expectLater(
            repository.getSupplierById('bad'),
            throwsFormatException,
          );
          await expectLater(repository.listSuppliers(), throwsFormatException);
        },
      );
    }
  }
  test(
    'missing or malformed records fail without being skipped or defaulted',
    () async {
      final records = [
        for (final field in _record().keys) _record()..remove(field),
        for (final patch in <Map<String, Object?>>[
          {'status': 'unknown'},
          {
            'serviceCategories': ['unknown'],
          },
          {
            'contacts': [null],
          },
          {
            'contacts': [
              SupplierContact(
                name: 'Jane',
                email: 'a@example.com',
                isPrimary: true,
              ).toMap(),
              SupplierContact(
                name: 'Sam',
                phone: '1234567',
                isPrimary: true,
              ).toMap(),
            ],
          },
        ])
          {..._record(), ...patch},
      ];
      for (final record in records) {
        firestore.documents['bad'] = record;
        await expectLater(
          repository.getSupplierById('bad'),
          throwsFormatException,
        );
        await expectLater(repository.listSuppliers(), throwsFormatException);
      }
    },
  );
  for (final id in ['', ' ', ' a', 'a/b', '.', '..']) {
    test('invalid ID/creator fails before contacting Firestore: $id', () async {
      await expectLater(
        repository.createSupplier(details: _details(), currentUserUid: id),
        throwsFormatException,
      );
      await expectLater(repository.getSupplierById(id), throwsFormatException);
      await expectLater(
        repository.updateSupplier(supplierId: id, details: _details()),
        throwsFormatException,
      );
      expect(firestore.collections, isEmpty);
    });
  }
  test(
    'permission failures propagate without fallback or retry writes',
    () async {
      final denied = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      firestore.error = denied;
      await expectLater(
        repository.createSupplier(details: _details(), currentUserUid: 'agent'),
        throwsA(same(denied)),
      );
      await expectLater(
        repository.getSupplierById('one'),
        throwsA(same(denied)),
      );
      await expectLater(
        repository.updateSupplier(supplierId: 'one', details: _details()),
        throwsA(same(denied)),
      );
      await expectLater(repository.listSuppliers(), throwsA(same(denied)));
      expect(firestore.sets, isEmpty);
      expect(firestore.updates, isEmpty);
    },
  );
  for (final list in [false, true]) {
    testWidgets('bounds stalled ${list ? 'list' : 'get'} reads', (
      tester,
    ) async {
      final pending = Completer<void>();
      firestore.readWait = pending.future;
      final future = list
          ? repository.listSuppliers()
          : repository.getSupplierById('one');
      final assertion = expectLater(future, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 30));
      await assertion;
      pending.complete();
      await tester.pump();
    });
  }
}

class _FakeFirestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final collections = <String>[];
  final requestedIds = <String?>[];
  final sets = <({String id, Map<String, dynamic> data})>[];
  final updates = <({String id, Map<String, dynamic> data})>[];
  final readOptions = <GetOptions?>[];
  final filters = <({Object field, Object? equals})>[];
  int unscopedReads = 0;
  Object? error;
  Future<void>? readWait;
  int _nextId = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    collections.add(path);
    return _Collection(this);
  }

  Future<void> beforeRead(GetOptions? options) async {
    readOptions.add(options);
    if (error != null) throw error!;
    await readWait;
  }
}

// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.firestore);
  @override
  final _FakeFirestore firestore;

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
    return _OwnerQuery(firestore, field, isEqualTo);
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    firestore.requestedIds.add(path);
    return _Reference(firestore, path ?? 'generated-${++firestore._nextId}');
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    firestore.unscopedReads++;
    await firestore.beforeRead(options);
    return _QuerySnapshot(
      firestore.documents.entries
          .map((entry) => _QueryDocument(entry.key, entry.value))
          .toList(),
    );
  }
}

// This fake applies the captured Firestore query before returning documents.
// ignore: subtype_of_sealed_class
class _OwnerQuery extends Fake implements Query<Map<String, dynamic>> {
  _OwnerQuery(this.firestore, this.field, this.value);
  @override
  final _FakeFirestore firestore;
  final Object field;
  final Object? value;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    await firestore.beforeRead(options);
    return _QuerySnapshot(
      firestore.documents.entries
          .where((entry) => entry.value[field] == value)
          .map((entry) => _QueryDocument(entry.key, entry.value))
          .toList(),
    );
  }
}

// ignore: subtype_of_sealed_class
class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.firestore, this.id);
  @override
  final _FakeFirestore firestore;
  @override
  final String id;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (firestore.error != null) throw firestore.error!;
    firestore.sets.add((id: id, data: Map.of(data)));
    firestore.documents[id] = Map.of(data);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    if (firestore.error != null) throw firestore.error!;
    if (!firestore.documents.containsKey(id)) {
      throw StateError('Missing document');
    }
    firestore.updates.add((id: id, data: Map<String, dynamic>.from(data)));
    firestore.documents[id]!.addAll(Map<String, dynamic>.from(data));
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    await firestore.beforeRead(options);
    return _Snapshot(id, firestore.documents[id]);
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
