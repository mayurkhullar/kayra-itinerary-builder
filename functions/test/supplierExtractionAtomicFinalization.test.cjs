const {test} = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');
const {
  SupplierExtractionPersistenceError,
  serializeSupplierExtractionForPersistence,
} = require('../lib/itineraryExtraction/supplierExtractionRepository');
const {
  adminSupplierExtractionRepositoryStore,
} = require('../lib/itineraryExtraction/supplierExtractionRepositoryAdmin');
const {
  normalizeSupplierExtractionSnapshot,
} = require('../lib/itineraryExtraction/supplierExtractionValidation');

const tripId = 'trip-1';
const packageId = 'package-1';
const jobId = 'job-1';
const rootPath = `trips/${tripId}/supplier_extractions/${jobId}`;
const jobPath = `trips/${tripId}/itinerary_extraction_jobs/${jobId}`;

const hasCode = (code) => (error) =>
  error instanceof SupplierExtractionPersistenceError && error.code === code;

function fixture({job = extractionJob(), actualJobId = jobId} = {}) {
  const db = new FakeFirestore();
  db.records.set(`trips/${tripId}`, {ownerUid: 'agent-1'});
  db.records.set(`trips/${tripId}/supplier_source_packages/${packageId}`, {
    tripId,
    supplierId: 'supplier-1',
    supplierNameSnapshot: 'Synthetic Supplier',
    fileIds: ['file-1'],
    uploadedByUid: 'agent-1',
    status: 'uploaded',
  });
  db.records.set(`trips/${tripId}/supplier_source_files/file-1`, sourceFile());
  db.records.set(
    `trips/${tripId}/itinerary_extraction_jobs/${actualJobId}`,
    job,
  );
  const trustedPackage = {
    tripId,
    packageId,
    supplierId: 'supplier-1',
    supplierNameSnapshot: 'Synthetic Supplier',
    files: [{
      sourceFileId: 'file-1',
      packageId,
      originalFileName: 'source.pdf',
      storagePath: `trips/${tripId}/supplier_sources/file-1/source.pdf`,
      contentType: 'application/pdf',
      sizeBytes: 100,
      uploadedByUid: 'agent-1',
    }],
  };
  const normalized = normalizeSupplierExtractionSnapshot(payload(), {
    extractionId: actualJobId,
    tripId,
    sourcePackageId: packageId,
    jobId: actualJobId,
    requestedByUid: 'agent-1',
    createdAt: new Date('2026-09-29T05:00:00.000Z'),
    providerVersion: 'kayra_itinerary_extraction_v3_staging',
    trustedPackage,
  });
  return {
    db,
    store: adminSupplierExtractionRepositoryStore(db),
    records: serializeSupplierExtractionForPersistence(normalized),
    trustedPackage,
  };
}

function extractionJob(overrides = {}) {
  return {
    tripId,
    sourcePackageId: packageId,
    status: 'processing',
    requestedByUid: 'agent-1',
    resultingDraftId: null,
    failureCode: null,
    createdAt: Timestamp.fromMillis(1000),
    updatedAt: Timestamp.fromMillis(2000),
    extractionContractVersion: 'supplier_extraction_v1',
    resultType: 'supplier_extraction',
    resultingExtractionId: null,
    ...overrides,
  };
}

function sourceFile() {
  return {
    tripId,
    packageId,
    originalFileName: 'source.pdf',
    storagePath: `trips/${tripId}/supplier_sources/file-1/source.pdf`,
    contentType: 'application/pdf',
    sizeBytes: 100,
    uploadedByUid: 'agent-1',
  };
}

function payload() {
  return {
    title: {text: 'Synthetic itinerary', basis: 'neutral_supported'},
    days: [{
      sourceDayNumber: 1,
      date: '2027-02-01',
      title: 'Arrival',
      services: [{
        type: 'transfer',
        title: 'Airport transfer',
        transferDetails: {pickup: 'Airport', dropoff: 'Hotel'},
      }],
    }],
    packageFacts: {
      inclusions: [{category: 'water', text: 'Water included'}],
    },
    reviewIssues: [{
      code: 'other',
      severity: 'warning',
      message: 'Confirm the pickup time.',
      target: {kind: 'service', scope: 'day', dayIndex: 1, serviceIndex: 1},
      resolutionRequired: true,
    }],
  };
}

async function beginAndWrite(f) {
  await f.store.beginSnapshot(f.records, f.trustedPackage);
  await f.store.writeSnapshotChildren(f.records);
}

test('begin creates only a writing root', async () => {
  const f = fixture();
  assert.equal(await f.store.beginSnapshot(f.records, f.trustedPackage), 'writing');
  assert.equal(f.db.records.get(rootPath).persistenceState, 'writing');
  assert.equal([...f.db.records.keys()].some((path) =>
    path.startsWith(`${rootPath}/days/`)), false);
  assert.equal(f.db.records.get(jobPath).status, 'processing');
});

test('child writes are create-only and leave both states unfinished', async () => {
  const f = fixture();
  await beginAndWrite(f);
  const firstSize = f.db.records.size;
  await f.store.writeSnapshotChildren(f.records);
  assert.equal(f.db.records.size, firstSize);
  assert.equal(f.db.records.get(rootPath).persistenceState, 'writing');
  assert.equal(f.db.records.get(jobPath).status, 'processing');
});

test('one transaction completes the Snapshot and Supplier Extraction job', async () => {
  const f = fixture();
  await beginAndWrite(f);
  assert.equal(
    await f.store.finalizeSnapshot(f.records, f.trustedPackage),
    'completed',
  );
  assert.equal(f.db.records.get(rootPath).persistenceState, 'complete');
  assert.equal(f.db.records.get(jobPath).status, 'completed');
  assert.equal(f.db.records.get(jobPath).resultingExtractionId, jobId);
  assert.equal(f.db.lastCommitUpdates.has(rootPath), true);
  assert.equal(f.db.lastCommitUpdates.has(jobPath), true);
});

test('missing child rejects finalization and changes neither state', async () => {
  const f = fixture();
  await beginAndWrite(f);
  const factPath = [...f.db.records.keys()].find((path) =>
    path.startsWith(`${rootPath}/facts/`));
  f.db.records.delete(factPath);
  await assert.rejects(
    () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
    hasCode('INCOMPLETE_SUPPLIER_EXTRACTION'),
  );
  assert.equal(f.db.records.get(rootPath).persistenceState, 'writing');
  assert.equal(f.db.records.get(jobPath).status, 'processing');
});

test('corrupted child order rejects finalization', async () => {
  const f = fixture();
  await beginAndWrite(f);
  const factPath = [...f.db.records.keys()].find((path) =>
    path.startsWith(`${rootPath}/facts/`));
  f.db.records.get(factPath).snapshotOrder = 99;
  await assert.rejects(
    () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
    hasCode('INVALID_STORED_SUPPLIER_EXTRACTION'),
  );
  assert.equal(f.db.records.get(rootPath).persistenceState, 'writing');
  assert.equal(f.db.records.get(jobPath).status, 'processing');
});

test('extra child count rejects finalization', async () => {
  const f = fixture();
  await beginAndWrite(f);
  const [factPath, fact] = [...f.db.records.entries()].find(([path]) =>
    path.startsWith(`${rootPath}/facts/`));
  f.db.records.set(`${factPath}-duplicate`, {
    ...clone(fact),
    snapshotOrder: fact.snapshotOrder + 1,
  });
  await assert.rejects(
    () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
    hasCode('INVALID_STORED_SUPPLIER_EXTRACTION'),
  );
  assert.equal(f.db.records.get(rootPath).persistenceState, 'writing');
  assert.equal(f.db.records.get(jobPath).status, 'processing');
});

test('wrong package or requesting-user relationship is rejected', async () => {
  for (const overrides of [
    {tripId: 'trip-2'},
    {sourcePackageId: 'package-2'},
    {requestedByUid: 'agent-2'},
  ]) {
    const f = fixture();
    await beginAndWrite(f);
    Object.assign(f.db.records.get(jobPath), overrides);
    await assert.rejects(
      () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
      hasCode('SUPPLIER_EXTRACTION_RELATIONSHIP_MISMATCH'),
    );
  }
});

test('itinerary-draft contract is rejected', async () => {
  const f = fixture();
  await beginAndWrite(f);
  Object.assign(f.db.records.get(jobPath), {
    extractionContractVersion: 'itinerary_draft_v1',
    resultType: 'itinerary_draft',
  });
  await assert.rejects(
    () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
    hasCode('SUPPLIER_EXTRACTION_JOB_CONTRACT_MISMATCH'),
  );
});

test('queued, failed, and malformed-result jobs cannot finalize', async () => {
  for (const job of [
    extractionJob({status: 'queued'}),
    extractionJob({status: 'failed', failureCode: 'extraction_failed'}),
    extractionJob({resultingExtractionId: 'existing-result'}),
  ]) {
    const f = fixture();
    await beginAndWrite(f);
    f.db.records.set(jobPath, job);
    await assert.rejects(
      () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
      hasCode('SUPPLIER_EXTRACTION_JOB_STATE_MISMATCH'),
    );
  }
});

test('repeat after successful finalization is idempotent', async () => {
  const f = fixture();
  await beginAndWrite(f);
  await f.store.finalizeSnapshot(f.records, f.trustedPackage);
  assert.equal(
    await f.store.finalizeSnapshot(f.records, f.trustedPackage),
    'already_completed',
  );
  assert.equal(f.db.records.get(jobPath).resultingExtractionId, jobId);
});

test('complete Snapshot with processing job is an integrity error', async () => {
  const f = fixture();
  await beginAndWrite(f);
  f.db.records.get(rootPath).persistenceState = 'complete';
  await assert.rejects(
    () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
    hasCode('SUPPLIER_EXTRACTION_JOB_STATE_MISMATCH'),
  );
});

test('writing Snapshot with completed job is an integrity error', async () => {
  const f = fixture();
  await beginAndWrite(f);
  f.db.records.set(jobPath, extractionJob({
    status: 'completed', resultingExtractionId: jobId,
  }));
  await assert.rejects(
    () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
    hasCode('SUPPLIER_EXTRACTION_JOB_STATE_MISMATCH'),
  );
});

test('completed job linked to another extraction is rejected', async () => {
  const f = fixture();
  await beginAndWrite(f);
  f.db.records.get(rootPath).persistenceState = 'complete';
  f.db.records.set(jobPath, extractionJob({
    status: 'completed', resultingExtractionId: 'another-extraction',
  }));
  await assert.rejects(
    () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
    hasCode('SUPPLIER_EXTRACTION_JOB_STATE_MISMATCH'),
  );
});

test('Snapshot linked to another job is rejected', async () => {
  const f = fixture();
  await beginAndWrite(f);
  f.db.records.get(rootPath).jobId = 'another-job';
  await assert.rejects(
    () => f.store.finalizeSnapshot(f.records, f.trustedPackage),
    hasCode('SUPPLIER_EXTRACTION_RELATIONSHIP_MISMATCH'),
  );
});

class FakeFirestore {
  constructor() {
    this.records = new Map();
    this.lastCommitUpdates = new Set();
  }

  doc(path) {
    return new FakeDocumentReference(this, path);
  }

  async getAll(...references) {
    return references.map((reference) => this.snapshot(reference));
  }

  async runTransaction(callback) {
    const writes = [];
    const transaction = {
      get: async (target) => target instanceof FakeQuery ?
        this.querySnapshot(target) : this.snapshot(target),
      getAll: async (...references) =>
        references.map((reference) => this.snapshot(reference)),
      create: (reference, data) => writes.push({kind: 'create', reference, data}),
      update: (reference, data) => writes.push({kind: 'update', reference, data}),
    };
    const result = await callback(transaction);
    for (const write of writes) {
      if (write.kind === 'create' && this.records.has(write.reference.path)) {
        throw new Error('Document already exists.');
      }
    }
    this.lastCommitUpdates = new Set(writes
      .filter((write) => write.kind === 'update')
      .map((write) => write.reference.path));
    for (const write of writes) {
      const data = resolveSentinels(clone(write.data));
      if (write.kind === 'create') {
        this.records.set(write.reference.path, data);
      } else {
        this.records.set(write.reference.path, {
          ...this.records.get(write.reference.path),
          ...data,
        });
      }
    }
    return result;
  }

  snapshot(reference) {
    return new FakeDocumentSnapshot(
      reference,
      this.records.has(reference.path) ? this.records.get(reference.path) : null,
    );
  }

  querySnapshot(query) {
    const prefix = `${query.collection.path}/`;
    const documents = [...this.records.entries()]
      .filter(([path]) => path.startsWith(prefix) &&
        !path.slice(prefix.length).includes('/'))
      .map(([path, data]) => new FakeDocumentSnapshot(
        new FakeDocumentReference(this, path),
        data,
      ))
      .sort((left, right) =>
        left.data()[query.field] - right.data()[query.field]);
    return {docs: documents};
  }
}

class FakeDocumentReference {
  constructor(db, path) {
    this.db = db;
    this.path = path;
    this.id = path.split('/').at(-1);
  }

  collection(name) {
    return new FakeCollectionReference(this.db, `${this.path}/${name}`);
  }

  get() {
    return Promise.resolve(this.db.snapshot(this));
  }
}

class FakeCollectionReference {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }

  doc(id) {
    return new FakeDocumentReference(this.db, `${this.path}/${id}`);
  }

  orderBy(field) {
    return new FakeQuery(this, field);
  }
}

class FakeQuery {
  constructor(collection, field) {
    this.collection = collection;
    this.field = field;
  }

  get() {
    return Promise.resolve(this.collection.db.querySnapshot(this));
  }
}

class FakeDocumentSnapshot {
  constructor(reference, data) {
    this.reference = reference;
    this.id = reference.id;
    this.exists = data !== null;
    this.value = data;
  }

  data() {
    return this.exists ? clone(this.value) : undefined;
  }
}

function clone(value) {
  if (value instanceof Timestamp) return value;
  if (Array.isArray(value)) return value.map(clone);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value)
      .map(([key, item]) => [key, clone(item)]));
  }
  return value;
}

function resolveSentinels(data) {
  for (const [key, value] of Object.entries(data)) {
    if (key === 'updatedAt' && !(value instanceof Timestamp)) {
      data[key] = Timestamp.now();
    }
  }
  return data;
}
