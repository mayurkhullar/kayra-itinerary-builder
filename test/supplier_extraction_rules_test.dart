import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Runs only against a local emulator and a demo project, never live Firebase.
// From the project root, with Java and the Firebase CLI already available:
// firebase emulators:exec --only firestore --project demo-kayra-supplier-extraction-rules \
//   'KAYRA_RULES_EMULATOR=1 flutter test --no-pub test/supplier_extraction_rules_test.dart'
const _project = 'demo-kayra-supplier-extraction-rules';
const _documents = 'projects/$_project/databases/(default)/documents';
const _root = 'trips/trip-1/supplier_extractions/extraction-1';
const _day = '$_root/days/staged-day-1';
const _fact = '$_root/facts/staged-service-1';
const _issue = '$_root/review_issues/review-1';
const _resolution = '$_root/resolutions/resolution-1';

void main() {
  group(
    'Supplier Extraction Firestore rules',
    () {
      late _Emulator emulator;

      setUp(() async {
        emulator = _Emulator();
        await emulator.seed({
          'users/agent-1': {'role': 'agent', 'status': 'active'},
          'users/agent-2': {'role': 'agent', 'status': 'active'},
          'users/admin-1': {'role': 'admin', 'status': 'active'},
          'users/inactive-agent': {'role': 'agent', 'status': 'inactive'},
          'trips/trip-1': {'ownerUid': 'agent-1'},
          _root: _extraction(),
          _day: _child('staged-day-1'),
          _fact: _child('staged-service-1'),
          _issue: _child('review-1'),
          _resolution: {'status': 'draft'},
          'trips/trip-1/supplier_extractions/writing': _extraction(
            extractionId: 'writing',
            persistenceState: 'writing',
          ),
          'trips/trip-1/supplier_extractions/writing/days/staged-day-1': _child(
            'staged-day-1',
          ),
        });
      });

      tearDown(() => emulator.close());

      test('owning active Agent can read root and machine children', () async {
        for (final path in [_root, _day, _fact, _issue]) {
          await emulator.expectRead(path, uid: 'agent-1', allowed: true);
        }
        for (final path in [
          '$_root/days',
          '$_root/facts',
          '$_root/review_issues',
        ]) {
          await emulator.expectRead(path, uid: 'agent-1', allowed: true);
        }
        await emulator.expectRead(
          'trips/trip-1/supplier_extractions',
          uid: 'agent-1',
          allowed: false,
        );
      });

      test('active Admin can read root and machine children', () async {
        for (final path in [_root, _day, _fact, _issue]) {
          await emulator.expectRead(path, uid: 'admin-1', allowed: true);
        }
      });

      test('another Agent cannot read root or children', () async {
        for (final path in [_root, _day, _fact, _issue]) {
          await emulator.expectRead(path, uid: 'agent-2', allowed: false);
        }
      });

      test('unauthenticated and inactive users cannot read', () async {
        await emulator.expectRead(_root, uid: null, allowed: false);
        await emulator.expectRead(_root, uid: 'inactive-agent', allowed: false);
      });

      test('writing snapshot and its children remain invisible', () async {
        await emulator.expectRead(
          'trips/trip-1/supplier_extractions/writing',
          uid: 'agent-1',
          allowed: false,
        );
        await emulator.expectRead(
          'trips/trip-1/supplier_extractions/writing/days/staged-day-1',
          uid: 'admin-1',
          allowed: false,
        );
      });

      test('direct root create, update and delete are denied', () async {
        await emulator.expectCreate(
          'trips/trip-1/supplier_extractions/client-created',
          _extraction(extractionId: 'client-created'),
          uid: 'agent-1',
          allowed: false,
        );
        await emulator.expectUpdate(
          _root,
          {'persistenceState': 'writing'},
          uid: 'admin-1',
          allowed: false,
        );
        await emulator.expectDelete(_root, uid: 'agent-1', allowed: false);
      });

      test('direct child create, update and delete are denied', () async {
        await emulator.expectCreate(
          '$_root/facts/client-fact',
          _child('client-fact'),
          uid: 'agent-1',
          allowed: false,
        );
        await emulator.expectUpdate(
          _fact,
          {'snapshotOrder': 2},
          uid: 'admin-1',
          allowed: false,
        );
        await emulator.expectDelete(_issue, uid: 'admin-1', allowed: false);
      });

      test('reserved resolutions namespace denies reads and writes', () async {
        await emulator.expectRead(_resolution, uid: 'admin-1', allowed: false);
        await emulator.expectCreate(
          '$_root/resolutions/client-created',
          {'status': 'draft'},
          uid: 'agent-1',
          allowed: false,
        );
      });
    },
    skip: Platform.environment['KAYRA_RULES_EMULATOR'] != '1'
        ? 'Requires local Firestore emulator; see command in this file.'
        : false,
  );
}

Map<String, Object?> _extraction({
  String extractionId = 'extraction-1',
  String persistenceState = 'complete',
}) => {
  'persistenceState': persistenceState,
  'schemaVersion': 'supplier_extraction_snapshot_v1',
  'extractionId': extractionId,
  'tripId': 'trip-1',
  'sourcePackageId': 'package-1',
  'jobId': 'job-1',
  'requestedByUid': 'agent-1',
  'createdAt': DateTime.utc(2026, 9, 29),
  'providerVersion': 'kayra_itinerary_extraction_v3_staging',
  'title': {'text': 'Synthetic itinerary'},
  'counts': {'days': 1},
};

Map<String, Object?> _child(String id) => {
  'snapshotOrder': 1,
  'value': {'id': id},
};

Map<String, Object?> _fields(Map<String, Object?> data) =>
    data.map((key, value) => MapEntry(key, _value(value)));

Map<String, Object?> _value(Object? value) => switch (value) {
  null => {'nullValue': null},
  String value => {'stringValue': value},
  bool value => {'booleanValue': value},
  int value => {'integerValue': '$value'},
  DateTime value => {'timestampValue': value.toUtc().toIso8601String()},
  List value => {
    'arrayValue': {'values': value.map(_value).toList()},
  },
  Map value => {
    'mapValue': {'fields': _fields(Map<String, Object?>.from(value))},
  },
  _ => throw ArgumentError('Unsupported emulator fixture value.'),
};

class _Emulator {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  void close() => _client.close(force: true);

  Future<void> seed(Map<String, Map<String, Object?>> records) async {
    final response = await _request(
      'POST',
      '/v1/$_documents:commit',
      token: 'owner',
      body: {
        'writes': records.entries
            .map(
              (entry) => {
                'update': {
                  'name': '$_documents/${entry.key}',
                  'fields': _fields(entry.value),
                },
              },
            )
            .toList(),
      },
    );
    expect(response.status, 200, reason: response.body);
  }

  Future<void> expectRead(
    String path, {
    required String? uid,
    required bool allowed,
  }) async {
    final response = await _request(
      'GET',
      '/v1/$_documents/$path',
      token: uid == null ? null : _token(uid),
    );
    expect(response.status, allowed ? 200 : 403, reason: response.body);
  }

  Future<void> expectCreate(
    String path,
    Map<String, Object?> data, {
    required String uid,
    required bool allowed,
  }) => _expectCommit(
    {
      'update': {'name': '$_documents/$path', 'fields': _fields(data)},
      'currentDocument': {'exists': false},
    },
    uid: uid,
    allowed: allowed,
  );

  Future<void> expectUpdate(
    String path,
    Map<String, Object?> patch, {
    required String uid,
    required bool allowed,
  }) => _expectCommit(
    {
      'update': {'name': '$_documents/$path', 'fields': _fields(patch)},
      'updateMask': {'fieldPaths': patch.keys.toList()},
      'currentDocument': {'exists': true},
    },
    uid: uid,
    allowed: allowed,
  );

  Future<void> expectDelete(
    String path, {
    required String uid,
    required bool allowed,
  }) => _expectCommit(
    {'delete': '$_documents/$path'},
    uid: uid,
    allowed: allowed,
  );

  Future<void> _expectCommit(
    Map<String, Object?> write, {
    required String uid,
    required bool allowed,
  }) async {
    final response = await _request(
      'POST',
      '/v1/$_documents:commit',
      token: _token(uid),
      body: {
        'writes': [write],
      },
    );
    expect(response.status, allowed ? 200 : 403, reason: response.body);
  }

  Future<({int status, String body})> _request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    final request = await _client.openUrl(
      method,
      Uri.http('127.0.0.1:8080', path),
    );
    request.followRedirects = false;
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  String _token(String uid) {
    String encode(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode({
      'sub': uid,
      'user_id': uid,
      'aud': _project,
      'iss': 'https://securetoken.google.com/$_project',
      'iat': now,
      'auth_time': now,
      'exp': now + 3600,
      'email': '$uid@kholidaymaps.com',
      'firebase': {'sign_in_provider': 'custom', 'identities': <String, Object?>{}},
    })}.';
  }
}
