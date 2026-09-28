import 'dart:async';

import 'package:kayra_crm_v1/features/itineraries/data/itinerary_extraction_dependencies.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_extraction_job_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/data/itinerary_extraction_request_client.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/kayra_itinerary_extraction_job.dart';

final class FakeItineraryExtractionJobRepository
    implements ItineraryExtractionJobRepository {
  final jobs = <KayraItineraryExtractionJob>[];
  final listCalls = <String>[];
  final observeCalls = <({String tripId, String jobId})>[];
  final _streams = <String, StreamController<KayraItineraryExtractionJob?>>{};
  Future<void> Function()? beforeList;
  Object? listError;
  int cancellations = 0;

  ItineraryExtractionDependencies dependencies({
    FakeItineraryExtractionRequestClient? requests,
  }) => ItineraryExtractionDependencies(
    jobs: this,
    requests: requests ?? FakeItineraryExtractionRequestClient(),
  );

  @override
  Future<List<KayraItineraryExtractionJob>> listJobsForTrip(
    String tripId,
  ) async {
    listCalls.add(tripId);
    await beforeList?.call();
    if (listError != null) throw listError!;
    return jobs.where((job) => job.tripId == tripId).toList();
  }

  @override
  Stream<KayraItineraryExtractionJob?> observeJob(String tripId, String jobId) {
    observeCalls.add((tripId: tripId, jobId: jobId));
    return _streams
        .putIfAbsent(
          jobId,
          () => StreamController<KayraItineraryExtractionJob?>.broadcast(
            onCancel: () => cancellations++,
          ),
        )
        .stream;
  }

  void emit(String jobId, KayraItineraryExtractionJob? job) {
    _streams[jobId]?.add(job);
  }

  void emitError(String jobId, Object error) {
    _streams[jobId]?.addError(error);
  }

  Future<void> dispose() async {
    await Future.wait(_streams.values.map((stream) => stream.close()));
  }

  @override
  Future<KayraItineraryExtractionJob?> getJob(
    String tripId,
    String jobId,
  ) async =>
      jobs.where((job) => job.tripId == tripId && job.id == jobId).firstOrNull;

  @override
  Future<String> createQueuedJob({
    required String tripId,
    required String sourcePackageId,
    required String currentUserUid,
  }) => throw UnimplementedError();

  @override
  Future<void> markCompleted({
    required String tripId,
    required String jobId,
    required String resultingDraftId,
  }) => throw UnimplementedError();

  @override
  Future<void> markFailed({
    required String tripId,
    required String jobId,
    required KayraItineraryExtractionFailureCode failureCode,
  }) => throw UnimplementedError();

  @override
  Future<void> markProcessing({
    required String tripId,
    required String jobId,
  }) => throw UnimplementedError();
}

final class FakeItineraryExtractionRequestClient
    implements ItineraryExtractionRequestClient {
  final calls = <({String tripId, String sourcePackageId})>[];
  Future<ItineraryExtractionRequestResult> Function(
    String tripId,
    String sourcePackageId,
  )?
  handler;

  @override
  Future<ItineraryExtractionRequestResult> request({
    required String tripId,
    required String sourcePackageId,
  }) {
    calls.add((tripId: tripId, sourcePackageId: sourcePackageId));
    return handler?.call(tripId, sourcePackageId) ??
        Future.value(
          ItineraryExtractionRequestResult(
            jobId: 'job-${calls.length}',
            status: KayraItineraryExtractionStatus.queued,
            createdNew: true,
          ),
        );
  }
}

KayraItineraryExtractionJob fakeExtractionJob({
  String id = 'job-1',
  String tripId = 'trip-1',
  String sourcePackageId = 'package-1',
  KayraItineraryExtractionStatus status = KayraItineraryExtractionStatus.queued,
  String? resultingDraftId,
  KayraItineraryExtractionFailureCode? failureCode,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => KayraItineraryExtractionJob(
  id: id,
  tripId: tripId,
  sourcePackageId: sourcePackageId,
  status: status,
  requestedByUid: 'agent-1',
  resultingDraftId: resultingDraftId,
  failureCode: failureCode,
  createdAt: createdAt ?? DateTime.utc(2026, 9, 28, 8),
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 28, 8),
);
