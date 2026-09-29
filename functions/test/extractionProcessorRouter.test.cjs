const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  itineraryDraftExtractionContractVersion,
  legacyQueuedExtractionJobData,
  parseExtractionJobRecord,
  supplierExtractionContractVersion,
} = require('../lib/itineraryExtraction/extractionJob');
const {
  routeItineraryExtractionJob,
} = require('../lib/itineraryExtraction/extractionProcessorRouter');
const {
  ItineraryExtractionProcessorError,
} = require('../lib/itineraryExtraction/processor');
const {
  currentProductionExtractionContractVersion,
} = require('../lib/itineraryExtraction/requestAdmin');

const input = {tripId: 'trip-1', jobId: 'job-1'};

function job(contract, persistenceShape = 'versioned') {
  const resultType = contract === supplierExtractionContractVersion ?
    'supplier_extraction' : 'itinerary_draft';
  return Object.freeze({
    persistenceShape,
    tripId: input.tripId,
    sourcePackageId: 'package-1',
    status: 'queued',
    requestedByUid: 'agent-1',
    extractionContractVersion: contract,
    resultType,
    resultingDraftId: null,
    resultingExtractionId: null,
    failureCode: null,
    createdAt: {},
    updatedAt: {},
  });
}

function fixture(options = {}) {
  const calls = {reads: 0, draft: 0, supplier: 0};
  const logs = [];
  const dependencies = {
    jobs: {
      async readAuthoritativeJob(actualTripId, actualJobId) {
        calls.reads += 1;
        assert.equal(actualTripId, input.tripId);
        assert.equal(actualJobId, input.jobId);
        if (options.readError) throw options.readError;
        return options.read ?? {
          kind: 'job',
          job: job(itineraryDraftExtractionContractVersion, 'legacy'),
        };
      },
    },
    async processItineraryDraft(actualInput, log) {
      calls.draft += 1;
      assert.deepEqual(actualInput, input);
      assert.equal(typeof log, 'function');
      if (options.draftError) throw options.draftError;
      return {jobId: input.jobId, draftId: 'draft-1', status: 'completed'};
    },
    async processSupplierExtraction(actualInput, log) {
      calls.supplier += 1;
      assert.deepEqual(actualInput, input);
      assert.equal(typeof log, 'function');
      if (options.supplierError) throw options.supplierError;
      return options.supplierResult ?? {
        outcome: 'completed',
        jobId: input.jobId,
        extractionId: input.jobId,
      };
    },
  };
  const run = () => routeItineraryExtractionJob(
    input,
    dependencies,
    (event, fields) => logs.push({event, ...fields}),
  );
  return {calls, dependencies, logs, run};
}

test('historical legacy job routes only to the V2.4 processor', async () => {
  const f = fixture();
  assert.deepEqual(await f.run(), {
    outcome: 'completed',
    route: 'itinerary_draft_v1',
    extractionContractVersion: 'itinerary_draft_v1',
  });
  assert.equal(f.calls.draft, 1);
  assert.equal(f.calls.supplier, 0);
});

test('explicit itinerary_draft_v1 routes only to V2.4', async () => {
  const f = fixture({read: {
    kind: 'job', job: job(itineraryDraftExtractionContractVersion),
  }});
  assert.equal((await f.run()).route, 'itinerary_draft_v1');
  assert.equal(f.calls.draft, 1);
  assert.equal(f.calls.supplier, 0);
});

test('explicit supplier_extraction_v1 routes only to V3', async () => {
  const f = fixture({read: {
    kind: 'job', job: job(supplierExtractionContractVersion),
  }});
  assert.deepEqual(await f.run(), {
    outcome: 'completed',
    route: 'supplier_extraction_v1',
    extractionContractVersion: 'supplier_extraction_v1',
  });
  assert.equal(f.calls.draft, 0);
  assert.equal(f.calls.supplier, 1);
});

for (const [reason, expectedReason] of [
  ['missing', 'job_missing'],
  ['invalid_contract', 'invalid_job_contract'],
]) {
  test(`${reason} authoritative job is non-retryable with no processor`, async () => {
    const f = fixture({read: {kind: 'not_processable', reason}});
    assert.deepEqual(await f.run(), {
      outcome: 'non_retryable',
      route: null,
      extractionContractVersion: null,
      reason: expectedReason,
    });
    assert.equal(f.calls.draft, 0);
    assert.equal(f.calls.supplier, 0);
  });
}

test('authoritative reader infrastructure failure propagates for retry', async () => {
  const failure = new Error('private transient Firestore failure');
  const f = fixture({readError: failure});
  await assert.rejects(f.run, (error) => error === failure);
  assert.equal(f.calls.draft, 0);
  assert.equal(f.calls.supplier, 0);
});

test('V2 JOB_NOT_PROCESSABLE preserves duplicate-safe no-op semantics', async () => {
  const f = fixture({draftError: new ItineraryExtractionProcessorError(
    'JOB_NOT_PROCESSABLE', 'Already claimed.',
  )});
  assert.equal((await f.run()).outcome, 'no_op');
  assert.equal(f.calls.supplier, 0);
});

test('V2 finalized business failure is handled without retry', async () => {
  const f = fixture({draftError: new ItineraryExtractionProcessorError(
    'EXTRACTION_PROVIDER_FAILED',
    'Provider failed.',
    'extraction_failed',
  )});
  assert.deepEqual(await f.run(), {
    outcome: 'terminal_failure',
    route: 'itinerary_draft_v1',
    extractionContractVersion: 'itinerary_draft_v1',
    failureCode: 'extraction_failed',
  });
});

test('V2 operational failure propagates for trigger retry', async () => {
  const failure = new ItineraryExtractionProcessorError(
    'JOB_FAILURE_FINALIZATION_FAILED',
    'Failure finalization unavailable.',
    'extraction_failed',
  );
  const f = fixture({draftError: failure});
  await assert.rejects(f.run, (error) => error === failure);
});

for (const outcome of [
  'completed', 'already_completed', 'already_processing',
]) {
  test(`V3 ${outcome} is handled successfully`, async () => {
    const result = {outcome, jobId: input.jobId};
    if (outcome !== 'already_processing') result.extractionId = input.jobId;
    const f = fixture({
      read: {kind: 'job', job: job(supplierExtractionContractVersion)},
      supplierResult: result,
    });
    assert.equal((await f.run()).outcome, outcome);
    assert.equal(f.calls.draft, 0);
  });
}

test('V3 terminal failure is handled without trigger retry', async () => {
  const f = fixture({
    read: {kind: 'job', job: job(supplierExtractionContractVersion)},
    supplierResult: {
      outcome: 'terminal_failure',
      jobId: input.jobId,
      failureCode: 'extraction_failed',
    },
  });
  assert.equal((await f.run()).outcome, 'terminal_failure');
});

test('V3 not_applicable is a non-retryable integrity result with no fallback', async () => {
  const f = fixture({
    read: {kind: 'job', job: job(supplierExtractionContractVersion)},
    supplierResult: {outcome: 'not_applicable', jobId: input.jobId},
  });
  assert.deepEqual(await f.run(), {
    outcome: 'non_retryable',
    route: 'supplier_extraction_v1',
    extractionContractVersion: 'supplier_extraction_v1',
    reason: 'selected_processor_not_applicable',
  });
  assert.equal(f.calls.draft, 0);
  assert.equal(f.calls.supplier, 1);
});

test('V3 operational failure propagates without V2 fallback', async () => {
  const failure = new Error('private V3 infrastructure failure');
  const f = fixture({
    read: {kind: 'job', job: job(supplierExtractionContractVersion)},
    supplierError: failure,
  });
  await assert.rejects(f.run, (error) => error === failure);
  assert.equal(f.calls.draft, 0);
  assert.equal(f.calls.supplier, 1);
});

test('ordinary legacy request output continues through the V2.4 route', async () => {
  assert.equal(
    currentProductionExtractionContractVersion,
    itineraryDraftExtractionContractVersion,
  );
  const raw = legacyQueuedExtractionJobData({
    tripId: input.tripId,
    sourcePackageId: 'package-1',
    requestedByUid: 'agent-1',
    createdAt: {},
    updatedAt: {},
  });
  const parsed = parseExtractionJobRecord(raw, {isTimestamp: () => true});
  const f = fixture({read: {kind: 'job', job: parsed}});
  assert.equal((await f.run()).route, 'itinerary_draft_v1');
  assert.equal(f.calls.draft, 1);
  assert.equal(f.calls.supplier, 0);
});

test('router observability contains only path IDs and stable route metadata', async () => {
  const f = fixture({read: {
    kind: 'job', job: job(supplierExtractionContractVersion),
  }});
  await f.run();
  assert.deepEqual(f.logs, [{
    event: 'itinerary-extraction-router-selected',
    tripId: input.tripId,
    jobId: input.jobId,
    extractionContractVersion: 'supplier_extraction_v1',
    selectedProcessorRoute: 'supplier_extraction_v1',
  }]);
});
