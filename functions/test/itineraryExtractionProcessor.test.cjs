const {test} = require('node:test');
const assert = require('node:assert/strict');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {
  ItineraryExtractionProviderError,
  ItineraryExtractionProcessorError,
  processItineraryExtractionJob,
} = require('../lib/itineraryExtraction/processor');
const {
  adminExtractionJobStore,
} = require('../lib/itineraryExtraction/processorAdmin');

const tripId = 'trip-1';
const jobId = 'job-1';
const packageId = 'package-1';
const jobPath = `trips/${tripId}/itinerary_extraction_jobs/${jobId}`;

const processorCode = (expected, failureCode = undefined) => (error) =>
  error instanceof ItineraryExtractionProcessorError &&
  error.code === expected &&
  (failureCode === undefined || error.failureCode === failureCode);

function queuedJob(overrides = {}) {
  return {
    tripId,
    sourcePackageId: packageId,
    status: 'queued',
    requestedByUid: 'agent-1',
    resultingDraftId: null,
    failureCode: null,
    createdAt: Timestamp.fromMillis(1000),
    updatedAt: Timestamp.fromMillis(1000),
    ...overrides,
  };
}

function file(id, extension = 'pdf', contentType = 'application/pdf') {
  return {
    tripId,
    packageId,
    originalFileName: `Source ${id}.${extension}`,
    storagePath: `trips/${tripId}/supplier_sources/${id}/source.${extension}`,
    contentType,
    sizeBytes: 100,
    uploadedByUid: 'agent-1',
  };
}

function sourceFixture() {
  const files = new Map([
    ['file-2', file('file-2', 'txt', 'text/plain')],
    ['file-1', file('file-1')],
  ]);
  const sourcePackage = {
    tripId,
    supplierId: 'supplier-1',
    supplierNameSnapshot: 'Example Supplier',
    fileIds: ['file-2', 'file-1'],
    uploadedByUid: 'agent-1',
    status: 'uploaded',
  };
  return {
    sourcePackage,
    files,
    dependencies: {
      async readPackage(actualTripId, actualPackageId) {
        assert.equal(actualTripId, tripId);
        assert.equal(actualPackageId, packageId);
        return sourcePackage;
      },
      async readFiles(actualTripId, ids) {
        assert.equal(actualTripId, tripId);
        return ids.map((id) => files.get(id) ?? null);
      },
      async inspectObject(storagePath) {
        const sourceFile = [...files.values()].find(
          (value) => value.storagePath === storagePath,
        );
        if (!sourceFile) return null;
        return {
          name: sourceFile.storagePath,
          contentType: sourceFile.contentType,
          size: String(sourceFile.sizeBytes),
          metadata: {packageId, uploadedByUid: sourceFile.uploadedByUid},
        };
      },
    },
  };
}

function providerPayload(fileIndex = 1) {
  return {
    title: ' Trusted itinerary ',
    days: [{
      date: '2027-02-03',
      title: ' Arrival ',
      services: [{
        type: 'other',
        title: ' Welcome ',
        source: {
          fileIndex,
          sourceLabel: ' Page 1 ',
        },
      }],
    }],
  };
}

function adminFixture(job = queuedJob()) {
  const records = new Map([
    [`trips/${tripId}`, {ownerUid: 'agent-1'}],
    [jobPath, job],
  ]);
  const state = {
    records,
    creates: [],
    updates: [],
    transactionCount: 0,
    failTransactions: new Set(),
    nextId: 1,
  };

  const reference = (path) => ({
    path,
    id: path.split('/').at(-1),
    collection(name) {
      return {
        doc(id = `generated-${state.nextId++}`) {
          return reference(`${path}/${name}/${id}`);
        },
      };
    },
  });
  const snapshot = (ref) => ({
    exists: records.has(ref.path),
    data: () => records.has(ref.path) ? {...records.get(ref.path)} : undefined,
  });
  const persisted = (data) => Object.fromEntries(
    Object.entries(data).map(([key, value]) => [
      key,
      value && typeof value.isEqual === 'function' &&
        value.isEqual(FieldValue.serverTimestamp()) ? Timestamp.now() : value,
    ]),
  );

  let queue = Promise.resolve();
  const db = {
    doc: reference,
    runTransaction(callback) {
      const operation = queue.then(async () => {
        state.transactionCount += 1;
        const transactionNumber = state.transactionCount;
        const writes = [];
        const transaction = {
          get: async (ref) => snapshot(ref),
          getAll: async (...refs) => refs.map(snapshot),
          create(ref, data) {
            writes.push({kind: 'create', ref, data});
          },
          update(ref, data) {
            writes.push({kind: 'update', ref, data});
          },
        };
        const result = await callback(transaction);
        if (state.failTransactions.has(transactionNumber)) {
          throw new Error('SECRET FIRESTORE COMMIT FAILURE');
        }
        for (const write of writes) {
          if (write.kind === 'create') {
            if (records.has(write.ref.path)) throw new Error('already exists');
            records.set(write.ref.path, persisted(write.data));
            state.creates.push({
              path: write.ref.path,
              data: {...write.data},
              transactionNumber,
            });
          } else {
            if (!records.has(write.ref.path)) throw new Error('missing document');
            records.set(write.ref.path, {
              ...records.get(write.ref.path),
              ...persisted(write.data),
            });
            state.updates.push({
              path: write.ref.path,
              data: {...write.data},
              transactionNumber,
            });
          }
        }
        return result;
      });
      queue = operation.catch(() => {});
      return operation;
    },
  };
  state.jobs = adminExtractionJobStore(db);
  return state;
}

function processorFixture(options = {}) {
  const admin = adminFixture(options.job);
  const source = sourceFixture();
  const providerCalls = [];
  const logs = [];
  const provider = options.provider ?? {
    async extract(input) {
      providerCalls.push(input);
      return providerPayload();
    },
  };
  const run = () => processItineraryExtractionJob(
    {tripId, jobId},
    {jobs: admin.jobs, sources: source.dependencies, provider},
    (event, fields) => logs.push({event, ...fields}),
  );
  return {admin, source, provider, providerCalls, logs, run};
}

test('queued job is claimed and valid output completes atomically', async () => {
  const f = processorFixture();
  const result = await f.run();

  assert.deepEqual(result, {
    jobId,
    draftId: 'generated-1',
    status: 'completed',
  });
  assert.equal(f.providerCalls.length, 1);
  assert.deepEqual(
    f.providerCalls[0].sourcePackage.files.map((value) => value.sourceFileId),
    ['file-2', 'file-1'],
  );
  const draft = f.admin.creates[0];
  const completedUpdate = f.admin.updates.at(-1);
  assert.equal(draft.path, `trips/${tripId}/itinerary_drafts/generated-1`);
  assert.equal(draft.transactionNumber, completedUpdate.transactionNumber);
  assert.equal(draft.data.tripId, tripId);
  assert.equal(draft.data.createdByUid, 'agent-1');
  assert.deepEqual(draft.data.sourcePackageIds, [packageId]);
  assert.ok(draft.data.createdAt.isEqual(FieldValue.serverTimestamp()));
  assert.ok(draft.data.updatedAt.isEqual(FieldValue.serverTimestamp()));
  assert.deepEqual(completedUpdate.data, {
    status: 'completed',
    resultingDraftId: 'generated-1',
    failureCode: null,
    updatedAt: FieldValue.serverTimestamp(),
  });
});

test('successful processing logs monotonic phase and total durations', async () => {
  const f = processorFixture();
  await f.run();

  const expectedTimings = [
    ['itinerary-extraction-job-claimed', 'jobClaimDurationMs'],
    ['itinerary-extraction-source-validated', 'sourceValidationDurationMs'],
    ['itinerary-extraction-provider-phase-completed', 'providerDurationMs'],
    ['itinerary-extraction-draft-validated', 'draftValidationDurationMs'],
    ['itinerary-extraction-processing-completed',
      'draftFinalizationDurationMs'],
    ['itinerary-extraction-processing-completed', 'totalProcessingDurationMs'],
  ];
  for (const [event, field] of expectedTimings) {
    const entry = f.logs.find((log) => log.event === event);
    assert.ok(entry, `missing ${event}`);
    assert.equal(Number.isInteger(entry[field]), true, `${event}.${field}`);
    assert.ok(entry[field] >= 0, `${event}.${field}`);
  }
});

test('malformed queued job is rejected before processing side effects', async () => {
  const missingRequester = queuedJob();
  delete missingRequester.requestedByUid;
  for (const malformed of [
    missingRequester,
    queuedJob({tripId: 'trip-2'}),
    queuedJob({sourcePackageId: ''}),
    queuedJob({requestedByUid: ''}),
    queuedJob({resultingDraftId: 'provider-draft'}),
    queuedJob({failureCode: 'extraction_failed'}),
    queuedJob({createdAt: 'not-a-timestamp'}),
    {...queuedJob(), provider: 'not-allowed'},
  ]) {
    const f = processorFixture({job: malformed});
    await assert.rejects(f.run(), processorCode('JOB_NOT_PROCESSABLE'));
    assert.equal(f.providerCalls.length, 0);
    assert.equal(f.admin.creates.length, 0);
    assert.equal(f.admin.updates.length, 0);
  }
});

test('missing job is unavailable and causes no processing side effects', async () => {
  const f = processorFixture();
  f.admin.records.delete(jobPath);
  await assert.rejects(f.run(), processorCode('JOB_UNAVAILABLE'));
  assert.equal(f.providerCalls.length, 0);
  assert.equal(f.admin.creates.length, 0);
  assert.equal(f.admin.updates.length, 0);
});

for (const status of ['processing', 'completed', 'failed']) {
  test(`${status} job cannot be reclaimed`, async () => {
    const outcome = status === 'completed' ? {
      resultingDraftId: 'draft-1',
    } : status === 'failed' ? {
      failureCode: 'extraction_failed',
    } : {};
    const f = processorFixture({job: queuedJob({status, ...outcome})});
    await assert.rejects(f.run(), processorCode('JOB_NOT_PROCESSABLE'));
    assert.equal(f.providerCalls.length, 0);
    assert.equal(f.admin.creates.length, 0);
  });
}

test('concurrent processing claims a queued job only once', async () => {
  const f = processorFixture();
  const results = await Promise.allSettled([f.run(), f.run()]);
  assert.equal(results.filter((value) => value.status === 'fulfilled').length, 1);
  const rejection = results.find((value) => value.status === 'rejected');
  assert.equal(processorCode('JOB_NOT_PROCESSABLE')(rejection.reason), true);
  assert.equal(f.providerCalls.length, 1);
  assert.equal(f.admin.creates.length, 1);
});

for (const scenario of [
  {
    name: 'unavailable source',
    failureCode: 'source_unavailable',
    mutate(f) {f.source.sourcePackage.status = 'uploaded'; f.source.dependencies.readPackage = async () => null;},
  },
  {
    name: 'unsupported source',
    failureCode: 'unsupported_source',
    mutate(f) {f.source.files.get('file-1').contentType = 'application/zip';},
  },
  {
    name: 'source integrity failure',
    failureCode: 'source_unavailable',
    mutate(f) {f.source.sourcePackage.tripId = 'trip-2';},
  },
]) {
  test(`${scenario.name} maps to ${scenario.failureCode}`, async () => {
    const f = processorFixture();
    scenario.mutate(f);
    await assert.rejects(
      f.run(),
      processorCode('SOURCE_FAILURE', scenario.failureCode),
    );
    assert.equal(f.providerCalls.length, 0);
    assert.equal(f.admin.creates.length, 0);
    assert.equal(f.admin.records.get(jobPath).status, 'failed');
    assert.equal(f.admin.records.get(jobPath).failureCode, scenario.failureCode);
  });
}

test('provider failure is sanitized and becomes extraction_failed', async () => {
  const providerCalls = [];
  const f = processorFixture({
    provider: {
      async extract(input) {
        providerCalls.push(input);
        throw new Error('SECRET PROVIDER DETAIL');
      },
    },
  });
  await assert.rejects(
    f.run(),
    (error) => processorCode(
      'EXTRACTION_PROVIDER_FAILED',
      'extraction_failed',
    )(error) && !error.message.includes('SECRET'),
  );
  assert.equal(providerCalls.length, 1);
  assert.equal(f.admin.records.get(jobPath).failureCode, 'extraction_failed');
  assert.equal(JSON.stringify(f.admin.records.get(jobPath)).includes('SECRET'), false);
  assert.equal(JSON.stringify(f.logs).includes('SECRET'), false);
  const phaseFailure = f.logs.find((log) =>
    log.event === 'itinerary-extraction-provider-phase-failed');
  assert.equal(phaseFailure.category, 'unknown');
  assert.equal(Number.isInteger(phaseFailure.providerDurationMs), true);
  assert.ok(phaseFailure.providerDurationMs >= 0);
  const processingFailure = f.logs.find((log) =>
    log.event === 'itinerary-extraction-processing-failed');
  assert.equal(Number.isInteger(processingFailure.totalProcessingDurationMs), true);
  assert.ok(processingFailure.totalProcessingDurationMs >= 0);
});

test('typed provider unsupported source becomes unsupported_source', async () => {
  const f = processorFixture({
    provider: {
      async extract() {
        throw new ItineraryExtractionProviderError(
          'UNSUPPORTED_SOURCE',
          'Office input is unsupported.',
        );
      },
    },
  });
  await assert.rejects(
    f.run(),
    processorCode('SOURCE_FAILURE', 'unsupported_source'),
  );
  assert.equal(f.admin.creates.length, 0);
  assert.equal(f.admin.records.get(jobPath).status, 'failed');
  assert.equal(f.admin.records.get(jobPath).failureCode, 'unsupported_source');
});

for (const [name, payload] of [
  ['malformed output', {title: '', days: [], reviewIssues: []}],
  ['invalid provenance', providerPayload(3)],
]) {
  test(`${name} becomes invalid_extraction_result without a draft`, async () => {
    const f = processorFixture({provider: {extract: async () => payload}});
    await assert.rejects(
      f.run(),
      processorCode('INVALID_EXTRACTION_RESULT', 'invalid_extraction_result'),
    );
    assert.equal(f.admin.creates.length, 0);
    assert.equal(f.admin.records.get(jobPath).status, 'failed');
    assert.equal(
      f.admin.records.get(jobPath).failureCode,
      'invalid_extraction_result',
    );
  });
}

test('failed atomic completion creates no orphan and records persistence failure', async () => {
  const f = processorFixture();
  f.admin.failTransactions.add(2);
  await assert.rejects(
    f.run(),
    processorCode('DRAFT_PERSISTENCE_FAILED', 'draft_persistence_failed'),
  );
  assert.equal(f.admin.creates.length, 0);
  assert.equal(
    [...f.admin.records.keys()].some((path) =>
      path.includes('/itinerary_drafts/')),
    false,
  );
  assert.equal(f.admin.records.get(jobPath).status, 'failed');
  assert.equal(
    f.admin.records.get(jobPath).failureCode,
    'draft_persistence_failed',
  );
  assert.equal(f.providerCalls.length, 1);
});

test('failure-finalization failure is surfaced and job remains processing', async () => {
  const f = processorFixture({
    provider: {extract: async () => {throw new Error('provider down');}},
  });
  f.admin.failTransactions.add(2);
  await assert.rejects(
    f.run(),
    processorCode('JOB_FAILURE_FINALIZATION_FAILED', 'extraction_failed'),
  );
  assert.equal(f.admin.records.get(jobPath).status, 'processing');
  assert.equal(f.admin.records.get(jobPath).failureCode, null);
  assert.equal(f.logs.at(-1).event, 'itinerary-extraction-failure-finalization-failed');
});

for (const status of ['completed', 'failed']) {
  test(`mark-failed never overwrites a ${status} job`, async () => {
    const f = adminFixture(queuedJob({
      status,
      resultingDraftId: status === 'completed' ? 'draft-1' : null,
      failureCode: status === 'failed' ? 'source_unavailable' : null,
    }));
    const claimed = {
      tripId,
      jobId,
      sourcePackageId: packageId,
      requestedByUid: 'agent-1',
    };
    await assert.rejects(
      f.jobs.markJobFailed(claimed, 'extraction_failed'),
      processorCode('JOB_NOT_PROCESSABLE'),
    );
    assert.equal(f.records.get(jobPath).status, status);
  });
}
