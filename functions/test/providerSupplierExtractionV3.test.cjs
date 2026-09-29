const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  normalizeProviderSupplierExtractionV3,
  supplierExtractionV3ProviderVersion,
} = require('../lib/itineraryExtraction/providerSupplierExtractionV3');
const {
  kayraSupplierExtractionV3ResponseSchema,
} = require('../lib/itineraryExtraction/geminiStagingProviderSchema');
const {
  kayraSupplierExtractionV3Prompt,
  kayraSupplierExtractionV3PromptVersion,
} = require('../lib/itineraryExtraction/geminiStagingProviderPrompt');
const {
  SupplierExtractionSnapshotError,
  assertSupplierExtractionSnapshotInvariants,
} = require('../lib/itineraryExtraction/supplierExtractionValidation');

const invalidExtraction = (error) =>
  error instanceof SupplierExtractionSnapshotError &&
  error.code === 'INVALID_SUPPLIER_EXTRACTION';

function sourceFile(sourceFileId, extension = 'pdf') {
  return {
    sourceFileId,
    packageId: 'package-v3',
    originalFileName: `${sourceFileId}.${extension}`,
    storagePath: `trips/trip-v3/supplier_sources/${sourceFileId}/source.${extension}`,
    contentType: extension === 'txt' ? 'text/plain' : 'application/pdf',
    sizeBytes: 200,
    uploadedByUid: 'agent-v3',
  };
}

function trustedPackage(fileIds = ['source-a', 'source-b']) {
  return {
    tripId: 'trip-v3',
    packageId: 'package-v3',
    supplierId: 'supplier-v3',
    supplierNameSnapshot: 'Synthetic Supplier',
    files: fileIds.map((id, index) => sourceFile(id, index === 0 ? 'pdf' : 'txt')),
  };
}

function context(packageValue = trustedPackage()) {
  return {
    extractionId: 'extraction-v3',
    tripId: 'trip-v3',
    sourcePackageId: 'package-v3',
    jobId: 'job-v3',
    requestedByUid: 'agent-v3',
    createdAt: new Date('2026-09-29T08:00:00.000Z'),
    trustedPackage: packageValue,
  };
}

function normalize(payload, contextValue = context()) {
  return normalizeProviderSupplierExtractionV3(payload, contextValue);
}

function title(text = 'Source itinerary') {
  return {
    text,
    basis: 'explicit_supplier',
    sources: [{fileIndex: 1, sourceLabel: 'Page 1'}],
  };
}

function facts(snapshot, kind) {
  return snapshot.facts.filter((fact) => fact.factKind === kind);
}

test('V3 has a separate version and accepts a sparse zero-day response', () => {
  const snapshot = normalize({}, {
    ...context(),
    providerVersion: 'provider-controlled-version',
  });

  assert.equal(
    supplierExtractionV3ProviderVersion,
    'kayra_itinerary_extraction_v3_staging',
  );
  assert.equal(kayraSupplierExtractionV3PromptVersion, supplierExtractionV3ProviderVersion);
  assert.equal(snapshot.providerVersion, supplierExtractionV3ProviderVersion);
  assert.equal(snapshot.title.text, 'Supplier itinerary');
  assert.equal(snapshot.title.basis, 'neutral_supported');
  assert.equal(snapshot.days.length, 0);
  assert.equal(snapshot.facts.length, 0);
  assert.deepEqual(snapshot.counts, {
    days: 0,
    assignedServices: 0,
    unassignedServices: 0,
    packageFacts: 0,
    ancillaryFlights: 0,
    ancillaryVisas: 0,
    commercialIndicators: 0,
    reviewIssues: 0,
  });
  assert(Object.isFrozen(snapshot));
});

test('detailed ten-day chronology keeps assigned services and trusted provenance', () => {
  const days = Array.from({length: 10}, (_, index) => ({
    sourceDayNumber: index + 1,
    date: `2027-04-${String(index + 1).padStart(2, '0')}`,
    title: `Source day ${index + 1}`,
    sources: [{fileIndex: index < 5 ? 1 : 2, sourceLabel: `Section ${index + 1}`}],
    services: [{
      type: index % 2 === 0 ? 'transfer' : 'sightseeing',
      title: `Service ${index + 1}`,
      ...(index % 2 === 0 ? {
        transferDetails: {pickup: 'Origin', dropoff: 'Destination'},
      } : {}),
      sources: [{fileIndex: index < 5 ? 1 : 2}],
    }],
  }));
  const snapshot = normalize({title: title('Ten-day itinerary'), days});

  assert.equal(snapshot.counts.days, 10);
  assert.equal(snapshot.counts.assignedServices, 10);
  assert.equal(snapshot.days[9].date, '2027-04-10');
  assert.equal(snapshot.days[0].id, 'staged-day-1');
  assert.equal(snapshot.days[9].id, 'staged-day-10');
  assert.equal(snapshot.days[9].assignedServiceIds[0], 'staged-service-10');
  assert.equal(snapshot.days[0].sources[0].supplierSourceFileId, 'source-a');
  assert.equal(snapshot.days[9].sources[0].supplierSourceFileId, 'source-b');
});

test('narrative source separates daily services, global hotel, and flight facts', () => {
  const snapshot = normalize({
    title: title('Narrative itinerary'),
    days: [{
      sourceDayNumber: 1,
      title: 'Arrival and city visit',
      summary: 'Arrival followed by the stated afternoon programme.',
      services: [
        {
          type: 'transfer',
          title: 'Arrival transfer',
          transferDetails: {pickup: 'Airport', dropoff: 'City hotel'},
        },
        {
          type: 'activity',
          activityDetails: {activityName: 'Guided city walk', duration: 'Two hours'},
        },
        {type: 'meal', title: 'Welcome dinner'},
      ],
    }],
    packageFacts: {
      accommodations: [{
        hotelName: 'Example Hotel',
        city: 'Example City',
        orSimilar: true,
        mealPlan: 'Breakfast',
      }],
    },
    ancillaryFacts: {
      flights: [{
        airline: 'Example Air',
        flightNumber: 'EA 100',
        origin: 'AAA',
        destination: 'BBB',
      }],
    },
  });

  assert.equal(snapshot.counts.assignedServices, 3);
  assert.equal(snapshot.counts.packageFacts, 1);
  assert.equal(snapshot.counts.ancillaryFlights, 1);
  assert.equal(facts(snapshot, 'flight').length, 1);
  assert.equal(facts(snapshot, 'service').some((fact) => fact.serviceType === 'other'), false);
});

test('table-style source preserves scoped facts and isolates commercial presence', () => {
  const snapshot = normalize({
    title: title('Table itinerary'),
    days: [{
      sourceDayNumber: 2,
      date: '2027-06-02',
      title: 'Regional tour',
      services: [{type: 'sightseeing', title: 'Full-day regional tour'}],
    }],
    packageFacts: {
      accommodations: [{hotelName: 'Table Hotel', roomType: 'Twin room'}],
      inclusions: [
        {category: 'meal', text: 'Five breakfasts', quantity: 5},
        {category: 'guide', text: 'Guide service included'},
      ],
      exclusions: [{category: 'entrance', text: 'Entrance tickets excluded'}],
    },
    commercialContent: {
      present: true,
      categories: ['package_price', 'supplement'],
      sources: [{fileIndex: 2, sourceLabel: 'Commercial table'}],
    },
  });

  assert.equal(snapshot.counts.packageFacts, 4);
  assert.deepEqual(facts(snapshot, 'commercial_presence')[0].categories, [
    'package_price', 'supplement',
  ]);
  assert.equal(JSON.stringify(snapshot).includes('amount'), false);
  assert.equal(JSON.stringify(snapshot).includes('currency'), false);
});

test('plain-text package preserves multiple services without inventing chronology', () => {
  const services = [
    'City tour',
    'Mountain excursion',
    'Museum visit',
    'Full-day regional tour',
  ].map((name) => ({type: 'sightseeing', title: name}));
  const snapshot = normalize({
    title: title('Four-night package'),
    unassignedServices: services,
    packageFacts: {
      accommodations: [{hotelName: 'Package Hotel', nightCount: 4}],
      inclusions: [{category: 'transport', text: 'Package transport included'}],
    },
    reviewIssues: [{
      code: 'chronology_unknown',
      severity: 'blocker',
      message: 'The source does not assign services to days.',
      target: {kind: 'snapshot'},
      resolutionRequired: true,
    }],
  });

  assert.equal(snapshot.days.length, 0);
  assert.equal(snapshot.counts.unassignedServices, 4);
  assert(facts(snapshot, 'service').every((fact) => fact.scope.kind === 'unassigned'));
  assert.equal(snapshot.reviewIssues[0].target.kind, 'snapshot');
});

test('screenshot-like source keeps semantic labels without layout assumptions', () => {
  const snapshot = normalize({
    title: title(),
    unassignedServices: [{
      type: 'activity',
      title: 'Evening performance',
      sources: [{fileIndex: 1, sourceLabel: 'Image region 1'}],
    }],
  });

  assert.equal(
    facts(snapshot, 'service')[0].sources[0].sourceLabel,
    'Image region 1',
  );
  assert.throws(
    () => normalize({
      title: title(),
      unassignedServices: [{
        title: 'Tour',
        sources: [{fileIndex: 1, sourceLabel: 'Line 1\nLine 2'}],
      }],
    }),
    invalidExtraction,
  );
});

test('global hotel keeps explicit nights without fabricated stay dates', () => {
  const snapshot = normalize({
    title: title(),
    packageFacts: {
      accommodations: [{
        hotelName: 'Global Hotel',
        city: 'Example City',
        orSimilar: true,
        nightCount: 4,
        roomType: 'Standard room',
        mealPlan: 'Breakfast',
        numberOfRooms: 2,
        supplierStarRating: 'Four star',
      }],
    },
  });
  const accommodation = facts(snapshot, 'package_accommodation')[0];

  assert.equal(accommodation.details.nightCount, 4);
  assert.equal(accommodation.details.checkInDate, null);
  assert.equal(accommodation.details.checkOutDate, null);
});

test('flight stays structured and ancillary rather than becoming a service', () => {
  const snapshot = normalize({
    title: title(),
    ancillaryFacts: {
      flights: [{
        airline: 'Example Air',
        flightNumber: 'EA 201',
        origin: 'AAA',
        destination: 'BBB',
        departureDate: '2027-07-01',
        departureTime: '09:15',
        arrivalDate: '2027-07-01',
        arrivalTime: '11:45',
        cabinClass: 'Economy',
        notes: 'Connection subject to schedule confirmation',
        sources: [{fileIndex: 1, sourceLabel: 'Page 3'}],
      }],
    },
  });
  const flight = facts(snapshot, 'flight')[0];

  assert.equal(flight.scope.kind, 'ancillary');
  assert.equal(flight.departureTime, '09:15');
  assert.equal(facts(snapshot, 'service').length, 0);
});

test('visa semantic facts are accepted while visa prices are rejected', () => {
  const snapshot = normalize({
    title: title(),
    ancillaryFacts: {
      visas: [
        {disposition: 'included'},
        {disposition: 'requirement', text: 'Passport copy required'},
      ],
    },
  });
  assert.deepEqual(facts(snapshot, 'visa').map((fact) => fact.disposition), [
    'included', 'requirement',
  ]);

  for (const visa of [
    {disposition: 'included', price: 30},
    {disposition: 'included', text: 'Visa included for USD 30'},
  ]) {
    assert.throws(
      () => normalize({title: title(), ancillaryFacts: {visas: [visa]}}),
      invalidExtraction,
    );
  }
});

test('commercial isolation accepts presence only and rejects values or pricing text', () => {
  const valid = normalize({
    title: title(),
    commercialContent: {
      present: true,
      categories: ['per_person_price', 'payment_terms'],
    },
  });
  assert.equal(valid.counts.commercialIndicators, 1);

  for (const payload of [
    {commercialContent: {present: true, categories: ['package_price'], amount: 200}},
    {commercialContent: {present: true, categories: ['package_price'], currency: 'USD'}},
    {unassignedServices: [{title: 'Tour price USD 200'}]},
    {packageFacts: {inclusions: [{category: 'visa', text: 'Visa cost is 30 USD'}]}},
  ]) {
    assert.throws(() => normalize({title: title(), ...payload}), invalidExtraction);
  }
});

test('provider provenance maps trusted single and multi-file sources', () => {
  const single = trustedPackage(['only-file']);
  const singleSnapshot = normalize({
    unassignedServices: [{title: 'Dinner'}],
  }, context(single));
  assert.equal(
    facts(singleSnapshot, 'service')[0].sources[0].supplierSourceFileId,
    'only-file',
  );

  const multiSnapshot = normalize({
    title: title(),
    unassignedServices: [{
      title: 'Dinner',
      sources: [{fileIndex: 2, sourceLabel: 'Message 1'}],
    }],
  });
  assert.equal(
    facts(multiSnapshot, 'service')[0].sources[0].supplierSourceFileId,
    'source-b',
  );

  for (const source of [
    {fileIndex: 0},
    {fileIndex: 3},
    {sourceFileId: 'source-a'},
    {sourcePackageId: 'package-v3'},
    {storagePath: 'private/path'},
  ]) {
    assert.throws(
      () => normalize({
        title: title(),
        unassignedServices: [{title: 'Dinner', sources: [source]}],
      }),
      invalidExtraction,
    );
  }
  assert.throws(
    () => normalize({
      title: title(),
      unassignedServices: [{
        title: 'Dinner',
        sources: [{fileIndex: 1}, {fileIndex: 1}],
      }],
    }),
    invalidExtraction,
  );
});

test('review targets resolve every supported local reference to backend IDs', () => {
  const snapshot = normalize({
    title: title(),
    days: [{title: 'Day', services: [{type: 'meal', title: 'Lunch'}]}],
    unassignedServices: [{type: 'sightseeing', title: 'Tour'}],
    packageFacts: {
      accommodations: [{hotelName: 'Hotel'}],
      inclusions: [{category: 'water', text: 'Water included'}],
      exclusions: [{category: 'entrance', text: 'Entry excluded'}],
      conditions: [{kind: 'operating_basis', value: 'Shared basis'}],
    },
    ancillaryFacts: {
      flights: [{flightNumber: 'EA 1'}],
      visas: [{disposition: 'excluded'}],
    },
    reviewIssues: [
      {
        code: 'other', severity: 'warning', message: 'Review day.',
        target: {kind: 'day', dayIndex: 1}, resolutionRequired: false,
      },
      {
        code: 'other', severity: 'warning', message: 'Review assigned service.',
        target: {kind: 'service', scope: 'day', dayIndex: 1, serviceIndex: 1},
        resolutionRequired: false,
      },
      {
        code: 'chronology_unknown', severity: 'blocker', message: 'Assign service.',
        target: {kind: 'service', scope: 'unassigned', serviceIndex: 1},
        resolutionRequired: true,
      },
      {
        code: 'global_mapping_required', severity: 'blocker', message: 'Map hotel.',
        target: {kind: 'package_fact', factType: 'accommodation', factIndex: 1},
        resolutionRequired: true,
      },
      {
        code: 'other', severity: 'warning', message: 'Review flight.',
        target: {kind: 'ancillary_fact', factType: 'flight', factIndex: 1},
        resolutionRequired: false,
      },
    ],
  });

  assert.deepEqual(snapshot.reviewIssues.map((issue) => issue.target.entityId), [
    'staged-day-1',
    'staged-service-1',
    'staged-service-2',
    'package-fact-1',
    'ancillary-flight-1',
  ]);

  for (const target of [
    {kind: 'day', dayIndex: 2},
    {kind: 'service', scope: 'day', dayIndex: 1, serviceIndex: 2},
    {kind: 'package_fact', factType: 'flight', factIndex: 1},
    {kind: 'ancillary_fact', factType: 'accommodation', factIndex: 1},
    {kind: 'snapshot', entityId: 'provider-id'},
  ]) {
    assert.throws(
      () => normalize({
        title: title(),
        days: [{title: 'Day', services: [{title: 'Service'}]}],
        reviewIssues: [{
          code: 'other', severity: 'warning', message: 'Invalid target.',
          target, resolutionRequired: false,
        }],
      }),
      invalidExtraction,
    );
  }
});

test('service typed details remain compatible with their service type', () => {
  const valid = normalize({
    title: title(),
    unassignedServices: [
      {type: 'hotel', hotelDetails: {hotelName: 'Hotel'}},
      {type: 'transfer', transferDetails: {pickup: 'A', dropoff: 'B'}},
      {type: 'activity', activityDetails: {activityName: 'Tour'}},
    ],
  });
  assert.deepEqual(facts(valid, 'service').map((fact) => fact.serviceType), [
    'hotel', 'transfer', 'activity',
  ]);

  for (const service of [
    {type: 'meal', title: 'Meal', hotelDetails: {hotelName: 'Hotel'}},
    {type: 'hotel', title: 'Hotel', transferDetails: {pickup: 'A'}},
    {type: 'transfer', title: 'Transfer', activityDetails: {activityName: 'Tour'}},
  ]) {
    assert.throws(
      () => normalize({title: title(), unassignedServices: [service]}),
      invalidExtraction,
    );
  }
});

test('unknown properties, trusted IDs, timestamps, and malformed values are rejected', () => {
  const payloads = [
    {title: title(), tripId: 'trip-v3'},
    {title: {...title(), sourcePackageId: 'package-v3'}},
    {title: title(), createdAt: '2026-01-01T00:00:00.000Z'},
    {title: title(), days: [{title: 'Day', id: 'provider-day'}]},
    {title: title(), days: [{title: 'Day', date: '2027-02-30'}]},
    {title: title(), unassignedServices: [{title: 'Tour', startTime: '9:30'}]},
    {title: title(), unassignedServices: [{type: 'unknown', title: 'Tour'}]},
    {
      title: title(),
      reviewIssues: [{
        code: 'other', severity: 'critical', message: 'Bad severity.',
        target: {kind: 'snapshot'}, resolutionRequired: true,
      }],
    },
  ];
  for (const payload of payloads) {
    assert.throws(() => normalize(payload), invalidExtraction);
  }
});

test('equivalent provider input and trusted context produce deterministic output', () => {
  const payload = {
    title: title(),
    days: [{title: 'Day', services: [{type: 'meal', title: 'Lunch'}]}],
    unassignedServices: [{type: 'sightseeing', title: 'Tour'}],
    packageFacts: {inclusions: [{category: 'water', text: 'Water included'}]},
    ancillaryFacts: {flights: [{flightNumber: 'EA 1'}]},
  };
  const first = normalize(payload);
  const second = normalize(JSON.parse(JSON.stringify(payload)));

  assert.deepEqual(second, first);
  assert.deepEqual(first.facts.map((fact) => fact.id), [
    'staged-service-1',
    'staged-service-2',
    'package-fact-1',
    'ancillary-flight-1',
  ]);
  assertSupplierExtractionSnapshotInvariants(first, context().trustedPackage);
});

test('V3 response schema is strict, stable, sparse, and contains no trusted IDs', () => {
  const supportedKeywords = new Set([
    '$id', '$defs', '$ref', 'type', 'format', 'enum', 'items', 'minItems',
    'minimum', 'properties', 'additionalProperties', 'required',
    'propertyOrdering',
  ]);
  const propertyNames = [];

  function inspectSchema(node) {
    if (!node || typeof node !== 'object' || Array.isArray(node)) return;
    if (node.type === 'object') {
      assert.equal(node.additionalProperties, false);
    }
    for (const [key, value] of Object.entries(node)) {
      assert(supportedKeywords.has(key), `Unsupported JSON Schema keyword: ${key}`);
      if (key === 'properties') {
        for (const [propertyName, propertySchema] of Object.entries(value)) {
          propertyNames.push(propertyName);
          inspectSchema(propertySchema);
        }
      } else if (key === '$defs') {
        for (const definition of Object.values(value)) inspectSchema(definition);
      } else if (key === 'items') {
        inspectSchema(value);
      }
    }
  }

  inspectSchema(kayraSupplierExtractionV3ResponseSchema);
  assert.equal(kayraSupplierExtractionV3ResponseSchema.required, undefined);
  assert.equal(
    Object.prototype.hasOwnProperty.call(
      kayraSupplierExtractionV3ResponseSchema.$defs.service,
      'anyOf',
    ),
    false,
  );
  for (const forbidden of [
    'tripId', 'sourcePackageId', 'sourceFileId', 'extractionId', 'jobId',
    'requestedByUid', 'createdAt', 'updatedAt', 'id', 'amount', 'currency',
    'rawPricingText',
  ]) {
    assert.equal(propertyNames.includes(forbidden), false, forbidden);
  }
});

test('V3 prompt contains the staging fidelity and isolation principles', () => {
  const expectedPrinciples = [
    /source fidelity over apparent completeness/i,
    /Capture each itinerary-relevant operational fact once/i,
    /Never invent chronology/i,
    /Never invent hotel spans/i,
    /Keep unassigned services unassigned/i,
    /packageFacts/i,
    /flights and visa facts only in ancillaryFacts/i,
    /record only the allowed presence categories/i,
    /marketing prose[\s\S]*boilerplate/i,
    /either activity or sightseeing, never both/i,
    /Preserve each explicit qualifier exactly once/i,
    /compact sourceLabel/i,
    /reviewIssues for genuine ambiguity/i,
    /Do not infer from general travel knowledge/i,
  ];
  for (const pattern of expectedPrinciples) {
    assert.match(kayraSupplierExtractionV3Prompt, pattern);
  }
  assert.doesNotMatch(kayraSupplierExtractionV3Prompt, /gs:\/\//i);
  assert.doesNotMatch(kayraSupplierExtractionV3Prompt, /supplierSourceFileId/i);
});

test('production V2.4 provider, writer, and processor do not import V3 modules', () => {
  const productionFiles = [
    'geminiProvider.ts',
    'geminiProviderSchema.ts',
    'geminiProviderPrompt.ts',
    'providerDraftV2.ts',
    'draftWriter.ts',
    'processor.ts',
    'trigger.ts',
  ];
  for (const fileName of productionFiles) {
    const contents = fs.readFileSync(
      path.join(__dirname, '../src/itineraryExtraction', fileName),
      'utf8',
    );
    assert.doesNotMatch(contents, /providerSupplierExtractionV3/);
    assert.doesNotMatch(contents, /geminiStagingProvider/);
    assert.doesNotMatch(contents, /kayra_itinerary_extraction_v3_staging/);
  }
});
