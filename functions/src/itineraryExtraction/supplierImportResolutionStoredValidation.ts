import {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import {
  SupplierImportAuditEvent,
  SupplierImportDecision,
  SupplierImportManualItem,
  SupplierImportResolutionAggregate,
  SupplierImportResolutionRoot,
} from "./supplierImportResolution";
import {
  SupplierImportResolutionError,
  validateSupplierImportResolution,
} from "./supplierImportResolutionValidation";

export interface StoredResolutionDocument<T> {
  documentId: string;
  value: T;
}

export interface StoredSupplierImportResolution {
  root: StoredResolutionDocument<unknown>;
  decisions: readonly StoredResolutionDocument<unknown>[];
  manualItems: readonly StoredResolutionDocument<unknown>[];
  auditEvents: readonly StoredResolutionDocument<unknown>[];
}

export function reconstructStoredSupplierImportResolution(
  snapshot: SupplierExtractionSnapshot,
  records: StoredSupplierImportResolution,
  tripId: string,
  extractionId: string,
): SupplierImportResolutionAggregate {
  if (records.root.documentId !== extractionId) malformed();
  const rawRoot = record(records.root.value);
  if (rawRoot.resolutionId !== records.root.documentId ||
      rawRoot.tripId !== tripId || rawRoot.extractionId !== extractionId) {
    malformed();
  }
  const decisions = childValues(records.decisions, "decisionId");
  const manualItems = records.manualItems.map((item) => {
    const value = record(item.value);
    const id = value.itemKind === "consultant_day" ?
      value.manualDayId : value.itemKind === "consultant_service" ?
        value.manualServiceId : null;
    if (id !== item.documentId) malformed();
    return item.value;
  });
  const auditEvents = childValues(records.auditEvents, "eventId");
  let aggregate: SupplierImportResolutionAggregate;
  try {
    aggregate = validateSupplierImportResolution(snapshot, {
      root: records.root.value,
      decisions,
      manualItems,
      auditEvents,
    });
  } catch (error) {
    if (error instanceof SupplierImportResolutionError) malformed();
    throw error;
  }
  validateCompleteAuditHistory(aggregate);
  return freeze({
    root: aggregate.root,
    decisions: [...aggregate.decisions].sort((a, b) =>
      a.decisionId.localeCompare(b.decisionId)),
    manualItems: [...aggregate.manualItems].sort((a, b) =>
      manualId(a).localeCompare(manualId(b))),
    auditEvents: [...aggregate.auditEvents].sort((a, b) =>
      a.resultingRevision - b.resultingRevision ||
      a.eventId.localeCompare(b.eventId)),
  });
}

export function serializeSupplierImportResolution(
  snapshot: SupplierExtractionSnapshot,
  input: unknown,
): StoredSupplierImportResolution {
  const aggregate = validateSupplierImportResolution(snapshot, input);
  validateCompleteAuditHistory(aggregate);
  return freeze({
    root: {documentId: aggregate.root.resolutionId, value: aggregate.root},
    decisions: aggregate.decisions.map((value) => ({
      documentId: value.decisionId, value,
    })),
    manualItems: aggregate.manualItems.map((value) => ({
      documentId: manualId(value), value,
    })),
    auditEvents: aggregate.auditEvents.map((value) => ({
      documentId: value.eventId, value,
    })),
  });
}

function validateCompleteAuditHistory(
  aggregate: SupplierImportResolutionAggregate,
): void {
  const events = [...aggregate.auditEvents].sort((a, b) =>
    a.resultingRevision - b.resultingRevision);
  if (events.length !== aggregate.root.revision) malformed();
  events.forEach((event, index) => {
    if (event.previousRevision !== index || event.resultingRevision !== index + 1) {
      malformed();
    }
  });
}

function childValues(
  children: readonly StoredResolutionDocument<unknown>[],
  identityField: string,
): readonly unknown[] {
  return children.map((child) => {
    if (record(child.value)[identityField] !== child.documentId) malformed();
    return child.value;
  });
}

function record(input: unknown): Record<string, unknown> {
  if (input === null || typeof input !== "object" || Array.isArray(input)) malformed();
  return input as Record<string, unknown>;
}

function manualId(item: SupplierImportManualItem): string {
  return item.itemKind === "consultant_day" ? item.manualDayId : item.manualServiceId;
}

function freeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value as Record<string, unknown>).forEach(freeze);
  }
  return value;
}

function malformed(): never {
  throw new SupplierImportResolutionError(
    "Stored Supplier Import Resolution is malformed.",
  );
}

export type StoredResolutionRoot = SupplierImportResolutionRoot;
export type StoredResolutionDecision = SupplierImportDecision;
export type StoredResolutionManualItem = SupplierImportManualItem;
export type StoredResolutionAuditEvent = SupplierImportAuditEvent;
