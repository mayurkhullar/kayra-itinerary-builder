const {test} = require('node:test');
const assert = require('node:assert/strict');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {
  DraftBoundaryError,
  validateDraftPayload,
} = require('../lib/itineraryExtraction/draftValidation');
const {
  writeTrustedItineraryDraft,
} = require('../lib/itineraryExtraction/draftWriter');
const {
  adminDraftWriterDependencies,
} = require('../lib/itineraryExtraction/draftWriterAdmin');

const draftCode = (expected) => (error) =>
  error instanceof DraftBoundaryError && error.code === expected;

function trustedPackage() {
  return {
    tripId: 'trip-1',
    packageId: 'package-1',
    supplierId: 'supplier-1',
    supplierNameSnapshot: 'Example Supplier',
    files: [
      {
        sourceFileId: 'file-1',
        packageId: 'package-1',
        originalFileName: 'quote.pdf',
        storagePath: 'trips/trip-1/supplier_sources/file-1/quote.pdf',
        contentType: 'application/pdf',
        sizeBytes: 100,
        uploadedByUid: 'agent-1',
      },
      {
        sourceFileId: 'file-2',
        packageId: 'package-1',
        originalFileName: 'notes.txt',
        storagePath: 'trips/trip-1/supplier_sources/file-2/notes.txt',
        contentType: 'text/plain',
        sizeBytes: 50,
        uploadedByUid: 'agent-1',
      },
    ],
  };
}

function payload(overrides = {}) {
  return {title: ' Dubai Escape ', days: [], reviewIssues: [], ...overrides};
}

function day(dayNumber = 1, services = []) {
  return {
    dayNumber,
    date: null,
    title: ` Day ${dayNumber} `,
    summary: null,
    services,
    notes: null,
  };
}

function service(type = 'other', overrides = {}) {
  return {
    id: `${type}-1`,
    type,
    title: ` ${type} service `,
    description: null,
    startTime: null,
    endTime: null,
    location: null,
    city: null,
    inclusions: [],
    exclusions: [],
    notes: null,
    hotelDetails: null,
    transferDetails: null,
    activityDetails: null,
    sourceReference: null,
    ...overrides,
  };
}

function hotelDetails() {
  return {
    hotelName: ' Example Hotel ',
    checkInDate: '2027-01-10',
    checkOutDate: '2027-01-12',
    roomType: ' Deluxe ',
    mealPlan: ' Breakfast ',
    numberOfRooms: 2,
    supplierStarRating: ' 5 Star ',
  };
}

function transferDetails(transferType = 'private') {
  return {
    pickup: ' Airport ',
    dropoff: ' Hotel ',
    vehicleType: ' Sedan ',
    transferType,
  };
}

function activityDetails() {
  return {
    activityName: ' Desert Safari ',
    duration: ' 6 hours ',
    activityType: ' Adventure ',
  };
}

function sourceReference(overrides = {}) {
  return {
    supplierSourcePackageId: 'package-1',
    supplierSourceFileId: 'file-1',
    sourceLabel: ' Page 2 ',
    ...overrides,
  };
}

function reviewIssue(severity = 'warning', overrides = {}) {
  return {
    id: `${severity}-1`,
    fieldPath: ' days[0].services[0].startTime ',
    message: ' Confirm timing. ',
    severity,
    ...overrides,
  };
}

function input(extractedPayload = payload(), overrides = {}) {
  return {
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    requestedByUid: 'agent-1',
    extractedPayload,
    trustedPackage: trustedPackage(),
    ...overrides,
  };
}

test('valid minimal draft is normalized', () => {
  assert.deepEqual(validateDraftPayload(payload(), trustedPackage()), {
    title: 'Dubai Escape',
    days: [],
    reviewIssues: [],
  });
});

test('blank title and unexpected root fields are rejected', () => {
  assert.throws(
    () => validateDraftPayload(payload({title: ' '}), trustedPackage()),
    draftCode('INVALID_EXTRACTION_RESULT'),
  );
  assert.throws(
    () => validateDraftPayload({...payload(), provider: 'example'}, trustedPackage()),
    draftCode('INVALID_EXTRACTION_RESULT'),
  );
});

test('multiple days are sorted by dayNumber', () => {
  const result = validateDraftPayload(
    payload({days: [day(3), day(1), day(2)]}),
    trustedPackage(),
  );
  assert.deepEqual(result.days.map((value) => value.dayNumber), [1, 2, 3]);
  assert.deepEqual(result.days.map((value) => value.title), ['Day 1', 'Day 2', 'Day 3']);
});

test('non-positive, duplicate, and blank-title days are rejected', () => {
  for (const days of [
    [day(0)],
    [day(1), day(1)],
    [{...day(1), title: ' '}],
  ]) {
    assert.throws(
      () => validateDraftPayload(payload({days}), trustedPackage()),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
  }
});

test('invalid and non-calendar day dates are rejected', () => {
  for (const date of ['2027-02-30', '10-01-2027', new Date(), 1]) {
    assert.throws(
      () => validateDraftPayload(
        payload({days: [{...day(1), date}]}),
        trustedPackage(),
      ),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
  }
});

test('every supported service type is accepted and order is preserved', () => {
  const types = [
    'hotel', 'transfer', 'activity', 'meal', 'sightseeing', 'free_time', 'other',
  ];
  const services = types.map((type, index) => service(type, {
    id: `service-${index}`,
    hotelDetails: type === 'hotel' ? hotelDetails() : null,
    transferDetails: type === 'transfer' ? transferDetails() : null,
    activityDetails: type === 'activity' ? activityDetails() : null,
  }));
  const result = validateDraftPayload(payload({days: [day(1, services)]}), trustedPackage());
  assert.deepEqual(result.days[0].services.map((value) => value.type), types);
  assert.deepEqual(
    result.days[0].services.map((value) => value.id),
    services.map((value) => value.id),
  );
});

test('unknown type, blank title, and duplicate service ID are rejected', () => {
  for (const services of [
    [service('flight')],
    [service('other', {title: ' '})],
    [service('meal', {id: 'same'}), service('other', {id: 'same'})],
  ]) {
    assert.throws(
      () => validateDraftPayload(payload({days: [day(1, services)]}), trustedPackage()),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
  }
});

test('incompatible detail objects are rejected exactly like Dart', () => {
  for (const value of [
    service('meal', {hotelDetails: hotelDetails()}),
    service('hotel', {transferDetails: transferDetails()}),
    service('transfer', {activityDetails: activityDetails()}),
  ]) {
    assert.throws(
      () => validateDraftPayload(payload({days: [day(1, [value])]}), trustedPackage()),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
  }
});

test('hotel details normalize to the Dart persisted shape', () => {
  const result = validateDraftPayload(payload({
    days: [day(1, [service('hotel', {hotelDetails: hotelDetails()})])],
  }), trustedPackage());
  const details = result.days[0].services[0].hotelDetails;
  assert.equal(details.hotelName, 'Example Hotel');
  assert.equal(details.checkInDate.toISOString(), '2027-01-10T00:00:00.000Z');
  assert.equal(details.checkOutDate.toISOString(), '2027-01-12T00:00:00.000Z');
  assert.deepEqual(Object.keys(details), [
    'hotelName', 'checkInDate', 'checkOutDate', 'roomType', 'mealPlan',
    'numberOfRooms', 'supplierStarRating',
  ]);
});

test('invalid hotel date range and room count are rejected', () => {
  for (const details of [
    {...hotelDetails(), checkOutDate: '2027-01-10'},
    {...hotelDetails(), numberOfRooms: 0},
  ]) {
    assert.throws(
      () => validateDraftPayload(payload({
        days: [day(1, [service('hotel', {hotelDetails: details})])],
      }), trustedPackage()),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
  }
});

test('every transfer type and null are accepted with Dart field shape', () => {
  for (const type of ['private', 'shared', 'scheduled', 'other', null]) {
    const result = validateDraftPayload(payload({
      days: [day(1, [service('transfer', {
        transferDetails: transferDetails(type),
      })])],
    }), trustedPackage());
    const details = result.days[0].services[0].transferDetails;
    assert.equal(details.transferType, type);
    assert.deepEqual(Object.keys(details), [
      'pickup', 'dropoff', 'vehicleType', 'transferType',
    ]);
  }
});

test('unknown transfer type is rejected', () => {
  assert.throws(
    () => validateDraftPayload(payload({
      days: [day(1, [service('transfer', {
        transferDetails: transferDetails('chauffeured'),
      })])],
    }), trustedPackage()),
    draftCode('INVALID_EXTRACTION_RESULT'),
  );
});

test('activity details are validated and normalized', () => {
  const result = validateDraftPayload(payload({
    days: [day(1, [service('activity', {activityDetails: activityDetails()})])],
  }), trustedPackage());
  assert.deepEqual(result.days[0].services[0].activityDetails, {
    activityName: 'Desert Safari',
    duration: '6 hours',
    activityType: 'Adventure',
  });
});

test('inclusions and exclusions mirror Dart trimming behavior', () => {
  const result = validateDraftPayload(payload({
    days: [day(1, [service('other', {
      inclusions: [' Breakfast ', '', ' Breakfast ', ' Transfers '],
      exclusions: [' Flights ', '  '],
    })])],
  }), trustedPackage());
  const value = result.days[0].services[0];
  assert.deepEqual(value.inclusions, ['Breakfast', 'Breakfast', 'Transfers']);
  assert.deepEqual(value.exclusions, ['Flights']);
});

test('trusted provenance package and file are accepted', () => {
  const result = validateDraftPayload(payload({
    days: [day(1, [service('other', {sourceReference: sourceReference()})])],
  }), trustedPackage());
  assert.deepEqual(result.days[0].services[0].sourceReference, {
    supplierSourcePackageId: 'package-1',
    supplierSourceFileId: 'file-1',
    sourceLabel: 'Page 2',
  });
});

test('wrong package, unknown file, and malformed provenance are rejected', () => {
  for (const reference of [
    sourceReference({supplierSourcePackageId: 'package-2'}),
    sourceReference({supplierSourceFileId: 'file-99'}),
    sourceReference({supplierSourceFileId: 'bad/id'}),
    {...sourceReference(), unexpected: true},
  ]) {
    assert.throws(
      () => validateDraftPayload(payload({
        days: [day(1, [service('other', {sourceReference: reference})])],
      }), trustedPackage()),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
  }
});

test('warning and blocker review issues are accepted', () => {
  const result = validateDraftPayload(payload({
    reviewIssues: [reviewIssue('warning'), reviewIssue('blocker')],
  }), trustedPackage());
  assert.deepEqual(result.reviewIssues.map((value) => value.severity), [
    'warning', 'blocker',
  ]);
});

test('unknown severity, blank message, and duplicate issue ID are rejected', () => {
  for (const reviewIssues of [
    [reviewIssue('info')],
    [reviewIssue('warning', {message: ' '})],
    [reviewIssue('warning', {id: 'same'}), reviewIssue('blocker', {id: 'same'})],
  ]) {
    assert.throws(
      () => validateDraftPayload(payload({reviewIssues}), trustedPackage()),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
  }
});

test('provider cannot supply backend-owned root fields', () => {
  for (const field of [
    'tripId', 'createdByUid', 'sourcePackageIds', 'createdAt', 'updatedAt', 'id',
  ]) {
    assert.throws(
      () => validateDraftPayload({...payload(), [field]: 'attacker'}, trustedPackage()),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
  }
});

test('writer attaches backend-owned identity and exactly one source package', async () => {
  const writes = [];
  const result = await writeTrustedItineraryDraft(input(), {
    async createDraft(tripId, data) {
      writes.push({tripId, data});
      return 'generated-draft';
    },
  });
  assert.deepEqual(result, {draftId: 'generated-draft'});
  assert.equal(writes[0].tripId, 'trip-1');
  assert.equal(writes[0].data.tripId, 'trip-1');
  assert.equal(writes[0].data.createdByUid, 'agent-1');
  assert.deepEqual(writes[0].data.sourcePackageIds, ['package-1']);
  assert.equal('createdAt' in writes[0].data, false);
  assert.equal('updatedAt' in writes[0].data, false);
});

test('trusted package mismatch and empty files produce zero writes', async () => {
  for (const trusted of [
    {...trustedPackage(), tripId: 'trip-2'},
    {...trustedPackage(), packageId: 'package-2'},
    {...trustedPackage(), files: []},
  ]) {
    let writes = 0;
    await assert.rejects(
      writeTrustedItineraryDraft(input(payload(), {trustedPackage: trusted}), {
        async createDraft() {
          writes += 1;
          return 'never';
        },
      }),
      draftCode('INVALID_EXTRACTION_RESULT'),
    );
    assert.equal(writes, 0);
  }
});

test('validation failure performs zero writes', async () => {
  let writes = 0;
  await assert.rejects(
    writeTrustedItineraryDraft(input(payload({title: ' '})), {
      async createDraft() {
        writes += 1;
        return 'never';
      },
    }),
    draftCode('INVALID_EXTRACTION_RESULT'),
  );
  assert.equal(writes, 0);
});

test('write failures map to sanitized DRAFT_PERSISTENCE_FAILED', async () => {
  await assert.rejects(
    writeTrustedItineraryDraft(input(), {
      async createDraft() {
        throw new Error('SECRET FIRESTORE ERROR');
      },
    }),
    (error) => draftCode('DRAFT_PERSISTENCE_FAILED')(error) &&
      !error.message.includes('SECRET'),
  );
});

function adminFixture({tripExists = true, writeError = null} = {}) {
  const state = {creates: [], generated: 0};
  const reference = (path) => ({
    path,
    id: path.split('/').at(-1),
    collection(name) {
      return {
        doc() {
          state.generated += 1;
          return reference(`${path}/${name}/draft-${state.generated}`);
        },
      };
    },
  });
  const db = {
    doc: reference,
    async runTransaction(callback) {
      const pending = [];
      const result = await callback({
        get: async () => ({exists: tripExists}),
        create(ref, data) {
          if (writeError) throw writeError;
          pending.push({path: ref.path, data});
        },
      });
      state.creates.push(...pending);
      return result;
    },
  };
  return {state, dependencies: adminDraftWriterDependencies(db)};
}

test('Admin writer uses auto ID, Trip subcollection, and server timestamps', async () => {
  const f = adminFixture();
  const result = await writeTrustedItineraryDraft(input(), f.dependencies);
  assert.deepEqual(result, {draftId: 'draft-1'});
  assert.equal(f.state.creates[0].path, 'trips/trip-1/itinerary_drafts/draft-1');
  const data = f.state.creates[0].data;
  assert.deepEqual(Object.keys(data).sort(), [
    'createdAt', 'createdByUid', 'days', 'reviewIssues', 'sourcePackageIds',
    'title', 'tripId', 'updatedAt',
  ]);
  assert.ok(data.createdAt.isEqual(FieldValue.serverTimestamp()));
  assert.ok(data.updatedAt.isEqual(FieldValue.serverTimestamp()));
});

test('missing parent Trip is rejected without a document write', async () => {
  const f = adminFixture({tripExists: false});
  await assert.rejects(
    writeTrustedItineraryDraft(input(), f.dependencies),
    draftCode('DRAFT_PERSISTENCE_FAILED'),
  );
  assert.deepEqual(f.state.creates, []);
});

test('representative persisted payload matches Dart fromMap schema', async () => {
  const fullPayload = payload({
    days: [{
      ...day(2, [service('hotel', {
        description: ' Stay ',
        startTime: ' 14:00 ',
        endTime: ' 11:00 ',
        location: ' Marina ',
        city: ' Dubai ',
        inclusions: [' Breakfast '],
        exclusions: [' Tourism fee '],
        notes: ' Confirm room ',
        hotelDetails: hotelDetails(),
        sourceReference: sourceReference(),
      })]),
      date: '2027-01-10',
      summary: ' Arrival ',
      notes: ' Welcome ',
    }],
    reviewIssues: [reviewIssue('blocker')],
  });
  const f = adminFixture();
  await writeTrustedItineraryDraft(input(fullPayload), f.dependencies);
  const draft = f.state.creates[0].data;
  const persistedDay = draft.days[0];
  const persistedService = persistedDay.services[0];
  assert.ok(persistedDay.date instanceof Timestamp);
  assert.ok(persistedService.hotelDetails.checkInDate instanceof Timestamp);
  assert.deepEqual(Object.keys(persistedDay), [
    'dayNumber', 'date', 'title', 'summary', 'services', 'notes',
  ]);
  assert.deepEqual(Object.keys(persistedService), [
    'id', 'type', 'title', 'description', 'startTime', 'endTime', 'location',
    'city', 'inclusions', 'exclusions', 'notes', 'hotelDetails',
    'transferDetails', 'activityDetails', 'sourceReference',
  ]);
});
