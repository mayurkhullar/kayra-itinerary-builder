const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  supplierImportResolutionSchemaVersion,
} = require('../lib/itineraryExtraction/supplierImportResolution');
const {
  serializeSupplierImportResolution,
  reconstructStoredSupplierImportResolution,
} = require('../lib/itineraryExtraction/supplierImportResolutionStoredValidation');
const {
  SupplierImportResolutionRepositoryError,
  readSupplierImportResolution,
  supplierImportResolutionPaths,
} = require('../lib/itineraryExtraction/supplierImportResolutionRepository');
const {
  supplierImportResolutionReferences,
  supplierImportResolutionValueForFirestore,
} = require('../lib/itineraryExtraction/supplierImportResolutionRepositoryAdmin');
const {
  normalizeSupplierExtractionSnapshot,
} = require('../lib/itineraryExtraction/supplierExtractionValidation');

const at = '2026-09-30T06:00:00.000Z';

function source() {
  return normalizeSupplierExtractionSnapshot({
    title: {text: 'Trip', basis: 'neutral_supported'},
    days: [{title: 'Day', services: [{type: 'other', title: 'Service'}]}],
    unassignedServices: [{title: 'Unassigned'}],
    packageFacts: {inclusions: [{category: 'meal', text: 'Breakfast'}]},
    ancillaryFacts: {flights: [{origin: 'DEL', destination: 'DXB'}]},
    reviewIssues: [{
      code: 'other', severity: 'warning', message: 'Check wording',
      target: {kind: 'snapshot'}, resolutionRequired: false,
    }],
  }, {
    extractionId: 'extraction-1', tripId: 'trip-1',
    sourcePackageId: 'package-1', jobId: 'job-1', requestedByUid: 'agent-1',
    createdAt: new Date(at), providerVersion: 'v3',
    trustedPackage: trustedPackage(),
  });
}

function trustedPackage() {
  return {tripId: 'trip-1', packageId: 'package-1', supplierId: null,
    supplierNameSnapshot: null, files: [{sourceFileId: 'file-1',
      packageId: 'package-1', originalFileName: 'source.pdf',
      storagePath: 'trips/trip-1/supplier_sources/file-1/source.pdf',
      contentType: 'application/pdf', sizeBytes: 100, uploadedByUid: 'agent-1'}]};
}

function event(revision = 1, overrides = {}) {
  return {
    eventId: `command-${revision}`, resolutionId: 'extraction-1',
    extractionId: 'extraction-1', previousRevision: revision - 1,
    resultingRevision: revision, actorUid: 'agent-1', occurredAt: at,
    action: revision === 1 ? 'open_review' : 'finalize',
    targetKind: revision === 1 ? 'resolution' : 'finalization',
    targetId: 'extraction-1', commandId: `command-${revision}`,
    metadata: {kind: 'lifecycle', status: revision === 1 ? 'active' : 'finalized'},
    ...overrides,
  };
}

function resolution(snapshot, overrides = {}) {
  return {
    root: {
      schemaVersion: supplierImportResolutionSchemaVersion,
      resolutionId: snapshot.extractionId, tripId: snapshot.tripId,
      extractionId: snapshot.extractionId, sourcePackageId: snapshot.sourcePackageId,
      snapshotSchemaVersion: snapshot.schemaVersion, status: 'active', revision: 1,
      createdByUid: 'agent-1', createdAt: at, updatedByUid: 'agent-1',
      updatedAt: at, finalizedByUid: null, finalizedAt: null,
      resultingDraftId: null,
    },
    decisions: [], manualItems: [], auditEvents: [event()], ...overrides,
  };
}

function meta(id, kind) {
  return {decisionId: id, decisionKind: kind, targetEntityId: id,
    lastRevision: 1, updatedByUid: 'agent-1', updatedAt: at};
}

function dayDecision() {
  return {...meta('staged-day-1', 'day'), disposition: 'retain', overrides: {},
    exclusionReason: null, exclusionNote: null};
}

function serviceDecision() {
  return {...meta('staged-service-2', 'service'), disposition: 'retain',
    day: {kind: 'staged_day', dayId: 'staged-day-1'}, canonicalOrder: 2,
    overrides: {serviceType: {operation: 'set', value: 'other'},
      title: {operation: 'set', value: 'Assigned'}},
    exclusionReason: null, exclusionNote: null};
}

function manualItems() {
  const common = {origin: 'consultant', createdByUid: 'agent-1', createdAt: at,
    updatedByUid: 'agent-1', updatedAt: at, lastRevision: 1};
  return [
    {...common, itemKind: 'consultant_day', manualDayId: 'consultant-day-1',
      canonicalOrder: 2, date: null, title: 'Manual day', summary: null, notes: null},
    {...common, itemKind: 'consultant_service',
      manualServiceId: 'consultant-service-1',
      day: {kind: 'consultant_day', manualDayId: 'consultant-day-1'},
      canonicalOrder: 1, serviceType: 'other', title: 'Manual service',
      description: null, startTime: null, endTime: null, location: null, city: null,
      inclusions: [], exclusions: [], notes: null, hotelDetails: null,
      transferDetails: null, activityDetails: null},
  ];
}

const clone = (value) => JSON.parse(JSON.stringify(value));
const malformed = (error) => error instanceof SupplierImportResolutionRepositoryError &&
  error.code === 'INVALID_STORED_SUPPLIER_IMPORT_RESOLUTION';

class Store {
  constructor(snapshot, records) { this.snapshot = snapshot; this.records = records; }
  async loadAuthoritativeSnapshot() { return this.snapshot; }
  async readResolution() { return this.records; }
}

test('missing resolution returns explicit not_started after authoritative Snapshot load', async () => {
  const snapshot = source();
  const result = await readSupplierImportResolution(
    'trip-1', 'extraction-1', new Store(snapshot, null),
  );
  assert.deepEqual(result, {kind: 'not_started'});
});

test('active empty resolution serializes and reconstructs exactly', async () => {
  const snapshot = source();
  const stored = serializeSupplierImportResolution(snapshot, resolution(snapshot));
  const result = await readSupplierImportResolution(
    'trip-1', 'extraction-1', new Store(snapshot, stored),
  );
  assert.equal(result.kind, 'found');
  assert.equal(result.resolution.root.status, 'active');
  assert.equal(Object.hasOwn(stored.root.value, 'canFinalize'), false);
});

test('multiple decisions reconstruct deterministically independent of query order', () => {
  const snapshot = source();
  const stored = clone(serializeSupplierImportResolution(snapshot, resolution(snapshot, {
    decisions: [serviceDecision(), dayDecision()],
  })));
  stored.decisions.reverse();
  const value = reconstructStoredSupplierImportResolution(
    snapshot, stored, 'trip-1', 'extraction-1',
  );
  assert.deepEqual(value.decisions.map((item) => item.decisionId),
    ['staged-day-1', 'staged-service-2']);
});

test('manual day and service reconstruct without Supplier provenance', () => {
  const snapshot = source();
  const stored = serializeSupplierImportResolution(snapshot, resolution(snapshot, {
    manualItems: manualItems(),
  }));
  const value = reconstructStoredSupplierImportResolution(
    snapshot, stored, 'trip-1', 'extraction-1',
  );
  assert.equal(value.manualItems.length, 2);
  assert(value.manualItems.every((item) => !Object.hasOwn(item, 'sources')));
});

test('audit history reconstructs in revision order', () => {
  const snapshot = source();
  const input = resolution(snapshot);
  input.root = {...input.root, revision: 2, updatedAt: at};
  input.auditEvents = [event(2, {action: 'set_day_decision',
    targetKind: 'day', targetId: 'staged-day-1',
    metadata: {kind: 'decision', disposition: 'retain', changedFields: [],
      exclusionReason: null, referencedIds: []}}), event(1)];
  const stored = clone(serializeSupplierImportResolution(snapshot, input));
  stored.auditEvents.reverse();
  const value = reconstructStoredSupplierImportResolution(
    snapshot, stored, 'trip-1', 'extraction-1',
  );
  assert.deepEqual(value.auditEvents.map((item) => item.resultingRevision), [1, 2]);
});

test('finalized resolution reconstructs with result identity', () => {
  const snapshot = source();
  const input = resolution(snapshot);
  input.root = {...input.root, status: 'finalized', revision: 2,
    finalizedByUid: 'agent-1', finalizedAt: at, resultingDraftId: 'draft-1'};
  input.auditEvents = [event(1), event(2)];
  assert.equal(serializeSupplierImportResolution(snapshot, input).root.value.status,
    'finalized');
});

test('root path, Trip, extraction, package, schema, and revision corruption reject', async () => {
  const snapshot = source();
  const original = serializeSupplierImportResolution(snapshot, resolution(snapshot));
  const mutations = [
    (x) => { x.root.documentId = 'wrong'; },
    (x) => { x.root.value.tripId = 'trip-2'; },
    (x) => { x.root.value.extractionId = 'wrong'; },
    (x) => { x.root.value.sourcePackageId = 'wrong'; },
    (x) => { x.root.value.schemaVersion = 'future'; },
    (x) => { x.root.value.revision = 1.5; },
  ];
  for (const mutate of mutations) {
    const stored = clone(original); mutate(stored);
    await assert.rejects(() => readSupplierImportResolution(
      'trip-1', 'extraction-1', new Store(snapshot, stored),
    ), malformed);
  }
});

test('malformed and competing decision documents reject', async () => {
  const snapshot = source();
  const original = serializeSupplierImportResolution(snapshot, resolution(snapshot, {
    decisions: [dayDecision()],
  }));
  for (const mutate of [
    (x) => { x.decisions[0].value.disposition = 'unknown'; },
    (x) => { x.decisions.push(clone(x.decisions[0])); },
    (x) => { x.decisions[0].documentId = 'wrong'; },
  ]) {
    const stored = clone(original); mutate(stored);
    await assert.rejects(() => readSupplierImportResolution(
      'trip-1', 'extraction-1', new Store(snapshot, stored),
    ), malformed);
  }
});

test('malformed, duplicate, and provenance-bearing manual items reject', async () => {
  const snapshot = source();
  const original = serializeSupplierImportResolution(snapshot, resolution(snapshot, {
    manualItems: manualItems(),
  }));
  for (const mutate of [
    (x) => { x.manualItems[0].value.origin = 'machine'; },
    (x) => { x.manualItems.push(clone(x.manualItems[0])); },
    (x) => { x.manualItems[0].value.sources = []; },
  ]) {
    const stored = clone(original); mutate(stored);
    await assert.rejects(() => readSupplierImportResolution(
      'trip-1', 'extraction-1', new Store(snapshot, stored),
    ), malformed);
  }
});

test('malformed, duplicate, and discontinuous events reject', async () => {
  const snapshot = source();
  const original = serializeSupplierImportResolution(snapshot, resolution(snapshot));
  for (const mutate of [
    (x) => { x.auditEvents[0].value.resultingRevision = 3; },
    (x) => { x.auditEvents.push(clone(x.auditEvents[0])); },
    (x) => { x.auditEvents[0].value.action = 'unknown'; },
  ]) {
    const stored = clone(original); mutate(stored);
    await assert.rejects(() => readSupplierImportResolution(
      'trip-1', 'extraction-1', new Store(snapshot, stored),
    ), malformed);
  }
});

test('commercial-value leakage and derived readiness reject as unknown fields', async () => {
  const snapshot = source();
  const original = serializeSupplierImportResolution(snapshot, resolution(snapshot));
  for (const field of ['price', 'canFinalize']) {
    const stored = clone(original); stored.root.value[field] = field === 'price' ? 370 : true;
    await assert.rejects(() => readSupplierImportResolution(
      'trip-1', 'extraction-1', new Store(snapshot, stored),
    ), malformed);
  }
});

test('nonexistent Snapshot target, day assignment, and incompatible override reject', async () => {
  const snapshot = source();
  const cases = [
    {...dayDecision(), decisionId: 'staged-day-404', targetEntityId: 'staged-day-404'},
    {...serviceDecision(), day: {kind: 'staged_day', dayId: 'staged-day-404'}},
    {...serviceDecision(), overrides: {hotel: {hotelName: {
      operation: 'set', value: 'Hotel',
    }}}},
  ];
  for (const decision of cases) {
    const stored = clone({
      root: {documentId: 'extraction-1', value: resolution(snapshot).root},
      decisions: [{documentId: decision.decisionId, value: decision}],
      manualItems: [], auditEvents: [{documentId: 'command-1', value: event()}],
    });
    await assert.rejects(() => readSupplierImportResolution(
      'trip-1', 'extraction-1', new Store(snapshot, stored),
    ), malformed);
  }
});

test('wrong package, ancillary, and review variants reject', async () => {
  const snapshot = source();
  for (const decision of [
    {...meta('package-fact-1', 'flight'), disposition: 'handled_separately',
      destinationId: null, overrides: {}, exclusionReason: null, exclusionNote: null},
    {...meta('ancillary-flight-1', 'package_statement'),
      disposition: 'retain_package_level', service: null, destination: null,
      overrides: {}, exclusionReason: null, exclusionNote: null},
    {...meta('staged-day-1', 'review_issue'), outcome: 'acknowledged',
      resolutionReferences: [], overrideReason: null, overrideNote: null},
  ]) {
    const input = resolution(snapshot, {decisions: [decision]});
    assert.throws(() => serializeSupplierImportResolution(snapshot, input));
  }
});

test('authoritative Snapshot supplied by the store controls cross-reference validation', async () => {
  const snapshot = source();
  const stored = serializeSupplierImportResolution(snapshot, resolution(snapshot, {
    decisions: [dayDecision()],
  }));
  const other = normalizeSupplierExtractionSnapshot({
    title: {text: 'Other', basis: 'neutral_supported'},
  }, {
    extractionId: 'extraction-1', tripId: 'trip-1', sourcePackageId: 'package-1',
    jobId: 'job-1', requestedByUid: 'agent-1', createdAt: new Date(at),
    providerVersion: 'v3', trustedPackage: trustedPackage(),
  });
  await assert.rejects(() => readSupplierImportResolution(
    'trip-1', 'extraction-1', new Store(other, stored),
  ), malformed);
});

test('repository paths use the exact deterministic hierarchy', () => {
  assert.deepEqual(supplierImportResolutionPaths('trip-1', 'extraction-1'), {
    root: 'trips/trip-1/supplier_extractions/extraction-1/resolutions/extraction-1',
    decisions: 'trips/trip-1/supplier_extractions/extraction-1/resolutions/extraction-1/decisions',
    manualItems: 'trips/trip-1/supplier_extractions/extraction-1/resolutions/extraction-1/manual_items',
    auditEvents: 'trips/trip-1/supplier_extractions/extraction-1/resolutions/extraction-1/events',
  });
});

test('Admin transaction references use deterministic child paths', () => {
  class Reference {
    constructor(path) { this.path = path; this.id = path.split('/').at(-1); }
    collection(name) { return {doc: (id) => new Reference(`${this.path}/${name}/${id}`)}; }
  }
  const references = supplierImportResolutionReferences(
    {doc: (path) => new Reference(path)}, 'trip-1', 'extraction-1',
  );
  assert.equal(references.root.path,
    'trips/trip-1/supplier_extractions/extraction-1/resolutions/extraction-1');
  assert.equal(references.decision('staged-day-1').path,
    `${references.root.path}/decisions/staged-day-1`);
  assert.equal(references.manualItem('consultant-day-1').path,
    `${references.root.path}/manual_items/consultant-day-1`);
  assert.equal(references.auditEvent('command-1').path,
    `${references.root.path}/events/command-1`);
});

test('Admin serializer converts only documented timestamps for Firestore', () => {
  const value = supplierImportResolutionValueForFirestore({
    createdAt: at, nested: {occurredAt: at}, note: at, finalizedAt: null,
  });
  assert.equal(typeof value.createdAt.toDate, 'function');
  assert.equal(value.createdAt.toDate().toISOString(), at);
  assert.equal(value.nested.occurredAt.toDate().toISOString(), at);
  assert.equal(value.note, at);
  assert.equal(value.finalizedAt, null);
});
