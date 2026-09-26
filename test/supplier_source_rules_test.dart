import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Runs only against a local emulator and a demo project, never live Firebase.
// From the project root, with Java and the Firebase CLI already available:
// firebase emulators:exec --only firestore --project demo-kayra-source-rules \
//   'KAYRA_RULES_EMULATOR=1 flutter test --no-pub test/supplier_source_rules_test.dart'
// The CLI loads this project's firestore.rules through firebase.json.
const _project = 'demo-kayra-source-rules';
const _documents = 'projects/$_project/databases/(default)/documents';
const _packagePath = 'trips/trip-1/supplier_source_packages/package-1';

void main() {
  group(
    'Supplier Source Firestore rules',
    () {
      late _Emulator emulator;

      setUp(() async {
        emulator = _Emulator();
        await emulator.seed({
          'users/agent-1': {'role': 'agent', 'status': 'active'},
          'users/agent-2': {'role': 'agent', 'status': 'active'},
          'users/admin-1': {'role': 'admin', 'status': 'active'},
          'trips/trip-1': {'ownerUid': 'agent-1'},
          _packagePath: _package('uploading'),
        });
      });
      tearDown(() => emulator.close());

      for (final status in ['uploading', 'uploaded', 'failed']) {
        test('create requires uploading, proposed $status', () async {
          final id = 'new-$status-${DateTime.now().microsecondsSinceEpoch}';
          final data = _package(status)
            ..remove('createdAt')
            ..remove('updatedAt');
          await emulator.expectCommit(
            {
              'update': {
                'name': '$_documents/trips/trip-1/supplier_source_packages/$id',
                'fields': _fields(data),
              },
              'currentDocument': {'exists': false},
              'updateTransforms': [
                _serverTime('createdAt'),
                _serverTime('updatedAt'),
              ],
            },
            uid: 'agent-1',
            allowed: status == 'uploading',
          );
        });
      }

      for (final uid in ['agent-1', 'admin-1']) {
        for (final initial in ['uploading', 'uploaded', 'failed']) {
          for (final target in ['uploading', 'uploaded', 'failed']) {
            test('$uid: $initial -> $target', () async {
              await emulator.seed({_packagePath: _package(initial)});
              await emulator.updatePackage(
                {
                  'status': target,
                  'fileIds': ['file-1', 'file-2'],
                },
                uid: uid,
                allowed:
                    initial == 'uploading' ||
                    (initial == 'uploaded' && target == 'uploaded'),
              );
            });
          }
        }
      }

      test('in-progress metadata edit can omit status', () async {
        await emulator.updatePackage(
          {
            'fileIds': ['file-2', 'file-1'],
          },
          uid: 'agent-1',
          allowed: true,
        );
      });
      test('uploaded metadata edit keeps status and non-empty files', () async {
        await emulator.seed({_packagePath: _package('uploaded')});
        await emulator.updatePackage(
          {
            'fileIds': ['file-2', 'file-1'],
          },
          uid: 'agent-1',
          allowed: true,
        );
        await emulator.updatePackage(
          {'fileIds': []},
          uid: 'agent-1',
          allowed: false,
        );
      });
      test(
        'failed package rejects metadata-only edits and timestamp-only writes',
        () async {
          await emulator.seed({_packagePath: _package('failed')});
          await emulator.updatePackage(
            {
              'fileIds': ['file-2'],
            },
            uid: 'admin-1',
            allowed: false,
          );
          await emulator.expectCommit(
            {
              'transform': {
                'document': '$_documents/$_packagePath',
                'fieldTransforms': [_serverTime('updatedAt')],
              },
            },
            uid: 'agent-1',
            allowed: false,
          );
        },
      );
      test('upload completion requires a non-empty file list', () async {
        await emulator.updatePackage(
          {'status': 'uploaded', 'fileIds': []},
          uid: 'agent-1',
          allowed: false,
        );
      });
      test('immutable fields and unexpected fields remain protected', () async {
        for (final patch in <Map<String, Object?>>[
          {'tripId': 'trip-2'},
          {'uploadedByUid': 'admin-1'},
          {'createdAt': DateTime.utc(2020)},
          {'unexpected': true},
          {'status': 'retrying'},
        ]) {
          await emulator.updatePackage(patch, uid: 'admin-1', allowed: false);
        }
      });
      test(
        'owner and Admin retain read/list/update access; others are denied',
        () async {
          for (final uid in ['agent-1', 'admin-1', 'agent-2', null]) {
            final allowed = uid == 'agent-1' || uid == 'admin-1';
            await emulator.expectRead(_packagePath, uid: uid, allowed: allowed);
            await emulator.expectRead(
              'trips/trip-1/supplier_source_packages',
              uid: uid,
              allowed: allowed,
            );
            await emulator.updatePackage(
              {
                'fileIds': ['file-1'],
              },
              uid: uid,
              allowed: allowed,
            );
          }
        },
      );
      test(
        'inactive users, outside-domain users and missing profiles are denied',
        () async {
          await emulator.seed({
            'users/agent-1': {'role': 'agent', 'status': 'inactive'},
            'users/admin-1': {'role': 'admin', 'status': 'inactive'},
          });
          for (final uid in ['agent-1', 'admin-1', 'missing-profile']) {
            await emulator.expectRead(_packagePath, uid: uid, allowed: false);
            await emulator.updatePackage(
              {
                'status': 'uploaded',
                'fileIds': ['file-1'],
              },
              uid: uid,
              allowed: false,
            );
          }
          await emulator.seed({
            'users/agent-1': {'role': 'agent', 'status': 'active'},
          });
          await emulator.expectRead(
            _packagePath,
            uid: 'agent-1',
            email: 'agent-1@example.com',
            allowed: false,
          );
        },
      );
      test(
        'ownership transfer revokes previous owner and permits current owner',
        () async {
          await emulator.seed({
            'trips/trip-1': {'ownerUid': 'agent-2'},
          });
          for (final uid in ['agent-1', 'agent-2', 'admin-1']) {
            await emulator.expectRead(
              _packagePath,
              uid: uid,
              allowed: uid != 'agent-1',
            );
            await emulator.updatePackage(
              {
                'fileIds': ['file-1'],
              },
              uid: uid,
              allowed: uid != 'agent-1',
            );
          }
        },
      );
      test(
        'missing parent Trip denies even Admin and deletion remains forbidden',
        () async {
          await emulator.expectCommit(
            {'delete': '$_documents/$_packagePath'},
            uid: 'admin-1',
            allowed: false,
          );
          await emulator.seed({
            'trips/missing/supplier_source_packages/orphan': {
              ..._package('uploading'),
              'tripId': 'missing',
            },
          });
          await emulator.expectRead(
            'trips/missing/supplier_source_packages/orphan',
            uid: 'admin-1',
            allowed: false,
          );
        },
      );
    },
    skip: Platform.environment['KAYRA_RULES_EMULATOR'] != '1'
        ? 'Requires local Firestore emulator; see command in this file.'
        : false,
  );
}

Map<String, Object?> _package(String status) => {
  'tripId': 'trip-1',
  'supplierId': null,
  'supplierNameSnapshot': null,
  'fileIds': status == 'uploaded' ? ['file-1'] : <String>[],
  'uploadedByUid': 'agent-1',
  'status': status,
  'createdAt': DateTime.utc(2026, 9, 25),
  'updatedAt': DateTime.utc(2026, 9, 25),
};

Map<String, Object?> _fields(Map<String, Object?> data) =>
    data.map((key, value) => MapEntry(key, _value(value)));

Map<String, Object?> _value(Object? value) => switch (value) {
  null => {'nullValue': null},
  String value => {'stringValue': value},
  bool value => {'booleanValue': value},
  DateTime value => {'timestampValue': value.toUtc().toIso8601String()},
  List value => {
    'arrayValue': {'values': value.map(_value).toList()},
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

  Future<void> updatePackage(
    Map<String, Object?> patch, {
    required String? uid,
    required bool allowed,
  }) => expectCommit(
    {
      'update': {'name': '$_documents/$_packagePath', 'fields': _fields(patch)},
      'updateMask': {'fieldPaths': patch.keys.toList()},
      'updateTransforms': [_serverTime('updatedAt')],
      'currentDocument': {'exists': true},
    },
    uid: uid,
    allowed: allowed,
  );

  Future<void> expectCommit(
    Map<String, Object?> write, {
    required String? uid,
    required bool allowed,
  }) async {
    final response = await _request(
      'POST',
      '/v1/$_documents:commit',
      token: uid == null ? null : _token(uid),
      body: {
        'writes': [write],
      },
    );
    expect(response.status, allowed ? 200 : 403, reason: response.body);
  }

  Future<void> expectRead(
    String path, {
    required String? uid,
    required bool allowed,
    String? email,
  }) async {
    final response = await _request(
      'GET',
      '/v1/$_documents/$path',
      token: uid == null ? null : _token(uid, email: email),
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

  // Unsigned mock token is accepted only by the local emulator.
  String _token(String uid, {String? email}) {
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
      'email': email ?? '$uid@kholidaymaps.com',
      'firebase': {'sign_in_provider': 'custom', 'identities': <String, Object?>{}},
    })}.';
  }
}
