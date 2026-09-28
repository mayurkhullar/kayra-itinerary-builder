import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/itinerary_extraction_job_selection.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';

import 'support/fake_itinerary_extraction.dart';

void main() {
  test('selects the latest attempt independently for each package', () {
    final jobs = [
      fakeExtractionJob(
        id: 'package-1-old',
        sourcePackageId: 'package-1',
        status: KayraItineraryExtractionStatus.completed,
        resultingDraftId: 'draft-old',
        createdAt: DateTime.utc(2026, 9, 20),
      ),
      fakeExtractionJob(
        id: 'package-2-only',
        sourcePackageId: 'package-2',
        status: KayraItineraryExtractionStatus.failed,
        failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
        createdAt: DateTime.utc(2026, 9, 22),
      ),
      fakeExtractionJob(
        id: 'package-1-new',
        sourcePackageId: 'package-1',
        createdAt: DateTime.utc(2026, 9, 25),
      ),
    ];
    final selected = latestItineraryExtractionJobsByPackage(jobs);
    expect(selected['package-1']!.id, 'package-1-new');
    expect(selected['package-2']!.id, 'package-2-only');
  });

  test('newer queued attempt beats an older completed attempt', () {
    final selected = latestItineraryExtractionJobsByPackage([
      fakeExtractionJob(id: 'new-queued', createdAt: DateTime.utc(2026, 9, 28)),
      fakeExtractionJob(
        id: 'old-completed',
        status: KayraItineraryExtractionStatus.completed,
        resultingDraftId: 'draft-old',
        createdAt: DateTime.utc(2026, 9, 27),
      ),
    ]);
    expect(selected['package-1']!.id, 'new-queued');
  });

  test('newer failed attempt beats an older completed attempt', () {
    final selected = latestItineraryExtractionJobsByPackage([
      fakeExtractionJob(
        id: 'old-completed',
        status: KayraItineraryExtractionStatus.completed,
        resultingDraftId: 'draft-old',
        createdAt: DateTime.utc(2026, 9, 27),
      ),
      fakeExtractionJob(
        id: 'new-failed',
        status: KayraItineraryExtractionStatus.failed,
        failureCode: KayraItineraryExtractionFailureCode.extractionFailed,
        createdAt: DateTime.utc(2026, 9, 28),
      ),
    ]);
    expect(selected['package-1']!.id, 'new-failed');
  });

  test('selection is deterministic when timestamps tie', () {
    final time = DateTime.utc(2026, 9, 28);
    final a = fakeExtractionJob(
      id: 'attempt-a',
      createdAt: time,
      updatedAt: time,
    );
    final b = fakeExtractionJob(
      id: 'attempt-b',
      createdAt: time,
      updatedAt: time,
    );
    expect(
      latestItineraryExtractionJobsByPackage([a, b])['package-1']!.id,
      'attempt-b',
    );
    expect(
      latestItineraryExtractionJobsByPackage([b, a])['package-1']!.id,
      'attempt-b',
    );
  });
}
