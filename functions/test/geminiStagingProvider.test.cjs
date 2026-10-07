const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {ApiError} = require('@google/genai');
const {
  GeminiStagingProviderError,
  geminiStagingModel,
  geminiStagingVertexApiVersion,
  geminiStagingVertexLocation,
  geminiSupplierExtractionStagingProvider,
  vertexGeminiStagingGenerationClient,
} = require('../lib/itineraryExtraction/geminiStagingProvider');
const {
  kayraSupplierExtractionV3Prompt,
  kayraSupplierExtractionV3PromptVersion,
} = require('../lib/itineraryExtraction/geminiStagingProviderPrompt');
const {
  kayraSupplierExtractionV3ResponseSchema,
} = require('../lib/itineraryExtraction/geminiStagingProviderSchema');
const {
  normalizeProviderSupplierExtractionV3,
} = require('../lib/itineraryExtraction/providerSupplierExtractionV3');

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

const validPayload = {
  title: {
    text: 'Source itinerary',
    basis: 'explicit_supplier',
    sources: [{fileIndex: 1, sourceLabel: 'Page 1'}],
  },
  days: [],
};

function sourceFile(id, contentType) {
  const extension = extensionFor[contentType];
  return {
    sourceFileId: id,
    packageId: 'package-v3',
    originalFileName: `source.${extension}`,
    storagePath: `trips/trip-v3/supplier_sources/${id}/source.${extension}`,
    contentType,
    sizeBytes: 100,
    uploadedByUid: 'agent-v3',
  };
}

function input(files) {
  return {
    tripId: 'trip-v3',
    sourcePackage: {
      tripId: 'trip-v3',
      packageId: 'package-v3',
      supplierId: null,
      supplierNameSnapshot: null,
      files,
    },
  };
}

function normalizationContext(sourcePackage) {
  return {
    extractionId: 'extraction-v3',
    tripId: 'trip-v3',
    sourcePackageId: 'package-v3',
    jobId: 'job-v3',
    requestedByUid: 'agent-v3',
    createdAt: new Date('2026-09-29T10:00:00.000Z'),
    trustedPackage: sourcePackage,
  };
}

function fixture(options = {}) {
  const calls = [];
  const csvReads = [];
  const logs = [];
  const response = options.response ?? {
    text: JSON.stringify(validPayload),
    candidates: [{finishReason: 'STOP'}],
  };
  const provider = geminiSupplierExtractionStagingProvider({
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
        return options.csvText ?? 'day,service\n1,Arrival';
      },
    },
    log: (event, fields) => logs.push({event, ...fields}),
  });
  return {calls, csvReads, logs, provider};
}

const providerFailure = (code, reason) => (error) =>
  error instanceof GeminiStagingProviderError &&
  error.code === code && error.reason === reason;

test('valid chronological V3 response uses one exact structured request', async () => {
  const payload = {
    title: validPayload.title,
    days: [{
      sourceDayNumber: 1,
      date: '2027-03-01',
      title: 'Arrival',
      services: [{
        type: 'transfer',
        title: 'Arrival transfer',
        transferDetails: {pickup: 'Airport', dropoff: 'Hotel'},
      }],
    }],
  };
  const f = fixture({
    response: {
      text: JSON.stringify(payload),
      candidates: [{finishReason: 'STOP'}],
    },
  });

  const result = await f.provider.extract(input([
    sourceFile('file-1', 'application/pdf'),
  ]));

  assert.deepEqual(result, payload);
  assert(Object.isFrozen(result));
  assert(Object.isFrozen(result.days[0].services[0]));
  assert.equal(f.calls.length, 1);
  const request = f.calls[0];
  assert.equal(geminiStagingModel, 'gemini-3.5-flash');
  assert.equal(geminiStagingVertexLocation, 'global');
  assert.equal(geminiStagingVertexApiVersion, 'v1');
  assert.equal(request.model, 'gemini-3.5-flash');
  assert.equal(request.config.systemInstruction, kayraSupplierExtractionV3Prompt);
  assert.equal(request.config.responseMimeType, 'application/json');
  assert.equal(request.config.responseJsonSchema, kayraSupplierExtractionV3ResponseSchema);
  assert.equal(request.config.candidateCount, 1);
  assert.equal(request.config.maxOutputTokens, 16_384);
  assert.equal(request.config.thinkingConfig.thinkingLevel, 'LOW');
  assert.deepEqual(Object.keys(request.config), [
    'systemInstruction',
    'responseMimeType',
    'responseJsonSchema',
    'candidateCount',
    'maxOutputTokens',
    'thinkingConfig',
  ]);
  assert.equal('tools' in request.config, false);
  assert.equal('groundingConfig' in request.config, false);
});

test('valid no-chronology response keeps unassigned services and package facts', async () => {
  const payload = {
    days: [],
    unassignedServices: [
      {type: 'sightseeing', title: 'City tour'},
      {type: 'activity', title: 'Mountain excursion'},
    ],
    packageFacts: {
      accommodations: [{hotelName: 'Package Hotel', nightCount: 4}],
      inclusions: [{category: 'guide', text: 'Guide included'}],
    },
    reviewIssues: [{
      code: 'chronology_unknown',
      severity: 'blocker',
      message: 'The source does not state chronology.',
      target: {kind: 'snapshot'},
      resolutionRequired: true,
    }],
  };
  const f = fixture({
    response: {
      text: JSON.stringify(payload),
      candidates: [{finishReason: 'STOP'}],
    },
  });

  const result = await f.provider.extract(input([
    sourceFile('file-1', 'text/plain'),
  ]));

  assert.equal(result.days.length, 0);
  assert.equal(result.unassignedServices.length, 2);
  assert.equal(result.packageFacts.accommodations[0].nightCount, 4);
  assert.equal(f.calls.length, 1);
});

test('narrative response keeps hotel global, services assigned, and flight ancillary',
  async () => {
    const payload = {
      days: [{
        title: 'Arrival programme',
        services: [
          {
            type: 'transfer',
            transferDetails: {pickup: 'Airport', dropoff: 'Hotel'},
          },
          {type: 'meal', title: 'Welcome dinner'},
        ],
      }],
      packageFacts: {
        accommodations: [{hotelName: 'Global Hotel', nightCount: 3}],
      },
      ancillaryFacts: {
        flights: [{flightNumber: 'EA 100', origin: 'AAA', destination: 'BBB'}],
      },
    };
    const f = fixture({
      response: {
        text: JSON.stringify(payload),
        candidates: [{finishReason: 'STOP'}],
      },
    });

    const result = await f.provider.extract(input([
      sourceFile('file-1', 'application/pdf'),
    ]));

    const accommodation = result.packageFacts.accommodations[0];
    assert.equal('checkInDate' in accommodation, false);
    assert.equal('checkOutDate' in accommodation, false);
    assert.equal(result.days[0].services.length, 2);
    assert.equal(result.ancillaryFacts.flights[0].flightNumber, 'EA 100');
  });

test('multi-file request and provenance retain authoritative package order', async () => {
  const files = [
    sourceFile('file-b', 'image/png'),
    sourceFile('file-a', 'application/pdf'),
    sourceFile('file-c', 'text/plain'),
  ];
  const payload = {
    unassignedServices: [{
      type: 'meal',
      title: 'Dinner',
      sources: [{fileIndex: 2, sourceLabel: 'Page 1'}],
    }],
  };
  const f = fixture({
    response: {
      text: JSON.stringify(payload),
      candidates: [{finishReason: 'STOP'}],
    },
  });
  const providerInput = input(files);

  const result = await f.provider.extract(providerInput);
  const parts = f.calls[0].contents[0].parts;
  const labels = parts.filter((part) => part.text?.startsWith('SOURCE FILE'));
  assert.deepEqual(labels.map((part) => part.text.split('\n')[0]), [
    'SOURCE FILE 1', 'SOURCE FILE 2', 'SOURCE FILE 3',
  ]);
  assert.match(labels[0].text, /fileIndex = 1/);
  assert.match(labels[1].text, /fileIndex = 2/);
  assert.match(labels[2].text, /fileIndex = 3/);
  assert.match(labels[0].text, /inputMode = private-gcs-uri/);
  assert.equal(labels.some((part) => part.text.includes('sourceFileId')), false);
  assert.equal(labels.some((part) => part.text.includes('trips/')), false);

  const snapshot = normalizeProviderSupplierExtractionV3(
    result,
    normalizationContext(providerInput.sourcePackage),
  );
  const service = snapshot.facts.find((fact) => fact.factKind === 'service');
  assert.equal(service.sources[0].supplierSourceFileId, 'file-a');
});

for (const contentType of [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'text/plain',
  'text/csv',
]) {
  test(`V3 supports ${contentType} with the established input mode`, async () => {
    const f = fixture();
    await f.provider.extract(input([sourceFile('file-1', contentType)]));

    assert.equal(f.calls.length, 1);
    assert.deepEqual(f.csvReads, contentType === 'text/csv' ? ['file-1'] : []);
    const parts = f.calls[0].contents[0].parts;
    if (contentType === 'text/csv') {
      assert(parts.some((part) => part.text?.startsWith('UTF-8 SOURCE CONTENT')));
      assert.equal(parts.some((part) => part.fileData), false);
    } else {
      assert.equal(parts.filter((part) => part.fileData).length, 1);
      assert.equal(parts.find((part) => part.fileData).fileData.mimeType, contentType);
    }
  });
}

for (const contentType of [
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]) {
  test(`V3 rejects ${contentType} before generation`, async () => {
    const f = fixture();
    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', contentType)])),
      providerFailure('UNSUPPORTED_SOURCE', 'unsupported_source'),
    );
    assert.equal(f.calls.length, 0);
    assert.equal(f.csvReads.length, 0);
  });
}

test('CSV inputs are read sequentially in package order', async () => {
  const activeReads = [];
  const completedReads = [];
  const requests = [];
  const provider = geminiSupplierExtractionStagingProvider({
    bucketName: 'kayra-crm-v1.firebasestorage.app',
    client: {
      async generateContent(request) {
        requests.push(request);
        return {
          text: JSON.stringify(validPayload),
          candidates: [{finishReason: 'STOP'}],
        };
      },
    },
    csvTextReader: {
      async readUtf8Csv(file) {
        activeReads.push(file.sourceFileId);
        assert.equal(activeReads.length, 1);
        await Promise.resolve();
        completedReads.push(file.sourceFileId);
        activeReads.pop();
        return `id\n${file.sourceFileId}`;
      },
    },
  });

  await provider.extract(input([
    sourceFile('file-2', 'text/csv'),
    sourceFile('file-1', 'text/csv'),
  ]));

  assert.deepEqual(completedReads, ['file-2', 'file-1']);
  const inline = requests[0].contents[0].parts.filter((part) =>
    part.text?.startsWith('UTF-8 SOURCE CONTENT'));
  assert.match(inline[0].text, /file-2/);
  assert.match(inline[1].text, /file-1/);
});

for (const response of [
  {text: '', candidates: [{finishReason: 'STOP'}]},
  {candidates: [{finishReason: 'STOP'}]},
]) {
  test('empty V3 output fails deterministically without retry', async () => {
    const f = fixture({response});
    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
      providerFailure('PROVIDER_EXECUTION_FAILED', 'empty_response'),
    );
    assert.equal(f.calls.length, 1);
  });
}

test('malformed JSON fails after one generation call and is not repaired', async () => {
  const f = fixture({
    response: {
      text: '{"days":[}',
      candidates: [{finishReason: 'STOP'}],
    },
  });
  await assert.rejects(
    f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
    providerFailure('PROVIDER_EXECUTION_FAILED', 'malformed_json'),
  );
  assert.equal(f.calls.length, 1);
});

test('structurally invalid V3 response fails strict validation without retry',
  async () => {
    const f = fixture({
      response: {
        text: JSON.stringify({days: [], providerOwnedId: 'unsafe'}),
        candidates: [{finishReason: 'STOP'}],
      },
    });
    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
      providerFailure('PROVIDER_EXECUTION_FAILED', 'invalid_v3_response'),
    );
    assert.equal(f.calls.length, 1);
  });

test('commercial-value leakage fails validation and never reaches logs', async () => {
  const secretPrice = 'USD 98765 per person';
  const f = fixture({
    response: {
      text: JSON.stringify({
        unassignedServices: [{title: `City tour ${secretPrice}`}],
        commercialContent: {
          present: true,
          categories: ['per_person_price'],
        },
      }),
      candidates: [{finishReason: 'STOP'}],
    },
  });
  await assert.rejects(
    f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
    providerFailure('PROVIDER_EXECUTION_FAILED', 'invalid_v3_response'),
  );

  assert.equal(f.calls.length, 1);
  assert.equal(JSON.stringify(f.logs).includes(secretPrice), false);
  assert.equal(JSON.stringify(f.logs).includes('98765'), false);
});

test('MAX_TOKENS reports aggregate V3 structure without response values',
  async () => {
    const truncated = [
      '{"days":[{"services":[{"type":"hotel",',
      '"hotelDetails":{"hotelName":"SECRET HOTEL"},',
      '"sources":[{"sourceLabel":"SECRET PAGE"}]}]}],',
      '"unassignedServices":[{"type":"activity",',
      '"activityDetails":{"activityName":"SECRET TOUR"}}],',
      '"packageFacts":{"conditions":[]},',
      '"ancillaryFacts":{"flights":[]},',
      '"commercialContent":{"present":true},',
      '"reviewIssues":[{"message":"SECRET ISSUE"',
    ].join('');
    const f = fixture({
      response: {
        text: truncated,
        candidates: [{finishReason: 'MAX_TOKENS'}],
        usageMetadata: {candidatesTokenCount: 16_384},
      },
    });

    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
      providerFailure('PROVIDER_EXECUTION_FAILED', 'incomplete_response'),
    );
    assert.equal(f.calls.length, 1);
    const completed = f.logs.find((entry) =>
      entry.event === 'supplier-extraction-v3-provider-completed');
    assert.equal(completed.finishReason, 'MAX_TOKENS');
    assert.equal(completed.responseUtf8Bytes, Buffer.byteLength(truncated, 'utf8'));
    assert.equal(completed.responseCharacterCount, [...truncated].length);
    assert.equal(completed.startsWithObjectBrace, true);
    assert.equal(completed.endsWithObjectBrace, false);
    assert.equal(completed.keyCountDays, 1);
    assert.equal(completed.keyCountServices, 1);
    assert.equal(completed.keyCountUnassignedServices, 1);
    assert.equal(completed.keyCountPackageFacts, 1);
    assert.equal(completed.keyCountAncillaryFacts, 1);
    assert.equal(completed.keyCountCommercialContent, 1);
    assert.equal(completed.keyCountReviewIssues, 1);
    assert.equal(completed.keyCountType, 2);
    assert.equal(completed.keyCountHotelDetails, 1);
    assert.equal(completed.keyCountActivityDetails, 1);
    assert.equal(completed.keyCountSources, 1);
    const serializedLogs = JSON.stringify(f.logs);
    for (const secret of [
      'SECRET HOTEL', 'SECRET PAGE', 'SECRET TOUR', 'SECRET ISSUE', truncated,
      kayraSupplierExtractionV3Prompt,
    ]) {
      assert.equal(serializedLogs.includes(secret), false, `leaked ${secret}`);
    }
  });

for (const finishReason of ['SAFETY', 'RECITATION', 'OTHER']) {
  test(`${finishReason} is rejected as an incomplete response`, async () => {
    const f = fixture({
      response: {
        text: JSON.stringify(validPayload),
        candidates: [{finishReason}],
      },
    });
    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
      providerFailure('PROVIDER_EXECUTION_FAILED', 'incomplete_response'),
    );
    assert.equal(f.calls.length, 1);
  });
}

test('missing finish reason is rejected even when JSON is otherwise valid', async () => {
  const f = fixture({response: {text: JSON.stringify(validPayload)}});
  await assert.rejects(
    f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
    providerFailure('PROVIDER_EXECUTION_FAILED', 'incomplete_response'),
  );
  assert.equal(f.calls.length, 1);
});

test('provider exception logs only allowlisted operational metadata', async () => {
  const rawMessage = JSON.stringify({
    error: {
      code: 429,
      status: 'RESOURCE_EXHAUSTED',
      message: 'SECRET PROVIDER BODY gs://secret/private.pdf',
    },
  });
  const sdkError = new ApiError({status: 429, message: rawMessage});
  sdkError.stack = 'SECRET STACK WITH SOURCE CONTENT';
  const f = fixture({clientError: sdkError});

  await assert.rejects(
    f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
    providerFailure('PROVIDER_EXECUTION_FAILED', 'provider_execution'),
  );
  assert.equal(f.calls.length, 1);
  const failed = f.logs.at(-1);
  assert.equal(failed.event, 'supplier-extraction-v3-provider-failed');
  assert.equal(failed.providerErrorName, 'ApiError');
  assert.equal(failed.providerHttpStatus, 429);
  assert.equal(failed.providerRpcStatus, 'RESOURCE_EXHAUSTED');
  assert.equal(failed.providerFailureCategory, 'resource_exhausted');
  const serializedLogs = JSON.stringify(f.logs);
  for (const secret of [
    rawMessage, 'SECRET PROVIDER BODY', 'SECRET STACK', 'gs://secret/private.pdf',
  ]) {
    assert.equal(serializedLogs.includes(secret), false);
  }
});

test('request and completion logs contain only safe aggregate metadata', async () => {
  const pdf = sourceFile('private-file-id', 'application/pdf');
  const csv = sourceFile('private-csv-id', 'text/csv');
  pdf.originalFileName = 'SECRET SUPPLIER.pdf';
  pdf.sizeBytes = 125;
  csv.originalFileName = 'SECRET PRICES.csv';
  csv.sizeBytes = 75;
  const secretOutput = 'SECRET EXTRACTED TITLE';
  const f = fixture({
    csvText: 'SECRET SOURCE TEXT,USD 900',
    response: {
      text: JSON.stringify({
        title: {text: secretOutput, basis: 'explicit_supplier'},
      }),
      candidates: [{finishReason: 'STOP'}],
      usageMetadata: {
        cacheTokensDetails: [{modality: 'TEXT', tokenCount: 2}],
        cachedContentTokenCount: 2,
        candidatesTokenCount: 20,
        candidatesTokensDetails: [{modality: 'TEXT', tokenCount: 20}],
        promptTokenCount: 100,
        promptTokensDetails: [{modality: 'DOCUMENT', tokenCount: 100}],
        thoughtsTokenCount: 30,
        toolUsePromptTokenCount: 0,
        toolUsePromptTokensDetails: [],
        totalTokenCount: 150,
        trafficType: 'ON_DEMAND',
      },
    },
  });

  await f.provider.extract(input([pdf, csv]));

  const requested = f.logs.find((entry) =>
    entry.event === 'supplier-extraction-v3-provider-requested');
  assert.equal(requested.provider, 'vertex-ai-gemini');
  assert.equal(requested.model, 'gemini-3.5-flash');
  assert.equal(requested.promptVersion, kayraSupplierExtractionV3PromptVersion);
  assert.equal(requested.promptVersion, 'kayra_itinerary_extraction_v3_staging');
  assert.equal(requested.thinkingLevel, 'LOW');
  assert.equal(requested.fileCount, 2);
  assert.deepEqual(requested.mimeTypes, ['application/pdf', 'text/csv']);
  assert.deepEqual(requested.fileSizesBytes, [125, 75]);
  assert.equal(requested.totalSourceBytes, 200);
  assert.deepEqual(requested.inputModes, [
    'private-gcs-uri', 'bounded-inline-text',
  ]);
  assert.equal(Number.isNaN(Date.parse(requested.providerStartedAt)), false);

  const completed = f.logs.find((entry) =>
    entry.event === 'supplier-extraction-v3-provider-completed');
  assert.equal(completed.finishReason, 'STOP');
  assert.equal(completed.candidateCount, 1);
  assert.equal(completed.promptTokenCount, 100);
  assert.equal(completed.candidatesTokenCount, 20);
  assert.equal(completed.totalTokenCount, 150);
  assert.equal(completed.trafficType, 'ON_DEMAND');
  assert.deepEqual(completed.promptTokensDetails, [
    {modality: 'DOCUMENT', tokenCount: 100},
  ]);

  const serializedLogs = JSON.stringify(f.logs);
  for (const secret of [
    'SECRET SUPPLIER', 'SECRET PRICES', 'SECRET SOURCE TEXT', 'USD 900',
    secretOutput, pdf.sourceFileId, csv.sourceFileId, pdf.storagePath,
    kayraSupplierExtractionV3Prompt,
  ]) {
    assert.equal(serializedLogs.includes(secret), false, `leaked ${secret}`);
  }
});

test('Vertex client validates project identity without requiring credentials in tests', () => {
  assert.throws(
    () => vertexGeminiStagingGenerationClient('invalid/project'),
    providerFailure('PROVIDER_EXECUTION_FAILED', 'provider_execution'),
  );
});

test('production processor and V2.4 provider do not import the V3 adapter', () => {
  for (const fileName of [
    'processor.ts',
    'trigger.ts',
    'request.ts',
    'geminiProvider.ts',
    'geminiProviderAdmin.ts',
  ]) {
    const contents = fs.readFileSync(
      path.join(__dirname, '../src/itineraryExtraction', fileName),
      'utf8',
    );
    assert.doesNotMatch(contents, /geminiStagingProvider/);
    assert.doesNotMatch(contents, /geminiSupplierExtractionStagingProvider/);
  }
});

for (const [index, value] of ['Commission 12%', 'CNY 500'].entries()) {
  test(`confirmed commercial escape ${index} fails safely after one generation without logging content`, async () => {
    const f = fixture({response: {text: JSON.stringify({days: [{title: 'Arrival', notes: value}]}),
      candidates: [{finishReason: 'STOP'}]}});
    await assert.rejects(f.provider.extract(input([sourceFile('file-1', 'application/pdf')])), error => {
      assert.equal(String(error).includes(value), false);
      return providerFailure('PROVIDER_EXECUTION_FAILED', 'invalid_v3_response')(error);
    });
    assert.equal(f.calls.length, 1);
    assert.equal(JSON.stringify(f.logs).includes(value), false);
  });
}
