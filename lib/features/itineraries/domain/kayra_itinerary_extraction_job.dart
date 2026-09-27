import 'itinerary_model_validation.dart';

enum KayraItineraryExtractionStatus {
  queued('queued'),
  processing('processing'),
  completed('completed'),
  failed('failed');

  const KayraItineraryExtractionStatus(this.value);
  final String value;

  static KayraItineraryExtractionStatus parse(Object? value) =>
      values.firstWhere(
        (status) => status.value == value,
        orElse: () => throw const FormatException(
          'Invalid itinerary extraction job status.',
        ),
      );
}

enum KayraItineraryExtractionFailureCode {
  sourceUnavailable('source_unavailable'),
  unsupportedSource('unsupported_source'),
  extractionFailed('extraction_failed'),
  invalidExtractionResult('invalid_extraction_result'),
  draftPersistenceFailed('draft_persistence_failed');

  const KayraItineraryExtractionFailureCode(this.value);
  final String value;

  static KayraItineraryExtractionFailureCode parse(Object? value) =>
      values.firstWhere(
        (code) => code.value == value,
        orElse: () => throw const FormatException(
          'Invalid itinerary extraction failure code.',
        ),
      );
}

final class KayraItineraryExtractionJob {
  KayraItineraryExtractionJob({
    required String id,
    required String tripId,
    required String sourcePackageId,
    required this.status,
    required String requestedByUid,
    this.resultingDraftId,
    this.failureCode,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : id = ItineraryModelValidation.id(id, 'itinerary extraction job'),
       tripId = ItineraryModelValidation.id(tripId, 'trip'),
       sourcePackageId = ItineraryModelValidation.id(
         sourcePackageId,
         'supplier source package',
       ),
       requestedByUid = ItineraryModelValidation.id(
         requestedByUid,
         'requester',
       ),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    _validateOutcome();
  }

  factory KayraItineraryExtractionJob.fromMap(
    Map<String, Object?> data, {
    required String documentId,
  }) {
    ItineraryModelValidation.fields(data, {
      'tripId',
      'sourcePackageId',
      'status',
      'requestedByUid',
      'resultingDraftId',
      'failureCode',
      'createdAt',
      'updatedAt',
    });
    final rawFailureCode = data['failureCode'];
    return KayraItineraryExtractionJob(
      id: documentId,
      tripId: ItineraryModelValidation.string(data['tripId']),
      sourcePackageId: ItineraryModelValidation.string(data['sourcePackageId']),
      status: KayraItineraryExtractionStatus.parse(data['status']),
      requestedByUid: ItineraryModelValidation.string(data['requestedByUid']),
      resultingDraftId: ItineraryModelValidation.nullableString(
        data['resultingDraftId'],
      ),
      failureCode: rawFailureCode == null
          ? null
          : KayraItineraryExtractionFailureCode.parse(rawFailureCode),
      createdAt: ItineraryModelValidation.dateTime(data['createdAt']),
      updatedAt: ItineraryModelValidation.dateTime(data['updatedAt']),
    );
  }

  final String id;
  final String tripId;
  final String sourcePackageId;
  final KayraItineraryExtractionStatus status;
  final String requestedByUid;
  final String? resultingDraftId;
  final KayraItineraryExtractionFailureCode? failureCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'tripId': tripId,
    'sourcePackageId': sourcePackageId,
    'status': status.value,
    'requestedByUid': requestedByUid,
    'resultingDraftId': resultingDraftId,
    'failureCode': failureCode?.value,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  static void validateTransition({
    required KayraItineraryExtractionStatus from,
    required KayraItineraryExtractionStatus to,
  }) {
    final allowed = switch (from) {
      KayraItineraryExtractionStatus.queued =>
        to == KayraItineraryExtractionStatus.processing,
      KayraItineraryExtractionStatus.processing =>
        to == KayraItineraryExtractionStatus.completed ||
            to == KayraItineraryExtractionStatus.failed,
      KayraItineraryExtractionStatus.completed ||
      KayraItineraryExtractionStatus.failed => false,
    };
    if (!allowed) {
      throw StateError(
        'Invalid itinerary extraction transition: ${from.value} -> ${to.value}.',
      );
    }
  }

  void _validateOutcome() {
    switch (status) {
      case KayraItineraryExtractionStatus.queued:
      case KayraItineraryExtractionStatus.processing:
        if (resultingDraftId != null || failureCode != null) {
          throw const FormatException(
            'An unfinished extraction job cannot have an outcome.',
          );
        }
      case KayraItineraryExtractionStatus.completed:
        if (resultingDraftId == null || failureCode != null) {
          throw const FormatException(
            'A completed extraction job requires only a resulting draft.',
          );
        }
        ItineraryModelValidation.id(resultingDraftId!, 'itinerary draft');
      case KayraItineraryExtractionStatus.failed:
        if (resultingDraftId != null || failureCode == null) {
          throw const FormatException(
            'A failed extraction job requires only a failure code.',
          );
        }
    }
  }
}
