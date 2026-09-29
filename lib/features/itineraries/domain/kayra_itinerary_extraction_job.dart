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

enum KayraItineraryExtractionContractVersion {
  itineraryDraftV1('itinerary_draft_v1'),
  supplierExtractionV1('supplier_extraction_v1');

  const KayraItineraryExtractionContractVersion(this.value);
  final String value;

  static KayraItineraryExtractionContractVersion parse(Object? value) =>
      values.firstWhere(
        (version) => version.value == value,
        orElse: () => throw const FormatException(
          'Invalid itinerary extraction contract version.',
        ),
      );
}

enum KayraItineraryExtractionResultType {
  itineraryDraft('itinerary_draft'),
  supplierExtraction('supplier_extraction');

  const KayraItineraryExtractionResultType(this.value);
  final String value;

  static KayraItineraryExtractionResultType parse(Object? value) =>
      values.firstWhere(
        (type) => type.value == value,
        orElse: () => throw const FormatException(
          'Invalid itinerary extraction result type.',
        ),
      );
}

enum KayraItineraryExtractionPersistenceShape { legacy, versioned }

enum KayraItineraryExtractionFailureCode {
  sourceUnavailable('source_unavailable'),
  unsupportedSource('unsupported_source'),
  extractionFailed('extraction_failed'),
  invalidExtractionResult('invalid_extraction_result'),
  draftPersistenceFailed('draft_persistence_failed'),
  supplierExtractionPersistenceFailed('supplier_extraction_persistence_failed');

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
    this.extractionContractVersion =
        KayraItineraryExtractionContractVersion.itineraryDraftV1,
    this.resultType = KayraItineraryExtractionResultType.itineraryDraft,
    this.persistenceShape = KayraItineraryExtractionPersistenceShape.legacy,
    this.resultingDraftId,
    this.resultingExtractionId,
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
    _validateContract();
    _validateOutcome();
  }

  factory KayraItineraryExtractionJob.fromMap(
    Map<String, Object?> data, {
    required String documentId,
  }) {
    const versionFields = {
      'extractionContractVersion',
      'resultType',
      'resultingExtractionId',
    };
    final versionFieldCount = versionFields.where(data.containsKey).length;
    if (versionFieldCount != 0 && versionFieldCount != versionFields.length) {
      throw const FormatException(
        'Partially versioned itinerary extraction job.',
      );
    }
    final persistenceShape = versionFieldCount == 0
        ? KayraItineraryExtractionPersistenceShape.legacy
        : KayraItineraryExtractionPersistenceShape.versioned;
    final fields = <String>{
      'tripId',
      'sourcePackageId',
      'status',
      'requestedByUid',
      'resultingDraftId',
      'failureCode',
      'createdAt',
      'updatedAt',
      if (persistenceShape ==
          KayraItineraryExtractionPersistenceShape.versioned)
        ...versionFields,
    };
    ItineraryModelValidation.fields(data, fields);

    final contractVersion =
        persistenceShape == KayraItineraryExtractionPersistenceShape.legacy
        ? KayraItineraryExtractionContractVersion.itineraryDraftV1
        : KayraItineraryExtractionContractVersion.parse(
            data['extractionContractVersion'],
          );
    final resultType =
        persistenceShape == KayraItineraryExtractionPersistenceShape.legacy
        ? KayraItineraryExtractionResultType.itineraryDraft
        : KayraItineraryExtractionResultType.parse(data['resultType']);
    final rawFailureCode = data['failureCode'];
    return KayraItineraryExtractionJob(
      id: documentId,
      tripId: ItineraryModelValidation.string(data['tripId']),
      sourcePackageId: ItineraryModelValidation.string(data['sourcePackageId']),
      status: KayraItineraryExtractionStatus.parse(data['status']),
      requestedByUid: ItineraryModelValidation.string(data['requestedByUid']),
      extractionContractVersion: contractVersion,
      resultType: resultType,
      persistenceShape: persistenceShape,
      resultingDraftId: ItineraryModelValidation.nullableString(
        data['resultingDraftId'],
      ),
      resultingExtractionId:
          persistenceShape == KayraItineraryExtractionPersistenceShape.legacy
          ? null
          : ItineraryModelValidation.nullableString(
              data['resultingExtractionId'],
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
  final KayraItineraryExtractionContractVersion extractionContractVersion;
  final KayraItineraryExtractionResultType resultType;
  final KayraItineraryExtractionPersistenceShape persistenceShape;
  final String? resultingDraftId;
  final String? resultingExtractionId;
  final KayraItineraryExtractionFailureCode? failureCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'tripId': tripId,
    'sourcePackageId': sourcePackageId,
    'status': status.value,
    'requestedByUid': requestedByUid,
    if (persistenceShape == KayraItineraryExtractionPersistenceShape.versioned)
      'extractionContractVersion': extractionContractVersion.value,
    if (persistenceShape == KayraItineraryExtractionPersistenceShape.versioned)
      'resultType': resultType.value,
    'resultingDraftId': resultingDraftId,
    if (persistenceShape == KayraItineraryExtractionPersistenceShape.versioned)
      'resultingExtractionId': resultingExtractionId,
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

  void _validateContract() {
    if (persistenceShape == KayraItineraryExtractionPersistenceShape.legacy &&
        (extractionContractVersion !=
                KayraItineraryExtractionContractVersion.itineraryDraftV1 ||
            resultType != KayraItineraryExtractionResultType.itineraryDraft)) {
      throw const FormatException(
        'A legacy extraction job must use the itinerary draft contract.',
      );
    }
    final contractMatchesResult = switch (extractionContractVersion) {
      KayraItineraryExtractionContractVersion.itineraryDraftV1 =>
        resultType == KayraItineraryExtractionResultType.itineraryDraft,
      KayraItineraryExtractionContractVersion.supplierExtractionV1 =>
        resultType == KayraItineraryExtractionResultType.supplierExtraction,
    };
    if (!contractMatchesResult) {
      throw const FormatException(
        'Extraction contract and result type do not match.',
      );
    }
    if (failureCode ==
            KayraItineraryExtractionFailureCode.draftPersistenceFailed &&
        resultType != KayraItineraryExtractionResultType.itineraryDraft) {
      throw const FormatException(
        'Draft persistence failure requires the itinerary draft contract.',
      );
    }
    if (failureCode ==
            KayraItineraryExtractionFailureCode
                .supplierExtractionPersistenceFailed &&
        resultType != KayraItineraryExtractionResultType.supplierExtraction) {
      throw const FormatException(
        'Supplier extraction persistence failure requires its contract.',
      );
    }
  }

  void _validateOutcome() {
    if (resultingDraftId != null && resultingExtractionId != null) {
      throw const FormatException(
        'An extraction job cannot contain both result identities.',
      );
    }
    switch (status) {
      case KayraItineraryExtractionStatus.queued:
      case KayraItineraryExtractionStatus.processing:
        if (resultingDraftId != null ||
            resultingExtractionId != null ||
            failureCode != null) {
          throw const FormatException(
            'An unfinished extraction job cannot have an outcome.',
          );
        }
      case KayraItineraryExtractionStatus.completed:
        if (failureCode != null) {
          throw const FormatException(
            'A completed extraction job cannot have a failure code.',
          );
        }
        switch (resultType) {
          case KayraItineraryExtractionResultType.itineraryDraft:
            if (resultingDraftId == null || resultingExtractionId != null) {
              throw const FormatException(
                'A completed draft extraction requires only a draft result.',
              );
            }
            ItineraryModelValidation.id(resultingDraftId!, 'itinerary draft');
          case KayraItineraryExtractionResultType.supplierExtraction:
            if (resultingExtractionId == null || resultingDraftId != null) {
              throw const FormatException(
                'A completed supplier extraction requires only its result.',
              );
            }
            ItineraryModelValidation.id(
              resultingExtractionId!,
              'supplier extraction',
            );
        }
      case KayraItineraryExtractionStatus.failed:
        if (resultingDraftId != null ||
            resultingExtractionId != null ||
            failureCode == null) {
          throw const FormatException(
            'A failed extraction job requires only a failure code.',
          );
        }
    }
  }
}
