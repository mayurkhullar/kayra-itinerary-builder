const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  adminGeminiItineraryExtractionProvider,
} = require('../lib/itineraryExtraction/geminiProviderAdmin');
const {
  ItineraryExtractionProcessorError,
} = require('../lib/itineraryExtraction/processor');
const {
  adminExtractionJobStore,
} = require('../lib/itineraryExtraction/processorAdmin');
const {
  adminSupplierSourceReaderDependencies,
} = require('../lib/itineraryExtraction/sourceReaderAdmin');
const {
  adminItineraryExtractionProcessorDependencies,
  createItineraryExtractionCreateHandler,
  itineraryExtractionTriggerFunctionName,
  itineraryExtractionTriggerOptions,
  itineraryExtractionTriggerPath,
  processItineraryExtractionJob,
  productionItineraryExtractionAdapters,
} = require('../lib/itineraryExtraction/trigger');

const dependencies = Object.freeze({
  jobs: Object.freeze({}),
  sources: Object.freeze({}),
  provider: Object.freeze({}),
});

function triggerFixture(router) {
  const calls = [];
  const logs = [];
  let dependencyCalls = 0;
  const handler = createItineraryExtractionCreateHandler({
    createDependencies() {
      dependencyCalls += 1;
      return dependencies;
    },
    async router(input, actualDependencies, log) {
      calls.push({input, dependencies: actualDependencies, log});
      return router(input, actualDependencies, log);
    },
    log: (level, event, fields) => logs.push({level, event, ...fields}),
  });
  return {
    calls,
    handler,
    logs,
    dependencyCalls: () => dependencyCalls,
  };
}

const validEvent = (overrides = {}) => ({
  id: 'event-1',
  params: {tripId: 'trip-1', jobId: 'job-1'},
  ...overrides,
});

test('valid path identities invoke the processor exactly once', async () => {
  const f = triggerFixture(async () => ({
    outcome: 'completed',
    route: 'itinerary_draft_v1',
    extractionContractVersion: 'itinerary_draft_v1',
  }));
  await f.handler(validEvent());
  assert.equal(f.calls.length, 1);
  assert.equal(f.dependencyCalls(), 1);
  assert.deepEqual(f.calls[0].input, {tripId: 'trip-1', jobId: 'job-1'});
  assert.equal(f.calls[0].dependencies, dependencies);
  assert.equal(f.logs.at(-1).outcome, 'completed');
});

test('event snapshot fields are never used as authoritative job input', async () => {
  const f = triggerFixture(async () => ({
    outcome: 'completed',
    route: 'itinerary_draft_v1',
    extractionContractVersion: 'itinerary_draft_v1',
  }));
  await f.handler(validEvent({
    data: {
      tripId: 'snapshot-trip',
      jobId: 'snapshot-job',
      sourcePackageId: 'untrusted-package',
      requestedByUid: 'untrusted-user',
      status: 'completed',
      resultingDraftId: 'untrusted-draft',
      failureCode: 'extraction_failed',
    },
  }));
  assert.deepEqual(f.calls[0].input, {tripId: 'trip-1', jobId: 'job-1'});
  assert.deepEqual(Object.keys(f.calls[0].input), ['tripId', 'jobId']);
});

for (const [name, params] of [
  ['missing tripId', {jobId: 'job-1'}],
  ['empty tripId', {tripId: '', jobId: 'job-1'}],
  ['malformed tripId', {tripId: 'trip/1', jobId: 'job-1'}],
  ['missing jobId', {tripId: 'trip-1'}],
  ['empty jobId', {tripId: 'trip-1', jobId: ''}],
  ['malformed jobId', {tripId: 'trip-1', jobId: '..'}],
]) {
  test(`${name} fails before processor creation or invocation`, async () => {
    const f = triggerFixture(async () => {
      throw new Error('processor must not run');
    });
    await assert.rejects(f.handler(validEvent({params})), /identity is invalid/);
    assert.equal(f.dependencyCalls(), 0);
    assert.equal(f.calls.length, 0);
    assert.equal(f.logs.at(-1).outcome, 'infrastructure-error');
  });
}

test('missing event fails safely before processor creation', async () => {
  const f = triggerFixture(async () => {
    throw new Error('processor must not run');
  });
  await assert.rejects(f.handler(), /identity is invalid/);
  assert.equal(f.dependencyCalls(), 0);
  assert.equal(f.calls.length, 0);
  assert.equal(f.logs.at(-1).outcome, 'infrastructure-error');
});

for (const outcome of [
  'completed',
  'already_completed',
  'already_processing',
  'no_op',
]) {
  test(`${outcome} router outcome is handled successfully`, async () => {
    const f = triggerFixture(async () => ({
      outcome,
      route: 'supplier_extraction_v1',
      extractionContractVersion: 'supplier_extraction_v1',
    }));
    assert.equal(await f.handler(validEvent()), undefined);
    assert.equal(f.calls.length, 1);
    assert.equal(f.logs.at(-1).outcome, outcome);
  });
}

test('terminal business outcome is handled without trigger retry', async () => {
  const f = triggerFixture(async () => ({
    outcome: 'terminal_failure',
    route: 'supplier_extraction_v1',
    extractionContractVersion: 'supplier_extraction_v1',
    failureCode: 'extraction_failed',
  }));
  assert.equal(await f.handler(validEvent()), undefined);
  assert.equal(f.logs.at(-1).outcome, 'terminal_failure');
  assert.equal(f.logs.at(-1).failureCode, 'extraction_failed');
});

test('deterministic routing failure is logged and handled without retry', async () => {
  const f = triggerFixture(async () => ({
    outcome: 'non_retryable',
    route: null,
    extractionContractVersion: null,
    reason: 'invalid_job_contract',
  }));
  assert.equal(await f.handler(validEvent()), undefined);
  assert.equal(f.logs.at(-1).level, 'error');
  assert.equal(f.logs.at(-1).outcome, 'non_retryable');
  assert.equal(f.logs.at(-1).reason, 'invalid_job_contract');
});

test('failure-finalization infrastructure error is rethrown', async () => {
  const failure = new ItineraryExtractionProcessorError(
    'JOB_FAILURE_FINALIZATION_FAILED',
    'Failure state could not be persisted.',
    'extraction_failed',
  );
  const f = triggerFixture(async () => {throw failure;});
  await assert.rejects(f.handler(validEvent()), (error) => error === failure);
  assert.equal(f.logs.at(-1).outcome, 'infrastructure-error');
  assert.equal(
    f.logs.at(-1).errorCategory,
    'JOB_FAILURE_FINALIZATION_FAILED',
  );
});

test('unexpected pre-finalization infrastructure error is rethrown', async () => {
  const failure = new Error('transient Firestore failure');
  const f = triggerFixture(async () => {throw failure;});
  await assert.rejects(f.handler(validEvent()), (error) => error === failure);
  assert.equal(f.logs.at(-1).outcome, 'infrastructure-error');
  assert.equal(JSON.stringify(f.logs).includes(failure.message), false);
});

test('production dependency factory composes only the existing adapters', () => {
  assert.equal(productionItineraryExtractionAdapters.jobs, adminExtractionJobStore);
  assert.equal(
    productionItineraryExtractionAdapters.sources,
    adminSupplierSourceReaderDependencies,
  );
  assert.equal(
    productionItineraryExtractionAdapters.provider,
    adminGeminiItineraryExtractionProvider,
  );

  const db = {};
  const bucket = {};
  const providerLog = () => {};
  const calls = [];
  const composed = adminItineraryExtractionProcessorDependencies(
    db,
    bucket,
    providerLog,
    {
      jobs(actualDb) {
        calls.push(['jobs', actualDb]);
        return 'jobs';
      },
      sources(actualDb, actualBucket) {
        calls.push(['sources', actualDb, actualBucket]);
        return 'sources';
      },
      provider(actualBucket, options) {
        calls.push(['provider', actualBucket, options.log]);
        return 'provider';
      },
    },
  );
  assert.deepEqual(composed, {
    jobs: 'jobs',
    sources: 'sources',
    provider: 'provider',
  });
  assert.deepEqual(calls, [
    ['jobs', db],
    ['sources', db, bucket],
    ['provider', bucket, providerLog],
  ]);
});

test('Firestore create trigger has the exact production configuration', () => {
  assert.equal(
    itineraryExtractionTriggerPath,
    'trips/{tripId}/itinerary_extraction_jobs/{jobId}',
  );
  assert.equal(
    itineraryExtractionTriggerFunctionName,
    'processItineraryExtractionJob',
  );
  assert.deepEqual(itineraryExtractionTriggerOptions, {
    document: 'trips/{tripId}/itinerary_extraction_jobs/{jobId}',
    region: 'asia-south2',
    minInstances: 0,
    maxInstances: 2,
    concurrency: 1,
    timeoutSeconds: 540,
    memory: '1GiB',
    retry: true,
    serviceAccount: '121704138111-compute@developer.gserviceaccount.com',
  });
  const endpoint = processItineraryExtractionJob.__endpoint;
  assert.equal(endpoint.platform, 'gcfv2');
  assert.deepEqual(endpoint.region, ['asia-south2']);
  assert.equal(endpoint.availableMemoryMb, 1024);
  assert.equal(endpoint.timeoutSeconds, 540);
  assert.equal(endpoint.minInstances, 0);
  assert.equal(endpoint.maxInstances, 2);
  assert.equal(endpoint.concurrency, 1);
  assert.equal(
    endpoint.serviceAccountEmail,
    '121704138111-compute@developer.gserviceaccount.com',
  );
  assert.equal(
    endpoint.eventTrigger.eventType,
    'google.cloud.firestore.document.v1.created',
  );
  assert.equal(
    endpoint.eventTrigger.eventFilterPathPatterns.document,
    itineraryExtractionTriggerPath,
  );
  assert.equal(endpoint.eventTrigger.retry, true);
});

test('Functions entrypoint preserves callables and exports the trigger', () => {
  const entrypoint = require('../lib/index');
  assert.equal(typeof entrypoint.cleanupSupplierSourceUpload, 'function');
  assert.equal(typeof entrypoint.requestItineraryExtraction, 'function');
  assert.equal(
    entrypoint.processItineraryExtractionJob,
    processItineraryExtractionJob,
  );
});

test('repository defines only one extraction Firestore trigger identity', () => {
  const sourceRoot = path.resolve(__dirname, '../src');
  const files = fs.readdirSync(path.join(sourceRoot, 'itineraryExtraction'))
    .filter((name) => name.endsWith('.ts'))
    .map((name) => fs.readFileSync(
      path.join(sourceRoot, 'itineraryExtraction', name),
      'utf8',
    ));
  const declarations = files.reduce((count, source) =>
    count + (source.match(/onDocumentCreated\s*\(/g) ?? []).length, 0);
  assert.equal(declarations, 1);
});
