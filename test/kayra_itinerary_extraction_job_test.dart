import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';

final _createdAt = DateTime.utc(2026, 9, 27, 8);
final _updatedAt = DateTime.utc(2026, 9, 27, 9);

KayraItineraryExtractionJob _job({
  KayraItineraryExtractionStatus status = KayraItineraryExtractionStatus.queued,
  String? resultingDraftId,
  KayraItineraryExtractionFailureCode? failureCode,
}) => KayraItineraryExtractionJob(
  id: 'job-1',
  tripId: 'trip-1',
  sourcePackageId: 'package-1',
  status: status,
  requestedByUid: 'agent-1',
  resultingDraftId: resultingDraftId,
  failureCode: failureCode,
  createdAt: _createdAt,
  updatedAt: _updatedAt,
);

void main() {
  test('queued and processing jobs round trip deterministically', () {
    for (final job in [
      _job(),
      _job(status: KayraItineraryExtractionStatus.processing),
    ]) {
      final restored = KayraItineraryExtractionJob.fromMap(
        job.toMap(),
        documentId: job.id,
      );
      expect(restored.id, job.id);
      expect(restored.toMap(), job.toMap());
    }
  });

  test('completed job requires a resulting draft and no failure', () {
    expect(
      () => _job(status: KayraItineraryExtractionStatus.completed),
      throwsFormatException,
    );
    expect(
      () => _job(
        status: KayraItineraryExtractionStatus.completed,
        resultingDraftId: 'draft-1',
        failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
      ),
      throwsFormatException,
    );
    final job = _job(
      status: KayraItineraryExtractionStatus.completed,
      resultingDraftId: 'draft-1',
    );
    expect(job.toMap()['resultingDraftId'], 'draft-1');
    expect(job.toMap()['failureCode'], isNull);
  });

  test('failed job requires a failure code and no resulting draft', () {
    expect(
      () => _job(status: KayraItineraryExtractionStatus.failed),
      throwsFormatException,
    );
    expect(
      () => _job(
        status: KayraItineraryExtractionStatus.failed,
        resultingDraftId: 'draft-1',
        failureCode: KayraItineraryExtractionFailureCode.unsupportedSource,
      ),
      throwsFormatException,
    );
    final job = _job(
      status: KayraItineraryExtractionStatus.failed,
      failureCode: KayraItineraryExtractionFailureCode.sourceUnavailable,
    );
    expect(job.toMap()['resultingDraftId'], isNull);
    expect(job.toMap()['failureCode'], 'source_unavailable');
  });

  test('queued and processing jobs reject outcome fields', () {
    for (final status in [
      KayraItineraryExtractionStatus.queued,
      KayraItineraryExtractionStatus.processing,
    ]) {
      expect(
        () => _job(status: status, resultingDraftId: 'draft-1'),
        throwsFormatException,
      );
      expect(
        () => _job(
          status: status,
          failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
        ),
        throwsFormatException,
      );
    }
  });

  test('unknown persisted status and failure code are rejected', () {
    final queued = _job().toMap();
    expect(
      () => KayraItineraryExtractionJob.fromMap({
        ...queued,
        'status': 'waiting',
      }, documentId: 'job-1'),
      throwsFormatException,
    );
    final failed = _job(
      status: KayraItineraryExtractionStatus.failed,
      failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
    ).toMap();
    expect(
      () => KayraItineraryExtractionJob.fromMap({
        ...failed,
        'failureCode': 'provider_timeout',
      }, documentId: 'job-1'),
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
        if (allowed.contains(transition)) {
          expect(
            () => KayraItineraryExtractionJob.validateTransition(
              from: from,
              to: to,
            ),
            returnsNormally,
          );
        } else {
          expect(
            () => KayraItineraryExtractionJob.validateTransition(
              from: from,
              to: to,
            ),
            throwsStateError,
          );
        }
      }
    }
  });

  test('document identity is external and immutable in serialization', () {
    final job = _job();
    expect(job.toMap(), isNot(contains('id')));
    final restored = KayraItineraryExtractionJob.fromMap(
      job.toMap(),
      documentId: 'job-2',
    );
    expect(restored.id, 'job-2');
    expect(restored.tripId, 'trip-1');
    expect(restored.sourcePackageId, 'package-1');
    expect(restored.requestedByUid, 'agent-1');
  });
}
