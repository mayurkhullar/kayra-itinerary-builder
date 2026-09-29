const {test} = require('node:test');
const assert = require('node:assert/strict');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {HttpsError} = require('firebase-functions/v2/https');
const {
  parseExtractionRequestInput,
  requireExtractionAuth,
  requireExtractionContext,
} = require('../lib/itineraryExtraction/requestValidation');
const {requestExtraction} = require('../lib/itineraryExtraction/request');
const {
  adminExtractionRequestDependencies,
  currentProductionExtractionContractVersion,
} = require('../lib/itineraryExtraction/requestAdmin');
const {
  itineraryDraftExtractionContractVersion,
  supplierExtractionContractVersion,
} = require('../lib/itineraryExtraction/extractionJob');

const input = {tripId: 'trip-1', sourcePackageId: 'package-1'};
const auth = {uid: 'agent-1', token: {email: 'Agent-1@kholidaymaps.com'}};
const packagePath = 'trips/trip-1/supplier_source_packages/package-1';
const jobsPath = 'trips/trip-1/itinerary_extraction_jobs';
const code = (expected) => (error) =>
  error instanceof HttpsError && error.code === expected;

function context() {
  return {
    profile: {role: 'agent', status: 'active'},
    trip: {ownerUid: 'agent-1', createdByUid: 'someone-else'},
    sourcePackage: {
      tripId: 'trip-1',
      status: 'uploaded',
      fileIds: ['file-1'],
    },
  };
}

function fixture(options = undefined) {
  const initial = context();
  const records = new Map([
    ['users/agent-1', initial.profile],
    ['users/agent-2', {role: 'agent', status: 'active'}],
    ['users/admin-1', {role: 'admin', status: 'active'}],
    ['trips/trip-1', initial.trip],
    [packagePath, initial.sourcePackage],
  ]);
  const state = {records, creates: [], logs: [], nextId: 0};

  const collection = (path) => ({
    path,
    doc(id) {
      const documentId = id ?? `generated-${++state.nextId}`;
      return reference(`${path}/${documentId}`);
    },
    where(field, operator, value) {
      assert.equal(field, 'sourcePackageId');
      assert.equal(operator, '==');
      return {kind: 'query', path, field, value};
    },
  });
  const reference = (path) => ({
    kind: 'document',
    path,
    id: path.split('/').at(-1),
    collection: (name) => collection(`${path}/${name}`),
  });
  const snapshot = (ref) => ({
    id: ref.id,
    data: () => records.has(ref.path) ? {...records.get(ref.path)} : undefined,
  });
  const querySnapshot = (query) => ({
    docs: [...records.entries()]
      .filter(([path, data]) => path.startsWith(`${query.path}/`) &&
        !path.slice(query.path.length + 1).includes('/') &&
        data[query.field] === query.value)
      .map(([path]) => snapshot(reference(path))),
  });
  const getAll = async (...refs) => refs.map(snapshot);
  const db = {
    doc: reference,
    async runTransaction(callback) {
      const writes = [];
      const result = await callback({
        getAll,
        get: async (target) => querySnapshot(target),
        create(ref, data) {
          writes.push(() => {
            if (records.has(ref.path)) throw new Error('already exists');
            records.set(ref.path, {...data});
            state.creates.push({path: ref.path, data: {...data}});
          });
        },
      });
      writes.forEach((write) => write());
      return result;
    },
  };
  state.dependencies = adminExtractionRequestDependencies(db, options);
  state.run = (request = {auth, data: input}) => requestExtraction(
    request,
    state.dependencies,
    (event, fields) => state.logs.push({event, ...fields}),
  );
  state.addJob = (id, status, contractVersion = null) => {
    const resultType = contractVersion === supplierExtractionContractVersion ?
      'supplier_extraction' : 'itinerary_draft';
    const data = {
      tripId: 'trip-1',
      sourcePackageId: 'package-1',
      status,
      requestedByUid: 'agent-1',
      resultingDraftId:
        status === 'completed' && resultType === 'itinerary_draft' ?
          'draft-1' : null,
      failureCode: status === 'failed' ? 'extraction_failed' : null,
      createdAt: Timestamp.fromMillis(1000),
      updatedAt: Timestamp.fromMillis(1000),
    };
    if (contractVersion !== null) {
      data.extractionContractVersion = contractVersion;
      data.resultType = resultType;
      data.resultingExtractionId =
        status === 'completed' && resultType === 'supplier_extraction' ?
          'extraction-1' : null;
    }
    records.set(`${jobsPath}/${id}`, data);
  };
  return state;
}

test('requires exactly tripId and sourcePackageId', () => {
  assert.deepEqual(parseExtractionRequestInput(input), input);
  for (const data of [
    null,
    [],
    {},
    {tripId: 'trip-1'},
    {sourcePackageId: 'package-1'},
    {...input, uid: 'agent-1'},
    {...input, status: 'queued'},
    {...input, provider: 'example'},
    {...input, extractionContractVersion: supplierExtractionContractVersion},
    {...input, resultType: 'supplier_extraction'},
  ]) {
    assert.throws(() => parseExtractionRequestInput(data), code('invalid-argument'));
  }
});

for (const [field, values] of [
  ['tripId', ['', ' ', ' trip-1', 'trip-1 ', 'a/b', '..', 1, null]],
  ['sourcePackageId', ['', ' ', ' package-1', 'package-1 ', 'a/b', '..', 1, null]],
]) {
  test(`rejects malformed ${field}`, () => {
    for (const value of values) {
      assert.throws(
        () => parseExtractionRequestInput({...input, [field]: value}),
        code('invalid-argument'),
      );
    }
  });
}

test('unauthenticated request is rejected before dependencies initialize', async () => {
  await assert.rejects(
    requestExtraction(
      {data: input},
      () => assert.fail('Dependencies must not initialize'),
      () => {},
    ),
    code('unauthenticated'),
  );
});

test('company email is normalized and suffix attacks are rejected', () => {
  assert.equal(
    requireExtractionAuth({...auth, token: {email: ' AGENT@KHOLIDAYMAPS.COM '}}),
    'agent-1',
  );
  for (const email of [
    undefined,
    null,
    '',
    '@kholidaymaps.com',
    'x@other.com',
    'x@kholidaymaps.com.attacker.com',
    'x@y@kholidaymaps.com',
  ]) {
    assert.throws(
      () => requireExtractionAuth({...auth, token: {email}}),
      code('permission-denied'),
    );
  }
});

test('inactive, missing, and invalid-role profiles are denied', () => {
  for (const profile of [
    null,
    {role: 'agent', status: 'inactive'},
    {role: 'admin', status: 'inactive'},
    {role: 'owner', status: 'active'},
  ]) {
    assert.throws(
      () => requireExtractionContext({...context(), profile}, auth.uid, input),
      code('permission-denied'),
    );
  }
});

test('current owner Agent is allowed and createdByUid is ignored', () => {
  assert.doesNotThrow(() => requireExtractionContext(context(), auth.uid, input));
});

test('non-owner Agent is denied', () => {
  assert.throws(
    () => requireExtractionContext(context(), 'agent-2', input),
    code('permission-denied'),
  );
});

test('active Admin can request another owner’s Trip', () => {
  const value = context();
  value.profile.role = 'admin';
  assert.doesNotThrow(() => requireExtractionContext(value, 'admin-1', input));
});

test('missing Trip and source package return not-found', () => {
  assert.throws(
    () => requireExtractionContext({...context(), trip: null}, auth.uid, input),
    code('not-found'),
  );
  assert.throws(
    () => requireExtractionContext(
      {...context(), sourcePackage: null},
      auth.uid,
      input,
    ),
    code('not-found'),
  );
});

for (const status of ['uploading', 'failed']) {
  test(`${status} source package is not ready`, () => {
    const value = context();
    value.sourcePackage.status = status;
    assert.throws(
      () => requireExtractionContext(value, auth.uid, input),
      code('failed-precondition'),
    );
  });
}

test('cross-Trip source package is rejected', () => {
  const value = context();
  value.sourcePackage.tripId = 'trip-2';
  assert.throws(
    () => requireExtractionContext(value, auth.uid, input),
    code('failed-precondition'),
  );
});

test('uploaded package requires a non-empty fileIds list', () => {
  for (const fileIds of [undefined, null, 'file-1', []]) {
    const value = context();
    value.sourcePackage.fileIds = fileIds;
    assert.throws(
      () => requireExtractionContext(value, auth.uid, input),
      code('failed-precondition'),
    );
  }
});

test('new request writes exactly one provider-independent queued job', async () => {
  const f = fixture();
  assert.deepEqual(await f.run(), {
    jobId: 'generated-1',
    status: 'queued',
    createdNew: true,
  });
  assert.equal(f.creates.length, 1);
  const {data} = f.creates[0];
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
  assert.equal(data.tripId, 'trip-1');
  assert.equal(data.sourcePackageId, 'package-1');
  assert.equal(data.status, 'queued');
  assert.equal(data.requestedByUid, 'agent-1');
  assert.equal(data.resultingDraftId, null);
  assert.equal(data.failureCode, null);
  assert.ok(data.createdAt.isEqual(FieldValue.serverTimestamp()));
  assert.ok(data.updatedAt.isEqual(FieldValue.serverTimestamp()));
  assert.equal('provider' in data, false);
  assert.equal('model' in data, false);
  assert.equal('id' in data, false);
  assert.equal(
    currentProductionExtractionContractVersion,
    itineraryDraftExtractionContractVersion,
  );
});

for (const status of ['queued', 'processing']) {
  test(`existing ${status} job is returned without another create`, async () => {
    const f = fixture();
    f.addJob(`existing-${status}`, status);
    assert.deepEqual(await f.run(), {
      jobId: `existing-${status}`,
      status,
      createdNew: false,
    });
    assert.deepEqual(f.creates, []);
  });
}

for (const status of ['completed', 'failed']) {
  test(`${status} attempt permits a new queued job`, async () => {
    const f = fixture();
    f.addJob(`old-${status}`, status);
    assert.deepEqual(await f.run(), {
      jobId: 'generated-1',
      status: 'queued',
      createdNew: true,
    });
    assert.equal(f.creates.length, 1);
  });
}

test('server-selected Supplier Extraction creation derives versioned metadata',
  async () => {
    const f = fixture({
      extractionContractVersion: supplierExtractionContractVersion,
    });
    const result = await f.run();
    assert.equal(result.createdNew, true);
    const data = f.creates[0].data;
    assert.equal(data.extractionContractVersion, 'supplier_extraction_v1');
    assert.equal(data.resultType, 'supplier_extraction');
    assert.equal(data.resultingDraftId, null);
    assert.equal(data.resultingExtractionId, null);
  });

test('server-selected explicit draft creation derives draft result type',
  async () => {
    const f = fixture({
      extractionContractVersion: itineraryDraftExtractionContractVersion,
      persistVersionedContractMetadata: true,
    });
    await f.run();
    const data = f.creates[0].data;
    assert.equal(data.extractionContractVersion, 'itinerary_draft_v1');
    assert.equal(data.resultType, 'itinerary_draft');
    assert.equal(data.resultingExtractionId, null);
  });

test('legacy active draft job does not deduplicate Supplier Extraction',
  async () => {
    const f = fixture({
      extractionContractVersion: supplierExtractionContractVersion,
    });
    f.addJob('legacy-active', 'queued');
    const result = await f.run();
    assert.equal(result.createdNew, true);
    assert.equal(f.creates.length, 1);
    assert.equal(f.creates[0].data.resultType, 'supplier_extraction');
  });

for (const status of ['queued', 'processing']) {
  test(`same-contract Supplier Extraction ${status} job deduplicates`,
    async () => {
      const f = fixture({
        extractionContractVersion: supplierExtractionContractVersion,
      });
      f.addJob('supplier-active', status, supplierExtractionContractVersion);
      const result = await f.run();
      assert.deepEqual(result, {
        jobId: 'supplier-active',
        status,
        createdNew: false,
      });
      assert.deepEqual(f.creates, []);
    });
}

for (const status of ['completed', 'failed']) {
  test(`terminal Supplier Extraction ${status} job does not deduplicate`,
    async () => {
      const f = fixture({
        extractionContractVersion: supplierExtractionContractVersion,
      });
      f.addJob('supplier-terminal', status, supplierExtractionContractVersion);
      const result = await f.run();
      assert.equal(result.createdNew, true);
      assert.equal(f.creates.length, 1);
    });
}

test('authenticated caller UID is authoritative', async () => {
  const f = fixture();
  f.records.set('users/admin-1', {role: 'admin', status: 'active'});
  await f.run({
    auth: {uid: 'admin-1', token: {email: 'admin@kholidaymaps.com'}},
    data: input,
  });
  assert.equal(f.creates[0].data.requestedByUid, 'admin-1');
});

test('unexpected backend failures are sanitized and logs omit raw messages', async () => {
  const logs = [];
  await assert.rejects(
    requestExtraction(
      {auth, data: input},
      {requestJob: async () => {throw new Error('SECRET SDK MESSAGE');}},
      (event, fields) => logs.push({event, ...fields}),
    ),
    (error) => code('internal')(error) && !error.message.includes('SECRET'),
  );
  assert.equal(JSON.stringify(logs).includes('SECRET'), false);
});
