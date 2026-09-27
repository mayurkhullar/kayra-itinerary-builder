import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Runs only against a local emulator and a demo project, never live Firebase.
// From the project root, with Java and the Firebase CLI already available:
// firebase emulators:exec --only firestore --project demo-kayra-itinerary-rules \
//   'KAYRA_RULES_EMULATOR=1 flutter test --no-pub test/itinerary_draft_rules_test.dart'
// The CLI loads this project's firestore.rules through firebase.json.
const _project = 'demo-kayra-itinerary-rules';
const _documents = 'projects/$_project/databases/(default)/documents';
const _draftPath = 'trips/trip-1/itinerary_drafts/draft-1';

void main() {
  group(
    'Itinerary Draft Firestore rules',
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
          _draftPath: _draft(),
        });
      });

      tearDown(() => emulator.close());

      test('Agent owner can create, read, list and update', () async {
        await emulator.createDraft(
          draftId: 'agent-created',
          data: _draft(createdByUid: 'agent-1'),
          uid: 'agent-1',
          allowed: true,
        );
        await emulator.expectRead(_draftPath, uid: 'agent-1', allowed: true);
        await emulator.expectRead(
          'trips/trip-1/itinerary_drafts',
          uid: 'agent-1',
          allowed: true,
        );
        await emulator.updateDraft(
          {'title': 'Updated by owner'},
          uid: 'agent-1',
          allowed: true,
        );
      });

      test('Agent non-owner is denied read', () async {
        await emulator.expectRead(_draftPath, uid: 'agent-2', allowed: false);
      });

      test('Agent non-owner is denied create', () async {
        await emulator.createDraft(
          draftId: 'non-owner-create',
          data: _draft(createdByUid: 'agent-2'),
          uid: 'agent-2',
          allowed: false,
        );
      });

      test('Agent non-owner is denied update', () async {
        await emulator.updateDraft(
          {'title': 'Unauthorized'},
          uid: 'agent-2',
          allowed: false,
        );
      });

      test('Admin can create, read, list and update', () async {
        await emulator.createDraft(
          draftId: 'admin-created',
          data: _draft(createdByUid: 'admin-1'),
          uid: 'admin-1',
          allowed: true,
        );
        await emulator.expectRead(_draftPath, uid: 'admin-1', allowed: true);
        await emulator.expectRead(
          'trips/trip-1/itinerary_drafts',
          uid: 'admin-1',
          allowed: true,
        );
        await emulator.updateDraft(
          {'title': 'Updated by Admin'},
          uid: 'admin-1',
          allowed: true,
        );
      });

      test('inactive Agent is denied create, read and update', () async {
        await emulator.createDraft(
          draftId: 'inactive-agent-create',
          data: _draft(createdByUid: 'inactive-agent'),
          uid: 'inactive-agent',
          allowed: false,
        );
        await emulator.expectRead(
          _draftPath,
          uid: 'inactive-agent',
          allowed: false,
        );
        await emulator.updateDraft(
          {'title': 'Inactive edit'},
          uid: 'inactive-agent',
          allowed: false,
        );
      });

      test('inactive Admin is denied create, read and update', () async {
        await emulator.createDraft(
          draftId: 'inactive-admin-create',
          data: _draft(createdByUid: 'inactive-admin'),
          uid: 'inactive-admin',
          allowed: false,
        );
        await emulator.expectRead(
          _draftPath,
          uid: 'inactive-admin',
          allowed: false,
        );
        await emulator.updateDraft(
          {'title': 'Inactive edit'},
          uid: 'inactive-admin',
          allowed: false,
        );
      });

      test('tripId mismatch is denied', () async {
        await emulator.createDraft(
          draftId: 'wrong-trip',
          data: _draft(tripId: 'trip-2', createdByUid: 'agent-1'),
          uid: 'agent-1',
          allowed: false,
        );
      });

      test('createdByUid spoof is denied on create', () async {
        await emulator.createDraft(
          draftId: 'spoofed-creator',
          data: _draft(createdByUid: 'admin-1'),
          uid: 'agent-1',
          allowed: false,
        );
      });

      test('createdByUid mutation is denied', () async {
        await emulator.updateDraft(
          {'createdByUid': 'admin-1'},
          uid: 'agent-1',
          allowed: false,
        );
      });

      test('createdAt mutation is denied', () async {
        await emulator.updateDraft(
          {'createdAt': DateTime.utc(2020)},
          uid: 'admin-1',
          allowed: false,
        );
      });

      test('Agent delete is denied', () async {
        await emulator.deleteDraft(uid: 'agent-1', allowed: false);
      });

      test('Admin delete is denied', () async {
        await emulator.deleteDraft(uid: 'admin-1', allowed: false);
      });

      test('unexpected top-level fields are denied', () async {
        await emulator.createDraft(
          draftId: 'unexpected-create',
          data: {
            ..._draft(createdByUid: 'agent-1'),
            'unexpected': true,
          },
          uid: 'agent-1',
          allowed: false,
        );
        await emulator.updateDraft(
          {'unexpected': true},
          uid: 'admin-1',
          allowed: false,
        );
      });

      test('missing parent Trip denies even Admin', () async {
        await emulator.seed({
          'trips/missing/itinerary_drafts/orphan': {
            ..._draft(tripId: 'missing'),
          },
        });
        await emulator.expectRead(
          'trips/missing/itinerary_drafts/orphan',
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

Map<String, Object?> _draft({
  String tripId = 'trip-1',
  String createdByUid = 'agent-1',
}) => {
  'tripId': tripId,
  'title': 'Dubai Escape',
  'days': <Object?>[],
  'sourcePackageIds': <Object?>[],
  'reviewIssues': <Object?>[],
  'createdByUid': createdByUid,
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

  Future<void> createDraft({
    required String draftId,
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
          'name': '$_documents/trips/trip-1/itinerary_drafts/$draftId',
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

  Future<void> updateDraft(
    Map<String, Object?> patch, {
    required String uid,
    required bool allowed,
  }) => expectCommit(
    {
      'update': {'name': '$_documents/$_draftPath', 'fields': _fields(patch)},
      'updateMask': {'fieldPaths': patch.keys.toList()},
      'updateTransforms': [_serverTime('updatedAt')],
      'currentDocument': {'exists': true},
    },
    uid: uid,
    allowed: allowed,
  );

  Future<void> deleteDraft({required String uid, required bool allowed}) =>
      expectCommit(
        {'delete': '$_documents/$_draftPath'},
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
