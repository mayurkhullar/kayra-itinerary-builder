const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {HttpsError} = require('firebase-functions/v2/https');
const {handleSupplierImportFinalization: handle, parseSupplierImportFinalizationRequest: parse} = require('../lib/itineraryExtraction/supplierImportFinalizationCallable');
const {SupplierImportFinalizationError} = require('../lib/itineraryExtraction/supplierImportFinalization');
const {itineraryDraftV2ImportPolicy: policyVersion} = require('../lib/itineraryExtraction/itineraryDraftV2');
const auth = {uid: 'agent-1', token: {email: 'agent@kholidaymaps.com', role: 'admin', secret: 'AUTH TOKEN PRIVATE'}};
const request = (extra = {}) => ({tripId: 'trip-1', extractionId: 'extraction-1', commandId: 'Command_AbC-123', expectedRevision: 7, policyVersion, ...extra});
const applied = {outcome: 'applied', resolutionId: 'extraction-1', revision: 8, resultingDraftId: 'draft-1', finalizationId: 'Command_AbC-123'};
const secret = 'PRIVATE SUPPLIER INR 500 gs://bucket/trips/private/source.pdf';
const code = (expected) => (error) => error instanceof HttpsError && error.code === expected;
function fixture(result = applied) {
  const x = {result, calls: [], logs: [], initialized: 0};
  x.run = (data = request(), actor = auth) => handle({auth: actor, data}, () => {
    x.initialized++; return {finalize: async (who, input) => {
      x.calls.push({who, input}); if (x.error) throw x.error; return x.result;
    }};
  }, (event, fields) => x.logs.push({event, ...fields}));
  return x;
}

test('real Gen2 finalizeSupplierImport export uses asia-south2 and the existing Node 22 runtime', () => {
  const exports = require('../lib/index');
  assert.equal(typeof exports.finalizeSupplierImport.run, 'function');
  assert.equal(exports.finalizeSupplierImport.__endpoint.platform, 'gcfv2');
  assert.deepEqual(exports.finalizeSupplierImport.__endpoint.region, ['asia-south2']);
  assert.deepEqual(exports.finalizeSupplierImport.__endpoint.callableTrigger, {});
  assert.equal(require('../package.json').engines.node, '22');
});
test('real exported callable delegates exactly once to the existing Admin engine without production calls', async (t) => {
  const admin = require('../lib/itineraryExtraction/supplierImportFinalizationAdmin');
  const calls = [];
  t.mock.method(admin, 'finalizeSupplierImportAdmin', async (db, actor, input) => {
    assert(db); calls.push({actor, input}); return applied;
  });
  t.mock.method(require('firebase-functions').logger, 'info', () => {});
  const response = await require('../lib/index').finalizeSupplierImport.run({auth, data: request()});
  assert.deepEqual(calls, [{actor: {uid: auth.uid, email: auth.token.email}, input: request()}]);
  assert.deepEqual(response, {outcome: 'applied', resolutionId: 'extraction-1', revision: 8, resultingDraftId: 'draft-1'});
});
for (const actor of [null, {uid: '', token: {}}, {uid: '../bad', token: {}}, {uid: 'x'.repeat(129), token: {}}]) {
  test(`invalid/missing authentication ${JSON.stringify(actor)} rejects before dependency initialization`, async () => {
    const x = fixture(); await assert.rejects(x.run(request(), actor), code('unauthenticated'));
    assert.equal(x.initialized, 0); assert.equal(x.calls.length, 0);
  });
}
test('absent auth is unauthenticated even with a malformed body', async () => {
  await assert.rejects(handle({data: null}, () => assert.fail('must not initialize'), () => {}), code('unauthenticated'));
});
for (const field of Object.keys(request())) test(`request requires ${field}`, async () => {
  const input = request(); delete input[field]; const x = fixture();
  await assert.rejects(x.run(input), code('invalid-argument')); assert.equal(x.initialized, 0);
});
for (const field of ['extra', 'actorUid', 'uid', 'email', 'role', 'candidate', 'Snapshot', 'snapshot', 'Resolution', 'resolution',
  'receipt', 'timestamp', 'finalizedAt', 'sourcePackageId', 'draftId', 'resultingDraftId', 'finalizationId']) {
  test(`closed request rejects ${field}`, async () => {
    const x = fixture(); await assert.rejects(x.run(request({[field]: secret})), code('invalid-argument'));
    assert.equal(x.calls.length, 0); assert(!JSON.stringify(x.logs).includes(secret));
  });
}
for (const field of ['tripId', 'extractionId', 'commandId']) {
  for (const value of ['', ' padded', 'padded ', 'a/b', 'a\\b', '..', '.', 'bad\nvalue', 1, null, 'x'.repeat(field === 'commandId' ? 129 : 257)]) {
    test(`${field} rejects unsafe identity ${JSON.stringify(value)}`, () => assert.throws(() => parse(request({[field]: value})), code('invalid-argument')));
  }
}
for (const value of ['7', 1.5, -1, 0, NaN, Infinity, Number.MAX_SAFE_INTEGER, Number.MAX_SAFE_INTEGER + 1]) {
  test(`expectedRevision rejects ${String(value)}`, () => assert.throws(() => parse(request({expectedRevision: value})), code('invalid-argument')));
}
for (const value of ['', null, 'future', policyVersion + ' ']) test(`policy rejects ${String(value)}`, () => {
  assert.throws(() => parse(request({policyVersion: value})), code('invalid-argument'));
});
for (const value of [null, [], 'request', Object.assign(new Date(), request())]) test('non-map request fails closed', () => {
  assert.throws(() => parse(value), code('invalid-argument'));
});
test('symbol fields and accessors cannot bypass the exact request boundary', () => {
  assert.throws(() => parse({...request(), [Symbol('secret')]: true}), code('invalid-argument'));
  const input = request(); Object.defineProperty(input, 'tripId', {get() {assert.fail('must not execute');}});
  assert.throws(() => parse(input), code('invalid-argument'));
});
test('authoritative policy and exact case-sensitive command/revision are forwarded unchanged once', async () => {
  const x = fixture(), input = request({expectedRevision: Number.MAX_SAFE_INTEGER - 1, commandId: 'A'.repeat(128), tripId: 't'.repeat(256)});
  await x.run(input); assert.equal(x.calls.length, 1); assert.deepEqual(x.calls[0].input, input);
  assert.deepEqual(x.calls[0].who, {uid: auth.uid, email: auth.token.email});
  assert.notEqual(x.calls[0].input, input); assert(Object.isFrozen(x.calls[0].input));
});
test('missing token email is passed safely to authoritative Admin authorization without trusting token role', async () => {
  const x = fixture(); x.error = new SupplierImportFinalizationError('UNAUTHORIZED_OR_FORBIDDEN');
  await assert.rejects(x.run(request(), {uid: auth.uid, token: {role: 'admin'}}), code('permission-denied'));
  assert.deepEqual(x.calls[0].who, {uid: auth.uid, email: ''});
});
for (const outcome of ['applied', 'already_applied']) test(`${outcome} returns only the closed successful DTO`, async () => {
  const x = fixture({...applied, outcome, receipt: secret, snapshot: secret, resolution: secret, candidate: secret});
  assert.deepEqual(await x.run(), {outcome, resolutionId: 'extraction-1', revision: 8, resultingDraftId: 'draft-1'});
  assert.equal(x.calls.length, 1); assert(!JSON.stringify(x.logs).includes(secret));
});
test('not_ready projects deterministic blocker/warning codes and targets without private content', async () => {
  const blocker = {code: 'unresolved_unassigned_service', targetKind: 'service', targetId: 'staged-service-1'};
  const warning = {code: 'snapshot_warning_open', targetKind: 'review_issue', targetId: 'review-1'};
  const x = fixture({outcome: 'not_ready', receipt: secret, assessment: {resolutionId: 'extraction-1', evaluatedRevision: 7,
    canFinalize: false, blockers: [{...blocker, message: secret, snapshot: secret}], warnings: [{...warning, message: secret}],
    informational: [], candidate: secret, accounting: secret, sourceText: secret}});
  assert.deepEqual(await x.run(), {outcome: 'not_ready', assessment: {resolutionId: 'extraction-1', evaluatedRevision: 7,
    canFinalize: false, blockers: [blocker], warnings: [warning]}});
  assert.equal(x.calls.length, 1); assert(!JSON.stringify(x.logs).includes(secret));
});
for (const result of [
  {outcome: 'resolution_conflict', resolutionId: 'extraction-1', currentRevision: 9},
  {outcome: 'resolution_not_started', resolutionId: 'extraction-1', revision: 0},
  {outcome: 'resolution_finalized', resolutionId: 'extraction-1', revision: 8},
  {outcome: 'persistence_capacity_exceeded', resolutionId: 'extraction-1', boundary: 'receipt'},
]) test(`${result.outcome} is normal and never automatically retried`, async () => {
  const x = fixture({...result, private: secret}); assert.deepEqual(await x.run(), result); assert.equal(x.calls.length, 1);
});
for (const outcome of ['trusted_state_invalid', 'snapshot_unavailable']) test(`${outcome} becomes sanitized failed-precondition`, async () => {
  const x = fixture({outcome, resolutionId: 'extraction-1', message: secret});
  await assert.rejects(x.run(), (error) => code('failed-precondition')(error) && !error.message.includes(secret) && !error.details);
  assert.equal(x.calls.length, 1); assert(!JSON.stringify(x.logs).includes(secret));
});
for (const [engineCode, httpsCode] of [['UNAUTHORIZED_OR_FORBIDDEN', 'permission-denied'],
  ['INVALID_FINALIZATION_REQUEST', 'invalid-argument'], ['FINALIZATION_PERSISTENCE_FAILED', 'internal']]) {
  test(`${engineCode} maps to ${httpsCode} without raw exception fields`, async () => {
    const x = fixture(); x.error = new SupplierImportFinalizationError(engineCode); x.error.message = secret; x.error.details = {secret};
    await assert.rejects(x.run(), (error) => code(httpsCode)(error) && !error.message.includes(secret) && !error.details);
    assert.equal(x.calls.length, 1); assert(!JSON.stringify(x.logs).includes(secret));
  });
}
for (const error of [Object.assign(new Error(secret), {code: 14}), new HttpsError('permission-denied', secret, {secret})]) {
  test('unexpected SDK and Https exceptions from Admin become generic internal errors', async () => {
    const x = fixture(); x.error = error;
    await assert.rejects(x.run(), (e) => code('internal')(e) && !e.message.includes(secret) && !e.details);
    assert.equal(x.calls.length, 1); assert(!JSON.stringify(x.logs).includes(secret));
  });
}
test('unknown engine outcome fails closed', async () => {
  const x = fixture({outcome: 'future', receipt: secret}); await assert.rejects(x.run(), code('internal'));
});
test('logs contain only function name and safe outcome/error code, never auth or request bodies', async () => {
  const x = fixture(); await x.run(); await assert.rejects(x.run({...request(), receipt: secret}));
  assert.deepEqual(x.logs, [
    {event: 'supplier-import-finalization-callable-completed', functionName: 'finalizeSupplierImport', outcome: 'applied'},
    {event: 'supplier-import-finalization-callable-rejected', functionName: 'finalizeSupplierImport', code: 'invalid-argument'},
  ]);
});
test('callable owns no persistence, assembly, receipt creation or identity generation', () => {
  const source = fs.readFileSync(path.join(__dirname, '../src/itineraryExtraction/supplierImportFinalizationCallable.ts'), 'utf8');
  assert.doesNotMatch(source, /firebase-admin\/|runTransaction|\.doc\(|\.collection\(|assembleSupplierImportV2|createSupplierImportFinalizationReceipt|randomUUID|createHash/);
  assert.equal(require('../lib/itineraryExtraction/requestAdmin').currentProductionExtractionContractVersion, 'itinerary_draft_v1');
});
