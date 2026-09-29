const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  GeminiStagingProviderError,
} = require('../lib/itineraryExtraction/geminiStagingProvider');
const {
  ItineraryExtractionProviderError,
} = require('../lib/itineraryExtraction/processor');
const {
  processSupplierExtractionJob,
  SupplierExtractionProcessorError,
} = require('../lib/itineraryExtraction/supplierExtractionProcessor');
const {
  TrustedSourceError,
} = require('../lib/itineraryExtraction/sourceReaderValidation');

const tripId = 'trip-v3';
const jobId = 'job-v3';
const packageId = 'package-v3';
const requestedByUid = 'agent-v3';
const fixedTime = new Date('2026-09-29T08:00:00.000Z');

function claimedJob(actualJobId = jobId) {
  return Object.freeze({
    jobId: actualJobId,
    tripId,
    sourcePackageId: packageId,
    requestedByUid,
    extractionContractVersion: 'supplier_extraction_v1',
    resultType: 'supplier_extraction',
    persistenceShape: 'versioned',
  });
}

function trustedPackage() {
  return Object.freeze({
    tripId,
    packageId,
    supplierId: 'supplier-v3',
    supplierNameSnapshot: 'Private supplier name',
    files: Object.freeze([Object.freeze({
      sourceFileId: 'source-v3',
      packageId,
      originalFileName: 'private-source.pdf',
      storagePath: `${tripId}/private/source.pdf`,
      contentType: 'application/pdf',
      sizeBytes: 200,
      uploadedByUid: requestedByUid,
    })]),
  });
}

function providerPayload(label = 'Private itinerary title') {
  return {
    title: {text: label, basis: 'explicit_supplier'},
    days: [{
      sourceDayNumber: 1,
      title: 'Private arrival day',
      services: [{type: 'hotel', title: 'Private Hotel Name'}],
    }],
  };
}

function fixture(options = {}) {
  const calls = {
    claim: 0,
    source: 0,
    provider: 0,
    begin: 0,
    children: 0,
    finalize: 0,
    inspect: 0,
    failure: [],
    phases: [],
  };
  const logs = [];
  const packages = trustedPackage();
  const jobs = options.jobs ?? {
    async claimSupplierExtractionJob() {
      calls.claim += 1;
      return options.claim ?? {kind: 'claimed', job: claimedJob()};
    },
    async finalizeSupplierExtractionFailure(job, failureCode) {
      calls.failure.push({job, failureCode});
      if (options.failureFinalizationError) {
        throw options.failureFinalizationError;
      }
      return options.failureResult ?? {kind: 'failed', failureCode};
    },
  };
  const sources = {
    async readTrustedPackage(actualTripId, actualPackageId) {
      calls.source += 1;
      assert.equal(actualTripId, tripId);
      assert.equal(actualPackageId, packageId);
      if (options.sourceError) throw options.sourceError;
      return packages;
    },
  };
  const provider = {
    async extract(input) {
      calls.provider += 1;
      assert.equal(input.tripId, tripId);
      assert.equal(input.sourcePackage, packages);
      if (options.providerError) throw options.providerError;
      return options.providerResult ?? providerPayload();
    },
  };
  const snapshots = {
    async beginSnapshot(records, sourcePackage) {
      calls.begin += 1;
      calls.phases.push('begin');
      calls.records = records;
      assert.equal(sourcePackage, packages);
      if (options.failurePhase === 'begin') throw new Error('private begin');
      return options.beginState ?? 'writing';
    },
    async writeSnapshotChildren(records) {
      calls.children += 1;
      calls.phases.push('children');
      assert.equal(records, calls.records);
      if (options.failurePhase === 'children') throw new Error('private child');
    },
    async finalizeSnapshot(records, sourcePackage) {
      calls.finalize += 1;
      calls.phases.push('finalize');
      assert.equal(records, calls.records);
      assert.equal(sourcePackage, packages);
      if (options.failurePhase === 'finalize') throw new Error('private final');
      return 'completed';
    },
    async inspectFinalization(records, sourcePackage) {
      calls.inspect += 1;
      assert.equal(records, calls.records);
      assert.equal(sourcePackage, packages);
      if (options.inspectionError) throw options.inspectionError;
      return options.inspection ?? 'eligible_for_failure';
    },
  };
  const dependencies = {
    jobs,
    sources,
    provider,
    snapshots,
    now: () => fixedTime,
    ...(options.normalize ? {normalize: options.normalize} : {}),
  };
  const run = (actualJobId = jobId) => processSupplierExtractionJob(
    {tripId, jobId: actualJobId},
    dependencies,
    (event, fields) => logs.push({event, ...fields}),
  );
  return {calls, logs, packages, dependencies, run};
}

test('happy path executes the V3 phases once and atomically completes by job ID', async () => {
  const f = fixture();
  assert.deepEqual(await f.run(), {
    outcome: 'completed', jobId, extractionId: jobId,
  });
  assert.deepEqual(f.calls.phases, ['begin', 'children', 'finalize']);
  assert.equal(f.calls.provider, 1);
  assert.equal(f.calls.records.root.extractionId, jobId);
  assert.equal(f.calls.records.root.jobId, jobId);
  assert.equal(f.calls.records.root.tripId, tripId);
  assert.equal(f.calls.records.root.sourcePackageId, packageId);
  assert.equal(f.calls.records.root.requestedByUid, requestedByUid);
  assert.equal(f.calls.records.root.createdAt, fixedTime.toISOString());
  assert.equal(f.calls.failure.length, 0);
});

for (const [name, claim, expected] of [
  ['wrong contract', {kind: 'not_applicable'}, {outcome: 'not_applicable', jobId}],
  ['already completed', {kind: 'already_completed', extractionId: jobId},
    {outcome: 'already_completed', jobId, extractionId: jobId}],
  ['already failed', {kind: 'terminal_failure', failureCode: 'extraction_failed'},
    {outcome: 'terminal_failure', jobId, failureCode: 'extraction_failed'}],
  ['already processing', {kind: 'already_processing'},
    {outcome: 'already_processing', jobId}],
]) {
  test(`${name} is a deterministic no-op before source or provider work`, async () => {
    const f = fixture({claim});
    assert.deepEqual(await f.run(), expected);
    assert.equal(f.calls.source, 0);
    assert.equal(f.calls.provider, 0);
    assert.equal(f.calls.begin, 0);
  });
}

test('source integrity/unavailability maps to source_unavailable', async () => {
  const f = fixture({sourceError: new TrustedSourceError(
    'INVALID_SOURCE_INTEGRITY', 'private source detail',
  )});
  assert.equal((await f.run()).failureCode, 'source_unavailable');
  assert.equal(f.calls.provider, 0);
  assert.equal(f.calls.failure[0].failureCode, 'source_unavailable');
});

test('unsupported trusted source maps to unsupported_source', async () => {
  const f = fixture({sourceError: new TrustedSourceError(
    'UNSUPPORTED_SOURCE', 'private source detail',
  )});
  assert.equal((await f.run()).failureCode, 'unsupported_source');
  assert.equal(f.calls.provider, 0);
});

test('provider unsupported-source error maps to unsupported_source', async () => {
  const f = fixture({providerError: new ItineraryExtractionProviderError(
    'UNSUPPORTED_SOURCE', 'private provider detail',
  )});
  assert.equal((await f.run()).failureCode, 'unsupported_source');
});

test('ordinary provider execution error maps to extraction_failed', async () => {
  const f = fixture({providerError: new ItineraryExtractionProviderError(
    'PROVIDER_EXECUTION_FAILED', 'private provider detail',
  )});
  assert.equal((await f.run()).failureCode, 'extraction_failed');
});

for (const reason of [
  'empty_response', 'incomplete_response', 'malformed_json',
]) {
  test(`${reason} remains a coarse extraction_failed provider outcome`, async () => {
    const f = fixture({providerError: new GeminiStagingProviderError(
      'PROVIDER_EXECUTION_FAILED', reason, 'private provider detail',
    )});
    assert.equal((await f.run()).failureCode, 'extraction_failed');
  });
}

test('provider-validated invalid V3 response maps to invalid_extraction_result', async () => {
  const f = fixture({providerError: new GeminiStagingProviderError(
    'PROVIDER_EXECUTION_FAILED', 'invalid_v3_response', 'private detail',
  )});
  assert.equal((await f.run()).failureCode, 'invalid_extraction_result');
  assert.equal(f.calls.begin, 0);
});

test('trusted normalization rejection maps to invalid_extraction_result', async () => {
  const f = fixture({normalize: () => { throw new Error('private value'); }});
  assert.equal((await f.run()).failureCode, 'invalid_extraction_result');
  assert.equal(f.calls.begin, 0);
});

for (const phase of ['begin', 'children', 'finalize']) {
  test(`${phase} persistence failure is finalized with the supplier code`, async () => {
    const f = fixture({failurePhase: phase});
    assert.equal(
      (await f.run()).failureCode,
      'supplier_extraction_persistence_failed',
    );
    assert.equal(f.calls.inspect, 1);
    assert.equal(
      f.calls.failure[0].failureCode,
      'supplier_extraction_persistence_failed',
    );
  });
}

test('ambiguous finalization error returns success after authoritative proof', async () => {
  const f = fixture({
    failurePhase: 'finalize',
    inspection: 'complete_completed',
  });
  assert.deepEqual(await f.run(), {
    outcome: 'completed', jobId, extractionId: jobId,
  });
  assert.equal(f.calls.failure.length, 0);
});

test('inconsistent persistence is not converted into a failed job', async () => {
  const f = fixture({failurePhase: 'finalize', inspection: 'inconsistent'});
  await assert.rejects(f.run, (error) =>
    error instanceof SupplierExtractionProcessorError &&
    error.code === 'PERSISTENCE_STATE_INCONSISTENT');
  assert.equal(f.calls.failure.length, 0);
});

test('an authoritative inspection failure is handled conservatively', async () => {
  const f = fixture({
    failurePhase: 'finalize',
    inspectionError: new Error('private read failure'),
  });
  await assert.rejects(f.run, (error) =>
    error instanceof SupplierExtractionProcessorError &&
    error.code === 'PERSISTENCE_STATE_INCONSISTENT');
  assert.equal(f.calls.failure.length, 0);
});

test('successful completion wins a failure-finalization race', async () => {
  const f = fixture({
    sourceError: new Error('private source detail'),
    failureResult: {kind: 'completed', extractionId: jobId},
  });
  assert.deepEqual(await f.run(), {
    outcome: 'already_completed', jobId, extractionId: jobId,
  });
});

test('failure-finalization errors are sanitized and keep the coarse code', async () => {
  const f = fixture({
    sourceError: new Error('private source detail'),
    failureFinalizationError: new Error('private Firestore detail'),
  });
  await assert.rejects(f.run, (error) =>
    error instanceof SupplierExtractionProcessorError &&
    error.code === 'FAILURE_FINALIZATION_FAILED' &&
    error.failureCode === 'source_unavailable' &&
    !error.message.includes('private'));
});

test('ordinary same-job duplicate cannot enter a second provider call', async () => {
  let status = 'queued';
  const jobs = {
    async claimSupplierExtractionJob() {
      if (status === 'queued') {
        status = 'processing';
        return {kind: 'claimed', job: claimedJob()};
      }
      return {kind: 'already_processing'};
    },
    async finalizeSupplierExtractionFailure(job, failureCode) {
      status = 'failed';
      return {kind: 'failed', failureCode};
    },
  };
  const f = fixture({jobs});
  const [first, duplicate] = await Promise.all([f.run(), f.run()]);
  assert.equal(first.outcome, 'completed');
  assert.equal(duplicate.outcome, 'already_processing');
  assert.equal(f.calls.provider, 1);
  assert.equal(f.calls.begin, 1);
});

test('separate rerun jobs use distinct stable extraction IDs', async () => {
  const first = fixture();
  await first.run();
  const otherJobId = 'job-v3-rerun';
  const second = fixture({
    claim: {kind: 'claimed', job: claimedJob(otherJobId)},
  });
  const result = await second.run(otherJobId);
  assert.equal(result.extractionId, otherJobId);
  assert.notEqual(result.extractionId, first.calls.records.root.extractionId);
});

test('logs contain lifecycle counts but no extracted semantic or source values', async () => {
  const secret = 'NEVER_LOG_THIS_SEMANTIC_VALUE';
  const f = fixture({providerResult: providerPayload(secret)});
  await f.run();
  const serialized = JSON.stringify(f.logs);
  assert.equal(serialized.includes(secret), false);
  assert.equal(serialized.includes('Private Hotel Name'), false);
  assert.equal(serialized.includes('private-source.pdf'), false);
  assert.equal(serialized.includes('/private/source.pdf'), false);
  const normalized = f.logs.find((entry) =>
    entry.event === 'supplier-extraction-v3-result-normalized');
  assert.equal(normalized.days, 1);
  assert.equal(normalized.assignedServices, 1);
});

test('new processor is isolated from production routing and canonical draft APIs', () => {
  const sourceRoot = path.resolve(__dirname, '../src');
  const productionFiles = [
    'index.ts',
    'itineraryExtraction/trigger.ts',
    'itineraryExtraction/processor.ts',
    'itineraryExtraction/processorAdmin.ts',
    'itineraryExtraction/request.ts',
  ];
  for (const relative of productionFiles) {
    const source = fs.readFileSync(path.join(sourceRoot, relative), 'utf8');
    assert.equal(source.includes('supplierExtractionProcessor'), false, relative);
    assert.equal(source.includes('supplierExtractionProcessorAdmin'), false, relative);
  }
  const processorSource = fs.readFileSync(
    path.join(sourceRoot, 'itineraryExtraction/supplierExtractionProcessor.ts'),
    'utf8',
  );
  assert.equal(processorSource.includes('draftWriter'), false);
  assert.equal(processorSource.includes('writeDraft'), false);
  assert.equal(processorSource.includes('resultingDraftId'), false);
});
