const {test} = require('node:test');
const assert = require('node:assert/strict');
const {HttpsError} = require('firebase-functions/v2/https');
const {
  SupplierImportResolutionMutationError,
} = require('../lib/itineraryExtraction/supplierImportResolutionMutation');
const {
  handleSupplierImportResolutionMutation,
  parseSupplierImportResolutionMutationRequest,
} = require('../lib/itineraryExtraction/supplierImportResolutionMutationCallable');

const auth = {uid: 'agent-1', token: {email: 'agent@kholidaymaps.com'}};
const base = {tripId: 'trip-1', extractionId: 'extraction-1',
  expectedRevision: 0, commandId: 'command-1'};
const serviceDecision = {decisionKind: 'service',
  targetEntityId: 'staged-service-1', disposition: 'retain',
  day: {kind: 'staged_day', dayId: 'staged-day-1'}, canonicalOrder: 1,
  overrides: {}, exclusionReason: null, exclusionNote: null};
const manualDay = {itemKind: 'consultant_day',
  manualDayId: 'consultant-day-1', canonicalOrder: 1, date: null,
  title: 'Consultant day', summary: null, notes: null};
const code = (expected) => (error) =>
  error instanceof HttpsError && error.code === expected;

function input(mutation, overrides = {}) {
  return {...base, mutation, ...overrides};
}

function fixture(result = {outcome: 'applied', resolutionId: 'extraction-1',
  revision: 1, status: 'active', canFinalize: false, blockerCount: 2,
  warningCount: 1}) {
  const calls = [];
  const logs = [];
  const state = {calls, logs, result, error: null};
  state.dependencies = {mutate: async (actor, request) => {
    calls.push({actor, request});
    if (state.error) throw state.error;
    return state.result;
  }};
  state.run = (data, requestAuth = auth) =>
    handleSupplierImportResolutionMutation(
      {auth: requestAuth, data}, state.dependencies,
      (event, fields) => logs.push({event, ...fields}),
    );
  return state;
}

test('A unauthenticated request fails before dependency initialization', async () => {
  let initialized = false;
  await assert.rejects(
    handleSupplierImportResolutionMutation(
      {data: input({action: 'start_review'})},
      () => {initialized = true; return {mutate: async () => assert.fail()};},
      () => {},
    ),
    code('unauthenticated'),
  );
  assert.equal(initialized, false);
});

test('B-H every supported command passes one strictly parsed request and auth actor',
  async () => {
    const commands = [
      {action: 'start_review'},
      {action: 'set_decision', decision: serviceDecision},
      {action: 'remove_decision', decisionId: 'staged-service-1'},
      {action: 'upsert_manual_item', item: manualDay},
      {action: 'remove_manual_item', manualItemId: 'consultant-day-1'},
    ];
    for (const mutation of commands) {
      const f = fixture();
      const request = input(mutation);
      await f.run(request);
      assert.equal(f.calls.length, 1);
      assert.deepEqual(f.calls[0].actor, {
        uid: auth.uid,
        email: auth.token.email,
      });
      assert.deepEqual(f.calls[0].request, request);
      assert.notEqual(f.calls[0].request, request);
    }
  });

test('G/H request identity cannot replace trusted UID or email', async () => {
  for (const field of ['actorUid', 'email', 'createdByUid', 'updatedByUid']) {
    const f = fixture();
    await assert.rejects(
      f.run({...input({action: 'start_review'}), [field]: 'attacker'}),
      code('invalid-argument'),
    );
    assert.equal(f.calls.length, 0);
  }
});

test('I-N malformed identifiers and revisions are rejected before Admin', async () => {
  const cases = [
    {tripId: undefined}, {extractionId: undefined},
    {expectedRevision: '0'}, {expectedRevision: -1},
    {commandId: undefined}, {commandId: 'bad/id'},
    {commandId: 'x'.repeat(129)},
  ];
  for (const override of cases) {
    const f = fixture();
    await assert.rejects(
      f.run(input({action: 'start_review'}, override)),
      code('invalid-argument'),
    );
    assert.equal(f.calls.length, 0);
  }
});

test('O-T unsupported, unknown, and server-owned transport fields are rejected',
  async () => {
    const cases = [
      input({action: 'finalize'}),
      input({action: 'start_review', extra: true}),
      {...input({action: 'start_review'}), unexpected: true},
      {...input({action: 'start_review'}), role: 'admin'},
      {...input({action: 'start_review'}), sourcePackageId: 'package-1'},
      {...input({action: 'start_review'}), audit: {}},
      {...input({action: 'start_review'}), updatedAt: '2026-10-01'},
      {...input({action: 'start_review'}), canFinalize: true},
    ];
    for (const value of cases) {
      const f = fixture();
      await assert.rejects(f.run(value), code('invalid-argument'));
      assert.equal(f.calls.length, 0);
    }
  });

test('set/manual payloads must be transport objects and are copied', () => {
  for (const mutation of [
    {action: 'set_decision', decision: null},
    {action: 'upsert_manual_item', item: []},
  ]) {
    assert.throws(() => parseSupplierImportResolutionMutationRequest(
      input(mutation)), code('invalid-argument'));
  }
  const original = input({action: 'set_decision', decision: serviceDecision});
  const parsed = parseSupplierImportResolutionMutationRequest(original);
  assert.deepEqual(parsed, original);
  assert.notEqual(parsed.mutation.decision, original.mutation.decision);
});

test('U-Y workflow outcomes are returned as small deterministic DTOs', async () => {
  const results = [
    {outcome: 'applied', resolutionId: 'extraction-1', revision: 2,
      status: 'active', canFinalize: true, blockerCount: 0, warningCount: 1},
    {outcome: 'already_applied', resolutionId: 'extraction-1', revision: 2},
    {outcome: 'resolution_conflict', resolutionId: 'extraction-1',
      currentRevision: 3},
    {outcome: 'resolution_not_started', resolutionId: 'extraction-1', revision: 0},
    {outcome: 'resolution_finalized', resolutionId: 'extraction-1', revision: 7},
  ];
  for (const result of results) {
    const f = fixture(result);
    assert.deepEqual(await f.run(input({action: 'start_review'})), result);
  }
});

test('Z-AD trusted failures map to sanitized callable errors', async () => {
  const cases = [
    ['UNAUTHORIZED_OR_FORBIDDEN', 'permission-denied'],
    ['INVALID_MUTATION', 'invalid-argument'],
    ['SNAPSHOT_UNAVAILABLE', 'failed-precondition'],
    ['MALFORMED_STORED_RESOLUTION', 'failed-precondition'],
    ['MUTATION_PERSISTENCE_FAILED', 'internal'],
  ];
  for (const [mutationCode, httpsCode] of cases) {
    const f = fixture();
    f.error = new SupplierImportResolutionMutationError(
      mutationCode, 'PRIVATE SUPPLIER CONTENT',
    );
    await assert.rejects(
      f.run(input({action: 'start_review'})),
      (error) => code(httpsCode)(error) &&
        !error.message.includes('PRIVATE'),
    );
    assert.equal(f.calls.length, 1);
  }
});

test('AG unexpected Admin errors become sanitized internal failures', async () => {
  const f = fixture();
  f.error = new Error('RAW INTERNAL SECRET');
  await assert.rejects(
    f.run(input({action: 'start_review'})),
    (error) => code('internal')(error) &&
      !error.message.includes('RAW INTERNAL SECRET'),
  );
  assert.equal(JSON.stringify(f.logs).includes('RAW INTERNAL SECRET'), false);
});

test('AE/AF logs contain only operational metadata', async () => {
  const secret = 'DO NOT LOG THIS SUPPLIER DESCRIPTION';
  const f = fixture();
  await f.run(input({action: 'set_decision', decision: {
    ...serviceDecision,
    overrides: {description: {operation: 'set', value: secret}},
  }}));
  const logged = JSON.stringify(f.logs);
  assert.equal(logged.includes(secret), false);
  assert.equal(logged.includes('decisionKind'), false);
  assert.equal(logged.includes('overrides'), false);
  assert.equal(logged.includes('supplier-import-resolution-callable-completed'), true);
});

test('AH/AI commandId is preserved and no automatic retry occurs', async () => {
  const f = fixture();
  await f.run(input({action: 'start_review'}));
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].request.commandId, base.commandId);
});

test('AJ/AK callable cannot finalize and imports no finalizer or draft writer', () => {
  assert.throws(
    () => parseSupplierImportResolutionMutationRequest(input({action: 'finalize'})),
    code('invalid-argument'),
  );
  const fs = require('node:fs');
  const path = require('node:path');
  const source = fs.readFileSync(path.resolve(__dirname,
    '../src/itineraryExtraction/supplierImportResolutionMutationCallable.ts'),
  'utf8');
  assert.doesNotMatch(source, /finalizeSupplierImport|draftWriter|resultingDraftId/);
});

test('real entrypoint exports exactly the expected Functions', () => {
  const functions = require('../lib/index');
  assert.deepEqual(Object.keys(functions).sort(), [
    'applySupplierImportResolutionMutation',
    'cleanupSupplierSourceUpload',
    'processItineraryExtractionJob',
    'requestItineraryExtraction',
  ]);
  assert.equal(Object.keys(functions)
    .filter((name) => name === 'applySupplierImportResolutionMutation').length, 1);
});

test('AL/AM Rules stay external and production requests remain V2.4-only', () => {
  const {
    currentProductionExtractionContractVersion,
  } = require('../lib/itineraryExtraction/requestAdmin');
  assert.equal(currentProductionExtractionContractVersion,
    'itinerary_draft_v1');
  const fs = require('node:fs');
  const path = require('node:path');
  const callableSource = fs.readFileSync(path.resolve(__dirname,
    '../src/itineraryExtraction/supplierImportResolutionMutationCallable.ts'),
  'utf8');
  assert.doesNotMatch(callableSource, /firestore\.rules|supplier_extraction_v1/);
});
