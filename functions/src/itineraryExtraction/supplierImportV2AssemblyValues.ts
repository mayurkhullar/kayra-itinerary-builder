import type {
  SupplierExtractionSnapshot, TrustedSnapshotSourceReference,
} from "./supplierExtractionSnapshot";
import type {
  DayReference, SupplierImportDecision, SupplierImportResolutionAggregate,
} from "./supplierImportResolution";
import type {
  ImportAccountingOutcome, SupplierImportAccounting,
} from "./supplierImportV2AssemblyTypes";

export const hotelFields = ["hotelName", "city", "orSimilar", "checkInDate",
  "checkOutDate", "nightCount", "roomType", "mealPlan", "numberOfRooms", "supplierStarRating"] as const;
export const canonicalHotelFields = hotelFields.filter((field) =>
  !["city", "orSimilar", "nightCount"].includes(field));
export const transferFields = ["pickup", "dropoff", "vehicleType", "transferType"] as const;
export const activityFields = ["activityName", "duration", "activityType"] as const;
export const commonServiceFields = ["title", "description", "startTime", "endTime", "location", "city", "notes"] as const;

/** Explicit field lists prevent decision/envelope fields leaking into content. */
export function fields(
  source: object | null, overrides: object | undefined, names: readonly string[],
): Record<string, unknown> {
  const original = source as Record<string, unknown> | null;
  const changes = overrides as Record<string, {operation: "set" | "clear"; value?: unknown}> | undefined;
  return Object.fromEntries(names.map((name) => {
    const change = changes?.[name];
    return [name, change === undefined ? original?.[name] ?? null :
      change.operation === "clear" ? null : change.value];
  }));
}

export function canonicalId(snapshot: SupplierExtractionSnapshot, kind: string, id: string): string {
  // Length-delimited identities are injective, including colons/unusual Unicode;
  // no URI conversion can throw or manufacture a source-derived document ID.
  return `import:${snapshot.extractionId.length}:${snapshot.extractionId}:${kind}:${id.length}:${id}`;
}

export function dayId(reference: DayReference): string {
  return reference.kind === "staged_day" ? reference.dayId : reference.manualDayId;
}

export function fieldChanges(overrides: object | undefined, prefix = ""):
  {field: string; operation: "set" | "clear"}[] {
  if (overrides === undefined) return [];
  return Object.entries(overrides).sort(([a], [b]) => a.localeCompare(b)).flatMap(([key, value]) =>
    value.operation === "set" || value.operation === "clear" ?
      [{field: `${prefix}${key}`, operation: value.operation as "set" | "clear"}] :
      fieldChanges(value, `${prefix}${key}.`));
}

export function account(
  ledger: SupplierImportAccounting[], entityId: string, entityKind: SupplierImportAccounting["entityKind"],
  sources: readonly TrustedSnapshotSourceReference[], decision: SupplierImportDecision | undefined,
  outcome: ImportAccountingOutcome, outputIds: readonly string[] = [], origin: "supplier" | "consultant" = "supplier", outputDayNumber: number | null = null,
): void {
  ledger.push({entityId, entityKind, origin, outcome, outputIds, outputDayNumber, sources,
    decisionIds: decision ? [decision.decisionId] : [],
    fieldChanges: fieldChanges(decision && "overrides" in decision ? decision.overrides : undefined)});
}

export function provenance(
  snapshot: SupplierExtractionSnapshot, resolution: SupplierImportResolutionAggregate,
  fact: {id: string; sources: readonly TrustedSnapshotSourceReference[]}, decision?: SupplierImportDecision,
): object {
  return {
    origin: "supplier", extractionId: snapshot.extractionId, sourcePackageId: snapshot.sourcePackageId,
    contributors: [{stagedFactId: fact.id, sources: fact.sources.map((source) => ({
      supplierSourceFileId: source.supplierSourceFileId, sourceLabel: source.sourceLabel,
    }))}], resolutionId: resolution.root.resolutionId, evaluatedRevision: resolution.root.revision,
    decisionIds: decision ? [decision.decisionId] : [],
    fieldChanges: fieldChanges(decision && "overrides" in decision ? decision.overrides : undefined),
  };
}

/** Legacy timeline has one locator. Preserve a shared locator only when all
 * contributors agree; the accounting retains every exact trusted reference. */
export function timelineSource(sources: readonly TrustedSnapshotSourceReference[]): object {
  return {
    supplierSourcePackageId: sources[0].supplierSourcePackageId,
    supplierSourceFileId: sources.every((source) => source.supplierSourceFileId === sources[0].supplierSourceFileId) ?
      sources[0].supplierSourceFileId : null,
    sourceLabel: sources.every((source) => source.sourceLabel === sources[0].sourceLabel) ? sources[0].sourceLabel : null,
  };
}
