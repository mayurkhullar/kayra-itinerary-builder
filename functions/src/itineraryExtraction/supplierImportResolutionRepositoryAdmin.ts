import {DocumentReference, Firestore, Timestamp} from "firebase-admin/firestore";
import {
  readSupplierExtractionSnapshot,
} from "./supplierExtractionRepository";
import {adminSupplierExtractionRepositoryStore} from
  "./supplierExtractionRepositoryAdmin";
import {
  SupplierImportResolutionRepositoryStore,
  supplierImportResolutionPaths,
} from "./supplierImportResolutionRepository";
import {StoredSupplierImportResolution} from
  "./supplierImportResolutionStoredValidation";

export interface SupplierImportResolutionReferences {
  root: DocumentReference;
  decision(decisionId: string): DocumentReference;
  manualItem(manualItemId: string): DocumentReference;
  auditEvent(eventId: string): DocumentReference;
}

export function adminSupplierImportResolutionRepositoryStore(
  db: Firestore,
): SupplierImportResolutionRepositoryStore {
  const snapshotStore = adminSupplierExtractionRepositoryStore(db);
  return {
    loadAuthoritativeSnapshot: (tripId, extractionId) =>
      readSupplierExtractionSnapshot(tripId, extractionId, snapshotStore),
    async readResolution(tripId, extractionId, resolutionId) {
      const references = supplierImportResolutionReferences(
        db, tripId, extractionId,
      );
      if (references.root.id !== resolutionId) return null;
      const root = await references.root.get();
      if (!root.exists) return null;
      const [decisions, manualItems, auditEvents] = await Promise.all([
        references.root.collection("decisions").get(),
        references.root.collection("manual_items").get(),
        references.root.collection("events").get(),
      ]);
      return {
        root: {documentId: root.id, value: fromFirestore(root.data())},
        decisions: decisions.docs.map((document) => ({
          documentId: document.id, value: fromFirestore(document.data()),
        })),
        manualItems: manualItems.docs.map((document) => ({
          documentId: document.id, value: fromFirestore(document.data()),
        })),
        auditEvents: auditEvents.docs.map((document) => ({
          documentId: document.id, value: fromFirestore(document.data()),
        })),
      } satisfies StoredSupplierImportResolution;
    },
  };
}

export function supplierImportResolutionReferences(
  db: Firestore,
  tripId: string,
  extractionId: string,
): SupplierImportResolutionReferences {
  const paths = supplierImportResolutionPaths(tripId, extractionId);
  const root = db.doc(paths.root);
  return Object.freeze({
    root,
    decision: (decisionId: string) => root.collection("decisions").doc(decisionId),
    manualItem: (manualItemId: string) =>
      root.collection("manual_items").doc(manualItemId),
    auditEvent: (eventId: string) => root.collection("events").doc(eventId),
  });
}

export function supplierImportResolutionValueForFirestore(
  input: unknown,
): unknown {
  if (Array.isArray(input)) return input.map(supplierImportResolutionValueForFirestore);
  if (input === null || typeof input !== "object") return input;
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input as Record<string, unknown>)) {
    result[key] = timestampFields.has(key) && typeof value === "string" ?
      Timestamp.fromDate(new Date(value)) :
      supplierImportResolutionValueForFirestore(value);
  }
  return result;
}

const timestampFields = new Set([
  "createdAt", "updatedAt", "finalizedAt", "occurredAt",
]);

function fromFirestore(input: unknown): unknown {
  if (input instanceof Timestamp) return input.toDate().toISOString();
  if (Array.isArray(input)) return input.map(fromFirestore);
  if (input === null || typeof input !== "object") return input;
  return Object.fromEntries(Object.entries(input as Record<string, unknown>)
    .map(([key, value]) => [key, fromFirestore(value)]));
}
