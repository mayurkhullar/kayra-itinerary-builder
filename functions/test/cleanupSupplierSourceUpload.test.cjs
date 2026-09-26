const {test} = require('node:test');
const assert = require('node:assert/strict');
const {HttpsError} = require('firebase-functions/v2/https');
const {parseInput, requireAuth, requireContext, requireObject, storagePath} =
  require('../lib/supplierSources/cleanupValidation');
const {cleanupUpload} = require('../lib/supplierSources/cleanup');
const {adminCleanupDependencies} = require('../lib/supplierSources/cleanupAdmin');

const input = {tripId: 'trip-1', packageId: 'package-1', sourceFileId: 'file-1', fileName: 'quote.pdf'};
const auth = {uid: 'agent-1', token: {email: 'Agent-1@kholidaymaps.com'}};
const packagePath = 'trips/trip-1/supplier_source_packages/package-1';
const filePath = 'trips/trip-1/supplier_source_files/file-1';
const path = 'trips/trip-1/supplier_sources/file-1/quote.pdf';
const code = (expected) => (error) => error instanceof HttpsError && error.code === expected;

function context() {
  return {
    profile: {role: 'agent', status: 'active'},
    trip: {ownerUid: 'agent-1'},
    package: {tripId: 'trip-1', status: 'uploading', uploadedByUid: 'agent-1'},
    file: {tripId: 'trip-1', packageId: 'package-1', storagePath: path, uploadedByUid: 'agent-1'},
  };
}
function object() {
  return {generation: '10000000000000001', metageneration: '1',
    metadata: {packageId: 'package-1', uploadedByUid: 'agent-1'}};
}

// In-memory SDK doubles exercise the real Admin adapter without credentials,
// network requests, emulators, or production Firebase.
function fixture() {
  const initial = context();
  const records = new Map([
    ['users/agent-1', initial.profile], ['users/admin-1', {role: 'admin', status: 'active'}],
    ['trips/trip-1', initial.trip], [packagePath, initial.package], [filePath, initial.file],
  ]);
  const events = [];
  const logs = [];
  const state = {records, events, logs, object: object(), beforeTransaction: null,
    beforeDelete: null, readError: null, deleteError: null, metadataError: null};
  const ref = (path) => ({path, collection: (name) => ({doc: (id) => ref(`${path}/${name}/${id}`)})});
  const getAll = async (...refs) => refs.map(({path}) => ({
    data: () => records.has(path) ? {...records.get(path)} : undefined,
  }));
  const db = {
    doc: ref, getAll,
    async runTransaction(callback) {
      if (state.beforeTransaction) {
        const hook = state.beforeTransaction;
        state.beforeTransaction = null;
        hook();
      }
      const writes = [];
      const result = await callback({getAll,
        update: (reference, data) => writes.push(() => {
          records.set(reference.path, {...records.get(reference.path), ...data});
          events.push(`update:${reference.path}`);
        }),
        delete: (reference) => {
          if (state.metadataError) throw state.metadataError;
          writes.push(() => {records.delete(reference.path); events.push(`delete:${reference.path}`);});
        },
      });
      writes.forEach((write) => write());
      return result;
    },
  };
  const bucket = {
    file(actualPath, options) {
      assert.equal(actualPath, path);
      return {
        async getMetadata() {
          if (state.readError) throw state.readError;
          if (!state.object) throw {code: 404};
          return [structuredClone(state.object)];
        },
        async delete() {
          if (state.beforeDelete) state.beforeDelete();
          if (state.deleteError) throw state.deleteError;
          if (!state.object) throw {code: 404};
          assert.equal(records.get(packagePath).status, 'failed');
          if (state.object.generation !== options.preconditionOpts.ifGenerationMatch ||
              state.object.metageneration !== options.preconditionOpts.ifMetagenerationMatch) {
            throw {code: 412};
          }
          events.push('storage:delete');
          state.object = null;
        },
      };
    },
  };
  state.dependencies = adminCleanupDependencies(db, bucket);
  state.run = (request = {auth, data: input}) => cleanupUpload(request, state.dependencies,
    (event, data) => logs.push({event, ...data}));
  return state;
}

for (const fileName of ['', ' ', '\t', '/', 'a/b', 'a\\b', '..', '../a', 'a..pdf', '.', ' a.pdf', 'a.pdf ', 'a\0.pdf']) {
  test(`reject invalid filename ${JSON.stringify(fileName)}`, () => {
    assert.throws(() => parseInput({...input, fileName}), code('invalid-argument'));
  });
}
for (const key of ['tripId', 'packageId', 'sourceFileId']) {
  for (const value of ['', ' ', 'a/b', '..', 12, null]) {
    test(`reject malformed ${key}=${JSON.stringify(value)}`, () => {
      assert.throws(() => parseInput({...input, [key]: value}), code('invalid-argument'));
    });
  }
}
test('requires exactly the identifier contract, never arbitrary paths or roles', () => {
  for (const data of [null, [], {...input, storagePath: path}, {...input, role: 'admin'}, {tripId: 'trip-1'}]) {
    assert.throws(() => parseInput(data), code('invalid-argument'));
  }
});
test('constructs canonical Storage path, preserving filename', () => {
  assert.equal(storagePath(parseInput(input)), path);
  assert.equal(storagePath(parseInput({...input, fileName: 'Quote 01.pdf'})),
    'trips/trip-1/supplier_sources/file-1/Quote 01.pdf');
});
test('unauthenticated caller fails before any reads or writes', async () => {
  const dependencies = new Proxy({}, {get() {assert.fail('No dependency should be used');}});
  await assert.rejects(cleanupUpload({data: input}, dependencies, () => {}), code('unauthenticated'));
});
test('unauthenticated caller is rejected before initializing Admin dependencies', async () => {
  await assert.rejects(cleanupUpload({data: input},
    () => assert.fail('Dependencies must remain uninitialized'), () => {}), code('unauthenticated'));
});
test('Admin initialization failures return only a sanitized internal error', async () => {
  await assert.rejects(cleanupUpload({auth, data: input},
    () => {throw new Error('SECRET CONFIG');}, () => {}),
  (error) => code('internal')(error) && !error.message.includes('SECRET'));
});
test('company email is normalized and rejects suffix attacks or missing email', () => {
  assert.equal(requireAuth({...auth, token: {email: ' AGENT@KHOLIDAYMAPS.COM '}}), 'agent-1');
  for (const email of [undefined, null, 1, '', '@kholidaymaps.com', 'x@other.com', 'x@kholidaymaps.com.attacker.com', 'x@y@kholidaymaps.com']) {
    assert.throws(() => requireAuth({...auth, token: {email}}), code('permission-denied'));
  }
});
for (const status of ['uploaded', 'unknown', null]) {
  test(`reject package status ${status} without mutations`, async () => {
    const f = fixture();
    f.records.get(packagePath).status = status;
    await assert.rejects(f.run(), code('failed-precondition'));
    assert.deepEqual(f.events, []);
    assert.ok(f.object);
  });
}
for (const status of ['uploading', 'failed']) {
  test(`${status} qualifies; Storage is deleted before file metadata`, async () => {
    const f = fixture();
    f.records.get(packagePath).status = status;
    assert.deepEqual(await f.run(), {cleaned: true, storageDeleted: true, metadataDeleted: true});
    assert.equal(f.records.get(packagePath).status, 'failed');
    assert.deepEqual(f.events, [
      ...(status === 'uploading' ? [`update:${packagePath}`] : []),
      'storage:delete', `delete:${filePath}`,
    ]);
    assert.ok(f.records.has('trips/trip-1'));
    assert.equal(f.records.get(packagePath).uploadedByUid, 'agent-1');
  });
}
for (const role of ['agent', 'admin']) {
  for (const corruption of ['object-package', 'object-uploader', 'missing-object-uploader', 'file-package', 'file-trip', 'file-path', 'file-uploader', 'package-trip', 'package-uploader']) {
    test(`${role} cannot bypass ${corruption} conflict`, async () => {
      const f = fixture();
      f.records.get('users/agent-1').role = role;
      if (corruption === 'object-package') f.object.metadata.packageId = 'other';
      if (corruption === 'object-uploader') f.object.metadata.uploadedByUid = 'other';
      if (corruption === 'missing-object-uploader') delete f.object.metadata.uploadedByUid;
      if (corruption === 'file-package') f.records.get(filePath).packageId = 'other';
      if (corruption === 'file-trip') f.records.get(filePath).tripId = 'other';
      if (corruption === 'file-path') f.records.get(filePath).storagePath = 'other';
      if (corruption === 'file-uploader') f.records.get(filePath).uploadedByUid = 'other';
      if (corruption === 'package-trip') f.records.get(packagePath).tripId = 'other';
      if (corruption === 'package-uploader') f.records.get(packagePath).uploadedByUid = '';
      await assert.rejects(f.run(), code('failed-precondition'));
      assert.deepEqual(f.events, []);
      assert.ok(f.object);
    });
  }
}
test('missing Storage object still cleans valid metadata and is repeatable', async () => {
  const f = fixture();
  f.object = null;
  assert.deepEqual(await f.run(), {cleaned: true, storageDeleted: false, metadataDeleted: true});
  assert.deepEqual(await f.run(), {cleaned: true, storageDeleted: false, metadataDeleted: false});
});
test('missing file metadata permits validated orphan-object cleanup', async () => {
  const f = fixture();
  f.records.delete(filePath);
  assert.deepEqual(await f.run(), {cleaned: true, storageDeleted: true, metadataDeleted: false});
});
test('missing object does not excuse conflicting file metadata', async () => {
  const f = fixture();
  f.object = null;
  f.records.get(filePath).packageId = 'other';
  await assert.rejects(f.run(), code('failed-precondition'));
  assert.deepEqual(f.events, []);
});
test('Admin can clean another uploader, without requiring caller UID to match', async () => {
  const f = fixture();
  assert.equal((await f.run({auth: {uid: 'admin-1', token: {email: 'admin@kholidaymaps.com'}}, data: input})).cleaned, true);
});
test('current Agent owner can clean the original uploader after reassignment', async () => {
  const f = fixture();
  f.records.set('users/agent-2', {role: 'agent', status: 'active'});
  f.records.get('trips/trip-1').ownerUid = 'agent-2';
  await assert.rejects(f.run(), code('permission-denied'));
  assert.equal((await f.run({auth: {uid: 'agent-2', token: {email: 'agent-2@kholidaymaps.com'}}, data: input})).cleaned, true);
});
for (const profile of [null, {role: 'agent', status: 'inactive'}, {role: 'admin', status: 'inactive'}, {role: 'unknown', status: 'active'}]) {
  test(`reject inactive or unknown profile ${JSON.stringify(profile)}`, async () => {
    const f = fixture();
    if (profile) f.records.set('users/agent-1', profile);
    else f.records.delete('users/agent-1');
    await assert.rejects(f.run(), code('permission-denied'));
    assert.deepEqual(f.events, []);
  });
}
for (const missing of ['trips/trip-1', packagePath]) {
  test(`missing required document: ${missing}`, async () => {
    const f = fixture();
    f.records.delete(missing);
    await assert.rejects(f.run(), code('not-found'));
    assert.deepEqual(f.events, []);
  });
}
test('completion that wins before the rollback claim prevents all deletion', async () => {
  const f = fixture();
  f.beforeTransaction = () => {f.records.get(packagePath).status = 'uploaded';};
  await assert.rejects(f.run(), code('failed-precondition'));
  assert.deepEqual(f.events, []);
  assert.ok(f.object);
});
test('ownership change before claim is revalidated', async () => {
  const f = fixture();
  f.beforeTransaction = () => {f.records.get('trips/trip-1').ownerUid = 'other';};
  await assert.rejects(f.run(), code('permission-denied'));
  assert.deepEqual(f.events, []);
});
test('file conflict appearing before claim prevents all deletion', async () => {
  const f = fixture();
  f.beforeTransaction = () => {f.records.get(filePath).packageId = 'other';};
  await assert.rejects(f.run(), code('failed-precondition'));
  assert.deepEqual(f.events, []);
});
for (const field of ['generation', 'metageneration']) {
  test(`changed object ${field} aborts deletion and retains metadata`, async () => {
    const f = fixture();
    f.beforeDelete = () => {f.object[field] = '999';};
    await assert.rejects(f.run(), code('failed-precondition'));
    assert.ok(f.object);
    assert.ok(f.records.has(filePath));
    assert.deepEqual(f.events, [`update:${packagePath}`]);
  });
}
test('object removed concurrently remains an idempotent success', async () => {
  const f = fixture();
  f.beforeDelete = () => {f.object = null;};
  assert.deepEqual(await f.run(), {cleaned: true, storageDeleted: false, metadataDeleted: true});
});
test('Storage failure keeps file metadata, sanitizes error and permits retry', async () => {
  const f = fixture();
  f.deleteError = new Error('SECRET SDK MESSAGE');
  await assert.rejects(f.run(), (error) => code('internal')(error) && !error.message.includes('SECRET'));
  assert.ok(f.records.has(filePath));
  assert.ok(f.object);
  assert.equal(f.records.get(packagePath).status, 'failed');
  assert.ok(!JSON.stringify(f.logs).includes('SECRET'));
  f.deleteError = null;
  assert.equal((await f.run()).cleaned, true);
});
test('metadata failure after Storage deletion can be safely retried', async () => {
  const f = fixture();
  f.metadataError = new Error('internal Firestore failure');
  await assert.rejects(f.run(), code('internal'));
  assert.equal(f.object, null);
  assert.ok(f.records.has(filePath));
  f.metadataError = null;
  assert.deepEqual(await f.run(), {cleaned: true, storageDeleted: false, metadataDeleted: true});
});
test('Storage read failure is not treated as missing and causes no mutation', async () => {
  const f = fixture();
  f.readError = {code: 403};
  await assert.rejects(f.run(), code('internal'));
  assert.deepEqual(f.events, []);
});
test('pure identity validation does not bypass package state for Admin', () => {
  const c = context();
  c.profile.role = 'admin';
  c.package.status = 'uploaded';
  assert.throws(() => requireContext(c, auth.uid, input), code('failed-precondition'));
  assert.throws(() => requireObject({...object(), generation: ''}, input, 'agent-1'), code('failed-precondition'));
});
