import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/data/supplier_import_resolution_repository.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_decision.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_event.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_manual_item.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_import_resolution_overrides.dart';

import 'support/supplier_import_resolution_fixture.dart';

void main() {
  late _Store store;
  late FirestoreSupplierImportResolutionRepository repository;

  setUp(() {
    store = _Store();
    repository = FirestoreSupplierImportResolutionRepository(store: store);
  });

  test('A missing root returns explicit not-started state', () async {
    expect(
      await repository.getResolution(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      ),
      isA<SupplierImportResolutionNotStarted>(),
    );
    expect(store.reads, ['root']);
  });

  test('B active root reconstructs from the deterministic hierarchy', () async {
    _storeValid(store);
    final result =
        await repository.getResolution(
              tripId: 'trip-1',
              extractionId: 'extraction-1',
            )
            as SupplierImportResolutionLoaded;
    expect(
      result.resolution.root.status,
      SupplierImportResolutionStatus.active,
    );
    expect(result.resolution.root.revision, 1);
    expect(store.reads, ['root', 'decisions', 'manual_items', 'events']);
  });

  test('C valid finalized root and complete audit history parse', () async {
    store.root = (
      documentId: 'extraction-1',
      data: supplierImportResolutionRoot(status: 'finalized', revision: 2),
    );
    store.events = [
      _document(
        'command-2',
        supplierImportAuditEvent(
          previousRevision: 1,
          eventId: 'command-2',
          action: 'finalize',
          status: 'finalized',
        ),
      ),
      _document('command-1', supplierImportAuditEvent()),
    ];
    final result =
        await repository.getResolution(
              tripId: 'trip-1',
              extractionId: 'extraction-1',
            )
            as SupplierImportResolutionLoaded;
    expect(
      result.resolution.root.status,
      SupplierImportResolutionStatus.finalized,
    );
    expect(
      result.resolution.auditEvents.map((event) => event.resultingRevision),
      [1, 2],
    );
  });

  test('D-I root path, linkage, schema, status, and revision reject', () async {
    final cases = <SupplierImportResolutionStoredDocument>[
      (documentId: 'other', data: supplierImportResolutionRoot()),
      (
        documentId: 'extraction-1',
        data: supplierImportResolutionRoot(resolutionId: 'other'),
      ),
      (
        documentId: 'extraction-1',
        data: supplierImportResolutionRoot(tripId: 'other'),
      ),
      (
        documentId: 'extraction-1',
        data: supplierImportResolutionRoot(extractionId: 'other'),
      ),
      (
        documentId: 'extraction-1',
        data: supplierImportResolutionRoot(schemaVersion: 'future'),
      ),
      (
        documentId: 'extraction-1',
        data: supplierImportResolutionRoot(status: 'unknown'),
      ),
      (
        documentId: 'extraction-1',
        data: supplierImportResolutionRoot(revision: 0),
      ),
    ];
    for (final root in cases) {
      store
        ..root = root
        ..events = [_document('command-1', supplierImportAuditEvent())];
      await expectLater(
        repository.getResolution(
          tripId: 'trip-1',
          extractionId: 'extraction-1',
        ),
        _throwsKind(SupplierImportResolutionRepositoryFailureKind.malformed),
      );
    }
  });

  test('J-N day/service decisions preserve set, clear, and untouched', () {
    final day =
        SupplierImportStoredDecision.fromMap(
              supplierImportDayDecision(),
            ).payload
            as SupplierImportDayDecision;
    expect(day.overrides.date, isA<SupplierImportSetOverride<String>>());
    expect(day.overrides.summary, isA<SupplierImportClearOverride<String>>());
    expect(day.overrides.notes, isNull);

    final service =
        SupplierImportStoredDecision.fromMap(
              supplierImportServiceDecision(),
            ).payload
            as SupplierImportServiceDecision;
    expect(service.day, isA<SupplierImportStagedDayReference>());
    expect(service.overrides.serviceType, isA<SupplierImportSetOverride>());
    expect(
      service.overrides.hotel?.roomType,
      isA<SupplierImportClearOverride<String>>(),
    );
  });

  test(
    'O-T every package, ancillary, and review decision parses distinctly',
    () {
      final values =
          [
                supplierImportAccommodationDecision(),
                supplierImportStatementDecision(),
                supplierImportConditionDecision(),
                supplierImportFlightDecision(),
                supplierImportVisaDecision(),
                supplierImportReviewDecision(),
              ]
              .map(
                (value) => SupplierImportStoredDecision.fromMap(value).payload,
              )
              .toList();
      expect(values[0], isA<SupplierImportPackageAccommodationDecision>());
      expect(values[1], isA<SupplierImportPackageStatementDecision>());
      expect(values[2], isA<SupplierImportPackageConditionDecision>());
      expect(values[3], isA<SupplierImportFlightDecision>());
      expect(values[4], isA<SupplierImportVisaDecision>());
      expect(values[5], isA<SupplierImportReviewIssueDecision>());
    },
  );

  test('title decision remains a dedicated strict variant', () {
    final value = SupplierImportStoredDecision.fromMap(
      supplierImportTitleDecision(),
    );
    expect(value.payload, isA<SupplierImportTitleDecision>());
    expect(value.metadata.decisionId, 'title');
  });

  test('U/V manual day and typed manual service parse', () {
    final day = SupplierImportStoredManualItem.fromMap(
      supplierImportManualDay(),
    );
    final service = SupplierImportStoredManualItem.fromMap(
      supplierImportManualService(),
    );
    expect(day.payload, isA<SupplierImportManualDay>());
    expect(service.payload, isA<SupplierImportManualService>());
    expect(
      (service.payload as SupplierImportManualService).hotelDetails,
      isNotNull,
    );
  });

  test('W manual Supplier provenance and commercial fields reject', () {
    for (final field in ['sources', 'supplierSourcePackageId', 'amount']) {
      expect(
        () => SupplierImportStoredManualItem.fromMap({
          ...supplierImportManualDay(),
          field: field == 'sources' ? <Object?>[] : 'forbidden',
        }),
        throwsFormatException,
      );
    }
  });

  test('X/Y audit event parses and requires one revision increment', () {
    final event = SupplierImportAuditEvent.fromMap(supplierImportAuditEvent());
    expect(event.action, SupplierImportAuditAction.openReview);
    expect(event.previousRevision, 0);
    expect(event.resultingRevision, 1);
    expect(
      () => SupplierImportAuditEvent.fromMap({
        ...supplierImportAuditEvent(),
        'resultingRevision': 2,
      }),
      throwsFormatException,
    );
  });

  test('Z-AB decisions, manual items, and events sort deterministically', () {
    final aggregate = SupplierImportResolutionAggregate.fromStoredDocuments(
      expectedTripId: 'trip-1',
      expectedExtractionId: 'extraction-1',
      rootDocumentId: 'extraction-1',
      rootData: supplierImportResolutionRoot(revision: 2),
      decisionDocuments: [
        _document(
          'staged-service-2',
          supplierImportServiceDecision(target: 'staged-service-2'),
        ),
        _document('staged-day-1', supplierImportDayDecision()),
      ],
      manualItemDocuments: [
        _document('consultant-service-1', supplierImportManualService()),
        _document('consultant-day-1', supplierImportManualDay()),
      ],
      eventDocuments: [
        _document(
          'command-2',
          supplierImportAuditEvent(previousRevision: 1, eventId: 'command-2'),
        ),
        _document('command-1', supplierImportAuditEvent()),
      ],
    );
    expect(aggregate.decisions.map((item) => item.metadata.decisionId), [
      'staged-day-1',
      'staged-service-2',
    ]);
    expect(aggregate.manualItems.map((item) => item.itemId), [
      'consultant-day-1',
      'consultant-service-1',
    ]);
    expect(aggregate.auditEvents.map((item) => item.eventId), [
      'command-1',
      'command-2',
    ]);
  });

  test('AC one malformed child fails the complete repository read', () async {
    _storeValid(store);
    store.decisions = [
      _document('staged-day-1', {
        ...supplierImportDayDecision(),
        'unexpected': true,
      }),
    ];
    await expectLater(
      repository.getResolution(tripId: 'trip-1', extractionId: 'extraction-1'),
      _throwsKind(SupplierImportResolutionRepositoryFailureKind.malformed),
    );
  });

  test('AD permission-denied maps to a sanitized typed read error', () async {
    store.error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'PRIVATE BACKEND DETAIL',
    );
    try {
      await repository.getResolution(
        tripId: 'trip-1',
        extractionId: 'extraction-1',
      );
      fail('Expected permission failure.');
    } on SupplierImportResolutionRepositoryFailure catch (error) {
      expect(
        error.kind,
        SupplierImportResolutionRepositoryFailureKind.permissionDenied,
      );
      expect(error.userMessage, isNot(contains('PRIVATE')));
    }
  });

  test('AE/BF repository contract performs reads only', () {
    expect(store, isA<SupplierImportResolutionReadStore>());
    final dynamic readOnly = repository;
    expect(() => readOnly.create(), throwsNoSuchMethodError);
    expect(() => readOnly.update(), throwsNoSuchMethodError);
    expect(() => readOnly.delete(), throwsNoSuchMethodError);
    final source = File(
      'lib/features/itineraries/data/'
      'supplier_import_resolution_repository.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('.set(')));
    expect(source, isNot(contains('.update(')));
    expect(source, isNot(contains('.delete(')));
  });
}

void _storeValid(_Store store) {
  store
    ..root = (documentId: 'extraction-1', data: supplierImportResolutionRoot())
    ..events = [_document('command-1', supplierImportAuditEvent())];
}

SupplierImportResolutionStoredDocument _document(
  String id,
  Map<String, Object?> data,
) => (documentId: id, data: data);

Matcher _throwsKind(SupplierImportResolutionRepositoryFailureKind kind) =>
    throwsA(
      isA<SupplierImportResolutionRepositoryFailure>().having(
        (error) => error.kind,
        'kind',
        kind,
      ),
    );

final class _Store implements SupplierImportResolutionReadStore {
  SupplierImportResolutionStoredDocument? root;
  List<SupplierImportResolutionStoredDocument> decisions = [];
  List<SupplierImportResolutionStoredDocument> manualItems = [];
  List<SupplierImportResolutionStoredDocument> events = [];
  Object? error;
  final List<String> reads = [];

  @override
  Future<SupplierImportResolutionStoredDocument?> readRoot(
    String tripId,
    String extractionId,
  ) async {
    reads.add('root');
    if (error != null) throw error!;
    return root;
  }

  @override
  Future<List<SupplierImportResolutionStoredDocument>> readChildren(
    String tripId,
    String extractionId,
    String collection,
  ) async {
    reads.add(collection);
    return switch (collection) {
      'decisions' => decisions,
      'manual_items' => manualItems,
      'events' => events,
      _ => throw StateError('Unexpected collection'),
    };
  }
}
