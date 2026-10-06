const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  snapshot, root, aggregate, meta, dayDecision, serviceDecision, exclusion,
  manualDay, manualService, context, set, clear, service, day, packageDecision, issue, reviewDecision,
} = require('./supplierImportV2Assembly.fixtures.cjs');
const {assembleSupplierImportV2} = require('../lib/itineraryExtraction/supplierImportV2Assembly');
const {assessSupplierImportFinalization} = require('../lib/itineraryExtraction/supplierImportFinalizationAssessment');
const {serializeItineraryDraftV2, itineraryDraftV2ToMap, validateItineraryDraftV2} = require('../lib/itineraryExtraction/itineraryDraftV2Validation');
const assemble = (source, changes = {}, trusted = context()) => assembleSupplierImportV2(source, aggregate(source, changes), trusted);
const ready = (result) => {assert.equal(result.canFinalize, true, JSON.stringify(result.blockers)); assert(result.candidate); return result.candidate;};
const blocked = (result, code) => {assert.equal(result.canFinalize, false); assert.equal(result.candidate, null); if (code) assert(result.blockers.some((b) => b.code === code), JSON.stringify(result.blockers));};
const firstService = (result) => ready(result).days[0].services[0];
const packageRows = (result) => result.accounting.filter((item) => item.entityKind.startsWith('package_'));
const dayRef = (id = 'staged-day-1') => ({kind: 'staged_day', dayId: id});
const serviceRef = {kind: 'staged_service', serviceId: 'staged-service-1'};

// A-D, AV, BU: the ordinary no-decision path is the primary behavior.
test('untouched assigned day and service carry automatically with extracted title', () => {
  const source = snapshot({days: [day({date: '2027-01-01', summary: 'Arrive', notes: 'Meet guide'})]});
  const result = assemble(source), draft = ready(result);
  assert.equal(draft.title, source.title.text);
  assert.equal(draft.days[0].title, 'Arrival');
  assert.equal(draft.days[0].date.toISOString(), '2027-01-01T00:00:00.000Z');
  assert.equal(draft.days[0].services[0].title, 'Museum visit');
  assert.deepEqual(result.blockers, []);
  assert.equal(result.accounting.find((a) => a.entityKind === 'service').outcome, 'auto_retained');
});
test('explicit day and service retain produces the same content', () => {
  const source = snapshot({days: [day()]});
  const result = assemble(source, {decisions: [dayDecision('staged-day-1'), serviceDecision('staged-service-1')]});
  assert.deepEqual(itineraryDraftV2ToMap(ready(result)), itineraryDraftV2ToMap(ready(assemble(source))));
});
test('explicit service exclusion wins and does not delete its source evidence', () => {
  const source = snapshot({days: [day()]});
  const result = assemble(source, {decisions: [serviceDecision('staged-service-1', exclusion())]});
  assert.equal(ready(result).days[0].services.length, 0);
  assert.equal(source.facts.length, 1);
  assert.equal(result.accounting.find((a) => a.entityKind === 'service').outcome, 'excluded');
});
test('explicit day exclusion removes day when dependencies are excluded', () => {
  const source = snapshot({days: [day()]});
  assert.deepEqual(ready(assemble(source, {decisions: [dayDecision('staged-day-1', exclusion()), serviceDecision('staged-service-1', exclusion())]})).days, []);
});
test('excluded day cannot strand an untouched included service', () => {
  const source = snapshot({days: [day()]});
  blocked(assemble(source, {decisions: [dayDecision('staged-day-1', exclusion())]}), 'invalid_resolution');
});
for (const [field, sourceValue, change, expected] of [
  ['title', 'Arrival', set('Corrected day'), 'Corrected day'],
  ['date', '2027-01-01', clear, null],
  ['summary', 'Original summary', set('Corrected summary'), 'Corrected summary'],
  ['notes', 'Original notes', clear, null],
]) test(`day sparse ${field} correction`, () => {
  const source = snapshot({days: [day({[field]: sourceValue})]});
  const output = ready(assemble(source, {decisions: [dayDecision('staged-day-1', {overrides: {[field]: change}})]})).days[0];
  assert.equal(output[field], expected);
});
for (const [field, value] of [['title', 'Corrected visit'], ['description', 'Meet at entrance'], ['startTime', '09:30'], ['endTime', '11:00'], ['location', 'Old town'], ['city', 'City centre'], ['notes', 'Bring hat']]) {
  test(`service common ${field} override survives`, () => {
    const source = snapshot({days: [day()]});
    assert.equal(firstService(assemble(source, {decisions: [serviceDecision('staged-service-1', {overrides: {[field]: set(value)}})]}))[field], value);
  });
}
test('untouched optional service value survives while explicit clear removes another', () => {
  const source = snapshot({days: [day({services: [service({description: 'Tour entrance', notes: 'Call guide'})]})]});
  const result = firstService(assemble(source, {decisions: [serviceDecision('staged-service-1', {overrides: {notes: clear}})]}));
  assert.equal(result.description, 'Tour entrance'); assert.equal(result.notes, null);
});
for (const [type, sourceDetails, overrides, field, value] of [
  ['hotel', {hotelName: 'Original hotel', roomType: 'Double'}, {hotelName: set('Correct hotel'), roomType: clear}, 'hotelName', 'Correct hotel'],
  ['transfer', {pickup: 'Airport', dropoff: 'Hotel'}, {vehicleType: set('Minivan'), transferType: set('private')}, 'vehicleType', 'Minivan'],
  ['activity', {activityName: 'Boat tour'}, {duration: set('Two hours'), activityType: set('Shared tour')}, 'duration', 'Two hours'],
]) test(`compatible ${type} correction applies`, () => {
  const source = snapshot({days: [day({services: [service({type, [`${type}Details`]: sourceDetails})]})]});
  assert.equal(firstService(assemble(source, {decisions: [serviceDecision('staged-service-1', {overrides: {[type]: overrides}})]}))[`${type}Details`][field], value);
});
test('service type correction from generic to activity uses explicit details', () => {
  const source = snapshot({days: [day()]});
  const out = firstService(assemble(source, {decisions: [serviceDecision('staged-service-1', {overrides: {serviceType: set('activity'), activity: {activityName: set('Museum')}}})]}));
  assert.equal(out.type, 'activity'); assert.equal(out.activityDetails.activityName, 'Museum');
});
test('service type change cannot discard surviving incompatible details', () => {
  const source = snapshot({days: [day({services: [service({type: 'hotel', hotelDetails: {hotelName: 'Hotel'}})]})]});
  blocked(assemble(source, {decisions: [serviceDecision('staged-service-1', {overrides: {serviceType: set('other')}})]}), 'unsupported_service_content');
});
test('explicit service move honors target and order', () => {
  const source = snapshot({days: [day(), day({title: 'Later', services: []})]});
  const out = ready(assemble(source, {decisions: [serviceDecision('staged-service-1', {day: dayRef('staged-day-2'), canonicalOrder: 3})]}));
  assert.equal(out.days[0].services.length, 0); assert.equal(out.days[1].services[0].title, 'Museum visit');
});
test('unassigned service never gains inferred chronology from dates or cities', () => {
  const source = snapshot({days: [day({date: '2027-01-01', services: []})], unassignedServices: [service({city: 'Same city', startTime: '08:00'})]});
  blocked(assemble(source), 'unresolved_unassigned_service');
});
test('unassigned service explicitly assigned with order is ready', () => {
  const source = snapshot({days: [day({services: []})], unassignedServices: [service()]});
  assert.equal(firstService(assemble(source, {decisions: [serviceDecision('staged-service-1', {day: dayRef(), canonicalOrder: 2})]})).title, 'Museum visit');
});
test('unassigned service needs explicit order after assignment', () => {
  const source = snapshot({days: [day({services: []})], unassignedServices: [service()]});
  blocked(assemble(source, {decisions: [serviceDecision('staged-service-1', {day: dayRef()})]}), 'missing_service_order');
});
test('unassigned service may be explicitly excluded', () => {
  const source = snapshot({unassignedServices: [service()]});
  assert.deepEqual(ready(assemble(source, {decisions: [serviceDecision('staged-service-1', exclusion())]})).days, []);
});
for (const target of ['missing-day', 'staged-day-2']) test(`assignment to unavailable ${target} fails closed`, () => {
  const source = snapshot({days: [day(), day({services: []})]});
  blocked(assemble(source, {decisions: [serviceDecision('staged-service-1', {day: dayRef(target), canonicalOrder: 1}), dayDecision('staged-day-2', exclusion())]}), 'invalid_resolution');
});
test('manual days and services preserve human origin and no supplier locator', () => {
  const source = snapshot({days: [day()]});
  const result = assemble(source, {manualItems: [manualDay(), manualService('consultant-service-1', {day: {kind: 'consultant_day', manualDayId: 'consultant-day-1'}})]});
  const draft = ready(result), out = draft.days[1].services[0];
  assert.equal(draft.days[1].title, 'Consultant day'); assert.equal(out.sourceReference, null);
  for (const row of result.accounting.filter((a) => a.outcome === 'manual')) {
    assert.equal(row.origin, 'consultant'); assert.deepEqual(row.sources, []); assert.deepEqual(row.decisionIds, []);
  }
});
test('manual service may target a retained source day', () => {
  const source = snapshot({days: [day()]});
  assert.equal(ready(assemble(source, {manualItems: [manualService()]})).days[0].services.length, 2);
});
test('manual service incompatible type/details is rejected', () => {
  const source = snapshot({days: [day()]});
  blocked(assemble(source, {manualItems: [manualService('consultant-service-1', {serviceType: 'hotel'})]}), 'invalid_resolution');
});

// Package-content defaults and closed accounting.
const packagePayload = () => ({packageFacts: {accommodations: [{hotelName: 'Hotel One', city: 'Hanoi', orSimilar: true, nightCount: 3, roomType: 'Twin', mealPlan: 'Breakfast', numberOfRooms: 2}],
  inclusions: [{category: 'water', text: 'Drinking water', quantity: 2, frequency: 'Daily', appliesTo: ['transfer']}],
  exclusions: [{category: 'other', text: 'Personal expenses'}],
  conditions: [{kind: 'availability', value: 'Subject to availability', appliesTo: ['hotel']}]}});
for (const key of ['accommodations', 'inclusions', 'exclusions', 'conditions']) test(`safe untouched package ${key} auto-carries without a retain click`, () => {
  const result = assemble(snapshot(packagePayload()));
  assert.equal(ready(result).packageContent[key].length, 1);
  assert.equal(packageRows(result).length, 4);
  assert(packageRows(result).every((a) => a.outcome === 'auto_retained'));
  assert(!result.blockers.some((b) => b.code === 'package_level_destination_unavailable'));
});
test('global accommodation keeps hotel facts without inferred dates or fake days', () => {
  const draft = ready(assemble(snapshot(packagePayload()))), details = draft.packageContent.accommodations[0].options[0].details;
  assert.deepEqual(draft.days, []); assert.equal(details.city, 'Hanoi'); assert.equal(details.orSimilar, true);
  assert.equal(details.nightCount, 3); assert.equal(details.checkInDate, null); assert.equal(details.checkOutDate, null);
});
for (const [id, kind] of [['package-fact-1', 'package_accommodation'], ['package-fact-2', 'package_statement'], ['package-fact-3', 'package_statement'], ['package-fact-4', 'package_condition']]) {
  test(`explicit retain_package_level is non-blocking for ${id}`, () => {
    const result = assemble(snapshot(packagePayload()), {decisions: [packageDecision(id, kind)]});
    ready(result); assert.equal(packageRows(result).find((a) => a.entityId === id).outcome, 'explicit_retained');
  });
}
test('package corrections preserve untouched fields and record set/clear provenance', () => {
  const source = snapshot(packagePayload());
  const draft = ready(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_accommodation', {overrides: {roomType: set('Triple'), nightCount: clear}})]}));
  const option = draft.packageContent.accommodations[0].options[0];
  assert.equal(option.details.roomType, 'Triple'); assert.equal(option.details.nightCount, null); assert.equal(option.details.city, 'Hanoi');
  assert.deepEqual(option.provenance.fieldChanges, [{field: 'nightCount', operation: 'clear'}, {field: 'roomType', operation: 'set'}]);
});
test('explicit package exclusion wins over default and preserves exactly one ledger outcome', () => {
  const result = assemble(snapshot(packagePayload()), {decisions: [packageDecision('package-fact-2', 'package_statement', exclusion())]});
  assert.deepEqual(ready(result).packageContent.inclusions, []);
  assert.equal(packageRows(result).filter((a) => a.entityId === 'package-fact-2').length, 1);
  assert.equal(packageRows(result).find((a) => a.entityId === 'package-fact-2').outcome, 'excluded');
});
test('mapped accommodation is consumed once without a package copy', () => {
  const source = snapshot({days: [day({services: []})], packageFacts: {accommodations: [{hotelName: 'Hotel One', roomType: 'Twin'}]}});
  const result = assemble(source, {decisions: [packageDecision('package-fact-1', 'package_accommodation', {disposition: 'map_to_day_service', day: dayRef(), canonicalOrder: 1})]});
  assert.equal(firstService(result).hotelDetails.roomType, 'Twin'); assert.deepEqual(result.candidate.packageContent.accommodations, []);
  assert.equal(packageRows(result)[0].outcome, 'mapped');
});
for (const [field, value] of [['city', 'Hanoi'], ['nightCount', 3], ['orSimilar', true]]) test(`hotel timeline mapping cannot lose ${field}`, () => {
  const source = snapshot({days: [day({services: []})], packageFacts: {accommodations: [{hotelName: 'Hotel One', [field]: value}]}});
  blocked(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_accommodation', {disposition: 'map_to_day_service', day: dayRef(), canonicalOrder: 1})]}), 'unsupported_package_accommodation_content');
});
for (const kind of ['inclusions', 'exclusions']) test(`simple package ${kind} mapping consumes once with polarity preserved`, () => {
  const source = snapshot({days: [day()], packageFacts: {[kind]: [{category: 'meal', text: 'Breakfast'}]}});
  const result = assemble(source, {decisions: [packageDecision('package-fact-1', 'package_statement', {disposition: 'map_to_service', service: serviceRef, destination: kind === 'inclusions' ? 'service_inclusion' : 'service_exclusion'})]});
  assert.deepEqual(firstService(result)[kind], ['Breakfast']); assert.deepEqual(result.candidate.packageContent[kind], []);
  assert.equal(packageRows(result)[0].outcome, 'mapped');
});
for (const [field, value] of [['quantity', 2], ['frequency', 'Daily'], ['appliesTo', ['meal']]]) test(`structured statement mapping cannot flatten ${field}`, () => {
  const source = snapshot({days: [day()], packageFacts: {inclusions: [{category: 'meal', text: 'Breakfast', [field]: value}]}});
  blocked(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_statement', {disposition: 'map_to_service', service: serviceRef, destination: 'service_inclusion'})]}), 'unsupported_package_mapping');
});
test('explicitly clearing a statement qualifier makes its plain mapping representable', () => {
  const source = snapshot({days: [day()], packageFacts: {inclusions: [{category: 'meal', text: 'Breakfast', quantity: 2}]}});
  ready(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_statement', {disposition: 'map_to_service', service: serviceRef, destination: 'service_inclusion', overrides: {quantity: clear}})]}));
});
test('statement mapping to generic notes cannot discard inclusion polarity', () => {
  const source = snapshot({days: [day()], packageFacts: {inclusions: [{category: 'meal', text: 'Breakfast'}]}});
  blocked(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_statement', {disposition: 'map_to_service', service: serviceRef, destination: 'service_notes'})]}), 'unsupported_package_mapping');
});
for (const [kind, value, destination, field] of [['vehicle', 'Minivan', 'transfer_vehicle_type', 'vehicleType'], ['operating_basis', 'private', 'transfer_type', 'transferType']]) test(`condition maps losslessly to ${destination}`, () => {
  const source = snapshot({days: [day({services: [service({type: 'transfer', transferDetails: {pickup: 'Airport', dropoff: 'Hotel'}})]})], packageFacts: {conditions: [{kind, value}]}});
  const result = assemble(source, {decisions: [packageDecision('package-fact-1', 'package_condition', {disposition: 'map_to_service', service: serviceRef, destination})]});
  assert.equal(firstService(result).transferDetails[field], value); assert.deepEqual(result.candidate.packageContent.conditions, []);
});
test('condition mapping cannot overwrite a populated typed field', () => {
  const source = snapshot({days: [day({services: [service({type: 'transfer', transferDetails: {pickup: 'Airport', dropoff: 'Hotel', vehicleType: 'Sedan'}})]})], packageFacts: {conditions: [{kind: 'vehicle', value: 'Minivan'}]}});
  blocked(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_condition', {disposition: 'map_to_service', service: serviceRef, destination: 'transfer_vehicle_type'})]}), 'unsupported_package_mapping');
});
test('package order compacts gaps while retaining relative source order', () => {
  const source = snapshot({packageFacts: {inclusions: ['First', 'Second', 'Third'].map((text) => ({category: 'other', text}))}});
  const result = assemble(source, {decisions: [packageDecision('package-fact-2', 'package_statement', exclusion())]});
  assert.deepEqual(ready(result).packageContent.inclusions.map((item) => [item.order, item.text]), [[1, 'First'], [2, 'Third']]);
  assert.deepEqual(packageRows(result).map((row) => row.outcome), ['auto_retained', 'excluded', 'auto_retained']);
});

for (const target of [
  {kind: 'snapshot'}, {kind: 'day', dayIndex: 1},
  {kind: 'service', scope: 'day', dayIndex: 1, serviceIndex: 1},
  {kind: 'package_fact', factType: 'inclusion', factIndex: 1},
]) test(`unresolved blocking issue gates ${target.kind} default content`, () => {
  const source = snapshot({days: [day()], packageFacts: {inclusions: [{category: 'other', text: 'Museum admission'}]},
    reviewIssues: [issue({severity: 'blocker', target})]});
  const result = assemble(source);
  blocked(result, 'unresolved_review_issue');
  if (target.kind === 'package_fact') {
    assert.equal(packageRows(result)[0].outcome, 'blocked');
    assert.equal(result.accounting.find((row) => row.entityKind === 'service').outcome, 'auto_retained');
  }
});
test('resolution-required warning remains a gate until a concrete correction', () => {
  const source = snapshot({days: [day()], reviewIssues: [issue({resolutionRequired: true, target: {kind: 'day', dayIndex: 1}})]});
  blocked(assemble(source), 'unresolved_review_issue');
  ready(assemble(source, {decisions: [dayDecision('staged-day-1', {overrides: {notes: set('Clarified meeting point')}}),
    reviewDecision({resolutionReferences: [{kind: 'decision', decisionId: 'staged-day-1'}]})]}));
});
test('bare retain cannot pretend to resolve a resolution-required issue', () => {
  const source = snapshot({days: [day()], reviewIssues: [issue({resolutionRequired: true, target: {kind: 'day', dayIndex: 1}})]});
  blocked(assemble(source, {decisions: [dayDecision('staged-day-1'), reviewDecision({resolutionReferences: [{kind: 'decision', decisionId: 'staged-day-1'}]})]}), 'unresolved_review_issue');
});
for (const acknowledge of [false, true]) test(`optional nonstructural warning is nonblocking; acknowledge=${acknowledge}`, () => {
  const source = snapshot({days: [day()], reviewIssues: [issue()]});
  const result = assemble(source, {decisions: acknowledge ? [reviewDecision({outcome: 'acknowledged'})] : []});
  assert.equal(ready(result).reviewIssues.length, 1);
  assert.equal(result.warnings[0].code, acknowledge ? 'snapshot_warning_acknowledged' : 'snapshot_warning_open');
});
for (const code of ['chronology_unknown', 'accommodation_span_unknown', 'classification_ambiguous', 'conflicting_dates', 'global_mapping_required', 'source_conflict']) {
  test(`structural ${code} is a gate even when severity and flag are permissive`, () => {
    const source = snapshot({days: [day()], reviewIssues: [issue({code})]});
    blocked(assemble(source), 'structural_review_issue_unresolved');
    blocked(assemble(source, {decisions: [reviewDecision({outcome: 'acknowledged'})]}), 'structural_review_issue_unresolved');
  });
}
test('concrete chronology correction resolves its actual target', () => {
  const source = snapshot({days: [day()], reviewIssues: [issue({code: 'chronology_unknown', target: {kind: 'day', dayIndex: 1}})]});
  ready(assemble(source, {decisions: [dayDecision('staged-day-1', {canonicalOrder: 2}), reviewDecision({resolutionReferences: [{kind: 'decision', decisionId: 'staged-day-1'}]})]}));
});
test('unrelated concrete correction cannot resolve a targeted structural issue', () => {
  const source = snapshot({days: [day(), day({services: []})], reviewIssues: [issue({code: 'chronology_unknown', target: {kind: 'day', dayIndex: 1}})]});
  blocked(assemble(source, {decisions: [dayDecision('staged-day-1'), dayDecision('staged-day-2', {canonicalOrder: 3}),
    reviewDecision({resolutionReferences: [{kind: 'decision', decisionId: 'staged-day-1'}, {kind: 'decision', decisionId: 'staged-day-2'}]})]}), 'structural_review_issue_unresolved');
});
test('snapshot-wide blocker is not resolved by excluding one unrelated fact', () => {
  const source = snapshot({days: [day(), day({services: []})], reviewIssues: [issue({severity: 'blocker'})]});
  blocked(assemble(source, {decisions: [dayDecision('staged-day-2', exclusion()), reviewDecision({resolutionReferences: [{kind: 'decision', decisionId: 'staged-day-2'}]})]}), 'unresolved_review_issue');
});
test('targeted package exclusion can concretely resolve its issue', () => {
  const source = snapshot({packageFacts: {accommodations: [{hotelName: 'Hotel'}]}, reviewIssues: [issue({code: 'accommodation_span_unknown', target: {kind: 'package_fact', factType: 'accommodation', factIndex: 1}})]});
  ready(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_accommodation', exclusion()),
    reviewDecision({resolutionReferences: [{kind: 'decision', decisionId: 'package-fact-1'}]})]}));
});
test('retain-package is not a blanket waiver for ambiguous hotel span', () => {
  const source = snapshot({packageFacts: {accommodations: [{hotelName: 'Hotel'}]}, reviewIssues: [issue({code: 'accommodation_span_unknown', target: {kind: 'package_fact', factType: 'accommodation', factIndex: 1}})]});
  blocked(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_accommodation')]}), 'structural_review_issue_unresolved');
});
test('narrow other override remains valid with rationale', () => {
  const source = snapshot({reviewIssues: [issue({severity: 'blocker'})]});
  const result = assemble(source, {decisions: [reviewDecision({outcome: 'overridden', overrideReason: 'extracted_in_error', overrideNote: 'Confirmed source scope'})]});
  ready(result); assert.equal(result.warnings[0].code, 'review_issue_overridden');
});
test('title uses explicit correction without marketing fallback', () => {
  const source = snapshot();
  assert.equal(ready(assemble(source, {decisions: [{...meta('title', 'title'), disposition: 'override', overrides: {title: set('Reviewed itinerary')}}]})).title, 'Reviewed itinerary');
  const missing = JSON.parse(JSON.stringify(source)); missing.title = null;
  blocked(assemble(missing), 'invalid_snapshot');
});
test('day order is exact, sorted and can retain intentional gaps', () => {
  const source = snapshot({days: [day({title: 'First source', services: []}), day({title: 'Second source', services: []})]});
  const out = ready(assemble(source, {decisions: [dayDecision('staged-day-1', {canonicalOrder: 5})]}));
  assert.deepEqual(out.days.map((item) => [item.dayNumber, item.title]), [[2, 'Second source'], [5, 'First source']]);
});
test('day order collision is not silently compacted or resolved', () => {
  const source = snapshot({days: [day({services: []}), day({services: []})]});
  blocked(assemble(source, {decisions: [dayDecision('staged-day-1', {canonicalOrder: 2})]}), 'duplicate_day_order');
});
test('service order is exact and deterministic', () => {
  const source = snapshot({days: [day({services: [service({title: 'First source'}), service({title: 'Second source'})]})]});
  const out = ready(assemble(source, {decisions: [serviceDecision('staged-service-1', {canonicalOrder: 5})]}));
  assert.deepEqual(out.days[0].services.map((item) => item.title), ['Second source', 'First source']);
});
test('service order collision blocks including manual services', () => {
  const source = snapshot({days: [day()]});
  blocked(assemble(source, {manualItems: [manualService('consultant-service-1', {canonicalOrder: 1})]}), 'duplicate_service_order');
});
test('mapped accommodation order collisions block with existing service', () => {
  const source = snapshot({days: [day()], packageFacts: {accommodations: [{hotelName: 'Hotel'}]}});
  blocked(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_accommodation', {disposition: 'map_to_day_service', day: dayRef(), canonicalOrder: 1})]}), 'duplicate_service_order');
});
test('trusted package lineage preserves identities, revision, source locator and corrections', () => {
  const source = snapshot(packagePayload());
  const out = ready(assemble(source, {decisions: [packageDecision('package-fact-2', 'package_statement', {overrides: {text: set('Drinking water supplied')}})]}));
  const p = out.packageContent.inclusions[0].provenance;
  assert.equal(p.origin, 'supplier'); assert.equal(p.extractionId, source.extractionId);
  assert.equal(p.sourcePackageId, source.sourcePackageId); assert.equal(p.resolutionId, source.extractionId); assert.equal(p.evaluatedRevision, 1);
  assert.deepEqual(p.contributors, [{stagedFactId: 'package-fact-2', sources: [{supplierSourceFileId: 'file-1', sourceLabel: null}]}]);
  assert.deepEqual(p.decisionIds, ['package-fact-2']); assert.deepEqual(p.fieldChanges, [{field: 'text', operation: 'set'}]);
  assert(!JSON.stringify(out).includes('Synthetic Supplier'));
});
test('importResult contains linkage only and exact trusted output context', () => {
  const source = snapshot(); const ctx = context(); ctx.actorUid = 'admin-1'; ctx.finalizationId = 'trusted-finalization';
  const out = ready(assemble(source, {}, ctx));
  assert.deepEqual(out.importResult, {extractionId: source.extractionId, resolutionId: source.extractionId,
    evaluatedRevision: 1, sourcePackageId: source.sourcePackageId, finalizationId: 'trusted-finalization', policyVersion: ctx.policyVersion});
  assert.equal(out.id, ctx.draftId); assert.equal(out.createdByUid, 'admin-1'); assert.equal(out.createdAt.toISOString(), ctx.createdAt);
});
test('commercial marker alone is informational and never canonical content', () => {
  const source = snapshot({commercialContent: {present: true, categories: ['package_price']}});
  const result = assemble(source); ready(result);
  assert.equal(result.informational[0].code, 'commercial_presence');
  assert(!serializeItineraryDraftV2(result.candidate).includes('package_price'));
});
test('prohibited commercial text at stricter canonical boundary blocks without redaction', () => {
  // Normalizer permits operational prose without monetary values; V2 rejects commercial terms.
  const source = snapshot({days: [day({notes: 'Payment terms apply'})]});
  const result = assemble(source); blocked(result, 'canonical_validation_failed');
  assert(!JSON.stringify(result).includes('Payment terms apply'));
});
for (const kind of ['flight', 'visa']) {
  const ancillary = kind === 'flight' ? {flights: [{airline: 'Example Air'}]} : {visas: [{disposition: 'mentioned', text: 'Visa required'}]};
  test(`unresolved ${kind} remains an ancillary blocker`, () => blocked(assemble(snapshot({ancillaryFacts: ancillary})), 'unresolved_ancillary_fact'));
  for (const disposition of ['handled_separately', 'exclude', `route_to_${kind}_workflow`]) test(`${kind} ${disposition} preserves ancillary boundary`, () => {
    const source = snapshot({ancillaryFacts: ancillary});
    const result = assemble(source, {decisions: [{...meta(`ancillary-${kind}-1`, kind), disposition,
      destinationId: disposition.startsWith('route') ? 'existing-destination-1' : null,
      overrides: {}, exclusionReason: disposition === 'exclude' ? 'not_part_of_requested_itinerary' : null, exclusionNote: null}]});
    const out = ready(result); assert.deepEqual(out.days, []);
    assert.deepEqual(out.packageContent, {accommodations: [], inclusions: [], exclusions: [], conditions: []});
  });
}
test('ready candidate round-trips through authoritative V2 validator', () => {
  const source = snapshot({days: [day()], ...packagePayload()}); const out = ready(assemble(source));
  assert.deepEqual(serializeItineraryDraftV2(validateItineraryDraftV2(out.id, itineraryDraftV2ToMap(out))), serializeItineraryDraftV2(out));
});
test('invalid all-cleared accommodation cannot return ready', () => {
  const source = snapshot({packageFacts: {accommodations: [{hotelName: 'Hotel'}]}});
  blocked(assemble(source, {decisions: [packageDecision('package-fact-1', 'package_accommodation', {overrides: {hotelName: clear}})]}), 'canonical_validation_failed');
});
test('contradictory supplied accommodation dates and nights cannot return ready', () => {
  const source = snapshot({packageFacts: {accommodations: [{hotelName: 'Hotel', checkInDate: '2027-01-01', checkOutDate: '2027-01-04', nightCount: 2}]}});
  blocked(assemble(source), 'canonical_validation_failed');
});
for (const count of [256, 257]) test(`package record capacity ${count}`, () => {
  const source = snapshot({packageFacts: {inclusions: Array.from({length: count}, (_, i) => ({category: 'other', text: `Admission ${i + 1}`}))}});
  const result = assemble(source);
  if (count === 256) ready(result); else blocked(result, 'package_record_limit_exceeded');
  assert.equal(packageRows(result).length, count);
});
test('accommodation envelope plus option both count toward capacity', () => {
  const source = snapshot({packageFacts: {accommodations: Array.from({length: 129}, (_, i) => ({hotelName: `Hotel ${i + 1}`}))}});
  blocked(assemble(source), 'package_record_limit_exceeded');
});
test('no inaccurate JSON-byte Firestore capacity gate', () => {
  const source = snapshot({packageFacts: {inclusions: [{category: 'other', text: 'a'.repeat(1100000)}]}});
  assert.equal(ready(assemble(source)).packageContent.inclusions[0].text.length, 1100000);
});
test('same inputs produce byte-equivalent immutable output without mutating input', () => {
  const source = snapshot({days: [day()], ...packagePayload()}); const input = aggregate(source); const before = JSON.stringify({source, input});
  const a = assembleSupplierImportV2(source, input, context()), b = assembleSupplierImportV2(source, input, context());
  assert.equal(JSON.stringify(a), JSON.stringify(b)); assert.equal(JSON.stringify({source, input}), before);
  assert(Object.isFrozen(a)); assert(Object.isFrozen(a.candidate)); assert(Object.isFrozen(a.accounting));
  a.candidate.createdAt.setTime(0); assert.equal(a.candidate.createdAt.toISOString(), context().createdAt);
});
test('decision and manual array ordering does not change candidate or accounting', () => {
  const source = snapshot({days: [day()]});
  const decisions = [dayDecision('staged-day-1'), serviceDecision('staged-service-1')];
  const manualItems = [manualDay(), manualService()];
  assert.deepEqual(assemble(source, {decisions, manualItems}), assemble(source, {decisions: [...decisions].reverse(), manualItems: [...manualItems].reverse()}));
});
test('blocker and warning ordering is stable and assessment runs the same policy', () => {
  const source = snapshot({unassignedServices: [service(), service()], reviewIssues: [issue()]});
  const result = assemble(source), assessment = assessSupplierImportFinalization(source, aggregate(source));
  assert.deepEqual(assessment, (({candidate, accounting, ...rest}) => rest)(result));
  assert.deepEqual(result, assemble(source)); assert.equal(result.warnings.length, 1);
});
test('assessment uses V2 validation too, not only structural gates', () => {
  const source = snapshot({days: [day({notes: 'Payment terms apply'})]});
  assert.equal(assessSupplierImportFinalization(source, aggregate(source)).canFinalize, false);
});
for (const key of ['tripId', 'extractionId', 'sourcePackageId']) test(`malformed Resolution ${key} linkage is a safe blocker`, () => {
  const source = snapshot(); const input = aggregate(source); input.root[key] = 'foreign';
  blocked(assembleSupplierImportV2(source, input, context()), 'invalid_resolution');
});
test('malformed source cross-reference fails closed', () => {
  const source = JSON.parse(JSON.stringify(snapshot({days: [day()]}))); source.days[0].assignedServiceIds = ['missing'];
  blocked(assemble(source), 'invalid_snapshot');
});
test('foreign Snapshot source package cannot supply trusted provenance', () => {
  const source = JSON.parse(JSON.stringify(snapshot(packagePayload()))); source.facts[0].sources[0].supplierSourcePackageId = 'foreign';
  blocked(assemble(source), 'invalid_snapshot');
});
for (const change of [{tripId: 'foreign'}, {policyVersion: 'other'}, {createdAt: 'bad'}, {actorUid: ''}, {finalizationId: ''}]) test(`trusted context rejects ${Object.keys(change)[0]}`, () => {
  blocked(assemble(snapshot(), {}, {...context(), ...change}), 'invalid_assembly_context');
});
test('finalized Resolution remains terminal and cannot yield a new candidate', () => {
  const source = snapshot();
  blocked(assemble(source, {root: root(source, {status: 'finalized', revision: 2, finalizedByUid: 'agent-1', finalizedAt: context().createdAt, resultingDraftId: 'old-draft'})}), 'resolution_already_finalized');
});
test('unsupported timeline conditions and structured statements remain blockers', () => {
  for (const extra of [{conditions: [{kind: 'availability', value: 'Subject to availability'}]}, {inclusions: [{category: 'water', text: 'Water', quantity: 2}]}]) {
    const source = snapshot({days: [day({services: [service(extra)]})]});
    blocked(assemble(source), 'unsupported_service_content');
  }
});
test('assembly modules contain no persistence, provider, Firebase, clock or random dependency', () => {
  const directory = path.join(__dirname, '../src/itineraryExtraction');
  for (const name of fs.readdirSync(directory).filter((name) => name.startsWith('supplierImportV2') && name.endsWith('.ts'))) {
    const text = fs.readFileSync(path.join(directory, name), 'utf8');
    assert(!/from\s+["'][^"']*(?:firebase|provider|repository|writer|firestore|storage)/i.test(text), name);
    assert(!/Date\.now\(|Math\.random\(|randomUUID\(|new Date\(\)/.test(text), name);
  }
});

test('package validation identifies an invalid fact despite an unrelated chronology blocker', () => {
  const source = snapshot({unassignedServices: [service()], packageFacts: {accommodations: [{hotelName: 'Hotel', checkInDate: '2027-01-01', checkOutDate: '2027-01-04', nightCount: 2}], inclusions: [{category: 'other', text: 'Admission'}]}});
  const result = assemble(source); blocked(result, 'unresolved_unassigned_service');
  assert.equal(packageRows(result).find((row) => row.entityId === 'package-fact-1').outcome, 'blocked');
  assert.equal(packageRows(result).find((row) => row.entityId === 'package-fact-2').outcome, 'auto_retained');
});
test('assessment accepts explicit trusted context and matches assembly validation', () => {
  const source = snapshot(); const input = aggregate(source); const ctx = {...context(), tripId: 'foreign'};
  const assembly = assembleSupplierImportV2(source, input, ctx);
  assert.deepEqual(assessSupplierImportFinalization(source, input, ctx), (({candidate, accounting, ...rest}) => rest)(assembly));
});
test('day accounting names actual canonical day number rather than a nonexistent ID', () => {
  const source = snapshot({days: [day()]});
  const result = assemble(source, {manualItems: [manualDay()]}); ready(result);
  const rows = result.accounting.filter((row) => ['day', 'consultant_day'].includes(row.entityKind));
  assert.deepEqual(rows.map((row) => row.outputDayNumber).sort(), [1, 2]);
  assert(rows.every((row) => row.outputIds.length === 0));
});
test('nested service source locators remain in accounting', () => {
  const source = snapshot({days: [day({services: [service({sources: [{fileIndex: 1, sourceLabel: 'Page 1'}], inclusions: [{category: 'meal', text: 'Breakfast', sources: [{fileIndex: 1, sourceLabel: 'Page 2'}]}]})]})]});
  const result = assemble(source); ready(result);
  assert.deepEqual(result.accounting.find((row) => row.entityKind === 'service').sources.map((item) => item.sourceLabel), ['Page 1', 'Page 2']);
});
test('stored Snapshot reader still requires a trusted package after structural-validator reuse', () => {
  const {parseStoredSupplierExtractionSnapshot} = require('../lib/itineraryExtraction/supplierExtractionStoredValidation');
  assert.throws(() => parseStoredSupplierExtractionSnapshot(snapshot(), undefined));
});
test('supplier source order and exact-text duplicates are preserved in mapped string lists', () => {
  const source = snapshot({days: [day()], packageFacts: {inclusions: [{category: 'other', text: 'Admission'}, {category: 'other', text: 'Admission'}]}});
  const result = assemble(source, {decisions: [2, 1].map((i) => packageDecision(`package-fact-${i}`, 'package_statement', {disposition: 'map_to_service', service: serviceRef, destination: 'service_inclusion'}))});
  assert.deepEqual(firstService(result).inclusions, ['Admission', 'Admission']); assert.equal(packageRows(result).length, 2);
});
test('service list set/clear overrides preserve their exact independent semantics', () => {
  const source = snapshot({days: [day({services: [service({inclusions: [{category: 'meal', text: 'Breakfast'}], exclusions: [{category: 'other', text: 'Personal expenses'}]})]})]});
  const out = firstService(assemble(source, {decisions: [serviceDecision('staged-service-1', {overrides: {inclusions: clear, exclusions: set(['Gratuities'])}})]}));
  assert.deepEqual(out.inclusions, []); assert.deepEqual(out.exclusions, ['Gratuities']);
});
test('package statement and condition overrides preserve untouched/set/clear fields', () => {
  const source = snapshot(packagePayload());
  const out = ready(assemble(source, {decisions: [
    packageDecision('package-fact-2', 'package_statement', {overrides: {category: set('other'), text: set('Water supplied'), quantity: clear, appliesTo: clear}}),
    packageDecision('package-fact-4', 'package_condition', {overrides: {kind: set('other'), value: set('Bring identification'), appliesTo: clear}}),
  ]}));
  const statement = out.packageContent.inclusions[0];
  assert.equal(statement.category, 'other'); assert.equal(statement.frequency, 'Daily'); assert.equal(statement.quantity, null); assert.deepEqual(statement.appliesTo, []);
  assert.equal(out.packageContent.conditions[0].kind, 'other'); assert.equal(out.packageContent.conditions[0].value, 'Bring identification'); assert.deepEqual(out.packageContent.conditions[0].appliesTo, []);
});
