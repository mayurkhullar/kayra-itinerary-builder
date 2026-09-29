const {test} = require('node:test');
const assert = require('node:assert/strict');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {
  adminSupplierExtractionProcessorJobStore,
} = require('../lib/itineraryExtraction/supplierExtractionProcessorAdmin');

const tripId = 'trip-v3';
const jobId = 'job-v3';
const jobPath = `trips/${tripId}/itinerary_extraction_jobs/${jobId}`;

function supplierJob(overrides = {}) {
  return {
    tripId,
    sourcePackageId: 'package-v3',
    status: 'queued',
    requestedByUid: 'agent-v3',
    resultingDraftId: null,
    failureCode: null,
    createdAt: Timestamp.fromMillis(1000),
    updatedAt: Timestamp.fromMillis(1000),
    extractionContractVersion: 'supplier_extraction_v1',
    resultType: 'supplier_extraction',
    resultingExtractionId: null,
    ...overrides,
  };
}

function draftJob(overrides = {}) {
  return supplierJob({
    extractionContractVersion: 'itinerary_draft_v1',
    resultType: 'itinerary_draft',
    ...overrides,
  });
}

function memoryDb(record) {
  const records = new Map([[jobPath, record]]);
  const state = {records, updates: []};
  let queue = Promise.resolve();
  const db = {
    doc(path) { return {path}; },
    runTransaction(callback) {
      const operation = queue.then(async () => {
        const writes = [];
        const transaction = {
          async get(ref) {
            return {
              exists: records.has(ref.path),
              data: () => records.get(ref.path),
            };
          },
          update(ref, data) { writes.push({ref, data}); },
        };
        const result = await callback(transaction);
        for (const {ref, data} of writes) {
          const materialized = Object.fromEntries(
            Object.entries(data).map(([key, value]) => [
              key,
              value && typeof value.isEqual === 'function' &&
                value.isEqual(FieldValue.serverTimestamp()) ?
                Timestamp.now() : value,
            ]),
          );
          records.set(ref.path, {...records.get(ref.path), ...materialized});
          state.updates.push({path: ref.path, data});
        }
        return result;
      });
      queue = operation.catch(() => {});
      return operation;
    },
  };
  return {db, state, store: adminSupplierExtractionProcessorJobStore(db)};
}

test('Admin claim strictly promotes queued supplier_extraction_v1 to processing', async () => {
  const f = memoryDb(supplierJob());
  const result = await f.store.claimSupplierExtractionJob(tripId, jobId);
  assert.equal(result.kind, 'claimed');
  assert.equal(result.job.jobId, jobId);
  assert.equal(result.job.extractionContractVersion, 'supplier_extraction_v1');
  assert.equal(result.job.resultType, 'supplier_extraction');
  assert.equal(result.job.persistenceShape, 'versioned');
  assert.equal(f.state.records.get(jobPath).status, 'processing');
  assert.equal(
    f.state.records.get(jobPath).extractionContractVersion,
    'supplier_extraction_v1',
  );
});

test('concurrent Admin claims allow one owner and one already-processing no-op', async () => {
  const f = memoryDb(supplierJob());
  const results = await Promise.all([
    f.store.claimSupplierExtractionJob(tripId, jobId),
    f.store.claimSupplierExtractionJob(tripId, jobId),
  ]);
  assert.deepEqual(results.map((value) => value.kind), [
    'claimed', 'already_processing',
  ]);
  assert.equal(f.state.updates.length, 1);
});

test('draft, legacy, and malformed partial-version jobs are not applicable', async () => {
  const legacy = supplierJob();
  delete legacy.extractionContractVersion;
  delete legacy.resultType;
  delete legacy.resultingExtractionId;
  const malformed = supplierJob();
  delete malformed.resultType;
  for (const record of [draftJob(), legacy, malformed]) {
    const f = memoryDb(record);
    assert.deepEqual(
      await f.store.claimSupplierExtractionJob(tripId, jobId),
      {kind: 'not_applicable'},
    );
    assert.equal(f.state.updates.length, 0);
  }
});

test('Admin claim reports matching completed, failed, and processing states', async () => {
  const cases = [
    [supplierJob({status: 'processing'}), {kind: 'already_processing'}],
    [supplierJob({status: 'completed', resultingExtractionId: jobId}),
      {kind: 'already_completed', extractionId: jobId}],
    [supplierJob({status: 'failed', failureCode: 'extraction_failed'}),
      {kind: 'terminal_failure', failureCode: 'extraction_failed'}],
  ];
  for (const [record, expected] of cases) {
    const f = memoryDb(record);
    assert.deepEqual(
      await f.store.claimSupplierExtractionJob(tripId, jobId),
      expected,
    );
    assert.equal(f.state.updates.length, 0);
  }
});

test('completed itinerary-draft result is not claimed by Supplier Extraction', async () => {
  const f = memoryDb(draftJob({
    status: 'completed',
    resultingDraftId: 'draft-v2',
  }));
  assert.deepEqual(
    await f.store.claimSupplierExtractionJob(tripId, jobId),
    {kind: 'not_applicable'},
  );
});

test('failure finalization never overwrites a completed Supplier Extraction', async () => {
  const f = memoryDb(supplierJob({
    status: 'completed', resultingExtractionId: jobId,
  }));
  const result = await f.store.finalizeSupplierExtractionFailure(
    {
      jobId,
      tripId,
      sourcePackageId: 'package-v3',
      requestedByUid: 'agent-v3',
      extractionContractVersion: 'supplier_extraction_v1',
      resultType: 'supplier_extraction',
      persistenceShape: 'versioned',
    },
    'supplier_extraction_persistence_failed',
  );
  assert.deepEqual(result, {kind: 'completed', extractionId: jobId});
  assert.equal(f.state.updates.length, 0);
  assert.equal(f.state.records.get(jobPath).status, 'completed');
});

test('failure finalization writes only supplier-compatible failure state', async () => {
  const f = memoryDb(supplierJob({status: 'processing'}));
  const result = await f.store.finalizeSupplierExtractionFailure(
    {
      jobId,
      tripId,
      sourcePackageId: 'package-v3',
      requestedByUid: 'agent-v3',
      extractionContractVersion: 'supplier_extraction_v1',
      resultType: 'supplier_extraction',
      persistenceShape: 'versioned',
    },
    'supplier_extraction_persistence_failed',
  );
  assert.deepEqual(result, {
    kind: 'failed', failureCode: 'supplier_extraction_persistence_failed',
  });
  assert.equal(f.state.records.get(jobPath).status, 'failed');
  assert.equal(f.state.records.get(jobPath).resultingExtractionId, null);
  assert.equal(f.state.records.get(jobPath).resultingDraftId, null);
});
