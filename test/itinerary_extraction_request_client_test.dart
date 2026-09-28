import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_extraction_request_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';

void main() {
  test('uses asia-south2 and sends only Trip and source package IDs', () async {
    final functions = _Functions();
    String? requestedRegion;
    final client = CallableItineraryExtractionRequestClient(
      functionsForRegion: (region) {
        requestedRegion = region;
        return functions;
      },
    );

    final result = await client.request(
      tripId: 'trip-1',
      sourcePackageId: 'package-1',
    );

    expect(requestedRegion, 'asia-south2');
    expect(functions.name, 'requestItineraryExtraction');
    expect(functions.callable.parameters, {
      'tripId': 'trip-1',
      'sourcePackageId': 'package-1',
    });
    expect((functions.callable.parameters as Map).keys, {
      'tripId',
      'sourcePackageId',
    });
    expect(result.jobId, 'job-1');
    expect(result.status, KayraItineraryExtractionStatus.queued);
    expect(result.createdNew, isTrue);
  });

  test('createdNew false and existing processing job are accepted', () async {
    final functions = _Functions()
      ..callable.response = {
        'jobId': 'existing-job',
        'status': 'processing',
        'createdNew': false,
      };
    final result = await CallableItineraryExtractionRequestClient(
      functions: functions,
    ).request(tripId: 'trip-1', sourcePackageId: 'package-1');
    expect(result.jobId, 'existing-job');
    expect(result.status, KayraItineraryExtractionStatus.processing);
    expect(result.createdNew, isFalse);
  });

  for (final response in <Object?>[
    null,
    const [],
    {'jobId': 'job-1', 'status': 'queued'},
    {'jobId': 'job-1', 'status': 'queued', 'createdNew': true, 'extra': true},
    {'jobId': '', 'status': 'queued', 'createdNew': true},
    {'jobId': 'job-1', 'status': 'completed', 'createdNew': true},
    {'jobId': 'job-1', 'status': 'unknown', 'createdNew': true},
    {'jobId': 'job-1', 'status': 'queued', 'createdNew': 'true'},
  ]) {
    test('malformed callable response is rejected safely: $response', () async {
      final functions = _Functions()..callable.response = response;
      await expectLater(
        CallableItineraryExtractionRequestClient(
          functions: functions,
        ).request(tripId: 'trip-1', sourcePackageId: 'package-1'),
        throwsA(
          isA<ItineraryExtractionRequestFailure>()
              .having(
                (error) => error.kind,
                'kind',
                ItineraryExtractionRequestFailureKind.unavailable,
              )
              .having(
                (error) => error.userMessage,
                'message',
                'We couldn’t start the itinerary draft. Please try again.',
              ),
        ),
      );
    });
  }

  const expected = <String, String>{
    'unauthenticated': 'Your session has expired. Please sign in again.',
    'permission-denied': 'You do not have access to generate this draft.',
    'not-found': 'This Supplier Source is no longer available.',
    'failed-precondition': 'This Supplier Source is not ready for extraction.',
    'invalid-argument': 'The extraction request could not be started.',
    'internal': 'We couldn’t start the itinerary draft. Please try again.',
    'unknown-code': 'We couldn’t start the itinerary draft. Please try again.',
  };
  for (final entry in expected.entries) {
    test('${entry.key} maps to a safe client message', () async {
      final functions = _Functions()
        ..callable.error = _TestFunctionsException(
          code: entry.key,
          message: 'PRIVATE BACKEND DETAIL',
        );
      try {
        await CallableItineraryExtractionRequestClient(
          functions: functions,
        ).request(tripId: 'trip-1', sourcePackageId: 'package-1');
        fail('Expected a safe request failure.');
      } on ItineraryExtractionRequestFailure catch (error) {
        expect(error.userMessage, entry.value);
        expect(error.userMessage, isNot(contains('PRIVATE')));
        expect(error.toString(), isNot(contains('PRIVATE')));
      }
    });
  }
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
  Object? parameters;
  Object? response = {'jobId': 'job-1', 'status': 'queued', 'createdNew': true};
  Object? error;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    this.parameters = parameters;
    if (error != null) throw error!;
    return _Result<T>(response as T);
  }
}

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException({required super.code, required super.message});
}
