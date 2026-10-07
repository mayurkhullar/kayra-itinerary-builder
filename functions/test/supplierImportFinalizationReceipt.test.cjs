const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const {assembleSupplierImportV2} = require('../lib/itineraryExtraction/supplierImportV2Assembly');
const {itineraryDraftV2ToMap, validateItineraryDraftV2, serializeItineraryDraftV2} = require('../lib/itineraryExtraction/itineraryDraftV2Validation');
const {createSupplierImportFinalizationReceipt: create, assertSupplierImportReceiptMatchesCandidate: bind} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptFactory');
const {supplierImportFinalizationReceiptFromMap: fromMap, supplierImportFinalizationReceiptToMap: toMap,
  serializeSupplierImportFinalizationReceipt: serialize} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptValidation');
const {supplierImportCanonicalContentDigest: digest} = require('../lib/itineraryExtraction/supplierImportFinalizationReceiptDigest');
const {SupplierImportFinalizationReceiptError} = require('../lib/itineraryExtraction/supplierImportFinalizationReceipt');
const clone = (value) => JSON.parse(JSON.stringify(value));
const ctx = (changes = {}) => ({tripId: 'trip-1', extractionId: 'extraction-1', commandId: 'finalization-1',
  expectedRevision: 1, policyVersion: f.context().policyVersion, actorUid: 'agent-1', finalizedAt: new Date(f.at), ...changes});
const assemble = (source = f.snapshot({days: [f.day()]}), changes = {}, context = f.context()) =>
  assembleSupplierImportV2(source, f.aggregate(source, changes), context);
const ready = (value) => {assert.equal(value.canFinalize, true, JSON.stringify(value.blockers)); return value;};
const receipt = () => create(ready(assemble()), ctx());
const map = () => clone(toMap(receipt()));
const row = (value, id) => value.outcomes.find((item) => item.targetId === id);
const rejects = (fn) => assert.throws(fn, (error) => error instanceof SupplierImportFinalizationReceiptError &&
  error.code === 'INVALID_SUPPLIER_IMPORT_FINALIZATION_RECEIPT' && error.message === 'Supplier Import finalization receipt is invalid.');
const dayRef = (dayId = 'staged-day-1') => ({kind: 'staged_day', dayId});
const serviceRef = {kind: 'staged_service', serviceId: 'staged-service-1'};

test('minimal successful receipt has the exact private root and immutable operation linkage', () => {
  const result = create(ready(assemble(f.snapshot())), ctx());
  assert.deepEqual(Object.keys(toMap(result)), ['schemaVersion', 'tripId', 'extractionId', 'resolutionId', 'sourcePackageId',
    'finalizationId', 'commandId', 'actorUid', 'finalizedAt', 'evaluatedRevision', 'resultingRevision', 'policyVersion',
    'canonicalSchemaVersion', 'resultingDraftId', 'requestFingerprint', 'contentDigest', 'outcomes']);
  assert.equal(result.schemaVersion, 'supplier_import_finalization_v1');
  assert.equal(result.canonicalSchemaVersion, 'itinerary_draft_v2');
  assert.equal(result.resolutionId, result.extractionId);
  assert.equal(result.finalizationId, result.commandId);
  assert.equal(result.resultingDraftId, 'draft-1');
  assert.equal(result.evaluatedRevision, 1); assert.equal(result.resultingRevision, 2);
  assert.equal(result.outcomes.length, 1); assert.equal(result.outcomes[0].targetId, null);
  assert.equal(result.outcomes[0].outcome, 'auto_retained');
});

test('automatic inclusion never claims consultant approval; explicit retain keeps the same canonical content', () => {
  const a = ready(assemble());
  const b = ready(assemble(f.snapshot({days: [f.day()]}), {decisions: [f.dayDecision('staged-day-1'), f.serviceDecision('staged-service-1')]}));
  assert.equal(serializeItineraryDraftV2(a.candidate), serializeItineraryDraftV2(b.candidate));
  const auto = create(a, ctx()), explicit = create(b, ctx());
  assert.equal(auto.contentDigest, explicit.contentDigest);
  assert.equal(row(auto, 'staged-service-1').outcome, 'auto_retained');
  assert.deepEqual(row(auto, 'staged-service-1').decisionIds, []);
  assert.equal(row(explicit, 'staged-service-1').outcome, 'explicit_retained');
  assert.deepEqual(row(explicit, 'staged-service-1').decisionIds, ['staged-service-1']);
});

test('corrections, clears and movement record only operations linked to their decision', () => {
  const source = f.snapshot({days: [f.day({notes: 'Private original note'}), f.day({services: []})]});
  const result = create(ready(assemble(source, {decisions: [
    f.dayDecision('staged-day-1', {overrides: {notes: f.clear}}),
    f.serviceDecision('staged-service-1', {overrides: {title: f.set('Unique corrected visit')}, day: dayRef('staged-day-2'), canonicalOrder: 4}),
  ]})), ctx());
  assert.deepEqual(row(result, 'staged-service-1').fieldOperations, ['canonicalOrder', 'day', 'title'].map((field) => ({field, operation: 'set', decisionId: 'staged-service-1'})));
  assert.deepEqual(row(result, 'staged-day-1').fieldOperations, [{field: 'notes', operation: 'clear', decisionId: 'staged-day-1'}]);
  assert(!serialize(result).includes('Unique corrected visit')); assert(!serialize(result).includes('Private original note'));
});

test('unassigned service assignment and manual items remain compact distinct outcomes', () => {
  const source = f.snapshot({days: [f.day({services: []})], unassignedServices: [f.service()]});
  const result = create(ready(assemble(source, {decisions: [f.serviceDecision('staged-service-1', {day: dayRef(), canonicalOrder: 1})],
    manualItems: [f.manualDay(), f.manualService()]})), ctx());
  assert.deepEqual(row(result, 'staged-service-1').fieldOperations.map((item) => item.field), ['canonicalOrder', 'day']);
  for (const id of ['consultant-day-1', 'consultant-service-1']) {
    assert.equal(row(result, id).outcome, 'manual'); assert.deepEqual(row(result, id).decisionIds, []);
  }
});

test('complete compact accounting includes package facts, exclusions, review, ancillary and commercial markers', () => {
  const source = f.snapshot({days: [f.day()], packageFacts: {
    accommodations: [{hotelName: 'Private hotel', roomType: 'Twin'}],
    inclusions: [{category: 'other', text: 'Private included service'}],
    exclusions: [{category: 'other', text: 'Private excluded service'}],
    conditions: [{kind: 'other', value: 'Private condition'}],
  }, ancillaryFacts: {flights: [{airline: 'Private airline'}], visas: [{disposition: 'mentioned', text: 'Private visa note'}]},
  reviewIssues: [f.issue()], commercialContent: {present: true, categories: ['package_price']}});
  const result = create(ready(assemble(source, {decisions: [
    f.packageDecision('package-fact-1', 'package_accommodation', {overrides: {roomType: f.set('Triple')}}),
    f.packageDecision('package-fact-3', 'package_statement', f.exclusion()),
    ...['flight', 'visa'].map((kind) => ({...f.meta(`ancillary-${kind}-1`, kind), disposition: 'handled_separately', destinationId: null,
      overrides: {}, exclusionReason: null, exclusionNote: null})),
  ]})), ctx());
  assert.equal(result.outcomes.length, 11);
  assert.equal(row(result, 'package-fact-1').outputTargets.length, 2);
  assert.deepEqual(row(result, 'package-fact-1').fieldOperations, [{field: 'roomType', operation: 'set', decisionId: 'package-fact-1'}]);
  assert.equal(row(result, 'package-fact-2').outcome, 'auto_retained');
  assert.equal(row(result, 'package-fact-3').outcome, 'excluded'); assert.deepEqual(row(result, 'package-fact-3').outputTargets, []);
  assert.equal(row(result, 'review-1').outcome, 'review_open_warning');
  assert.equal(row(result, 'commercial-presence-1').outcome, 'informational');
  for (const text of ['Private', 'Synthetic', 'Triple', 'Page 1', 'source.pdf', 'package_price', 'supplierName', 'auditEvents', 'sourceLabel']) assert(!serialize(result).includes(text), text);
});

for (const [kind, payload, destination, field] of [
  ['package_statement', {inclusions: [{category: 'other', text: 'Admission'}]}, 'service_inclusion', 'inclusions'],
  ['package_statement', {exclusions: [{category: 'other', text: 'Personal items'}]}, 'service_exclusion', 'exclusions'],
  ['package_condition', {conditions: [{kind: 'other', value: 'Meet guide'}]}, 'service_notes', 'notes'],
  ['package_condition', {conditions: [{kind: 'vehicle', value: 'Minivan'}]}, 'transfer_vehicle_type', 'transferDetails.vehicleType'],
  ['package_condition', {conditions: [{kind: 'operating_basis', value: 'private'}]}, 'transfer_type', 'transferDetails.transferType'],
]) test(`mapping preserves exact ${destination} output selector without duplicating text`, () => {
  const source = f.snapshot({days: [f.day({services: [f.service({type: 'transfer', transferDetails: {pickup: 'Airport', dropoff: 'Hotel'}})]})], packageFacts: payload});
  const result = create(ready(assemble(source, {decisions: [f.packageDecision('package-fact-1', kind, {disposition: 'map_to_service', service: serviceRef, destination})]})), ctx());
  assert.equal(row(result, 'package-fact-1').outcome, 'mapped');
  assert.deepEqual(row(result, 'package-fact-1').outputTargets, [{kind: 'service', id: row(result, 'staged-service-1').outputTargets[0].id, field}]);
});

test('mapped accommodation identifies the created hotel service and explicit day/order operations', () => {
  const source = f.snapshot({days: [f.day({services: []})], packageFacts: {accommodations: [{hotelName: 'Hotel'}]}});
  const result = create(ready(assemble(source, {decisions: [f.packageDecision('package-fact-1', 'package_accommodation',
    {disposition: 'map_to_day_service', day: dayRef(), canonicalOrder: 1})]})), ctx());
  const item = row(result, 'package-fact-1'); assert.equal(item.outcome, 'mapped');
  assert.equal(item.outputTargets[0].kind, 'service');
  assert.deepEqual(item.fieldOperations.map((change) => change.field), ['canonicalOrder', 'day']);
});

for (const kind of ['flight', 'visa']) for (const disposition of ['handled_separately', 'exclude', `route_to_${kind}_workflow`]) {
  test(`${kind} ${disposition} records disposition and no ancillary content or destination architecture`, () => {
    const source = f.snapshot({ancillaryFacts: kind === 'flight' ? {flights: [{airline: 'Unique airline'}]} : {visas: [{text: 'Unique visa', disposition: 'mentioned'}]}});
    const result = create(ready(assemble(source, {decisions: [{...f.meta(`ancillary-${kind}-1`, kind), disposition,
      destinationId: disposition.startsWith('route') ? 'workflow-1' : null, overrides: kind === 'visa' ? {text: f.clear} : {},
      exclusionReason: disposition === 'exclude' ? 'irrelevant_supplier_content' : null, exclusionNote: null}]})), ctx());
    const item = row(result, `ancillary-${kind}-1`);
    assert.equal(item.outcome, disposition === 'exclude' ? 'excluded' : disposition.startsWith('route') ? 'routed' : 'handled_separately');
    assert.deepEqual(item.outputTargets, []); assert(!serialize(result).includes('Unique')); assert(!serialize(result).includes('workflow-1'));
  });
}

for (const outcome of ['open', 'acknowledged', 'resolved', 'overridden']) test(`review ${outcome} preserves the existing policy outcome without issue text`, () => {
  const source = f.snapshot({days: [f.day()], reviewIssues: [f.issue({target: {kind: 'service', scope: 'day', dayIndex: 1, serviceIndex: 1}})]});
  const decisions = outcome === 'open' ? [] : [f.reviewDecision({outcome,
    resolutionReferences: outcome === 'resolved' ? [{kind: 'decision', decisionId: 'staged-service-1'}] : [],
    overrideReason: outcome === 'overridden' ? 'extracted_in_error' : null,
    overrideNote: outcome === 'overridden' ? 'Reviewed with source' : null})];
  if (outcome === 'resolved') decisions.push(f.serviceDecision('staged-service-1', {overrides: {title: f.set('Corrected service')}}));
  const result = create(ready(assemble(source, {decisions})), ctx());
  const item = row(result, 'review-1'); assert.equal(item.outcome, outcome === 'open' ? 'review_open_warning' : `review_${outcome}`);
  assert.equal(item.outputTargets.length, ['open', 'acknowledged'].includes(outcome) ? 1 : 0);
  assert(!serialize(result).includes('Check source detail'));
});

test('unresolved blocking review cannot create a receipt', () => {
  const result = assemble(f.snapshot({reviewIssues: [f.issue({severity: 'blocker', resolutionRequired: true})]}));
  assert.equal(result.canFinalize, false); rejects(() => create(result, ctx()));
});
for (const change of [{canFinalize: false}, {candidate: null}, {blockers: [{code: 'unresolved_review_issue', targetKind: 'review_issue', targetId: 'review-1'}]},
  {resolutionId: 'other'}, {evaluatedRevision: 2}, {extra: true}]) test(`factory fails closed for invalid assembly ${Object.keys(change)[0]}`, () => rejects(() => create({...assemble(), ...change}, ctx())));
for (const [key, value] of [['tripId', 'foreign'], ['extractionId', 'foreign'], ['commandId', 'foreign'], ['expectedRevision', 2], ['expectedRevision', 0],
  ['expectedRevision', Number.MAX_SAFE_INTEGER + 1], ['actorUid', 'other'], ['actorUid', ''], ['actorUid', 'x'.repeat(129)],
  ['policyVersion', 'unknown'], ['finalizedAt', new Date('invalid')], ['finalizedAt', new Date(0)], ['finalizedAt', f.at], ['extra', true]]) {
  test(`trusted context rejects conflicting/malformed ${key} ${JSON.stringify(value)?.slice(0, 25)}`, () => rejects(() => create(assemble(), ctx({[key]: value}))));
}

for (const [key, value] of [['schemaVersion', undefined], ['schemaVersion', 'supplier_import_finalization_v2'], ['schemaVersion', {version: 1}],
  ['canonicalSchemaVersion', 'itinerary_draft_v1'], ['policyVersion', 'supplier_import_exception_review_v2'],
  ['tripId', ' x'], ['extractionId', 'a/b'], ['resolutionId', 'other'], ['sourcePackageId', ''],
  ['actorUid', 'a\u0000b'], ['actorUid', 'x'.repeat(129)], ['finalizationId', 'x'.repeat(129)], ['commandId', 'other'],
  ['evaluatedRevision', 0], ['evaluatedRevision', -1], ['evaluatedRevision', 1.2], ['evaluatedRevision', '1'],
  ['evaluatedRevision', Number.MAX_SAFE_INTEGER + 1], ['resultingRevision', 1], ['resultingRevision', Number.MAX_SAFE_INTEGER + 1],
  ['finalizedAt', '2026-02-30T00:00:00.000Z'], ['finalizedAt', '2026-09-30'], ['finalizedAt', new Date(f.at)],
  ['contentDigest', 'bad'], ['contentDigest', 'A'.repeat(64)], ['contentDigest', 'a'.repeat(63)], ['requestFingerprint', 'a'.repeat(64)],
]) test(`strict map rejects ${key} ${JSON.stringify(value)?.slice(0, 25)}`, () => {const data = map(); data[key] = value; rejects(() => fromMap(data));});

for (const key of ['snapshot', 'resolution', 'canonicalDraft', 'auditEvents', 'supplierId', 'supplierName', 'rawText',
  'price', 'currency', 'rate', 'total', 'supplement', 'markup', 'margin', 'discount', 'payment', 'counts', 'extra']) {
  test(`unknown/private/commercial ${key} payload rejected at every nested boundary`, () => {
    const data = map(); data[key] = 'forbidden'; rejects(() => fromMap(data));
    const nested = map(); nested.outcomes[0][key] = 'forbidden'; rejects(() => fromMap(nested));
    const target = map(); target.outcomes[0].outputTargets[0][key] = 'forbidden'; rejects(() => fromMap(target));
    const op = map(); const r = op.outcomes.find((item) => item.targetKind === 'service'); r.outcome = 'explicit_retained'; r.decisionIds = [r.targetId];
    r.fieldOperations = [{field: 'title', operation: 'set', decisionId: r.targetId, [key]: 'forbidden'}]; rejects(() => fromMap(op));
  });
}

for (const [label, mutate] of [
  ['duplicate entity', (m) => m.outcomes.push(clone(m.outcomes[0]))],
  ['missing title', (m) => m.outcomes.splice(m.outcomes.findIndex((r) => r.targetKind === 'title'), 1)],
  ['title ID', (m) => m.outcomes.find((r) => r.targetKind === 'title').targetId = 'title'],
  ['wrong source namespace', (m) => m.outcomes[0].targetId = 'package-fact-1'],
  ['unknown disposition', (m) => m.outcomes[0].outcome = 'approve_everything'],
  ['blocked disposition', (m) => m.outcomes[0].outcome = 'blocked'],
  ['automatic pretending approval', (m) => m.outcomes[0].decisionIds = [m.outcomes[0].targetId]],
  ['explicit without decision', (m) => m.outcomes[0].outcome = 'explicit_retained'],
  ['excluded with output', (m) => {m.outcomes[0].outcome = 'excluded'; m.outcomes[0].decisionIds = [m.outcomes[0].targetId];}],
  ['unlinked operation', (m) => m.outcomes[0].fieldOperations = [{field: 'notes', operation: 'set', decisionId: 'foreign'}]],
  ['arbitrary output path', (m) => m.outcomes[0].outputTargets[0].field = 'days[0].title'],
  ['duplicate output', (m) => m.outcomes[0].outputTargets.push(clone(m.outcomes[0].outputTargets[0]))],
  ['missing output', (m) => m.outcomes[0].outputTargets = []],
  ['wrong draft target', (m) => m.outcomes.find((r) => r.targetKind === 'title').outputTargets[0].id = 'other'],
  ['contradictory draft ID', (m) => m.resultingDraftId = 'other'],
  ['sparse outcomes', (m) => delete m.outcomes[0]],
  ['array extra key', (m) => m.outcomes.extra = true],
  ['unknown symbol', (m) => m[Symbol('extra')] = true],
  ['accessor', (m) => Object.defineProperty(m, 'tripId', {get() {throw new Error('do not call');}})],
]) test(`strict receipt rejects ${label}`, () => {const data = map(); mutate(data); rejects(() => fromMap(data));});

test('invalid field operation type/duplicate/required clear and decision identity rejected', () => {
  for (const changes of [
    [{field: 'unknown', operation: 'set', decisionId: 'staged-day-1'}],
    [{field: 'notes', operation: 'merge', decisionId: 'staged-day-1'}],
    [{field: 'title', operation: 'clear', decisionId: 'staged-day-1'}],
    [{field: 'notes', operation: 'set', decisionId: 'staged-day-1'}, {field: 'notes', operation: 'clear', decisionId: 'staged-day-1'}],
  ]) {
    const data = map(); const item = row(data, 'staged-day-1'); item.outcome = 'explicit_retained'; item.decisionIds = [item.targetId];
    item.fieldOperations = changes; rejects(() => fromMap(data));
  }
});

test('factory rejects damaged/omitted accounting, source link and findings without dropping data', () => {
  const original = ready(assemble(f.snapshot({days: [f.day()], reviewIssues: [f.issue()]})));
  for (const mutate of [
    (a) => a.accounting.pop(), (a) => a.accounting[0].extra = true,
    (a) => a.accounting[0].sources[0].supplierSourcePackageId = 'foreign',
    (a) => a.accounting[0].sources[0].extra = true, (a) => a.accounting[0].origin = 'consultant',
    (a) => a.warnings = [], (a) => a.accounting.find((r) => r.entityKind === 'service').outputIds = ['missing'],
    (a) => a.accounting.find((r) => r.entityKind === 'service').mappingDestination = 'service_notes',
  ]) {
    const a = {...original, accounting: clone(original.accounting), warnings: clone(original.warnings)};
    mutate(a); rejects(() => create(a, ctx()));
  }
});

test('initial candidate verification rejects altered trip, draft, revision, package, identity and content', () => {
  const a = ready(assemble()), r = create(a, ctx()); bind(r, a.candidate);
  for (const mutate of [(m) => m.tripId = 'different', (m) => m.createdByUid = 'other', (m) => m.title = 'Changed trip',
    (m) => m.importResult.evaluatedRevision = 2, (m) => m.importResult.finalizationId = 'other',
    (m) => {m.importResult.extractionId = 'other'; m.importResult.resolutionId = 'other';},
    (m) => {m.importResult.sourcePackageId = 'different'; m.sourcePackageIds.push('different');},
  ]) {const m = clone(itineraryDraftV2ToMap(a.candidate)); mutate(m); rejects(() => bind(r, validateItineraryDraftV2(a.candidate.id, m)));}
  rejects(() => bind(r, validateItineraryDraftV2('different-draft', itineraryDraftV2ToMap(a.candidate))));
  const altered = map(); altered.contentDigest = '0'.repeat(64); rejects(() => bind(fromMap(altered), a.candidate));
});

test('canonical digest is pinned SHA-256 over authoritative V2 payload excluding only server timestamps', () => {
  const a = ready(assemble()); const {createdAt, updatedAt, ...payload} = itineraryDraftV2ToMap(a.candidate);
  assert.equal(digest(a.candidate), createHash('sha256').update(JSON.stringify(payload), 'utf8').digest('hex'));
  assert.equal(digest(a.candidate), '45d775931f3d2036b94e34ece2e82e4070f63b8e1525a4e8d640af7caf7c0381');
  const m = clone(itineraryDraftV2ToMap(a.candidate)); m.createdAt = m.updatedAt = '2026-10-01T06:00:00.000Z';
  assert.equal(digest(a.candidate), digest(validateItineraryDraftV2(a.candidate.id, m)));
});

test('property insertion order and same-instant Date copies cannot alter digest or receipt serialization', () => {
  const a = ready(assemble()); const reverse = (value) => Array.isArray(value) ? value.map(reverse) :
    value && typeof value === 'object' ? Object.fromEntries(Object.entries(value).reverse().map(([k, v]) => [k, reverse(v)])) : value;
  const other = validateItineraryDraftV2(a.candidate.id, reverse(itineraryDraftV2ToMap(a.candidate)));
  assert.equal(digest(a.candidate), digest(other));
  assert.equal(digest(a.candidate), digest({...a.candidate, createdAt: new Date(a.candidate.createdAt), updatedAt: new Date(a.candidate.updatedAt)}));
  assert.equal(serialize(receipt()), serialize(fromMap(reverse(map()))));
});

test('meaningful content including travel dates affects the digest', () => {
  const a = ready(assemble());
  for (const mutate of [(m) => m.title = 'Changed title', (m) => m.days[0].date = '2027-01-01',
    (m) => m.days[0].services[0].notes = 'Meet in lobby']) {
    const data = clone(itineraryDraftV2ToMap(a.candidate)); mutate(data);
    assert.notEqual(digest(a.candidate), digest(validateItineraryDraftV2(a.candidate.id, data)));
  }
});

test('idempotency fingerprint binds command, actor, trip, extraction, revision and policy, not timestamp', () => {
  const source = f.snapshot(); const a = ready(assemble(source)), base = create(a, ctx());
  assert.equal(base.requestFingerprint, 'ac5e5b5985cc60e1b15302aa161b60ef7add296a637f90c533cee6d9ec3b7e30');
  assert.equal(base.requestFingerprint, create(a, ctx({finalizedAt: new Date('2026-10-01T00:00:00.000Z')})).requestFingerprint);
  const changedRevision = ready(assemble(source, {root: f.root(source, {revision: 2})}));
  assert.notEqual(base.requestFingerprint, create(changedRevision, ctx({expectedRevision: 2})).requestFingerprint);
  for (const change of [{actorUid: 'admin-1'}, {finalizationId: 'other-command'}]) {
    const c = {...f.context(), ...change};
    assert.notEqual(base.requestFingerprint, create(ready(assemble(source, {}, c)), ctx({actorUid: c.actorUid, commandId: c.finalizationId})).requestFingerprint);
  }
});

test('stable accounting order, exact round trip and detached deep immutability', () => {
  const a = ready(assemble()), context = ctx(), before = serializeItineraryDraftV2(a.candidate);
  const r = create({...a, accounting: [...a.accounting].reverse()}, context);
  assert.equal(serialize(r), serialize(create(a, ctx())));
  const data = clone(toMap(r)); const copy = fromMap(data); data.outcomes[0].outputTargets[0].dayNumber = 999; data.outcomes.length = 0;
  context.finalizedAt.setTime(0); r.finalizedAt.setTime(0);
  assert.equal(r.finalizedAt.toISOString(), f.at); assert.equal(serialize(r), serialize(copy));
  assert.equal(serialize(fromMap(JSON.parse(serialize(r)))), serialize(r));
  for (const value of [r, r.finalizedAt, r.outcomes, r.outcomes[0], r.outcomes[0].decisionIds, r.outcomes[0].outputTargets, r.outcomes[0].outputTargets[0], toMap(r)]) assert(Object.isFrozen(value));
  assert.throws(() => r.outcomes.push({}), TypeError);
  assert.equal(serializeItineraryDraftV2(a.candidate), before);
});

for (const count of [2000, 2001]) test(`Snapshot entity capacity ${count} excludes the root title`, () => {
  const data = toMap(create(ready(assemble(f.snapshot())), ctx()));
  const outcomes = [...data.outcomes, ...Array.from({length: count}, (_, i) => ({targetKind: 'day', targetId: `staged-day-${i + 1}`,
    outcome: 'auto_retained', decisionIds: [], outputTargets: [{kind: 'day', dayNumber: i + 1, field: 'entity'}], fieldOperations: []}))];
  if (count === 2000) assert.equal(fromMap({...data, outcomes}).outcomes.length, 2001);
  else rejects(() => fromMap({...data, outcomes}));
});
for (const count of [2000, 2001]) test(`combined decisions/manual capacity ${count}`, () => {
  const data = toMap(create(ready(assemble(f.snapshot())), ctx()));
  const title = {...data.outcomes[0], outcome: 'explicit_retained', decisionIds: ['title']};
  const outcomes = [title, ...Array.from({length: count - 1}, (_, i) => ({targetKind: 'consultant_day', targetId: `consultant-day-${i + 1}`,
    outcome: 'manual', decisionIds: [], outputTargets: [{kind: 'day', dayNumber: i + 1, field: 'entity'}], fieldOperations: []}))];
  if (count === 2000) assert.equal(fromMap({...data, outcomes}).outcomes.length, 2000);
  else rejects(() => fromMap({...data, outcomes}));
});

test('long source content is not copied or gated by an inaccurate Firestore JSON byte estimate', () => {
  const source = f.snapshot({packageFacts: {inclusions: [{category: 'other', text: 'a'.repeat(1100000)}]}});
  const r = create(ready(assemble(source)), ctx()); assert(serialize(r).length < 2000);
});
test('closed validation vocabularies are immutable at runtime', () => {
  const domain = require('../lib/itineraryExtraction/supplierImportFinalizationReceipt');
  for (const key of ['receiptTargetKinds', 'receiptOutcomeCodes', 'receiptOutputKinds', 'receiptOutputFields', 'receiptOperationFields']) assert(Object.isFrozen(domain[key]), key);
  for (const fields of Object.values(domain.receiptOperationFields)) assert(Object.isFrozen(fields));
});
test('mapped inclusion cannot masquerade as exclusion or target an unowned service', () => {
  const source = f.snapshot({days: [f.day()], packageFacts: {inclusions: [{category: 'other', text: 'Admission'}]}});
  const result = create(ready(assemble(source, {decisions: [f.packageDecision('package-fact-1', 'package_statement',
    {disposition: 'map_to_service', service: serviceRef, destination: 'service_inclusion'})]})), ctx());
  const wrongField = clone(toMap(result)); row(wrongField, 'package-fact-1').outputTargets[0].field = 'exclusions'; rejects(() => fromMap(wrongField));
  const missingOwner = clone(toMap(result)); row(missingOwner, 'package-fact-1').outputTargets[0].id = 'unowned'; rejects(() => fromMap(missingOwner));
});
test('factory rejects swapped service lineage and missing canonical owners', () => {
  const source = f.snapshot({days: [f.day({services: [f.service(), f.service({title: 'Second visit'})]})]});
  const a = ready(assemble(source)); const ledger = clone(a.accounting);
  const entries = ledger.filter((r) => r.entityKind === 'service');
  [entries[0].outputIds, entries[1].outputIds] = [entries[1].outputIds, entries[0].outputIds];
  rejects(() => create({...a, accounting: ledger}, ctx()));
  rejects(() => create({...a, accounting: a.accounting.filter((r) => r.entityId !== 'staged-service-1')}, ctx()));
});
test('package lineage rejects an accounting record that hides its correction', () => {
  const source = f.snapshot({packageFacts: {inclusions: [{category: 'other', text: 'Admission'}]}});
  const a = ready(assemble(source, {decisions: [f.packageDecision('package-fact-1', 'package_statement', {overrides: {text: f.set('Updated admission')}})]}));
  const ledger = clone(a.accounting); ledger.find((r) => r.entityId === 'package-fact-1').fieldChanges = [];
  rejects(() => create({...a, accounting: ledger}, ctx()));
});
test('title correction and day reorder have exact root/day selectors', () => {
  const source = f.snapshot({days: [f.day({services: []})]});
  const result = create(ready(assemble(source, {decisions: [
    {...f.meta('title', 'title'), disposition: 'override', overrides: {title: f.set('Reviewed trip')}},
    f.dayDecision('staged-day-1', {canonicalOrder: 4}),
  ]})), ctx());
  const title = result.outcomes.find((r) => r.targetKind === 'title');
  assert.deepEqual(title.outputTargets, [{kind: 'draft', id: 'draft-1', field: 'title'}]);
  assert.deepEqual(title.fieldOperations, [{field: 'title', operation: 'set', decisionId: 'title'}]);
  assert.deepEqual(row(result, 'staged-day-1').outputTargets, [{kind: 'day', dayNumber: 4, field: 'entity'}]);
});
test('largest safe evaluated revision cannot overflow the resulting seal revision', () => {
  const source = f.snapshot(); const a = ready(assemble(source, {root: f.root(source, {revision: Number.MAX_SAFE_INTEGER})}));
  rejects(() => create(a, ctx({expectedRevision: Number.MAX_SAFE_INTEGER})));
});
test('receipt modules remain pure, private and independent of persistence/provider/clock/randomness', () => {
  const dir = path.join(__dirname, '../src/itineraryExtraction');
  for (const file of fs.readdirSync(dir).filter((name) => name.startsWith('supplierImportFinalizationReceipt') && name.endsWith('.ts'))) {
    const text = fs.readFileSync(path.join(dir, file), 'utf8');
    const imports = [...text.matchAll(/from\s+["']([^"']+)["']/g)].map((match) => match[1]);
    assert(!imports.some((name) => /firebase|firestore|repository|persistence|provider|genai|storage/i.test(name)), file);
    assert(!/Date\.now|new Date\(\)|Math\.random|randomUUID|fetch\(/.test(text), file);
    assert(!/Buffer\.byteLength|TextEncoder/.test(text), file);
  }
});

test('derived issue accounting never invents an explicit issue decision or copies prose', () => {
  const source = f.snapshot({days: [f.day()], reviewIssues: [f.issue({code: 'chronology_unknown', target: {kind: 'day', dayIndex: 1}})]});
  const result = create(ready(assemble(source, {decisions: [f.dayDecision('staged-day-1', {canonicalOrder: 2})]})), ctx());
  assert.equal(row(result, 'review-1').outcome, 'review_derived');
  assert.deepEqual(row(result, 'review-1').decisionIds, []);
  assert.equal(JSON.stringify(toMap(result)).includes('Check source detail'), false);
  assert.equal(fromMap(toMap(result)).outcomes.find(x => x.targetId === 'review-1').outcome, 'review_derived');
});
