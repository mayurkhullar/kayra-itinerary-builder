import {isDeepStrictEqual} from "node:util";
import {DocumentSnapshot, FieldPath, Firestore} from "firebase-admin/firestore";
import {SupplierImportFinalizationRequest, InvalidFinalizationState, supplierImportFinalizationPaths} from "./supplierImportFinalization";
import {FinalizationCapacityError, FinalizationInputBudget} from "./supplierImportFinalizationCapacity";
import {plainMap, resolutionFromFirestore, storedTimestampIso} from "./supplierImportFinalizationStored";
import {readSupplierExtractionSnapshot, SupplierExtractionPersistenceRecords} from "./supplierExtractionRepository";
import {adminSupplierExtractionRepositoryStore} from "./supplierExtractionRepositoryAdmin";
import {reconstructStoredSupplierImportResolution, StoredResolutionDocument} from "./supplierImportResolutionStoredValidation";
import {SupplierImportResolutionServerActor, requireSupplierImportResolutionAuthorization} from "./supplierImportResolutionMutationAdmin";
import {SupplierImportResolutionMutationError} from "./supplierImportResolutionMutation";
import {SupplierImportFinalizationError} from "./supplierImportFinalization";
import {SupplierExtractionSnapshot} from "./supplierExtractionSnapshot";
import {SupplierImportResolutionAggregate} from "./supplierImportResolution";
import {exact, identity} from "./itineraryDraftValidationPrimitives";

export interface LoadedSupplierImportFinalization {
  snapshot: SupplierExtractionSnapshot;
  snapshotRoot: Record<string, unknown>;
  resolution: SupplierImportResolutionAggregate;
}

export function authorizeFinalization(actor: SupplierImportResolutionServerActor, profile: DocumentSnapshot, trip: DocumentSnapshot): void {
  try {
    requireSupplierImportResolutionAuthorization(actor, profile.exists ? profile.data() : null, trip.exists ? trip.data() : null);
  } catch (error) {
    if (error instanceof SupplierImportResolutionMutationError) throw new SupplierImportFinalizationError("UNAUTHORIZED_OR_FORBIDDEN");
    throw error;
  }
}

/** Bounded reads before preparation. Root is read again AFTER all children so
 * no mixed-revision aggregate reaches assembly. The commit rechecks it again.
 * Existing stored validation requires the complete audit chain; retain that
 * check with bounded paging/bytes instead of weakening it to a partial history.
 */
export async function loadSupplierImportFinalizationAdmin(
  db: Firestore, actor: SupplierImportResolutionServerActor, request: SupplierImportFinalizationRequest,
): Promise<LoadedSupplierImportFinalization | "not_started" | "snapshot_unavailable" | {conflictRevision: number}> {
  const paths = supplierImportFinalizationPaths(request);
  const [profile, trip, extraction, root, receipt, event, draft] = await db.getAll(
    db.doc(`users/${actor.uid}`), db.doc(`trips/${request.tripId}`), db.doc(paths.snapshot), db.doc(paths.root),
    db.doc(paths.receipt), db.doc(paths.event), db.doc(paths.draft),
  );
  authorizeFinalization(actor, profile, trip);
  if (!extraction.exists) return "snapshot_unavailable";
  const rawSnapshot = plainMap(extraction.data());
  if (rawSnapshot.persistenceState !== "complete") return "snapshot_unavailable";
  if (!root.exists) {
    if (receipt.exists || event.exists || draft.exists) throw new InvalidFinalizationState();
    return "not_started";
  }
  const budget = new FinalizationInputBudget();
  for (const item of [profile, trip, extraction, root, receipt, event, draft]) if (item.exists) budget.add(item.data(), item.ref.path);
  const counts = plainMap(rawSnapshot.counts);
  if (Object.values(counts).some((value) => typeof value !== "number" || !Number.isSafeInteger(value) || value < 0)) throw new InvalidFinalizationState();
  const expectedEntities = Number(counts.days) + Number(counts.assignedServices) + Number(counts.unassignedServices) +
    Number(counts.packageFacts) + Number(counts.ancillaryFlights) + Number(counts.ancillaryVisas) +
    Number(counts.commercialIndicators) + Number(counts.reviewIssues);
  if (!Number.isSafeInteger(expectedEntities)) throw new InvalidFinalizationState();
  if (expectedEntities > 2000) throw new FinalizationCapacityError("inputs");
  const machineChildren = [];
  for (const name of ["days", "facts", "review_issues"]) {
    machineChildren.push(await readBounded(db, `${paths.snapshot}/${name}`, budget, 2000));
  }
  if (machineChildren.reduce((sum, items) => sum + items.length, 0) > 2000) throw new FinalizationCapacityError("inputs");
  const sourceStore = adminSupplierExtractionRepositoryStore(db);
  const sourcePackageId = identity(rawSnapshot.sourcePackageId, "Stored source package");
  const trustedPackage = await sourceStore.loadTrustedPackage(request.tripId, sourcePackageId);
  budget.add(trustedPackage);
  const childRecords = (items: StoredResolutionDocument<unknown>[]) => items.map((item) => {
    const map = exact(item.value, ["snapshotOrder", "value"], "Snapshot child");
    return {documentId: item.documentId, snapshotOrder: map.snapshotOrder, value: map.value};
  });
  const records = {root: {...rawSnapshot, createdAt: storedTimestampIso(rawSnapshot.createdAt)},
    days: childRecords(machineChildren[0]), facts: childRecords(machineChildren[1]),
    reviewIssues: childRecords(machineChildren[2])} as unknown as SupplierExtractionPersistenceRecords;
  const snapshot = await readSupplierExtractionSnapshot(request.tripId, request.extractionId, {
    ...sourceStore, readSnapshot: async () => records, loadTrustedPackage: async () => trustedPackage,
  });
  const decisions = await readBounded(db, paths.decisions, budget, 2000);
  const manualItems = await readBounded(db, paths.manualItems, budget, 2000 - decisions.length);
  const auditEvents = await readBounded(db, paths.auditEvents, budget);
  const latestRoot = await db.doc(paths.root).get();
  if (!latestRoot.exists) throw new InvalidFinalizationState();
  if (!isDeepStrictEqual(root.data(), latestRoot.data())) {
    const revision = latestRoot.get("revision");
    if (!Number.isSafeInteger(revision) || revision < 1) throw new InvalidFinalizationState();
    return {conflictRevision: revision};
  }
  const convert = (items: StoredResolutionDocument<unknown>[]) => items.map((item) => ({...item, value: resolutionFromFirestore(item.value)}));
  const resolution = reconstructStoredSupplierImportResolution(snapshot, {
    root: {documentId: root.id, value: resolutionFromFirestore(root.data())},
    decisions: convert(decisions), manualItems: convert(manualItems), auditEvents: convert(auditEvents),
  }, request.tripId, request.extractionId);
  if (!Number.isSafeInteger(resolution.root.revision)) throw new InvalidFinalizationState();
  if (resolution.root.status === "active") {
    if (receipt.exists || draft.exists) throw new InvalidFinalizationState();
    if (event.exists) return {conflictRevision: resolution.root.revision};
  }
  return {snapshot, snapshotRoot: rawSnapshot, resolution};
}

async function readBounded(db: Firestore, path: string, budget: FinalizationInputBudget, maximum = Infinity): Promise<StoredResolutionDocument<unknown>[]> {
  const rows: StoredResolutionDocument<unknown>[] = [];
  let cursor: DocumentSnapshot | undefined;
  while (true) {
    let query = db.collection(path).orderBy(FieldPath.documentId()).limit(Math.min(32, maximum + 1 - rows.length));
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const item of page.docs) {
      budget.add(item.data(), item.ref.path);
      rows.push({documentId: item.id, value: item.data()});
      if (rows.length > maximum) throw new FinalizationCapacityError("inputs");
    }
    if (page.empty) return rows;
    cursor = page.docs[page.docs.length - 1];
  }
}
