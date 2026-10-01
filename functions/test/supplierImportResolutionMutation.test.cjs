const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  SupplierImportResolutionMutationError,
  mutateSupplierImportResolution,
} = require('../lib/itineraryExtraction/supplierImportResolutionMutation');
const {
  requireSupplierImportResolutionAuthorization,
} = require('../lib/itineraryExtraction/supplierImportResolutionMutationAdmin');
const {normalizeSupplierExtractionSnapshot} =
  require('../lib/itineraryExtraction/supplierExtractionValidation');

const at = '2026-10-01T06:00:00.000Z';
const actor = {uid: 'agent-1'};

function snapshot() {
  return normalizeSupplierExtractionSnapshot({
    title: {text: 'Trip', basis: 'neutral_supported'},
    days: [{title: 'Day one', services: [{type: 'other', title: 'Assigned'}]}],
    unassignedServices: [{title: 'Unassigned'}],
    packageFacts: {
      accommodations: [{hotelName: 'Hotel'}],
      inclusions: [{category: 'meal', text: 'Breakfast'}],
      conditions: [{kind: 'guide', value: 'Guide included'}],
    },
    ancillaryFacts: {
      flights: [{origin: 'DEL', destination: 'DXB'}],
      visas: [{disposition: 'mentioned', text: 'Visa required'}],
    },
    reviewIssues: [{code: 'other', severity: 'warning', message: 'Review wording',
      target: {kind: 'snapshot'}, resolutionRequired: false}],
  }, {
    extractionId: 'extraction-1', tripId: 'trip-1',
    sourcePackageId: 'package-1', jobId: 'job-1', requestedByUid: 'agent-1',
    createdAt: new Date(at), providerVersion: 'v3', trustedPackage: {
      tripId: 'trip-1', packageId: 'package-1', supplierId: null,
      supplierNameSnapshot: null, files: [{sourceFileId: 'file-1',
        packageId: 'package-1', originalFileName: 'source.pdf',
        storagePath: 'trips/trip-1/supplier_sources/file-1/source.pdf',
        contentType: 'application/pdf', sizeBytes: 100, uploadedByUid: 'agent-1'}],
    },
  });
}

class MemoryStore {
  constructor() {
    this.aggregate = null;
    this.commits = [];
    this.order = [];
    this.failCommit = false;
  }
  async runTransaction(operation) {
    let pending = null;
    const transaction = {
      readState: async (commandId) => {
        this.order.push('read');
        return {aggregate: this.aggregate,
          existingCommandEvent: this.aggregate?.auditEvents.find(
            (event) => event.eventId === commandId,
          ) ?? null};
      },
      commit: (plan) => {
        this.order.push('write');
        if (this.failCommit) throw new Error('synthetic commit failure');
        pending = plan;
      },
    };
    const result = await operation(transaction);
    if (pending) {
      const current = this.aggregate ?? {decisions: [], manualItems: [], auditEvents: []};
      let decisions = current.decisions.filter((item) =>
        item.decisionId !== pending.decision?.decisionId);
      if (pending.decision?.value) decisions.push(pending.decision.value);
      let manualItems = current.manualItems.filter((item) =>
        manualId(item) !== pending.manualItem?.manualItemId);
      if (pending.manualItem?.value) manualItems.push(pending.manualItem.value);
      this.aggregate = {root: pending.root, decisions, manualItems,
        auditEvents: [...current.auditEvents, pending.event]};
      this.commits.push(pending);
    }
    return result;
  }
}

function manualId(item) {
  return item.itemKind === 'consultant_day' ? item.manualDayId : item.manualServiceId;
}

function request(action, expectedRevision, commandId, payload = {}) {
  return {tripId: 'trip-1', extractionId: 'extraction-1', expectedRevision,
    commandId, mutation: {action, ...payload}};
}

async function start(store, source = snapshot()) {
  return mutateSupplierImportResolution(source,
    request('start_review', 0, 'command-start'), actor, at, store);
}

function setDecision(decision, revision, commandId) {
  return request('set_decision', revision, commandId, {decision});
}

function serviceDecision(overrides = {}) {
  return {decisionKind: 'service', targetEntityId: 'staged-service-2',
    disposition: 'retain', day: {kind: 'staged_day', dayId: 'staged-day-1'},
    canonicalOrder: 2, overrides: {
      serviceType: {operation: 'set', value: 'other'},
      title: {operation: 'set', value: 'Unassigned'},
    }, exclusionReason: null, exclusionNote: null, ...overrides};
}

const invalid = (error) => error instanceof SupplierImportResolutionMutationError &&
  error.code === 'INVALID_MUTATION';

test('A start review creates linked active root and exactly one 0→1 event', async () => {
  const source = snapshot(); const store = new MemoryStore();
  const result = await start(store, source);
  assert.equal(result.outcome, 'applied');
  assert.equal(store.aggregate.root.revision, 1);
  assert.equal(store.aggregate.root.sourcePackageId, source.sourcePackageId);
  assert.equal(store.aggregate.root.createdByUid, actor.uid);
  assert.equal(store.aggregate.auditEvents.length, 1);
  assert.deepEqual([store.aggregate.auditEvents[0].previousRevision,
    store.aggregate.auditEvents[0].resultingRevision], [0, 1]);
  assert.equal(store.aggregate.auditEvents[0].eventId, 'command-start');
});

test('B/C only start_review with expected revision zero may initialize', async () => {
  const source = snapshot();
  const conflict = await mutateSupplierImportResolution(source,
    request('start_review', 1, 'bad-start'), actor, at, new MemoryStore());
  assert.equal(conflict.outcome, 'resolution_conflict');
  const missing = await mutateSupplierImportResolution(source,
    setDecision(serviceDecision(), 0, 'set'), actor, at, new MemoryStore());
  assert.equal(missing.outcome, 'resolution_not_started');
});

test('D/J/K replay wins before stale validation and never mutates twice', async () => {
  const source = snapshot(); const store = new MemoryStore();
  await start(store, source);
  const retry = await mutateSupplierImportResolution(source,
    request('start_review', 99, 'command-start'), actor, at, store);
  assert.equal(retry.outcome, 'already_applied');
  assert.equal(retry.revision, 1);
  assert.equal(store.commits.length, 1);
});

test('E/F/G/H valid decision atomically advances root and audit once', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  const result = await mutateSupplierImportResolution(source,
    setDecision(serviceDecision(), 1, 'set-service'), actor, at, store);
  assert.equal(result.revision, 2);
  assert.equal(store.aggregate.root.revision, 2);
  assert.equal(store.aggregate.decisions.length, 1);
  assert.equal(store.aggregate.auditEvents.length, 2);
  assert.deepEqual(store.order, ['read', 'write', 'read', 'write']);
});

test('I stale new command conflicts without writes', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  const result = await mutateSupplierImportResolution(source,
    setDecision(serviceDecision(), 0, 'stale'), actor, at, store);
  assert.equal(result.outcome, 'resolution_conflict');
  assert.equal(store.commits.length, 1);
});

test('L/M replay precedes finalized lock while new command is rejected', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  store.aggregate = {...store.aggregate, root: {...store.aggregate.root,
    status: 'finalized', revision: 2, finalizedByUid: 'agent-1', finalizedAt: at,
    resultingDraftId: 'draft-1'}, auditEvents: [...store.aggregate.auditEvents,
    {...store.aggregate.auditEvents[0], eventId: 'finalize', commandId: 'finalize',
      previousRevision: 1, resultingRevision: 2, action: 'finalize',
      targetKind: 'finalization', metadata: {kind: 'lifecycle', status: 'finalized'}}]};
  assert.equal((await mutateSupplierImportResolution(source,
    request('start_review', 0, 'command-start'), actor, at, store)).outcome,
  'already_applied');
  assert.equal((await mutateSupplierImportResolution(source,
    setDecision(serviceDecision(), 2, 'new'), actor, at, store)).outcome,
  'resolution_finalized');
});

test('N-R day/service assignment, exclusion, and sparse overrides validate', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  const decisions = [
    {decisionKind: 'day', targetEntityId: 'staged-day-1', disposition: 'retain',
      overrides: {summary: {operation: 'clear'}}, exclusionReason: null,
      exclusionNote: null},
    serviceDecision(),
    serviceDecision({disposition: 'exclude', day: undefined,
      canonicalOrder: undefined, overrides: {}, exclusionReason: 'duplicate'}),
  ];
  for (let index = 0; index < decisions.length; index++) {
    const result = await mutateSupplierImportResolution(source,
      setDecision(decisions[index], store.aggregate.root.revision, `decision-${index}`),
      actor, at, store);
    assert.equal(result.outcome, 'applied');
  }
});

test('S/T invalid day reference and incompatible details write nothing', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  for (const decision of [
    serviceDecision({day: {kind: 'staged_day', dayId: 'missing'}}),
    serviceDecision({overrides: {hotel: {hotelName: {
      operation: 'set', value: 'Hotel',
    }}}}),
  ]) {
    await assert.rejects(() => mutateSupplierImportResolution(source,
      setDecision(decision, 1, `bad-${store.commits.length}`), actor, at, store),
    invalid);
  }
  assert.equal(store.commits.length, 1);
});

test('U-Z package, ancillary, visa, and warning decisions apply', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  const decisions = [
    {decisionKind: 'package_accommodation', targetEntityId: 'package-fact-1',
      disposition: 'map_to_day_service', day: {kind: 'staged_day', dayId: 'staged-day-1'},
      canonicalOrder: 3, overrides: {}, exclusionReason: null, exclusionNote: null},
    {decisionKind: 'package_statement', targetEntityId: 'package-fact-2',
      disposition: 'map_to_service',
      service: {kind: 'staged_service', serviceId: 'staged-service-1'},
      destination: 'service_inclusion', overrides: {}, exclusionReason: null,
      exclusionNote: null},
    {decisionKind: 'package_condition', targetEntityId: 'package-fact-3',
      disposition: 'map_to_service',
      service: {kind: 'staged_service', serviceId: 'staged-service-1'},
      destination: 'service_notes', overrides: {}, exclusionReason: null,
      exclusionNote: null},
    {decisionKind: 'flight', targetEntityId: 'ancillary-flight-1',
      disposition: 'handled_separately', destinationId: null, overrides: {},
      exclusionReason: null, exclusionNote: null},
    {decisionKind: 'visa', targetEntityId: 'ancillary-visa-1',
      disposition: 'handled_separately', destinationId: null,
      overrides: {text: {operation: 'clear'}}, exclusionReason: null,
      exclusionNote: null},
    {decisionKind: 'review_issue', targetEntityId: 'review-1',
      outcome: 'acknowledged', resolutionReferences: [], overrideReason: null,
      overrideNote: null},
  ];
  for (const [index, decision] of decisions.entries()) {
    const result = await mutateSupplierImportResolution(source,
      setDecision(decision, store.aggregate.root.revision, `typed-${index}`),
      actor, at, store);
    assert.equal(result.outcome, 'applied');
  }
});

test('AA illegal blocker acknowledgement and invalid package variant reject', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  await assert.rejects(() => mutateSupplierImportResolution(source,
    setDecision({decisionKind: 'flight', targetEntityId: 'package-fact-2',
      disposition: 'handled_separately', destinationId: null, overrides: {},
      exclusionReason: null, exclusionNote: null}, 1, 'bad-kind'), actor, at, store),
  invalid);
});

test('AB/AC remove decision preserves audit and may reduce readiness', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  await mutateSupplierImportResolution(source,
    setDecision(serviceDecision(), 1, 'set'), actor, at, store);
  const result = await mutateSupplierImportResolution(source,
    request('remove_decision', 2, 'remove', {decisionId: 'staged-service-2'}),
    actor, at, store);
  assert.equal(result.outcome, 'applied');
  assert.equal(result.canFinalize, false);
  assert.equal(store.aggregate.decisions.length, 0);
  assert.equal(store.aggregate.auditEvents.length, 3);
});

function dayItem() {
  return {itemKind: 'consultant_day', manualDayId: 'consultant-day-1',
    canonicalOrder: 2, date: null, title: 'Manual day', summary: null, notes: null};
}
function serviceItem() {
  return {itemKind: 'consultant_service', manualServiceId: 'consultant-service-1',
    day: {kind: 'consultant_day', manualDayId: 'consultant-day-1'}, canonicalOrder: 1,
    serviceType: 'other', title: 'Manual service', description: null,
    startTime: null, endTime: null, location: null, city: null, inclusions: [],
    exclusions: [], notes: null, hotelDetails: null, transferDetails: null,
    activityDetails: null};
}

test('AD-AH manual create/update/remove enforces references and trusted metadata', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  await mutateSupplierImportResolution(source, request('upsert_manual_item', 1,
    'day', {item: dayItem()}), actor, at, store);
  await mutateSupplierImportResolution(source, request('upsert_manual_item', 2,
    'service', {item: serviceItem()}), actor, at, store);
  assert(store.aggregate.manualItems.every((item) =>
    item.createdByUid === actor.uid && item.updatedByUid === actor.uid));
  await assert.rejects(() => mutateSupplierImportResolution(source,
    request('remove_manual_item', 3, 'remove-day',
      {manualItemId: 'consultant-day-1'}), actor, at, store), invalid);
  const result = await mutateSupplierImportResolution(source,
    request('remove_manual_item', 3, 'remove-service',
      {manualItemId: 'consultant-service-1'}), actor, at, store);
  assert.equal(result.outcome, 'applied');
});

test('AF/AK/AL trusted fields and Supplier provenance are rejected', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  for (const item of [
    {...dayItem(), sources: []},
    {...dayItem(), createdByUid: 'attacker'},
  ]) {
    await assert.rejects(() => mutateSupplierImportResolution(source,
      request('upsert_manual_item', 1, `bad-${Object.keys(item).length}`, {item}),
      actor, at, store), invalid);
  }
});

test('AM-AQ reads precede writes and transaction failures preserve all state', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  const before = JSON.stringify(store.aggregate);
  store.failCommit = true;
  await assert.rejects(() => mutateSupplierImportResolution(source,
    setDecision(serviceDecision(), 1, 'fails'), actor, at, store),
  (error) => error.code === 'MUTATION_PERSISTENCE_FAILED');
  assert.equal(JSON.stringify(store.aggregate), before);
  assert.deepEqual(store.order.slice(-2), ['read', 'write']);
});

test('AS-AV event/root fields are server owned and commercial state cannot enter', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  await mutateSupplierImportResolution(source,
    setDecision(serviceDecision(), 1, 'server-owned'), actor, at, store);
  const event = store.aggregate.auditEvents.at(-1);
  assert.equal(event.resultingRevision, event.previousRevision + 1);
  assert.equal(event.commandId, event.eventId);
  assert.equal(Object.hasOwn(store.aggregate.root, 'canFinalize'), false);
  await assert.rejects(() => mutateSupplierImportResolution(source,
    setDecision({...serviceDecision(), price: 370}, 2, 'commercial'), actor, at, store),
  invalid);
});

test('AX/AY separate commands increment once and same-revision loser conflicts', async () => {
  const source = snapshot(); const store = new MemoryStore(); await start(store, source);
  assert.equal((await mutateSupplierImportResolution(source,
    setDecision(serviceDecision(), 1, 'first'), actor, at, store)).revision, 2);
  const loser = await mutateSupplierImportResolution(source,
    setDecision(serviceDecision({overrides: {serviceType: {operation: 'set', value: 'meal'},
      title: {operation: 'set', value: 'Meal'}}}), 1, 'second'), actor, at, store);
  assert.equal(loser.outcome, 'resolution_conflict');
});

test('Admin authorization accepts owner/Admin and rejects other/inactive/domain', () => {
  const trip = {ownerUid: 'agent-1'};
  assert.doesNotThrow(() => requireSupplierImportResolutionAuthorization(
    {uid: 'agent-1', email: 'agent@kholidaymaps.com'},
    {role: 'agent', status: 'active'}, trip));
  assert.doesNotThrow(() => requireSupplierImportResolutionAuthorization(
    {uid: 'admin-1', email: 'admin@kholidaymaps.com'},
    {role: 'admin', status: 'active'}, trip));
  for (const [actorValue, profile] of [
    [{uid: 'agent-2', email: 'other@kholidaymaps.com'},
      {role: 'agent', status: 'active'}],
    [{uid: 'agent-1', email: 'agent@other.com'},
      {role: 'agent', status: 'active'}],
    [{uid: 'agent-1', email: 'agent@kholidaymaps.com'},
      {role: 'agent', status: 'inactive'}],
  ]) {
    assert.throws(() => requireSupplierImportResolutionAuthorization(
      actorValue, profile, trip), (error) => error.code === 'UNAUTHORIZED_OR_FORBIDDEN');
  }
});

test('AW logger surface contains no semantic command payload', () => {
  const source = require('node:fs').readFileSync(
    require('node:path').resolve(__dirname,
      '../src/itineraryExtraction/supplierImportResolutionMutationAdmin.ts'), 'utf8');
  assert.doesNotMatch(source, /log\([^)]*(?:decision|overrides|hotelName|description)/su);
});

test('BA/BB mutation modules import no draft writer and export no callable', () => {
  const fs = require('node:fs'); const path = require('node:path');
  for (const file of ['supplierImportResolutionMutation.ts',
    'supplierImportResolutionMutationAdmin.ts']) {
    const source = fs.readFileSync(path.resolve(__dirname,
      `../src/itineraryExtraction/${file}`), 'utf8');
    assert.doesNotMatch(source, /draftWriter|onCall|firebase-functions\/v2\/https/u);
  }
});
