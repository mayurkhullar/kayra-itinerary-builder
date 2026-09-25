import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/clients/data/client_repository.dart';
import 'package:kayra_crm_v1/features/clients/domain/kayra_client.dart';

void main() {
  ClientDetails details() => ClientDetails(
    firstName: ' Priya ',
    lastName: ' Shah ',
    mobileNumber: ' +91 09876543210 ',
    email: ' PRIYA@EXAMPLE.COM ',
    city: ' Mumbai ',
    company: ' Partner ',
  );

  test(
    'create uses an auto ID and writes exactly the normalized profile and audit fields',
    () async {
      final firestore = _FakeFirestore();
      final id = await FirestoreClientRepository(
        firestore: firestore,
      ).createClient(details: details(), currentUserUid: 'signed-in-agent');
      expect(id, 'generated-1');
      expect(firestore.collections, ['clients']);
      expect(firestore.requestedIds, [null]);
      expect(firestore.sets.single.id, id);
      expect(firestore.sets.single.data, {
        'firstName': 'Priya',
        'lastName': 'Shah',
        'mobileNumber': '+91 09876543210',
        'email': 'priya@example.com',
        'city': 'Mumbai',
        'company': 'Partner',
        'createdByUid': 'signed-in-agent',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      expect(firestore.readOptions, isEmpty);
      expect(firestore.updates, isEmpty);
    },
  );

  test(
    'two identical profiles get separate generated IDs without merging',
    () async {
      final firestore = _FakeFirestore();
      final repository = FirestoreClientRepository(firestore: firestore);
      final first = await repository.createClient(
        details: details(),
        currentUserUid: 'agent',
      );
      final second = await repository.createClient(
        details: details(),
        currentUserUid: 'agent',
      );
      expect(first, isNot(second));
      expect(firestore.requestedIds, [null, null]);
    },
  );

  test(
    'update preserves ID, creator and creation time, and clears omitted optional fields',
    () async {
      final firestore = _FakeFirestore()..documents['client-1'] = _record();
      final original = Map<String, dynamic>.from(
        firestore.documents['client-1']!,
      );
      await FirestoreClientRepository(firestore: firestore).updateClient(
        clientId: 'client-1',
        details: ClientDetails(
          firstName: 'Updated',
          lastName: 'Name',
          mobileNumber: '0012345',
        ),
      );
      expect(firestore.requestedIds, ['client-1']);
      expect(firestore.updates.single.data, {
        'firstName': 'Updated',
        'lastName': 'Name',
        'mobileNumber': '0012345',
        'email': null,
        'city': null,
        'company': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      expect(
        firestore.documents['client-1']!['createdByUid'],
        original['createdByUid'],
      );
      expect(
        firestore.documents['client-1']!['createdAt'],
        original['createdAt'],
      );
      expect(firestore.documents.keys, ['client-1']);
      expect(firestore.sets, isEmpty);
    },
  );

  test('update never creates a missing document', () async {
    final firestore = _FakeFirestore();
    await expectLater(
      FirestoreClientRepository(
        firestore: firestore,
      ).updateClient(clientId: 'missing', details: details()),
      throwsStateError,
    );
    expect(firestore.documents, isEmpty);
    expect(firestore.sets, isEmpty);
  });

  test(
    'get parses Firestore timestamps, uses document identity and server reads',
    () async {
      final firestore = _FakeFirestore()..documents['client-1'] = _record();
      final client = await FirestoreClientRepository(
        firestore: firestore,
      ).getClientById('client-1');
      expect(client!.id, 'client-1');
      expect(client.createdByUid, 'agent-1');
      expect(client.createdAt, DateTime.utc(2026, 9, 1));
      expect(client.updatedAt, DateTime.utc(2026, 9, 25));
      expect(client.updatedAt.isUtc, isTrue);
      expect(firestore.readOptions.single?.source, Source.server);
    },
  );

  test('missing client returns null', () async {
    final firestore = _FakeFirestore();
    expect(
      await FirestoreClientRepository(
        firestore: firestore,
      ).getClientById('missing'),
      isNull,
    );
  });

  test(
    'Admin list returns all owners without a filter and an immutable result',
    () async {
      final firestore = _FakeFirestore();
      final repository = FirestoreClientRepository(firestore: firestore);
      expect(await repository.listAllClientsForAdmin(), isEmpty);
      firestore.documents.addAll({
        'one': _record(),
        'two': {..._record(), 'createdByUid': 'another-agent'},
      });
      final clients = await repository.listAllClientsForAdmin();
      expect(clients.map((client) => client.id), ['one', 'two']);
      expect(clients.first.displayName, 'Priya Shah');
      expect(() => clients.clear(), throwsUnsupportedError);
      expect(
        firestore.readOptions.every(
          (option) => option?.source == Source.server,
        ),
        isTrue,
      );
      expect(firestore.collections, ['clients', 'clients']);
      expect(firestore.sets, isEmpty);
      expect(firestore.updates, isEmpty);
      expect(firestore.filters, isEmpty);
      expect(firestore.unscopedReads, 2);
    },
  );

  test(
    'Agent list sends an owner equality query, never fetches all clients',
    () async {
      final firestore = _FakeFirestore()
        ..documents.addAll({
          'mine': _record(),
          'other': {..._record(), 'createdByUid': 'agent-2'},
        });
      final clients = await FirestoreClientRepository(
        firestore: firestore,
      ).listOwnedClients('agent-1');
      expect(firestore.filters, [(field: 'createdByUid', equals: 'agent-1')]);
      expect(firestore.unscopedReads, 0);
      expect(firestore.readOptions.single?.source, Source.server);
      expect(clients.map((client) => client.id), ['mine']);
      expect(() => clients.clear(), throwsUnsupportedError);
      expect(firestore.collections, ['clients']);
    },
  );

  test(
    'owner-scoped empty results do not fall back to the entire collection',
    () async {
      final firestore = _FakeFirestore()..documents['other'] = _record();
      final clients = await FirestoreClientRepository(
        firestore: firestore,
      ).listOwnedClients('agent-2');
      expect(clients, isEmpty);
      expect(firestore.unscopedReads, 0);
      expect(firestore.filters, [(field: 'createdByUid', equals: 'agent-2')]);
    },
  );

  test('client repository exposes no delete method', () {
    final firestore = _FakeFirestore();
    final dynamic repository = FirestoreClientRepository(firestore: firestore);
    expect(() => repository.deleteClient('one'), throwsNoSuchMethodError);
    expect(firestore.collections, isEmpty);
  });

  for (final field in ['createdAt', 'updatedAt']) {
    for (final value in [null, '2026-09-25', DateTime.utc(2026), 123]) {
      test('get and list reject invalid Firestore $field: $value', () async {
        final firestore = _FakeFirestore()
          ..documents['bad'] = {..._record(), field: value};
        final repository = FirestoreClientRepository(firestore: firestore);
        await expectLater(
          repository.getClientById('bad'),
          throwsFormatException,
        );
        await expectLater(
          repository.listAllClientsForAdmin(),
          throwsFormatException,
        );
      });
    }
  }

  test(
    'malformed profiles are rejected rather than skipped or fabricated',
    () async {
      for (final field in [
        'firstName',
        'lastName',
        'mobileNumber',
        'createdByUid',
        'createdAt',
        'updatedAt',
      ]) {
        final firestore = _FakeFirestore()
          ..documents['bad'] = (_record()..remove(field));
        final repository = FirestoreClientRepository(firestore: firestore);
        await expectLater(
          repository.getClientById('bad'),
          throwsFormatException,
        );
        await expectLater(
          repository.listAllClientsForAdmin(),
          throwsFormatException,
        );
      }
    },
  );

  for (final id in ['', ' ', 'clients/other', '.', '..']) {
    test(
      'rejects invalid IDs and creator before contacting Firestore: $id',
      () async {
        final firestore = _FakeFirestore();
        final repository = FirestoreClientRepository(firestore: firestore);
        await expectLater(
          repository.createClient(details: details(), currentUserUid: id),
          throwsFormatException,
        );
        await expectLater(repository.getClientById(id), throwsFormatException);
        await expectLater(
          repository.listOwnedClients(id),
          throwsFormatException,
        );
        await expectLater(
          repository.updateClient(clientId: id, details: details()),
          throwsFormatException,
        );
        expect(firestore.collections, isEmpty);
      },
    );
  }

  test(
    'permission errors propagate without retries, cached fallbacks or writes elsewhere',
    () async {
      final denied = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      final firestore = _FakeFirestore()..error = denied;
      final repository = FirestoreClientRepository(firestore: firestore);
      await expectLater(
        repository.createClient(details: details(), currentUserUid: 'agent'),
        throwsA(same(denied)),
      );
      await expectLater(repository.getClientById('one'), throwsA(same(denied)));
      await expectLater(
        repository.updateClient(clientId: 'one', details: details()),
        throwsA(same(denied)),
      );
      await expectLater(
        repository.listAllClientsForAdmin(),
        throwsA(same(denied)),
      );
      await expectLater(
        repository.listOwnedClients('agent-1'),
        throwsA(same(denied)),
      );
      expect(firestore.collections, [
        'clients',
        'clients',
        'clients',
        'clients',
        'clients',
      ]);
      expect(firestore.documents, isEmpty);
    },
  );

  for (final operation in ['get', 'owned list', 'Admin list']) {
    testWidgets('bounds stalled $operation reads', (tester) async {
      final pending = Completer<void>();
      final firestore = _FakeFirestore()..readWait = pending.future;
      final repository = FirestoreClientRepository(firestore: firestore);
      final future = switch (operation) {
        'get' => repository.getClientById('one'),
        'owned list' => repository.listOwnedClients('agent-1'),
        _ => repository.listAllClientsForAdmin(),
      };
      final assertion = expectLater(future, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 30));
      await assertion;
      pending.complete();
      await tester.pump();
    });
  }
}

Map<String, dynamic> _record() => {
  'firstName': 'Priya',
  'lastName': 'Shah',
  'mobileNumber': '+91 09876543210',
  'email': 'priya@example.com',
  'city': 'Mumbai',
  'company': 'Partner',
  'createdByUid': 'agent-1',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 25)),
};

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
