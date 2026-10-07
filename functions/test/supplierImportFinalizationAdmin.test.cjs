const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {Timestamp} = require('firebase-admin/firestore');
const {fixture, request, actor, now, opening, advance, clone} = require('./supplierImportFinalization.fixtures.cjs');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const {finalizeSupplierImportAdmin: finalize} = require('../lib/itineraryExtraction/supplierImportFinalizationAdmin');
const {SupplierImportFinalizationError, supplierImportFinalizationPaths: pathsFor} = require('../lib/itineraryExtraction/supplierImportFinalization');
const {readStoredItineraryDraftV2: readDraft, readStoredFinalizationReceipt: readReceipt, resolutionFromFirestore: decode} = require('../lib/itineraryExtraction/supplierImportFinalizationStored');
const {supplierImportCanonicalContentDigest: digest} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptDigest');
const {reconstructStoredSupplierImportResolution: reconstruct} = require('../lib/itineraryExtraction/supplierImportResolutionStoredValidation');
const {mutateSupplierImportResolution: mutate} = require('../lib/itineraryExtraction/supplierImportResolutionMutation');
const {supplierImportResolutionValueForFirestore: encode} = require('../lib/itineraryExtraction/supplierImportResolutionRepositoryAdmin');
const run = (x, req = request(), who = actor) => finalize(x.db, who, req);
const before = (x) => clone([...x.db.records]);
const unchanged = (x, state) => {assert.deepEqual([...x.db.records], state); assert.equal(x.db.commits.length, 0);};
const errorCode = (code) => (err) => err instanceof SupplierImportFinalizationError && err.code === code;
function resolution(x) {
  const children = (prefix) => [...x.db.records].filter(([p]) => p.startsWith(prefix + '/')).map(([p, value]) => ({documentId: p.split('/').at(-1), value: decode(value)}));
  return reconstruct(x.source, {root: {documentId: 'extraction-1', value: decode(x.db.records.get(x.paths.root))},
    decisions: children(x.paths.decisions), manualItems: children(x.paths.manualItems), auditEvents: children(x.paths.auditEvents)}, 'trip-1', 'extraction-1');
}

test('ready untouched import establishes exactly four atomic artifacts at documented paths', async (t) => {
  t.mock.method(Timestamp, 'now', () => Timestamp.fromDate(new Date(now)));
  const x = fixture({days: [f.day({date: '2027-01-01'})], packageFacts: {accommodations: [{hotelName: 'Hotel', checkInDate: '2027-01-01', checkOutDate: '2027-01-03'}]}});
  const result = await run(x);
  assert.equal(result.outcome, 'applied'); assert.equal(result.revision, 2);
  assert.equal(x.db.commits.length, 1); assert.equal(x.db.commits[0].length, 4);
  assert.deepEqual(x.db.commits[0].map(({kind, path}) => [kind, path]), [['create', x.paths.draft], ['create', x.paths.receipt], ['update', x.paths.root], ['create', x.paths.event]]);
  assert.equal(x.paths.receipt, 'trips/trip-1/supplier_extractions/extraction-1/resolutions/extraction-1/finalizations/finalize-1');
  assert.equal(x.paths.event, 'trips/trip-1/supplier_extractions/extraction-1/resolutions/extraction-1/events/finalize-1');
  assert.match(result.resultingDraftId, /^supplier-import-[0-9a-f]{64}$/);
  const draft = readDraft(result.resultingDraftId, x.db.records.get(x.paths.draft));
  const receipt = readReceipt(x.db.records.get(x.paths.receipt));
  assert.equal(draft.schemaVersion, 'itinerary_draft_v2'); assert.equal(receipt.contentDigest, digest(draft));
  assert.equal(receipt.evaluatedRevision, 1); assert.equal(receipt.resultingRevision, 2);
  assert.equal(receipt.commandId, request().commandId); assert.equal(receipt.finalizationId, request().commandId);
  assert.equal(draft.importResult.finalizationId, receipt.finalizationId); assert.equal(draft.importResult.evaluatedRevision, 1);
  const sealed = resolution(x); assert.equal(sealed.root.status, 'finalized'); assert.equal(sealed.root.revision, 2);
  assert.equal(sealed.root.resultingDraftId, result.resultingDraftId); assert.equal(sealed.root.finalizedAt, now);
  assert.equal(sealed.root.createdAt, f.at); assert.equal(sealed.root.createdByUid, actor.uid);
  assert.deepEqual(sealed.auditEvents[1], {...opening(), eventId: request().commandId, commandId: request().commandId,
    previousRevision: 1, resultingRevision: 2, occurredAt: now, action: 'finalize', targetKind: 'finalization',
    targetId: request().commandId, metadata: {kind: 'lifecycle', status: 'finalized'}});
  assert.equal(x.db.reads.includes(`${x.paths.snapshot}/facts/staged-service-1`), true);
  assert.equal(receipt.outcomes.every((item) => item.outcome === 'auto_retained'), true);
});

test('active Admin may finalize another Agent Trip using authoritative role', async () => {
  const x = fixture(); x.db.replace('users/admin-1', {role: 'admin', status: 'active'});
  assert.equal((await run(x, request(), {uid: 'admin-1', email: 'admin@kholidaymaps.com'})).outcome, 'applied');
  assert.equal(x.db.records.get(x.paths.root).finalizedByUid, 'admin-1');
});
for (const [name, setup, who] of [
  ['non-owner', (x) => x.db.replace('trips/trip-1', {ownerUid: 'other'})],
  ['inactive', (x) => x.db.replace('users/agent-1', {role: 'agent', status: 'inactive'})],
  ['unsupported role', (x) => x.db.replace('users/agent-1', {role: 'owner', status: 'active'})],
  ['missing profile', (x) => x.db.records.delete('users/agent-1')],
  ['missing Trip', (x) => x.db.records.delete('trips/trip-1')],
  ['wrong domain', () => {}, {uid: actor.uid, email: 'agent@outside.com'}],
  ['lookalike domain', () => {}, {uid: actor.uid, email: 'agent@kholidaymaps.com.other.com'}],
]) test(`${name} is denied with no writes`, async () => {const x = fixture(); setup(x); const old = before(x); await assert.rejects(() => run(x, request(), who), errorCode('UNAUTHORIZED_OR_FORBIDDEN')); unchanged(x, old);});

for (const field of ['snapshot', 'resolution', 'candidate', 'receipt', 'role', 'sourcePackageId', 'actorUid', 'finalizedAt', 'resultingDraftId', 'finalizationId']) {
  test(`request cannot inject ${field}`, async () => {const x = fixture(); await assert.rejects(() => run(x, request({[field]: 'untrusted'})), errorCode('INVALID_FINALIZATION_REQUEST')); assert.equal(x.db.reads.length, 0);});
}
for (const [field, value] of [['expectedRevision', 0], ['expectedRevision', Number.MAX_SAFE_INTEGER], ['expectedRevision', 1.5],
  ['tripId', '../bad'], ['extractionId', ''], ['commandId', 'x'.repeat(129)], ['policyVersion', 'future']]) {
  test(`invalid ${field} fails before reads`, async () => {const x = fixture(); await assert.rejects(() => run(x, request({[field]: value})), errorCode('INVALID_FINALIZATION_REQUEST')); assert.equal(x.db.reads.length, 0);});
}

test('missing/incomplete Snapshot and missing Resolution are explicit safe results', async () => {
  for (const [target, expected] of [['snapshot', 'snapshot_unavailable'], ['root', 'resolution_not_started']]) {
    const x = fixture(); x.db.records.delete(x.paths[target]); const old = before(x); assert.equal((await run(x)).outcome, expected); unchanged(x, old);
  }
  const x = fixture(); x.db.records.get(x.paths.snapshot).persistenceState = 'writing'; const old = before(x);
  assert.equal((await run(x)).outcome, 'snapshot_unavailable'); unchanged(x, old);
});
test('missing Resolution with an orphaned output fails closed', async () => {
  const x = fixture(); x.db.records.delete(x.paths.root); x.db.replace(x.paths.receipt, {schemaVersion: 'partial'});
  const old = before(x); assert.equal((await run(x)).outcome, 'trusted_state_invalid'); unchanged(x, old);
});
for (const [name, mutateData] of [
  ['Snapshot source relationship', (x) => x.db.records.get(`${x.paths.snapshot}/facts/staged-service-1`).value.sources[0].supplierSourcePackageId = 'foreign'],
  ['Snapshot unknown child key', (x) => x.db.records.get(`${x.paths.snapshot}/facts/staged-service-1`).extra = true],
  ['Snapshot missing child', (x) => x.db.records.delete(`${x.paths.snapshot}/facts/staged-service-1`)],
  ['Resolution schema', (x) => x.db.records.get(x.paths.root).schemaVersion = 'future'],
  ['Resolution linkage', (x) => x.db.records.get(x.paths.root).sourcePackageId = 'foreign'],
  ['Resolution missing audit history', (x) => x.db.records.delete(`${x.paths.auditEvents}/open-1`)],
  ['Resolution foreign decision', (x) => x.db.replace(`${x.paths.decisions}/staged-day-99`, encode(f.dayDecision('staged-day-99')))],
]) test(`authoritative ${name} corruption prevents all writes`, async () => {const x = fixture(); mutateData(x); const old = before(x); assert.equal((await run(x)).outcome, 'trusted_state_invalid'); unchanged(x, old);});

for (const payload of [{unassignedServices: [f.service()]}, {reviewIssues: [f.issue({severity: 'blocker'})]}]) {
  test(`blocked ${Object.keys(payload)[0]} returns safe findings without any partial result`, async () => {
    const x = fixture(payload), old = before(x), result = await run(x);
    assert.equal(result.outcome, 'not_ready'); assert.equal(result.assessment.canFinalize, false); assert(result.assessment.blockers.length > 0);
    assert(!JSON.stringify(result).includes('Museum visit')); assert(!Object.hasOwn(result, 'candidate')); unchanged(x, old);
  });
}

test('stale expected revision writes nothing', async () => {const x = fixture(); advance(x); const old = before(x); assert.deepEqual(await run(x), {outcome: 'resolution_conflict', resolutionId: 'extraction-1', currentRevision: 2}); unchanged(x, old);});
test('concurrent child mutation root advance during preflight is detected', async () => {
  const x = fixture(); let changed = false; x.db.beforeQuery = (path) => {if (!changed && path === x.paths.decisions) {changed = true; advance(x);}};
  assert.equal((await run(x)).outcome, 'resolution_conflict'); assert.equal(x.db.commits.length, 0);
});
test('root advance after assembly prevents stale transaction commit', async () => {
  const x = fixture(); x.db.beforeTransaction = () => advance(x); const result = await run(x);
  assert.equal(result.outcome, 'resolution_conflict'); assert.equal(x.db.commits.length, 0); assert(!x.db.records.has(x.paths.draft));
});
test('optimistic retry after a committed concurrent mutation rejects the stale plan', async () => {
  const x = fixture(); x.db.beforeCommit = (attempt) => {if (!attempt) advance(x);};
  assert.equal((await run(x)).outcome, 'resolution_conflict'); assert.equal(x.db.commits.length, 0); assert(!x.db.records.has(x.paths.receipt));
});
test('existing Admin child mutation atomically advances the root and invalidates a prepared finalization', async () => {
  const {applySupplierImportResolutionMutationAdmin: applyMutation} = require('../lib/itineraryExtraction/supplierImportResolutionMutationAdmin');
  const x = fixture();
  x.db.beforeTransaction = async () => {
    x.db.beforeTransaction = null;
    const result = await applyMutation(x.db, actor, {tripId: 'trip-1', extractionId: 'extraction-1', commandId: 'correct-day',
      expectedRevision: 1, mutation: {action: 'set_decision', decision: {decisionKind: 'day', targetEntityId: 'staged-day-1',
        disposition: 'retain', overrides: {title: f.set('Corrected day')}, exclusionReason: null, exclusionNote: null}}}, new Date(now));
    assert.equal(result.outcome, 'applied'); assert.equal(result.revision, 2);
  };
  assert.equal((await run(x)).outcome, 'resolution_conflict');
  assert.equal(x.db.commits.length, 1);
  assert.deepEqual(x.db.commits[0].map(({path}) => path), [x.paths.root, `${x.paths.decisions}/staged-day-1`, `${x.paths.auditEvents}/correct-day`]);
  assert.equal(x.db.records.get(x.paths.root).revision, 2); assert(!x.db.records.has(x.paths.draft)); assert(!x.db.records.has(x.paths.receipt));
});
for (const target of ['profile', 'owner']) test(`authorization ${target} is rechecked in transaction`, async () => {
  const x = fixture(); x.db.beforeTransaction = () => x.db.replace(target === 'profile' ? 'users/agent-1' : 'trips/trip-1',
    target === 'profile' ? {role: 'agent', status: 'inactive'} : {ownerUid: 'other'});
  await assert.rejects(() => run(x), errorCode('UNAUTHORIZED_OR_FORBIDDEN')); assert.equal(x.db.commits.length, 0);
});
test('Snapshot root is rechecked inside transaction', async () => {
  const x = fixture(); x.db.beforeTransaction = () => x.db.replace(x.paths.snapshot, {...x.db.records.get(x.paths.snapshot), persistenceState: 'writing'});
  assert.equal((await run(x)).outcome, 'trusted_state_invalid'); assert.equal(x.db.commits.length, 0);
});
test('transaction callback retry uses identical IDs, values and one logical timestamp', async (t) => {
  let calls = 0; t.mock.method(Timestamp, 'now', () => {calls++; return Timestamp.fromMillis(Date.parse(now) + calls);});
  const x = fixture(); x.db.retryOnce = true; assert.equal((await run(x)).outcome, 'applied');
  assert.equal(calls, 1); assert.equal(x.db.attempts.length, 2); assert.deepEqual(x.db.attempts[0], x.db.attempts[1]); assert.equal(x.db.commits.length, 1);
});

test('same logical retry returns already_applied without rewriting any artifact', async () => {
  const x = fixture(), first = await run(x), old = before(x), writes = x.db.commits.length;
  const again = await run(x); assert.deepEqual(again, {...first, outcome: 'already_applied'});
  assert.deepEqual([...x.db.records], old); assert.equal(x.db.commits.length, writes); assert.equal(x.db.records.get(x.paths.root).revision, 2);
});
test('replay verifies original digest from sealed inputs and tolerates later canonical edits', async () => {
  const x = fixture(); await run(x); const draft = x.db.records.get(x.paths.draft);
  x.db.replace(x.paths.draft, {...draft, title: 'Later consultant edit', updatedAt: Timestamp.fromMillis(draft.updatedAt.toMillis() + 1000)});
  const old = before(x); assert.equal((await run(x)).outcome, 'already_applied'); assert.deepEqual([...x.db.records], old);
});
test('different command cannot reopen finalized Resolution', async () => {
  const x = fixture(); await run(x); const old = before(x); assert.equal((await run(x, request({commandId: 'finalize-2'}))).outcome, 'resolution_finalized'); assert.deepEqual([...x.db.records], old);
});
test('same command with different revision or authorized actor conflicts', async () => {
  const x = fixture(); await run(x); x.db.replace('users/admin-1', {role: 'admin', status: 'active'}); const old = before(x);
  assert.equal((await run(x, request({expectedRevision: 2}))).outcome, 'resolution_conflict');
  assert.equal((await run(x, request(), {uid: 'admin-1', email: 'admin@kholidaymaps.com'})).outcome, 'resolution_conflict'); assert.deepEqual([...x.db.records], old);
});
for (const target of ['draft', 'receipt', 'event']) test(`existing ${target} is never overwritten`, async () => {
  const x = fixture(); x.db.replace(x.paths[target], {unrelated: true}); const old = before(x), result = await run(x);
  assert(['trusted_state_invalid', 'resolution_conflict'].includes(result.outcome)); unchanged(x, old);
});
for (const [name, corrupt] of [
  ['receipt fingerprint', (x) => x.db.records.get(x.paths.receipt).requestFingerprint = 'a'.repeat(64)],
  ['receipt digest', (x) => x.db.records.get(x.paths.receipt).contentDigest = 'a'.repeat(64)],
  ['receipt outcome', (x) => x.db.records.get(x.paths.receipt).outcomes.pop()],
  ['different root draft', (x) => x.db.records.get(x.paths.root).resultingDraftId = 'other'],
  ['different draft lineage', (x) => x.db.records.get(x.paths.draft).importResult.finalizationId = 'other'],
  ['event actor', (x) => x.db.records.get(x.paths.event).actorUid = 'other'],
  ['event revision', (x) => x.db.records.get(x.paths.event).resultingRevision = 3],
  ['missing receipt', (x) => x.db.records.delete(x.paths.receipt)],
  ['missing draft', (x) => x.db.records.delete(x.paths.draft)],
  ['missing event', (x) => x.db.records.delete(x.paths.event)],
]) test(`replay ${name} corruption fails closed without repair`, async () => {
  const x = fixture(); await run(x); corrupt(x); const old = before(x), commits = x.db.commits.length;
  assert.equal((await run(x)).outcome, 'trusted_state_invalid'); assert.deepEqual([...x.db.records], old); assert.equal(x.db.commits.length, commits);
});

for (let index = 1; index <= 4; index++) test(`failure queueing finalization write ${index} commits none`, async () => {
  const x = fixture(), old = before(x); x.db.failWrite = index;
  await assert.rejects(() => run(x), errorCode('FINALIZATION_PERSISTENCE_FAILED')); unchanged(x, old);
});
test('transaction abort commits none and exposes no raw SDK text', async () => {
  const x = fixture(), old = before(x); x.db.commitError = Object.assign(new Error('private supplier gs://secret/path SDK payload'), {code: 10});
  await assert.rejects(() => run(x), (error) => errorCode('FINALIZATION_PERSISTENCE_FAILED')(error) && !JSON.stringify(error).includes('private') && !error.message.includes('secret') && !error.cause);
  unchanged(x, old);
});
test('receipt factory rejection happens before any transaction or write', async (t) => {
  const factory = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptFactory');
  const {SupplierImportFinalizationReceiptError} = require('../lib/itineraryExtraction/supplierImportFinalizationReceipt');
  t.mock.method(factory, 'createSupplierImportFinalizationReceipt', () => {throw new SupplierImportFinalizationReceiptError('Invalid synthetic receipt');});
  const x = fixture(), old = before(x); assert.equal((await run(x)).outcome, 'trusted_state_invalid');
  assert.equal(x.db.attempts.length, 0); unchanged(x, old);
});
test('concurrent identical command committed after preparation is recognized despite different server time', async (t) => {
  t.mock.method(Timestamp, 'now', () => Timestamp.fromDate(new Date(now)));
  const committed = fixture(); await run(committed);
  t.mock.method(Timestamp, 'now', () => Timestamp.fromMillis(Date.parse(now) + 1000));
  const x = fixture(); x.db.beforeTransaction = () => {
    for (const name of ['draft', 'receipt', 'root', 'event']) x.db.replace(x.paths[name], committed.db.records.get(committed.paths[name]));
  };
  assert.equal((await run(x)).outcome, 'already_applied'); assert.equal(x.db.commits.length, 0);
});
test('concurrent different finalization cannot overwrite the winner', async () => {
  const winner = fixture(), otherRequest = request({commandId: 'other-finalization'});
  await run(winner, otherRequest);
  const x = fixture(); x.db.beforeTransaction = () => {
    const paths = pathsFor(otherRequest);
    for (const name of ['draft', 'receipt', 'root', 'event']) x.db.replace(paths[name], winner.db.records.get(paths[name]));
  };
  assert.equal((await run(x)).outcome, 'resolution_finalized'); assert.equal(x.db.commits.length, 0);
});
test('Firestore INVALID_ARGUMENT document size failure becomes a safe capacity result', async () => {
  const x = fixture(), old = before(x); x.db.commitError = Object.assign(new Error('Document is too large: private content'), {code: 3});
  assert.deepEqual(await run(x), {outcome: 'persistence_capacity_exceeded', resolutionId: 'extraction-1', boundary: 'firestore'}); unchanged(x, old);
});
test('lost commit acknowledgement is resolved by exact retry without duplicate writes', async () => {
  const x = fixture(); x.db.afterCommitError = Object.assign(new Error('unavailable'), {code: 14});
  await assert.rejects(() => run(x), errorCode('FINALIZATION_PERSISTENCE_FAILED'));
  assert.equal(x.db.commits.length, 1); x.db.afterCommitError = null;
  assert.equal((await run(x)).outcome, 'already_applied'); assert.equal(x.db.commits.length, 1);
});
for (const code of [8, 'resource-exhausted', 'RESOURCE_EXHAUSTED']) test(`Firestore capacity ${code} returns sanitized capacity outcome`, async () => {
  const x = fixture(), old = before(x); x.db.commitError = Object.assign(new Error('private quota payload'), {code});
  assert.deepEqual(await run(x), {outcome: 'persistence_capacity_exceeded', resolutionId: 'extraction-1', boundary: 'firestore'}); unchanged(x, old);
});

test('finalized Resolution is mutation-locked by the existing mutation engine', async () => {
  const x = fixture(); await run(x); let writes = 0;
  const result = await mutate(x.source, {tripId: 'trip-1', extractionId: 'extraction-1', expectedRevision: 2, commandId: 'edit-after-seal', mutation: {action: 'remove_decision', decisionId: 'staged-day-1'}},
    {uid: actor.uid}, now, {runTransaction: (operation) => operation({readState: async () => ({aggregate: resolution(x), existingCommandEvent: null}), commit: () => writes++})});
  assert.equal(result.outcome, 'resolution_finalized'); assert.equal(writes, 0);
});
test('current decisions and audit chain are loaded from authoritative collections', async () => {
  const x = fixture(); advance(x); x.db.replace(`${x.paths.decisions}/staged-day-1`, encode(f.dayDecision('staged-day-1', {lastRevision: 2, overrides: {title: f.set('Consultant corrected day')}})));
  assert.equal((await run(x, request({expectedRevision: 2}))).outcome, 'applied');
  assert.equal(x.db.records.get(x.paths.draft).days[0].title, 'Consultant corrected day'); assert.equal(resolution(x).root.revision, 3);
});
test('Admin engine remains internal and logs no source/canonical/SDK payload', () => {
  const dir = path.join(__dirname, '../src/itineraryExtraction');
  for (const file of ['supplierImportFinalizationAdmin.ts', 'supplierImportFinalizationLoaderAdmin.ts', 'supplierImportFinalizationPlan.ts']) {
    const text = fs.readFileSync(path.join(dir, file), 'utf8');
    assert(!/from ["']firebase\//.test(text)); assert(!/console\.|logger\.|onCall\(|generateContent\(|fetch\(/.test(text));
  }
  // The callable may delegate to this engine; persistence remains internal.
  assert(!fs.readFileSync(path.join(dir, 'supplierImportFinalizationAdmin.ts'), 'utf8').includes('onCall('));
});

for (const [index, value] of ['Commission 12%', 'CNY 500'].entries()) {
  test(`injected commercial Snapshot variant ${index} cannot create any finalization evidence`, async () => {
    const x = fixture();
    x.db.records.get(`${x.paths.snapshot}/facts/staged-service-1`).value.notes = value;
    const old = before(x), result = await run(x);
    assert.equal(result.outcome, 'trusted_state_invalid');
    assert.equal(JSON.stringify(result).includes(value), false);
    unchanged(x, old);
  });
}
