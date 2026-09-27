const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  readTrustedSupplierSourcePackage,
} = require('../lib/itineraryExtraction/sourceReader');
const {
  adminSupplierSourceReaderDependencies,
} = require('../lib/itineraryExtraction/sourceReaderAdmin');
const {
  maxTrustedSourceSizeBytes,
  TrustedSourceError,
  validateCanonicalStoragePath,
  validateExtensionAndMime,
} = require('../lib/itineraryExtraction/sourceReaderValidation');

const tripId = 'trip-1';
const packageId = 'package-1';

const sourceCode = (expected) => (error) =>
  error instanceof TrustedSourceError && error.code === expected;

function file(id, extension = 'pdf', contentType = 'application/pdf') {
  return {
    tripId,
    packageId,
    originalFileName: `Supplier Quote.${extension}`,
    storagePath: `trips/${tripId}/supplier_sources/${id}/quote.${extension}`,
    contentType,
    sizeBytes: 1024,
    uploadedByUid: 'agent-1',
  };
}

function objectFor(data) {
  return {
    name: data.storagePath,
    contentType: data.contentType,
    size: String(data.sizeBytes),
    metadata: {packageId, uploadedByUid: data.uploadedByUid},
  };
}

function fixture() {
  const files = new Map([
    ['file-1', file('file-1')],
    ['file-2', file('file-2', 'txt', 'text/plain')],
  ]);
  const objects = new Map(
    [...files.values()].map((value) => [value.storagePath, objectFor(value)]),
  );
  const state = {
    package: {
      tripId,
      supplierId: 'supplier-1',
      supplierNameSnapshot: 'Example Supplier',
      fileIds: ['file-1', 'file-2'],
      uploadedByUid: 'agent-1',
      status: 'uploaded',
    },
    files,
    objects,
    fileReads: [],
    objectReads: [],
  };
  state.dependencies = {
    async readPackage() {
      return state.package && structuredClone(state.package);
    },
    async readFiles(actualTripId, ids) {
      assert.equal(actualTripId, tripId);
      state.fileReads.push([...ids]);
      return ids.map((id) => state.files.has(id) ?
        structuredClone(state.files.get(id)) : null);
    },
    async inspectObject(path) {
      state.objectReads.push(path);
      return state.objects.has(path) ? structuredClone(state.objects.get(path)) : null;
    },
  };
  state.read = () => readTrustedSupplierSourcePackage(
    tripId,
    packageId,
    state.dependencies,
  );
  return state;
}

test('valid uploaded package returns trusted descriptors in fileIds order', async () => {
  const f = fixture();
  f.package.fileIds = ['file-2', 'file-1'];
  const result = await f.read();
  assert.equal(result.tripId, tripId);
  assert.equal(result.packageId, packageId);
  assert.equal(result.supplierId, 'supplier-1');
  assert.equal(result.supplierNameSnapshot, 'Example Supplier');
  assert.deepEqual(result.files.map((value) => value.sourceFileId), [
    'file-2',
    'file-1',
  ]);
  assert.deepEqual(f.fileReads, [['file-2', 'file-1']]);
  assert.deepEqual(f.objectReads, [
    f.files.get('file-2').storagePath,
    f.files.get('file-1').storagePath,
  ]);
  assert.throws(() => result.files.push(file('other')), TypeError);
});

for (const status of ['uploading', 'failed']) {
  test(`${status} package is rejected`, async () => {
    const f = fixture();
    f.package.status = status;
    await assert.rejects(f.read(), sourceCode('INVALID_SOURCE_INTEGRITY'));
    assert.deepEqual(f.fileReads, []);
  });
}

test('empty and duplicate fileIds are rejected', async () => {
  for (const fileIds of [[], ['file-1', 'file-1']]) {
    const f = fixture();
    f.package.fileIds = fileIds;
    await assert.rejects(f.read(), sourceCode('INVALID_SOURCE_INTEGRITY'));
  }
});

test('malformed package file ID is rejected', async () => {
  for (const id of ['', ' ', 'file/1', '..', 1, null]) {
    const f = fixture();
    f.package.fileIds = [id];
    await assert.rejects(f.read(), sourceCode('INVALID_SOURCE_INTEGRITY'));
  }
});

test('missing package and file metadata are source unavailable', async () => {
  const missingPackage = fixture();
  missingPackage.package = null;
  await assert.rejects(missingPackage.read(), sourceCode('SOURCE_UNAVAILABLE'));

  const missingFile = fixture();
  missingFile.files.delete('file-1');
  await assert.rejects(missingFile.read(), sourceCode('SOURCE_UNAVAILABLE'));
});

test('file metadata must match Trip, package, and uploader', async () => {
  for (const mutation of [
    (data) => {data.tripId = 'trip-2';},
    (data) => {data.packageId = 'package-2';},
    (data) => {data.uploadedByUid = 'agent-2';},
    (data) => {data.originalFileName = ' ';},
  ]) {
    const f = fixture();
    mutation(f.files.get('file-1'));
    await assert.rejects(f.read(), sourceCode('INVALID_SOURCE_INTEGRITY'));
  }
});

test('non-integer, zero, and greater-than-25-MB files are unsupported', async () => {
  for (const sizeBytes of ['1024', 1.5, 0, maxTrustedSourceSizeBytes + 1]) {
    const f = fixture();
    f.files.get('file-1').sizeBytes = sizeBytes;
    await assert.rejects(f.read(), sourceCode('UNSUPPORTED_SOURCE'));
  }
});

test('exactly 25 MB is accepted', async () => {
  const f = fixture();
  const data = f.files.get('file-1');
  data.sizeBytes = maxTrustedSourceSizeBytes;
  f.objects.set(data.storagePath, objectFor(data));
  const result = await f.read();
  assert.equal(result.files[0].sizeBytes, maxTrustedSourceSizeBytes);
});

test('unsupported Firestore MIME is rejected', async () => {
  const f = fixture();
  f.files.get('file-1').contentType = 'application/zip';
  await assert.rejects(f.read(), sourceCode('UNSUPPORTED_SOURCE'));
});

test('canonical Storage path accepts the exact namespace', () => {
  assert.equal(
    validateCanonicalStoragePath(
      'trips/trip-1/supplier_sources/file-1/quote.pdf',
      'trip-1',
      'file-1',
    ),
    'quote.pdf',
  );
});

test('canonical Storage path rejects wrong identity and nested paths', () => {
  for (const path of [
    'trips/trip-2/supplier_sources/file-1/quote.pdf',
    'trips/trip-1/supplier_sources/file-2/quote.pdf',
    'trips/trip-1/supplier_sources/file-1/nested/quote.pdf',
    'trips/trip-1/supplier_sources/file-1/',
    'trips/trip-1/supplier_sources/file-1/../quote.pdf',
    'trips/trip-1/supplier_sources/file-1/%2e%2e.pdf',
    'trips/trip-1/supplier_sources/file-1/a..pdf',
  ]) {
    assert.throws(
      () => validateCanonicalStoragePath(path, tripId, 'file-1'),
      sourceCode('INVALID_SOURCE_INTEGRITY'),
    );
  }
});

const mimeByExtension = {
  pdf: 'application/pdf',
  doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  csv: 'text/csv',
  txt: 'text/plain',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
};

test('every supported extension maps to its secured MIME type', () => {
  for (const [extension, mime] of Object.entries(mimeByExtension)) {
    assert.doesNotThrow(() => validateExtensionAndMime(`quote.${extension}`, mime));
    assert.doesNotThrow(() => validateExtensionAndMime(
      `quote.${extension.toUpperCase()}`,
      mime,
    ));
  }
});

test('missing/unsupported extensions and MIME mismatches are rejected', () => {
  for (const [name, mime] of [
    ['quote', 'application/pdf'],
    ['quote.zip', 'application/zip'],
    ['quote.pdf', 'text/plain'],
  ]) {
    assert.throws(
      () => validateExtensionAndMime(name, mime),
      sourceCode('UNSUPPORTED_SOURCE'),
    );
  }
});

test('missing Storage object is source unavailable', async () => {
  const f = fixture();
  f.objects.delete(f.files.get('file-1').storagePath);
  await assert.rejects(f.read(), sourceCode('SOURCE_UNAVAILABLE'));
});

test('matching Storage identity metadata is accepted', async () => {
  const f = fixture();
  assert.equal((await f.read()).files.length, 2);
});

test('Storage object name and content type mismatches are rejected', async () => {
  for (const field of ['name', 'contentType']) {
    const f = fixture();
    const path = f.files.get('file-1').storagePath;
    f.objects.get(path)[field] = 'mismatch';
    await assert.rejects(f.read(), sourceCode('INVALID_SOURCE_INTEGRITY'));
  }
});

test('Storage size must be safe, supported, and equal Firestore size', async () => {
  for (const size of ['1025', '0', String(maxTrustedSourceSizeBytes + 1), '1.5']) {
    const f = fixture();
    const path = f.files.get('file-1').storagePath;
    f.objects.get(path).size = size;
    const expected = size === '1025' ?
      'INVALID_SOURCE_INTEGRITY' : 'UNSUPPORTED_SOURCE';
    await assert.rejects(f.read(), sourceCode(expected));
  }
});

test('Storage package custom metadata is required and must match', async () => {
  for (const packageValue of [undefined, 'package-2']) {
    const f = fixture();
    const path = f.files.get('file-1').storagePath;
    if (packageValue === undefined) {
      delete f.objects.get(path).metadata.packageId;
    } else {
      f.objects.get(path).metadata.packageId = packageValue;
    }
    await assert.rejects(f.read(), sourceCode('INVALID_SOURCE_INTEGRITY'));
  }
});

test('Storage uploader custom metadata is required and must match', async () => {
  for (const uploader of [undefined, 'agent-2']) {
    const f = fixture();
    const path = f.files.get('file-1').storagePath;
    if (uploader === undefined) {
      delete f.objects.get(path).metadata.uploadedByUid;
    } else {
      f.objects.get(path).metadata.uploadedByUid = uploader;
    }
    await assert.rejects(f.read(), sourceCode('INVALID_SOURCE_INTEGRITY'));
  }
});

test('Admin adapter reads metadata only and preserves requested file order', async () => {
  const f = fixture();
  f.package.fileIds = ['file-2', 'file-1'];
  const requestedObjects = [];
  const reference = (path) => ({
    path,
    async get() {
      return {data: () => path.endsWith(packageId) ? f.package : undefined};
    },
  });
  const db = {
    doc: reference,
    async getAll(...references) {
      return references.map(({path}) => ({
        data: () => f.files.get(path.split('/').at(-1)),
      }));
    },
  };
  const bucket = {
    file(path) {
      requestedObjects.push(path);
      return {
        async getMetadata() {
          return [f.objects.get(path)];
        },
        async download() {
          assert.fail('Reader must not download bytes');
        },
      };
    },
  };
  const result = await readTrustedSupplierSourcePackage(
    tripId,
    packageId,
    adminSupplierSourceReaderDependencies(db, bucket),
  );
  assert.deepEqual(result.files.map((value) => value.sourceFileId), [
    'file-2',
    'file-1',
  ]);
  assert.deepEqual(requestedObjects, [
    f.files.get('file-2').storagePath,
    f.files.get('file-1').storagePath,
  ]);
});

test('Admin adapter sanitizes Firestore and Storage SDK failures', async () => {
  const firestoreDependencies = adminSupplierSourceReaderDependencies({
    doc: () => ({get: async () => {throw new Error('SECRET FIRESTORE');}}),
  }, {});
  await assert.rejects(
    firestoreDependencies.readPackage(tripId, packageId),
    (error) => sourceCode('SOURCE_UNAVAILABLE')(error) &&
      !error.message.includes('SECRET'),
  );

  const storageDependencies = adminSupplierSourceReaderDependencies({}, {
    file: () => ({getMetadata: async () => {throw new Error('SECRET STORAGE');}}),
  });
  await assert.rejects(
    storageDependencies.inspectObject('canonical/path'),
    (error) => sourceCode('SOURCE_UNAVAILABLE')(error) &&
      !error.message.includes('SECRET'),
  );
});
