import 'package:cloud_functions/cloud_functions.dart';

import '../domain/itinerary_model_validation.dart';
import '../domain/kayra_itinerary_extraction_job.dart';

enum ItineraryExtractionRequestFailureKind {
  sessionExpired,
  permissionDenied,
  sourceUnavailable,
  sourceNotReady,
  invalidRequest,
  unavailable,
}

final class ItineraryExtractionRequestFailure implements Exception {
  const ItineraryExtractionRequestFailure(this.kind);

  final ItineraryExtractionRequestFailureKind kind;

  String get userMessage => switch (kind) {
    ItineraryExtractionRequestFailureKind.sessionExpired =>
      'Your session has expired. Please sign in again.',
    ItineraryExtractionRequestFailureKind.permissionDenied =>
      'You do not have access to generate this draft.',
    ItineraryExtractionRequestFailureKind.sourceUnavailable =>
      'This Supplier Source is no longer available.',
    ItineraryExtractionRequestFailureKind.sourceNotReady =>
      'This Supplier Source is not ready for extraction.',
    ItineraryExtractionRequestFailureKind.invalidRequest =>
      'The extraction request could not be started.',
    ItineraryExtractionRequestFailureKind.unavailable =>
      'We couldn’t start the itinerary draft. Please try again.',
  };
}

final class ItineraryExtractionRequestResult {
  ItineraryExtractionRequestResult({
    required String jobId,
    required this.status,
    required this.createdNew,
  }) : jobId = ItineraryModelValidation.id(jobId, 'itinerary extraction job') {
    if (status != KayraItineraryExtractionStatus.queued &&
        status != KayraItineraryExtractionStatus.processing) {
      throw const FormatException(
        'An extraction request must return an active job.',
      );
    }
  }

  final String jobId;
  final KayraItineraryExtractionStatus status;
  final bool createdNew;
}

abstract interface class ItineraryExtractionRequestClient {
  Future<ItineraryExtractionRequestResult> request({
    required String tripId,
    required String sourcePackageId,
  });
}

final class CallableItineraryExtractionRequestClient
    implements ItineraryExtractionRequestClient {
  CallableItineraryExtractionRequestClient({
    FirebaseFunctions? functions,
    FirebaseFunctions Function(String region)? functionsForRegion,
  }) : _functions =
           functions ??
           functionsForRegion?.call(region) ??
           FirebaseFunctions.instanceFor(region: region);

  static const region = 'asia-south2';
  static const functionName = 'requestItineraryExtraction';

  final FirebaseFunctions _functions;

  @override
  Future<ItineraryExtractionRequestResult> request({
    required String tripId,
    required String sourcePackageId,
  }) async {
    ItineraryModelValidation.id(tripId, 'trip');
    ItineraryModelValidation.id(sourcePackageId, 'supplier source package');
    try {
      final response = await _functions
          .httpsCallable(functionName)
          .call<Object?>({
            'tripId': tripId,
            'sourcePackageId': sourcePackageId,
          });
      return _parseResponse(response.data);
    } on FirebaseFunctionsException catch (error) {
      throw ItineraryExtractionRequestFailure(_failureKind(error.code));
    } on ItineraryExtractionRequestFailure {
      rethrow;
    } catch (_) {
      throw const ItineraryExtractionRequestFailure(
        ItineraryExtractionRequestFailureKind.unavailable,
      );
    }
  }

  ItineraryExtractionRequestResult _parseResponse(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        value['jobId'] is! String ||
        value['status'] is! String ||
        value['createdNew'] is! bool) {
      throw const ItineraryExtractionRequestFailure(
        ItineraryExtractionRequestFailureKind.unavailable,
      );
    }
    try {
      return ItineraryExtractionRequestResult(
        jobId: value['jobId'] as String,
        status: KayraItineraryExtractionStatus.parse(value['status']),
        createdNew: value['createdNew'] as bool,
      );
    } catch (_) {
      throw const ItineraryExtractionRequestFailure(
        ItineraryExtractionRequestFailureKind.unavailable,
      );
    }
  }
}

ItineraryExtractionRequestFailureKind _failureKind(
  String code,
) => switch (code) {
  'unauthenticated' => ItineraryExtractionRequestFailureKind.sessionExpired,
  'permission-denied' => ItineraryExtractionRequestFailureKind.permissionDenied,
  'not-found' => ItineraryExtractionRequestFailureKind.sourceUnavailable,
  'failed-precondition' => ItineraryExtractionRequestFailureKind.sourceNotReady,
  'invalid-argument' => ItineraryExtractionRequestFailureKind.invalidRequest,
  _ => ItineraryExtractionRequestFailureKind.unavailable,
};
