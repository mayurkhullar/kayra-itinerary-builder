import type {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import type {SupplierImportResolutionAggregate} from "./supplierImportResolution";
import type {SupplierImportAccounting} from "./supplierImportV2AssemblyTypes";
import {
  account, activityFields, canonicalHotelFields, canonicalId, commonServiceFields,
  dayId, fields, timelineSource, transferFields,
} from "./supplierImportV2AssemblyValues";

export interface AssemblyService {
  entityId: string;
  dayId: string;
  order: number;
  data: Record<string, unknown>;
}
export interface AssemblyDay {
  entityId: string;
  order: number;
  data: Record<string, unknown>;
}
export interface AssemblyTimeline {
  days: AssemblyDay[];
  services: Map<string, AssemblyService>;
}

/** Content construction only; readiness checks and canonical validation are
 * mandatory in the shared evaluator. This never invents placement or details. */
export function buildTimeline(
  snapshot: SupplierExtractionSnapshot, resolution: SupplierImportResolutionAggregate,
  ledger: SupplierImportAccounting[],
): AssemblyTimeline {
  const decisions = new Map(resolution.decisions.map((decision) => [decision.targetEntityId, decision]));
  const days: AssemblyDay[] = [];
  const services = new Map<string, AssemblyService>();
  for (const day of snapshot.days) {
    const value = decisions.get(day.id);
    const decision = value?.decisionKind === "day" ? value : undefined;
    const excluded = decision?.disposition === "exclude";
    account(ledger, day.id, "day", day.sources, decision,
      excluded ? "excluded" : decision ? "explicit_retained" : "auto_retained", [], "supplier",
      excluded ? null : decision?.canonicalOrder ?? day.order);
    if (excluded) continue;
    days.push({entityId: day.id, order: decision?.canonicalOrder ?? day.order,
      data: fields(day, decision?.overrides, ["date", "title", "summary", "notes"])});
  }
  for (const source of snapshot.facts) {
    if (source.factKind !== "service") continue;
    const value = decisions.get(source.id);
    const decision = value?.decisionKind === "service" ? value : undefined;
    const excluded = decision?.disposition === "exclude";
    const id = canonicalId(snapshot, "service", source.id);
    const sources = [...source.sources];
    for (const item of [...source.inclusions, ...source.exclusions, ...source.conditions]) {
      for (const reference of item.sources) {
        if (!sources.some((existing) => existing.supplierSourceFileId === reference.supplierSourceFileId &&
            existing.sourceLabel === reference.sourceLabel)) sources.push(reference);
      }
    }
    account(ledger, source.id, "service", sources, decision,
      excluded ? "excluded" : decision ? "explicit_retained" : "auto_retained", excluded ? [] : [id]);
    if (excluded) continue;
    const destination = decision?.day ? dayId(decision.day) : source.scope.kind === "day" ? source.scope.dayId : null;
    const order = decision?.canonicalOrder ??
      (source.scope.kind === "day" && decision?.day === undefined ? source.order : null);
    if (destination === null || order === null) continue; // Policy reports the structural blocker.
    const overrides = decision?.overrides;
    const type = overrides?.serviceType?.value ?? source.serviceType;
    const data: Record<string, unknown> = {
      id, type, ...fields(source, overrides, commonServiceFields),
      inclusions: list(source.inclusions.map((item) => item.text), overrides?.inclusions),
      exclusions: list(source.exclusions.map((item) => item.text), overrides?.exclusions),
      ...(source.conditions.length || overrides?.conditions ? {conditions:
        list(source.conditions.map(({kind, value}) => ({kind, value})), overrides?.conditions)} : {}),
      hotelDetails: type === "hotel" ? {
        ...fields(source.hotelDetails, overrides?.hotel, canonicalHotelFields),
        ...fields(source.hotelDetails, overrides?.hotel, ["city", "orSimilar", "nightCount"].filter((key) =>
          (source.hotelDetails as unknown as Record<string, unknown> | null)?.[key] != null ||
          Object.prototype.hasOwnProperty.call(overrides?.hotel ?? {}, key))),
      } : null,
      transferDetails: type === "transfer" ? fields(source.transferDetails, overrides?.transfer, transferFields) : null,
      activityDetails: type === "activity" ? fields(source.activityDetails, overrides?.activity, activityFields) : null,
      sourceReference: timelineSource(source.sources),
    };
    services.set(source.id, {entityId: source.id, dayId: destination, order, data});
  }
  for (const item of [...resolution.manualItems].sort((a, b) =>
    (a.itemKind === "consultant_day" ? a.manualDayId : a.manualServiceId).localeCompare(
      b.itemKind === "consultant_day" ? b.manualDayId : b.manualServiceId))) {
    const entityId = item.itemKind === "consultant_day" ? item.manualDayId : item.manualServiceId;
    const id = canonicalId(snapshot, item.itemKind, entityId);
    account(ledger, entityId, item.itemKind, [], undefined, "manual",
      item.itemKind === "consultant_day" ? [] : [id], "consultant",
      item.itemKind === "consultant_day" ? item.canonicalOrder : null);
    if (item.itemKind === "consultant_day") {
      days.push({entityId, order: item.canonicalOrder,
        data: fields(item, undefined, ["date", "title", "summary", "notes"])});
    } else {
      services.set(entityId, {entityId, order: item.canonicalOrder, dayId: dayId(item.day), data: {
        id, type: item.serviceType, ...fields(item, undefined, commonServiceFields),
        inclusions: [...item.inclusions], exclusions: [...item.exclusions],
        hotelDetails: item.hotelDetails === null ? null : {...item.hotelDetails},
        transferDetails: item.transferDetails === null ? null : {...item.transferDetails},
        activityDetails: item.activityDetails === null ? null : {...item.activityDetails},
        sourceReference: null,
      }});
    }
  }
  return {days, services};
}

export function timelineMap(timeline: AssemblyTimeline): object[] {
  return [...timeline.days].sort((a, b) => a.order - b.order).map((day) => ({
    dayNumber: day.order, ...day.data,
    services: [...timeline.services.values()].filter((service) => service.dayId === day.entityId)
      .sort((a, b) => a.order - b.order).map((service) => service.data),
  }));
}

function list<T>(source: readonly T[], override?: {operation: "set"; value: readonly T[]} | {operation: "clear"}): readonly T[] {
  return override === undefined ? source : override.operation === "clear" ? [] : [...override.value];
}
