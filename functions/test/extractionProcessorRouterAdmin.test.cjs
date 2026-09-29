const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {Timestamp} = require('firebase-admin/firestore');
const {
  adminExtractionRoutingJobReader,
} = require('../lib/itineraryExtraction/extractionProcessorRouterAdmin');

const tripId = 'trip-1';
const jobId = 'job-1';
const jobPath = `trips/${tripId}/itinerary_extraction_jobs/${jobId}`;

function legacy(overrides = {}) {
  return {
    tripId,
    sourcePackageId: 'package-1',
    status: 'queued',
    requestedByUid: 'agent-1',
    resultingDraftId: null,
    failureCode: null,
    createdAt: Timestamp.fromMillis(1000),
    updatedAt: Timestamp.fromMillis(1000),
    ...overrides,
  };
}

function versioned(contract, resultType, overrides = {}) {
  return {
    ...legacy(),
    extractionContractVersion: contract,
    resultType,
    resultingExtractionId: null,
    ...overrides,
  };
}

function readerFixture(record, readError = null) {
  const reads = [];
  const db = {
    doc(actualPath) {
      reads.push(actualPath);
      return {
        async get() {
          if (readError) throw readError;
          return {
            exists: record !== null,
            data: () => record,
          };
        },
      };
    },
  };
  return {reads, reader: adminExtractionRoutingJobReader(db)};
}

test('Admin reader reloads the exact path and infers legacy V2.4 contract', async () => {
  const f = readerFixture(legacy());
  const result = await f.reader.readAuthoritativeJob(tripId, jobId);
  assert.deepEqual(f.reads, [jobPath]);
  assert.equal(result.kind, 'job');
  assert.equal(result.job.persistenceShape, 'legacy');
  assert.equal(result.job.extractionContractVersion, 'itinerary_draft_v1');
  assert.equal(result.job.resultType, 'itinerary_draft');
});

for (const [contract, resultType] of [
  ['itinerary_draft_v1', 'itinerary_draft'],
  ['supplier_extraction_v1', 'supplier_extraction'],
]) {
  test(`Admin reader accepts strict ${contract}`, async () => {
    const f = readerFixture(versioned(contract, resultType));
    const result = await f.reader.readAuthoritativeJob(tripId, jobId);
    assert.equal(result.kind, 'job');
    assert.equal(result.job.extractionContractVersion, contract);
    assert.equal(result.job.resultType, resultType);
  });
}

test('partial version metadata is deterministic non-processable', async () => {
  const f = readerFixture({
    ...legacy(), extractionContractVersion: 'supplier_extraction_v1',
  });
  assert.deepEqual(
    await f.reader.readAuthoritativeJob(tripId, jobId),
    {kind: 'not_processable', reason: 'invalid_contract'},
  );
});

test('invalid contract/result pair is deterministic non-processable', async () => {
  const f = readerFixture(versioned(
    'supplier_extraction_v1', 'itinerary_draft',
  ));
  assert.deepEqual(
    await f.reader.readAuthoritativeJob(tripId, jobId),
    {kind: 'not_processable', reason: 'invalid_contract'},
  );
});

test('unknown future contract is non-processable and never guessed', async () => {
  const f = readerFixture(versioned('future_v9', 'future_result'));
  assert.deepEqual(
    await f.reader.readAuthoritativeJob(tripId, jobId),
    {kind: 'not_processable', reason: 'invalid_contract'},
  );
});

test('job Trip mismatch and missing document are non-processable', async () => {
  const mismatch = readerFixture(legacy({tripId: 'trip-2'}));
  assert.deepEqual(
    await mismatch.reader.readAuthoritativeJob(tripId, jobId),
    {kind: 'not_processable', reason: 'invalid_contract'},
  );
  const missing = readerFixture(null);
  assert.deepEqual(
    await missing.reader.readAuthoritativeJob(tripId, jobId),
    {kind: 'not_processable', reason: 'missing'},
  );
});

test('Firestore read failures propagate unchanged for trigger retry', async () => {
  const failure = new Error('private transient Firestore failure');
  const f = readerFixture(null, failure);
  await assert.rejects(
    () => f.reader.readAuthoritativeJob(tripId, jobId),
    (error) => error === failure,
  );
});

test('production router composition imports both processors exactly once', () => {
  const source = fs.readFileSync(path.resolve(
    __dirname,
    '../src/itineraryExtraction/extractionProcessorRouterAdmin.ts',
  ), 'utf8');
  assert.equal(
    (source.match(/processItineraryExtractionJob/g) ?? []).length,
    2,
  );
  assert.equal(
    (source.match(/processSupplierExtractionJob/g) ?? []).length,
    2,
  );
  assert.equal(source.includes('adminSupplierExtractionProcessorDependencies'), true);
});
