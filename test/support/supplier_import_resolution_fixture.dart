final supplierImportResolutionTime = DateTime.utc(2026, 10, 1, 8);

Map<String, Object?> supplierImportResolutionRoot({
  String resolutionId = 'extraction-1',
  String tripId = 'trip-1',
  String extractionId = 'extraction-1',
  String schemaVersion = 'supplier_import_resolution_v1',
  String status = 'active',
  int revision = 1,
}) => {
  'schemaVersion': schemaVersion,
  'resolutionId': resolutionId,
  'tripId': tripId,
  'extractionId': extractionId,
  'sourcePackageId': 'package-1',
  'snapshotSchemaVersion': 'supplier_extraction_snapshot_v1',
  'status': status,
  'revision': revision,
  'createdByUid': 'agent-1',
  'createdAt': supplierImportResolutionTime,
  'updatedByUid': 'agent-1',
  'updatedAt': supplierImportResolutionTime,
  'finalizedByUid': status == 'finalized' ? 'agent-1' : null,
  'finalizedAt': status == 'finalized' ? supplierImportResolutionTime : null,
  'resultingDraftId': status == 'finalized' ? 'draft-1' : null,
};

Map<String, Object?> supplierImportDecisionMetadata({
  required String decisionId,
  required String decisionKind,
  required String targetEntityId,
}) => {
  'decisionId': decisionId,
  'decisionKind': decisionKind,
  'targetEntityId': targetEntityId,
  'lastRevision': 1,
  'updatedByUid': 'agent-1',
  'updatedAt': supplierImportResolutionTime,
};

Map<String, Object?> supplierImportTitleDecision() => {
  ...supplierImportDecisionMetadata(
    decisionId: 'title',
    decisionKind: 'title',
    targetEntityId: 'title',
  ),
  'disposition': 'accept',
  'overrides': <String, Object?>{},
};

Map<String, Object?> supplierImportDayDecision({
  String target = 'staged-day-1',
}) => {
  ...supplierImportDecisionMetadata(
    decisionId: target,
    decisionKind: 'day',
    targetEntityId: target,
  ),
  'disposition': 'retain',
  'canonicalOrder': 1,
  'overrides': {
    'date': {'operation': 'set', 'value': '2026-12-01'},
    'summary': {'operation': 'clear'},
  },
  'exclusionReason': null,
  'exclusionNote': null,
};

Map<String, Object?> supplierImportServiceDecision({
  String target = 'staged-service-1',
}) => {
  ...supplierImportDecisionMetadata(
    decisionId: target,
    decisionKind: 'service',
    targetEntityId: target,
  ),
  'disposition': 'retain',
  'day': {'kind': 'staged_day', 'dayId': 'staged-day-1'},
  'canonicalOrder': 1,
  'overrides': {
    'serviceType': {'operation': 'set', 'value': 'hotel'},
    'hotel': {
      'hotelName': {'operation': 'set', 'value': 'Kayra Hotel'},
      'roomType': {'operation': 'clear'},
    },
  },
  'exclusionReason': null,
  'exclusionNote': null,
};

Map<String, Object?> supplierImportAccommodationDecision() => {
  ...supplierImportDecisionMetadata(
    decisionId: 'package-fact-1',
    decisionKind: 'package_accommodation',
    targetEntityId: 'package-fact-1',
  ),
  'disposition': 'retain_package_level',
  'day': null,
  'canonicalOrder': null,
  'overrides': <String, Object?>{},
  'exclusionReason': null,
  'exclusionNote': null,
};

Map<String, Object?> supplierImportStatementDecision() => {
  ...supplierImportDecisionMetadata(
    decisionId: 'package-fact-2',
    decisionKind: 'package_statement',
    targetEntityId: 'package-fact-2',
  ),
  'disposition': 'map_to_service',
  'service': {'kind': 'staged_service', 'serviceId': 'staged-service-1'},
  'destination': 'service_inclusion',
  'overrides': {
    'category': {'operation': 'set', 'value': 'meal'},
  },
  'exclusionReason': null,
  'exclusionNote': null,
};

Map<String, Object?> supplierImportConditionDecision() => {
  ...supplierImportDecisionMetadata(
    decisionId: 'package-fact-3',
    decisionKind: 'package_condition',
    targetEntityId: 'package-fact-3',
  ),
  'disposition': 'retain_package_level',
  'service': null,
  'destination': null,
  'overrides': {
    'kind': {'operation': 'set', 'value': 'guide'},
  },
  'exclusionReason': null,
  'exclusionNote': null,
};

Map<String, Object?> supplierImportFlightDecision() => {
  ...supplierImportDecisionMetadata(
    decisionId: 'ancillary-flight-1',
    decisionKind: 'flight',
    targetEntityId: 'ancillary-flight-1',
  ),
  'disposition': 'handled_separately',
  'destinationId': null,
  'overrides': {
    'airline': {'operation': 'set', 'value': 'Example Air'},
  },
  'exclusionReason': null,
  'exclusionNote': null,
};

Map<String, Object?> supplierImportVisaDecision() => {
  ...supplierImportDecisionMetadata(
    decisionId: 'ancillary-visa-1',
    decisionKind: 'visa',
    targetEntityId: 'ancillary-visa-1',
  ),
  'disposition': 'handled_separately',
  'destinationId': null,
  'overrides': {
    'disposition': {'operation': 'set', 'value': 'requirement'},
    'text': {'operation': 'clear'},
  },
  'exclusionReason': null,
  'exclusionNote': null,
};

Map<String, Object?> supplierImportReviewDecision() => {
  ...supplierImportDecisionMetadata(
    decisionId: 'review-1',
    decisionKind: 'review_issue',
    targetEntityId: 'review-1',
  ),
  'outcome': 'acknowledged',
  'resolutionReferences': <Object?>[],
  'overrideReason': null,
  'overrideNote': null,
};

Map<String, Object?> supplierImportManualDay() => {
  'itemKind': 'consultant_day',
  'manualDayId': 'consultant-day-1',
  'canonicalOrder': 2,
  'date': null,
  'title': 'Consultant day',
  'summary': null,
  'notes': null,
  ...supplierImportManualMetadata(),
};

Map<String, Object?> supplierImportManualService() => {
  'itemKind': 'consultant_service',
  'manualServiceId': 'consultant-service-1',
  'day': {'kind': 'consultant_day', 'manualDayId': 'consultant-day-1'},
  'canonicalOrder': 1,
  'serviceType': 'hotel',
  'title': 'Manual hotel',
  'description': null,
  'startTime': null,
  'endTime': null,
  'location': null,
  'city': null,
  'inclusions': <Object?>[],
  'exclusions': <Object?>[],
  'notes': null,
  'hotelDetails': {
    'hotelName': 'Manual Hotel',
    'checkInDate': null,
    'checkOutDate': null,
    'roomType': null,
    'mealPlan': null,
    'numberOfRooms': null,
    'supplierStarRating': null,
  },
  'transferDetails': null,
  'activityDetails': null,
  ...supplierImportManualMetadata(),
};

Map<String, Object?> supplierImportManualMetadata() => {
  'origin': 'consultant',
  'createdByUid': 'agent-1',
  'createdAt': supplierImportResolutionTime,
  'updatedByUid': 'agent-1',
  'updatedAt': supplierImportResolutionTime,
  'lastRevision': 1,
};

Map<String, Object?> supplierImportAuditEvent({
  int previousRevision = 0,
  String? eventId,
  String action = 'open_review',
  String status = 'active',
}) {
  final id = eventId ?? 'command-${previousRevision + 1}';
  return {
    'eventId': id,
    'resolutionId': 'extraction-1',
    'extractionId': 'extraction-1',
    'previousRevision': previousRevision,
    'resultingRevision': previousRevision + 1,
    'actorUid': 'agent-1',
    'occurredAt': supplierImportResolutionTime,
    'action': action,
    'targetKind': previousRevision == 0 ? 'resolution' : 'finalization',
    'targetId': 'extraction-1',
    'commandId': id,
    'metadata': {'kind': 'lifecycle', 'status': status},
  };
}
