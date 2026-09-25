import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/clients/data/client_repository.dart';
import 'package:kayra_crm_v1/features/clients/domain/kayra_client.dart';
import 'package:kayra_crm_v1/features/trips/data/trip_repository.dart';
import 'package:kayra_crm_v1/features/trips/domain/kayra_trip.dart';

TripBrief _brief({
  TripType type = TripType.fit,
  List<String> destinations = const ['Dubai'],
  DateTime? date,
}) => TripBrief(
  destinations: destinations,
  travelStartDate: date ?? DateTime(2026, 12, 1, 15),
  numberOfNights: 4,
  adults: 2,
  children: 0,
  infants: 0,
  hotelCategory: HotelCategory.fourStar,
  tripType: type,
);
KayraClient _client({String? company = 'Company'}) => KayraClient(
  id: 'client-1',
  details: ClientDetails(
    firstName: 'Mayur',
    lastName: 'Sharma',
    mobileNumber: '+91 98765 43210',
    company: company,
  ),
  createdByUid: 'agent-1',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
Map<String, dynamic> _record() => {
  ..._brief().toMap(),
  'travelStartDate': Timestamp.fromDate(DateTime.utc(2026, 12, 1)),
  'clientId': 'client-1',
  'clientFirstName': 'Mayur',
  'clientLastName': 'Sharma',
  'tripName': 'Mayur Sharma – Dubai – Dec 2026',
  'ownerUid': 'agent-2',
  'createdByUid': 'agent-1',
  'status': 'confirmed',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 25)),
};

void main() {
  late _FakeFirestore firestore;
  late _Clients clients;
  late FirestoreTripRepository repository;
  setUp(() {
    firestore = _FakeFirestore();
    clients = _Clients()..client = _client();
    repository = FirestoreTripRepository(
      firestore: firestore,
      clientRepository: clients,
    );
  });
  test(
    'create verifies Client, auto-generates ID and writes exact Draft payload',
    () async {
      final id = await repository.createTrip(
        clientId: 'client-1',
        brief: _brief(),
        currentUserUid: 'signed-in-agent',
      );
      expect(id, 'generated-1');
      expect(clients.reads, ['client-1']);
      expect(firestore.collections, ['trips']);
      expect(firestore.requestedIds, [null]);
      expect(firestore.sets.single.data, {
        ..._brief().toMap(),
        'travelStartDate': Timestamp.fromDate(DateTime.utc(2026, 12, 1)),
        'clientId': 'client-1',
        'clientFirstName': 'Mayur',
        'clientLastName': 'Sharma',
        'tripName': 'Mayur Sharma – Dubai – Dec 2026',
        'status': 'draft',
        'ownerUid': 'signed-in-agent',
        'createdByUid': 'signed-in-agent',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      expect(firestore.readOptions, isEmpty);
    },
  );
  test('identical briefs receive distinct Firestore IDs', () async {
    final first = await repository.createTrip(
      clientId: 'client-1',
      brief: _brief(),
      currentUserUid: 'agent-1',
    );
    final second = await repository.createTrip(
      clientId: 'client-1',
      brief: _brief(),
      currentUserUid: 'agent-1',
    );
    expect(first, isNot(second));
    expect(firestore.requestedIds, [null, null]);
  });
  test('missing Client prevents creation and update', () async {
    clients.client = null;
    await expectLater(
      repository.createTrip(
        clientId: 'missing',
        brief: _brief(),
        currentUserUid: 'agent-1',
      ),
      throwsFormatException,
    );
    firestore.documents['trip-1'] = _record();
    await expectLater(
      repository.updateTrip(tripId: 'trip-1', brief: _brief()),
      throwsFormatException,
    );
    expect(firestore.sets, isEmpty);
    expect(firestore.updates, isEmpty);
  });
  for (final type in TripType.values) {
    test(
      '${type.label} checks actual Client company on create and update',
      () async {
        clients.client = _client(company: ' ');
        firestore.documents['trip-1'] = _record();
        if (type == TripType.corporate || type == TripType.groups) {
          await expectLater(
            repository.createTrip(
              clientId: 'client-1',
              brief: _brief(type: type),
              currentUserUid: 'agent-1',
            ),
            throwsFormatException,
          );
          await expectLater(
            repository.updateTrip(
              tripId: 'trip-1',
              brief: _brief(type: type),
            ),
            throwsFormatException,
          );
          expect(firestore.sets, isEmpty);
          expect(firestore.updates, isEmpty);
          clients.client = _client();
        }
        await repository.createTrip(
          clientId: 'client-1',
          brief: _brief(type: type),
          currentUserUid: 'agent-1',
        );
        await repository.updateTrip(
          tripId: 'trip-1',
          brief: _brief(type: type),
        );
        expect(firestore.sets.single.data['tripType'], type.value);
        expect(firestore.updates.single.data['tripType'], type.value);
      },
    );
  }
  test(
    'update excludes protected fields and regenerates name from original snapshot',
    () async {
      firestore.documents['trip-1'] = {
        ..._record(),
        'clientFirstName': 'Original',
        'tripName': 'Original Sharma – Dubai – Dec 2026',
      };
      final original = Map.of(firestore.documents['trip-1']!);
      final brief = _brief(
        destinations: [' Paris ', 'London'],
        date: DateTime.utc(2027, 1, 30),
      );
      await repository.updateTrip(tripId: 'trip-1', brief: brief);
      expect(firestore.updates.single.id, 'trip-1');
      expect(firestore.updates.single.data, {
        ...brief.toMap(),
        'travelStartDate': Timestamp.fromDate(DateTime.utc(2027, 1, 30)),
        'tripName': 'Original Sharma – Paris & London – Jan 2027',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final field in [
        'clientId',
        'clientFirstName',
        'clientLastName',
        'ownerUid',
        'createdByUid',
        'createdAt',
        'status',
      ]) {
        expect(
          firestore.documents['trip-1']![field],
          original[field],
          reason: field,
        );
        expect(firestore.updates.single.data.containsKey(field), isFalse);
      }
      expect(firestore.sets, isEmpty);
    },
  );
  test('update never upserts missing trip', () async {
    await expectLater(
      repository.updateTrip(tripId: 'missing', brief: _brief()),
      throwsStateError,
    );
    expect(firestore.documents, isEmpty);
    expect(clients.reads, isEmpty);
  });
  test(
    'get converts all Timestamp fields and missing trip returns null',
    () async {
      firestore.documents['trip-1'] = _record();
      final trip = await repository.getTripById('trip-1');
      expect(trip!.travelStartDate, DateTime.utc(2026, 12, 1));
      expect(trip.createdAt, DateTime.utc(2026, 9, 1));
      expect(trip.updatedAt, DateTime.utc(2026, 9, 25));
      expect(trip.status, TripStatus.confirmed);
      expect(trip.ownerUid, 'agent-2');
      expect(await repository.getTripById('missing'), isNull);
      expect(
        firestore.readOptions.every(
          (option) => option?.source == Source.server,
        ),
        isTrue,
      );
    },
  );
  test(
    'owner query filters ownerUid, never original creator or all records',
    () async {
      firestore.documents.addAll({
        'owned': _record(),
        'created-only': {
          ..._record(),
          'ownerUid': 'agent-1',
          'createdByUid': 'agent-2',
        },
      });
      final trips = await repository.listOwnedTrips('agent-2');
      expect(trips.map((trip) => trip.id), ['owned']);
      expect(firestore.filters, [(field: 'ownerUid', equals: 'agent-2')]);
      expect(firestore.unscopedReads, 0);
      expect(firestore.readOptions.single?.source, Source.server);
      expect(() => trips.clear(), throwsUnsupportedError);
      expect(await repository.listOwnedTrips('nobody'), isEmpty);
      expect(firestore.unscopedReads, 0);
    },
  );
  test('Admin list supports all owners without a filter', () async {
    expect(await repository.listAllTripsForAdmin(), isEmpty);
    firestore.documents.addAll({
      'one': _record(),
      'two': {..._record(), 'ownerUid': 'other'},
    });
    final trips = await repository.listAllTripsForAdmin();
    expect(trips.map((trip) => trip.id), ['one', 'two']);
    expect(firestore.filters, isEmpty);
    expect(firestore.unscopedReads, 2);
    expect(() => trips.clear(), throwsUnsupportedError);
  });
  for (final field in ['travelStartDate', 'createdAt', 'updatedAt']) {
    for (final value in [null, '2026-12-01', DateTime.utc(2026), 123]) {
      test('get and list reject non-Timestamp $field=$value', () async {
        firestore.documents['bad'] = {..._record(), field: value};
        await expectLater(repository.getTripById('bad'), throwsFormatException);
        await expectLater(
          repository.listAllTripsForAdmin(),
          throwsFormatException,
        );
      });
    }
  }
  test('corrupt records fail instead of being skipped or defaulted', () async {
    for (final field in _record().keys) {
      firestore.documents['bad'] = _record()..remove(field);
      await expectLater(repository.getTripById('bad'), throwsFormatException);
      await expectLater(
        repository.listOwnedTrips('agent-2'),
        field == 'ownerUid' ? completion(isEmpty) : throwsFormatException,
      );
    }
    for (final patch in <Map<String, Object?>>[
      {'status': 'unknown'},
      {'hotelCategory': 'five'},
      {'tripType': 'other'},
      {'adults': -1},
      {'infants': 1.5},
    ]) {
      firestore.documents['bad'] = {..._record(), ...patch};
      await expectLater(
        repository.listAllTripsForAdmin(),
        throwsFormatException,
      );
    }
  });
  for (final id in ['', ' ', 'trips/other', '.', '..']) {
    test(
      'invalid identifiers fail before any database operation: $id',
      () async {
        await expectLater(
          repository.createTrip(
            clientId: id,
            brief: _brief(),
            currentUserUid: 'agent',
          ),
          throwsFormatException,
        );
        await expectLater(
          repository.createTrip(
            clientId: 'client-1',
            brief: _brief(),
            currentUserUid: id,
          ),
          throwsFormatException,
        );
        await expectLater(repository.getTripById(id), throwsFormatException);
        await expectLater(
          repository.updateTrip(tripId: id, brief: _brief()),
          throwsFormatException,
        );
        expect(() => repository.listOwnedTrips(id), throwsFormatException);
        expect(firestore.collections, isEmpty);
        expect(clients.reads, isEmpty);
      },
    );
  }
  test(
    'permission failures propagate without fallback writes or retries',
    () async {
      final denied = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      firestore.error = denied;
      await expectLater(
        repository.createTrip(
          clientId: 'client-1',
          brief: _brief(),
          currentUserUid: 'agent',
        ),
        throwsA(same(denied)),
      );
      await expectLater(
        repository.getTripById('trip-1'),
        throwsA(same(denied)),
      );
      await expectLater(
        repository.updateTrip(tripId: 'trip-1', brief: _brief()),
        throwsA(same(denied)),
      );
      await expectLater(
        repository.listOwnedTrips('agent'),
        throwsA(same(denied)),
      );
      await expectLater(
        repository.listAllTripsForAdmin(),
        throwsA(same(denied)),
      );
      expect(firestore.sets, isEmpty);
      expect(firestore.updates, isEmpty);
    },
  );
  for (final operation in ['get', 'owned', 'admin']) {
    testWidgets('bounds stalled $operation reads', (tester) async {
      final pending = Completer<void>();
      firestore.readWait = pending.future;
      final future = switch (operation) {
        'get' => repository.getTripById('one'),
        'owned' => repository.listOwnedTrips('agent'),
        _ => repository.listAllTripsForAdmin(),
      };
      final assertion = expectLater(future, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 30));
      await assertion;
      pending.complete();
      await tester.pump();
    });
  }
}

class _Clients extends Fake implements ClientRepository {
  KayraClient? client;
  final reads = <String>[];
  @override
  Future<KayraClient?> getClientById(String clientId) async {
    reads.add(clientId);
    return client;
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
