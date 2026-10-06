import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import '../../../domain/supplier_extraction_values.dart';
import '../../../domain/supplier_import_resolution.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_manual_item.dart';
import '../../../domain/supplier_import_resolution_mutation.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import '../../controllers/supplier_import_review_state.dart';
import 'review_components.dart';

/// Presentation of current decisions, never inferred from audit history.
final class StagedServiceReviewData {
  StagedServiceReviewData(this.state)
    : snapshot = state.loaded!.snapshot,
      resolution = switch (state.loaded!) {
        SupplierImportReviewActive(:final resolution) ||
        SupplierImportReviewFinalized(:final resolution) => resolution,
        SupplierImportReviewNotStarted() => null,
      };

  final SupplierImportReviewState state;
  final SupplierExtractionSnapshot snapshot;
  final SupplierImportResolutionAggregate? resolution;
  late final _decisions = {
    for (final stored
        in resolution?.decisions ?? <SupplierImportStoredDecision>[])
      stored.metadata.decisionId: stored.payload,
  };

  bool get canReview =>
      state.loaded is SupplierImportReviewActive &&
      (state is SupplierImportReviewActive ||
          state is SupplierImportReviewConflict) &&
      state.pendingMutation == null;

  SupplierImportServiceDecision? decisionFor(String serviceId) {
    final decision = _decisions[serviceId];
    return decision is SupplierImportServiceDecision &&
            decision.targetEntityId == serviceId
        ? decision
        : null;
  }

  SupplierExtractionStagedDay? dayById(String id) =>
      snapshot.days.where((day) => day.id == id).firstOrNull;

  String? sourceDayId(SupplierExtractionServiceFact service) =>
      switch (service.scope) {
        SupplierExtractionDayScope(:final dayId) => dayId,
        SupplierExtractionUnassignedScope() => null,
      };

  String sourcePlacement(SupplierExtractionServiceFact service) {
    final id = sourceDayId(service);
    final day = id == null ? null : dayById(id);
    return day == null ? 'No day assigned in source' : stagedDayLabel(day);
  }

  bool isRetainedDay(SupplierExtractionStagedDay day) {
    return dayDecisionFor(day.id)?.disposition !=
        SupplierImportRetainDisposition.exclude;
  }

  SupplierImportDayDecision? dayDecisionFor(String dayId) {
    final decision = _decisions[dayId];
    return decision is SupplierImportDayDecision &&
            decision.targetEntityId == dayId
        ? decision
        : null;
  }

  /// Current placement used by both service ordering and day-exclusion preflight.
  SupplierImportDayReference? effectiveDayFor(
    SupplierExtractionServiceFact service,
  ) {
    final decision = decisionFor(service.id);
    if (decision?.disposition == SupplierImportRetainDisposition.exclude) {
      return null;
    }
    final sourceId = sourceDayId(service);
    return decision?.day ??
        (sourceId == null ? null : SupplierImportStagedDayReference(sourceId));
  }

  bool canRetainSource(SupplierExtractionServiceFact service) {
    final id = sourceDayId(service);
    final day = id == null ? null : dayById(id);
    return day != null && isRetainedDay(day);
  }

  List<SupplierExtractionStagedDay> targetsFor(
    SupplierExtractionServiceFact service,
  ) => snapshot.days
      .where((day) => isRetainedDay(day) && day.id != sourceDayId(service))
      .toList();

  String? decisionLabel(SupplierExtractionServiceFact service) {
    final decision = decisionFor(service.id);
    if (decision == null) return null;
    if (decision.disposition == SupplierImportRetainDisposition.exclude) {
      return 'Excluded from import';
    }
    final sourceId = sourceDayId(service);
    final target = decision.day;
    if (target == null ||
        target is SupplierImportStagedDayReference &&
            target.dayId == sourceId) {
      if (sourceId == null) return 'Awaiting day assignment';
      return decision.overrides.toMap().isEmpty &&
              (decision.canonicalOrder == null ||
                  decision.canonicalOrder == service.order)
          ? 'Accepted as extracted'
          : 'Source placement retained';
    }
    final destination = switch (target) {
      SupplierImportStagedDayReference(:final dayId) => _destinationLabel(
        dayId,
      ),
      SupplierImportManualDayReference() => 'consultant-authored day',
    };
    return '${sourceId == null ? 'Assigned' : 'Moved'} to $destination';
  }

  String _destinationLabel(String id) {
    final day = dayById(id);
    return day == null ? 'staged day' : stagedDayLabel(day);
  }

  bool isPending(String serviceId) => switch (state.pendingMutation?.mutation) {
    SupplierImportSetDecisionCommand(:final decision) =>
      decision is SupplierImportServiceDecision &&
          decision.targetEntityId == serviceId,
    SupplierImportRemoveDecisionCommand(:final decisionId) =>
      decisionId == serviceId,
    _ => false,
  };

  SupplierImportServiceDecision retain(SupplierExtractionServiceFact service) =>
      _decision(service, SupplierImportRetainDisposition.retain);

  SupplierImportServiceDecision assign(
    SupplierExtractionServiceFact service,
    SupplierExtractionStagedDay day,
  ) => _decision(
    service,
    SupplierImportRetainDisposition.retain,
    day: SupplierImportStagedDayReference(day.id),
    order: _appendOrder(day.id, service.id),
  );

  SupplierImportServiceDecision exclude(
    SupplierExtractionServiceFact service,
    SupplierImportExclusionReason reason,
    String? note,
  ) => _decision(
    service,
    SupplierImportRetainDisposition.exclude,
    reason: reason,
    note: note,
  );

  SupplierImportServiceDecision _decision(
    SupplierExtractionServiceFact service,
    SupplierImportRetainDisposition disposition, {
    SupplierImportDayReference? day,
    int? order,
    SupplierImportExclusionReason? reason,
    String? note,
  }) => SupplierImportServiceDecision(
    targetEntityId: service.id,
    disposition: disposition,
    day: day,
    canonicalOrder: order,
    // This slice changes placement/disposition only. Never erase corrections
    // recorded by another client when replacing the current decision.
    overrides:
        decisionFor(service.id)?.overrides ??
        const SupplierImportServiceOverrides(),
    exclusionReason: reason,
    exclusionNote: note,
  );

  int _appendOrder(String dayId, String movingServiceId) {
    // Offer an append intent, without reordering others or calculating readiness.
    // Include existing manual services and mapped accommodation in that day.
    var last = 0;
    void consider(SupplierImportDayReference? day, int? order) {
      if (day is SupplierImportStagedDayReference &&
          day.dayId == dayId &&
          order != null &&
          order > last) {
        last = order;
      }
    }

    for (final fact
        in snapshot.facts.whereType<SupplierExtractionServiceFact>()) {
      if (fact.id == movingServiceId) continue;
      final decision = decisionFor(fact.id);
      if (decision?.disposition == SupplierImportRetainDisposition.exclude) {
        continue;
      }
      final sourceId = sourceDayId(fact);
      consider(
        effectiveDayFor(fact),
        decision?.canonicalOrder ??
            (decision?.day == null && sourceId != null ? fact.order : null),
      );
    }
    for (final decision
        in _decisions.values
            .whereType<SupplierImportPackageAccommodationDecision>()) {
      if (decision.disposition ==
          SupplierImportAccommodationDisposition.mapToDayService) {
        consider(decision.day, decision.canonicalOrder);
      }
    }
    for (final item
        in resolution?.manualItems ?? <SupplierImportStoredManualItem>[]) {
      if (item.payload case SupplierImportManualService(
        :final day,
        :final canonicalOrder,
      )) {
        consider(day, canonicalOrder);
      }
    }
    return last + 1;
  }
}

String stagedDayLabel(SupplierExtractionStagedDay day) => [
  if (day.sourceDayNumber != null)
    'Day ${day.sourceDayNumber}'
  else
    'Source position ${day.order}',
  if (day.title != null) day.title!,
  if (day.date != null) reviewDate(day.date)!,
].join(' · ');

String exclusionReasonLabel(SupplierImportExclusionReason reason) =>
    switch (reason) {
      SupplierImportExclusionReason.duplicate => 'Duplicate',
      SupplierImportExclusionReason.extractedInError => 'Extracted in error',
      SupplierImportExclusionReason.irrelevantSupplierContent =>
        'Irrelevant supplier content',
      SupplierImportExclusionReason.notPartOfRequestedItinerary =>
        'Not part of the requested itinerary',
      SupplierImportExclusionReason.replacedByConsultantContent =>
        'Replaced by consultant content',
      SupplierImportExclusionReason.other => 'Other',
    };
