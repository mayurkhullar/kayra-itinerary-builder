import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_finalization_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_draft_v2.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_finalization.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';

import 'support/supplier_import_finalization_fixture.dart';

void main() {
  test(
    'request has exactly five fields and uses authoritative policy literal',
    () {
      expect(finalizationRequest().toMap(), {
        'tripId': 'trip-1',
        'extractionId': 'extraction-1',
        'commandId': 'intent-1',
        'expectedRevision': 2,
        'policyVersion': 'supplier_import_optional_chronology_v2',
      });
      expect(
        File(
          'functions/src/itineraryExtraction/itineraryDraftV2.ts',
        ).readAsStringSync(),
        contains('"$optionalChronologyImportPolicy"'),
      );
      final body = finalizationRequest().toMap()..clear();
      expect(body, isEmpty);
      expect(finalizationRequest().toMap(), hasLength(5));
    },
  );
  for (final revision in [0, -1, 9007199254740991, 9007199254740992]) {
    test(
      'invalid request revision $revision rejected',
      () => expect(
        () => finalizationRequest(revision: revision),
        throwsFormatException,
      ),
    );
  }
  for (final field in ['tripId', 'extractionId', 'commandId']) {
    for (final value in [
      '',
      ' padded',
      'padded ',
      '.',
      '..',
      'bad/path',
      r'bad\path',
      'bad\nvalue',
      'x' * 257,
    ]) {
      test('strict request $field rejects ${jsonEncode(value)}', () {
        expect(
          () => SupplierImportFinalizationRequest(
            tripId: field == 'tripId' ? value : 'trip-1',
            extractionId: field == 'extractionId' ? value : 'extraction-1',
            commandId: field == 'commandId' ? value : 'command-1',
            expectedRevision: 1,
          ),
          throwsFormatException,
        );
      });
    }
  }
  test('command max and policy rejected without normalization', () {
    expect(
      () => finalizationRequest(commandId: 'x' * 129),
      throwsFormatException,
    );
    expect(
      () => SupplierImportFinalizationRequest(
        tripId: 't',
        extractionId: 'e',
        commandId: 'c',
        expectedRevision: 1,
        policyVersion: 'future',
      ),
      throwsFormatException,
    );
    expect(finalizationRequest(commandId: 'A' * 128).commandId, 'A' * 128);
  });
  test('reuses secure URL-safe command generator', () {
    final generator = SupplierImportCommandIdGenerator();
    final ids = List.generate(40, (_) => generator.generate());
    expect(ids.toSet(), hasLength(40));
    for (final id in ids) {
      expect(id, matches(r'^[A-Za-z0-9_-]{24}$'));
    }
    expect(
      File(
        'lib/features/itineraries/domain/supplier_import_resolution_mutation.dart',
      ).readAsStringSync(),
      contains('Random.secure()'),
    );
  });
  for (final name in finalizationOutcomes) {
    test('$name strictly parses its exact safe union member', () {
      final result = SupplierImportFinalizationOutcome.fromMap(
        finalizationResponse(name),
      );
      expect(result.resolutionId, 'extraction-1');
      switch (result) {
        case SupplierImportFinalizationSuccess():
          expect(result.revision, 3);
          expect(result.resultingDraftId, 'draft-1');
          expect(result.alreadyApplied, name == 'already_applied');
        case SupplierImportFinalizationNotReady():
          expect(
            result.blockers.single.code,
            SupplierImportFinalizationBlockerCode.unresolvedUnassignedService,
          );
          expect(
            result.warnings.single.code,
            SupplierImportFinalizationWarningCode.snapshotWarningOpen,
          );
          expect(result.evaluatedRevision, 2);
          expect(result.canFinalize, isFalse);
        case SupplierImportFinalizationConflict():
          expect(result.currentRevision, 3);
        case SupplierImportFinalizationNotStarted():
          expect(result.revision, 0);
        case SupplierImportFinalizationFinalized():
          expect(result.revision, 3);
        case SupplierImportFinalizationCapacityExceeded():
          expect(
            result.boundary,
            SupplierImportFinalizationCapacityBoundary.receipt,
          );
      }
    });
    for (final private in ['receipt', 'candidate']) {
      test(
        '$name rejects extra $private',
        () => expect(
          () => SupplierImportFinalizationOutcome.fromMap({
            ...finalizationResponse(name),
            private: 'PRIVATE',
          }),
          throwsFormatException,
        ),
      );
    }
  }
  for (final mutation in <String, void Function(Map<String, Object?>)>{
    'unknown outcome': (m) => m['outcome'] = 'future',
    'wrong revision type': (m) => m['revision'] = '3',
    'missing draft': (m) => m.remove('resultingDraftId'),
    'revision zero': (m) => m['revision'] = 0,
    'unsafe revision': (m) => m['revision'] = 9007199254740992,
    'invalid identity': (m) => m['resolutionId'] = ' padded',
  }.entries) {
    test(mutation.key, () {
      final m = finalizationResponse('applied');
      mutation.value(m);
      expect(
        () => SupplierImportFinalizationOutcome.fromMap(m),
        throwsFormatException,
      );
    });
  }
  for (final bad in ['code', 'targetKind', 'targetId', 'message']) {
    test('finding rejects malformed or private $bad', () {
      final m = finalizationResponse('not_ready');
      final a = m['assessment'] as Map;
      final b = (a['blockers'] as List).single as Map;
      b[bad] = bad == 'targetId' ? 'bad/path' : 'PRIVATE';
      expect(
        () => SupplierImportFinalizationOutcome.fromMap(m),
        throwsFormatException,
      );
    });
  }
  test('not-ready lists detached immutable and reject private assessment', () {
    final m = finalizationResponse('not_ready');
    final value =
        SupplierImportFinalizationOutcome.fromMap(m)
            as SupplierImportFinalizationNotReady;
    ((m['assessment'] as Map)['blockers'] as List).clear();
    expect(value.blockers, hasLength(1));
    expect(() => value.blockers.clear(), throwsUnsupportedError);
    expect(() => value.warnings.clear(), throwsUnsupportedError);
    (m['assessment'] as Map)['receipt'] = 'private';
    expect(
      () => SupplierImportFinalizationOutcome.fromMap(m),
      throwsFormatException,
    );
  });
  for (final boundary in SupplierImportFinalizationCapacityBoundary.values) {
    test(
      'capacity boundary ${boundary.value}',
      () => expect(
        (SupplierImportFinalizationOutcome.fromMap({
                  ...finalizationResponse('persistence_capacity_exceeded'),
                  'boundary': boundary.value,
                })
                as SupplierImportFinalizationCapacityExceeded)
            .boundary,
        boundary,
      ),
    );
  }
  test(
    'unknown capacity boundary rejected',
    () => expect(
      () => SupplierImportFinalizationOutcome.fromMap({
        ...finalizationResponse('persistence_capacity_exceeded'),
        'boundary': 'future',
      }),
      throwsFormatException,
    ),
  );
  final mappings = {
    'unauthenticated': SupplierImportFinalizationFailureKind.sessionExpired,
    'permission-denied': SupplierImportFinalizationFailureKind.permissionDenied,
    'invalid-argument': SupplierImportFinalizationFailureKind.invalidRequest,
    'failed-precondition': SupplierImportFinalizationFailureKind.invalidState,
    'internal': SupplierImportFinalizationFailureKind.internal,
    'unavailable': SupplierImportFinalizationFailureKind.unavailable,
    'deadline-exceeded': SupplierImportFinalizationFailureKind.unavailable,
    'unknown': SupplierImportFinalizationFailureKind.unavailable,
  };
  for (final entry in mappings.entries) {
    test('Https ${entry.key} sanitized and classified', () async {
      final functions = _Functions()..callable.error = _Exception(entry.key);
      try {
        await CallableSupplierImportFinalizationClient(
          functions: functions,
        ).execute(finalizationRequest());
        fail('expected failure');
      } on SupplierImportFinalizationFailure catch (e) {
        expect(e.kind, entry.value);
        expect(e.toString(), isNot(contains('PRIVATE')));
        expect(
          e.isAmbiguous,
          entry.value == SupplierImportFinalizationFailureKind.unavailable ||
              entry.value == SupplierImportFinalizationFailureKind.internal,
        );
      }
      expect(functions.callable.bodies, hasLength(1));
    });
  }
  for (final error in [TimeoutException('PRIVATE'), StateError('PRIVATE')]) {
    test('network ${error.runtimeType} ambiguous', () async {
      final f = _Functions()..callable.error = error;
      await expectLater(
        CallableSupplierImportFinalizationClient(
          functions: f,
        ).execute(finalizationRequest()),
        throwsA(
          isA<SupplierImportFinalizationFailure>().having(
            (e) => e.isAmbiguous,
            'ambiguous',
            true,
          ),
        ),
      );
    });
  }
  test(
    'region/name exact; execution never regenerates or retries command',
    () async {
      final f = _Functions();
      String? region;
      final client = CallableSupplierImportFinalizationClient(
        functionsForRegion: (r) {
          region = r;
          return f;
        },
      );
      final request = finalizationRequest();
      await client.execute(request);
      await client.execute(request);
      expect(region, 'asia-south2');
      expect(f.name, 'finalizeSupplierImport');
      expect(f.callable.bodies, [
        jsonEncode(request.toMap()),
        jsonEncode(request.toMap()),
      ]);
    },
  );
  test(
    'malformed successful response remains ambiguous, not definitive rejection',
    () async {
      final f = _Functions()
        ..callable.response = {'outcome': 'future', 'receipt': 'PRIVATE'};
      await expectLater(
        CallableSupplierImportFinalizationClient(
          functions: f,
        ).execute(finalizationRequest()),
        throwsA(
          isA<SupplierImportFinalizationFailure>().having(
            (e) => e.isAmbiguous,
            'ambiguous',
            true,
          ),
        ),
      );
    },
  );
}

class _Functions extends Fake implements FirebaseFunctions {
  final callable = _Callable();
  String? name;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    this.name = name;
    return callable;
  }
}

class _Callable extends Fake implements HttpsCallable {
  Object? error;
  Object? response = finalizationResponse('applied');
  final bodies = <String>[];
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    bodies.add(jsonEncode(parameters));
    if (error != null) throw error!;
    return _Result(response as T);
  }
}

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

class _Exception extends FirebaseFunctionsException {
  _Exception(String code)
    : super(code: code, message: 'PRIVATE source gs://bucket');
}
