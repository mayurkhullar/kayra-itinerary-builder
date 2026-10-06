const {test} = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const {request, actor, now, opening, clone} = require('./supplierImportFinalization.fixtures.cjs');
const {prepareSupplierImportFinalization: prepare} = require('../lib/itineraryExtraction/supplierImportFinalizationPlan');
const {itineraryDraftV2ForFirestore: encodeDraft, readStoredItineraryDraftV2: readDraft,
  finalizationReceiptForFirestore: encodeReceipt, readStoredFinalizationReceipt: readReceipt} = require('../lib/itineraryExtraction/supplierImportFinalizationStored');
const {itineraryDraftV2ToMap: draftMap} = require('../lib/itineraryExtraction/itineraryDraftV2Validation');
const {supplierImportFinalizationReceiptToMap: receiptMap} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptValidation');
const {supplierImportCanonicalContentDigest: digest} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptDigest');
const {validateDraftPayload, DraftBoundaryError} = require('../lib/itineraryExtraction/draftValidation');

function plan() {
  const source = f.snapshot({days: [f.day({date: '2027-01-01', services: [f.service({type: 'hotel', hotelDetails: {
    hotelName: 'Hotel', checkInDate: '2027-01-01', checkOutDate: '2027-01-03', roomType: 'Twin',
  }})]})], packageFacts: {accommodations: [{hotelName: 'Other hotel', checkInDate: '2027-01-03', checkOutDate: '2027-01-04'}]}});
  return prepare(source, f.aggregate(source, {auditEvents: [opening()]}), request(), actor.uid, now);
}

test('V2 persisted Timestamp dates round-trip without changing canonical digest or field order', () => {
  const p = plan(), stored = encodeDraft(p.candidate), read = readDraft(p.candidate.id, stored);
  assert(stored.createdAt instanceof Timestamp); assert(stored.updatedAt instanceof Timestamp);
  assert(stored.days[0].date instanceof Timestamp);
  assert(stored.days[0].services[0].hotelDetails.checkInDate instanceof Timestamp);
  assert(stored.days[0].services[0].hotelDetails.checkOutDate instanceof Timestamp);
  assert.equal(stored.packageContent.accommodations[0].options[0].details.checkInDate, '2027-01-03');
  assert.deepEqual(draftMap(read), draftMap(p.candidate)); assert.equal(digest(read), p.receipt.contentDigest);
  assert.equal(JSON.stringify(draftMap(read)), JSON.stringify(draftMap(p.candidate)));
});
test('receipt persisted Timestamp round-trips exactly with explicit schema', () => {
  const p = plan(), stored = encodeReceipt(p.receipt);
  assert.equal(stored.schemaVersion, 'supplier_import_finalization_v1'); assert(stored.finalizedAt instanceof Timestamp);
  assert.deepEqual(receiptMap(readReceipt(stored)), receiptMap(p.receipt));
});
for (const [name, alter] of [
  ['V1 absent version', (s) => {delete s.schemaVersion;}],
  ['explicit V1 version', (s) => {s.schemaVersion = 'itinerary_draft_v1';}],
  ['future version', (s) => {s.schemaVersion = 'itinerary_draft_v3';}],
  ['unknown root key', (s) => {s.extra = true;}],
  ['unknown nested key', (s) => {s.days[0].extra = true;}],
  ['undefined field', (s) => {s.days[0].summary = undefined;}],
  ['timestamp string', (s) => {s.createdAt = now;}],
  ['JS Date', (s) => {s.createdAt = new Date(now);}],
  ['sub-millisecond timestamp', (s) => {s.createdAt = new Timestamp(s.createdAt.seconds, 1);}],
  ['non-midnight day date', (s) => {s.days[0].date = Timestamp.fromMillis(s.days[0].date.toMillis() + 1);}],
  ['string timeline date', (s) => {s.days[0].date = '2027-01-01';}],
  ['invalid package date', (s) => {s.packageContent.accommodations[0].options[0].details.checkInDate = '2027-02-30';}],
  ['sparse day array', (s) => {delete s.days[0];}],
  ['extra array property', (s) => {s.days.extra = true;}],
  ['hidden unknown root field', (s) => {Object.defineProperty(s, 'hidden', {value: true});}],
  ['accessor root field', (s) => {Object.defineProperty(s, 'title', {get() {throw new Error('must not evaluate');}});}],
]) test(`stored V2 rejects ${name}`, () => {
  const p = plan(), stored = clone(encodeDraft(p.candidate)); alter(stored);
  assert.throws(() => readDraft(p.candidate.id, stored), /Stored Supplier Import finalization state is invalid/);
});
for (const [name, alter] of [
  ['unknown field', (s) => {s.extra = true;}],
  ['unknown nested field', (s) => {s.outcomes[0].extra = true;}],
  ['future version', (s) => {s.schemaVersion = 'supplier_import_finalization_v2';}],
  ['undefined', (s) => {s.actorUid = undefined;}],
  ['wrong revision', (s) => {s.resultingRevision++;}],
  ['timestamp string', (s) => {s.finalizedAt = now;}],
  ['sub-millisecond time', (s) => {s.finalizedAt = new Timestamp(s.finalizedAt.seconds, 1);}],
]) test(`stored receipt rejects ${name}`, () => {
  const stored = clone(encodeReceipt(plan().receipt)); alter(stored); assert.throws(() => readReceipt(stored));
});
test('serializers reject undefined and unknown domain fields instead of silently persisting them', () => {
  const p = plan();
  for (const extra of [{unexpected: true}, {title: undefined}]) assert.throws(() => encodeDraft({...p.candidate, ...extra}));
  for (const extra of [{unexpected: true}, {actorUid: undefined}]) assert.throws(() => encodeReceipt({...p.receipt, ...extra}));
});
test('V2 canonical storage is rejected by the unchanged strict V1 write boundary', () => {
  const trustedPackage = {tripId: 'trip-1', packageId: 'package-1', supplierId: 'supplier-1', supplierNameSnapshot: 'Synthetic Supplier',
    files: [{sourceFileId: 'file-1', packageId: 'package-1', originalFileName: 'source.pdf', storagePath: 'trips/trip-1/supplier_sources/file-1/source.pdf',
      contentType: 'application/pdf', sizeBytes: 100, uploadedByUid: actor.uid}]};
  assert.throws(() => validateDraftPayload(encodeDraft(plan().candidate), trustedPackage), (error) => error instanceof DraftBoundaryError);
});
