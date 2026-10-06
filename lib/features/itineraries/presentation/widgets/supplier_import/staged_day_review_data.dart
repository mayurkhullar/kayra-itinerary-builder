import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_manual_item.dart';
import '../../../domain/supplier_import_resolution_mutation.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import 'staged_day_correction.dart';
import 'staged_service_review_data.dart';

/// Day-specific display and UX preflight, not a finalization/readiness engine.
final class StagedDayReviewData {
  const StagedDayReviewData(this.review);
  final StagedServiceReviewData review;

  SupplierImportDayDecision? decisionFor(SupplierExtractionStagedDay day) =>
      review.dayDecisionFor(day.id);
  int effectiveOrder(SupplierExtractionStagedDay day) =>
      decisionFor(day)?.canonicalOrder ?? day.order;

  bool canCorrect(SupplierExtractionStagedDay day) =>
      review.canReview && review.isRetainedDay(day);

  SupplierImportDayDecision correctField(
    SupplierExtractionStagedDay day,
    StagedDayCorrectionField field,
    SupplierImportFieldOverride<String>? value,
  ) {
    if (!canCorrect(day)) throw StateError('Day corrections are unavailable.');
    final current = decisionFor(day);
    final old = current?.overrides ?? const SupplierImportDayOverrides();
    // A set-decision replaces the whole document. Change exactly one member,
    // including removing that member for reset, and preserve all other state.
    // Even after the last field reset, explicit retain remains meaningful.
    // Removing the whole decision belongs only to the separate Revert action.
    return SupplierImportDayDecision(
      targetEntityId: day.id,
      disposition:
          current?.disposition ?? SupplierImportRetainDisposition.retain,
      canonicalOrder: current?.canonicalOrder,
      exclusionReason: current?.exclusionReason,
      exclusionNote: current?.exclusionNote,
      overrides: SupplierImportDayOverrides(
        title: field == StagedDayCorrectionField.title
            ? value as SupplierImportSetOverride<String>?
            : old.title,
        date: field == StagedDayCorrectionField.date ? value : old.date,
        summary: field == StagedDayCorrectionField.summary
            ? value
            : old.summary,
        notes: field == StagedDayCorrectionField.notes ? value : old.notes,
      ),
    );
  }

  String? decisionLabel(SupplierExtractionStagedDay day) {
    final decision = decisionFor(day);
    if (decision == null) return null;
    if (decision.disposition == SupplierImportRetainDisposition.exclude) {
      return 'Excluded from import';
    }
    return decision.overrides.toMap().isEmpty &&
            effectiveOrder(day) == day.order
        ? 'Accepted as extracted'
        : 'Retained for import';
  }

  int effectiveServiceCount(SupplierExtractionStagedDay day) => review
      .snapshot
      .facts
      .whereType<SupplierExtractionServiceFact>()
      .where((service) => _targets(review.effectiveDayFor(service), day))
      .length;

  String? exclusionBlocker(SupplierExtractionStagedDay day) {
    if (effectiveServiceCount(day) > 0) {
      return 'Move or exclude the services assigned to this day before excluding the day.';
    }
    for (final item in review.resolution?.manualItems ?? []) {
      if (item.payload case SupplierImportManualService(day: final reference)) {
        if (_targets(reference, day)) {
          return 'Consultant-added services still use this day. Resolve those assignments before excluding the day.';
        }
      }
    }
    for (final stored in review.resolution?.decisions ?? []) {
      if (stored.payload case SupplierImportPackageAccommodationDecision(
        :final disposition,
        day: final reference,
      )) {
        if (disposition ==
                SupplierImportAccommodationDisposition.mapToDayService &&
            _targets(reference, day)) {
          return 'Mapped accommodation still uses this day. Resolve its assignment before excluding the day.';
        }
      }
    }
    return null;
  }

  bool _targets(
    SupplierImportDayReference? reference,
    SupplierExtractionStagedDay day,
  ) =>
      reference is SupplierImportStagedDayReference &&
      reference.dayId == day.id;

  String? orderError(SupplierExtractionStagedDay day, int? order) {
    // Exact integers must survive Flutter Web -> JSON -> JavaScript unchanged.
    if (order == null || order < 1) return 'Enter a positive whole number.';
    if (order > 9007199254740991) return 'Enter a smaller whole number.';
    if (review.snapshot.days.any(
      (other) =>
          other.id != day.id &&
          review.isRetainedDay(other) &&
          effectiveOrder(other) == order,
    )) {
      return 'This order is already used by another retained day. Choose an unused number.';
    }
    for (final item in review.resolution?.manualItems ?? []) {
      if (item.payload case SupplierImportManualDay(:final canonicalOrder)) {
        if (canonicalOrder == order) {
          return 'This order is already used by a consultant-added day. Choose an unused number.';
        }
      }
    }
    return null;
  }

  List<SupplierExtractionStagedDay> get retainedDaysByOrder =>
      review.snapshot.days.where(review.isRetainedDay).toList()..sort((a, b) {
        final order = effectiveOrder(a).compareTo(effectiveOrder(b));
        return order != 0 ? order : a.order.compareTo(b.order);
      });

  bool isPending(SupplierExtractionStagedDay day) =>
      switch (review.state.pendingMutation?.mutation) {
        SupplierImportSetDecisionCommand(:final decision) =>
          decision is SupplierImportDayDecision &&
              decision.targetEntityId == day.id,
        SupplierImportRemoveDecisionCommand(:final decisionId) =>
          decisionId == day.id,
        _ => false,
      };

  SupplierImportDayDecision retain(
    SupplierExtractionStagedDay day, {
    int? order,
  }) => _decision(
    day,
    SupplierImportRetainDisposition.retain,
    order: order ?? decisionFor(day)?.canonicalOrder,
  );

  SupplierImportDayDecision exclude(
    SupplierExtractionStagedDay day,
    SupplierImportExclusionReason reason,
    String? note,
  ) => _decision(
    day,
    SupplierImportRetainDisposition.exclude,
    order: decisionFor(day)?.canonicalOrder,
    reason: reason,
    note: note,
  );

  SupplierImportDayDecision _decision(
    SupplierExtractionStagedDay day,
    SupplierImportRetainDisposition disposition, {
    int? order,
    SupplierImportExclusionReason? reason,
    String? note,
  }) => SupplierImportDayDecision(
    targetEntityId: day.id,
    disposition: disposition,
    canonicalOrder: order,
    // Structural actions preserve separately recorded field corrections.
    overrides:
        decisionFor(day)?.overrides ?? const SupplierImportDayOverrides(),
    exclusionReason: reason,
    exclusionNote: note,
  );
}
