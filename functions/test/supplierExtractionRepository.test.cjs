const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  SupplierExtractionPersistenceError,
  readSupplierExtractionSnapshot,
  serializeSupplierExtractionForPersistence,
  writeSupplierExtractionSnapshot,
} = require('../lib/itineraryExtraction/supplierExtractionRepository');
const {
  normalizeSupplierExtractionSnapshot,
} = require('../lib/itineraryExtraction/supplierExtractionValidation');

function sourceFile(sourceFileId, packageId = 'package-1') {
  return {
    sourceFileId,
    packageId,
    originalFileName: `${sourceFileId}.pdf`,
    storagePath: `trips/trip-1/supplier_sources/${sourceFileId}/source.pdf`,
    contentType: 'application/pdf',
    sizeBytes: 100,
    uploadedByUid: 'agent-1',
  };
}

function trustedPackage(fileIds = ['file-1', 'file-2']) {
  return {
    tripId: 'trip-1',
    packageId: 'package-1',
    supplierId: 'supplier-1',
    supplierNameSnapshot: 'Synthetic Supplier',
    files: fileIds.map((id) => sourceFile(id)),
  };
}

function snapshot({
  extractionId = 'extraction-1',
  packageValue = trustedPackage(),
  payload = completePayload(),
} = {}) {
  return normalizeSupplierExtractionSnapshot(payload, {
    extractionId,
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    jobId: 'job-1',
    requestedByUid: 'agent-1',
    createdAt: new Date('2026-09-29T05:00:00.000Z'),
    providerVersion: 'kayra_itinerary_extraction_v3_staging',
    trustedPackage: packageValue,
  });
}

function completePayload() {
  return {
    title: {
      text: 'Synthetic itinerary',
      basis: 'neutral_supported',
      sources: [{fileIndex: 1, sourceLabel: 'Page 1'}],
    },
    days: [{
      sourceDayNumber: 1,
      date: '2027-02-01',
      title: 'Arrival',
      services: [{
        type: 'transfer',
        title: 'Airport transfer',
        transferDetails: {pickup: 'Airport', dropoff: 'Hotel'},
        sources: [{fileIndex: 1, sourceLabel: 'Page 1'}],
      }],
    }],
    unassignedServices: [{
      type: 'sightseeing',
      title: 'City tour',
      sources: [{fileIndex: 2, sourceLabel: 'Tour list'}],
    }],
    packageFacts: {
      accommodations: [{hotelName: 'Example Hotel', city: 'Example City'}],
      inclusions: [{category: 'water', text: 'Water included'}],
    },
    ancillaryFacts: {
      flights: [{origin: 'DEL', destination: 'DXB'}],
      visas: [{disposition: 'mentioned'}],
    },
    commercialContent: {present: true, categories: ['package_price']},
    reviewIssues: [{
      code: 'chronology_unknown',
      severity: 'blocker',
      message: 'Assign the city tour.',
      target: {kind: 'service', scope: 'unassigned', serviceIndex: 1},
      resolutionRequired: true,
      sources: [{fileIndex: 2, sourceLabel: 'Tour list'}],
    }],
  };
}

class MemoryStore {
  constructor(packageValue = trustedPackage()) {
    this.packageValue = packageValue;
    this.records = new Map();
    this.createCalls = 0;
    this.failRelationship = false;
  }

  async loadTrustedPackage(tripId, packageId) {
    if (this.failRelationship || tripId !== this.packageValue.tripId ||
        packageId !== this.packageValue.packageId) {
      throw new SupplierExtractionPersistenceError(
        'INVALID_SUPPLIER_EXTRACTION',
        'Trusted source relationship is invalid.',
      );
    }
    return this.packageValue;
  }

  async createSnapshot(records) {
    this.createCalls += 1;
    const key = `${records.root.tripId}/${records.root.extractionId}`;
    if (this.records.has(key)) {
      throw new SupplierExtractionPersistenceError(
        'SUPPLIER_EXTRACTION_PERSISTENCE_FAILED',
        'Snapshot already exists.',
      );
    }
    const stored = clone(records);
    stored.root.persistenceState = 'complete';
    this.records.set(key, stored);
  }

  async readSnapshot(tripId, extractionId) {
    const value = this.records.get(`${tripId}/${extractionId}`);
    return value === undefined ? null : clone(value);
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function write(value, store, extractionId = value.extractionId) {
  return writeSupplierExtractionSnapshot({
    tripId: value.tripId,
    extractionId,
    snapshot: value,
  }, store);
}

const hasCode = (code) => (error) =>
  error instanceof SupplierExtractionPersistenceError && error.code === code;

test('successful write/read round-trip preserves all staged entity groups', async () => {
  const store = new MemoryStore();
  const original = snapshot();
  const result = await write(original, store);
  const restored = await readSupplierExtractionSnapshot(
    'trip-1',
    result.extractionId,
    store,
  );

  assert.deepEqual(restored, original);
  assert.equal(restored.days.length, 1);
  assert.equal(restored.facts.filter((fact) => fact.factKind === 'service').length, 2);
  assert.equal(restored.facts.some((fact) => fact.factKind === 'package_inclusion'), true);
  assert.equal(restored.facts.some((fact) => fact.factKind === 'flight'), true);
  assert.equal(restored.reviewIssues[0].target.entityId, 'staged-service-2');
  assert.equal(
    restored.facts.find((fact) => fact.id === 'staged-service-2')
      .sources[0].supplierSourceFileId,
    'file-2',
  );
});

test('persistence records use root metadata and ordered child envelopes', () => {
  const records = serializeSupplierExtractionForPersistence(snapshot());
  assert.equal(records.root.persistenceState, 'writing');
  assert.deepEqual(Object.keys(records.root).sort(), [
    'counts', 'createdAt', 'extractionId', 'jobId', 'persistenceState',
    'providerVersion', 'requestedByUid', 'schemaVersion', 'sourcePackageId',
    'title', 'tripId',
  ]);
  assert.deepEqual(records.days.map((item) => item.snapshotOrder), [1]);
  assert.deepEqual(
    records.facts.map((item) => item.snapshotOrder),
    records.facts.map((_, index) => index + 1),
  );
  assert.equal(records.facts[0].documentId, records.facts[0].value.id);
});

test('incomplete chronology round-trips without a fake day', async () => {
  const store = new MemoryStore();
  const original = snapshot({payload: {
    title: {text: 'Undated package', basis: 'neutral_supported'},
    unassignedServices: [
      {type: 'activity', title: 'Museum visit'},
      {type: 'meal', title: 'Welcome dinner'},
    ],
    reviewIssues: [{
      code: 'chronology_unknown',
      severity: 'blocker',
      message: 'Service chronology is unknown.',
      target: {kind: 'snapshot'},
      resolutionRequired: true,
    }],
  }});
  await write(original, store);
  const restored = await readSupplierExtractionSnapshot(
    'trip-1',
    original.extractionId,
    store,
  );
  assert.equal(restored.days.length, 0);
  assert(restored.facts.every((fact) =>
    fact.factKind !== 'service' || fact.scope.kind === 'unassigned'));
});

test('global accommodation retains unknown stay dates', async () => {
  const store = new MemoryStore();
  const original = snapshot({payload: {
    title: {text: 'Hotel package', basis: 'neutral_supported'},
    packageFacts: {
      accommodations: [{hotelName: 'Example Hotel', nightCount: 4}],
    },
  }});
  await write(original, store);
  const restored = await readSupplierExtractionSnapshot(
    'trip-1',
    original.extractionId,
    store,
  );
  const hotel = restored.facts.find((fact) =>
    fact.factKind === 'package_accommodation');
  assert.equal(hotel.details.checkInDate, null);
  assert.equal(hotel.details.checkOutDate, null);
  assert.equal(hotel.details.nightCount, 4);
});

test('rerun uses a new ID and cannot overwrite an existing snapshot', async () => {
  const store = new MemoryStore();
  const first = snapshot({extractionId: 'extraction-1'});
  const second = snapshot({extractionId: 'extraction-2'});
  await write(first, store);
  await write(second, store);
  await assert.rejects(() => write(first, store),
    hasCode('SUPPLIER_EXTRACTION_PERSISTENCE_FAILED'));
  assert.equal(store.records.size, 2);
  assert.deepEqual(
    await readSupplierExtractionSnapshot('trip-1', 'extraction-1', store),
    first,
  );
});

test('invalid Trip/package relationship is rejected before persistence', async () => {
  const store = new MemoryStore();
  store.failRelationship = true;
  await assert.rejects(() => write(snapshot(), store),
    hasCode('INVALID_SUPPLIER_EXTRACTION'));
  assert.equal(store.createCalls, 0);
});

test('invalid trusted file relationship is rejected before persistence', async () => {
  const original = snapshot();
  const store = new MemoryStore(trustedPackage(['file-1']));
  await assert.rejects(() => write(original, store),
    hasCode('INVALID_SUPPLIER_EXTRACTION'));
  assert.equal(store.createCalls, 0);
});

test('snapshot/path extraction ID mismatch is rejected before persistence', async () => {
  const store = new MemoryStore();
  await assert.rejects(
    () => write(snapshot(), store, 'different-extraction'),
    hasCode('INVALID_SUPPLIER_EXTRACTION'),
  );
  assert.equal(store.createCalls, 0);
});

test('cross-reference and derived-count corruption is rejected', async () => {
  for (const mutate of [
    (value) => { value.facts[0].scope.dayId = 'staged-day-missing'; },
    (value) => { value.counts.assignedServices = 99; },
  ]) {
    const store = new MemoryStore();
    const changed = clone(snapshot());
    mutate(changed);
    await assert.rejects(() => write(changed, store),
      hasCode('INVALID_SUPPLIER_EXTRACTION'));
    assert.equal(store.createCalls, 0);
  }
});

test('writing state is never reconstructed as a complete snapshot', async () => {
  const store = new MemoryStore();
  const original = snapshot();
  const records = clone(serializeSupplierExtractionForPersistence(original));
  records.root.persistenceState = 'writing';
  records.facts = records.facts.slice(0, 1);
  store.records.set('trip-1/extraction-1', records);
  await assert.rejects(
    () => readSupplierExtractionSnapshot('trip-1', 'extraction-1', store),
    hasCode('SUPPLIER_EXTRACTION_UNAVAILABLE'),
  );
});

test('unknown root or child fields are rejected on trusted read', async () => {
  for (const mutate of [
    (records) => { records.root.unexpected = true; },
    (records) => { records.facts[0].value.unexpected = true; },
  ]) {
    const store = new MemoryStore();
    const records = clone(serializeSupplierExtractionForPersistence(snapshot()));
    records.root.persistenceState = 'complete';
    mutate(records);
    store.records.set('trip-1/extraction-1', records);
    await assert.rejects(
      () => readSupplierExtractionSnapshot('trip-1', 'extraction-1', store),
      hasCode('INVALID_STORED_SUPPLIER_EXTRACTION'),
    );
  }
});

test('child document identity and sequence corruption are rejected', async () => {
  for (const mutate of [
    (records) => { records.facts[0].documentId = 'wrong-id'; },
    (records) => { records.facts[0].snapshotOrder = 2; },
  ]) {
    const store = new MemoryStore();
    const records = clone(serializeSupplierExtractionForPersistence(snapshot()));
    records.root.persistenceState = 'complete';
    mutate(records);
    store.records.set('trip-1/extraction-1', records);
    await assert.rejects(
      () => readSupplierExtractionSnapshot('trip-1', 'extraction-1', store),
      hasCode('INVALID_STORED_SUPPLIER_EXTRACTION'),
    );
  }
});
