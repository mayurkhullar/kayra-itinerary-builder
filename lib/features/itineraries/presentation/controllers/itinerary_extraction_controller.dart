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
  longRunning,
  completed,
  failed,
  error,
}

final class ItineraryExtractionPackageState {
  const ItineraryExtractionPackageState({
    required this.kind,
    this.message,
    this.resultType = KayraItineraryExtractionResultType.itineraryDraft,
    this.resultingDraftId,
    this.resultingExtractionId,
  });

  final ItineraryExtractionPackageStateKind kind;
  final String? message;
  final KayraItineraryExtractionResultType resultType;
  final String? resultingDraftId;
  final String? resultingExtractionId;
}

final class ItineraryExtractionController extends ChangeNotifier {
  ItineraryExtractionController({
    required this.tripId,
    required ItineraryExtractionJobRepository jobs,
    required ItineraryExtractionRequestClient requests,
    DateTime Function()? now,
  }) : _jobs = jobs,
       _requests = requests,
       _now = now ?? DateTime.now;

  final DateTime Function() _now;
  Timer? _recoveryTimer;
  final Map<String, DateTime> _retryOfferAfter = {};
  // An early retry (for example from a fast client clock) returns to progress.
  // Re-offer locally later; this timer never requests or polls anything.
  static const _retryOfferDelay = Duration(minutes: 1);
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
    return stateForPackage(package.id);
  }

  /// State of a trusted uploaded package, also used by explicit review reruns.
  ItineraryExtractionPackageState stateForPackage(String packageId) {
    if (_requesting.contains(packageId)) {
      return const ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.requesting,
      );
    }
    final requestError = _requestErrors[packageId];
    if (requestError != null) {
      return ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.error,
        message: requestError,
      );
    }
    if (_observationErrors.contains(packageId) || _loadFailed) {
      return const ItineraryExtractionPackageState(
        kind: ItineraryExtractionPackageStateKind.error,
        message: 'We couldn’t build the itinerary draft. Please try again.',
      );
    }
    final pending = _pendingStatuses[packageId];
    if (pending != null) return _stateForStatus(pending);
    final job = _latestJobs[packageId];
    if (job != null) {
      final deadline = _presentationDeadline(job);
      if (deadline != null && !_now().isBefore(deadline)) {
        return ItineraryExtractionPackageState(
          kind: ItineraryExtractionPackageStateKind.longRunning,
          resultType: job.resultType,
        );
      }
      return _stateForStatus(
        job.status,
        resultType: job.resultType,
        failureCode: job.failureCode,
        resultingDraftId: job.resultingDraftId,
        resultingExtractionId: job.resultingExtractionId,
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
      if (!result.createdNew) {
        _retryOfferAfter[result.jobId] = _now().add(_retryOfferDelay);
      }
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
    KayraItineraryExtractionResultType resultType =
        KayraItineraryExtractionResultType.itineraryDraft,
    KayraItineraryExtractionFailureCode? failureCode,
    String? resultingDraftId,
    String? resultingExtractionId,
  }) {
    switch (status) {
      case KayraItineraryExtractionStatus.queued:
        return ItineraryExtractionPackageState(
          kind: ItineraryExtractionPackageStateKind.queued,
          resultType: resultType,
        );
      case KayraItineraryExtractionStatus.processing:
        return ItineraryExtractionPackageState(
          kind: ItineraryExtractionPackageStateKind.processing,
          resultType: resultType,
        );
      case KayraItineraryExtractionStatus.completed:
        final hasCompatibleResult = switch (resultType) {
          KayraItineraryExtractionResultType.itineraryDraft =>
            resultingDraftId != null &&
                resultingDraftId.trim().isNotEmpty &&
                resultingExtractionId == null,
          KayraItineraryExtractionResultType.supplierExtraction =>
            resultingExtractionId != null &&
                resultingExtractionId.trim().isNotEmpty &&
                resultingDraftId == null,
        };
        if (!hasCompatibleResult) {
          return ItineraryExtractionPackageState(
            kind: ItineraryExtractionPackageStateKind.error,
            resultType: resultType,
            message: 'We couldn’t build the itinerary draft. Please try again.',
          );
        }
        return ItineraryExtractionPackageState(
          kind: ItineraryExtractionPackageStateKind.completed,
          resultType: resultType,
          resultingDraftId: resultingDraftId,
          resultingExtractionId: resultingExtractionId,
        );
      case KayraItineraryExtractionStatus.failed:
        return ItineraryExtractionPackageState(
          kind: ItineraryExtractionPackageStateKind.failed,
          resultType: resultType,
          message: itineraryExtractionFailureMessage(failureCode),
        );
    }
  }

  bool _isCurrentLoad(int version) => !_disposed && version == _loadVersion;

  bool _isCurrentBinding(String packageId, int version) =>
      !_disposed && _bindingVersions[packageId] == version;

  bool _isActive(KayraItineraryExtractionStatus status) =>
      status == KayraItineraryExtractionStatus.queued ||
      status == KayraItineraryExtractionStatus.processing;

  DateTime? _presentationDeadline(KayraItineraryExtractionJob job) {
    final deadline = job.recoveryDeadline;
    if (deadline == null) return null;
    final deferred = _retryOfferAfter[job.id];
    return deferred != null && deferred.isAfter(deadline) ? deferred : deadline;
  }

  void _notify() {
    if (_disposed) return;
    _recoveryTimer?.cancel();
    final now = _now();
    DateTime? next;
    for (final job in _latestJobs.values) {
      final deadline = _presentationDeadline(job);
      if (deadline != null &&
          deadline.isAfter(now) &&
          (next == null || deadline.isBefore(next))) {
        next = deadline;
      }
    }
    if (next != null) _recoveryTimer = Timer(next.difference(now), _notify);
    notifyListeners();
  }

  void _cancelSubscriptions() {
    _recoveryTimer?.cancel();
    _retryOfferAfter.clear();
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
  KayraItineraryExtractionFailureCode.queuedStale ||
  KayraItineraryExtractionFailureCode.processingStale =>
    'This extraction took longer than expected. Please try again.',
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
  KayraItineraryExtractionFailureCode.supplierExtractionPersistenceFailed =>
    'We couldn’t save the extracted itinerary. Please try again.',
  null => 'We couldn’t build the itinerary draft. Please try again.',
};
