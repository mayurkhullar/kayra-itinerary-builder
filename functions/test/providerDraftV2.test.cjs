const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  DraftBoundaryError,
  validateDraftPayload,
} = require('../lib/itineraryExtraction/draftValidation');
const {
  normalizeItineraryExtractionV2,
} = require('../lib/itineraryExtraction/providerDraftV2');

const invalidExtraction = (error) =>
  error instanceof DraftBoundaryError &&
  error.code === 'INVALID_EXTRACTION_RESULT';

function sourceFile(sourceFileId) {
  return {
    sourceFileId,
    packageId: 'package-1',
    originalFileName: `${sourceFileId}.pdf`,
    storagePath: `trips/trip-1/supplier_sources/${sourceFileId}/source.pdf`,
    contentType: 'application/pdf',
    sizeBytes: 100,
    uploadedByUid: 'agent-1',
  };
}

function trustedPackage(fileIds = ['file-1', 'file-2']) {
  return {
    tripId: 'trip-1',
    packageId: 'package-1',
    supplierId: 'supplier-1',
    supplierNameSnapshot: 'Supplier',
    files: fileIds.map(sourceFile),
  };
}

function normalize(payload, packageValue = trustedPackage()) {
  const expanded = normalizeItineraryExtractionV2(payload, packageValue);
  return validateDraftPayload(expanded, packageValue);
}

test('sparse optional fields expand to the unchanged persisted shape', () => {
  const result = normalize({
    title: 'Sparse trip',
    days: [{title: 'Arrival', services: [{type: 'other'}]}],
  });
  const day = result.days[0];
  const service = day.services[0];
  assert.deepEqual(day, {
    dayNumber: 1,
    date: null,
    title: 'Arrival',
    summary: null,
    services: [service],
    notes: null,
  });
  assert.deepEqual(service, {
    id: 'service-d1-s1',
    type: 'other',
    title: 'Other service',
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
    sourceReference: {
      supplierSourcePackageId: 'package-1',
      supplierSourceFileId: null,
      sourceLabel: null,
    },
  });
  assert.deepEqual(result.reviewIssues, []);
});

test('day numbers and service IDs are deterministic from provider order', () => {
  const result = normalize({
    title: 'Ordered trip',
    days: [
      {title: 'First', services: [{type: 'meal'}, {type: 'free_time'}]},
      {title: 'Second', services: [{type: 'sightseeing'}]},
    ],
  });
  assert.deepEqual(result.days.map((day) => day.dayNumber), [1, 2]);
  assert.deepEqual(result.days.flatMap((day) =>
    day.services.map((service) => service.id)), [
    'service-d1-s1', 'service-d1-s2', 'service-d2-s1',
  ]);
});

test('typed service details stay sparse at input and expand only their branch', () => {
  const result = normalize({
    title: 'Typed trip',
    days: [{
      title: 'Services',
      services: [
        {type: 'hotel', hotelDetails: {hotelName: 'Harbour Hotel'}},
        {
          type: 'transfer',
          transferDetails: {pickup: 'Airport', dropoff: 'Hotel'},
        },
        {
          type: 'activity',
          activityDetails: {activityName: 'Desert safari'},
        },
      ],
    }],
  });
  const [hotel, transfer, activity] = result.days[0].services;
  assert.equal(hotel.title, 'Harbour Hotel');
  assert.deepEqual(hotel.hotelDetails, {
    hotelName: 'Harbour Hotel',
    checkInDate: null,
    checkOutDate: null,
    roomType: null,
    mealPlan: null,
    numberOfRooms: null,
    supplierStarRating: null,
  });
  assert.equal(hotel.transferDetails, null);
  assert.equal(hotel.activityDetails, null);
  assert.equal(transfer.title, 'Airport to Hotel');
  assert.deepEqual(transfer.transferDetails, {
    pickup: 'Airport',
    dropoff: 'Hotel',
    vehicleType: null,
    transferType: null,
  });
  assert.equal(activity.title, 'Desert safari');
  assert.deepEqual(activity.activityDetails, {
    activityName: 'Desert safari',
    duration: null,
    activityType: null,
  });
});

test('neutral title fallbacks are deterministic and source titles win', () => {
  const result = normalize({
    title: 'Titles',
    days: [{
      title: 'Day',
      services: [
        {type: 'hotel'},
        {type: 'transfer'},
        {type: 'activity'},
        {type: 'meal'},
        {type: 'sightseeing'},
        {type: 'free_time'},
        {type: 'other'},
        {type: 'other', title: 'Supplier welcome service'},
      ],
    }],
  });
  assert.deepEqual(result.days[0].services.map((service) => service.title), [
    'Hotel',
    'Transfer',
    'Activity',
    'Meal',
    'Sightseeing',
    'Free time',
    'Other service',
    'Supplier welcome service',
  ]);
});

test('irrelevant detail branches and provider-owned structural IDs are rejected', () => {
  for (const service of [
    {type: 'meal', hotelDetails: {hotelName: 'Injected'}},
    {type: 'hotel', transferDetails: {pickup: 'A', dropoff: 'B'}},
    {type: 'transfer', activityDetails: {activityName: 'Injected'}},
    {type: 'other', id: 'provider-id'},
  ]) {
    assert.throws(
      () => normalize({
        title: 'Invalid',
        days: [{title: 'Day', services: [service]}],
      }),
      invalidExtraction,
    );
  }
  assert.throws(
    () => normalize({title: 'Invalid', days: [{dayNumber: 8, title: 'Day'}]}),
    invalidExtraction,
  );
});

test('single-file provenance automatically uses the sole trusted file', () => {
  const result = normalize({
    title: 'Single source',
    days: [{title: 'Day', services: [{type: 'meal'}]}],
  }, trustedPackage(['only-file']));
  assert.deepEqual(result.days[0].services[0].sourceReference, {
    supplierSourcePackageId: 'package-1',
    supplierSourceFileId: 'only-file',
    sourceLabel: null,
  });
});

test('multi-file 1-based provenance maps through trusted package order', () => {
  const result = normalize({
    title: 'Multiple sources',
    days: [{
      title: 'Day',
      services: [{
        type: 'meal',
        source: {fileIndex: 2, sourceLabel: 'Page 4'},
      }],
    }],
  });
  assert.deepEqual(result.days[0].services[0].sourceReference, {
    supplierSourcePackageId: 'package-1',
    supplierSourceFileId: 'file-2',
    sourceLabel: 'Page 4',
  });
});

test('invalid file indexes and provider-supplied trusted IDs are rejected', () => {
  for (const source of [
    {fileIndex: 0},
    {fileIndex: 3},
    {fileIndex: 1.5},
    {fileIndex: '1'},
    {supplierSourcePackageId: 'package-1'},
    {supplierSourceFileId: 'file-1'},
  ]) {
    assert.throws(
      () => normalize({
        title: 'Invalid source',
        days: [{
          title: 'Day',
          services: [{type: 'meal', source}],
        }],
      }),
      invalidExtraction,
    );
  }
});

test('review issues receive stable IDs and preserve semantic fields', () => {
  const result = normalize({
    title: 'Review trip',
    days: [],
    reviewIssues: [
      {
        fieldPath: 'days[0].date',
        message: 'Date is ambiguous.',
        severity: 'warning',
      },
      {
        fieldPath: 'days[1].services[0]',
        message: 'Service cannot be identified.',
        severity: 'blocker',
      },
    ],
  });
  assert.deepEqual(result.reviewIssues, [
    {
      id: 'review-1',
      fieldPath: 'days[0].date',
      message: 'Date is ambiguous.',
      severity: 'warning',
    },
    {
      id: 'review-2',
      fieldPath: 'days[1].services[0]',
      message: 'Service cannot be identified.',
      severity: 'blocker',
    },
  ]);
});

test('provider review IDs, invalid severity, and explicit nulls are rejected', () => {
  for (const payload of [
    {
      title: 'Invalid',
      days: [],
      reviewIssues: [{
        id: 'provider-id',
        fieldPath: 'days[0]',
        message: 'Problem',
        severity: 'warning',
      }],
    },
    {
      title: 'Invalid',
      days: [],
      reviewIssues: [{
        fieldPath: 'days[0]',
        message: 'Problem',
        severity: 'info',
      }],
    },
    {title: 'Invalid', days: [{title: 'Day', summary: null}]},
  ]) {
    assert.throws(() => normalize(payload), invalidExtraction);
  }
});
