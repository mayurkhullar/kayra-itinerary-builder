const {test} = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');
const {finalizationPayloadLimits: limits, finalizationPayloadBytes: bytes, requireFinalizationBudget: requireBudget,
  checkFinalizationWriteBudgets: check, FinalizationInputBudget, FinalizationCapacityError, isFirestoreCapacityError} = require('../lib/itineraryExtraction/supplierImportFinalizationCapacity');
const {fixture, request, actor, clone} = require('./supplierImportFinalization.fixtures.cjs');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const {finalizeSupplierImportAdmin: finalize} = require('../lib/itineraryExtraction/supplierImportFinalizationAdmin');
const boundary = (name) => (error) => error instanceof FinalizationCapacityError && error.boundary === name;

test('payload estimator counts UTF-8, document paths and structural reserve, not string length', () => {
  assert.equal(bytes({text: '旅程'}) - bytes({text: 'ab'}), 4);
  assert.equal(bytes({}, '旅程') - bytes({}, 'ab'), 4);
  assert(bytes({text: 'x'}) > Buffer.byteLength(JSON.stringify({text: 'x'}), 'utf8'));
  assert(bytes({time: Timestamp.fromMillis(1000)}) > 0);
});
for (const [name, limit] of Object.entries(limits)) test(`${name} budget accepts its inclusive boundary and rejects one byte over`, () => {
  requireBudget(name, limit); assert.throws(() => requireBudget(name, limit + 1), boundary(name));
});
for (const [name, value] of [['undefined', {bad: undefined}], ['NaN', {bad: NaN}], ['Date', new Date()],
  ['custom prototype', Object.create({inherited: true})], ['sparse array', new Array(1)],
  ['extra array field', Object.assign([], {extra: 1})]]) {
  test(`budget traversal rejects ${name} instead of silently omitting it`, () => assert.throws(() => bytes(value)));
}
test('budget traversal never invokes input accessors', () => {
  let calls = 0; const input = []; Object.defineProperty(input, '0', {enumerable: true, get() {calls++; return 1;}});
  assert.throws(() => bytes(input)); assert.equal(calls, 0);
});
test('deep nesting stops before the platform depth limit', () => {
  let data = 'leaf'; for (let i = 0; i < 19; i++) data = {nested: data};
  assert.throws(() => bytes(data), boundary('nesting'));
});
test('total authoritative input budget is cumulative across separate documents', () => {
  const budget = new FinalizationInputBudget(), chunk = {text: 'x'.repeat(1024 * 1024)};
  for (let i = 0; i < 15; i++) budget.add(chunk);
  assert.throws(() => budget.add(chunk), boundary('inputs'));
});
test('combined commit reserve rejects documents that each fit their individual budgets', () => {
  const writes = {canonical: {path: 'canonical', data: {packageContent: {}, text: 'x'.repeat(760 * 1024)}},
    receipt: {path: 'receipt', data: {text: 'x'.repeat(250 * 1024)}},
    resolution: {path: 'resolution', data: {text: 'x'.repeat(20 * 1024)}},
    event: {path: 'event', data: {text: 'x'.repeat(20 * 1024)}}};
  for (const [name, item] of Object.entries(writes)) requireBudget(name, bytes(item.data, item.path));
  assert.throws(() => check(writes), boundary('commit'));
});
for (const [name, payload, expected] of [
  ['oversize canonical', {days: [f.day({notes: 'x'.repeat(800 * 1024)})]}, 'canonical'],
  ['oversize package content', {packageFacts: {inclusions: [{category: 'other', text: 'x'.repeat(270 * 1024)}]}}, 'package_content'],
  ['oversize receipt ledger', {days: Array.from({length: 500}, (_, i) => f.day({title: `Day ${i + 1}`, services: []}))}, 'receipt'],
]) test(`${name} blocks before the transaction and preserves all source evidence without truncation`, async () => {
  const x = fixture(payload), old = clone([...x.db.records]);
  assert.deepEqual(await finalize(x.db, actor, request()), {outcome: 'persistence_capacity_exceeded', resolutionId: 'extraction-1', boundary: expected});
  assert.deepEqual([...x.db.records], old); assert.equal(x.db.commits.length, 0); assert.equal(x.db.attempts.length, 0);
});
test('Snapshot entity guard rejects over 2000 before loading all child documents', async () => {
  const x = fixture(); x.db.records.get(x.paths.snapshot).counts.days = 2001;
  assert.equal((await finalize(x.db, actor, request())).boundary, 'inputs');
  assert(!x.db.reads.some((p) => p.startsWith(x.paths.snapshot + '/days/'))); assert.equal(x.db.commits.length, 0);
});
test('decisions plus manual items share the 2000-document input bound', async () => {
  const x = fixture();
  for (let i = 0; i < 2000; i++) x.db.replace(`${x.paths.decisions}/decision-${i}`, {bounded: true});
  x.db.replace(`${x.paths.manualItems}/one-over`, {bounded: true});
  const old = clone([...x.db.records]); assert.equal((await finalize(x.db, actor, request())).boundary, 'inputs');
  assert.deepEqual([...x.db.records], old); assert.equal(x.db.commits.length, 0);
});
test('large authoritative documents trigger the input byte bound before validation or writes', async () => {
  const x = fixture(); x.db.records.get(`${x.paths.snapshot}/facts/staged-service-1`).value.notes = 'x'.repeat(16 * 1024 * 1024);
  const old = clone([...x.db.records]); assert.equal((await finalize(x.db, actor, request())).boundary, 'inputs');
  assert.deepEqual([...x.db.records], old); assert.equal(x.db.commits.length, 0);
});
test('Firestore known resource-size errors classify without exposing raw text', () => {
  assert(isFirestoreCapacityError({code: 3, message: 'Document is too large: private payload'}));
  assert(isFirestoreCapacityError({code: 'invalid-argument', message: 'Request exceeds maximum size'}));
  assert(!isFirestoreCapacityError({code: 3, message: 'Unrelated malformed query'}));
  assert(!isFirestoreCapacityError({code: 14, message: 'unavailable'}));
});
