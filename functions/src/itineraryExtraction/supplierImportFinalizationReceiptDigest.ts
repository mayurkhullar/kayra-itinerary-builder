import {createHash} from "node:crypto";
import type {ItineraryDraftV2} from "./itineraryDraftV2";
import {itineraryDraftV2ToMap} from "./itineraryDraftV2Validation";
import type {SupplierImportFinalizationReceiptContext} from "./supplierImportFinalizationReceipt";

/** V1 binding: UTF-8 SHA-256, lowercase hex, authoritative V2 map key order;
 * omit only root server timestamps. Travel dates and importResult remain bound.
 * The document ID is external to the canonical map and is linked by the receipt.
 */
export function supplierImportCanonicalContentDigest(candidate: ItineraryDraftV2): string {
  const {createdAt: _createdAt, updatedAt: _updatedAt, ...payload} = itineraryDraftV2ToMap(candidate);
  return sha256(JSON.stringify(payload));
}

/** Called only after command metadata validation. Timestamp is intentionally
 * absent so the same logical retry has the same fingerprint. Key order is the
 * explicit v1 command contract, independent of caller insertion order.
 */
export function finalizationRequestFingerprint(
  context: Omit<SupplierImportFinalizationReceiptContext, "finalizedAt">,
): string {
  return sha256(JSON.stringify({
    tripId: context.tripId, extractionId: context.extractionId, commandId: context.commandId,
    expectedRevision: context.expectedRevision, policyVersion: context.policyVersion, actorUid: context.actorUid,
  }));
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
