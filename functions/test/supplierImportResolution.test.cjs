const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  supplierImportResolutionSchemaVersion,
} = require('../lib/itineraryExtraction/supplierImportResolution');
const {
  SupplierImportResolutionError,
  validateSupplierImportResolution,
} = require('../lib/itineraryExtraction/supplierImportResolutionValidation');
const {
  assessSupplierImportFinalization,
} = require('../lib/itineraryExtraction/supplierImportFinalizationAssessment');
const {
  normalizeSupplierExtractionSnapshot,
} = require('../lib/itineraryExtraction/supplierExtractionValidation');

const at = '2026-09-30T06:00:00.000Z';
const invalidResolution = (error) =>
  error instanceof SupplierImportResolutionError &&
  error.code === 'INVALID_SUPPLIER_IMPORT_RESOLUTION';

function trustedPackage() {
  return {
    tripId: 'trip-1',
    packageId: 'package-1',
    supplierId: 'supplier-1',
    supplierNameSnapshot: 'Synthetic Supplier',
    files: [{
      sourceFileId: 'file-1',
      packageId: 'package-1',
      originalFileName: 'source.pdf',
      storagePath: 'trips/trip-1/supplier_sources/file-1/source.pdf',
      contentType: 'application/pdf',
      sizeBytes: 100,
      uploadedByUid: 'agent-1',
    }],
  };
}

function snapshot(payload = {}) {
  return normalizeSupplierExtractionSnapshot({
    title: {
      text: 'Synthetic itinerary',
      basis: 'neutral_supported',
      sources: [{fileIndex: 1, sourceLabel: 'Page 1'}],
    },
    ...payload,
  }, {
    extractionId: 'extraction-1',
    tripId: 'trip-1',
    sourcePackageId: 'package-1',
    jobId: 'job-1',
    requestedByUid: 'agent-1',
    createdAt: new Date(at),
    providerVersion: 'kayra_itinerary_extraction_v3_staging',
    trustedPackage: trustedPackage(),
  });
}

function root(source, overrides = {}) {
  return {
    schemaVersion: supplierImportResolutionSchemaVersion,
    resolutionId: source.extractionId,
    tripId: source.tripId,
    extractionId: source.extractionId,
    sourcePackageId: source.sourcePackageId,
    snapshotSchemaVersion: source.schemaVersion,
    status: 'active',
    revision: 1,
    createdByUid: 'agent-1',
    createdAt: at,
    updatedByUid: 'agent-1',
    updatedAt: at,
    finalizedByUid: null,
    finalizedAt: null,
    resultingDraftId: null,
    ...overrides,
  };
}

function aggregate(source, overrides = {}) {
  return {
    root: root(source),
    decisions: [],
    manualItems: [],
    auditEvents: [],
    ...overrides,
  };
}

function meta(id, kind, overrides = {}) {
  return {
    decisionId: id,
    decisionKind: kind,
    targetEntityId: id,
    lastRevision: 1,
    updatedByUid: 'agent-1',
    updatedAt: at,
    ...overrides,
  };
}

function dayDecision(id, overrides = {}) {
  return {
    ...meta(id, 'day'),
    disposition: 'retain',
    overrides: {},
    exclusionReason: null,
    exclusionNote: null,
    ...overrides,
  };
}

function serviceDecision(id, overrides = {}) {
  return {
    ...meta(id, 'service'),
    disposition: 'retain',
    overrides: {},
    exclusionReason: null,
    exclusionNote: null,
    ...overrides,
  };
}

function exclusion(overrides = {}) {
  return {
    disposition: 'exclude',
    exclusionReason: 'irrelevant_supplier_content',
    exclusionNote: null,
    ...overrides,
  };
}

function manualDay(id = 'consultant-day-1', overrides = {}) {
  return {
    itemKind: 'consultant_day',
    manualDayId: id,
    canonicalOrder: 2,
    date: null,
    title: 'Consultant day',
    summary: null,
    notes: null,
    origin: 'consultant',
    createdByUid: 'agent-1',
    createdAt: at,
    updatedByUid: 'agent-1',
    updatedAt: at,
    lastRevision: 1,
    ...overrides,
  };
}

function manualService(id = 'consultant-service-1', overrides = {}) {
  return {
    itemKind: 'consultant_service',
    manualServiceId: id,
    day: {kind: 'staged_day', dayId: 'staged-day-1'},
    canonicalOrder: 2,
    serviceType: 'other',
    title: 'Consultant service',
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
    origin: 'consultant',
    createdByUid: 'agent-1',
    createdAt: at,
    updatedByUid: 'agent-1',
    updatedAt: at,
    lastRevision: 1,
    ...overrides,
  };
}

function validate(source, value) {
  return validateSupplierImportResolution(source, value);
}

function codes(assessment, key = 'blockers') {
  return assessment[key].map((finding) => finding.code);
}

test('A/B valid near-empty resolution is immutable and identity equals extraction', () => {
  const source = snapshot();
  const value = validate(source, aggregate(source));
  assert.equal(value.root.resolutionId, source.extractionId);
  assert(Object.isFrozen(value));
  assert(Object.isFrozen(value.root));
  assert.equal(assessSupplierImportFinalization(source, value).canFinalize, true);
});

test('C/D/E resolution linkage mismatches are rejected', () => {
  const source = snapshot();
  for (const [field, value] of [
    ['tripId', 'trip-2'],
    ['extractionId', 'extraction-2'],
    ['sourcePackageId', 'package-2'],
  ]) {
    const input = aggregate(source);
    input.root = root(source, {[field]: value});
    if (field === 'extractionId') input.root.resolutionId = value;
    assert.throws(() => validate(source, input), invalidResolution);
  }
});

test('F/G/H staged-day retain, sparse correction, and exclusion are valid', () => {
  const source = snapshot({days: [{title: 'Day one'}]});
  validate(source, aggregate(source, {decisions: [dayDecision('staged-day-1')]}));
  const corrected = validate(source, aggregate(source, {decisions: [dayDecision(
    'staged-day-1', {
      canonicalOrder: 2,
      overrides: {
        date: {operation: 'set', value: '2027-01-02'},
        summary: {operation: 'clear'},
      },
    },
  )]}));
  assert.deepEqual(corrected.decisions[0].overrides.summary, {operation: 'clear'});
  validate(source, aggregate(source, {decisions: [dayDecision(
    'staged-day-1', exclusion(),
  )]}));
});

test('I/J assigned service retain and explicit move are valid', () => {
  const source = snapshot({days: [
    {title: 'Day one', services: [{type: 'other', title: 'Service'}]},
    {title: 'Day two'},
  ]});
  validate(source, aggregate(source, {decisions: [serviceDecision('staged-service-1')]}));
  const moved = validate(source, aggregate(source, {decisions: [serviceDecision(
    'staged-service-1', {
      day: {kind: 'staged_day', dayId: 'staged-day-2'},
      canonicalOrder: 1,
    },
  )]}));
  assert.equal(moved.decisions[0].day.dayId, 'staged-day-2');
});

test('K/L unassigned service blocks until assigned to a staged day', () => {
  const source = snapshot({
    days: [{title: 'Day one'}],
    unassignedServices: [{type: 'other', title: 'Unassigned'}],
  });
  const open = validate(source, aggregate(source));
  assert(codes(assessSupplierImportFinalization(source, open))
    .includes('unresolved_unassigned_service'));
  const assigned = validate(source, aggregate(source, {decisions: [serviceDecision(
    'staged-service-1', {
      day: {kind: 'staged_day', dayId: 'staged-day-1'},
      canonicalOrder: 1,
    },
  )]}));
  assert.equal(assessSupplierImportFinalization(source, assigned).canFinalize, true);
});

test('M unassigned service can target a valid consultant day', () => {
  const source = snapshot({unassignedServices: [{type: 'other', title: 'Service'}]});
  const value = validate(source, aggregate(source, {
    manualItems: [manualDay('consultant-day-1', {canonicalOrder: 1})],
    decisions: [serviceDecision('staged-service-1', {
      day: {kind: 'consultant_day', manualDayId: 'consultant-day-1'},
      canonicalOrder: 1,
    })],
  }));
  assert.equal(assessSupplierImportFinalization(source, value).canFinalize, true);
});

test('N/O service assignment to missing or excluded day is rejected', () => {
  const source = snapshot({days: [
    {title: 'Day one', services: [{type: 'other', title: 'Service'}]},
    {title: 'Day two'},
  ]});
  assert.throws(() => validate(source, aggregate(source, {decisions: [serviceDecision(
    'staged-service-1', {
      day: {kind: 'staged_day', dayId: 'staged-day-404'},
      canonicalOrder: 1,
    },
  )]})), invalidResolution);
  assert.throws(() => validate(source, aggregate(source, {decisions: [
    dayDecision('staged-day-2', exclusion()),
    serviceDecision('staged-service-1', {
      day: {kind: 'staged_day', dayId: 'staged-day-2'},
      canonicalOrder: 1,
    }),
  ]})), invalidResolution);
});

test('P excluding an unassigned service resolves its chronology blocker', () => {
  const source = snapshot({unassignedServices: [{type: 'other', title: 'Service'}]});
  const value = validate(source, aggregate(source, {decisions: [serviceDecision(
    'staged-service-1', exclusion(),
  )]}));
  assert.equal(assessSupplierImportFinalization(source, value).canFinalize, true);
});

test('Q/R/S set, clear, and untouched overrides remain distinct', () => {
  const source = snapshot({days: [{title: 'Day', services: [{
    type: 'other', title: 'Service', description: 'Supplier description',
  }]}]});
  const value = validate(source, aggregate(source, {decisions: [serviceDecision(
    'staged-service-1', {overrides: {
      title: {operation: 'set', value: 'Corrected title'},
      description: {operation: 'clear'},
    }},
  )]}));
  assert.deepEqual(value.decisions[0].overrides.title,
    {operation: 'set', value: 'Corrected title'});
  assert.deepEqual(value.decisions[0].overrides.description, {operation: 'clear'});
  assert.equal(Object.hasOwn(value.decisions[0].overrides, 'notes'), false);
});

test('T incompatible typed service override is rejected', () => {
  const source = snapshot({days: [{title: 'Day', services: [
    {type: 'other', title: 'Service'},
  ]}]});
  assert.throws(() => validate(source, aggregate(source, {decisions: [serviceDecision(
    'staged-service-1', {
      overrides: {hotel: {hotelName: {operation: 'set', value: 'Hotel'}}},
    },
  )]})), invalidResolution);
});

function accommodationSource() {
  return snapshot({
    days: [{title: 'Day one'}],
    packageFacts: {accommodations: [{hotelName: 'Example Hotel'}]},
  });
}

function accommodationDecision(overrides = {}) {
  return {
    ...meta('package-fact-1', 'package_accommodation'),
    disposition: 'map_to_day_service',
    day: {kind: 'staged_day', dayId: 'staged-day-1'},
    canonicalOrder: 1,
    overrides: {},
    exclusionReason: null,
    exclusionNote: null,
    ...overrides,
  };
}

test('U/V accommodation blocks unresolved and mapped accommodation resolves', () => {
  const source = accommodationSource();
  const open = validate(source, aggregate(source));
  assert(codes(assessSupplierImportFinalization(source, open))
    .includes('unresolved_package_accommodation'));
  const mapped = validate(source, aggregate(source, {
    decisions: [accommodationDecision()],
  }));
  assert.equal(assessSupplierImportFinalization(source, mapped).canFinalize, true);
});

test('W accommodation consultant dates remain explicit override operations', () => {
  const source = accommodationSource();
  const value = validate(source, aggregate(source, {decisions: [accommodationDecision({
    overrides: {
      checkInDate: {operation: 'set', value: '2027-04-01'},
      checkOutDate: {operation: 'set', value: '2027-04-03'},
    },
  })]}));
  assert.deepEqual(value.decisions[0].overrides.checkInDate,
    {operation: 'set', value: '2027-04-01'});
  assert.equal(source.facts[0].details.checkInDate, null);
});

test('X retained package accommodation remains canonically blocked', () => {
  const source = accommodationSource();
  const value = validate(source, aggregate(source, {decisions: [accommodationDecision({
    disposition: 'retain_package_level', day: null, canonicalOrder: null,
  })]}));
  assert(codes(assessSupplierImportFinalization(source, value))
    .includes('package_level_destination_unavailable'));
});

function packageStatementDecision(id, overrides = {}) {
  return {
    ...meta(id, 'package_statement'),
    disposition: 'retain_package_level',
    service: null,
    destination: null,
    overrides: {},
    exclusionReason: null,
    exclusionNote: null,
    ...overrides,
  };
}

test('Y retained package inclusion follows canonical destination gate', () => {
  const source = snapshot({packageFacts: {inclusions: [
    {category: 'meal', text: 'Breakfast included'},
  ]}});
  const value = validate(source, aggregate(source, {decisions: [
    packageStatementDecision('package-fact-1'),
  ]}));
  assert(codes(assessSupplierImportFinalization(source, value))
    .includes('package_level_destination_unavailable'));
});

test('Z/AA compatible package mapping is valid and incompatible mapping rejects', () => {
  const source = snapshot({
    days: [{title: 'Day', services: [{type: 'other', title: 'Service'}]}],
    packageFacts: {inclusions: [{category: 'meal', text: 'Breakfast included'}]},
  });
  const mapped = packageStatementDecision('package-fact-1', {
    disposition: 'map_to_service',
    service: {kind: 'staged_service', serviceId: 'staged-service-1'},
    destination: 'service_inclusion',
  });
  validate(source, aggregate(source, {decisions: [mapped]}));
  assert.throws(() => validate(source, aggregate(source, {decisions: [{
    ...mapped, destination: 'service_exclusion',
  }]})), invalidResolution);
});

test('package conditions require a compatible typed service destination', () => {
  const source = snapshot({
    days: [{title: 'Day', services: [{
      type: 'transfer', title: 'Transfer',
      transferDetails: {pickup: 'Airport', dropoff: 'Hotel'},
    }]}],
    packageFacts: {conditions: [{
      kind: 'operating_basis', value: 'Private basis', appliesTo: ['transfer'],
    }]},
  });
  const base = {
    ...meta('package-fact-1', 'package_condition'),
    disposition: 'map_to_service',
    service: {kind: 'staged_service', serviceId: 'staged-service-1'},
    destination: 'transfer_type',
    overrides: {},
    exclusionReason: null,
    exclusionNote: null,
  };
  assert.throws(() => validate(source, aggregate(source, {decisions: [base]})),
    invalidResolution);
  validate(source, aggregate(source, {decisions: [{
    ...base,
    overrides: {value: {operation: 'set', value: 'private'}},
  }]}));
});

test('AB/AC/AD flights stay ancillary and require explicit disposition', () => {
  const source = snapshot({ancillaryFacts: {flights: [{
    airline: 'Example Air', origin: 'DEL', destination: 'DXB',
  }]}});
  assert.equal(source.facts.some((fact) =>
    fact.factKind === 'service' && fact.serviceType === 'other'), false);
  const open = validate(source, aggregate(source));
  assert(codes(assessSupplierImportFinalization(source, open))
    .includes('unresolved_ancillary_fact'));
  const handled = validate(source, aggregate(source, {decisions: [{
    ...meta('ancillary-flight-1', 'flight'),
    disposition: 'handled_separately',
    destinationId: null,
    overrides: {},
    exclusionReason: null,
    exclusionNote: null,
  }]}));
  assert.equal(assessSupplierImportFinalization(source, handled).canFinalize, true);
});

test('AE visa semantic correction is accepted without commercial fields', () => {
  const source = snapshot({ancillaryFacts: {visas: [{
    disposition: 'mentioned', text: 'Visa required',
  }]}});
  const value = validate(source, aggregate(source, {decisions: [{
    ...meta('ancillary-visa-1', 'visa'),
    disposition: 'handled_separately',
    destinationId: null,
    overrides: {
      disposition: {operation: 'set', value: 'requirement'},
      text: {operation: 'set', value: 'Visa required before travel'},
    },
    exclusionReason: null,
    exclusionNote: null,
  }]}));
  assert.equal(value.decisions[0].overrides.disposition.value, 'requirement');
});

test('AF commercial fields cannot be represented in decisions', () => {
  const source = snapshot();
  assert.throws(() => validate(source, aggregate(source, {decisions: [{
    ...meta('title', 'title', {targetEntityId: 'title'}),
    disposition: 'accept',
    overrides: {},
    price: 370,
  }]})), invalidResolution);
});

test('AG commercial presence is informational and requires no decision', () => {
  const source = snapshot({commercialContent: {
    present: true,
    categories: ['package_price'],
    sources: [{fileIndex: 1, sourceLabel: 'Commercial section'}],
  }});
  const value = validate(source, aggregate(source));
  const assessment = assessSupplierImportFinalization(source, value);
  assert.equal(assessment.canFinalize, true);
  assert.deepEqual(codes(assessment, 'informational'), ['commercial_presence']);
});

test('AH acknowledgement is valid only for an optional warning', () => {
  const source = snapshot({reviewIssues: [{
    code: 'other', severity: 'warning', message: 'Optional uncertainty',
    target: {kind: 'snapshot'}, resolutionRequired: false,
  }]});
  const acknowledged = {
    ...meta('review-1', 'review_issue'),
    outcome: 'acknowledged',
    resolutionReferences: [],
    overrideReason: null,
    overrideNote: null,
  };
  const value = validate(source, aggregate(source, {decisions: [acknowledged]}));
  assert(codes(assessSupplierImportFinalization(source, value), 'warnings')
    .includes('snapshot_warning_acknowledged'));
  const required = snapshot({reviewIssues: [{
    code: 'other', severity: 'warning', message: 'Required uncertainty',
    target: {kind: 'snapshot'}, resolutionRequired: true,
  }]});
  assert.throws(() => validate(required, aggregate(required, {
    decisions: [acknowledged],
  })), invalidResolution);
});

test('AI/AJ structural and blocking issues cannot be cleared by acknowledgement', () => {
  const source = snapshot({reviewIssues: [{
    code: 'chronology_unknown', severity: 'blocker', message: 'Chronology unknown',
    target: {kind: 'snapshot'}, resolutionRequired: true,
  }]});
  const value = validate(source, aggregate(source));
  assert(codes(assessSupplierImportFinalization(source, value))
    .includes('structural_review_issue_unresolved'));
  assert.throws(() => validate(source, aggregate(source, {decisions: [{
    ...meta('review-1', 'review_issue'),
    outcome: 'acknowledged', resolutionReferences: [],
    overrideReason: null, overrideNote: null,
  }]})), invalidResolution);
});

test('structural resolved outcome requires a concrete typed correction', () => {
  const source = snapshot({
    days: [{title: 'Day one'}],
    unassignedServices: [{title: 'Unclassified'}],
    reviewIssues: [{
      code: 'classification_ambiguous', severity: 'blocker',
      message: 'Classify this service.',
      target: {kind: 'service', scope: 'unassigned', serviceIndex: 1},
      resolutionRequired: true,
    }],
  });
  const review = {
    ...meta('review-1', 'review_issue'),
    outcome: 'resolved',
    resolutionReferences: [{kind: 'decision', decisionId: 'staged-service-1'}],
    overrideReason: null,
    overrideNote: null,
  };
  assert.throws(() => validate(source, aggregate(source, {decisions: [
    serviceDecision('staged-service-1', {
      day: {kind: 'staged_day', dayId: 'staged-day-1'}, canonicalOrder: 1,
    }),
    review,
  ]})), invalidResolution);
  validate(source, aggregate(source, {decisions: [
    serviceDecision('staged-service-1', {
      day: {kind: 'staged_day', dayId: 'staged-day-1'}, canonicalOrder: 1,
      overrides: {serviceType: {operation: 'set', value: 'other'}},
    }),
    review,
  ]}));
});

test('AK/AL/AM valid manual day and service have consultant origin and no provenance', () => {
  const source = snapshot({days: [{title: 'Day one'}]});
  const value = validate(source, aggregate(source, {
    manualItems: [manualDay(), manualService()],
  }));
  assert.equal(value.manualItems[0].origin, 'consultant');
  assert.equal(Object.hasOwn(value.manualItems[1], 'sources'), false);
  assert.equal(Object.hasOwn(value.manualItems[1], 'sourceReference'), false);
});

test('AN malformed and duplicate manual IDs are rejected', () => {
  const source = snapshot({days: [{title: 'Day one'}]});
  assert.throws(() => validate(source, aggregate(source, {
    manualItems: [manualDay('bad-id')],
  })), invalidResolution);
  assert.throws(() => validate(source, aggregate(source, {
    manualItems: [manualDay(), manualDay()],
  })), invalidResolution);
});

test('AO duplicate current decisions are rejected', () => {
  const source = snapshot({days: [{title: 'Day one'}]});
  assert.throws(() => validate(source, aggregate(source, {
    decisions: [dayDecision('staged-day-1'), dayDecision('staged-day-1')],
  })), invalidResolution);
});

test('AP invalid root and child revisions are rejected', () => {
  const source = snapshot({days: [{title: 'Day one'}]});
  const invalidRoot = aggregate(source);
  invalidRoot.root = root(source, {revision: 1.5});
  assert.throws(() => validate(source, invalidRoot), invalidResolution);
  assert.throws(() => validate(source, aggregate(source, {
    decisions: [dayDecision('staged-day-1', {lastRevision: 2})],
  })), invalidResolution);
});

function audit(overrides = {}) {
  return {
    eventId: 'command-1',
    resolutionId: 'extraction-1',
    extractionId: 'extraction-1',
    previousRevision: 0,
    resultingRevision: 1,
    actorUid: 'agent-1',
    occurredAt: at,
    action: 'open_review',
    targetKind: 'resolution',
    targetId: 'extraction-1',
    commandId: 'command-1',
    metadata: {kind: 'lifecycle', status: 'active'},
    ...overrides,
  };
}

test('AQ audit revision increments exactly one', () => {
  const source = snapshot();
  assert.throws(() => validate(source, aggregate(source, {
    auditEvents: [audit({resultingRevision: 2})],
  })), invalidResolution);
  validate(source, aggregate(source, {auditEvents: [audit()]}));
});

test('AR duplicate audit and command IDs are rejected', () => {
  const source = snapshot();
  assert.throws(() => validate(source, aggregate(source, {
    auditEvents: [audit(), audit()],
  })), invalidResolution);
});

test('AS active resolution with resulting output is rejected', () => {
  const source = snapshot();
  const input = aggregate(source);
  input.root = root(source, {resultingDraftId: 'draft-1'});
  assert.throws(() => validate(source, input), invalidResolution);
});

test('AT/AU finalized resolution requires complete finalization and is terminal-valid', () => {
  const source = snapshot();
  const incomplete = aggregate(source);
  incomplete.root = root(source, {status: 'finalized'});
  assert.throws(() => validate(source, incomplete), invalidResolution);
  const complete = aggregate(source);
  complete.root = root(source, {
    status: 'finalized', revision: 2, finalizedByUid: 'agent-1', finalizedAt: at,
    resultingDraftId: 'draft-1',
  });
  const value = validate(source, complete);
  assert.equal(value.root.status, 'finalized');
  assert(codes(assessSupplierImportFinalization(source, value))
    .includes('resolution_already_finalized'));
});

test('AV finding order is deterministic across input ordering', () => {
  const source = snapshot({
    days: [{title: 'Day one'}],
    unassignedServices: [
      {type: 'other', title: 'B'},
      {type: 'other', title: 'A'},
    ],
    ancillaryFacts: {visas: [{disposition: 'mentioned', text: 'Visa required'}]},
  });
  const value = validate(source, aggregate(source));
  const first = JSON.stringify(assessSupplierImportFinalization(source, value));
  const second = JSON.stringify(assessSupplierImportFinalization(source, value));
  assert.equal(first, second);
  const assessment = JSON.parse(first);
  const sorted = [...assessment.blockers].sort((a, b) =>
    a.code.localeCompare(b.code) || a.targetKind.localeCompare(b.targetKind) ||
    (a.targetId || '').localeCompare(b.targetId || ''));
  assert.deepEqual(assessment.blockers, sorted);
});

test('AW canFinalize becomes true only after mandatory blockers clear', () => {
  const source = snapshot({
    days: [{title: 'Day one'}],
    unassignedServices: [{type: 'other', title: 'Service'}],
    ancillaryFacts: {visas: [{disposition: 'mentioned', text: 'Visa required'}]},
  });
  const open = validate(source, aggregate(source));
  assert.equal(assessSupplierImportFinalization(source, open).canFinalize, false);
  const resolved = validate(source, aggregate(source, {decisions: [
    serviceDecision('staged-service-1', {
      day: {kind: 'staged_day', dayId: 'staged-day-1'}, canonicalOrder: 1,
    }),
    {
      ...meta('ancillary-visa-1', 'visa'),
      disposition: 'handled_separately', destinationId: null, overrides: {},
      exclusionReason: null, exclusionNote: null,
    },
  ]}));
  assert.equal(assessSupplierImportFinalization(source, resolved).canFinalize, true);
});

test('AX warnings are separate from blockers', () => {
  const source = snapshot({reviewIssues: [{
    code: 'other', severity: 'warning', message: 'Optional uncertainty',
    target: {kind: 'snapshot'}, resolutionRequired: false,
  }]});
  const assessment = assessSupplierImportFinalization(
    source, validate(source, aggregate(source)),
  );
  assert.equal(assessment.blockers.length, 0);
  assert.equal(assessment.warnings.length, 1);
  assert.equal(assessment.canFinalize, true);
});

test('AY unknown schema and enum values are rejected', () => {
  const source = snapshot({days: [{title: 'Day one'}]});
  const schema = aggregate(source);
  schema.root = root(source, {schemaVersion: 'future_version'});
  assert.throws(() => validate(source, schema), invalidResolution);
  assert.throws(() => validate(source, aggregate(source, {decisions: [dayDecision(
    'staged-day-1', {disposition: 'maybe'},
  )]})), invalidResolution);
});

test('AZ pure resolution modules have no Firebase, Functions, or provider imports', () => {
  const sourceRoot = path.resolve(__dirname, '../src/itineraryExtraction');
  for (const file of [
    'supplierImportResolution.ts',
    'supplierImportResolutionValidation.ts',
    'supplierImportFinalizationAssessment.ts',
  ]) {
    const contents = fs.readFileSync(path.join(sourceRoot, file), 'utf8');
    assert.doesNotMatch(contents,
      /firebase-admin|firebase-functions|gemini|vertex|providerSupplier/iu);
  }
});

test('additional cross-reference and order conflicts remain strict blockers', () => {
  const source = snapshot({days: [
    {title: 'Day one', services: [{type: 'other', title: 'One'}]},
    {title: 'Day two', services: [{type: 'other', title: 'Two'}]},
  ]});
  const duplicateDay = validate(source, aggregate(source, {decisions: [
    dayDecision('staged-day-2', {canonicalOrder: 1}),
  ]}));
  assert(codes(assessSupplierImportFinalization(source, duplicateDay))
    .includes('duplicate_day_order'));
  const duplicateService = validate(source, aggregate(source, {decisions: [
    serviceDecision('staged-service-2', {
      day: {kind: 'staged_day', dayId: 'staged-day-1'}, canonicalOrder: 1,
    }),
  ]}));
  assert(codes(assessSupplierImportFinalization(source, duplicateService))
    .includes('duplicate_service_order'));
});
