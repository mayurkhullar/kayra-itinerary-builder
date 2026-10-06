import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_draft_v2_repository.dart';

import 'support/itinerary_draft_v2_fixture.dart';

Matcher failure(ItineraryDraftV2RepositoryFailureKind kind) => throwsA(
  isA<ItineraryDraftV2RepositoryFailure>().having((e) => e.kind, 'kind', kind),
);

void main() {
  late _Firestore db;
  late FirestoreItineraryDraftV2Repository repository;
  setUp(() {
    db = _Firestore();
    repository = FirestoreItineraryDraftV2Repository(firestore: db);
  });
  test(
    'one server read uses exact canonical path without queries or private receipt reads',
    () async {
      final result = await repository.getDraft('trip-1', 'draft-1');
      expect(result.id, 'draft-1');
      expect(result.tripId, 'trip-1');
      expect(db.paths, ['trips/trip-1/itinerary_drafts/draft-1']);
      expect(db.options.single!.source, Source.server);
      expect(
        result
            .packageContent
            .accommodations
            .single
            .options
            .single
            .details
            .hotelName,
        'Example Hotel',
      );
    },
  );
  test('not found is distinct', () async {
    db.exists = false;
    db.data = null;
    await expectLater(
      repository.getDraft('trip-1', 'draft-1'),
      failure(ItineraryDraftV2RepositoryFailureKind.notFound),
    );
  });
  test('existing document with no data is malformed', () async {
    db.data = null;
    await expectLater(
      repository.getDraft('trip-1', 'draft-1'),
      failure(ItineraryDraftV2RepositoryFailureKind.malformed),
    );
  });
  test('returned document identity must match requested identity', () async {
    db.id = 'other';
    await expectLater(
      repository.getDraft('trip-1', 'draft-1'),
      failure(ItineraryDraftV2RepositoryFailureKind.identityMismatch),
    );
  });
  test('stored Trip identity must match requested Trip', () async {
    db.data!['tripId'] = 'other';
    await expectLater(
      repository.getDraft('trip-1', 'draft-1'),
      failure(ItineraryDraftV2RepositoryFailureKind.identityMismatch),
    );
  });
  for (final version in [null, 'itinerary_draft_v1', 'itinerary_draft_v3']) {
    test('unsupported/legacy version $version is distinct', () async {
      db.data!['schemaVersion'] = version;
      await expectLater(
        repository.getDraft('trip-1', 'draft-1'),
        failure(ItineraryDraftV2RepositoryFailureKind.unsupportedVersion),
      );
    });
  }
  test('malformed V2 never escapes as a partial object', () async {
    db.data!.remove('packageContent');
    await expectLater(
      repository.getDraft('trip-1', 'draft-1'),
      failure(ItineraryDraftV2RepositoryFailureKind.malformed),
    );
  });
  test(
    'stored id cannot smuggle an alternate identity into the closed map',
    () async {
      db.data!['id'] = 'other';
      await expectLater(
        repository.getDraft('trip-1', 'draft-1'),
        failure(ItineraryDraftV2RepositoryFailureKind.malformed),
      );
    },
  );
  test('malformed request identities cause zero reads', () async {
    for (final ids in [
      ('bad/trip', 'draft'),
      ('trip-1', r'bad\draft'),
      (' trip', 'draft'),
      ('trip', ''),
    ]) {
      await expectLater(
        repository.getDraft(ids.$1, ids.$2),
        failure(ItineraryDraftV2RepositoryFailureKind.identityMismatch),
      );
    }
    expect(db.paths, isEmpty);
  });
  for (final code in ['permission-denied', 'unavailable', 'unknown']) {
    test('Firestore $code is sanitized', () async {
      db.error = FirebaseException(
        plugin: 'cloud_firestore',
        code: code,
        message: 'PRIVATE gs://bucket/trips/file.pdf INR 500',
      );
      try {
        await repository.getDraft('trip-1', 'draft-1');
        fail('expected failure');
      } on ItineraryDraftV2RepositoryFailure catch (error) {
        expect(
          error.kind,
          code == 'permission-denied'
              ? ItineraryDraftV2RepositoryFailureKind.permissionDenied
              : ItineraryDraftV2RepositoryFailureKind.readFailed,
        );
        expect(error.toString(), isNot(contains('PRIVATE')));
        expect(error.toString(), isNot(contains('gs://')));
      }
    });
  }
  test('unknown infrastructure error is sanitized', () async {
    db.error = StateError('private source content');
    await expectLater(
      repository.getDraft('trip-1', 'draft-1'),
      failure(ItineraryDraftV2RepositoryFailureKind.readFailed),
    );
  });
  testWidgets('stalled read times out safely', (tester) async {
    final pending = Completer<void>();
    db.wait = pending.future;
    final check = expectLater(
      repository.getDraft('trip-1', 'draft-1'),
      failure(ItineraryDraftV2RepositoryFailureKind.readFailed),
    );
    await tester.pump(const Duration(seconds: 30));
    await check;
    pending.complete();
    await tester.pump();
  });
  test(
    'read-only source adds no persistence/listeners/callable/receipt access',
    () {
      final source = File(
        'lib/features/itineraries/data/itinerary_draft_v2_repository.dart',
      ).readAsStringSync();
      expect(source, isNot(matches(r'\.(set|update|delete|add|snapshots)\(')));
      expect(source, isNot(contains('finalizations')));
      expect(source, isNot(contains('cloud_functions')));
      expect(source, isNot(contains('finalizeSupplierImport')));
      final dynamic dynamicRepository = repository;
      expect(() => dynamicRepository.createDraft(), throwsNoSuchMethodError);
      expect(() => dynamicRepository.updateDraft(), throwsNoSuchMethodError);
      expect(() => dynamicRepository.deleteDraft(), throwsNoSuchMethodError);
      expect(db.paths, isEmpty);
    },
  );
}

class _Firestore extends Fake implements FirebaseFirestore {
  Map<String, dynamic>? data = itineraryDraftV2Fixture();
  bool exists = true;
  String id = 'draft-1';
  Object? error;
  Future<void>? wait;
  final paths = <String>[];
  final options = <GetOptions?>[];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
}

// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.collectionPath);
  final _Firestore db;
  final String collectionPath;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Reference(db, '$collectionPath/$path');
}

// ignore: subtype_of_sealed_class
class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.db, this.documentPath);
  final _Firestore db;
  final String documentPath;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    db.paths.add(documentPath);
    db.options.add(options);
    if (db.error != null) throw db.error!;
    await db.wait;
    return _Snapshot(db.id, db.exists, db.data);
  }
}

// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.id, this.exists, this.value);
  @override
  final String id;
  @override
  final bool exists;
  final Map<String, dynamic>? value;
  @override
  Map<String, dynamic>? data() => value;
}
