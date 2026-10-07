const {test} = require('node:test');
const assert = require('node:assert/strict');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const c = require('./itineraryDraftV2.fixtures.cjs');
const {normalizeProviderSupplierExtractionV3} = require('../lib/itineraryExtraction/providerSupplierExtractionV3');
const {parseSupplierExtractionSnapshotStructure} = require('../lib/itineraryExtraction/supplierExtractionStoredValidation');
const {validateSupplierImportResolution} = require('../lib/itineraryExtraction/supplierImportResolutionValidation');
const {assembleSupplierImportV2} = require('../lib/itineraryExtraction/supplierImportV2Assembly');
const {validateItineraryDraftV2} = require('../lib/itineraryExtraction/itineraryDraftV2Validation');
const context = {extractionId: 'extraction-1', tripId: 'trip-1', sourcePackageId: 'package-1',
  jobId: 'job-1', requestedByUid: 'agent-1', createdAt: new Date(f.at),
  trustedPackage: {tripId: 'trip-1', packageId: 'package-1', supplierId: 'supplier-1',
    supplierNameSnapshot: 'Synthetic supplier', files: [{sourceFileId: 'file-1', packageId: 'package-1',
      originalFileName: 'source.pdf', storagePath: 'trips/trip-1/supplier_sources/file-1/source.pdf',
      contentType: 'application/pdf', sizeBytes: 100, uploadedByUid: 'agent-1'}]}};
const normalize = (data) => normalizeProviderSupplierExtractionV3(data, context);
function rejectsSafely(operation, value) {
  assert.throws(operation, error => {
    assert.equal(String(error).includes(value), false);
    assert.equal(JSON.stringify(error).includes(value), false);
    return typeof error.code === 'string';
  });
}
const payloads = {
  title: v => ({title: {text: v, basis: 'explicit_supplier'}}),
  dayTitle: v => ({days: [{title: v}]}),
  daySummary: v => ({days: [{title: 'Day', summary: v}]}),
  dayNote: v => ({days: [{title: 'Day', notes: v}]}),
  serviceDescription: v => ({unassignedServices: [{title: 'Service', description: v}]}),
  serviceLocation: v => ({unassignedServices: [{title: 'Service', location: v}]}),
  serviceCity: v => ({unassignedServices: [{title: 'Service', city: v}]}),
  serviceNote: v => ({unassignedServices: [{title: 'Service', notes: v}]}),
  serviceInclusion: v => ({unassignedServices: [{title: 'Service', inclusions: [{category: 'other', text: v}]}]}),
  serviceExclusion: v => ({unassignedServices: [{title: 'Service', exclusions: [{category: 'other', text: v}]}]}),
  serviceCondition: v => ({unassignedServices: [{title: 'Service', conditions: [{kind: 'other', value: v}]}]}),
  hotel: v => ({packageFacts: {accommodations: [{hotelName: v}]}}),
  inclusion: v => ({packageFacts: {inclusions: [{category: 'other', text: v}]}}),
  exclusion: v => ({packageFacts: {exclusions: [{category: 'other', text: v}]}}),
  frequency: v => ({packageFacts: {inclusions: [{category: 'water', text: 'Water', frequency: v}]}}),
  condition: v => ({packageFacts: {conditions: [{kind: 'other', value: v}]}}),
  flight: v => ({ancillaryFacts: {flights: [{origin: 'DEL', notes: v}]}}),
  visa: v => ({ancillaryFacts: {visas: [{disposition: 'mentioned', text: v}]}}),
  issue: v => ({reviewIssues: [{code: 'other', severity: 'warning', message: v,
    target: {kind: 'snapshot'}, resolutionRequired: false}]}),
  sourceLabel: v => ({title: {text: 'Trip', basis: 'neutral_supported', sources: [{sourceLabel: v}]}}),
};
for (const [name, payload] of Object.entries(payloads)) {
  for (const [index, value] of ['Commission 12%', 'CNY 500'].entries()) {
    test(`provider and stored Snapshot reject ${name} commercial variant ${index}`, () => {
      const input = payload(value), original = JSON.stringify(input);
      rejectsSafely(() => normalize(input), value);
      assert.equal(JSON.stringify(input), original); // no stripping/repair
      const safe = normalize(payload('Safe wording'));
      // Inject into every occurrence of this free-text slot after normalization.
      const injected = JSON.parse(JSON.stringify(safe).replaceAll('Safe wording', value));
      rejectsSafely(() => parseSupplierExtractionSnapshotStructure(injected), value);
    });
  }
}
const source = f.snapshot({days: [f.day()], packageFacts: {
  accommodations: [{hotelName: 'Hotel'}], inclusions: [{category: 'meal', text: 'Breakfast'}],
  conditions: [{kind: 'guide', value: 'Local guide'}]}});
const aggregateCases = {
  day: v => ({decisions: [f.dayDecision('staged-day-1', {overrides: {notes: f.set(v)}})]}),
  service: v => ({decisions: [f.serviceDecision('staged-service-1', {overrides: {description: f.set(v)}})]}),
  list: v => ({decisions: [f.serviceDecision('staged-service-1', {overrides: {inclusions: f.set([v])}})]}),
  package: v => ({decisions: [f.packageDecision('package-fact-1', 'package_accommodation', {overrides: {roomType: f.set(v)}})]}),
  manualDay: v => ({manualItems: [f.manualDay(undefined, {notes: v})]}),
  manualService: v => ({manualItems: [f.manualService(undefined, {description: v})]}),
};
for (const [name, changes] of Object.entries(aggregateCases)) {
  test(`Resolution ${name} rejects injected commercial text and assembly blocks`, () => {
    const value = 'Commission 12%', aggregate = f.aggregate(source, changes(value));
    // Ensure shape/relationships are otherwise valid, not merely a malformed fixture.
    validateSupplierImportResolution(source, f.aggregate(source, changes('Safe wording')));
    rejectsSafely(() => validateSupplierImportResolution(source, aggregate), value);
    const result = assembleSupplierImportV2(source, aggregate, f.context());
    assert.equal(result.canFinalize, false); assert.equal(result.candidate, null);
    assert.equal(JSON.stringify(result).includes(value), false);
  });
}
for (const value of ['Commission 12%', 'CNY 500']) {
  test(`canonical and assembly defence rejects confirmed escape ${value.startsWith('CNY') ? 'currency' : 'commission'}`, () => {
    const snapshot = JSON.parse(JSON.stringify(source)); snapshot.days[0].notes = value;
    const result = assembleSupplierImportV2(snapshot, f.aggregate(source), f.context());
    assert.equal(result.canFinalize, false); assert.equal(result.candidate, null);
    assert.equal(JSON.stringify(result).includes(value), false);
    const draft = c.full(); draft.days[0].notes = value;
    rejectsSafely(() => validateItineraryDraftV2('draft-1', draft), value);
    assert.equal(draft.days[0].notes, value);
  });
}
test('safe numbers, punctuation and value-free commercial metadata survive unchanged', () => {
  const notes = '3 nights; 2 rooms; Breakfast for 3; Flight AI 302; Terminal 3; 100% vegetarian; $';
  const snapshot = normalize({days: [{title: 'Hotel 81', notes}], commercialContent: {
    present: true, categories: ['package_price', 'supplement', 'payment_terms']}});
  assert.equal(snapshot.days[0].notes, notes);
  assert.equal(snapshot.counts.commercialIndicators, 1);
  const result = assembleSupplierImportV2(snapshot, f.aggregate(snapshot), f.context());
  assert.equal(result.canFinalize, true);
  assert.equal(result.candidate.days[0].notes, notes);
  assert.equal(JSON.stringify(result.candidate).includes('commercial_presence'), false);
  // Existing generic non-commercial text permits coverage quantities; no new insurance schema.
  const draft = c.full(); draft.days[0].notes = '50,000 coverage';
  assert.equal(validateItineraryDraftV2('draft-1', draft).days[0].notes, '50,000 coverage');
});
