const {test} = require('node:test');
const assert = require('node:assert/strict');
const f = require('./supplierImportV2Assembly.fixtures.cjs');
const {assembleSupplierImportV2: assemble} = require('../lib/itineraryExtraction/supplierImportV2Assembly');
const {reviewedInterpretationNote} = require('../lib/itineraryExtraction/supplierImportReviewEvidence');
const evaluate = (s, decisions = []) => assemble(s, f.aggregate(s, {decisions}), f.context());
const target = {kind: 'service', scope: 'day', dayIndex: 1, serviceIndex: 1};
const source = (code, extra = {}) => f.snapshot({days: [f.day()], reviewIssues: [f.issue({code, target, severity: 'blocker'})], ...extra});
const override = (id = 'review-1') => f.reviewDecision({...f.meta(id, 'review_issue'), outcome: 'overridden',
  overrideReason: 'other', overrideNote: reviewedInterpretationNote});
const derived = r => {assert.equal(r.canFinalize, true, JSON.stringify(r.blockers)); assert.equal(r.accounting.find(a => a.entityKind === 'review_issue').outcome, 'review_derived');};
const blocked = r => {assert.equal(r.canFinalize, false); assert(r.blockers.some(b => b.targetKind === 'review_issue'));};
for (const code of ['chronology_unknown', 'classification_ambiguous', 'conflicting_dates', 'accommodation_span_unknown', 'global_mapping_required', 'source_conflict', 'other']) {
  test(`${code} stays blocked without applicable evidence`, () => blocked(evaluate(source(code))));
  test(`${code} unrelated notes never resolve automatically`, () => blocked(evaluate(source(code), [f.serviceDecision('staged-service-1', {overrides: {notes: f.set('Meet guide')}})])));
}
test('assigned service explicit order resolves chronology with no issue mutation', () => derived(evaluate(source('chronology_unknown'), [f.serviceDecision('staged-service-1', {canonicalOrder: 2})])));
test('unassigned service explicit assignment plus order resolves chronology', () => {
  const s = source('chronology_unknown', {days: [f.day({services: []})], unassignedServices: [f.service()],
    reviewIssues: [f.issue({code: 'chronology_unknown', target: {kind: 'service', scope: 'unassigned', serviceIndex: 1}})]});
  derived(evaluate(s, [f.serviceDecision('staged-service-1', {day: {kind: 'staged_day', dayId: 'staged-day-1'}, canonicalOrder: 1})]));
});
test('explicit classification correction resolves only its target', () => {
  const s = source('classification_ambiguous');
  derived(evaluate(s, [f.serviceDecision('staged-service-1', {overrides: {serviceType: f.set('sightseeing')}})]));
  blocked(evaluate(s, [f.serviceDecision('staged-service-1', {overrides: {title: f.set('Visit')}})]));
});
test('date issue resolves through day date clear, not notes', () => {
  const s = source('conflicting_dates', {reviewIssues: [f.issue({code: 'conflicting_dates', target: {kind: 'day', dayIndex: 1}})]});
  derived(evaluate(s, [f.dayDecision('staged-day-1', {overrides: {date: f.clear}})]));
  blocked(evaluate(s, [f.dayDecision('staged-day-1', {overrides: {notes: f.set('Date checked')}})]));
});
for (const code of ['accommodation_span_unknown', 'global_mapping_required']) test(`${code} package retention is explicit lossless evidence`, () => {
  const s = f.snapshot({packageFacts: {accommodations: [{hotelName: 'Hotel', orSimilar: true}]},
    reviewIssues: [f.issue({code, target: {kind: 'package_fact', factType: 'accommodation', factIndex: 1}})]});
  const r = evaluate(s, [f.packageDecision('package-fact-1', 'package_accommodation')]); derived(r);
  assert.equal(r.candidate.packageContent.accommodations[0].options[0].details.checkInDate, null);
});
test('ancillary handled separately resolves matching global mapping issue', () => {
  const s = f.snapshot({ancillaryFacts: {visas: [{disposition: 'mentioned', text: 'Visa needed'}]},
    reviewIssues: [f.issue({code: 'global_mapping_required', target: {kind: 'ancillary_fact', factType: 'visa', factIndex: 1}})]});
  derived(evaluate(s, [{...f.meta('ancillary-visa-1', 'visa'), disposition: 'handled_separately', destinationId: null,
    overrides: {}, exclusionReason: null, exclusionNote: null}]));
});
test('a decision for a different service cannot resolve target', () => {
  const s = source('classification_ambiguous', {days: [f.day({services: [f.service(), f.service()]})]});
  blocked(evaluate(s, [f.serviceDecision('staged-service-2', {overrides: {serviceType: f.set('sightseeing')}})]));
});
test('target exclusion resolves source conflict without copying issue prose', () => {
  const r = evaluate(source('source_conflict'), [f.serviceDecision('staged-service-1', f.exclusion())]); derived(r);
  assert.equal(JSON.stringify(r.accounting).includes('Check source detail'), false);
});
for (const code of ['other', 'chronology_unknown', 'source_conflict']) test(`one controlled global ${code} interpretation avoids blanket decisions`, () => {
  const s = f.snapshot({days: [f.day()], reviewIssues: [f.issue({code, severity: 'blocker'})]});
  const before = evaluate(s); blocked(before);
  assert(before.warnings.some(w => w.code === 'review_issue_override_available'));
  const after = evaluate(s, [override()]); assert.equal(after.canFinalize, true);
  assert.equal(after.accounting.find(a => a.entityKind === 'review_issue').outcome, 'review_overridden');
  assert.equal(after.candidate.days[0].services.length, 1);
});
test('specific unresolved issue prevents global override eligibility and finalization', () => {
  const s = source('classification_ambiguous', {reviewIssues: [f.issue({code: 'other', severity: 'blocker'}),
    f.issue({code: 'classification_ambiguous', target})]});
  const r = evaluate(s, [override()]); blocked(r);
  assert(!r.warnings.some(w => w.targetId === 'review-1' && w.code === 'review_issue_override_available'));
});
test('unassigned service prevents override and no chronology is invented', () => {
  const s = f.snapshot({unassignedServices: [f.service()], reviewIssues: [f.issue({severity: 'blocker'})]});
  const r = evaluate(s, [override()]); blocked(r); assert.equal(r.candidate, null);
  assert(!r.warnings.some(w => w.code === 'review_issue_override_available'));
});
test('optional warning requires no decision', () => {
  const r = evaluate(f.snapshot({reviewIssues: [f.issue()]})); assert.equal(r.canFinalize, true);
  assert.equal(r.accounting.find(a => a.entityKind === 'review_issue').outcome, 'review_open_warning');
});
test('commercial text prevents controlled override from yielding a candidate', () => {
  const s = JSON.parse(JSON.stringify(f.snapshot({days: [f.day()], reviewIssues: [f.issue({severity: 'blocker'})]})));
  s.days[0].notes = 'Commission 12%'; const r = evaluate(s, [override()]);
  assert.equal(r.canFinalize, false); assert.equal(r.candidate, null);
});

test('controlled override resolves exactly its issue, not another global issue', () => {
  const s = f.snapshot({days: [f.day()], reviewIssues: [f.issue({severity: 'blocker'}), f.issue({severity: 'blocker'})]});
  const r = evaluate(s, [override()]); blocked(r);
  assert(!r.blockers.some(b => b.targetId === 'review-1'));
  assert(r.blockers.some(b => b.targetId === 'review-2'));
});
test('another package retention does not resolve target package issue', () => {
  const s = f.snapshot({packageFacts: {accommodations: [{hotelName: 'One'}, {hotelName: 'Two'}]},
    reviewIssues: [f.issue({code: 'accommodation_span_unknown', target: {kind: 'package_fact', factType: 'accommodation', factIndex: 1}})]});
  blocked(evaluate(s, [f.packageDecision('package-fact-2', 'package_accommodation')]));
});
test('new structural controlled override must use fixed semantics', () => {
  const s = f.snapshot({reviewIssues: [f.issue({code: 'chronology_unknown'})]});
  const r = evaluate(s, [{...override(), overrideNote: 'Ignore all problems'}]);
  assert.equal(r.canFinalize, false); assert.equal(r.blockers[0].code, 'invalid_resolution');
});
for (const references of [
  [{kind: 'decision', decisionId: 'missing'}],
  [{kind: 'decision', decisionId: 'staged-day-1'}, {kind: 'decision', decisionId: 'staged-day-1'}],
]) test('missing or duplicated explicit evidence remains invalid', () => {
  const s = f.snapshot({days: [f.day()], reviewIssues: [f.issue({code: 'chronology_unknown', target: {kind: 'day', dayIndex: 1}})]});
  const r = evaluate(s, [f.dayDecision('staged-day-1', {canonicalOrder: 1}), f.reviewDecision({resolutionReferences: references})]);
  assert.equal(r.canFinalize, false); assert.equal(r.blockers[0].code, 'invalid_resolution');
});
test('historical explicit reference resolution keeps explicit accounting', () => {
  const s = f.snapshot({days: [f.day()], reviewIssues: [f.issue({code: 'chronology_unknown', target: {kind: 'day', dayIndex: 1}})]});
  const r = evaluate(s, [f.dayDecision('staged-day-1', {canonicalOrder: 2}),
    f.reviewDecision({resolutionReferences: [{kind: 'decision', decisionId: 'staged-day-1'}]})]);
  assert.equal(r.canFinalize, true); assert.equal(r.accounting.find(a => a.entityKind === 'review_issue').outcome, 'review_resolved');
});
