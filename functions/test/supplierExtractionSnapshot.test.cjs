const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  supplierExtractionSnapshotSchemaVersion,
  serializeSupplierExtractionSnapshot,
} = require('../lib/itineraryExtraction/supplierExtractionSnapshot');
const {
  SupplierExtractionSnapshotError,
  assertSupplierExtractionSnapshotInvariants,
  normalizeSupplierExtractionSnapshot,
} = require('../lib/itineraryExtraction/supplierExtractionValidation');

const invalidExtraction = (error) =>
  error instanceof SupplierExtractionSnapshotError &&
  error.code === 'INVALID_SUPPLIER_EXTRACTION';

function sourceFile(sourceFileId, extension = 'pdf') {
  const contentType = extension === 'txt' ? 'text/plain' : 'application/pdf';
  return {
    sourceFileId,
    packageId: 'package-1',
    originalFileName: `${sourceFileId}.${extension}`,
    storagePath: `trips/trip-1/supplier_sources/${sourceFileId}/source.${extension}`,
    contentType,
    sizeBytes: 100,
    uploadedByUid: 'agent-1',
  };
}

function trustedPackage(fileIds = ['file-1', 'file-2']) {
  return {
    tripId: 'trip-1',
    packageId: 'package-1',
    supplierId: 'supplier-1',
    supplierNameSnapshot: 'Synthetic Supplier',
    files: fileIds.map((id, index) => sourceFile(id, index === 0 ? 'pdf' : 'txt')),
  };
}

function context(packageValue = trustedPackage()) {
  return {
    extractionId: 'extraction-1',
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    jobId: 'job-1',
    requestedByUid: 'agent-1',
    createdAt: new Date('2026-09-29T05:00:00.000Z'),
    providerVersion: 'kayra_itinerary_extraction_v3_staging',
    trustedPackage: packageValue,
  };
}

function title(text = 'Synthetic itinerary') {
  return {
    text,
    basis: 'neutral_supported',
    sources: [{fileIndex: 1, sourceLabel: 'Page 1'}],
  };
}

function normalize(payload, contextValue = context()) {
  return normalizeSupplierExtractionSnapshot(payload, contextValue);
}

function facts(snapshot, kind) {
  return snapshot.facts.filter((fact) => fact.factKind === kind);
}

test('detailed chronological source preserves days, services, dates, and provenance', () => {
  const snapshot = normalize({
    title: title('France and Switzerland itinerary'),
    days: [
      {
        sourceDayNumber: 1,
        date: '2027-02-01',
        title: 'Arrival in Paris',
        sources: [{fileIndex: 1, sourceLabel: 'Page 1'}],
        services: [
          {
            type: 'transfer',
            title: 'Airport to hotel',
            startTime: '12:00',
            transferDetails: {
              pickup: 'Airport',
              dropoff: 'Hotel',
              vehicleType: 'Standard sedan',
            },
            sources: [{fileIndex: 1, sourceLabel: 'Page 1'}],
          },
          {
            type: 'hotel',
            hotelDetails: {
              hotelName: 'Example Hotel',
              orSimilar: true,
              roomType: 'Double room',
              mealPlan: 'Breakfast',
              numberOfRooms: 1,
            },
            sources: [{fileIndex: 2, sourceLabel: 'Hotel table'}],
          },
        ],
      },
      {
        sourceDayNumber: 3,
        date: '2027-02-03',
        title: 'Sightseeing',
        services: [{type: 'sightseeing', title: 'City tour'}],
      },
    ],
  });

  assert.equal(snapshot.schemaVersion, supplierExtractionSnapshotSchemaVersion);
  assert.deepEqual(snapshot.days.map((day) => day.sourceDayNumber), [1, 3]);
  assert.deepEqual(snapshot.days.map((day) => day.date), ['2027-02-01', '2027-02-03']);
  assert.deepEqual(snapshot.days[0].assignedServiceIds, [
    'staged-service-1', 'staged-service-2',
  ]);
  assert.deepEqual(snapshot.days[1].assignedServiceIds, ['staged-service-3']);
  assert.equal(facts(snapshot, 'service')[1].sources[0].supplierSourceFileId, 'file-2');
  assert.equal(snapshot.counts.assignedServices, 3);
  assert.equal(snapshot.counts.unassignedServices, 0);
  assert(Object.isFrozen(snapshot));
  assert(Object.isFrozen(snapshot.facts));
  assert(Object.isFrozen(snapshot.facts[0].scope));
});

test('incomplete message preserves separate unassigned services and global facts', () => {
  const tourNames = [
    'City tour',
    'Mud volcanoes and museum',
    'Fire temple and mountain',
    'Full-day mountain tour with cable car',
  ];
  const snapshot = normalize({
    title: title('Four-night city package'),
    unassignedServices: tourNames.map((name) => ({
      type: 'sightseeing',
      title: name,
    })),
    packageFacts: {
      inclusions: [
        {category: 'guide', text: 'English-speaking guide included'},
        {category: 'water', text: 'Water per person per day'},
      ],
      conditions: [{
        kind: 'operating_basis',
        value: 'Private basis for tours and transfers',
        appliesTo: ['sightseeing', 'transfer'],
      }],
    },
    reviewIssues: [{
      code: 'chronology_unknown',
      severity: 'blocker',
      message: 'Tour chronology is not stated.',
      target: {kind: 'snapshot'},
      resolutionRequired: true,
    }],
  });

  assert.equal(snapshot.days.length, 0);
  assert.deepEqual(
    facts(snapshot, 'service').map((fact) => [fact.title, fact.scope.kind]),
    tourNames.map((name) => [name, 'unassigned']),
  );
  assert.equal(snapshot.counts.unassignedServices, 4);
  assert.equal(snapshot.counts.packageFacts, 3);
  assert.equal(snapshot.reviewIssues[0].target.kind, 'snapshot');
});

test('global accommodation keeps known hotel and nights without fabricated dates', () => {
  const snapshot = normalize({
    title: title('Four-night package'),
    packageFacts: {
      accommodations: [{
        hotelName: 'Boulevard Hotel',
        city: 'Baku',
        orSimilar: true,
        nightCount: 4,
        mealPlan: 'Breakfast',
      }],
    },
    reviewIssues: [{
      code: 'accommodation_span_unknown',
      severity: 'blocker',
      message: 'The hotel night allocation is not stated.',
      target: {kind: 'package_fact', factType: 'accommodation', factIndex: 1},
      resolutionRequired: true,
    }],
  });
  const accommodation = facts(snapshot, 'package_accommodation')[0];
  assert.equal(accommodation.details.hotelName, 'Boulevard Hotel');
  assert.equal(accommodation.details.city, 'Baku');
  assert.equal(accommodation.details.nightCount, 4);
  assert.equal(accommodation.details.checkInDate, null);
  assert.equal(accommodation.details.checkOutDate, null);
  assert.equal(snapshot.reviewIssues[0].target.entityId, accommodation.id);
});

test('multiple unmapped hotels remain distinct package accommodations', () => {
  const snapshot = normalize({
    title: title('Multi-city package'),
    packageFacts: {
      accommodations: [
        {hotelName: 'First Hotel', nightCount: 2},
        {hotelName: 'Second Hotel', nightCount: 3, orSimilar: true},
      ],
    },
  });
  const accommodations = facts(snapshot, 'package_accommodation');
  assert.deepEqual(accommodations.map((fact) => fact.id), [
    'package-fact-1', 'package-fact-2',
  ]);
  assert.deepEqual(accommodations.map((fact) => fact.details.hotelName), [
    'First Hotel', 'Second Hotel',
  ]);
  assert(accommodations.every((fact) => fact.scope.kind === 'package'));
});

test('package inclusions and exclusions remain package scoped and are not copied', () => {
  const snapshot = normalize({
    title: title(),
    unassignedServices: [{type: 'activity', title: 'Museum visit'}],
    packageFacts: {
      inclusions: [{
        category: 'meal',
        text: 'Lunches included',
        quantity: 5,
        appliesTo: ['meal'],
      }],
      exclusions: [{
        category: 'entrance',
        text: 'Attraction entrance fees excluded',
      }],
    },
  });
  const service = facts(snapshot, 'service')[0];
  assert.deepEqual(service.inclusions, []);
  assert.deepEqual(service.exclusions, []);
  assert.equal(facts(snapshot, 'package_inclusion')[0].quantity, 5);
  assert.deepEqual(facts(snapshot, 'package_inclusion')[0].appliesTo, ['meal']);
  assert.equal(facts(snapshot, 'package_exclusion')[0].scope.kind, 'package');
});

test('flight facts remain ancillary and never become itinerary services', () => {
  const snapshot = normalize({
    title: title(),
    ancillaryFacts: {
      flights: [{
        airline: 'Example Air',
        flightNumber: 'EA 101',
        origin: 'DEL',
        destination: 'DXB',
        departureDate: '2027-05-01',
        departureTime: '09:30',
        arrivalDate: '2027-05-01',
        arrivalTime: '11:45',
        cabinClass: 'Economy',
        conditions: [{kind: 'availability', value: 'Subject to reconfirmation'}],
      }],
    },
  });
  const flight = facts(snapshot, 'flight')[0];
  assert.equal(flight.scope.kind, 'ancillary');
  assert.equal(flight.departureTime, '09:30');
  assert.equal(facts(snapshot, 'service').length, 0);
});

test('visa semantics are preserved while pricing fields and values are rejected', () => {
  const snapshot = normalize({
    title: title(),
    ancillaryFacts: {visas: [{disposition: 'included'}]},
  });
  assert.equal(facts(snapshot, 'visa')[0].disposition, 'included');

  for (const visa of [
    {disposition: 'included', price: 30},
    {disposition: 'included', currency: 'USD'},
    {disposition: 'included', text: 'Visa included — USD 30 per person'},
    {disposition: 'included', text: 'Visa included — 30 USD per person'},
    {disposition: 'included', text: 'Visa total: 30 per person'},
  ]) {
    assert.throws(
      () => normalize({title: title(), ancillaryFacts: {visas: [visa]}}),
      invalidExtraction,
    );
  }
});

test('commercial content accepts only controlled presence categories', () => {
  const snapshot = normalize({
    title: title(),
    commercialContent: {
      present: true,
      categories: ['package_price', 'payment_terms'],
      sources: [{fileIndex: 2, sourceLabel: 'Quotation table'}],
    },
  });
  const commercial = facts(snapshot, 'commercial_presence')[0];
  assert.deepEqual(commercial.categories, ['package_price', 'payment_terms']);
  assert.equal(commercial.sources[0].supplierSourceFileId, 'file-2');

  for (const commercialContent of [
    {present: true, categories: ['package_price'], amount: 1000},
    {present: true, categories: ['package_price'], currency: 'USD'},
    {present: true, categories: ['package_price'], rawText: 'USD 1000'},
    {present: true, categories: ['unknown_price']},
    {present: false, categories: ['package_price']},
  ]) {
    assert.throws(
      () => normalize({title: title(), commercialContent}),
      invalidExtraction,
    );
  }
});

test('provider-safe provenance resolves file indexes and rejects trusted IDs', () => {
  const snapshot = normalize({
    title: title(),
    unassignedServices: [{
      type: 'meal',
      title: 'Dinner',
      sources: [{fileIndex: 2, sourceLabel: 'Section B'}],
    }],
  });
  assert.deepEqual(facts(snapshot, 'service')[0].sources[0], {
    supplierSourcePackageId: 'package-1',
    supplierSourceFileId: 'file-2',
    sourceLabel: 'Section B',
  });

  for (const source of [
    {fileIndex: 0},
    {fileIndex: 3},
    {fileIndex: 1.5},
    {fileIndex: '1'},
    {supplierSourcePackageId: 'package-1'},
    {supplierSourceFileId: 'file-1'},
    {tripId: 'trip-1'},
  ]) {
    assert.throws(
      () => normalize({
        title: title(),
        unassignedServices: [{type: 'meal', title: 'Dinner', sources: [source]}],
      }),
      invalidExtraction,
    );
  }
});

test('review targets resolve to backend-owned day, service, package, and ancillary IDs', () => {
  const snapshot = normalize({
    title: title(),
    days: [{title: 'Day A', services: [{type: 'meal', title: 'Lunch'}]}],
    unassignedServices: [{title: 'Unknown service'}],
    packageFacts: {accommodations: [{hotelName: 'Hotel'}]},
    ancillaryFacts: {flights: [{origin: 'A', destination: 'B'}]},
    reviewIssues: [
      {
        code: 'conflicting_dates', severity: 'blocker', message: 'Check day.',
        target: {kind: 'day', dayIndex: 1}, resolutionRequired: true,
      },
      {
        code: 'chronology_unknown', severity: 'blocker', message: 'Map service.',
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
    'staged-service-2',
    'package-fact-1',
    'ancillary-flight-1',
  ]);
});

test('missing review targets are rejected', () => {
  for (const target of [
    {kind: 'day', dayIndex: 2},
    {kind: 'service', scope: 'day', dayIndex: 1, serviceIndex: 2},
    {kind: 'service', scope: 'unassigned', serviceIndex: 1},
    {kind: 'package_fact', factType: 'accommodation', factIndex: 1},
    {kind: 'ancillary_fact', factType: 'flight', factIndex: 1},
  ]) {
    assert.throws(
      () => normalize({
        title: title(),
        days: [{title: 'Only day', services: [{type: 'meal', title: 'Lunch'}]}],
        reviewIssues: [{
          code: 'other', severity: 'warning', message: 'Missing target.',
          target, resolutionRequired: false,
        }],
      }),
      invalidExtraction,
    );
  }
});

test('trusted invariant validator rejects assigned services pointing to missing days', () => {
  const snapshot = normalize({
    title: title(),
    days: [{title: 'Day', services: [{type: 'meal', title: 'Lunch'}]}],
  });
  const changed = JSON.parse(serializeSupplierExtractionSnapshot(snapshot));
  changed.facts[0].scope.dayId = 'staged-day-missing';
  assert.throws(
    () => assertSupplierExtractionSnapshotInvariants(changed, context().trustedPackage),
    invalidExtraction,
  );
});

test('trusted invariant validator rejects duplicate internal identities', () => {
  const snapshot = normalize({
    title: title(),
    unassignedServices: [
      {type: 'meal', title: 'Lunch'},
      {type: 'meal', title: 'Dinner'},
    ],
  });
  const changed = JSON.parse(serializeSupplierExtractionSnapshot(snapshot));
  changed.facts[1].id = changed.facts[0].id;
  assert.throws(
    () => assertSupplierExtractionSnapshotInvariants(changed, context().trustedPackage),
    invalidExtraction,
  );
});

test('trusted invariant validator maps malformed timestamps to the domain error', () => {
  const snapshot = normalize({title: title()});
  const changed = JSON.parse(serializeSupplierExtractionSnapshot(snapshot));
  changed.createdAt = 'not-a-timestamp';
  assert.throws(
    () => assertSupplierExtractionSnapshotInvariants(changed, context().trustedPackage),
    invalidExtraction,
  );
});

test('service detail branches remain compatible with their service types', () => {
  const invalidServices = [
    {type: 'meal', title: 'Meal', hotelDetails: {hotelName: 'Hotel'}},
    {
      type: 'hotel',
      title: 'Hotel',
      transferDetails: {pickup: 'A', dropoff: 'B'},
    },
    {
      type: 'transfer',
      title: 'Transfer',
      activityDetails: {activityName: 'Tour'},
    },
    {title: 'Unclassified', hotelDetails: {hotelName: 'Hotel'}},
  ];
  for (const service of invalidServices) {
    assert.throws(
      () => normalize({title: title(), unassignedServices: [service]}),
      invalidExtraction,
    );
  }

  const snapshot = normalize({
    title: title(),
    unassignedServices: [
      {type: 'hotel', hotelDetails: {hotelName: 'Hotel'}},
      {type: 'transfer', transferDetails: {pickup: 'Airport'}},
      {type: 'activity', activityDetails: {activityName: 'Tour'}},
    ],
  });
  assert.deepEqual(facts(snapshot, 'service').map((fact) => fact.serviceType), [
    'hotel', 'transfer', 'activity',
  ]);
});

test('incomplete chronology remains valid without fake days or dates', () => {
  const snapshot = normalize({
    title: title('Undated services'),
    unassignedServices: [
      {title: 'Coach transfer', type: 'transfer', transferDetails: {vehicleType: 'Coach'}},
      {title: 'Welcome dinner', type: 'meal'},
    ],
  });
  assert.equal(snapshot.days.length, 0);
  assert(facts(snapshot, 'service').every((fact) => fact.scope.kind === 'unassigned'));
  assert(facts(snapshot, 'service').every((fact) => fact.startTime === null));
});

test('unknown keys and provider-owned trusted metadata are rejected everywhere', () => {
  const payloads = [
    {title: title(), provider: 'injected'},
    {title: {...title(), sourcePackageId: 'package-1'}},
    {title: title(), days: [{title: 'Day', dayId: 'provider-day'}]},
    {title: title(), unassignedServices: [{title: 'Tour', id: 'provider-service'}]},
    {
      title: title(),
      packageFacts: {accommodations: [{hotelName: 'Hotel', tripId: 'trip-1'}]},
    },
  ];
  for (const payload of payloads) {
    assert.throws(() => normalize(payload), invalidExtraction);
  }
});

test('malformed dates, times, ranges, and empty typed details are rejected', () => {
  const services = [
    {type: 'meal', title: 'Meal', startTime: '9:30'},
    {type: 'hotel', hotelDetails: {}},
    {
      type: 'hotel',
      hotelDetails: {hotelName: 'Hotel', checkInDate: '2027-02-02', checkOutDate: '2027-02-01'},
    },
    {type: 'transfer', transferDetails: {}},
    {type: 'activity', activityDetails: {}},
  ];
  for (const service of services) {
    assert.throws(
      () => normalize({title: title(), unassignedServices: [service]}),
      invalidExtraction,
    );
  }
  assert.throws(
    () => normalize({title: title(), days: [{title: 'Day', date: '2027-02-30'}]}),
    invalidExtraction,
  );
});

test('normalized IDs and serialization are deterministic for equivalent input', () => {
  const payload = {
    title: title(),
    days: [{title: 'Day', services: [{type: 'meal', title: 'Lunch'}]}],
    unassignedServices: [{type: 'sightseeing', title: 'City tour'}],
    packageFacts: {
      inclusions: [{category: 'water', text: 'Water included'}],
    },
    ancillaryFacts: {
      flights: [{flightNumber: 'EA 101'}],
      visas: [{disposition: 'excluded'}],
    },
    reviewIssues: [{
      code: 'chronology_unknown',
      severity: 'blocker',
      message: 'Assign the tour.',
      target: {kind: 'service', scope: 'unassigned', serviceIndex: 1},
      resolutionRequired: true,
    }],
  };
  const first = normalize(payload);
  const second = normalize(JSON.parse(JSON.stringify(payload)));
  assert.equal(
    serializeSupplierExtractionSnapshot(first),
    serializeSupplierExtractionSnapshot(second),
  );
  assert.deepEqual(first.facts.map((fact) => fact.id), [
    'staged-service-1',
    'staged-service-2',
    'package-fact-1',
    'ancillary-flight-1',
    'ancillary-visa-1',
  ]);
  assert.deepEqual(first.reviewIssues.map((issue) => issue.id), ['review-1']);
});
