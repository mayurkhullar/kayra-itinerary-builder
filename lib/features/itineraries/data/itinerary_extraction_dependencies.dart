import 'itinerary_extraction_job_repository.dart';
import 'itinerary_extraction_request_client.dart';

final class ItineraryExtractionDependencies {
  const ItineraryExtractionDependencies({
    required this.jobs,
    required this.requests,
  });

  factory ItineraryExtractionDependencies.firebase() =>
      ItineraryExtractionDependencies(
        jobs: FirestoreItineraryExtractionJobRepository(),
        requests: CallableItineraryExtractionRequestClient(),
      );

  final ItineraryExtractionJobRepository jobs;
  final ItineraryExtractionRequestClient requests;
}
