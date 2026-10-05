import 'dart:io';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_mutation_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_manual_item.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_mutation.dart';

void main() {
  test('AF-AM all commands serialize the exact closed request contract', () {
    final commands = <SupplierImportResolutionMutationCommand>[
      const SupplierImportStartReviewCommand(),
      const SupplierImportSetDecisionCommand(
        SupplierImportTitleDecision(
          disposition: SupplierImportTitleDisposition.accept,
        ),
      ),
      SupplierImportRemoveDecisionCommand('staged-day-1'),
      const SupplierImportUpsertManualItemCommand(
        SupplierImportManualDay(
          manualDayId: 'consultant-day-1',
          canonicalOrder: 1,
          date: null,
          title: 'Consultant day',
          summary: null,
          notes: null,
        ),
      ),
      SupplierImportRemoveManualItemCommand('consultant-day-1'),
    ];
    const actions = [
      'start_review',
      'set_decision',
      'remove_decision',
      'upsert_manual_item',
      'remove_manual_item',
    ];
    for (var index = 0; index < commands.length; index++) {
      final request = _request(commands[index]);
      final map = request.toMap();
      expect(map.keys, {
        'tripId',
        'extractionId',
        'expectedRevision',
        'commandId',
        'mutation',
      });
      expect((map['mutation'] as Map)['action'], actions[index]);
      expect(map.containsKey('uid'), isFalse);
      expect(map.containsKey('email'), isFalse);
      expect(map.containsKey('sourcePackageId'), isFalse);
      expect(map.containsKey('resolutionId'), isFalse);
      expect(map.containsKey('updatedAt'), isFalse);
      expect(map.containsKey('audit'), isFalse);
    }
  });

  test('AN generated command IDs satisfy the backend boundary', () {
    final generator = SupplierImportCommandIdGenerator(random: Random(7));
    final values = List.generate(20, (_) => generator.generate());
    expect(values.toSet().length, values.length);
    for (final value in values) {
      expect(value.length, lessThanOrEqualTo(128));
      expect(value, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    }
  });

  test(
    'AO/AP/BB execution preserves one supplied command object and ID',
    () async {
      final functions = _Functions();
      final request = _request(const SupplierImportStartReviewCommand());
      final client = CallableSupplierImportResolutionMutationClient(
        functions: functions,
      );
      await client.execute(request);
      expect(functions.callable.calls, 1);
      expect(
        (functions.callable.parameters as Map)['commandId'],
        request.commandId,
      );
      expect(request.commandId, 'command-retry-1');

      functions.callable.error = _TestFunctionsException(
        code: 'unavailable',
        message: 'ambiguous network result',
      );
      await expectLater(
        client.execute(request),
        throwsA(
          isA<SupplierImportMutationFailure>().having(
            (error) => error.kind,
            'kind',
            SupplierImportMutationFailureKind.unavailable,
          ),
        ),
      );
      expect(
        (functions.callable.parameters as Map)['commandId'],
        'command-retry-1',
      );
    },
  );

  test('AQ-AU every callable outcome parses as its typed variant', () async {
    final cases = <Map<String, Object?>, Type>{
      {
        'outcome': 'applied',
        'resolutionId': 'extraction-1',
        'revision': 2,
        'status': 'active',
        'canFinalize': false,
        'blockerCount': 1,
        'warningCount': 2,
      }: SupplierImportMutationApplied,
      {
        'outcome': 'already_applied',
        'resolutionId': 'extraction-1',
        'revision': 2,
      }: SupplierImportMutationAlreadyApplied,
      {
        'outcome': 'resolution_conflict',
        'resolutionId': 'extraction-1',
        'currentRevision': 3,
      }: SupplierImportMutationConflict,
      {
        'outcome': 'resolution_not_started',
        'resolutionId': 'extraction-1',
        'revision': 0,
      }: SupplierImportMutationNotStarted,
      {
        'outcome': 'resolution_finalized',
        'resolutionId': 'extraction-1',
        'revision': 4,
      }: SupplierImportMutationFinalized,
    };
    for (final entry in cases.entries) {
      final functions = _Functions()..callable.response = entry.key;
      final result = await CallableSupplierImportResolutionMutationClient(
        functions: functions,
      ).execute(_request(const SupplierImportStartReviewCommand()));
      expect(result.runtimeType, entry.value);
    }
  });

  test('AS conflict and AR already-applied remain normal outcomes', () async {
    final functions = _Functions()
      ..callable.response = {
        'outcome': 'resolution_conflict',
        'resolutionId': 'extraction-1',
        'currentRevision': 9,
      };
    final client = CallableSupplierImportResolutionMutationClient(
      functions: functions,
    );
    final conflict = await client.execute(
      _request(const SupplierImportStartReviewCommand()),
    );
    expect((conflict as SupplierImportMutationConflict).currentRevision, 9);
    functions.callable.response = {
      'outcome': 'already_applied',
      'resolutionId': 'extraction-1',
      'revision': 9,
    };
    expect(
      await client.execute(_request(const SupplierImportStartReviewCommand())),
      isA<SupplierImportMutationAlreadyApplied>(),
    );
  });

  test('AV unknown response outcome fails safely', () async {
    final functions = _Functions()
      ..callable.response = {
        'outcome': 'future',
        'resolutionId': 'extraction-1',
      };
    await expectLater(
      CallableSupplierImportResolutionMutationClient(
        functions: functions,
      ).execute(_request(const SupplierImportStartReviewCommand())),
      throwsA(
        isA<SupplierImportMutationFailure>().having(
          (error) => error.kind,
          'kind',
          SupplierImportMutationFailureKind.unavailable,
        ),
      ),
    );
  });

  const mappings = {
    'unauthenticated': SupplierImportMutationFailureKind.sessionExpired,
    'permission-denied': SupplierImportMutationFailureKind.permissionDenied,
    'invalid-argument': SupplierImportMutationFailureKind.invalidMutation,
    'failed-precondition': SupplierImportMutationFailureKind.invalidState,
    'internal': SupplierImportMutationFailureKind.internal,
    'unavailable': SupplierImportMutationFailureKind.unavailable,
  };
  for (final entry in mappings.entries) {
    test('AW-BA ${entry.key} maps to a sanitized typed failure', () async {
      final functions = _Functions()
        ..callable.error = _TestFunctionsException(
          code: entry.key,
          message: 'PRIVATE SERVER DETAIL',
        );
      try {
        await CallableSupplierImportResolutionMutationClient(
          functions: functions,
        ).execute(_request(const SupplierImportStartReviewCommand()));
        fail('Expected callable failure.');
      } on SupplierImportMutationFailure catch (error) {
        expect(error.kind, entry.value);
        expect(error.userMessage, isNot(contains('PRIVATE')));
        expect(error.toString(), isNot(contains('PRIVATE')));
      }
    });
  }

  test(
    'BC callable is created in asia-south2 and uses deployed name',
    () async {
      final functions = _Functions();
      String? region;
      final client = CallableSupplierImportResolutionMutationClient(
        functionsForRegion: (value) {
          region = value;
          return functions;
        },
      );
      await client.execute(_request(const SupplierImportStartReviewCommand()));
      expect(region, 'asia-south2');
      expect(functions.name, 'applySupplierImportResolutionMutation');
    },
  );

  test(
    'BD-BF foundation contains no finalizer, draft writer, or Firestore write',
    () {
      const commands = <SupplierImportResolutionMutationCommand>[
        SupplierImportStartReviewCommand(),
      ];
      expect(commands.map((item) => item.action), isNot(contains('finalize')));
      final files = [
        'lib/features/itineraries/domain/'
            'supplier_import_resolution_mutation.dart',
        'lib/features/itineraries/data/'
            'supplier_import_resolution_mutation_client.dart',
      ].map((path) => File(path).readAsStringSync()).join();
      expect(files, isNot(contains('finalizeSupplierImport')));
      expect(files, isNot(contains('resultingDraftId')));
      expect(files, isNot(contains('FirebaseFirestore')));
      expect(files, isNot(contains('.set(')));
      expect(files, isNot(contains('.update(')));
    },
  );
}

SupplierImportResolutionMutationRequest _request(
  SupplierImportResolutionMutationCommand command,
) => SupplierImportResolutionMutationRequest(
  tripId: 'trip-1',
  extractionId: 'extraction-1',
  expectedRevision: 1,
  commandId: 'command-retry-1',
  mutation: command,
);

final class _Functions extends Fake implements FirebaseFunctions {
  final callable = _Callable();
  String? name;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    this.name = name;
    return callable;
  }
}

final class _Callable extends Fake implements HttpsCallable {
  Object? response = {
    'outcome': 'applied',
    'resolutionId': 'extraction-1',
    'revision': 2,
    'status': 'active',
    'canFinalize': false,
    'blockerCount': 1,
    'warningCount': 0,
  };
  Object? error;
  Object? parameters;
  int calls = 0;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    calls++;
    this.parameters = parameters;
    if (error != null) throw error!;
    return _Result<T>(response as T);
  }
}

final class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

final class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException({required super.code, required super.message});
}
