import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';

import 'supplier_import_resolution_fixture.dart';

SupplierImportDayDecision dayReviewDecision({
  String id = 'staged-day-1',
  int? order,
  SupplierImportExclusionReason? exclude,
  String? note,
  SupplierImportDayOverrides overrides = const SupplierImportDayOverrides(),
}) => SupplierImportDayDecision(
  targetEntityId: id,
  disposition: exclude == null
      ? SupplierImportRetainDisposition.retain
      : SupplierImportRetainDisposition.exclude,
  canonicalOrder: order,
  overrides: overrides,
  exclusionReason: exclude,
  exclusionNote: note,
);

SupplierImportServiceDecision dayReviewService({
  String id = 'staged-service-1',
  String? day,
  bool exclude = false,
}) => SupplierImportServiceDecision(
  targetEntityId: id,
  disposition: exclude
      ? SupplierImportRetainDisposition.exclude
      : SupplierImportRetainDisposition.retain,
  day: day == null ? null : SupplierImportStagedDayReference(day),
  canonicalOrder: day == null ? null : 3,
  overrides: const SupplierImportServiceOverrides(),
  exclusionReason: exclude ? SupplierImportExclusionReason.duplicate : null,
  exclusionNote: null,
);

SupplierImportResolutionLoaded dayReviewResolution({
  List<SupplierImportDecisionPayload> decisions = const [],
  int revision = 1,
  List<Map<String, Object?>> manual = const [],
}) => SupplierImportResolutionLoaded(
  SupplierImportResolutionAggregate.fromStoredDocuments(
    expectedTripId: 'trip-1',
    expectedExtractionId: 'extraction-1',
    rootDocumentId: 'extraction-1',
    rootData: supplierImportResolutionRoot(revision: revision),
    decisionDocuments: [
      for (final decision in decisions)
        (
          documentId: decision.targetEntityId,
          data: {
            ...supplierImportDecisionMetadata(
              decisionId: decision.targetEntityId,
              decisionKind: decision.decisionKind,
              targetEntityId: decision.targetEntityId,
            ),
            ...decision.toMutationMap(),
          },
        ),
    ],
    manualItemDocuments: [
      for (final item in manual)
        (
          documentId:
              (item['manualDayId'] ?? item['manualServiceId'])! as String,
          data: item,
        ),
    ],
    eventDocuments: List.generate(
      revision,
      (index) => (
        documentId: 'command-${index + 1}',
        data: {
          ...supplierImportAuditEvent(previousRevision: index),
          if (index > 0) ...{
            'action': 'set_day_decision',
            'targetKind': 'day',
            'targetId': 'staged-day-1',
            'metadata': {
              'kind': 'decision',
              'disposition': 'retain',
              'changedFields': <String>[],
              'exclusionReason': null,
              'referencedIds': <String>[],
            },
          },
        },
      ),
    ),
  ),
);
