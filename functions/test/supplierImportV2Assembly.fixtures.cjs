const {normalizeSupplierExtractionSnapshot} = require('../lib/itineraryExtraction/supplierExtractionValidation');
const {validateSupplierImportResolution} = require('../lib/itineraryExtraction/supplierImportResolutionValidation');
const {supplierImportResolutionSchemaVersion} = require('../lib/itineraryExtraction/supplierImportResolution');
const at = '2026-09-30T06:00:00.000Z';

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


const context = () => ({draftId: 'draft-1', tripId: 'trip-1', actorUid: 'agent-1',
  finalizationId: 'finalization-1', createdAt: at, updatedAt: at,
  policyVersion: 'supplier_import_exception_review_v1'});
const set = (value) => ({operation: 'set', value});
const clear = {operation: 'clear'};
const service = (extra = {}) => ({type: 'other', title: 'Museum visit', ...extra});
const day = (extra = {}) => ({title: 'Arrival', services: [service()], ...extra});
function packageDecision(id, kind, extra = {}) {
  return {...meta(id, kind), disposition: 'retain_package_level', overrides: {},
    exclusionReason: null, exclusionNote: null,
    ...(kind === 'package_accommodation' ? {day: null, canonicalOrder: null} : {service: null, destination: null}), ...extra};
}
const issue = (extra = {}) => ({code: 'other', severity: 'warning',
  message: 'Check source detail', target: {kind: 'snapshot'}, resolutionRequired: false, ...extra});
const reviewDecision = (extra = {}) => ({...meta('review-1', 'review_issue'), outcome: 'resolved',
  resolutionReferences: [], overrideReason: null, overrideNote: null, ...extra});
module.exports = {at, snapshot, root, aggregate, meta, dayDecision, serviceDecision,
  exclusion, manualDay, manualService, validate, codes, context, set, clear, service, day,
  packageDecision, issue, reviewDecision};
