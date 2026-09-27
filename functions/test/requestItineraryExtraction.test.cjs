const {test} = require('node:test');
const assert = require('node:assert/strict');
const {FieldValue} = require('firebase-admin/firestore');
const {HttpsError} = require('firebase-functions/v2/https');
const {
  parseExtractionRequestInput,
  requireExtractionAuth,
  requireExtractionContext,
} = require('../lib/itineraryExtraction/requestValidation');
const {requestExtraction} = require('../lib/itineraryExtraction/request');
const {
  adminExtractionRequestDependencies,
} = require('../lib/itineraryExtraction/requestAdmin');

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

function fixture() {
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
    data: () => records.has(ref.path) ? structuredClone(records.get(ref.path)) : undefined,
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
  state.dependencies = adminExtractionRequestDependencies(db);
  state.run = (request = {auth, data: input}) => requestExtraction(
    request,
    state.dependencies,
    (event, fields) => state.logs.push({event, ...fields}),
  );
  state.addJob = (id, status) => records.set(`${jobsPath}/${id}`, {
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    status,
    requestedByUid: 'agent-1',
    resultingDraftId: status === 'completed' ? 'draft-1' : null,
    failureCode: status === 'failed' ? 'extraction_failed' : null,
  });
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
