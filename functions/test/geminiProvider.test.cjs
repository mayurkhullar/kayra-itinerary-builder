const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  adminCsvTextReader,
  resolveGoogleCloudProjectId,
} = require('../lib/itineraryExtraction/geminiProviderAdmin');
const {
  geminiItineraryExtractionProvider,
  geminiItineraryModel,
  geminiVertexLocation,
} = require('../lib/itineraryExtraction/geminiProvider');
const {
  kayraItineraryExtractionPrompt,
  kayraItineraryExtractionPromptVersion,
} = require('../lib/itineraryExtraction/geminiProviderPrompt');
const {
  geminiReviewSeverities,
  geminiServiceTypes,
  geminiTransferTypes,
  kayraItineraryExtractionResponseSchema,
} = require('../lib/itineraryExtraction/geminiProviderSchema');
const {
  ItineraryExtractionProviderError,
} = require('../lib/itineraryExtraction/processor');
const {
  maxTrustedSourceSizeBytes,
} = require('../lib/itineraryExtraction/sourceReaderValidation');

const validJson = JSON.stringify({
  title: 'Extracted itinerary',
  days: [],
  reviewIssues: [],
});

const providerCode = (expected) => (error) =>
  error instanceof ItineraryExtractionProviderError && error.code === expected;

const extensionFor = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'text/plain': 'txt',
  'text/csv': 'csv',
  'application/msword': 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.ms-excel': 'xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
};

function sourceFile(id, contentType) {
  const extension = extensionFor[contentType];
  return {
    sourceFileId: id,
    packageId: 'package-1',
    originalFileName: `source.${extension}`,
    storagePath: `trips/trip-1/supplier_sources/${id}/source.${extension}`,
    contentType,
    sizeBytes: 100,
    uploadedByUid: 'agent-1',
  };
}

function input(files) {
  return {
    tripId: 'trip-1',
    sourcePackage: {
      tripId: 'trip-1',
      packageId: 'package-1',
      supplierId: null,
      supplierNameSnapshot: null,
      files,
    },
  };
}

function fixture(options = {}) {
  const calls = [];
  const csvReads = [];
  const logs = [];
  const response = options.response ?? {text: validJson};
  const provider = geminiItineraryExtractionProvider({
    bucketName: 'kayra-crm-v1.firebasestorage.app',
    client: {
      async generateContent(request) {
        calls.push(request);
        if (options.clientError) throw options.clientError;
        return response;
      },
    },
    csvTextReader: {
      async readUtf8Csv(file) {
        csvReads.push(file.sourceFileId);
        return 'day,service\n1,Arrival';
      },
    },
    log: (event, fields) => logs.push({event, ...fields}),
  });
  return {calls, csvReads, logs, provider};
}

for (const contentType of [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'text/plain',
  'text/csv',
]) {
  test(`${contentType} is accepted`, async () => {
    const f = fixture();
    const result = await f.provider.extract(input([
      sourceFile('file-1', contentType),
    ]));
    assert.deepEqual(result, JSON.parse(validJson));
    assert.equal(f.calls.length, 1);
    assert.deepEqual(f.csvReads, contentType === 'text/csv' ? ['file-1'] : []);
  });
}

for (const contentType of [
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]) {
  test(`${contentType} is unsupported before Gemini is called`, async () => {
    const f = fixture();
    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', contentType)])),
      providerCode('UNSUPPORTED_SOURCE'),
    );
    assert.equal(f.calls.length, 0);
    assert.equal(f.csvReads.length, 0);
  });
}

test('one unsupported file rejects the entire ordered package', async () => {
  const f = fixture();
  await assert.rejects(
    f.provider.extract(input([
      sourceFile('file-1', 'application/pdf'),
      sourceFile('file-2', 'application/msword'),
      sourceFile('file-3', 'text/csv'),
    ])),
    providerCode('UNSUPPORTED_SOURCE'),
  );
  assert.equal(f.calls.length, 0);
  assert.equal(f.csvReads.length, 0);
});

test('private GCS parts preserve package order and trusted source identities', async () => {
  const f = fixture();
  await f.provider.extract(input([
    sourceFile('file-2', 'image/png'),
    sourceFile('file-1', 'application/pdf'),
    sourceFile('file-3', 'text/plain'),
  ]));
  const parts = f.calls[0].contents[0].parts;
  assert.deepEqual(parts.filter((part) => part.fileData).map((part) =>
    part.fileData.fileUri), [
    'gs://kayra-crm-v1.firebasestorage.app/trips/trip-1/' +
      'supplier_sources/file-2/source.png',
    'gs://kayra-crm-v1.firebasestorage.app/trips/trip-1/' +
      'supplier_sources/file-1/source.pdf',
    'gs://kayra-crm-v1.firebasestorage.app/trips/trip-1/' +
      'supplier_sources/file-3/source.txt',
  ]);
  const labels = parts.filter((part) => part.text?.startsWith('SOURCE FILE'));
  assert.deepEqual(labels.map((part) => part.text.split('\n')[0]), [
    'SOURCE FILE 1', 'SOURCE FILE 2', 'SOURCE FILE 3',
  ]);
  assert.match(labels[0].text, /sourcePackageId = package-1/);
  assert.match(labels[0].text, /sourceFileId = file-2/);
  assert.match(labels[1].text, /sourceFileId = file-1/);
  assert.match(labels[2].text, /sourceFileId = file-3/);
  assert.equal(labels.some((part) => part.text.includes('trips/')), false);
  assert.equal(JSON.stringify(f.calls[0]).includes('signed'), false);
  assert.equal(JSON.stringify(f.calls[0]).includes('downloadUrl'), false);
});

test('CSV is read sequentially and supplied inline in package order', async () => {
  const activeReads = [];
  const callOrder = [];
  const requests = [];
  const provider = geminiItineraryExtractionProvider({
    bucketName: 'kayra-crm-v1.firebasestorage.app',
    client: {
      async generateContent(request) {
        requests.push(request);
        return {text: validJson};
      },
    },
    csvTextReader: {
      async readUtf8Csv(file) {
        activeReads.push(file.sourceFileId);
        assert.equal(activeReads.length, 1);
        await Promise.resolve();
        callOrder.push(file.sourceFileId);
        activeReads.pop();
        return `id\n${file.sourceFileId}`;
      },
    },
  });
  await provider.extract(input([
    sourceFile('file-2', 'text/csv'),
    sourceFile('file-1', 'text/csv'),
  ]));
  assert.deepEqual(callOrder, ['file-2', 'file-1']);
  const inline = requests[0].contents[0].parts
    .filter((part) => part.text?.startsWith('UTF-8 SOURCE CONTENT'));
  assert.match(inline[0].text, /file-2/);
  assert.match(inline[1].text, /file-1/);
});

test('prompt is versioned and constrains factual extraction', () => {
  assert.equal(kayraItineraryExtractionPromptVersion, 'kayra_itinerary_extraction_v1');
  assert.match(kayraItineraryExtractionPrompt, /never invent/i);
  assert.match(kayraItineraryExtractionPrompt, /reviewIssues/);
  assert.match(kayraItineraryExtractionPrompt, /supplier pricing and costs/i);
  assert.match(kayraItineraryExtractionPrompt, /Flights and visa are outside/i);
  assert.match(kayraItineraryExtractionPrompt, /first structured/i);
  assert.equal(kayraItineraryExtractionPrompt.includes('@kholidaymaps.com'), false);
  assert.equal(kayraItineraryExtractionPrompt.includes('Test Client'), false);
});

test('request uses the exact model and controlled JSON schema once', async () => {
  const f = fixture();
  await f.provider.extract(input([sourceFile('file-1', 'application/pdf')]));
  assert.equal(f.calls.length, 1);
  const request = f.calls[0];
  assert.equal(geminiItineraryModel, 'gemini-3.5-flash');
  assert.equal(geminiVertexLocation, 'global');
  assert.equal(request.model, 'gemini-3.5-flash');
  assert.equal(request.config.responseMimeType, 'application/json');
  assert.equal(request.config.responseJsonSchema, kayraItineraryExtractionResponseSchema);
  assert.equal(request.config.candidateCount, 1);
  assert.equal(request.config.thinkingConfig.thinkingLevel, 'LOW');
  assert.equal('temperature' in request.config, false);
  assert.equal('topK' in request.config, false);
  assert.equal('topP' in request.config, false);
  assert.equal('tools' in request.config, false);
});

test('schema mirrors provider-controlled Dart and TypeScript values', () => {
  const root = kayraItineraryExtractionResponseSchema;
  assert.deepEqual(Object.keys(root.properties), ['title', 'days', 'reviewIssues']);
  for (const backendField of [
    'id', 'tripId', 'sourcePackageIds', 'createdByUid', 'createdAt', 'updatedAt',
  ]) {
    assert.equal(backendField in root.properties, false);
  }
  const service = root.properties.days.items.properties.services.items;
  assert.deepEqual(service.properties.type.enum, [...geminiServiceTypes]);
  assert.deepEqual(
    service.properties.transferDetails.anyOf[0].properties.transferType.anyOf[0].enum,
    [...geminiTransferTypes],
  );
  assert.deepEqual(
    root.properties.reviewIssues.items.properties.severity.enum,
    [...geminiReviewSeverities],
  );
  assert.equal(root.additionalProperties, false);
  assert.equal(service.additionalProperties, false);
});

test('parsed JSON is returned without trusted schema validation in the adapter', async () => {
  const parsedButInvalid = {providerSpecific: true};
  const f = fixture({response: {text: JSON.stringify(parsedButInvalid)}});
  assert.deepEqual(
    await f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
    parsedButInvalid,
  );
});

for (const response of [{text: ''}, {text: 'not json'}, {}]) {
  test('empty or invalid JSON response becomes provider execution failure', async () => {
    const f = fixture({response});
    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
      providerCode('PROVIDER_EXECUTION_FAILED'),
    );
    assert.equal(f.calls.length, 1);
  });
}

test('ordinary client errors are sanitized and response content is never logged', async () => {
  const f = fixture({clientError: new Error('SECRET VERTEX ERROR')});
  await assert.rejects(
    f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
    (error) => providerCode('PROVIDER_EXECUTION_FAILED')(error) &&
      !error.message.includes('SECRET'),
  );
  assert.equal(JSON.stringify(f.logs).includes('SECRET'), false);

  const successful = fixture({
    response: {
      text: JSON.stringify({title: 'SECRET RESPONSE', days: [], reviewIssues: []}),
      usageMetadata: {
        promptTokenCount: 10,
        candidatesTokenCount: 5,
        totalTokenCount: 15,
      },
    },
  });
  await successful.provider.extract(input([
    sourceFile('file-1', 'application/pdf'),
  ]));
  assert.equal(JSON.stringify(successful.logs).includes('SECRET RESPONSE'), false);
  assert.equal(successful.logs.at(-1).totalTokenCount, 15);
});

test('Admin CSV reader performs one bounded private download and strict UTF-8 decode', async () => {
  const downloads = [];
  const bytes = Buffer.from('day,service\n1,Arrival', 'utf8');
  const bucket = {
    file(path) {
      return {
        async download(options) {
          downloads.push({path, options});
          return [bytes];
        },
      };
    },
  };
  const file = sourceFile('file-1', 'text/csv');
  file.sizeBytes = bytes.byteLength;
  assert.equal(await adminCsvTextReader(bucket).readUtf8Csv(file), bytes.toString());
  assert.deepEqual(downloads, [{
    path: file.storagePath,
    options: {start: 0, end: maxTrustedSourceSizeBytes},
  }]);
});

test('Admin CSV reader rejects changed size and invalid UTF-8', async () => {
  const file = sourceFile('file-1', 'text/csv');
  file.sizeBytes = 2;
  for (const bytes of [Buffer.from('abc'), Buffer.from([0xc3, 0x28])]) {
    const bucket = {
      file: () => ({download: async () => [bytes]}),
    };
    await assert.rejects(
      adminCsvTextReader(bucket).readUtf8Csv(file),
      providerCode('PROVIDER_EXECUTION_FAILED'),
    );
  }
});

test('runtime project discovery uses Google Cloud or Firebase configuration', () => {
  assert.equal(
    resolveGoogleCloudProjectId({GOOGLE_CLOUD_PROJECT: 'kayra-crm-v1'}),
    'kayra-crm-v1',
  );
  assert.equal(
    resolveGoogleCloudProjectId({FIREBASE_CONFIG: '{"projectId":"kayra-crm-v1"}'}),
    'kayra-crm-v1',
  );
  assert.throws(
    () => resolveGoogleCloudProjectId({}),
    providerCode('PROVIDER_EXECUTION_FAILED'),
  );
});
