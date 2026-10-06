'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const {
  ItineraryDraftV2Error, validateItineraryDraftV2: validate,
  itineraryDraftV2FromMap: fromMap, itineraryDraftV2ToMap: toMap, serializeItineraryDraftV2: serialize,
} = require('../lib/itineraryExtraction/itineraryDraftV2Validation');
const {maxItineraryPackageRecords} = require('../lib/itineraryExtraction/itineraryDraftPackageContent');
const {validateDraftPayload} = require('../lib/itineraryExtraction/draftValidation');
const {containsCommercialTerm, containsCommercialValue} = require('../lib/itineraryExtraction/nonCommercialText');
const f = require('./itineraryDraftV2.fixtures.cjs');
const valid = (data = f.minimal()) => validate('draft-1', data);
const invalid = (data, message) => assert.throws(() => valid(data),
  (error) => error instanceof ItineraryDraftV2Error && error.code === 'INVALID_ITINERARY_DRAFT_V2' &&
    (!message || message.test(error.message)));
const option = (data) => data.packageContent.accommodations[0].options[0];
const statement = (data) => data.packageContent.inclusions[0];
const mutate = (fn) => { const data = f.full(); fn(data); invalid(data); };

test('minimal V2 is valid with empty timeline and four empty package arrays', () => {
  const input = f.minimal();
  const result = valid(input);
  assert.equal(result.id, 'draft-1');
  assert.equal(result.schemaVersion, 'itinerary_draft_v2');
  assert.deepEqual(toMap(result), input);
  assert.equal('id' in toMap(result), false);
  assert.ok(result.createdAt instanceof Date);
});

test('full V2 preserves timeline and every package category without assembly', () => {
  const input = f.full();
  const result = valid(input);
  assert.deepEqual(toMap(result), input);
  assert.equal(result.days[0].date.toISOString(), '2027-01-10T00:00:00.000Z');
  assert.equal(result.packageContent.inclusions[0].quantity, 5);
  assert.equal(result.packageContent.exclusions[0].quantity, 3);
  assert.equal(result.days[0].services.length, 3);
});

for (const version of [undefined, null, 'itinerary_draft_v1', 'itinerary_draft_v3', '']) {
  test(`V2 rejects missing/malformed/other version ${String(version)}`, () => {
    const data = f.minimal();
    if (version === undefined) delete data.schemaVersion;
    else data.schemaVersion = version;
    invalid(data);
  });
}

for (const field of Object.keys(f.minimal())) {
  test(`V2 root requires ${field}`, () => {
    const data = f.minimal(); delete data[field]; invalid(data);
  });
}

test('V1 remains valid, sorts days as before and rejects V2-specific fields', () => {
  const trusted = {packageId: 'package-1', files: [{sourceFileId: 'file-1'}]};
  const fixture = {title: ' Dubai visit ', days: [f.day(2), f.day(1)], reviewIssues: []};
  const before = JSON.stringify(fixture);
  const result = validateDraftPayload(fixture, trusted);
  assert.equal(result.title, 'Dubai visit');
  assert.deepEqual(result.days.map((day) => day.dayNumber), [1, 2]);
  assert.equal(JSON.stringify(fixture), before);
  invalid(fixture);
  for (const extra of [{packageContent: f.minimal().packageContent},
    {schemaVersion: 'itinerary_draft_v2'}, {importResult: f.importResult()}]) {
    assert.throws(() => validateDraftPayload({...fixture, ...extra}, trusted),
      (error) => error.code === 'INVALID_EXTRACTION_RESULT');
  }
  assert.throws(() => validateDraftPayload(f.minimal(), trusted));
});

test('legacy service fields, detail objects, optional trimming and list ordering survive', () => {
  const data = f.full();
  const s = data.days[0].services[0];
  s.description = '  '; s.inclusions = [' Breakfast ', '', ' Breakfast ', 'Transfer'];
  const legacy = validateDraftPayload({title: data.title, days: data.days, reviewIssues: data.reviewIssues},
    {packageId: 'package-1', files: [{sourceFileId: 'file-1'}]});
  const result = valid(data);
  assert.deepEqual(result.days, legacy.days);
  assert.deepEqual(result.reviewIssues, legacy.reviewIssues);
});

for (const key of ['accommodations', 'inclusions', 'exclusions', 'conditions']) {
  test(`packageContent requires ${key} array`, () => {
    for (const value of [null, {}, '']) mutate((data) => {data.packageContent[key] = value;});
    mutate((data) => {delete data.packageContent[key];});
  });
}

test('explicit hotel dates and nights are preserved without derivation', () => {
  const data = f.full();
  option(data).details = f.hotel({checkInDate: '2028-02-28', checkOutDate: '2028-03-02', nightCount: 3});
  assert.deepEqual(valid(data).packageContent.accommodations[0].options[0].details, option(data).details);
  option(data).details.nightCount = null;
  assert.equal(valid(data).packageContent.accommodations[0].options[0].details.nightCount, null);
});

test('undated hotel/nights do not acquire chronology or traveller-derived values', () => {
  const data = f.full();
  option(data).details.numberOfRooms = null;
  const details = valid(data).packageContent.accommodations[0].options[0].details;
  assert.equal(details.checkInDate, null); assert.equal(details.checkOutDate, null);
  assert.equal(details.nightCount, 3); assert.equal(details.numberOfRooms, null);
  const onlyRoom = Object.fromEntries(Object.keys(f.hotel()).map((key) => [key, null]));
  onlyRoom.roomType = 'Twin'; option(data).details = onlyRoom;
  assert.deepEqual(valid(data).packageContent.accommodations[0].options[0].details, onlyRoom);
});

test('partial hotel spans remain partial', () => {
  const data = f.full(); option(data).details.checkInDate = '2027-01-01';
  const details = valid(data).packageContent.accommodations[0].options[0].details;
  assert.equal(details.checkOutDate, null); assert.equal(details.nightCount, 3);
});

test('orSimilar preserves true, false and null without boolean coercion', () => {
  for (const qualifier of [true, false, null]) {
    const data = f.full(); option(data).details.orSimilar = qualifier;
    assert.equal(valid(data).packageContent.accommodations[0].options[0].details.orSimilar, qualifier);
  }
  for (const bad of ['true', 0, 1, undefined]) mutate((d) => {option(d).details.orSimilar = bad;});
});

test('explicit alternatives preserve separate options/details/provenance', () => {
  const data = f.full(); const item = data.packageContent.accommodations[0];
  item.selection = 'alternatives';
  item.options.push({...f.accommodation('stay-2').options[0], order: 2});
  assert.deepEqual(valid(data).packageContent.accommodations[0], item);
});

test('hotel selection and cardinality fail closed', () => {
  mutate((d) => {d.packageContent.accommodations[0].selection = 'alternatives';});
  mutate((d) => {d.packageContent.accommodations[0].options = [];});
  mutate((d) => {d.packageContent.accommodations[0].selection = 'both';});
  mutate((d) => {d.packageContent.accommodations[0].options.push({...f.accommodation('second').options[0], order: 2});});
});

test('empty hotel attributes and explicitly conflicting dates/nights are rejected', () => {
  mutate((d) => {option(d).details = Object.fromEntries(Object.keys(f.hotel()).map((key) => [key, null]));});
  for (const end of ['2027-01-01', '2026-12-31', '2027-01-03']) {
    mutate((d) => {Object.assign(option(d).details, {checkInDate: '2027-01-01', checkOutDate: end, nightCount: 3});});
  }
});

test('ordered inclusions and separate exclusions retain all structured fields', () => {
  const data = f.full(); data.packageContent.inclusions.push(f.statement('second', 2));
  const result = valid(data).packageContent;
  assert.deepEqual(result.inclusions, data.packageContent.inclusions);
  assert.deepEqual(result.exclusions, data.packageContent.exclusions);
  assert.equal(result.inclusions[0].text, 'Lunches');
  assert.equal(result.exclusions[0].text, 'Dinners');
});

test('all documented statement categories and service applicability enums validate', () => {
  for (const category of ['accommodation', 'meal', 'guide', 'water', 'entrance', 'transport', 'visa', 'other']) {
    const data = f.full(); statement(data).category = category;
    statement(data).appliesTo = ['hotel', 'transfer', 'activity', 'meal', 'sightseeing', 'free_time', 'other'];
    assert.equal(valid(data).packageContent.inclusions[0].category, category);
  }
  // Reading the visa vocabulary is not runtime carry-through/ancillary routing.
  mutate((d) => {statement(d).category = 'flights';});
});

test('all documented condition kinds preserve typed content', () => {
  for (const kind of ['operating_basis', 'vehicle', 'class', 'ticket_scope', 'availability', 'payment_basis', 'guide', 'other']) {
    const data = f.full(); data.packageContent.conditions[0].kind = kind;
    data.packageContent.conditions[0].value = kind === 'payment_basis' ? 'Direct payment' : 'As stated';
    assert.equal(valid(data).packageContent.conditions[0].kind, kind);
  }
  mutate((d) => {d.packageContent.conditions[0].kind = 'commercial_notes';});
});

test('direct payment is a narrow condition qualifier, never permission for amounts/terms', () => {
  const data = f.full(); const c = data.packageContent.conditions[0];
  c.kind = 'payment_basis'; c.value = 'Direct payment'; valid(data);
  for (const value of ['Direct payment USD 30', 'Direct payment, balance due in 30 days', 'Payment schedule']) {
    c.value = value; invalid(data);
  }
  c.kind = 'other'; c.value = 'Direct payment'; invalid(data);
});

for (const quantity of [0, -1, 1.5, '2', true, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
  test(`positive numeric fields reject ${String(quantity)} (${typeof quantity})`, () => {
    mutate((d) => {statement(d).quantity = quantity;});
    mutate((d) => {option(d).details.nightCount = quantity;});
    mutate((d) => {option(d).details.numberOfRooms = quantity;});
    mutate((d) => {d.importResult.evaluatedRevision = quantity;});
    mutate((d) => {d.days[0].dayNumber = quantity;});
  });
}

test('statement nullable facts retain explicit absence and reject malformed values', () => {
  const data = f.full(); Object.assign(statement(data), {quantity: null, frequency: null, appliesTo: []});
  assert.deepEqual(valid(data).packageContent.inclusions[0], statement(data));
  for (const frequency of ['', ' ', 7, {}, false]) mutate((d) => {statement(d).frequency = frequency;});
  for (const appliesTo of [null, 'meal', ['unknown'], ['meal', 'meal'], [1]]) mutate((d) => {statement(d).appliesTo = appliesTo;});
});

for (const field of ['supplierCost', 'supplierRate', 'sellingPrice', 'total', 'currency', 'supplement',
  'markup', 'margin', 'discount', 'paymentAmount', 'paymentSchedule', 'rawPricing']) {
  test(`commercial field ${field} rejected at every package/root boundary`, () => {
    mutate((d) => {d[field] = 100;});
    mutate((d) => {d.packageContent[field] = 100;});
    mutate((d) => {option(d).details[field] = 100;});
    mutate((d) => {statement(d)[field] = 100;});
    mutate((d) => {d.packageContent.exclusions[0][field] = 100;});
    mutate((d) => {d.packageContent.conditions[0][field] = 100;});
  });
}

test('commercial prose cannot hide in itinerary/package/lineage text', () => {
  for (const value of ['USD 30', '₹500', 'Rate: 300', 'Markup 10%', 'Margin 5%', 'Payment schedule']) {
    mutate((d) => {d.title = value;});
    mutate((d) => {statement(d).text = value;});
    mutate((d) => {statement(d).frequency = value;});
    mutate((d) => {option(d).details.roomType = value;});
    mutate((d) => {d.packageContent.conditions[0].value = value;});
    mutate((d) => {statement(d).provenance.contributors[0].sources[0].sourceLabel = value;});
    mutate((d) => {d.days[0].services[0].notes = value;});
  }
});

test('shared predicates retain distinct existing extraction/override policies', () => {
  assert.equal(containsCommercialValue('Direct payment'), false);
  assert.equal(containsCommercialTerm('Direct payment'), true);
  for (const value of ['USD 30', '30 USD', '$30', 'price 30', '30 cost']) assert.equal(containsCommercialValue(value), true);
  for (const value of ['5 lunches', '3 nights', '5 Star', 'Shared transfer']) {
    assert.equal(containsCommercialValue(value), false);
    assert.equal(containsCommercialTerm(value), false);
  }
});

test('trusted-shaped provenance preserves all contributors/locators and correction linkage', () => {
  const data = f.full(); const p = statement(data).provenance;
  p.contributors.push({stagedFactId: 'fact-2', sources: [{supplierSourceFileId: null, sourceLabel: null}]});
  p.decisionIds = ['decision-1']; p.fieldChanges = [{field: 'text', operation: 'set'}, {field: 'quantity', operation: 'clear'}];
  statement(data).quantity = null;
  assert.deepEqual(valid(data).packageContent.inclusions[0].provenance, p);
});

test('provenance shape is validated, not falsely authenticated against live sources', () => {
  const data = f.full(); statement(data).provenance.contributors[0].sources[0].supplierSourceFileId = 'backend-must-verify-file';
  assert.equal(valid(data).packageContent.inclusions[0].provenance.contributors[0].sources[0].supplierSourceFileId,
    'backend-must-verify-file');
});

test('source labels preserve page fractions but reject paths in both source shapes', () => {
  const data = f.full();
  statement(data).provenance.contributors[0].sources[0].sourceLabel = 'Page 1/2';
  data.days[0].services[0].sourceReference.sourceLabel = 'Page 1/2';
  assert.deepEqual(toMap(valid(data)), data);
  for (const label of ['gs://bucket/private', '/private/document.pdf', 'trips/trip-1/file.pdf']) {
    mutate((d) => {statement(d).provenance.contributors[0].sources[0].sourceLabel = label;});
    mutate((d) => {d.days[0].services[0].sourceReference.sourceLabel = label;});
  }
});

test('provenance must match import extraction/package/resolution/revision', () => {
  for (const key of ['extractionId', 'sourcePackageId', 'resolutionId', 'evaluatedRevision']) {
    mutate((d) => {statement(d).provenance[key] = key === 'evaluatedRevision' ? 4 : 'different';});
  }
  mutate((d) => {statement(d).provenance.origin = 'consultant';});
});

test('provenance rejects missing/duplicate contributors, locators and decision IDs', () => {
  for (const change of [
    (p) => {p.contributors = [];},
    (p) => {p.contributors.push(structuredClone(p.contributors[0]));},
    (p) => {p.contributors[0].sources = [];},
    (p) => {p.contributors[0].sources.push({...p.contributors[0].sources[0]});},
    (p) => {p.decisionIds = ['decision-1', 'decision-1'];},
    (p) => {p.contributors[0].stagedFactId = '../fact';},
  ]) mutate((d) => change(statement(d).provenance));
});

test('lineage field operations are closed, entity-specific and linked to decisions', () => {
  for (const changes of [[{field: 'hotelName', operation: 'set'}], [{field: 'text', operation: 'clear'}],
    [{field: 'quantity', operation: 'delete'}], [{field: 'quantity', operation: 'set', value: 3}],
    [{field: 'quantity', operation: 'set'}, {field: 'quantity', operation: 'clear'}]]) {
    mutate((d) => {statement(d).provenance.decisionIds = ['decision-1']; statement(d).provenance.fieldChanges = changes;});
  }
  mutate((d) => {statement(d).provenance.fieldChanges = [{field: 'text', operation: 'set'}];});
});

test('provenance and importResult reject private supplier/pricing/audit/source payloads', () => {
  for (const field of ['supplierName', 'supplierCost', 'snapshot', 'decisions', 'auditEvents', 'receipt', 'rawSource']) {
    mutate((d) => {statement(d).provenance[field] = 'private';});
    mutate((d) => {d.importResult[field] = 'private';});
  }
  for (const label of ['gs://private/file', 'https://private/file', 'x'.repeat(161)]) {
    mutate((d) => {statement(d).provenance.contributors[0].sources[0].sourceLabel = label;});
  }
});

test('importResult required, exact, current-policy and consistently linked', () => {
  for (const field of Object.keys(f.importResult())) mutate((d) => {delete d.importResult[field];});
  mutate((d) => {d.importResult = null;});
  mutate((d) => {d.importResult.resolutionId = 'another-extraction';});
  mutate((d) => {d.importResult.policyVersion = 'unknown';});
  mutate((d) => {d.importResult.finalizationId = 'x'.repeat(129);});
  mutate((d) => {d.sourcePackageIds = [];});
  mutate((d) => {d.sourcePackageIds = ['another-package'];});
  mutate((d) => {d.sourcePackageIds.push('package-1');});
});

for (const id of ['', ' ', ' padded', 'a/b', 'a\\b', '.', '..', 'a\n', 1, null]) {
  test(`malformed identity rejected: ${JSON.stringify(id)}`, () => {
    assert.throws(() => validate(id, f.minimal()), ItineraryDraftV2Error);
    mutate((d) => {statement(d).id = id;});
    mutate((d) => {d.importResult.finalizationId = id;});
    mutate((d) => {statement(d).provenance.contributors[0].sources[0].supplierSourceFileId = id === null ? {} : id;});
  });
}

test('canonical IDs are unique across package categories, options and timeline', () => {
  mutate((d) => {d.packageContent.inclusions.push({...f.statement('inclusion-1', 2)});});
  mutate((d) => {d.packageContent.exclusions[0].id = statement(d).id;});
  mutate((d) => {option(d).id = statement(d).id;});
  mutate((d) => {d.packageContent.accommodations[0].id = option(d).id;});
  mutate((d) => {d.days[0].services[0].id = statement(d).id;});
  mutate((d) => {d.days.push(f.day(2, [{...f.service(), id: d.days[0].services[0].id}]));});
  mutate((d) => {d.reviewIssues[0].id = statement(d).id;});
});

test('all explicit package orders are contiguous; malformed input is not sorted', () => {
  for (const order of [0, -1, '1', 1.5, 2]) {
    mutate((d) => {statement(d).order = order;});
    mutate((d) => {option(d).order = order;});
    mutate((d) => {d.packageContent.accommodations[0].order = order;});
  }
  mutate((d) => {d.packageContent.inclusions.push(f.statement('second', 1));});
  mutate((d) => {d.packageContent.inclusions = [f.statement('second', 2), f.statement()];});
});

test('timeline order is explicit; service/review/applicability order is preserved', () => {
  const data = f.full(); data.days.push(f.day(3, [f.service('meal')]));
  const before = JSON.stringify(data); valid(data);
  assert.equal(JSON.stringify(data), before);
  assert.deepEqual(toMap(valid(data)), data);
  data.days.reverse(); invalid(data);
  mutate((d) => {d.days.push(f.day(1));});
});

for (const date of ['2027-02-29', '2028-02-30', '2027-13-01', '2027-00-01', '2027-01-00',
  '2027-1-01', '01-01-2027', '2027-01-01T00:00:00Z', ' 2027-01-01', 1]) {
  test(`strict calendar date rejects ${JSON.stringify(date)}`, () => {
    mutate((d) => {option(d).details.checkInDate = date;});
    mutate((d) => {d.days[0].date = date;});
    mutate((d) => {d.days[0].services[0].hotelDetails.checkInDate = date;});
  });
}

test('timestamps require real canonical UTC instants and monotonic metadata', () => {
  for (const value of ['2027-02-30T00:00:00.000Z', '2026-10-06', '2026-10-06T10:00:00+00:00',
    '2026-10-06T25:00:00.000Z', new Date(), null]) mutate((d) => {d.createdAt = value;});
  mutate((d) => {d.updatedAt = '2025-01-01T00:00:00.000Z';});
});

test('unknown fields fail closed at every nested boundary', () => {
  for (const get of [(d) => d, (d) => d.packageContent, (d) => d.importResult,
    (d) => d.packageContent.accommodations[0], option, (d) => option(d).details, statement,
    (d) => statement(d).provenance, (d) => statement(d).provenance.contributors[0],
    (d) => statement(d).provenance.contributors[0].sources[0], (d) => d.days[0],
    (d) => d.days[0].services[0], (d) => d.days[0].services[0].hotelDetails,
    (d) => d.reviewIssues[0]]) mutate((d) => {get(d).unexpected = true;});
});

test('maps reject exotic objects, accessors, symbols and sparse arrays', () => {
  for (const value of [null, [], new Date(), new Map(), 1, 'map']) invalid(value);
  const withSymbol = f.minimal(); withSymbol[Symbol('hidden')] = 1; invalid(withSymbol);
  const getter = f.minimal(); Object.defineProperty(getter, 'title', {get() {throw Error('not evaluated');}});
  invalid(getter);
  const sparse = f.minimal(); sparse.days = Array(2); invalid(sparse);
});

test('service/detail incompatibility and unsupported enums remain rejected', () => {
  mutate((d) => {d.days[0].services[0].type = 'meal';});
  mutate((d) => {d.days[0].services[1].type = 'activity';});
  mutate((d) => {d.days[0].services[2].type = 'hotel';});
  mutate((d) => {d.days[0].services[0].type = 'flight';});
  mutate((d) => {d.days[0].services[1].transferDetails.transferType = 'unknown';});
  mutate((d) => {d.reviewIssues[0].severity = 'info';});
  mutate((d) => {d.days[0].services[0].sourceReference.supplierSourcePackageId = 'foreign';});
});

test('validated aggregate is deeply frozen and detached from caller-owned input', () => {
  const input = f.full(); const result = valid(input); const saved = serialize(result);
  input.title = 'Changed'; option(input).details.hotelName = 'Changed';
  statement(input).provenance.contributors[0].sources[0].sourceLabel = 'Changed';
  input.days[0].services.push(f.service());
  assert.equal(serialize(result), saved);
  for (const value of [result, result.days, result.days[0], result.days[0].services,
    result.sourcePackageIds, result.reviewIssues, result.importResult, result.packageContent,
    result.packageContent.accommodations, result.packageContent.inclusions,
    result.packageContent.exclusions, result.packageContent.conditions, option(result),
    option(result).details, statement(result).appliesTo, statement(result).provenance,
    statement(result).provenance.contributors, statement(result).provenance.contributors[0].sources]) {
    assert.ok(Object.isFrozen(value));
    assert.throws(() => {value.changed = true;}, TypeError);
  }
  assert.throws(() => result.days.push(f.day(2)), TypeError);
  assert.throws(() => {option(result).details.hotelName = 'Changed';}, TypeError);
  assert.equal(Object.isFrozen(input), false);
});

test('Date mutation cannot mutate validated root/timeline/hotel values', () => {
  const result = valid(f.full()); const saved = serialize(result);
  result.createdAt.setTime(0); result.updatedAt.setUTCFullYear(2000);
  result.days[0].date.setUTCDate(1);
  result.days[0].services[0].hotelDetails.checkInDate.setTime(0);
  assert.equal(serialize(result), saved);
});

test('exact count boundary includes accommodation envelopes and options', () => {
  assert.equal(maxItineraryPackageRecords, 256);
  const data = f.minimal();
  data.packageContent.accommodations = Array.from({length: 128}, (_, i) => f.accommodation(`stay-${i}`, i + 1));
  assert.equal(valid(data).packageContent.accommodations.length, 128);
  data.packageContent.conditions.push(f.condition()); invalid(data, /capacity/);
  const statements = f.minimal();
  statements.packageContent.inclusions = Array.from({length: 256}, (_, i) => f.statement(`fact-${i}`, i + 1));
  valid(statements); statements.packageContent.inclusions.push(f.statement('extra', 257)); invalid(statements, /capacity/);
});

test('domain count validation does not claim to enforce Firestore byte budgets', () => {
  const data = f.full(); statement(data).text = '界'.repeat(300000);
  const result = valid(data);
  assert.ok(Buffer.byteLength(serialize(result), 'utf8') > 768 * 1024);
  // This needs a future persistence-capacity rejection, not a fake JSON-size gate here.
  assert.equal(result.packageContent.inclusions[0].text, statement(data).text);
});

test('deterministic map/JSON round-trip preserves fields, nulls and ordering', () => {
  const data = f.full(); const result = valid(data);
  const map = toMap(result); const json = serialize(result);
  assert.deepEqual(map, data);
  assert.equal(serialize(fromMap('draft-1', JSON.parse(json))), json);
  const reordered = Object.fromEntries(Object.entries(data).reverse());
  reordered.packageContent = Object.fromEntries(Object.entries(data.packageContent).reverse());
  assert.equal(serialize(valid(reordered)), json);
  assert.ok(Object.isFrozen(map)); assert.ok(Object.isFrozen(map.packageContent));
  assert.equal(map.days[0].date, '2027-01-10');
});

test('malformed transport map and forged serialization fail closed', () => {
  const data = JSON.parse(serialize(valid(f.full()))); data.packageContent.unknown = [];
  invalid(data);
  assert.throws(() => toMap({...valid(), unknown: true}), ItineraryDraftV2Error);
  const result = valid(f.full());
  assert.throws(() => toMap({...result, createdAt: new Date('invalid')}), ItineraryDraftV2Error);
});

test('canonical runtime graph has no Firebase, provider, persistence or Resolution dependency', () => {
  const root = path.resolve(__dirname, '../lib/itineraryExtraction/itineraryDraftV2Validation.js');
  const script = `require(${JSON.stringify(root)}); const seen=new Set();
    function walk(m){if(seen.has(m.id))return;seen.add(m.id);m.children.forEach(walk);}
    walk(require.cache[${JSON.stringify(root)}]);console.log(JSON.stringify([...seen]));`;
  const graph = JSON.parse(execFileSync(process.execPath, ['-e', script], {encoding: 'utf8'}));
  assert.ok(graph.length > 1);
  assert.ok(graph.every((file) => !/firebase|google|gemini|vertex|supplierImport|Writer|Repository|sourceReader|Processor/i.test(file)));
  for (const name of ['itineraryDraftV2', 'itineraryDraftPackageContent', 'itineraryDraftV2Validation',
    'itineraryDraftPackageContentValidation', 'itineraryDraftTimelineValidation', 'itineraryDraftValidationPrimitives']) {
    const source = fs.readFileSync(path.join(__dirname, `../src/itineraryExtraction/${name}.ts`), 'utf8');
    assert.doesNotMatch(source, /from ["'](?:firebase|@google|.*supplierImport|.*FinalizationAssessment|.*Repository|.*Writer)/);
  }
});
