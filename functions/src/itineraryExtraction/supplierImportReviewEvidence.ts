import type {StagedReviewIssue, SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import type {SupplierImportDecision, SupplierImportResolutionAggregate, ResolutionReference} from "./supplierImportResolution";

export const reviewedInterpretationNote = "Use reviewed itinerary without changing supplier facts.";
export const structuralReviewCodes = new Set(["chronology_unknown", "accommodation_span_unknown",
  "classification_ambiguous", "conflicting_dates", "global_mapping_required", "source_conflict"]);
export function reviewBlocks(issue: StagedReviewIssue): boolean {
  return structuralReviewCodes.has(issue.code) || issue.severity === "blocker" || issue.resolutionRequired;
}
export function permitsReviewOverride(issue: StagedReviewIssue): boolean {
  return issue.code === "other" || issue.code === "source_conflict" || issue.target.kind === "snapshot";
}

/** Pure evidence policy. Call only with validated Snapshot/Resolution and the
 * assembly's representation gate. No prose interpretation or inferred dates.
 * A snapshot-wide issue has no affected-entity list: only an explicit controlled
 * interpretation can establish its scope. Never demand blanket fact decisions.
 */
export function evaluateReviewIssue(
  issue: StagedReviewIssue, snapshot: SupplierExtractionSnapshot,
  resolution: SupplierImportResolutionAggregate, representationSafe: boolean,
  specificIssuesClear: boolean, optionalChronology = false,
): "optional" | "unresolved" | "derived" | "explicit" | "overridden" {
  const explicit = resolution.decisions.find((d) => d.decisionKind === "review_issue" && d.targetEntityId === issue.id);
  const target = resolution.decisions.find((d) => d.targetEntityId === issue.target.entityId);
  // Preserve historical explicit resolutions, while requiring applicable evidence.
  if (explicit?.decisionKind === "review_issue" && explicit.outcome === "resolved") {
    const evidence = explicit.resolutionReferences.flatMap((r) => r.kind === "decision" ?
      resolution.decisions.filter((d) => d.decisionId === r.decisionId) : []);
    if (issue.target.kind === "snapshot") {
      // Compatibility for old explicit, fully evidenced decisions. New global
      // resolution never requires creating this blanket decision set.
      const ids = [...snapshot.days.map((d) => d.id), ...snapshot.facts.filter((f) => f.factKind !== "commercial_presence").map((f) => f.id)];
      const decisions = new Map(resolution.decisions.map((d) => [d.decisionId, d]));
      const manualIds = new Set(resolution.manualItems.map((m) => m.itemKind === "consultant_day" ? m.manualDayId : m.manualServiceId));
      if (ids.length && ids.every((id) => evidence.some((d) => d.targetEntityId === id &&
          (issue.code === "other" ? concreteChange(d) : concretelyResolves(issue.code,
            {kind: "decision", decisionId: d.decisionId}, decisions, manualIds))))) return "explicit";
    }
    if (issue.target.kind !== "snapshot" && evidence.some((d) => d.targetEntityId === issue.target.entityId &&
        (issue.code === "other" ? concreteChange(d) : concretelyResolves(issue.code,
          {kind: "decision", decisionId: d.decisionId}, new Map(resolution.decisions.map((v) => [v.decisionId, v])),
          new Set(resolution.manualItems.map((m) => m.itemKind === "consultant_day" ? m.manualDayId : m.manualServiceId)))))) return "explicit";
  }
  if (issue.target.kind !== "snapshot" && issue.code !== "other" && target &&
      evidenceResolves(issue, target, snapshot)) return "derived";
  if (explicit?.decisionKind === "review_issue" && explicit.outcome === "overridden" &&
      permitsReviewOverride(issue) && representationSafe &&
      (issue.target.kind !== "snapshot" || specificIssuesClear)) return "overridden";
  if (optionalChronology && representationSafe && absenceOnlyRepresentable(issue, snapshot, resolution)) return "derived";
  return reviewBlocks(issue) ? "unresolved" : "optional";
}

function concreteChange(d: SupplierImportDecision): boolean {
  if (d.decisionKind === "review_issue") return false;
  return "overrides" in d && Object.keys(d.overrides).length > 0 ||
    "disposition" in d && !["retain", "retain_package_level", "accept"].includes(d.disposition) ||
    (d.decisionKind === "day" || d.decisionKind === "service") && d.canonicalOrder !== undefined ||
    d.decisionKind === "service" && d.day !== undefined;
}

function evidenceResolves(issue: StagedReviewIssue, d: SupplierImportDecision, snapshot: SupplierExtractionSnapshot): boolean {
  if (d.targetEntityId !== issue.target.entityId || d.decisionKind === "review_issue" || d.decisionKind === "title") return false;
  if (d.disposition === "exclude") return true;
  switch (issue.code) {
  case "chronology_unknown":
    return d.decisionKind === "day" && d.canonicalOrder !== undefined ||
      d.decisionKind === "service" && d.canonicalOrder !== undefined &&
      (d.day !== undefined || snapshot.facts.some((f) => f.id === d.targetEntityId && f.factKind === "service" && f.scope.kind === "day"));
  case "classification_ambiguous":
    return d.decisionKind === "service" && d.overrides.serviceType?.operation === "set";
  case "conflicting_dates":
    return d.decisionKind === "day" && d.overrides.date !== undefined ||
      d.decisionKind === "service" && (d.overrides.hotel?.checkInDate !== undefined || d.overrides.hotel?.checkOutDate !== undefined) ||
      d.decisionKind === "package_accommodation" && (d.overrides.checkInDate !== undefined || d.overrides.checkOutDate !== undefined) ||
      d.decisionKind === "flight" && (d.overrides.departureDate !== undefined || d.overrides.arrivalDate !== undefined);
  case "accommodation_span_unknown": {
    if (d.decisionKind === "package_accommodation" && d.disposition === "retain_package_level") return true;
    const fact = snapshot.facts.find((f) => f.id === d.targetEntityId);
    const source = fact?.factKind === "package_accommodation" ? fact.details : fact?.factKind === "service" ? fact.hotelDetails : null;
    const o = d.decisionKind === "package_accommodation" ? d.overrides : d.decisionKind === "service" ? d.overrides.hotel : undefined;
    const start = o?.checkInDate?.operation === "set" ? o.checkInDate.value : o?.checkInDate ? null : source?.checkInDate;
    const end = o?.checkOutDate?.operation === "set" ? o.checkOutDate.value : o?.checkOutDate ? null : source?.checkOutDate;
    return !!(o && (o.checkInDate || o.checkOutDate) && start && end && end > start);
  }
  case "global_mapping_required":
    return d.decisionKind === "service" && d.day !== undefined && d.canonicalOrder !== undefined ||
      d.decisionKind === "package_accommodation" || d.decisionKind === "package_statement" || d.decisionKind === "package_condition" ||
      d.decisionKind === "flight" || d.decisionKind === "visa";
  // No field-level conflict locator exists. Arbitrary overrides cannot prove
  // which conflicting fact was chosen; require an explicit interpretation.
  case "source_conflict": return false;
  case "other": return false;
  }
}

// Historical explicit-reference compatibility; not an automatic readiness bypass.
export function concretelyResolves(
  code: StagedReviewIssue["code"],
  reference: ResolutionReference,
  decisions: Map<string, SupplierImportDecision>,
  manualIds: ReadonlySet<string>,
): boolean {
  if (reference.kind === "manual_item") {
    return manualIds.has(reference.manualItemId) && code === "chronology_unknown";
  }
  const related = decisions.get(reference.decisionId);
  if (related === undefined || related.decisionKind === "review_issue" ||
      related.decisionKind === "title") return false;
  if ("disposition" in related && related.disposition === "exclude") return true;
  switch (code) {
  case "chronology_unknown":
    return related.decisionKind === "service" && related.day !== undefined &&
      related.canonicalOrder !== undefined ||
      related.decisionKind === "day" && related.canonicalOrder !== undefined;
  case "accommodation_span_unknown":
    return related.decisionKind === "package_accommodation" &&
      (related.overrides.checkInDate?.operation === "set" ||
       related.overrides.checkOutDate?.operation === "set") ||
      related.decisionKind === "service" && related.overrides.hotel !== undefined &&
      (related.overrides.hotel.checkInDate?.operation === "set" ||
       related.overrides.hotel.checkOutDate?.operation === "set");
  case "classification_ambiguous":
    return related.decisionKind === "service" &&
      related.overrides.serviceType?.operation === "set";
  case "conflicting_dates":
    return hasDateCorrection(related);
  case "global_mapping_required":
    return related.decisionKind === "package_accommodation" &&
      related.disposition === "map_to_day_service" ||
      (related.decisionKind === "package_statement" ||
       related.decisionKind === "package_condition") &&
      related.disposition === "map_to_service" ||
      related.decisionKind === "service" && related.day !== undefined ||
      related.decisionKind === "flight" || related.decisionKind === "visa";
  case "source_conflict":
    return decisionHasOverrides(related);
  case "other": return false;
  }
}

function hasDateCorrection(decision: SupplierImportDecision): boolean {
  if (decision.decisionKind === "day") return decision.overrides.date !== undefined;
  if (decision.decisionKind === "service") {
    return decision.overrides.hotel?.checkInDate !== undefined ||
      decision.overrides.hotel?.checkOutDate !== undefined;
  }
  if (decision.decisionKind === "package_accommodation") {
    return decision.overrides.checkInDate !== undefined ||
      decision.overrides.checkOutDate !== undefined;
  }
  if (decision.decisionKind === "flight") {
    return decision.overrides.departureDate !== undefined ||
      decision.overrides.arrivalDate !== undefined;
  }
  return false;
}

function decisionHasOverrides(decision: SupplierImportDecision): boolean {
  if (!("overrides" in decision)) return false;
  return Object.keys(decision.overrides).length > 0;
}


/** Structured absence can waive placement only; it never waives content validity,
 * explicit source chronology, relationship ambiguity or ancillary routing. */
function absenceOnlyRepresentable(issue: StagedReviewIssue, snapshot: SupplierExtractionSnapshot,
  resolution: SupplierImportResolutionAggregate): boolean {
  if (issue.structureBasis !== "absence_only") return false;
  const safeFact = (id: string): boolean => {
    const fact = snapshot.facts.find((f) => f.id === id);
    if (!fact) return false;
    const decision = resolution.decisions.find((d) => d.targetEntityId === id);
    if (fact.factKind === "service") {
      if (fact.scope.kind !== "unassigned" || decision?.decisionKind === "service" && decision.day !== undefined) return false;
      if (issue.code === "accommodation_span_unknown") return fact.serviceType === "hotel" &&
        fact.hotelDetails?.checkInDate == null && fact.hotelDetails?.checkOutDate == null && fact.hotelDetails?.nightCount == null;
      return issue.code === "chronology_unknown" || issue.code === "global_mapping_required";
    }
    if (fact.factKind === "package_accommodation") {
      if (decision?.decisionKind === "package_accommodation" && decision.disposition === "map_to_day_service") return false;
      return issue.code === "global_mapping_required" || issue.code === "accommodation_span_unknown" &&
        fact.details.checkInDate === null && fact.details.checkOutDate === null && fact.details.nightCount === null;
    }
    return issue.code === "global_mapping_required" &&
      ["package_inclusion", "package_exclusion", "package_condition"].includes(fact.factKind);
  };
  if (issue.target.kind === "snapshot") {
    const facts = snapshot.facts.filter((f) => f.factKind !== "commercial_presence");
    return snapshot.days.length === 0 && facts.length > 0 && facts.every((f) => safeFact(f.id));
  }
  return issue.target.entityId !== null && safeFact(issue.target.entityId);
}
