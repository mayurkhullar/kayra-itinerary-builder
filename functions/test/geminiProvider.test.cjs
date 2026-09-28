const {test} = require('node:test');
const assert = require('node:assert/strict');
const {ApiError} = require('@google/genai');
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
        return options.csvText ?? 'day,service\n1,Arrival';
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

test('private GCS parts preserve package order with compact file indexes', async () => {
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
  assert.match(labels[0].text, /fileIndex = 1/);
  assert.match(labels[1].text, /fileIndex = 2/);
  assert.match(labels[2].text, /fileIndex = 3/);
  assert.equal(labels.some((part) => part.text.includes('sourcePackageId')), false);
  assert.equal(labels.some((part) => part.text.includes('sourceFileId')), false);
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
  assert.equal(
    kayraItineraryExtractionPromptVersion,
    'kayra_itinerary_extraction_v2_4',
  );
  assert.match(kayraItineraryExtractionPrompt, /never invent/i);
  assert.match(
    kayraItineraryExtractionPrompt,
    /Capture each itinerary-relevant operational fact once/,
  );
  assert.equal(
    /Preserve every distinct factual supplier detail/i.test(
      kayraItineraryExtractionPrompt,
    ),
    false,
  );
  assert.equal(
    /Do not summarize away facts/i.test(kayraItineraryExtractionPrompt),
    false,
  );
  assert.match(kayraItineraryExtractionPrompt, /consolidate repeated mentions/i);
  assert.match(kayraItineraryExtractionPrompt, /pickup and\s+dropoff/i);
  assert.match(kayraItineraryExtractionPrompt, /either activity or sightseeing/i);
  assert.match(kayraItineraryExtractionPrompt, /never\s+standalone services/i);
  assert.match(kayraItineraryExtractionPrompt, /Narrative paragraphs.*headings/i);
  assert.match(kayraItineraryExtractionPrompt, /Supplier marketing prose/i);
  assert.match(kayraItineraryExtractionPrompt, /Destination promotional prose/i);
  assert.match(kayraItineraryExtractionPrompt, /Use other only for a genuine/i);
  assert.match(kayraItineraryExtractionPrompt, /omit unavailable optional/i);
  assert.match(
    kayraItineraryExtractionPrompt,
    /omit list properties when the list\s+would be empty/i,
  );
  assert.match(kayraItineraryExtractionPrompt, /only the detail object applicable/i);
  assert.match(kayraItineraryExtractionPrompt, /reviewIssues/);
  assert.match(kayraItineraryExtractionPrompt, /supplier pricing and costs/i);
  assert.match(kayraItineraryExtractionPrompt, /Flights and visa are outside/i);
  assert.match(kayraItineraryExtractionPrompt, /first structured/i);
  assert.equal(kayraItineraryExtractionPrompt.includes('@kholidaymaps.com'), false);
  assert.equal(kayraItineraryExtractionPrompt.includes('Test Client'), false);
});

test('V2.4 prompt protects explicit day dates and temporal attribution', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /explicitly gives an unambiguous calendar date[\s\S]*day's date property/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Do not leave an explicit date only in[\s\S]*day title/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Do not derive dates from sequence, neighboring days, or Trip[\s\S]*data/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /time belongs only to the event or service explicitly associated/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /airport or flight arrival time to a transfer's[\s\S]*startTime/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /hotel check-in time to an unrelated activity/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /contextual time once in day\.summary or a relevant service description/i,
  );
});

test('V2.4 prompt separates structured dates from day-title generation', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /Preserve meaningful supplier-provided day title text/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /date is already[\s\S]*stored in date[\s\S]*do not mechanically repeat it/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /actual supplier heading that genuinely includes its date may remain intact/i,
  );
});

test('V2.4 prompt requires a source-supported or neutral root title', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /Preserve an explicit supplier itinerary or package title/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /When none exists[\s\S]*factually neutral root title/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /destinations and an explicitly supplied duration/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Never invent a package[\s\S]*or tourism or marketing language/i,
  );
});

test('V2.4 prompt preserves operational qualifiers exactly once', () => {
  for (const qualifier of [
    'ticket only',
    'payable locally',
    'standard class',
    'SIC or shared basis',
    'subject\\s+to availability',
  ]) {
    assert.match(kayraItineraryExtractionPrompt, new RegExp(qualifier, 'i'));
  }
  assert.match(
    kayraItineraryExtractionPrompt,
    /Preserve each short operational restriction or qualifier once/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /typed detail field[\s\S]*inclusion or exclusion[\s\S]*description or note/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Do not repeat the qualifier across title, description, notes, inclusions/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /service title inherently contains the[\s\S]*qualifier[\s\S]*do not repeat it elsewhere/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Otherwise preserve[\s\S]*once in the most appropriate existing field/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Pricing values and commercial[\s\S]*terms remain excluded/i,
  );
});

test('V2.4 prompt distinguishes covered stays from uncertain accommodation', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /continuous[\s\S]*hotel stay or check-in\/check-out span[\s\S]*1-4 February/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /intervening nights without a missing-accommodation warning/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /hotel mentioned[\s\S]*only on Day 1 without a stated stay span/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /chronology requires that assumption[\s\S]*warning reviewIssue/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /instead of inventing another hotel service/i,
  );
});

test('V2.4 prompt permits only source-supported hotel stay dates', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /hotelDetails\.checkInDate or checkOutDate only when the source[\s\S]*explicitly states/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /explicit source-provided[\s\S]*stay span establishes it/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /dated itinerary day containing only an overnight[\s\S]*does not[\s\S]*establish a hotel check-in/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Do not[\s\S]*derive hotel dates from a day date, neighboring days, nights count, chronology/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /later hotel departure, or Trip data/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /reviewIssue mechanism for uncertain accommodation continuity/i,
  );
});

test('V2.4 extraction rules are supplier and destination agnostic', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /semantic meaning across any supplier, file layout, or[\s\S]*destination/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Do not depend on exact benchmark wording/i,
  );
  for (const benchmarkText of [
    'France',
    'Switzerland',
    'Paris',
    'Basel',
    'Disneyland',
    'Eiffel Tower',
    'Standard Sedan',
    'Swiss Pass',
  ]) {
    assert.equal(kayraItineraryExtractionPrompt.includes(benchmarkText), false);
  }
});

test('V2.4 prompt requests optional compact PDF page provenance', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /For PDF evidence[\s\S]*source\.sourceLabel[\s\S]*Page N/i,
  );
  assert.match(kayraItineraryExtractionPrompt, /Page 1 or Page 2/);
  assert.match(
    kayraItineraryExtractionPrompt,
    /Omit sourceLabel rather than inventing a page number when uncertain/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Never emit a package ID or source file ID/i,
  );
  assert.match(kayraItineraryExtractionPrompt, /1-based fileIndex/i);
});

test('V2.4 prompt requires source-supported transfer basis', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /vehicle class or[\s\S]*model belongs in vehicleType[\s\S]*never establishes private/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /travel pass does not make a movement scheduled/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /transferType to private, shared, or scheduled only when[\s\S]*explicit/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /explicit SIC or shared wording supports[\s\S]*shared/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /explicit[\s\S]*private transfer wording supports private/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /omit transferType, or use[\s\S]*other only if a value is required/i,
  );
});

test('V2.4 prompt classifies traveller train movement once as transfer', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /traveller movement from an origin to a destination by train[\s\S]*one transfer service/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Preserve[\s\S]*origin, destination, time, and travel class/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /transport[\s\S]*pass or ticket product is not itself a transfer/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Never[\s\S]*duplicate one journey as both transfer and other/i,
  );
});

test('V2.4 prompt keeps activity type separate from operating basis', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /activityDetails\.activityType describes the kind of activity/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Never put SIC, shared, or private[\s\S]*in activityType/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /operating basis[\s\S]*preserve it once in description[\s\S]*or notes/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Genuine source-supported activity types remain allowed/i,
  );
});

test('V2.4 prompt separates review uncertainty from supplier notes', () => {
  assert.match(
    kayraItineraryExtractionPrompt,
    /extraction uncertainty[\s\S]*only in[\s\S]*reviewIssues/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Do not repeat it verbatim or semantically in day notes or[\s\S]*service notes/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /Actual supplier notes remain allowed/i,
  );
  assert.match(
    kayraItineraryExtractionPrompt,
    /subject-to-availability condition once[\s\S]*without[\s\S]*reviewIssue solely/i,
  );
});

test('request uses the exact model and controlled JSON schema once', async () => {
  const f = fixture();
  await f.provider.extract(input([sourceFile('file-1', 'application/pdf')]));
  assert.equal(f.calls.length, 1);
  const request = f.calls[0];
  assert.equal(geminiItineraryModel, 'gemini-3.5-flash');
  assert.equal(geminiVertexLocation, 'global');
  assert.equal(request.model, 'gemini-3.5-flash');
  assert.equal(request.config.systemInstruction, kayraItineraryExtractionPrompt);
  assert.equal(request.config.responseMimeType, 'application/json');
  assert.equal(request.config.responseJsonSchema, kayraItineraryExtractionResponseSchema);
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
  assert.equal('temperature' in request.config, false);
  assert.equal('topK' in request.config, false);
  assert.equal('topP' in request.config, false);
  assert.equal('tools' in request.config, false);
});

test('successful call logs safe source, timing, candidate and usage metadata', async () => {
  const pdf = sourceFile('file-1', 'application/pdf');
  const csv = sourceFile('file-2', 'text/csv');
  pdf.sizeBytes = 125;
  csv.sizeBytes = 75;
  const f = fixture({
    response: {
      text: validJson,
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

  assert.equal(f.calls.length, 1);
  const requested = f.logs.find((log) =>
    log.event === 'itinerary-extraction-provider-requested');
  assert.equal(requested.model, 'gemini-3.5-flash');
  assert.equal(requested.promptVersion, 'kayra_itinerary_extraction_v2_4');
  assert.equal(requested.fileCount, 2);
  assert.deepEqual(requested.mimeTypes, ['application/pdf', 'text/csv']);
  assert.deepEqual(requested.fileSizesBytes, [125, 75]);
  assert.equal(requested.totalSourceBytes, 200);
  assert.deepEqual(requested.inputModes, [
    'private-gcs-uri', 'bounded-inline-text',
  ]);
  assert.equal(requested.thinkingLevel, 'LOW');
  assert.equal(Number.isNaN(Date.parse(requested.providerStartedAt)), false);

  const completed = f.logs.find((log) =>
    log.event === 'itinerary-extraction-provider-completed');
  assert.equal(Number.isInteger(completed.providerDurationMs), true);
  assert.ok(completed.providerDurationMs >= 0);
  assert.equal(completed.candidateCount, 1);
  assert.equal(completed.finishReason, 'STOP');
  assert.equal(completed.promptTokenCount, 100);
  assert.equal(completed.candidatesTokenCount, 20);
  assert.equal(completed.thoughtsTokenCount, 30);
  assert.equal(completed.cachedContentTokenCount, 2);
  assert.equal(completed.toolUsePromptTokenCount, 0);
  assert.equal(completed.totalTokenCount, 150);
  assert.equal(completed.trafficType, 'ON_DEMAND');
  assert.deepEqual(completed.cacheTokensDetails, [
    {modality: 'TEXT', tokenCount: 2},
  ]);
  assert.deepEqual(completed.promptTokensDetails, [
    {modality: 'DOCUMENT', tokenCount: 100},
  ]);
  assert.deepEqual(completed.candidatesTokensDetails, [
    {modality: 'TEXT', tokenCount: 20},
  ]);
  assert.deepEqual(completed.toolUsePromptTokensDetails, []);
  assert.equal('responseUtf8Bytes' in completed, false);
});

test('MAX_TOKENS logs only quote-aware aggregate structure diagnostics',
  async () => {
    const truncated = [
      '{"title":"SECRET café ✈️ services description source",',
      '"days":[{"title":"Day","services":[',
      '{"type":"hotel",',
      '"description":"services type description source notes hotelDetails",',
      '"notes":"SECRET SOURCE TEXT",',
      '"inclusions":["SECRET"],"exclusions":["SECRET"],',
      '"hotelDetails":{"hotelName":"SECRET HOTEL"},',
      '"source":{"fileIndex":1}},',
      '{"type":"transfer","transferDetails":{',
      '"pickup":"SECRET PICKUP","dropoff":"SECRET DROPOFF"}}],',
      '"notes":"SECRET DAY NOTE"}],',
      '"reviewIssues":[{"fieldPath":"days[0]",',
      '"message":"SECRET arbitrary exception message private.pdf ',
      'gs://secret-bucket/private/source.pdf"',
    ].join('');
    const f = fixture({
      response: {
        text: truncated,
        candidates: [{finishReason: 'MAX_TOKENS'}],
        usageMetadata: {candidatesTokenCount: 16_367},
      },
    });

    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
      providerCode('PROVIDER_EXECUTION_FAILED'),
    );

    assert.equal(f.calls.length, 1);
    const completed = f.logs.find((log) =>
      log.event === 'itinerary-extraction-provider-completed');
    assert.equal(completed.finishReason, 'MAX_TOKENS');
    assert.equal(completed.responseCharacterCount, [...truncated].length);
    assert.equal(completed.responseUtf8Bytes, Buffer.byteLength(truncated, 'utf8'));
    assert.equal(completed.startsWithObjectBrace, true);
    assert.equal(completed.endsWithObjectBrace, false);
    assert.equal(completed.keyCountDays, 1);
    assert.equal(completed.keyCountServices, 1);
    assert.equal(completed.keyCountType, 2);
    assert.equal(completed.keyCountFieldPath, 1);
    assert.equal(completed.keyCountHotelDetails, 1);
    assert.equal(completed.keyCountTransferDetails, 1);
    assert.equal(completed.keyCountActivityDetails, 0);
    assert.equal(completed.keyCountDescription, 1);
    assert.equal(completed.keyCountNotes, 2);
    assert.equal(completed.keyCountInclusions, 1);
    assert.equal(completed.keyCountExclusions, 1);
    assert.equal(completed.keyCountSource, 1);

    const serializedLogs = JSON.stringify(f.logs);
    for (const secret of [
      'SECRET',
      'café',
      'arbitrary exception message',
      'private.pdf',
      'gs://secret-bucket/private/source.pdf',
      truncated,
      kayraItineraryExtractionPrompt,
    ]) {
      assert.equal(serializedLogs.includes(secret), false, `leaked ${secret}`);
    }
  });

test('missing usage and candidate metadata does not fail extraction', async () => {
  const f = fixture({response: {text: validJson}});
  assert.deepEqual(
    await f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
    JSON.parse(validJson),
  );
  const completed = f.logs.find((log) =>
    log.event === 'itinerary-extraction-provider-completed');
  assert.equal(completed.candidateCount, null);
  assert.equal(completed.finishReason, null);
  assert.equal('promptTokenCount' in completed, false);
});

test('provider failure logs only a stable category and elapsed duration', async () => {
  const f = fixture({clientError: new Error('SECRET PROVIDER BODY')});
  await assert.rejects(
    f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
    providerCode('PROVIDER_EXECUTION_FAILED'),
  );
  const failed = f.logs.at(-1);
  assert.equal(failed.event, 'itinerary-extraction-provider-failed');
  assert.equal(failed.model, 'gemini-3.5-flash');
  assert.equal(failed.category, 'PROVIDER_EXECUTION_FAILED');
  assert.equal(Number.isInteger(failed.providerDurationMs), true);
  assert.ok(failed.providerDurationMs >= 0);
  assert.equal(JSON.stringify(f.logs).includes('SECRET PROVIDER BODY'), false);
});

for (const scenario of [
  {httpStatus: 400, rpcStatus: 'INVALID_ARGUMENT'},
  {httpStatus: 403, rpcStatus: 'PERMISSION_DENIED', statusCodeShape: true},
  {httpStatus: 429, rpcStatus: 'RESOURCE_EXHAUSTED'},
  {httpStatus: 503, rpcStatus: 'UNAVAILABLE', statusCodeShape: true},
]) {
  test(`${scenario.httpStatus} / ${scenario.rpcStatus} is safely classified`,
    async () => {
      const rawMessage = JSON.stringify({
        error: {
          code: scenario.httpStatus,
          status: scenario.rpcStatus,
          message: 'SECRET API DETAIL ' + kayraItineraryExtractionPrompt +
            ' gs://secret-bucket/private/source.pdf',
        },
      });
      const sdkError = scenario.statusCodeShape ?
        Object.assign(new Error(rawMessage), {
          name: scenario.httpStatus === 403 ?
            'PermissionDeniedError' : 'InternalServerError',
          statusCode: scenario.httpStatus,
        }) :
        new ApiError({status: scenario.httpStatus, message: rawMessage});
      sdkError.stack = 'SECRET STACK TRACE WITH REQUEST CONTENT';
      const f = fixture({clientError: sdkError});

      await assert.rejects(
        f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
        providerCode('PROVIDER_EXECUTION_FAILED'),
      );

      assert.equal(f.calls.length, 1);
      const failed = f.logs.at(-1);
      assert.equal(failed.event, 'itinerary-extraction-provider-failed');
      assert.equal(failed.providerHttpStatus, scenario.httpStatus);
      assert.equal(failed.providerRpcStatus, scenario.rpcStatus);
      assert.equal(
        failed.providerFailureCategory,
        scenario.rpcStatus.toLowerCase(),
      );
      const serializedLogs = JSON.stringify(f.logs);
      for (const secret of [
        rawMessage,
        'SECRET API DETAIL',
        'SECRET STACK TRACE',
        kayraItineraryExtractionPrompt,
        'gs://secret-bucket/private/source.pdf',
      ]) {
        assert.equal(serializedLogs.includes(secret), false);
      }
    });
}

test('unknown SDK failure is classified generically without raw diagnostics',
  async () => {
    const sdkError = new Error(
      'SECRET UNKNOWN SDK ERROR with source and request content',
    );
    sdkError.name = 'MysterySdkFailure';
    sdkError.stack = 'SECRET UNKNOWN STACK';
    const f = fixture({clientError: sdkError});

    await assert.rejects(
      f.provider.extract(input([sourceFile('file-1', 'application/pdf')])),
      providerCode('PROVIDER_EXECUTION_FAILED'),
    );

    assert.equal(f.calls.length, 1);
    const failed = f.logs.at(-1);
    assert.equal(failed.providerErrorName, 'unknown');
    assert.equal(failed.providerFailureCategory, 'unknown');
    assert.equal('providerHttpStatus' in failed, false);
    assert.equal('providerRpcStatus' in failed, false);
    assert.equal('providerErrorCode' in failed, false);
    const serializedLogs = JSON.stringify(f.logs);
    assert.equal(serializedLogs.includes('SECRET UNKNOWN SDK ERROR'), false);
    assert.equal(serializedLogs.includes('SECRET UNKNOWN STACK'), false);
  });

test('provider logs omit request and response content identities', async () => {
  const csv = sourceFile('file-1', 'text/csv');
  csv.originalFileName = 'SECRET SUPPLIER QUOTE.csv';
  const f = fixture({
    csvText: 'SECRET SOURCE DOCUMENT TEXT',
    response: {
      text: JSON.stringify({
        title: 'SECRET PROVIDER OUTPUT',
        days: [],
        reviewIssues: [],
      }),
    },
  });
  await f.provider.extract(input([csv]));

  const serializedLogs = JSON.stringify(f.logs);
  for (const secret of [
    'SECRET SUPPLIER QUOTE',
    'SECRET SOURCE DOCUMENT TEXT',
    'SECRET PROVIDER OUTPUT',
    csv.sourceFileId,
    csv.storagePath,
    `gs://kayra-crm-v1.firebasestorage.app/${csv.storagePath}`,
    kayraItineraryExtractionPrompt,
  ]) {
    assert.equal(serializedLogs.includes(secret), false);
  }
});

test('schema mirrors provider-controlled Dart and TypeScript values', () => {
  const root = kayraItineraryExtractionResponseSchema;
  assert.deepEqual(Object.keys(root.properties), ['title', 'days', 'reviewIssues']);
  for (const backendField of [
    'id', 'tripId', 'sourcePackageIds', 'createdByUid', 'createdAt', 'updatedAt',
  ]) {
    assert.equal(backendField in root.properties, false);
  }
  assert.deepEqual(root.required, ['title', 'days']);
  const day = root.properties.days.items;
  assert.deepEqual(day.required, ['title']);
  const service = day.properties.services.items;
  assert.equal(service.type, 'object');
  assert.equal('anyOf' in service, false);
  assert.equal('oneOf' in service, false);
  assert.deepEqual(service.required, ['type']);
  assert.deepEqual(service.properties.type.enum, [...geminiServiceTypes]);
  assert.deepEqual(
    service.properties.transferDetails.properties.transferType.enum,
    [...geminiTransferTypes],
  );
  assert.deepEqual(
    root.properties.reviewIssues.items.properties.severity.enum,
    [...geminiReviewSeverities],
  );
  assert.equal(root.additionalProperties, false);
  assert.equal(service.additionalProperties, false);
  assert.equal('id' in service.properties, false);
  assert.equal('dayNumber' in day.properties, false);
  assert.equal('id' in root.properties.reviewIssues.items.properties, false);
  assert.deepEqual(
    service.properties.source.properties,
    {
      fileIndex: {type: 'integer', minimum: 1},
      sourceLabel: {type: 'string'},
    },
  );
  assert.deepEqual(service.properties.hotelDetails.required, ['hotelName']);
  assert.deepEqual(
    service.properties.transferDetails.required,
    ['pickup', 'dropoff'],
  );
  assert.deepEqual(
    service.properties.activityDetails.required,
    ['activityName'],
  );
  for (const optional of [
    'title', 'description', 'startTime', 'endTime', 'location', 'city',
    'inclusions', 'exclusions', 'notes', 'hotelDetails', 'transferDetails',
    'activityDetails', 'source',
  ]) {
    assert.equal(service.required.includes(optional), false);
  }
  for (const schema of [
    root,
    day,
    service,
    service.properties.hotelDetails,
    service.properties.transferDetails,
    service.properties.activityDetails,
    service.properties.source,
    root.properties.reviewIssues.items,
  ]) {
    assert.ok(Array.isArray(schema.propertyOrdering));
  }
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
