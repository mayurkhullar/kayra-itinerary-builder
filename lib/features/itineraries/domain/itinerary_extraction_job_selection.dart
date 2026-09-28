import 'kayra_itinerary_extraction_job.dart';

Map<String, KayraItineraryExtractionJob> latestItineraryExtractionJobsByPackage(
  Iterable<KayraItineraryExtractionJob> jobs,
) {
  final latest = <String, KayraItineraryExtractionJob>{};
  for (final job in jobs) {
    final current = latest[job.sourcePackageId];
    if (current == null || _isLater(job, current)) {
      latest[job.sourcePackageId] = job;
    }
  }
  return Map.unmodifiable(latest);
}

bool _isLater(
  KayraItineraryExtractionJob candidate,
  KayraItineraryExtractionJob current,
) {
  final created = candidate.createdAt.compareTo(current.createdAt);
  if (created != 0) return created > 0;
  final updated = candidate.updatedAt.compareTo(current.updatedAt);
  if (updated != 0) return updated > 0;
  return candidate.id.compareTo(current.id) > 0;
}
