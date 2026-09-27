import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_draft_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_day.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_details.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_draft.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_review_issue.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_service.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_repository.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';

const _drafts = 'trips/trip-1/itinerary_drafts';
final _createdAt = DateTime.utc(2026, 9, 26, 8);
final _updatedAt = DateTime.utc(2026, 9, 26, 9);

KayraItineraryService _hotelService() => KayraItineraryService(
  id: 'hotel-1',
  type: KayraItineraryServiceType.hotel,
  title: 'Hotel stay',
  inclusions: ['Breakfast'],
  hotelDetails: KayraItineraryHotelDetails(
    hotelName: 'Example Hotel',
    checkInDate: DateTime.utc(2027, 1, 10),
    checkOutDate: DateTime.utc(2027, 1, 12),
    numberOfRooms: 1,
  ),
  sourceReference: KayraItinerarySourceReference(
    supplierSourcePackageId: 'package-1',
    supplierSourceFileId: 'file-1',
  ),
);

KayraItineraryDay _day({int number = 1, String title = 'Arrival'}) =>
    KayraItineraryDay(
      dayNumber: number,
      date: DateTime.utc(2027, 1, 9 + number),
      title: title,
      services: [_hotelService()],
    );

KayraItineraryReviewIssue _issue({
  String id = 'issue-1',
  KayraItineraryReviewSeverity severity = KayraItineraryReviewSeverity.warning,
}) => KayraItineraryReviewIssue(
  id: id,
  fieldPath: 'days[0].services[0].startTime',
  message: 'Confirm time.',
  severity: severity,
);

KayraItineraryDraft _draft({
  String id = 'draft-1',
  String tripId = 'trip-1',
  String title = 'Dubai Escape',
  List<KayraItineraryDay>? days,
  List<String> sourcePackageIds = const ['package-1'],
  List<KayraItineraryReviewIssue>? reviewIssues,
  String createdByUid = 'agent-1',
  DateTime? createdAt,
  DateTime? updatedAt,
}) => KayraItineraryDraft(
  id: id,
  tripId: tripId,
  title: title,
  days: days ?? [_day()],
  sourcePackageIds: sourcePackageIds,
  reviewIssues: reviewIssues ?? [_issue()],
  createdByUid: createdByUid,
  createdAt: createdAt ?? _createdAt,
  updatedAt: updatedAt ?? _updatedAt,
);

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
  KayraItineraryDraft? draft,
  DateTime? createdAt,
}) {
  final model = draft ?? _draft();
  final data = _toFirestoreMap(model.toMap());
  if (createdAt != null) {
    data['createdAt'] = Timestamp.fromDate(createdAt);
  }
  return data;
}

void main() {
  late _FakeFirestore firestore;
  late _Sources sources;
  late FirestoreItineraryDraftRepository repository;

  setUp(() {
    firestore = _FakeFirestore();
    sources = _Sources()..packages['package-1'] = _package();
    repository = FirestoreItineraryDraftRepository(
      firestore: firestore,
      sourceRepository: sources,
    );
  });

  test(
    'create allocates ID and persists a valid model with server audit times',
    () async {
      final id = await repository.createDraft(
        tripId: 'trip-1',
        title: ' Dubai Escape ',
        days: [_day()],
        sourcePackageIds: [' package-1 ', 'package-1'],
        reviewIssues: [_issue()],
        currentUserUid: 'agent-1',
      );

      expect(id, 'generated-1');
      expect(firestore.requestedIds, [null]);
      expect(firestore.sets.single.path, '$_drafts/generated-1');
      expect(sources.reads, [(tripId: 'trip-1', packageId: 'package-1')]);
      final payload = firestore.sets.single.data;
      expect(payload['tripId'], 'trip-1');
      expect(payload['title'], 'Dubai Escape');
      expect(payload['sourcePackageIds'], ['package-1']);
      expect(payload['createdByUid'], 'agent-1');
      expect(payload['createdAt'], FieldValue.serverTimestamp());
      expect(payload['updatedAt'], FieldValue.serverTimestamp());
      expect(
        ((payload['days'] as List).single as Map)['date'],
        isA<Timestamp>(),
      );
      expect(
        (((((payload['days'] as List).single as Map)['services'] as List).single
                as Map)['hotelDetails']
            as Map)['checkInDate'],
        isA<Timestamp>(),
      );

      firestore.documents['$_drafts/generated-1'] = Map.of(payload)
        ..['createdAt'] = Timestamp.fromDate(_createdAt)
        ..['updatedAt'] = Timestamp.fromDate(_createdAt);
      final persisted = await repository.getDraft('trip-1', id);
      expect(persisted!.id, id);
      expect(persisted.tripId, 'trip-1');
      expect(persisted.title, 'Dubai Escape');
      expect(
        persisted.days.single.services.single.hotelDetails?.hotelName,
        'Example Hotel',
      );
      expect(persisted.sourcePackageIds, ['package-1']);
      expect(persisted.reviewIssues.single.id, 'issue-1');
    },
  );

  test('get round trips nested dates and missing draft returns null', () async {
    firestore.documents['$_drafts/draft-1'] = _record();
    final draft = await repository.getDraft('trip-1', 'draft-1');
    expect(draft!.toMap(), _draft().toMap());
    expect(draft.days.single.date, DateTime.utc(2027, 1, 10));
    expect(
      draft.days.single.services.single.hotelDetails?.checkOutDate,
      DateTime.utc(2027, 1, 12),
    );
    expect(await repository.getDraft('trip-1', 'missing'), isNull);
    expect(
      firestore.readOptions.every(
        (options) => options?.source == Source.server,
      ),
      isTrue,
    );
  });

  test('list scopes to one Trip and orders createdAt ascending', () async {
    firestore.documents.addAll({
      '$_drafts/later': _record(
        draft: _draft(id: 'later'),
        createdAt: DateTime.utc(2026, 9, 28),
      ),
      '$_drafts/earlier': _record(
        draft: _draft(id: 'earlier'),
        createdAt: DateTime.utc(2026, 9, 20),
      ),
      'trips/trip-2/itinerary_drafts/other': _record(
        draft: _draft(id: 'other', tripId: 'trip-2'),
      ),
    });

    final drafts = await repository.listDraftsForTrip('trip-1');
    expect(drafts.map((draft) => draft.id), ['earlier', 'later']);
    expect(firestore.orderFields, ['createdAt']);
    expect(firestore.collections.single, _drafts);
    expect(() => drafts.clear(), throwsUnsupportedError);
  });

  test(
    'update replaces editable content and preserves identity and creation data',
    () async {
      final original = _record();
      firestore.documents['$_drafts/draft-1'] = Map.of(original);
      sources.packages['package-2'] = _package(id: 'package-2');
      final replacement = _draft(
        title: 'Revised Dubai Escape',
        days: [_day(number: 2, title: 'Desert Safari')],
        sourcePackageIds: ['package-2'],
        reviewIssues: [
          _issue(
            id: 'blocker-1',
            severity: KayraItineraryReviewSeverity.blocker,
          ),
        ],
        updatedAt: DateTime.utc(2026, 9, 27),
      );

      await repository.updateDraft(tripId: 'trip-1', draft: replacement);

      expect(firestore.updates.single.path, '$_drafts/draft-1');
      expect(firestore.updates.single.data.keys, {
        'title',
        'days',
        'sourcePackageIds',
        'reviewIssues',
        'updatedAt',
      });
      expect(firestore.updates.single.data['title'], 'Revised Dubai Escape');
      expect(firestore.updates.single.data['sourcePackageIds'], ['package-2']);
      expect(
        ((firestore.updates.single.data['reviewIssues'] as List).single
            as Map)['severity'],
        'blocker',
      );
      expect(
        firestore.documents['$_drafts/draft-1']!['tripId'],
        original['tripId'],
      );
      expect(
        firestore.documents['$_drafts/draft-1']!['createdByUid'],
        original['createdByUid'],
      );
      expect(
        firestore.documents['$_drafts/draft-1']!['createdAt'],
        original['createdAt'],
      );
      expect(firestore.sets, isEmpty);
    },
  );

  test('update rejects moving a draft between Trips', () async {
    await expectLater(
      repository.updateDraft(
        tripId: 'trip-1',
        draft: _draft(tripId: 'trip-2'),
      ),
      throwsFormatException,
    );
    expect(firestore.readOptions, isEmpty);
    expect(firestore.updates, isEmpty);
  });

  test('update rejects createdByUid mutation', () async {
    firestore.documents['$_drafts/draft-1'] = _record();
    await expectLater(
      repository.updateDraft(
        tripId: 'trip-1',
        draft: _draft(createdByUid: 'agent-2'),
      ),
      throwsFormatException,
    );
    expect(firestore.updates, isEmpty);
  });

  test('update rejects createdAt mutation', () async {
    firestore.documents['$_drafts/draft-1'] = _record();
    await expectLater(
      repository.updateDraft(
        tripId: 'trip-1',
        draft: _draft(createdAt: DateTime.utc(2026, 9, 25)),
      ),
      throwsFormatException,
    );
    expect(firestore.updates, isEmpty);
  });

  test('empty sourcePackageIds are allowed without source reads', () async {
    await repository.createDraft(
      tripId: 'trip-1',
      title: 'Manual itinerary',
      sourcePackageIds: const [],
      currentUserUid: 'agent-1',
    );
    expect(sources.reads, isEmpty);
    expect(firestore.sets.single.data['sourcePackageIds'], isEmpty);
  });

  for (final status in [
    SupplierSourcePackageStatus.uploading,
    SupplierSourcePackageStatus.failed,
  ]) {
    test('${status.value} source package is rejected', () async {
      sources.packages['package-1'] = _package(status: status);
      await expectLater(
        repository.createDraft(
          tripId: 'trip-1',
          title: 'Draft',
          sourcePackageIds: const ['package-1'],
          currentUserUid: 'agent-1',
        ),
        throwsFormatException,
      );
      expect(firestore.sets, isEmpty);
    });
  }

  for (final status in [
    SupplierSourcePackageStatus.uploading,
    SupplierSourcePackageStatus.failed,
  ]) {
    test('update rejects a ${status.value} source package', () async {
      firestore.documents['$_drafts/draft-1'] = _record();
      sources.packages['package-1'] = _package(status: status);
      await expectLater(
        repository.updateDraft(tripId: 'trip-1', draft: _draft()),
        throwsFormatException,
      );
      expect(firestore.updates, isEmpty);
    });
  }

  test('missing source package is rejected', () async {
    sources.packages.clear();
    await expectLater(
      repository.createDraft(
        tripId: 'trip-1',
        title: 'Draft',
        sourcePackageIds: const ['missing'],
        currentUserUid: 'agent-1',
      ),
      throwsFormatException,
    );
    expect(firestore.sets, isEmpty);
  });

  test('source package from another Trip is rejected', () async {
    sources.packages['package-1'] = _package(tripId: 'trip-2');
    await expectLater(
      repository.createDraft(
        tripId: 'trip-1',
        title: 'Draft',
        sourcePackageIds: const ['package-1'],
        currentUserUid: 'agent-1',
      ),
      throwsFormatException,
    );
    expect(firestore.sets, isEmpty);
  });

  test('malformed persisted itinerary fails domain deserialization', () async {
    for (final data in [
      _record()..remove('title'),
      {..._record(), 'tripId': 'trip-2'},
      {..._record(), 'days': 'not-a-list'},
      {
        ..._record(),
        'reviewIssues': [
          {
            'id': 'issue-1',
            'fieldPath': 'days[0]',
            'message': '',
            'severity': 'warning',
          },
        ],
      },
      {..._record(), 'createdAt': DateTime.utc(2026)},
    ]) {
      firestore.documents['$_drafts/bad'] = data;
      await expectLater(
        repository.getDraft('trip-1', 'bad'),
        throwsFormatException,
      );
    }
  });

  test('missing draft is never upserted by update', () async {
    await expectLater(
      repository.updateDraft(tripId: 'trip-1', draft: _draft()),
      throwsStateError,
    );
    expect(firestore.sets, isEmpty);
    expect(firestore.updates, isEmpty);
  });

  test('repository exposes no delete API', () {
    final dynamic dynamicRepository = repository;
    expect(
      () => dynamicRepository.deleteDraft('trip-1', 'draft-1'),
      throwsNoSuchMethodError,
    );
    expect(firestore.collections, isEmpty);
  });

  testWidgets('bounds stalled get and list reads', (tester) async {
    final pending = Completer<void>();
    firestore.readWait = pending.future;
    final assertions = [
      expectLater(
        repository.getDraft('trip-1', 'draft-1'),
        throwsA(isA<TimeoutException>()),
      ),
      expectLater(
        repository.listDraftsForTrip('trip-1'),
        throwsA(isA<TimeoutException>()),
      ),
    ];
    await tester.pump(const Duration(seconds: 30));
    await Future.wait(assertions);
    pending.complete();
    await tester.pump();
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
  final collections = <String>[];
  final requestedIds = <String?>[];
  final sets = <({String path, Map<String, dynamic> data})>[];
  final updates = <({String path, Map<String, dynamic> data})>[];
  final readOptions = <GetOptions?>[];
  final orderFields = <Object>[];
  Future<void>? readWait;
  Object? error;
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
    Object? orderBy,
    bool descending = false,
  }) async {
    await beforeRead(options);
    final entries = documents.entries
        .where(
          (entry) =>
              entry.key.startsWith('$path/') &&
              !entry.key.substring(path.length + 1).contains('/'),
        )
        .toList();
    if (orderBy != null) {
      entries.sort((left, right) {
        final leftValue = left.value[orderBy];
        final rightValue = right.value[orderBy];
        if (leftValue is! Timestamp || rightValue is! Timestamp) {
          throw const FormatException('Invalid ordered timestamp.');
        }
        final comparison = leftValue.compareTo(rightValue);
        return descending ? -comparison : comparison;
      });
    }
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
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    firestore.orderFields.add(field);
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
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      firestore.query(path, options, orderBy: field, descending: descending);
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
    final converted = Map<String, dynamic>.from(data);
    firestore.updates.add((path: path, data: converted));
    firestore.documents[path]!.addAll(converted);
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
