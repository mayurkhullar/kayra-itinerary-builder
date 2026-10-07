import {
  PackageAccommodationFact,
  StagedHotelDetails,
  StagedServiceFact,
  StagedServiceType,
  SupplierExtractionSnapshot,
} from "./supplierExtractionSnapshot";
import {
  ConsultantDay,
  ConsultantService,
  DayReference,
  FieldOverride,
  PackageAccommodationDecision,
  StagedServiceDecision,
  SupplierImportDecision,
  SupplierImportResolutionAggregate,
} from "./supplierImportResolution";

import {
  FinalizationBlockerCode, FinalizationInformationalCode,
  FinalizationFinding, FinalizationTargetKind, SupplierImportFinalizationAssessment,
} from "./supplierImportV2AssemblyTypes";

/** Partial structural findings only. Readiness belongs exclusively to the full
 * assembleSupplierImportV2 evaluator, including canonical validation. */
export function findAssemblyStructureIssues(
  snapshot: SupplierExtractionSnapshot,
  resolution: SupplierImportResolutionAggregate,
): Pick<SupplierImportFinalizationAssessment, "blockers" | "informational"> {
  const blockers: FinalizationFinding<FinalizationBlockerCode>[] = [];
  const informational: FinalizationFinding<FinalizationInformationalCode>[] = [];
  const decisions = new Map(resolution.decisions.map((decision) =>
    [decision.decisionId, decision]));
  const manualDays = resolution.manualItems.filter(
    (item): item is ConsultantDay => item.itemKind === "consultant_day",
  );
  const manualServices = resolution.manualItems.filter(
    (item): item is ConsultantService => item.itemKind === "consultant_service",
  );
  const retainedDayIds = retainedDays(snapshot, decisions, manualDays);

  if (resolution.root.status === "finalized") {
    add(blockers, "resolution_already_finalized", "resolution",
      resolution.root.resolutionId);
    add(informational, "resolution_finalized", "resolution",
      resolution.root.resolutionId);
  }

  assessDays(snapshot, decisions, manualDays, blockers);
  assessServices(
    snapshot, decisions, manualServices, retainedDayIds, blockers,
  );
  assessPackageFacts(snapshot, decisions, retainedDayIds, blockers);
  assessAncillaryFacts(snapshot, decisions, blockers);

  for (const fact of snapshot.facts) {
    if (fact.factKind === "commercial_presence") {
      add(informational, "commercial_presence", "commercial_fact", fact.id);
    }
  }

  sortFindings(blockers);
  sortFindings(informational);
  return deepFreeze({
    blockers,
    informational,
  });
}

function assessDays(
  snapshot: SupplierExtractionSnapshot,
  decisions: Map<string, SupplierImportDecision>,
  manualDays: readonly ConsultantDay[],
  blockers: FinalizationFinding<FinalizationBlockerCode>[],
): void {
  const orders = new Map<number, string>();
  for (const day of snapshot.days) {
    const decision = decisions.get(day.id);
    if (decision?.decisionKind === "day" && decision.disposition === "exclude") {
      continue;
    }
    const dayDecision = decision?.decisionKind === "day" ? decision : undefined;
    const title = effective(day.title, dayDecision?.overrides.title);
    if (title === null) add(blockers, "missing_day_title", "day", day.id);
    addOrder(orders, dayDecision?.canonicalOrder ?? day.order, day.id,
      "duplicate_day_order", "day", blockers);
  }
  for (const day of manualDays) {
    addOrder(orders, day.canonicalOrder, day.manualDayId, "duplicate_day_order",
      "day", blockers);
  }
}

function assessServices(
  snapshot: SupplierExtractionSnapshot,
  decisions: Map<string, SupplierImportDecision>,
  manualServices: readonly ConsultantService[],
  retainedDayIds: ReadonlySet<string>,
  blockers: FinalizationFinding<FinalizationBlockerCode>[],
): void {
  const orders = new Map<string, Map<number, string>>();
  const services = snapshot.facts.filter(
    (fact): fact is StagedServiceFact => fact.factKind === "service",
  );
  for (const service of services) {
    const candidate = decisions.get(service.id);
    const decision = candidate?.decisionKind === "service" ? candidate : undefined;
    if (decision?.disposition === "exclude") continue;
    const day = effectiveServiceDay(service, decision);
    if (service.scope.kind === "unassigned" && decision === undefined) {
      add(blockers, "unresolved_unassigned_service", "service", service.id);
      continue;
    }
    if (day === null || !retainedDayIds.has(dayReferenceId(day))) {
      add(blockers, "missing_service_day", "service", service.id);
      continue;
    }
    const order = decision?.canonicalOrder ??
      (service.scope.kind === "day" && decision?.day === undefined ? service.order : null);
    if (order === null) {
      add(blockers, "missing_service_order", "service", service.id);
    } else {
      addServiceOrder(orders, dayReferenceId(day), order, service.id, blockers);
    }
    assessServiceContent(service, decision, blockers);
  }
  for (const service of manualServices) {
    const dayId = dayReferenceId(service.day);
    if (!retainedDayIds.has(dayId)) {
      add(blockers, "missing_service_day", "service", service.manualServiceId);
      continue;
    }
    addServiceOrder(orders, dayId, service.canonicalOrder,
      service.manualServiceId, blockers);
  }
  for (const fact of snapshot.facts) {
    if (fact.factKind !== "package_accommodation") continue;
    const candidate = decisions.get(fact.id);
    if (candidate?.decisionKind !== "package_accommodation" ||
        candidate.disposition !== "map_to_day_service" ||
        candidate.day === null || candidate.canonicalOrder === null) continue;
    const dayId = dayReferenceId(candidate.day);
    if (retainedDayIds.has(dayId)) {
      addServiceOrder(orders, dayId, candidate.canonicalOrder, fact.id, blockers);
    }
  }
}

function assessServiceContent(
  source: StagedServiceFact,
  decision: StagedServiceDecision | undefined,
  blockers: FinalizationFinding<FinalizationBlockerCode>[],
): void {
  const type = decision?.overrides.serviceType?.value ?? source.serviceType;
  const title = effective(source.title, decision?.overrides.title);
  if (type === null) add(blockers, "missing_service_type", "service", source.id);
  if (title === null) add(blockers, "missing_service_title", "service", source.id);

  if (type === "hotel") {
    const hotelName = effective(source.hotelDetails?.hotelName ?? null,
      decision?.overrides.hotel?.hotelName);
    if (hotelName === null) {
      add(blockers, "missing_required_service_details", "service", source.id);
    }
    const checkIn = effective(source.hotelDetails?.checkInDate ?? null,
      decision?.overrides.hotel?.checkInDate);
    const checkOut = effective(source.hotelDetails?.checkOutDate ?? null,
      decision?.overrides.hotel?.checkOutDate);
    if (checkIn !== null && checkOut !== null && checkOut <= checkIn) {
      add(blockers, "missing_required_service_details", "service", source.id);
    }
  } else if (type === "transfer") {
    const pickup = effective(source.transferDetails?.pickup ?? null,
      decision?.overrides.transfer?.pickup);
    const dropoff = effective(source.transferDetails?.dropoff ?? null,
      decision?.overrides.transfer?.dropoff);
    if (pickup === null || dropoff === null) {
      add(blockers, "missing_required_service_details", "service", source.id);
    }
  } else if (type === "activity") {
    const activityName = effective(source.activityDetails?.activityName ?? null,
      decision?.overrides.activity?.activityName);
    if (activityName === null) {
      add(blockers, "missing_required_service_details", "service", source.id);
    }
  }

  if (hasIncompatibleSourceDetails(source, decision, type) ||
      hasStructuredStatements(source, decision)) {
    add(blockers, "unsupported_service_content", "service", source.id);
  }
}

function hasIncompatibleSourceDetails(
  source: StagedServiceFact,
  decision: StagedServiceDecision | undefined,
  type: StagedServiceType | null,
): boolean {
  if (source.hotelDetails !== null && type !== "hotel" &&
      !allCleared(decision?.overrides.hotel, Object.keys(source.hotelDetails))) return true;
  if (source.transferDetails !== null && type !== "transfer" &&
      !allCleared(decision?.overrides.transfer, Object.keys(source.transferDetails))) return true;
  if (source.activityDetails !== null && type !== "activity" &&
      !allCleared(decision?.overrides.activity, Object.keys(source.activityDetails))) return true;
  return false;
}

function allCleared(
  overrides: object | undefined,
  fields: readonly string[],
): boolean {
  if (overrides === undefined) return false;
  const data = overrides as Record<string, FieldOverride<unknown> | undefined>;
  return fields.every((field) => data[field]?.operation === "clear");
}

function hasStructuredStatements(
  source: StagedServiceFact,
  decision: StagedServiceDecision | undefined,
): boolean {
  const structured = (items: StagedServiceFact["inclusions"]): boolean =>
    items.some((item) => item.quantity !== null || item.frequency !== null ||
      item.appliesTo.length > 0);
  return (structured(source.inclusions) && decision?.overrides.inclusions === undefined) ||
    (structured(source.exclusions) && decision?.overrides.exclusions === undefined);
}

function assessPackageFacts(
  snapshot: SupplierExtractionSnapshot,
  decisions: Map<string, SupplierImportDecision>,
  retainedDayIds: ReadonlySet<string>,
  blockers: FinalizationFinding<FinalizationBlockerCode>[],
): void {
  for (const fact of snapshot.facts) {
    if (fact.factKind === "package_accommodation") {
      assessAccommodation(fact, decisions.get(fact.id), retainedDayIds, blockers);

    }
  }
}

function assessAccommodation(
  fact: PackageAccommodationFact,
  candidate: SupplierImportDecision | undefined,
  retainedDayIds: ReadonlySet<string>,
  blockers: FinalizationFinding<FinalizationBlockerCode>[],
): void {
  const decision = candidate?.decisionKind === "package_accommodation" ?
    candidate : undefined;
  if (decision === undefined) return;
  if (decision.disposition === "exclude") return;
  if (decision.disposition === "retain_package_level") {
    return;
  }
  if (decision.day === null || !retainedDayIds.has(dayReferenceId(decision.day))) {
    add(blockers, "incomplete_package_accommodation", "package_fact", fact.id);
  }
  if (effective(fact.details.hotelName, decision.overrides.hotelName) === null) {
    add(blockers, "incomplete_package_accommodation", "package_fact", fact.id);
  }
  if (unsupportedAccommodation(fact.details, decision)) {
    add(blockers, "unsupported_package_accommodation_content", "package_fact", fact.id);
  }
}

function unsupportedAccommodation(
  source: StagedHotelDetails,
  decision: PackageAccommodationDecision,
): boolean {
  return effective(source.city, decision.overrides.city) !== null ||
    effective(source.orSimilar, decision.overrides.orSimilar) !== null ||
    effective(source.nightCount, decision.overrides.nightCount) !== null;
}

function assessAncillaryFacts(
  snapshot: SupplierExtractionSnapshot,
  decisions: Map<string, SupplierImportDecision>,
  blockers: FinalizationFinding<FinalizationBlockerCode>[],
): void {
  for (const fact of snapshot.facts) {
    if (fact.factKind !== "flight" && fact.factKind !== "visa") continue;
    const decision = decisions.get(fact.id);
    const compatible = fact.factKind === "flight" ?
      decision?.decisionKind === "flight" : decision?.decisionKind === "visa";
    if (!compatible) {
      add(blockers, "unresolved_ancillary_fact", "ancillary_fact", fact.id);
    }
  }
}

function retainedDays(
  snapshot: SupplierExtractionSnapshot,
  decisions: Map<string, SupplierImportDecision>,
  manualDays: readonly ConsultantDay[],
): ReadonlySet<string> {
  const ids = new Set<string>();
  for (const day of snapshot.days) {
    const decision = decisions.get(day.id);
    if (decision?.decisionKind !== "day" || decision.disposition !== "exclude") {
      ids.add(`staged:${day.id}`);
    }
  }
  for (const day of manualDays) ids.add(`consultant:${day.manualDayId}`);
  return ids;
}

function effectiveServiceDay(
  service: StagedServiceFact,
  decision: StagedServiceDecision | undefined,
): DayReference | null {
  if (decision?.day !== undefined) return decision.day;
  return service.scope.kind === "day" ?
    {kind: "staged_day", dayId: service.scope.dayId} : null;
}

function dayReferenceId(reference: DayReference): string {
  return reference.kind === "staged_day" ?
    `staged:${reference.dayId}` : `consultant:${reference.manualDayId}`;
}

function addServiceOrder(
  orders: Map<string, Map<number, string>>,
  dayId: string,
  order: number,
  serviceId: string,
  blockers: FinalizationFinding<FinalizationBlockerCode>[],
): void {
  let dayOrders = orders.get(dayId);
  if (dayOrders === undefined) {
    dayOrders = new Map();
    orders.set(dayId, dayOrders);
  }
  addOrder(dayOrders, order, serviceId, "duplicate_service_order", "service", blockers);
}

function addOrder(
  orders: Map<number, string>,
  order: number,
  id: string,
  code: "duplicate_day_order" | "duplicate_service_order",
  targetKind: "day" | "service",
  blockers: FinalizationFinding<FinalizationBlockerCode>[],
): void {
  const existing = orders.get(order);
  if (existing !== undefined) {
    add(blockers, code, targetKind, existing);
    add(blockers, code, targetKind, id);
  } else {
    orders.set(order, id);
  }
}

function effective<T>(source: T | null, override?: FieldOverride<T>): T | null {
  if (override === undefined) return source;
  return override.operation === "clear" ? null : override.value;
}

function add<Code extends string>(
  findings: FinalizationFinding<Code>[],
  code: Code,
  targetKind: FinalizationTargetKind,
  targetId: string | null,
): void {
  if (!findings.some((finding) => finding.code === code &&
      finding.targetKind === targetKind && finding.targetId === targetId)) {
    findings.push({code, targetKind, targetId});
  }
}

function sortFindings<Code extends string>(findings: FinalizationFinding<Code>[]): void {
  findings.sort((left, right) =>
    left.code.localeCompare(right.code) ||
    left.targetKind.localeCompare(right.targetKind) ||
    (left.targetId ?? "").localeCompare(right.targetId ?? ""));
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const nested of Object.values(value as Record<string, unknown>)) {
      deepFreeze(nested);
    }
  }
  return value;
}
