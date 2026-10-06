function importResult() {
  return {extractionId: 'extraction-1', resolutionId: 'extraction-1',
    evaluatedRevision: 3, sourcePackageId: 'package-1', finalizationId: 'finalize-1',
    policyVersion: 'supplier_import_exception_review_v1'};
}

function provenance(stagedFactId = 'package-fact-1') {
  return {origin: 'supplier', extractionId: 'extraction-1', sourcePackageId: 'package-1',
    contributors: [{stagedFactId, sources: [{supplierSourceFileId: 'file-1', sourceLabel: 'Page 2'}]}],
    resolutionId: 'extraction-1', evaluatedRevision: 3, decisionIds: [], fieldChanges: []};
}

function hotel(overrides = {}) {
  return {hotelName: 'Example Hotel', city: 'Dubai', orSimilar: true,
    checkInDate: null, checkOutDate: null, nightCount: 3, roomType: 'Deluxe',
    mealPlan: 'Breakfast', numberOfRooms: 2, supplierStarRating: '5 Star', ...overrides};
}

function accommodation(id = 'stay-1', order = 1) {
  return {id, order, selection: 'single', options: [
    {id: `${id}-option-1`, order: 1, details: hotel(), provenance: provenance(id)},
  ]};
}

function statement(id = 'inclusion-1', order = 1) {
  return {id, order, category: 'meal', text: 'Lunches', quantity: 5,
    frequency: 'per stay', appliesTo: ['meal'], provenance: provenance(id)};
}

function condition(id = 'condition-1', order = 1) {
  return {id, order, kind: 'operating_basis', value: 'Shared basis',
    appliesTo: ['transfer'], provenance: provenance(id)};
}

function service(type = 'other', id = `service-${type}`) {
  return {id, type, title: 'Local visit', description: null, startTime: null,
    endTime: null, location: null, city: null, inclusions: [], exclusions: [], notes: null,
    hotelDetails: null, transferDetails: null, activityDetails: null, sourceReference: null};
}

function day(dayNumber = 1, services = []) {
  return {dayNumber, date: null, title: 'Arrival', summary: null, services, notes: null};
}

function minimal() {
  return {tripId: 'trip-1', schemaVersion: 'itinerary_draft_v2', title: 'Dubai visit',
    days: [], sourcePackageIds: ['package-1'], reviewIssues: [], createdByUid: 'agent-1',
    createdAt: '2026-10-06T10:00:00.000Z', updatedAt: '2026-10-06T10:00:00.000Z',
    packageContent: {accommodations: [], inclusions: [], exclusions: [], conditions: []},
    importResult: importResult()};
}

function full() {
  const data = minimal();
  const hotelService = service('hotel');
  hotelService.hotelDetails = {hotelName: 'Timeline Hotel', checkInDate: '2027-01-10',
    checkOutDate: '2027-01-12', roomType: 'Twin', mealPlan: 'Breakfast',
    numberOfRooms: 1, supplierStarRating: null};
  hotelService.sourceReference = {supplierSourcePackageId: 'package-1',
    supplierSourceFileId: 'file-1', sourceLabel: 'Page 1'};
  const transferService = service('transfer');
  transferService.transferDetails = {pickup: 'Airport', dropoff: 'Hotel', vehicleType: 'Sedan', transferType: 'private'};
  const activityService = service('activity');
  activityService.activityDetails = {activityName: 'Museum visit', duration: '2 hours', activityType: 'Guided'};
  data.days = [{...day(1, [hotelService, transferService, activityService]), date: '2027-01-10'}];
  data.reviewIssues = [{id: 'warning-1', fieldPath: 'days[0].services[2].startTime',
    message: 'Timing not supplied.', severity: 'warning'}];
  data.packageContent = {accommodations: [accommodation()], inclusions: [statement()],
    exclusions: [{...statement('exclusion-1'), text: 'Dinners', quantity: 3}], conditions: [condition()]};
  return data;
}

module.exports = {minimal, full, importResult, provenance, hotel, accommodation, statement, condition, day, service};
