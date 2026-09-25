import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/users/data/user_profile_repository.dart';
import 'package:kayra_crm_v1/features/users/domain/kayra_user.dart';

void main() {
  KayraUser actor({
    String uid = 'admin-1',
    KayraUserRole role = KayraUserRole.admin,
    KayraUserStatus status = KayraUserStatus.active,
  }) => KayraUser(
    uid: uid,
    email: 'admin@kholidaymaps.com',
    role: role,
    status: status,
    createdAt: DateTime.utc(2026),
    lastLoginAt: DateTime.utc(2026),
  );

  for (final role in KayraUserRole.values) {
    test(
      'updates only role to ${role.name} on the selected document',
      () async {
        final firestore = _FakeFirestore(
          document: _storedProfile(
            role: role == KayraUserRole.admin ? 'agent' : 'admin',
          ),
        );
        final original = Map<String, dynamic>.from(firestore.document!);
        await FirestoreUserProfileRepository(
          firestore: firestore,
        ).updateUserRole(currentUser: actor(), userId: 'agent-1', role: role);
        expect(firestore.collectionPaths, ['users']);
        expect(firestore.documentPaths, ['agent-1']);
        expect(firestore.directUpdates, [
          {'role': role.name},
        ]);
        expect(firestore.document, {...original, 'role': role.name});
        expect(firestore.attempts, isEmpty);
      },
    );
  }

  for (final currentUser in [
    actor(uid: 'agent-1'),
    actor(role: KayraUserRole.agent),
    actor(status: KayraUserStatus.inactive),
  ]) {
    test(
      'rejects self/non-admin/inactive role change ${currentUser.uid}/${currentUser.role}/${currentUser.status}',
      () async {
        final firestore = _FakeFirestore();
        await expectLater(
          FirestoreUserProfileRepository(firestore: firestore).updateUserRole(
            currentUser: currentUser,
            userId: 'agent-1',
            role: KayraUserRole.admin,
          ),
          throwsStateError,
        );
        expect(firestore.collectionPaths, isEmpty);
        expect(firestore.directUpdates, isEmpty);
      },
    );
  }

  test('invalid roles cannot cross the typed repository boundary', () {
    final firestore = _FakeFirestore();
    final dynamic repository = FirestoreUserProfileRepository(
      firestore: firestore,
    );
    for (final role in ['owner', 'admin', '', null, 1]) {
      expect(
        () => repository.updateUserRole(
          currentUser: actor(),
          userId: 'agent-1',
          role: role,
        ),
        throwsA(isA<TypeError>()),
      );
    }
    expect(firestore.collectionPaths, isEmpty);
  });

  test('invalid target ID is rejected without a write', () async {
    final firestore = _FakeFirestore();
    await expectLater(
      FirestoreUserProfileRepository(firestore: firestore).updateUserRole(
        currentUser: actor(),
        userId: 'users/other',
        role: KayraUserRole.admin,
      ),
      throwsFormatException,
    );
    expect(firestore.collectionPaths, isEmpty);
  });

  test('role write failures propagate without changing profile data', () async {
    final firestore = _FakeFirestore(document: _storedProfile());
    final original = Map<String, dynamic>.from(firestore.document!);
    final failure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    firestore.updateError = failure;
    await expectLater(
      FirestoreUserProfileRepository(firestore: firestore).updateUserRole(
        currentUser: actor(),
        userId: 'agent-1',
        role: KayraUserRole.admin,
      ),
      throwsA(same(failure)),
    );
    expect(firestore.document, original);
  });

  test(
    'directory reads only the server and sorts active users by name or email',
    () async {
      Map<String, dynamic> entry(
        String uid,
        String? name, {
        String status = 'active',
      }) => {
        ..._storedProfile(status: status),
        'uid': uid,
        'email': '$uid@kholidaymaps.com',
        'displayName': name,
      };
      final firestore = _FakeFirestore()
        ..directory = {
          'inactive': entry('inactive', 'A First', status: 'inactive'),
          'zoe': entry('zoe', 'Zoe'),
          'fallback': entry('fallback', '  '),
          'alice': entry('alice', ' Alice '),
        };
      final users = await FirestoreUserProfileRepository(
        firestore: firestore,
      ).listUsers();
      expect(users.map((user) => user.uid), [
        'alice',
        'fallback',
        'zoe',
        'inactive',
      ]);
      expect(firestore.collectionPaths, ['users']);
      expect(firestore.directoryReadOptions.single?.source, Source.server);
      expect(firestore.attempts, isEmpty);
      expect(firestore.documentPaths, isEmpty);
    },
  );

  test(
    'directory permits an unavailable last login without changing bootstrap validation',
    () async {
      for (final omit in [true, false]) {
        final data = _storedProfile();
        if (omit) {
          data.remove('lastLoginAt');
        } else {
          data['lastLoginAt'] = null;
        }
        final firestore = _FakeFirestore()..directory = {'agent-1': data};
        final users = await FirestoreUserProfileRepository(
          firestore: firestore,
        ).listUsers();
        expect(users.single.lastLoginAt, isNull);
      }
    },
  );

  test('directory returns an empty list without inventing users', () async {
    final firestore = _FakeFirestore();
    expect(
      await FirestoreUserProfileRepository(firestore: firestore).listUsers(),
      isEmpty,
    );
    expect(firestore.attempts, isEmpty);
  });

  for (final invalid in [
    {'role': 'owner'},
    {'status': 'pending'},
    {'uid': 'different'},
    {'email': 'external@example.com'},
    {'lastLoginAt': 'yesterday'},
    {'unexpected': true},
  ]) {
    test('directory rejects malformed profile fields $invalid', () async {
      final firestore = _FakeFirestore()
        ..directory = {
          'agent-1': {..._storedProfile(), ...invalid},
        };
      await expectLater(
        FirestoreUserProfileRepository(firestore: firestore).listUsers(),
        throwsFormatException,
      );
      expect(firestore.attempts, isEmpty);
    });
  }

  test(
    'directory propagates permission denial without cached fallback',
    () async {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      final firestore = _FakeFirestore()..directoryError = error;
      await expectLater(
        FirestoreUserProfileRepository(firestore: firestore).listUsers(),
        throwsA(same(error)),
      );
    },
  );

  testWidgets('directory read times out without retrying', (tester) async {
    final pending = Completer<void>();
    final firestore = _FakeFirestore()..directoryWait = pending.future;
    final result = FirestoreUserProfileRepository(
      firestore: firestore,
    ).listUsers();
    final assertion = expectLater(result, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 30));
    await assertion;
    expect(firestore.directoryReadOptions, hasLength(1));
    pending.complete();
    await tester.pump();
  });

  test(
    'creates one agent profile with normalized identity and server dates',
    () async {
      final firestore = _FakeFirestore();
      final repository = FirestoreUserProfileRepository(firestore: firestore);

      final profile = await repository.bootstrap(
        _TestUser(email: ' AGENT@KHOLIDAYMAPS.COM '),
      );

      expect(firestore.collectionPaths, ['users']);
      expect(firestore.documentPaths, ['agent-1']);
      final creation = firestore.attempts.single.creation!;
      expect(creation.keys, unorderedEquals(_storedProfile().keys));
      expect(creation['uid'], 'agent-1');
      expect(creation['email'], 'agent@kholidaymaps.com');
      expect(creation['displayName'], 'Current Agent');
      expect(creation['photoUrl'], 'https://example.com/current.png');
      expect(creation['role'], 'agent');
      expect(creation['status'], 'active');
      expect(creation['createdAt'], isA<FieldValue>());
      expect(creation['lastLoginAt'], isA<FieldValue>());
      expect(firestore.serverReadOptions.single?.source, Source.server);
      expect(profile.role, KayraUserRole.agent);
      expect(profile.isActive, isTrue);
      expect(profile.createdAt, firestore.commitTime);
      expect(profile.lastLoginAt, firestore.commitTime);
    },
  );

  test('refreshes only identity and activity on an existing admin', () async {
    final firestore = _FakeFirestore(document: _storedProfile(role: 'admin'));
    final original = Map<String, dynamic>.from(firestore.document!);
    final repository = FirestoreUserProfileRepository(firestore: firestore);

    final profile = await repository.bootstrap(_TestUser());

    expect(firestore.attempts.single.creation, isNull);
    expect(
      firestore.attempts.single.updateData!.keys,
      unorderedEquals(['displayName', 'photoUrl', 'lastLoginAt']),
    );
    for (final field in ['uid', 'email', 'role', 'status', 'createdAt']) {
      expect(firestore.document![field], original[field]);
    }
    expect(profile.role, KayraUserRole.admin);
    expect(profile.displayName, 'Current Agent');
    expect(profile.photoUrl, 'https://example.com/current.png');
    expect(profile.createdAt, DateTime.utc(2026, 9, 1));
    expect(profile.lastLoginAt, firestore.commitTime);
  });

  test(
    'preserves the original creation timestamp across repeated sign-ins',
    () async {
      final firestore = _FakeFirestore();
      final repository = FirestoreUserProfileRepository(firestore: firestore);
      final first = await repository.bootstrap(_TestUser());
      firestore.commitTime = DateTime.utc(2026, 9, 25);

      final second = await repository.bootstrap(_TestUser());

      expect(second.createdAt, first.createdAt);
      expect(second.lastLoginAt, firestore.commitTime);
      expect(firestore.attempts.last.creation, isNull);
    },
  );

  test('allows missing Google display name and photo', () async {
    final firestore = _FakeFirestore();
    final profile = await FirestoreUserProfileRepository(
      firestore: firestore,
    ).bootstrap(_TestUser(displayName: null, photoURL: null));

    expect(profile.displayName, isNull);
    expect(profile.photoUrl, isNull);
    expect(firestore.document!.containsKey('displayName'), isTrue);
    expect(firestore.document!.containsKey('photoUrl'), isTrue);
  });

  test('returns an inactive profile without attempting any write', () async {
    final firestore = _FakeFirestore(
      document: _storedProfile(status: 'inactive', role: 'admin'),
    );
    final original = Map<String, dynamic>.from(firestore.document!);
    final profile = await FirestoreUserProfileRepository(
      firestore: firestore,
    ).bootstrap(_TestUser());

    expect(profile.status, KayraUserStatus.inactive);
    expect(profile.isActive, isFalse);
    expect(profile.role, KayraUserRole.admin);
    expect(firestore.attempts.single.creation, isNull);
    expect(firestore.attempts.single.updateData, isNull);
    expect(firestore.document, original);
    expect(firestore.serverReadOptions.single?.source, Source.server);
  });

  test(
    'uses the final server status if access changes after the transaction',
    () async {
      final firestore = _FakeFirestore(document: _storedProfile());
      firestore.beforeServerRead = () {
        firestore.document!['status'] = 'inactive';
      };

      final profile = await FirestoreUserProfileRepository(
        firestore: firestore,
      ).bootstrap(_TestUser());

      expect(profile.isActive, isFalse);
    },
  );

  test(
    're-reads on a transaction retry instead of resetting a concurrent profile',
    () async {
      final firestore = _FakeFirestore()
        ..retryWithDocument = _storedProfile(role: 'admin', status: 'inactive');

      final profile = await FirestoreUserProfileRepository(
        firestore: firestore,
      ).bootstrap(_TestUser());

      expect(firestore.attempts, hasLength(2));
      expect(firestore.attempts.first.creation, isNotNull);
      expect(firestore.attempts.last.creation, isNull);
      expect(firestore.attempts.last.updateData, isNull);
      expect(profile.role, KayraUserRole.admin);
      expect(profile.isActive, isFalse);
      expect(profile.createdAt, DateTime.utc(2026, 9, 1));
    },
  );

  for (final user in [
    _TestUser(uid: ''),
    _TestUser(uid: 'other/user'),
    _TestUser(uid: '..'),
    _TestUser(email: null),
    _TestUser(email: '@kholidaymaps.com'),
    _TestUser(email: 'agent@gmail.com'),
    _TestUser(email: 'agent@team.kholidaymaps.com'),
    _TestUser(email: 'a@agent@kholidaymaps.com'),
  ]) {
    test(
      'rejects invalid auth identity ${user.uid}/${user.email} before Firestore',
      () async {
        final firestore = _FakeFirestore();

        await expectLater(
          FirestoreUserProfileRepository(firestore: firestore).bootstrap(user),
          throwsFormatException,
        );

        expect(firestore.collectionPaths, isEmpty);
        expect(firestore.attempts, isEmpty);
      },
    );
  }

  final malformedFields = <String, Object?>{
    'uid': 'other-user',
    'email': 'other@kholidaymaps.com',
    'role': 'owner',
    'status': 'pending',
    'createdAt': DateTime.utc(2026, 9, 1),
    'lastLoginAt': null,
  };
  for (final field in malformedFields.entries) {
    test(
      'fails closed on stored malformed ${field.key} without writing',
      () async {
        final firestore = _FakeFirestore(
          document: {..._storedProfile(), field.key: field.value},
        );

        await expectLater(
          FirestoreUserProfileRepository(
            firestore: firestore,
          ).bootstrap(_TestUser()),
          throwsFormatException,
        );

        expect(firestore.attempts.single.creation, isNull);
        expect(firestore.attempts.single.updateData, isNull);
        expect(firestore.serverReadOptions, isEmpty);
      },
    );
  }

  for (final mode in [
    'missing',
    'unresolved timestamp',
    'wrong identity',
    'wrong email',
  ]) {
    test('rejects a $mode final server profile', () async {
      final firestore = _FakeFirestore();
      firestore.beforeServerRead = () {
        switch (mode) {
          case 'missing':
            firestore.document = null;
          case 'unresolved timestamp':
            firestore.document!['createdAt'] = null;
          case 'wrong identity':
            firestore.document!['uid'] = 'other-user';
          case 'wrong email':
            firestore.document!['email'] = 'other@kholidaymaps.com';
        }
      };

      await expectLater(
        FirestoreUserProfileRepository(
          firestore: firestore,
        ).bootstrap(_TestUser()),
        throwsFormatException,
      );
    });
  }

  for (final failingStage in ['transaction', 'server read']) {
    test(
      'propagates $failingStage failure without a cached profile fallback',
      () async {
        final firestore = _FakeFirestore(document: _storedProfile());
        final failure = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        );
        if (failingStage == 'transaction') {
          firestore.transactionError = failure;
        } else {
          firestore.serverReadError = failure;
        }

        await expectLater(
          FirestoreUserProfileRepository(
            firestore: firestore,
          ).bootstrap(_TestUser()),
          throwsA(same(failure)),
        );
      },
    );
  }

  for (final stalledStage in ['transaction', 'server read']) {
    testWidgets('bounds a stalled $stalledStage to 30 seconds', (tester) async {
      final completion = Completer<void>();
      final firestore = _FakeFirestore(document: _storedProfile());
      if (stalledStage == 'transaction') {
        firestore.transactionWait = completion.future;
      } else {
        firestore.serverReadWait = completion.future;
      }
      final result = FirestoreUserProfileRepository(
        firestore: firestore,
      ).bootstrap(_TestUser());
      final assertion = expectLater(result, throwsA(isA<TimeoutException>()));

      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await assertion;
      completion.complete();
      await tester.pump();
    });
  }
}

Map<String, dynamic> _storedProfile({
  String role = 'agent',
  String status = 'active',
}) => {
  'uid': 'agent-1',
  'email': 'agent@kholidaymaps.com',
  'displayName': 'Previous Agent',
  'photoUrl': 'https://example.com/previous.png',
  'role': role,
  'status': status,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
  'lastLoginAt': Timestamp.fromDate(DateTime.utc(2026, 9, 20)),
};

class _TestUser extends Fake implements User {
  _TestUser({
    this.uid = 'agent-1',
    this.email = 'agent@kholidaymaps.com',
    this.displayName = 'Current Agent',
    this.photoURL = 'https://example.com/current.png',
  });

  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;
  @override
  final String? photoURL;
}

// A bounded transaction harness: captures writes, resolves server sentinels,
// and can discard one attempt to exercise a concurrent profile creation.
class _FakeFirestore extends Fake implements FirebaseFirestore {
  _FakeFirestore({this.document});

  Map<String, dynamic>? document;
  Map<String, dynamic>? retryWithDocument;
  DateTime commitTime = DateTime.utc(2026, 9, 24);
  final collectionPaths = <String>[];
  final documentPaths = <String?>[];
  final attempts = <_FakeTransaction>[];
  final serverReadOptions = <GetOptions?>[];
  Object? transactionError;
  Object? serverReadError;
  Future<void>? transactionWait;
  Future<void>? serverReadWait;
  void Function()? beforeServerRead;
  Map<String, Map<String, dynamic>> directory = {};
  final directoryReadOptions = <GetOptions?>[];
  Object? directoryError;
  Future<void>? directoryWait;
  final directUpdates = <Map<Object, Object?>>[];
  Object? updateError;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    collectionPaths.add(collectionPath);
    return _FakeCollection(this);
  }

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (transactionError != null) throw transactionError!;
    if (transactionWait != null) await transactionWait;
    var transaction = _FakeTransaction(this);
    attempts.add(transaction);
    var result = await transactionHandler(transaction);
    if (retryWithDocument != null) {
      document = retryWithDocument;
      retryWithDocument = null;
      transaction = _FakeTransaction(this);
      attempts.add(transaction);
      result = await transactionHandler(transaction);
    }
    final creation = transaction.creation;
    final update = transaction.updateData;
    if (creation != null) document = _resolveDates(creation);
    if (update != null) document!.addAll(_resolveDates(update));
    return result;
  }

  Map<String, dynamic> _resolveDates(Map<String, dynamic> values) => values.map(
    (key, value) => MapEntry(
      key,
      value is FieldValue ? Timestamp.fromDate(commitTime) : value,
    ),
  );
}

// ignore: subtype_of_sealed_class
class _FakeCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollection(this.firestore);

  @override
  final _FakeFirestore firestore;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    firestore.directoryReadOptions.add(options);
    if (firestore.directoryError != null) throw firestore.directoryError!;
    if (firestore.directoryWait != null) await firestore.directoryWait;
    return _FakeQuerySnapshot(
      firestore.directory.entries
          .map((entry) => _FakeQueryDocument(entry.key, entry.value))
          .toList(),
    );
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    firestore.documentPaths.add(path);
    return _FakeReference(firestore, path!);
  }
}

// ignore: subtype_of_sealed_class
class _FakeReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _FakeReference(this.firestore, this.id);

  @override
  final _FakeFirestore firestore;
  @override
  final String id;

  @override
  Future<void> update(Map<Object, Object?> data) async {
    firestore.directUpdates.add(Map.of(data));
    if (firestore.updateError != null) throw firestore.updateError!;
    if (firestore.document == null) throw StateError('Missing document');
    firestore.document!.addAll(Map<String, dynamic>.from(data));
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    firestore.serverReadOptions.add(options);
    if (firestore.serverReadError != null) throw firestore.serverReadError!;
    if (firestore.serverReadWait != null) await firestore.serverReadWait;
    firestore.beforeServerRead?.call();
    return _FakeSnapshot(id, firestore.document);
  }
}

class _FakeTransaction extends Fake implements Transaction {
  _FakeTransaction(this.firestore);

  final _FakeFirestore firestore;
  Map<String, dynamic>? creation;
  Map<String, dynamic>? updateData;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async =>
      _FakeSnapshot(documentReference.id, firestore.document)
          as DocumentSnapshot<T>;

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    creation = Map<String, dynamic>.from(data as Map);
    return this;
  }

  @override
  Transaction update(
    DocumentReference documentReference,
    Map<Object, Object?> data,
  ) {
    updateData = Map<String, dynamic>.from(data);
    return this;
  }
}

// ignore: subtype_of_sealed_class
class _FakeSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeSnapshot(this.id, Map<String, dynamic>? data)
    : _data = data == null ? null : Map<String, dynamic>.from(data);

  @override
  final String id;
  final Map<String, dynamic>? _data;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;
}

// ignore: subtype_of_sealed_class
class _FakeQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _FakeQuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

// ignore: subtype_of_sealed_class
class _FakeQueryDocument extends _FakeSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeQueryDocument(super.id, super.data);
  @override
  Map<String, dynamic> data() => super.data()!;
}
