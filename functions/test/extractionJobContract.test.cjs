const {test} = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');
const {
  completedDraftJobUpdate,
  completedSupplierExtractionJobUpdate,
  failedExtractionJobUpdate,
  itineraryDraftExtractionContractVersion,
  legacyQueuedExtractionJobData,
  parseExtractionJobRecord,
  processingExtractionJobUpdate,
  resultTypeForExtractionContract,
  supplierExtractionContractVersion,
  versionedQueuedExtractionJobData,
} = require('../lib/itineraryExtraction/extractionJob');
const {
  adminExtractionJobStore,
  supplierExtractionCompletionUpdate,
} = require('../lib/itineraryExtraction/processorAdmin');

const invalid = (error) =>
  error instanceof Error &&
  error.message === 'Itinerary extraction job data is invalid.';

function legacy(status = 'queued', overrides = {}) {
  return {
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    status,
    requestedByUid: 'agent-1',
    resultingDraftId: status === 'completed' ? 'draft-1' : null,
    failureCode: status === 'failed' ? 'extraction_failed' : null,
    createdAt: Timestamp.fromMillis(1000),
    updatedAt: Timestamp.fromMillis(2000),
    ...overrides,
  };
}

function versioned(
  contract = itineraryDraftExtractionContractVersion,
  status = 'queued',
  overrides = {},
) {
  const resultType = resultTypeForExtractionContract(contract);
  return {
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    status,
    requestedByUid: 'agent-1',
    resultingDraftId:
      status === 'completed' && resultType === 'itinerary_draft' ?
        'draft-1' : null,
    failureCode: status === 'failed' ? 'extraction_failed' : null,
    createdAt: Timestamp.fromMillis(1000),
    updatedAt: Timestamp.fromMillis(2000),
    extractionContractVersion: contract,
    resultType,
    resultingExtractionId:
      status === 'completed' && resultType === 'supplier_extraction' ?
        'extraction-1' : null,
    ...overrides,
  };
}

function parse(value) {
  return parseExtractionJobRecord(value, {
    isTimestamp: (candidate) => candidate instanceof Timestamp,
  });
}

test('historical queued job infers the draft contract and result type', () => {
  const job = parse(legacy());
  assert.equal(job.persistenceShape, 'legacy');
  assert.equal(job.extractionContractVersion, 'itinerary_draft_v1');
  assert.equal(job.resultType, 'itinerary_draft');
});

test('historical processing job remains readable without new fields', () => {
  const job = parse(legacy('processing'));
  assert.equal(job.status, 'processing');
  assert.equal(job.resultingExtractionId, null);
});

for (const failureCode of [
  'source_unavailable',
  'unsupported_source',
  'extraction_failed',
  'invalid_extraction_result',
  'draft_persistence_failed',
]) {
  test(`historical failed job preserves ${failureCode}`, () => {
    const job = parse(legacy('failed', {failureCode}));
    assert.equal(job.failureCode, failureCode);
    assert.equal(job.resultingDraftId, null);
  });
}

test('historical completed job preserves its resulting draft', () => {
  const job = parse(legacy('completed'));
  assert.equal(job.resultingDraftId, 'draft-1');
  assert.equal(job.resultingExtractionId, null);
});

test('historical completed job requires a valid draft ID', () => {
  assert.throws(
    () => parse(legacy('completed', {resultingDraftId: null})),
    invalid,
  );
});

for (const status of ['queued', 'processing', 'completed', 'failed']) {
  test(`explicit draft ${status} job validates`, () => {
    const job = parse(versioned(
      itineraryDraftExtractionContractVersion,
      status,
    ));
    assert.equal(job.persistenceShape, 'versioned');
    assert.equal(job.resultType, 'itinerary_draft');
  });
}

for (const status of ['queued', 'processing', 'completed']) {
  test(`Supplier Extraction ${status} job validates`, () => {
    const job = parse(versioned(supplierExtractionContractVersion, status));
    assert.equal(job.extractionContractVersion, 'supplier_extraction_v1');
    assert.equal(job.resultType, 'supplier_extraction');
  });
}

test('Supplier Extraction completed job requires only its extraction ID', () => {
  const job = parse(versioned(supplierExtractionContractVersion, 'completed'));
  assert.equal(job.resultingExtractionId, 'extraction-1');
  assert.equal(job.resultingDraftId, null);
  assert.equal(job.failureCode, null);
});

test('Supplier Extraction persistence failure is valid for its contract', () => {
  const job = parse(versioned(supplierExtractionContractVersion, 'failed', {
    failureCode: 'supplier_extraction_persistence_failed',
  }));
  assert.equal(job.failureCode, 'supplier_extraction_persistence_failed');
});

for (const field of [
  'extractionContractVersion',
  'resultType',
  'resultingExtractionId',
]) {
  test(`partial version metadata is rejected when only ${field} is present`, () => {
    assert.throws(() => parse({...legacy(), [field]: field}), invalid);
  });
}

for (const [contract, resultType] of [
  [itineraryDraftExtractionContractVersion, 'supplier_extraction'],
  [supplierExtractionContractVersion, 'itinerary_draft'],
]) {
  test(`contract ${contract} rejects result type ${resultType}`, () => {
    assert.throws(
      () => parse(versioned(contract, 'queued', {resultType})),
      invalid,
    );
  });
}

test('unknown contract and result values are rejected', () => {
  assert.throws(
    () => parse(versioned(itineraryDraftExtractionContractVersion, 'queued', {
      extractionContractVersion: 'unknown_v1',
      resultType: 'unknown_result',
    })),
    invalid,
  );
});

for (const contract of [
  itineraryDraftExtractionContractVersion,
  supplierExtractionContractVersion,
]) {
  test(`${contract} rejects both successful result IDs`, () => {
    assert.throws(
      () => parse(versioned(contract, 'completed', {
        resultingDraftId: 'draft-1',
        resultingExtractionId: 'extraction-1',
      })),
      invalid,
    );
  });
}

test('draft completion rejects only a Supplier Extraction result ID', () => {
  assert.throws(
    () => parse(versioned(itineraryDraftExtractionContractVersion, 'completed', {
      resultingDraftId: null,
      resultingExtractionId: 'extraction-1',
    })),
    invalid,
  );
});

test('Supplier Extraction completion rejects only a draft result ID', () => {
  assert.throws(
    () => parse(versioned(supplierExtractionContractVersion, 'completed', {
      resultingDraftId: 'draft-1',
      resultingExtractionId: null,
    })),
    invalid,
  );
});

for (const status of ['queued', 'processing']) {
  test(`${status} rejects either successful result ID`, () => {
    assert.throws(
      () => parse(versioned(supplierExtractionContractVersion, status, {
        resultingExtractionId: 'extraction-1',
      })),
      invalid,
    );
    assert.throws(
      () => parse(versioned(itineraryDraftExtractionContractVersion, status, {
        resultingDraftId: 'draft-1',
      })),
      invalid,
    );
  });
}

for (const contract of [
  itineraryDraftExtractionContractVersion,
  supplierExtractionContractVersion,
]) {
  test(`${contract} completed job rejects a missing result`, () => {
    assert.throws(
      () => parse(versioned(contract, 'completed', {
        resultingDraftId: null,
        resultingExtractionId: null,
      })),
      invalid,
    );
  });
}

test('failed job rejects either successful result ID', () => {
  assert.throws(
    () => parse(versioned(supplierExtractionContractVersion, 'failed', {
      resultingExtractionId: 'extraction-1',
    })),
    invalid,
  );
  assert.throws(
    () => parse(versioned(itineraryDraftExtractionContractVersion, 'failed', {
      resultingDraftId: 'draft-1',
    })),
    invalid,
  );
});

for (const status of ['queued', 'processing', 'completed']) {
  test(`${status} job rejects a failure code`, () => {
    assert.throws(
      () => parse(versioned(itineraryDraftExtractionContractVersion, status, {
        failureCode: 'extraction_failed',
      })),
      invalid,
    );
  });
}

test('versioned draft job rejects Supplier Extraction persistence failure', () => {
  assert.throws(
    () => parse(versioned(itineraryDraftExtractionContractVersion, 'failed', {
      failureCode: 'supplier_extraction_persistence_failed',
    })),
    invalid,
  );
});

test('versioned Supplier Extraction job rejects draft persistence failure', () => {
  assert.throws(
    () => parse(versioned(supplierExtractionContractVersion, 'failed', {
      failureCode: 'draft_persistence_failed',
    })),
    invalid,
  );
});

test('historical job rejects the new Supplier Extraction persistence failure', () => {
  assert.throws(
    () => parse(legacy('failed', {
      failureCode: 'supplier_extraction_persistence_failed',
    })),
    invalid,
  );
});

test('queued builders derive result type from the server-selected contract', () => {
  const input = {
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    requestedByUid: 'agent-1',
    createdAt: Timestamp.fromMillis(1000),
    updatedAt: Timestamp.fromMillis(1000),
  };
  const draft = versionedQueuedExtractionJobData(
    input,
    itineraryDraftExtractionContractVersion,
  );
  const extraction = versionedQueuedExtractionJobData(
    input,
    supplierExtractionContractVersion,
  );
  assert.equal(draft.resultType, 'itinerary_draft');
  assert.equal(extraction.resultType, 'supplier_extraction');
  assert.equal(draft.resultingExtractionId, null);
  assert.equal(extraction.resultingDraftId, null);
});

test('legacy queued builder keeps the exact historical field set', () => {
  const data = legacyQueuedExtractionJobData({
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    requestedByUid: 'agent-1',
    createdAt: Timestamp.fromMillis(1000),
    updatedAt: Timestamp.fromMillis(1000),
  });
  assert.deepEqual(Object.keys(data).sort(), [
    'createdAt',
    'failureCode',
    'requestedByUid',
    'resultingDraftId',
    'sourcePackageId',
    'status',
    'tripId',
    'updatedAt',
  ]);
});

test('processing update preserves legacy shape', () => {
  const update = processingExtractionJobUpdate(parse(legacy()));
  assert.deepEqual(update, {
    status: 'processing',
    resultingDraftId: null,
    failureCode: null,
  });
});

test('processing update preserves versioned result fields', () => {
  const update = processingExtractionJobUpdate(parse(versioned(
    supplierExtractionContractVersion,
  )));
  assert.deepEqual(update, {
    status: 'processing',
    resultingDraftId: null,
    failureCode: null,
    resultingExtractionId: null,
  });
});

test('failure update preserves contract and clears every result ID', () => {
  const parsed = parse(versioned(
    supplierExtractionContractVersion,
    'processing',
  ));
  const update = failedExtractionJobUpdate(
    parsed,
    'supplier_extraction_persistence_failed',
  );
  assert.deepEqual(update, {
    status: 'failed',
    resultingDraftId: null,
    failureCode: 'supplier_extraction_persistence_failed',
    resultingExtractionId: null,
  });
  assert.equal(parsed.extractionContractVersion, 'supplier_extraction_v1');
});

test('draft completion accepts only the draft contract', () => {
  const draft = parse(versioned(
    itineraryDraftExtractionContractVersion,
    'processing',
  ));
  assert.equal(completedDraftJobUpdate(draft, 'draft-new').resultingDraftId,
    'draft-new');
  const extraction = parse(versioned(
    supplierExtractionContractVersion,
    'processing',
  ));
  assert.throws(
    () => completedDraftJobUpdate(extraction, 'draft-new'),
    invalid,
  );
});

test('Supplier Extraction completion accepts only its explicit contract', () => {
  const extraction = parse(versioned(
    supplierExtractionContractVersion,
    'processing',
  ));
  const update = supplierExtractionCompletionUpdate(
    extraction,
    'extraction-new',
  );
  assert.equal(update.resultingExtractionId, 'extraction-new');
  assert.equal(update.resultingDraftId, null);
  const draft = parse(versioned(
    itineraryDraftExtractionContractVersion,
    'processing',
  ));
  assert.throws(
    () => completedSupplierExtractionJobUpdate(draft, 'extraction-new'),
    invalid,
  );
});

test('Admin claim preserves an explicit Supplier Extraction contract', async () => {
  const path = 'trips/trip-1/itinerary_extraction_jobs/job-1';
  const records = new Map([[path, versioned(supplierExtractionContractVersion)]]);
  const db = fakeJobDatabase(records);
  const claimed = await adminExtractionJobStore(db).claimQueuedJob(
    'trip-1',
    'job-1',
    supplierExtractionContractVersion,
  );
  assert.equal(claimed.extractionContractVersion, 'supplier_extraction_v1');
  assert.equal(claimed.resultType, 'supplier_extraction');
  assert.equal(claimed.persistenceShape, 'versioned');
  const stored = records.get(path);
  assert.equal(stored.status, 'processing');
  assert.equal(stored.extractionContractVersion, 'supplier_extraction_v1');
  assert.equal(stored.resultType, 'supplier_extraction');
});

test('Admin claim does not backfill a historical job', async () => {
  const path = 'trips/trip-1/itinerary_extraction_jobs/job-1';
  const records = new Map([[path, legacy()]]);
  const db = fakeJobDatabase(records);
  const claimed = await adminExtractionJobStore(db).claimQueuedJob(
    'trip-1',
    'job-1',
    itineraryDraftExtractionContractVersion,
  );
  assert.equal(claimed.extractionContractVersion, 'itinerary_draft_v1');
  assert.equal(claimed.persistenceShape, 'legacy');
  assert.equal('extractionContractVersion' in records.get(path), false);
  assert.equal('resultType' in records.get(path), false);
  assert.equal('resultingExtractionId' in records.get(path), false);
});

function fakeJobDatabase(records) {
  const reference = (path) => ({path, id: path.split('/').at(-1)});
  const snapshot = (ref) => ({
    exists: records.has(ref.path),
    data: () => records.get(ref.path),
  });
  return {
    doc: reference,
    async runTransaction(callback) {
      const updates = [];
      const result = await callback({
        get: async (ref) => snapshot(ref),
        getAll: async (...refs) => refs.map(snapshot),
        update(ref, data) {
          updates.push({ref, data});
        },
      });
      for (const {ref, data} of updates) {
        records.set(ref.path, {...records.get(ref.path), ...data});
      }
      return result;
    },
  };
}
