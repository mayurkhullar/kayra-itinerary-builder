import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../supplier_sources/domain/supplier_source_package.dart';
import '../../data/itinerary_extraction_job_repository.dart';
import '../../data/itinerary_extraction_request_client.dart';
import '../../domain/itinerary_extraction_job_selection.dart';
import '../../domain/kayra_itinerary_extraction_job.dart';

enum ItineraryExtractionPackageStateKind {
  unavailable,
  loading,
  idle,
  requesting,
  queued,
  processing,
  completed,
  failed,
  error,
}

final class ItineraryExtractionPackageState {
  const ItineraryExtractionPackageState({
    required this.kind,
    this.message,
    this.resultingDraftId,
  });

  final ItineraryExtractionPackageStateKind kind;
  final String? message;
  final String? resultingDraftId;
}

final class ItineraryExtractionController extends ChangeNotifier {
  ItineraryExtractionController({
    required this.tripId,
    required ItineraryExtractionJobRepository jobs,
    required ItineraryExtractionRequestClient requests,
  }) : _jobs = jobs,
       _requests = requests;

  final String tripId;
  final ItineraryExtractionJobRepository _jobs;
  final ItineraryExtractionRequestClient _requests;
  final Map<String, KayraItineraryExtractionJob> _latestJobs = {};
  final Map<String, KayraItineraryExtractionStatus> _pendingStatuses = {};
  final Map<String, String> _requestErrors = {};
  final Set<String> _observationErrors = {};
  final Set<String> _requesting = {};
  final Map<String, StreamSubscription<KayraItineraryExtractionJob?>>
  _subscriptions = {};
  final Map<String, int> _bindingVersions = {};
  bool _loaded = false;
  bool _loadFailed = false;
  bool _disposed = false;
  int _loadVersion = 0;

  Future<void> load() async {
    final version = ++_loadVersion;
    _loaded = false;
    _loadFailed = false;
    _latestJobs.clear();
    _pendingStatuses.clear();
    _requestErrors.clear();
    _observationErrors.clear();
    _requesting.clear();
    _cancelSubscriptions();
    _notify();
    try {
      final jobs = await _jobs.listJobsForTrip(tripId);
      if (!_isCurrentLoad(version)) return;
      _latestJobs.addAll(latestItineraryExtractionJobsByPackage(jobs));
      _loaded = true;
      _notify();
      for (final job in _latestJobs.values) {
        if (_isActive(job.status)) {
          _bind(job.sourcePackageId, job.id);
        }
      }
    } catch (_) {
      if (!_isCurrentLoad(version)) return;
      _loaded = true;
      _loadFailed = true;
      _notify();
    }
  }

  ItineraryExtractionPackageState stateFor(SupplierSourcePackage package) {
    if (package.status != SupplierSourcePackageStatus.uploaded) {
      return const ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.unavailable,
      );
    }
    if (_requesting.contains(package.id)) {
      return const ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.requesting,
      );
    }
    final requestError = _requestErrors[package.id];
    if (requestError != null) {
      return ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.error,
        message: requestError,
      );
    }
    if (_observationErrors.contains(package.id) || _loadFailed) {
      return const ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.error,
        message: 'We couldn’t build the itinerary draft. Please try again.',
      );
    }
    final pending = _pendingStatuses[package.id];
    if (pending != null) return _stateForStatus(pending);
    final job = _latestJobs[package.id];
    if (job != null) {
      return _stateForStatus(
        job.status,
        failureCode: job.failureCode,
        resultingDraftId: job.resultingDraftId,
      );
    }
    if (!_loaded) {
      return const ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.loading,
      );
    }
    return const ItineraryExtractionPackageState(
      kind: ItineraryExtractionPackageStateKind.idle,
    );
  }

  Future<void> request(String sourcePackageId) async {
    if (_disposed || _requesting.contains(sourcePackageId)) return;
    final version = (_bindingVersions[sourcePackageId] ?? 0) + 1;
    _bindingVersions[sourcePackageId] = version;
    _requesting.add(sourcePackageId);
    _requestErrors.remove(sourcePackageId);
    _observationErrors.remove(sourcePackageId);
    _notify();
    try {
      final result = await _requests.request(
        tripId: tripId,
        sourcePackageId: sourcePackageId,
      );
      if (!_isCurrentBinding(sourcePackageId, version)) return;
      _latestJobs.remove(sourcePackageId);
      _pendingStatuses[sourcePackageId] = result.status;
      _notify();
      _bind(sourcePackageId, result.jobId, version: version);
    } on ItineraryExtractionRequestFailure catch (error) {
      if (!_isCurrentBinding(sourcePackageId, version)) return;
      _requestErrors[sourcePackageId] = error.userMessage;
    } catch (_) {
      if (!_isCurrentBinding(sourcePackageId, version)) return;
      _requestErrors[sourcePackageId] =
          'We couldn’t start the itinerary draft. Please try again.';
    } finally {
      if (_isCurrentBinding(sourcePackageId, version)) {
        _requesting.remove(sourcePackageId);
        _notify();
      }
    }
  }

  void _bind(String packageId, String jobId, {int? version}) {
    final bindingVersion = version ?? (_bindingVersions[packageId] ?? 0) + 1;
    _bindingVersions[packageId] = bindingVersion;
    unawaited(_subscriptions.remove(packageId)?.cancel());
    _subscriptions[packageId] = _jobs.observeJob(tripId, jobId).listen((job) {
      if (!_isCurrentBinding(packageId, bindingVersion)) return;
      if (job == null ||
          job.tripId != tripId ||
          job.sourcePackageId != packageId ||
          job.id != jobId) {
        _setObservationError(packageId, bindingVersion);
        return;
      }
      _latestJobs[packageId] = job;
      _pendingStatuses.remove(packageId);
      _observationErrors.remove(packageId);
      _notify();
      if (!_isActive(job.status)) {
        unawaited(_subscriptions.remove(packageId)?.cancel());
      }
    }, onError: (_) => _setObservationError(packageId, bindingVersion));
  }

  void _setObservationError(String packageId, int version) {
    if (!_isCurrentBinding(packageId, version)) return;
    _pendingStatuses.remove(packageId);
    _observationErrors.add(packageId);
    _notify();
    unawaited(_subscriptions.remove(packageId)?.cancel());
  }

  ItineraryExtractionPackageState _stateForStatus(
    KayraItineraryExtractionStatus status, {
    KayraItineraryExtractionFailureCode? failureCode,
    String? resultingDraftId,
  }) => switch (status) {
    KayraItineraryExtractionStatus.queued =>
      const ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.queued,
      ),
    KayraItineraryExtractionStatus.processing =>
      const ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.processing,
      ),
    KayraItineraryExtractionStatus.completed =>
      resultingDraftId == null || resultingDraftId.trim().isEmpty
          ? const ItineraryExtractionPackageState(
              kind: ItineraryExtractionPackageStateKind.error,
              message:
                  'We couldn’t build the itinerary draft. Please try again.',
            )
          : ItineraryExtractionPackageState(
              kind: ItineraryExtractionPackageStateKind.completed,
              resultingDraftId: resultingDraftId,
            ),
    KayraItineraryExtractionStatus.failed => ItineraryExtractionPackageState(
      kind: ItineraryExtractionPackageStateKind.failed,
      message: itineraryExtractionFailureMessage(failureCode),
    ),
  };

  bool _isCurrentLoad(int version) => !_disposed && version == _loadVersion;

  bool _isCurrentBinding(String packageId, int version) =>
      !_disposed && _bindingVersions[packageId] == version;

  bool _isActive(KayraItineraryExtractionStatus status) =>
      status == KayraItineraryExtractionStatus.queued ||
      status == KayraItineraryExtractionStatus.processing;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _bindingVersions.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadVersion++;
    _cancelSubscriptions();
    super.dispose();
  }
}

String itineraryExtractionFailureMessage(
  KayraItineraryExtractionFailureCode? code,
) => switch (code) {
  KayraItineraryExtractionFailureCode.sourceUnavailable =>
    'The Supplier Source could not be read. Please check the uploaded files and try again.',
  KayraItineraryExtractionFailureCode.unsupportedSource =>
    'One or more uploaded file formats cannot yet be processed for itinerary extraction.',
  KayraItineraryExtractionFailureCode.extractionFailed =>
    'The itinerary could not be extracted. Please try again.',
  KayraItineraryExtractionFailureCode.invalidExtractionResult =>
    'The extracted itinerary needs another attempt before it can be used.',
  KayraItineraryExtractionFailureCode.draftPersistenceFailed =>
    'The itinerary was extracted but could not be saved. Please try again.',
  null => 'We couldn’t build the itinerary draft. Please try again.',
};
