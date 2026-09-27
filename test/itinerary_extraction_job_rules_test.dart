import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Runs only against a local emulator and a demo project, never live Firebase.
// From the project root, with Java and the Firebase CLI already available:
// firebase emulators:exec --only firestore --project demo-kayra-extraction-job-rules \
//   'KAYRA_RULES_EMULATOR=1 flutter test --no-pub test/itinerary_extraction_job_rules_test.dart'
// The CLI loads this project's firestore.rules through firebase.json.
const _project = 'demo-kayra-extraction-job-rules';
const _documents = 'projects/$_project/databases/(default)/documents';
const _jobPath = 'trips/trip-1/itinerary_extraction_jobs/job-1';

void main() {
  group(
    'Itinerary Extraction Job Firestore rules',
    () {
      late _Emulator emulator;

      setUp(() async {
        emulator = _Emulator();
        await emulator.seed({
          'users/agent-1': {'role': 'agent', 'status': 'active'},
          'users/agent-2': {'role': 'agent', 'status': 'active'},
          'users/admin-1': {'role': 'admin', 'status': 'active'},
          'users/inactive-agent': {'role': 'agent', 'status': 'inactive'},
          'users/inactive-admin': {'role': 'admin', 'status': 'inactive'},
          'trips/trip-1': {'ownerUid': 'agent-1'},
          _jobPath: _job(),
        });
      });

      tearDown(() => emulator.close());

      test('active Agent owner can read', () async {
        await emulator.expectRead(_jobPath, uid: 'agent-1', allowed: true);
      });

      test('active Agent owner can list', () async {
        await emulator.expectRead(
          'trips/trip-1/itinerary_extraction_jobs',
          uid: 'agent-1',
          allowed: true,
        );
      });

      test('non-owner Agent is denied read and list', () async {
        await emulator.expectRead(_jobPath, uid: 'agent-2', allowed: false);
        await emulator.expectRead(
          'trips/trip-1/itinerary_extraction_jobs',
          uid: 'agent-2',
          allowed: false,
        );
      });

      test('active Admin can read and list', () async {
        await emulator.expectRead(_jobPath, uid: 'admin-1', allowed: true);
        await emulator.expectRead(
          'trips/trip-1/itinerary_extraction_jobs',
          uid: 'admin-1',
          allowed: true,
        );
      });

      test('inactive Agent is denied read', () async {
        await emulator.expectRead(
          _jobPath,
          uid: 'inactive-agent',
          allowed: false,
        );
      });

      test('inactive Admin is denied read', () async {
        await emulator.expectRead(
          _jobPath,
          uid: 'inactive-admin',
          allowed: false,
        );
      });

      test('Agent client create is denied', () async {
        await emulator.createJob(
          jobId: 'agent-created',
          data: _job(requestedByUid: 'agent-1'),
          uid: 'agent-1',
          allowed: false,
        );
      });

      test('Admin client create is denied', () async {
        await emulator.createJob(
          jobId: 'admin-created',
          data: _job(requestedByUid: 'admin-1'),
          uid: 'admin-1',
          allowed: false,
        );
      });

      test('Agent client update is denied', () async {
        await emulator.updateJob(
          {'status': 'processing'},
          uid: 'agent-1',
          allowed: false,
        );
      });

      test('Admin client update is denied', () async {
        await emulator.updateJob(
          {'status': 'processing'},
          uid: 'admin-1',
          allowed: false,
        );
      });

      test('Agent delete is denied', () async {
        await emulator.deleteJob(uid: 'agent-1', allowed: false);
      });

      test('Admin delete is denied', () async {
        await emulator.deleteJob(uid: 'admin-1', allowed: false);
      });

      test('missing parent Trip denies even Admin', () async {
        await emulator.seed({
          'trips/missing/itinerary_extraction_jobs/orphan': {
            ..._job(tripId: 'missing'),
          },
        });
        await emulator.expectRead(
          'trips/missing/itinerary_extraction_jobs/orphan',
          uid: 'admin-1',
          allowed: false,
        );
      });
    },
    skip: Platform.environment['KAYRA_RULES_EMULATOR'] != '1'
        ? 'Requires local Firestore emulator; see command in this file.'
        : false,
  );
}

Map<String, Object?> _job({
  String tripId = 'trip-1',
  String requestedByUid = 'agent-1',
}) => {
  'tripId': tripId,
  'sourcePackageId': 'package-1',
  'status': 'queued',
  'requestedByUid': requestedByUid,
  'resultingDraftId': null,
  'failureCode': null,
  'createdAt': DateTime.utc(2026, 9, 26, 8),
  'updatedAt': DateTime.utc(2026, 9, 26, 8),
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

Map<String, Object?> _serverTime(String field) => {
  'fieldPath': field,
  'setToServerValue': 'REQUEST_TIME',
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

  Future<void> createJob({
    required String jobId,
    required Map<String, Object?> data,
    required String uid,
    required bool allowed,
  }) {
    final fields = Map<String, Object?>.of(data)
      ..remove('createdAt')
      ..remove('updatedAt');
    return expectCommit(
      {
        'update': {
          'name': '$_documents/trips/trip-1/itinerary_extraction_jobs/$jobId',
          'fields': _fields(fields),
        },
        'currentDocument': {'exists': false},
        'updateTransforms': [
          _serverTime('createdAt'),
          _serverTime('updatedAt'),
        ],
      },
      uid: uid,
      allowed: allowed,
    );
  }

  Future<void> updateJob(
    Map<String, Object?> patch, {
    required String uid,
    required bool allowed,
  }) => expectCommit(
    {
      'update': {'name': '$_documents/$_jobPath', 'fields': _fields(patch)},
      'updateMask': {'fieldPaths': patch.keys.toList()},
      'updateTransforms': [_serverTime('updatedAt')],
      'currentDocument': {'exists': true},
    },
    uid: uid,
    allowed: allowed,
  );

  Future<void> deleteJob({required String uid, required bool allowed}) =>
      expectCommit(
        {'delete': '$_documents/$_jobPath'},
        uid: uid,
        allowed: allowed,
      );

  Future<void> expectCommit(
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

  Future<void> expectRead(
    String path, {
    required String uid,
    required bool allowed,
  }) async {
    final response = await _request(
      'GET',
      '/v1/$_documents/$path',
      token: _token(uid),
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

  // Unsigned mock tokens are accepted only by the local emulator.
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
