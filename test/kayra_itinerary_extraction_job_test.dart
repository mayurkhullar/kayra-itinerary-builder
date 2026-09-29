import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';

final _createdAt = DateTime.utc(2026, 9, 27, 8);
final _updatedAt = DateTime.utc(2026, 9, 27, 9);

Map<String, Object?> _legacyRecord({
  KayraItineraryExtractionStatus status = KayraItineraryExtractionStatus.queued,
  String? resultingDraftId,
  KayraItineraryExtractionFailureCode? failureCode,
}) => {
  'tripId': 'trip-1',
  'sourcePackageId': 'package-1',
  'status': status.value,
  'requestedByUid': 'agent-1',
  'resultingDraftId': resultingDraftId,
  'failureCode': failureCode?.value,
  'createdAt': _createdAt,
  'updatedAt': _updatedAt,
};

Map<String, Object?> _versionedRecord({
  KayraItineraryExtractionContractVersion contractVersion =
      KayraItineraryExtractionContractVersion.supplierExtractionV1,
  KayraItineraryExtractionResultType resultType =
      KayraItineraryExtractionResultType.supplierExtraction,
  KayraItineraryExtractionStatus status = KayraItineraryExtractionStatus.queued,
  String? resultingDraftId,
  String? resultingExtractionId,
  KayraItineraryExtractionFailureCode? failureCode,
}) => {
  ..._legacyRecord(
    status: status,
    resultingDraftId: resultingDraftId,
    failureCode: failureCode,
  ),
  'extractionContractVersion': contractVersion.value,
  'resultType': resultType.value,
  'resultingExtractionId': resultingExtractionId,
};

KayraItineraryExtractionJob _parse(Map<String, Object?> record) =>
    KayraItineraryExtractionJob.fromMap(record, documentId: 'job-1');

void main() {
  test('historical queued and processing jobs infer the draft contract', () {
    for (final status in [
      KayraItineraryExtractionStatus.queued,
      KayraItineraryExtractionStatus.processing,
    ]) {
      final job = _parse(_legacyRecord(status: status));
      expect(
        job.extractionContractVersion,
        KayraItineraryExtractionContractVersion.itineraryDraftV1,
      );
      expect(job.resultType, KayraItineraryExtractionResultType.itineraryDraft);
      expect(
        job.persistenceShape,
        KayraItineraryExtractionPersistenceShape.legacy,
      );
      expect(job.toMap(), _legacyRecord(status: status));
    }
  });

  test('historical failed job parses with its safe failure code', () {
    final job = _parse(
      _legacyRecord(
        status: KayraItineraryExtractionStatus.failed,
        failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
      ),
    );
    expect(job.resultType, KayraItineraryExtractionResultType.itineraryDraft);
    expect(
      job.failureCode,
      KayraItineraryExtractionFailureCode.extractionFailed,
    );
  });

  test('historical completed job retains its draft result', () {
    final job = _parse(
      _legacyRecord(
        status: KayraItineraryExtractionStatus.completed,
        resultingDraftId: 'draft-1',
      ),
    );
    expect(job.resultingDraftId, 'draft-1');
    expect(job.resultingExtractionId, isNull);
    expect(job.resultType, KayraItineraryExtractionResultType.itineraryDraft);
  });

  test('explicit versioned itinerary draft job parses and round trips', () {
    final record = _versionedRecord(
      contractVersion: KayraItineraryExtractionContractVersion.itineraryDraftV1,
      resultType: KayraItineraryExtractionResultType.itineraryDraft,
      status: KayraItineraryExtractionStatus.completed,
      resultingDraftId: 'draft-1',
    );
    final job = _parse(record);
    expect(
      job.persistenceShape,
      KayraItineraryExtractionPersistenceShape.versioned,
    );
    expect(job.toMap(), record);
  });

  test('supplier extraction queued and processing jobs parse', () {
    for (final status in [
      KayraItineraryExtractionStatus.queued,
      KayraItineraryExtractionStatus.processing,
    ]) {
      final job = _parse(_versionedRecord(status: status));
      expect(
        job.extractionContractVersion,
        KayraItineraryExtractionContractVersion.supplierExtractionV1,
      );
      expect(
        job.resultType,
        KayraItineraryExtractionResultType.supplierExtraction,
      );
    }
  });

  test('completed supplier extraction retains only its extraction result', () {
    final job = _parse(
      _versionedRecord(
        status: KayraItineraryExtractionStatus.completed,
        resultingExtractionId: 'extraction-1',
      ),
    );
    expect(job.resultingExtractionId, 'extraction-1');
    expect(job.resultingDraftId, isNull);
    expect(job.toMap()['resultingExtractionId'], 'extraction-1');
  });

  test('failed supplier extraction parses', () {
    final job = _parse(
      _versionedRecord(
        status: KayraItineraryExtractionStatus.failed,
        failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
      ),
    );
    expect(
      job.resultType,
      KayraItineraryExtractionResultType.supplierExtraction,
    );
    expect(
      job.failureCode,
      KayraItineraryExtractionFailureCode.extractionFailed,
    );
  });

  test(
    'partial version metadata is rejected rather than treated as legacy',
    () {
      for (final partial in <Map<String, Object?>>[
        {..._legacyRecord(), 'extractionContractVersion': 'itinerary_draft_v1'},
        {..._legacyRecord(), 'resultType': 'itinerary_draft'},
        {..._legacyRecord(), 'resultingExtractionId': null},
        {
          ..._legacyRecord(),
          'extractionContractVersion': 'itinerary_draft_v1',
          'resultType': 'itinerary_draft',
        },
      ]) {
        expect(() => _parse(partial), throwsFormatException);
      }
    },
  );

  test('unknown and mismatched contract metadata is rejected', () {
    expect(
      () => _parse({
        ..._versionedRecord(),
        'extractionContractVersion': 'future_contract',
      }),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _versionedRecord(
          contractVersion:
              KayraItineraryExtractionContractVersion.itineraryDraftV1,
          resultType: KayraItineraryExtractionResultType.supplierExtraction,
        ),
      ),
      throwsFormatException,
    );
  });

  test('both result IDs and the wrong result ID are rejected', () {
    expect(
      () => _parse(
        _versionedRecord(
          status: KayraItineraryExtractionStatus.completed,
          resultingDraftId: 'draft-1',
          resultingExtractionId: 'extraction-1',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _versionedRecord(
          status: KayraItineraryExtractionStatus.completed,
          resultingDraftId: 'draft-1',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _versionedRecord(
          contractVersion:
              KayraItineraryExtractionContractVersion.itineraryDraftV1,
          resultType: KayraItineraryExtractionResultType.itineraryDraft,
          status: KayraItineraryExtractionStatus.completed,
          resultingExtractionId: 'extraction-1',
        ),
      ),
      throwsFormatException,
    );
  });

  test('completed jobs require their contract-compatible result ID', () {
    expect(
      () => _parse(
        _legacyRecord(status: KayraItineraryExtractionStatus.completed),
      ),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _versionedRecord(status: KayraItineraryExtractionStatus.completed),
      ),
      throwsFormatException,
    );
  });

  test('queued and processing jobs reject every outcome field', () {
    for (final status in [
      KayraItineraryExtractionStatus.queued,
      KayraItineraryExtractionStatus.processing,
    ]) {
      expect(
        () => _parse(
          _versionedRecord(
            status: status,
            resultingExtractionId: 'extraction-1',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => _parse(
          _versionedRecord(
            status: status,
            failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
          ),
        ),
        throwsFormatException,
      );
    }
  });

  test('failed jobs reject either result ID', () {
    for (final record in [
      _legacyRecord(
        status: KayraItineraryExtractionStatus.failed,
        resultingDraftId: 'draft-1',
        failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
      ),
      _versionedRecord(
        status: KayraItineraryExtractionStatus.failed,
        resultingExtractionId: 'extraction-1',
        failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
      ),
    ]) {
      expect(() => _parse(record), throwsFormatException);
    }
  });

  test('failure code is required only for failed jobs', () {
    expect(
      () =>
          _parse(_legacyRecord(status: KayraItineraryExtractionStatus.failed)),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _legacyRecord(
          failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
        ),
      ),
      throwsFormatException,
    );
  });

  test('persistence failure codes are restricted to their contracts', () {
    expect(
      () => _parse(
        _legacyRecord(
          status: KayraItineraryExtractionStatus.failed,
          failureCode: KayraItineraryExtractionFailureCode
              .supplierExtractionPersistenceFailed,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _versionedRecord(
          status: KayraItineraryExtractionStatus.failed,
          failureCode:
              KayraItineraryExtractionFailureCode.draftPersistenceFailed,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _versionedRecord(
          status: KayraItineraryExtractionStatus.failed,
          failureCode: KayraItineraryExtractionFailureCode
              .supplierExtractionPersistenceFailed,
        ),
      ),
      returnsNormally,
    );
  });

  test('unknown persisted status and failure code are rejected', () {
    expect(
      () => _parse({..._legacyRecord(), 'status': 'waiting'}),
      throwsFormatException,
    );
    expect(
      () => _parse({
        ..._legacyRecord(
          status: KayraItineraryExtractionStatus.failed,
          failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
        ),
        'failureCode': 'provider_timeout',
      }),
      throwsFormatException,
    );
  });

  test('only the defined monotonic transitions are valid', () {
    const allowed = {
      (
        KayraItineraryExtractionStatus.queued,
        KayraItineraryExtractionStatus.processing,
      ),
      (
        KayraItineraryExtractionStatus.processing,
        KayraItineraryExtractionStatus.completed,
      ),
      (
        KayraItineraryExtractionStatus.processing,
        KayraItineraryExtractionStatus.failed,
      ),
    };
    for (final from in KayraItineraryExtractionStatus.values) {
      for (final to in KayraItineraryExtractionStatus.values) {
        final transition = (from, to);
        expect(
          () => KayraItineraryExtractionJob.validateTransition(
            from: from,
            to: to,
          ),
          allowed.contains(transition) ? returnsNormally : throwsStateError,
        );
      }
    }
  });

  test('document identity remains external to serialization', () {
    final record = _legacyRecord();
    final job = _parse(record);
    expect(job.toMap(), isNot(contains('id')));
    final restored = KayraItineraryExtractionJob.fromMap(
      record,
      documentId: 'job-2',
    );
    expect(restored.id, 'job-2');
  });
}
