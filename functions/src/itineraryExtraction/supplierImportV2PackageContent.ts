import type {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import type {SupplierImportResolutionAggregate} from "./supplierImportResolution";
import type {
  FinalizationBlockerCode, FinalizationFinding, SupplierImportAccounting,
} from "./supplierImportV2AssemblyTypes";
import {parsePackageContent} from "./itineraryDraftPackageContentValidation";
import type {ItineraryDraftImportResult} from "./itineraryDraftV2";
import {maxItineraryPackageRecords} from "./itineraryDraftPackageContent";
import type {AssemblyTimeline} from "./supplierImportV2Timeline";
import {
  account, canonicalHotelFields, canonicalId, dayId, fields, hotelFields, provenance, timelineSource,
} from "./supplierImportV2AssemblyValues";

export interface AssemblyPackageContent {
  accommodations: Record<string, unknown>[];
  inclusions: Record<string, unknown>[];
  exclusions: Record<string, unknown>[];
  conditions: Record<string, unknown>[];
}

export function buildPackageContent(
  snapshot: SupplierExtractionSnapshot, resolution: SupplierImportResolutionAggregate,
  imported: ItineraryDraftImportResult, timeline: AssemblyTimeline, ledger: SupplierImportAccounting[],
  blockers: FinalizationFinding<FinalizationBlockerCode>[], optionalChronology = false,
): AssemblyPackageContent {
  const result: AssemblyPackageContent = {accommodations: [], inclusions: [], exclusions: [], conditions: []};
  const decisions = new Map(resolution.decisions.map((decision) => [decision.targetEntityId, decision]));
  const block = (id: string): void => {
    blockers.push({code: "unsupported_package_mapping", targetKind: "package_fact", targetId: id});
  };
  for (const fact of snapshot.facts) {
    if (!fact.factKind.startsWith("package_")) continue;
    const decision = decisions.get(fact.id);
    if (decision && "disposition" in decision && decision.disposition === "exclude") {
      account(ledger, fact.id, fact.factKind, fact.sources, decision, "excluded");
      continue;
    }
    const id = canonicalId(snapshot, fact.factKind, fact.id);
    const lineage = provenance(snapshot, resolution, fact, decision);
    let mapped = false;
    let successful = true;
    let outputIds = [id];
    let retainedRecord: {key: keyof AssemblyPackageContent; data: Record<string, unknown>} | null = null;
    if (fact.factKind === "package_accommodation") {
      const change = decision?.decisionKind === "package_accommodation" ? decision : undefined;
      const details = fields(fact.details, change?.overrides, hotelFields);
      if (change?.disposition === "map_to_day_service") {
        mapped = true;
        const destination = change.day === null ? null : dayId(change.day);
        if (destination === null || !timeline.days.some((day) => day.entityId === destination) ||
            change.canonicalOrder === null || details.hotelName === null ||
            [details.city, details.orSimilar, details.nightCount].some((value) => value !== null)) {
          successful = false;
        } else {
          timeline.services.set(fact.id, {entityId: fact.id, dayId: destination, order: change.canonicalOrder, data: {
            id, type: "hotel", title: details.hotelName,
            description: null, startTime: null, endTime: null, location: null, city: null,
            inclusions: [], exclusions: [], notes: null,
            hotelDetails: fields(details, undefined, canonicalHotelFields),
            transferDetails: null, activityDetails: null, sourceReference: timelineSource(fact.sources),
          }});
        }
      } else {
        const optionId = canonicalId(snapshot, "accommodation_option", fact.id);
        const record = {id, order: result.accommodations.length + 1, selection: "single",
          options: [{id: optionId, order: 1, details, provenance: lineage}]};
        result.accommodations.push(record);
        retainedRecord = {key: "accommodations", data: record};
        outputIds = [id, optionId];
      }
    } else if (fact.factKind === "package_inclusion" || fact.factKind === "package_exclusion" || fact.factKind === "package_condition") {
      const change = decision?.decisionKind === "package_statement" || decision?.decisionKind === "package_condition" ? decision : undefined;
      const value = fields(fact, change?.overrides, fact.factKind === "package_condition" ?
        ["kind", "value", "appliesTo"] : ["category", "text", "quantity", "frequency", "appliesTo"]);
      value.appliesTo ??= [];
      if (change?.disposition === "map_to_service") {
        mapped = true;
        const reference = change.service;
        const targetId = reference?.kind === "staged_service" ? reference.serviceId : reference?.manualServiceId;
        const target = targetId === undefined ? undefined : timeline.services.get(targetId);
        successful = target !== undefined && (optionalChronology && target.dayId === null || timeline.days.some((day) => day.entityId === target.dayId)) &&
          mapValue(value, fact.factKind, change.destination, target.data);
        outputIds = target === undefined ? [] : [String(target.data.id)];
      } else {
        const collection = fact.factKind === "package_inclusion" ? result.inclusions :
          fact.factKind === "package_exclusion" ? result.exclusions : result.conditions;
        const record = {id, order: collection.length + 1, ...value, provenance: lineage};
        collection.push(record);
        retainedRecord = {key: fact.factKind === "package_inclusion" ? "inclusions" :
          fact.factKind === "package_exclusion" ? "exclusions" : "conditions", data: record};
      }
    }
    if (!successful) block(fact.id);
    if (retainedRecord !== null) {
      // Validate even when an unrelated structural exception blocks the import.
      // The isolated view uses order 1 only for this check; output keeps compact
      // relative source order. Reuse the canonical validator, not a second schema.
      try {
        parsePackageContent({accommodations: [], inclusions: [], exclusions: [], conditions: [],
          [retainedRecord.key]: [{...retainedRecord.data, order: 1}]}, imported);
      } catch {
        successful = false;
        blockers.push({code: "canonical_validation_failed", targetKind: "package_fact", targetId: fact.id});
      }
    }
    account(ledger, fact.id, fact.factKind, fact.sources, decision,
      !successful ? "blocked" : mapped ? "mapped" : decision ? "explicit_retained" : "auto_retained",
      successful ? outputIds : []);
  }
  const records = result.accommodations.reduce((count, item) => count + 1 + (item.options as unknown[]).length, 0) +
    result.inclusions.length + result.exclusions.length + result.conditions.length;
  if (records > maxItineraryPackageRecords) {
    blockers.push({code: "package_record_limit_exceeded", targetKind: "resolution", targetId: resolution.root.resolutionId});
  }
  return result;
}

function mapValue(
  value: Record<string, unknown>, kind: string, destination: string | null, target: Record<string, unknown>,
): boolean {
  // Legacy timeline strings cannot preserve quantity/frequency/applicability.
  if ((value.appliesTo as unknown[]).length > 0) return false;
  if (kind !== "package_condition") {
    if (value.quantity !== null || value.frequency !== null) return false;
    // Mapping polarity must remain explicit. A generic notes field loses it.
    const field = destination === "service_inclusion" ? "inclusions" : destination === "service_exclusion" ? "exclusions" : null;
    if (field === null) return false;
    (target[field] as unknown[]).push(value.text);
    return true;
  }
  if (destination === "service_notes") {
    // Non-generic condition kinds need their structured package destination.
    if (value.kind !== "other") return false;
    target.notes = target.notes === null ? value.value : `${target.notes}\n${value.value}`;
    return true;
  }
  const field = destination === "transfer_vehicle_type" ? "vehicleType" : destination === "transfer_type" ? "transferType" : null;
  if (field === null || target.type !== "transfer" || target.transferDetails === null) return false;
  const details = target.transferDetails as Record<string, unknown>;
  if (details[field] !== null) return false; // Never overwrite competing content, even identical text.
  details[field] = value.value;
  return true;
}
