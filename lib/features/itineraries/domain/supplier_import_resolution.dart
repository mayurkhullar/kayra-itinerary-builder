import 'supplier_extraction_snapshot.dart';
import 'supplier_import_resolution_decision.dart';
import 'supplier_import_resolution_event.dart';
import 'supplier_import_resolution_manual_item.dart';
import 'supplier_import_resolution_parsing.dart';

const supplierImportResolutionSchemaVersion = 'supplier_import_resolution_v1';

enum SupplierImportResolutionStatus {
  active('active'),
  finalized('finalized');

  const SupplierImportResolutionStatus(this.value);
  final String value;
}

typedef SupplierImportResolutionStoredDocument = ({
  String documentId,
  Map<String, Object?> data,
});

final class SupplierImportResolutionRoot {
  const SupplierImportResolutionRoot._({
    required this.resolutionId,
    required this.tripId,
    required this.extractionId,
    required this.sourcePackageId,
    required this.status,
    required this.revision,
    required this.createdByUid,
    required this.createdAt,
    required this.updatedByUid,
    required this.updatedAt,
    required this.finalizedByUid,
    required this.finalizedAt,
    required this.resultingDraftId,
  });

  factory SupplierImportResolutionRoot.fromMap(
    Map<String, Object?> input, {
    required String expectedTripId,
    required String expectedExtractionId,
  }) {
    final data = SupplierImportResolutionParsing.exact(input, const {
      'schemaVersion',
      'resolutionId',
      'tripId',
      'extractionId',
      'sourcePackageId',
      'snapshotSchemaVersion',
      'status',
      'revision',
      'createdByUid',
      'createdAt',
      'updatedByUid',
      'updatedAt',
      'finalizedByUid',
      'finalizedAt',
      'resultingDraftId',
    }, 'Stored resolution root');
    if (data['schemaVersion'] != supplierImportResolutionSchemaVersion ||
        data['snapshotSchemaVersion'] !=
            supplierExtractionSnapshotSchemaVersion) {
      throw const FormatException('Stored resolution schema is unsupported.');
    }
    final resolutionId = SupplierImportResolutionParsing.id(
      data['resolutionId'],
      'Resolution',
    );
    final tripId = SupplierImportResolutionParsing.id(data['tripId'], 'Trip');
    final extractionId = SupplierImportResolutionParsing.id(
      data['extractionId'],
      'Extraction',
    );
    if (resolutionId != extractionId ||
        tripId != expectedTripId ||
        extractionId != expectedExtractionId) {
      throw const FormatException(
        'Stored resolution identity is inconsistent.',
      );
    }
    final status = SupplierImportResolutionParsing.enumValue(
      data['status'],
      SupplierImportResolutionStatus.values,
      (item) => item.value,
      'Resolution status',
    );
    final finalizedByUid = SupplierImportResolutionParsing.nullableId(
      data['finalizedByUid'],
      'Finalizing user',
    );
    final finalizedAt = SupplierImportResolutionParsing.nullableTimestamp(
      data['finalizedAt'],
      'Finalization time',
    );
    final resultingDraftId = SupplierImportResolutionParsing.nullableId(
      data['resultingDraftId'],
      'Resulting draft',
    );
    if (status == SupplierImportResolutionStatus.active &&
        (finalizedByUid != null ||
            finalizedAt != null ||
            resultingDraftId != null)) {
      throw const FormatException('Active resolution claims finalization.');
    }
    final revision = SupplierImportResolutionParsing.positiveInt(
      data['revision'],
      'Resolution revision',
    );
    if (status == SupplierImportResolutionStatus.finalized &&
        (revision < 2 ||
            finalizedByUid == null ||
            finalizedAt == null ||
            resultingDraftId == null)) {
      throw const FormatException('Finalized resolution metadata is invalid.');
    }
    return SupplierImportResolutionRoot._(
      resolutionId: resolutionId,
      tripId: tripId,
      extractionId: extractionId,
      sourcePackageId: SupplierImportResolutionParsing.id(
        data['sourcePackageId'],
        'Source package',
      ),
      status: status,
      revision: revision,
      createdByUid: SupplierImportResolutionParsing.id(
        data['createdByUid'],
        'Resolution creator',
      ),
      createdAt: SupplierImportResolutionParsing.timestamp(
        data['createdAt'],
        'Resolution creation time',
      ),
      updatedByUid: SupplierImportResolutionParsing.id(
        data['updatedByUid'],
        'Resolution updater',
      ),
      updatedAt: SupplierImportResolutionParsing.timestamp(
        data['updatedAt'],
        'Resolution update time',
      ),
      finalizedByUid: finalizedByUid,
      finalizedAt: finalizedAt,
      resultingDraftId: resultingDraftId,
    );
  }

  String get schemaVersion => supplierImportResolutionSchemaVersion;
  String get snapshotSchemaVersion => supplierExtractionSnapshotSchemaVersion;
  final String resolutionId;
  final String tripId;
  final String extractionId;
  final String sourcePackageId;
  final SupplierImportResolutionStatus status;
  final int revision;
  final String createdByUid;
  final DateTime createdAt;
  final String updatedByUid;
  final DateTime updatedAt;
  final String? finalizedByUid;
  final DateTime? finalizedAt;
  final String? resultingDraftId;
}

final class SupplierImportResolutionAggregate {
  SupplierImportResolutionAggregate._({
    required this.root,
    required List<SupplierImportStoredDecision> decisions,
    required List<SupplierImportStoredManualItem> manualItems,
    required List<SupplierImportAuditEvent> auditEvents,
  }) : decisions = List.unmodifiable(decisions),
       manualItems = List.unmodifiable(manualItems),
       auditEvents = List.unmodifiable(auditEvents);

  factory SupplierImportResolutionAggregate.fromStoredDocuments({
    required String expectedTripId,
    required String expectedExtractionId,
    required String rootDocumentId,
    required Map<String, Object?> rootData,
    required Iterable<SupplierImportResolutionStoredDocument> decisionDocuments,
    required Iterable<SupplierImportResolutionStoredDocument>
    manualItemDocuments,
    required Iterable<SupplierImportResolutionStoredDocument> eventDocuments,
  }) {
    if (rootDocumentId != expectedExtractionId) {
      throw const FormatException('Resolution root path is inconsistent.');
    }
    final root = SupplierImportResolutionRoot.fromMap(
      rootData,
      expectedTripId: expectedTripId,
      expectedExtractionId: expectedExtractionId,
    );
    if (root.resolutionId != rootDocumentId) {
      throw const FormatException('Resolution root identity is inconsistent.');
    }
    final decisions =
        decisionDocuments.map((document) {
          final value = SupplierImportStoredDecision.fromMap(document.data);
          if (value.metadata.decisionId != document.documentId) {
            throw const FormatException(
              'Decision document identity is invalid.',
            );
          }
          return value;
        }).toList()..sort(
          (left, right) =>
              left.metadata.decisionId.compareTo(right.metadata.decisionId),
        );
    final manualItems = manualItemDocuments.map((document) {
      final value = SupplierImportStoredManualItem.fromMap(document.data);
      if (value.itemId != document.documentId) {
        throw const FormatException(
          'Manual-item document identity is invalid.',
        );
      }
      return value;
    }).toList()..sort((left, right) => left.itemId.compareTo(right.itemId));
    final events =
        eventDocuments.map((document) {
          final value = SupplierImportAuditEvent.fromMap(document.data);
          if (value.eventId != document.documentId ||
              value.resolutionId != root.resolutionId ||
              value.extractionId != root.extractionId) {
            throw const FormatException('Audit event identity is invalid.');
          }
          return value;
        }).toList()..sort((left, right) {
          final byRevision = left.resultingRevision.compareTo(
            right.resultingRevision,
          );
          return byRevision != 0
              ? byRevision
              : left.eventId.compareTo(right.eventId);
        });
    SupplierImportResolutionParsing.unique(
      decisions.map((item) => item.metadata.decisionId),
      'decision identities',
    );
    SupplierImportResolutionParsing.unique(
      manualItems.map((item) => item.itemId),
      'manual item identities',
    );
    SupplierImportResolutionParsing.unique(
      events.map((item) => item.eventId),
      'audit event identities',
    );
    SupplierImportResolutionParsing.unique(
      events.map((item) => item.commandId),
      'audit command identities',
    );
    if (events.length != root.revision) {
      throw const FormatException('Audit history is incomplete.');
    }
    for (var index = 0; index < events.length; index++) {
      if (events[index].previousRevision != index ||
          events[index].resultingRevision != index + 1) {
        throw const FormatException('Audit history revisions are invalid.');
      }
    }
    if (decisions.any((item) => item.metadata.lastRevision > root.revision) ||
        manualItems.any((item) => item.metadata.lastRevision > root.revision)) {
      throw const FormatException('Stored child revision is invalid.');
    }
    return SupplierImportResolutionAggregate._(
      root: root,
      decisions: decisions,
      manualItems: manualItems,
      auditEvents: events,
    );
  }

  final SupplierImportResolutionRoot root;
  final List<SupplierImportStoredDecision> decisions;
  final List<SupplierImportStoredManualItem> manualItems;
  final List<SupplierImportAuditEvent> auditEvents;
}

sealed class SupplierImportResolutionReadResult {
  const SupplierImportResolutionReadResult();
}

final class SupplierImportResolutionNotStarted
    extends SupplierImportResolutionReadResult {
  const SupplierImportResolutionNotStarted();
}

final class SupplierImportResolutionLoaded
    extends SupplierImportResolutionReadResult {
  const SupplierImportResolutionLoaded(this.resolution);
  final SupplierImportResolutionAggregate resolution;
}
