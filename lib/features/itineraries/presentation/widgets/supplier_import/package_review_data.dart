import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_values.dart';
import '../../../domain/supplier_import_finalization.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_manual_item.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import '../../../domain/supplier_import_resolution_mutation.dart';
import '../../controllers/supplier_import_review_state.dart';
import 'staged_service_review_data.dart';

/// Existing identities and decision shapes only. Assembly remains server-owned.
class PackageReviewData {
  const PackageReviewData(this.review, this.fact);
  final StagedServiceReviewData review;
  final SupplierExtractionFact fact;
  SupplierImportDecisionPayload? get decision => review.resolution?.decisions
      .where((d) => d.payload.targetEntityId == fact.id)
      .firstOrNull
      ?.payload;

  bool get isPending => switch (review.state.pendingMutation?.mutation) {
    SupplierImportSetDecisionCommand(:final decision) =>
      decision.targetEntityId == fact.id,
    SupplierImportRemoveDecisionCommand(:final decisionId) =>
      decisionId == fact.id,
    _ => false,
  };

  bool get needsAttention {
    final state = review.state;
    final outcome = state.finalization?.outcome;
    if (state is! SupplierImportReviewActive ||
        outcome is! SupplierImportFinalizationNotReady ||
        outcome.evaluatedRevision != state.resolution.root.revision) {
      return false;
    }
    return outcome.blockers.any(
      (f) =>
          f.targetKind == SupplierImportFinalizationTargetKind.packageFact &&
              f.targetId == fact.id ||
          f.targetKind == SupplierImportFinalizationTargetKind.reviewIssue &&
              review.snapshot.reviewIssues.any(
                (issue) =>
                    issue.id == f.targetId && issue.target.entityId == fact.id,
              ),
    );
  }

  List<(SupplierImportDayReference, String)> get days => [
    for (final day in review.snapshot.days)
      if (review.isRetainedDay(day))
        (
          SupplierImportStagedDayReference(day.id),
          day.title ?? 'Day ${day.order}',
        ),
    for (final item in review.resolution?.manualItems ?? [])
      if (item.payload case SupplierImportManualDay(
        :final manualDayId,
        :final title,
      ))
        (SupplierImportManualDayReference(manualDayId), title),
  ];

  List<(SupplierImportServiceReference, String)> services(
    SupplierImportPackageDestination destination,
  ) {
    final transferOnly =
        destination == SupplierImportPackageDestination.transferType ||
        destination == SupplierImportPackageDestination.transferVehicleType;
    return [
      for (final source
          in review.snapshot.facts.whereType<SupplierExtractionServiceFact>())
        if (review.decisionFor(source.id)?.disposition !=
                SupplierImportRetainDisposition.exclude &&
            (!transferOnly ||
                (review.decisionFor(source.id)?.overrides.serviceType?.value ??
                        source.serviceType) ==
                    SupplierExtractionServiceType.transfer))
          (
            SupplierImportStagedServiceReference(source.id),
            source.title ?? 'Service',
          ),
      for (final item in review.resolution?.manualItems ?? [])
        if (item.payload case SupplierImportManualService(
          :final manualServiceId,
          :final title,
          :final serviceType,
        ))
          if (!transferOnly ||
              serviceType == SupplierExtractionServiceType.transfer)
            (SupplierImportManualServiceReference(manualServiceId), title),
    ];
  }

  List<SupplierImportPackageDestination> get destinations {
    if (fact.factKind == SupplierExtractionFactKind.packageInclusion) {
      return [SupplierImportPackageDestination.serviceInclusion];
    }
    if (fact.factKind == SupplierExtractionFactKind.packageExclusion) {
      return [SupplierImportPackageDestination.serviceExclusion];
    }
    if (fact case SupplierExtractionPackageConditionFact(
      :final kind,
      :final value,
    )) {
      final old = decision;
      final effectiveKind = old is SupplierImportPackageConditionDecision
          ? old.overrides.kind?.value ?? kind
          : kind;
      // Typed destination compatibility, not lossless/readiness evaluation.
      return [
        if (effectiveKind == SupplierExtractionConditionKind.other)
          SupplierImportPackageDestination.serviceNotes,
        if (effectiveKind == SupplierExtractionConditionKind.vehicle)
          SupplierImportPackageDestination.transferVehicleType,
        if (effectiveKind == SupplierExtractionConditionKind.operatingBasis &&
            SupplierExtractionTransferType.values.any(
              (type) =>
                  type.value ==
                  (old is SupplierImportPackageConditionDecision
                      ? old.overrides.value?.value ?? value
                      : value),
            ))
          SupplierImportPackageDestination.transferType,
      ];
    }
    return [];
  }

  SupplierImportDecisionPayload choose(
    String action, {
    SupplierImportDayReference? day,
    int? order,
    SupplierImportServiceReference? service,
    SupplierImportPackageDestination? destination,
    SupplierImportExclusionReason? reason,
    String? note,
  }) {
    final old = decision;
    final exclude = action == 'exclude';
    final map = action == 'map';
    if (fact is SupplierExtractionPackageAccommodationFact) {
      return SupplierImportPackageAccommodationDecision(
        targetEntityId: fact.id,
        disposition: exclude
            ? SupplierImportAccommodationDisposition.exclude
            : map
            ? SupplierImportAccommodationDisposition.mapToDayService
            : SupplierImportAccommodationDisposition.retainPackageLevel,
        day: map ? day : null,
        canonicalOrder: map ? order : null,
        overrides: old is SupplierImportPackageAccommodationDecision
            ? old.overrides
            : const SupplierImportHotelOverrides(),
        exclusionReason: exclude ? reason : null,
        exclusionNote: exclude ? note : null,
      );
    }
    final disposition = exclude
        ? SupplierImportPackageDisposition.exclude
        : map
        ? SupplierImportPackageDisposition.mapToService
        : SupplierImportPackageDisposition.retainPackageLevel;
    if (fact is SupplierExtractionPackageStatementFact) {
      return SupplierImportPackageStatementDecision(
        targetEntityId: fact.id,
        disposition: disposition,
        service: map ? service : null,
        destination: map ? destination : null,
        overrides: old is SupplierImportPackageStatementDecision
            ? old.overrides
            : const SupplierImportStatementOverrides(),
        exclusionReason: exclude ? reason : null,
        exclusionNote: exclude ? note : null,
      );
    }
    return SupplierImportPackageConditionDecision(
      targetEntityId: fact.id,
      disposition: disposition,
      service: map ? service : null,
      destination: map ? destination : null,
      overrides: old is SupplierImportPackageConditionDecision
          ? old.overrides
          : const SupplierImportConditionOverrides(),
      exclusionReason: exclude ? reason : null,
      exclusionNote: exclude ? note : null,
    );
  }
}
