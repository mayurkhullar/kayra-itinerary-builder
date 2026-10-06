const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const {serializeSupplierExtractionForPersistence} = require('../lib/itineraryExtraction/supplierExtractionRepository');
const {supplierImportResolutionValueForFirestore: encode} = require('../lib/itineraryExtraction/supplierImportResolutionRepositoryAdmin');
const {supplierImportFinalizationPaths} = require('../lib/itineraryExtraction/supplierImportFinalization');

const request = (extra = {}) => ({tripId: 'trip-1', extractionId: 'extraction-1', commandId: 'finalize-1', expectedRevision: 1,
  policyVersion: 'supplier_import_exception_review_v1', ...extra});
const actor = {uid: 'agent-1', email: 'agent@kholidaymaps.com'};
const now = '2026-10-06T06:00:00.000Z';
function opening() { return {eventId: 'open-1', commandId: 'open-1', resolutionId: 'extraction-1', extractionId: 'extraction-1',
  previousRevision: 0, resultingRevision: 1, actorUid: actor.uid, occurredAt: f.at, action: 'open_review',
  targetKind: 'resolution', targetId: 'extraction-1', metadata: {kind: 'lifecycle', status: 'active'}}; }
function fixture(payload = {days: [f.day()]}) {
  const db = new FakeFirestore(), source = f.snapshot(payload), paths = supplierImportFinalizationPaths(request());
  db.replace('users/agent-1', {role: 'agent', status: 'active', email: actor.email});
  db.replace('trips/trip-1', {ownerUid: actor.uid});
  db.replace('trips/trip-1/supplier_source_packages/package-1', {tripId: 'trip-1', supplierId: 'supplier-1',
    supplierNameSnapshot: 'Private supplier', fileIds: ['file-1'], uploadedByUid: actor.uid, status: 'uploaded'});
  db.replace('trips/trip-1/supplier_source_files/file-1', {tripId: 'trip-1', packageId: 'package-1', originalFileName: 'source.pdf',
    storagePath: 'trips/trip-1/supplier_sources/file-1/source.pdf', contentType: 'application/pdf', sizeBytes: 100, uploadedByUid: actor.uid});
  const records = serializeSupplierExtractionForPersistence(source);
  db.replace(paths.snapshot, {...records.root, persistenceState: 'complete', createdAt: Timestamp.fromDate(new Date(f.at))});
  for (const [key, collection] of [['days', 'days'], ['facts', 'facts'], ['reviewIssues', 'review_issues']]) for (const item of records[key]) {
    db.replace(`${paths.snapshot}/${collection}/${item.documentId}`, {snapshotOrder: item.snapshotOrder, value: item.value});
  }
  db.replace(paths.root, encode(f.root(source)));
  db.replace(`${paths.auditEvents}/open-1`, encode(opening()));
  return {db, source, paths};
}

/** Execute the real Admin adapter against isolated state. Enforce read-before-
 * write, create/update preconditions, optimistic read versions, atomic staging,
 * callback retries and commit/acknowledgement failures. Never connects to Firebase.
 */
class FakeFirestore {
  constructor() { this.records = new Map(); this.versions = new Map(); this.commits = []; this.attempts = []; this.reads = []; this.retryOnce = false; }
  doc(path) { return new Reference(this, path); }
  collection(path) { return new Query(this, path); }
  replace(path, data) { this.records.set(path, clone(data)); this.versions.set(path, (this.versions.get(path) || 0) + 1); }
  snapshot(ref) { this.reads.push(ref.path); return {id: ref.id, ref, exists: this.records.has(ref.path), data: () => clone(this.records.get(ref.path)), get: (key) => clone(this.records.get(ref.path)?.[key])}; }
  async getAll(...refs) { return refs.map((ref) => this.snapshot(ref)); }
  async runTransaction(callback) {
    await this.beforeTransaction?.();
    for (let attempt = 0; attempt < 3; attempt++) {
      const staged = [], observed = new Map();
      const read = (ref) => {assert.equal(staged.length, 0, 'reads must precede ALL writes'); observed.set(ref.path, this.versions.get(ref.path) || 0); return this.snapshot(ref);};
      const write = (kind, ref, data) => {staged.push({kind, path: ref.path, data: clone(data)}); if (this.failWrite === staged.length) throw new Error('private SDK error while queueing write');};
      const transaction = {getAll: async (...refs) => refs.map(read), get: async (ref) => {
        if (!(ref instanceof Query)) return read(ref);
        assert.equal(staged.length, 0, 'query reads must precede ALL writes');
        const result = await ref.get(); result.docs.forEach((doc) => read(doc.ref)); return result;
      }, create: (ref, data) => write('create', ref, data), update: (ref, data) => write('update', ref, data),
        set: (ref, data) => write('set', ref, data), delete: (ref) => write('delete', ref)};
      const result = await callback(transaction);
      this.attempts.push(clone(staged));
      await this.beforeCommit?.(attempt);
      if (attempt === 0 && this.retryOnce) continue;
      if ([...observed].some(([path, version]) => (this.versions.get(path) || 0) !== version)) continue;
      if (this.commitError) throw this.commitError;
      const next = new Map(this.records);
      for (const item of staged) {
        if (item.kind === 'create' && next.has(item.path)) throw Object.assign(new Error('already exists'), {code: 6});
        if (item.kind === 'update' && !next.has(item.path)) throw Object.assign(new Error('not found'), {code: 5});
        if (item.kind === 'delete') next.delete(item.path);
        else next.set(item.path, item.kind === 'update' ? {...next.get(item.path), ...clone(item.data)} : clone(item.data));
      }
      this.records = next;
      if (staged.length) this.commits.push(clone(staged));
      for (const item of staged) this.versions.set(item.path, (this.versions.get(item.path) || 0) + 1);
      if (this.afterCommitError) throw this.afterCommitError;
      return result;
    }
    throw Object.assign(new Error('aborted after retries'), {code: 10});
  }
}
class Reference {
  constructor(db, path) { this.db = db; this.path = path; this.id = path.split('/').at(-1); }
  collection(name) { return new Query(this.db, `${this.path}/${name}`); }
  async get() { this.db.beforeDocumentRead?.(this.path); return this.db.snapshot(this); }
}
class Query {
  constructor(db, path, limit = Infinity, after = '') { Object.assign(this, {db, path, maximum: limit, after}); }
  doc(id) { return this.db.doc(`${this.path}/${id}`); }
  orderBy() { return this; }
  limit(count) { assert(count > 0); return new Query(this.db, this.path, count, this.after); }
  startAfter(doc) { return new Query(this.db, this.path, this.maximum, doc.id); }
  async get() {
    this.db.beforeQuery?.(this.path);
    const docs = [...this.db.records.keys()].filter((path) => path.startsWith(`${this.path}/`) && !path.slice(this.path.length + 1).includes('/'))
      .sort().filter((path) => path.split('/').at(-1) > this.after).slice(0, this.maximum).map((path) => this.db.snapshot(this.db.doc(path)));
    return {docs, empty: docs.length === 0};
  }
}
function clone(value) {
  if (value instanceof Timestamp) return value;
  if (Array.isArray(value)) return value.map(clone);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, clone(v)]));
  return value;
}
function advance(x) {
  const current = x.db.records.get(x.paths.root), r = current.revision + 1, commandId = `mutation-${r}`;
  x.db.replace(x.paths.root, {...current, revision: r});
  x.db.replace(`${x.paths.auditEvents}/${commandId}`, encode({...opening(), eventId: commandId, commandId, previousRevision: r - 1,
    resultingRevision: r, action: 'set_day_decision', targetKind: 'day', targetId: 'staged-day-1',
    metadata: {kind: 'decision', disposition: 'retain', changedFields: [], exclusionReason: null, referencedIds: []}}));
}
module.exports = {fixture, request, actor, now, opening, advance, clone, FakeFirestore};
