import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_fact.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_snapshot.dart';
import 'package:kayra_crm_v1/features/itineraries/domain/supplier_extraction_values.dart';

import 'support/supplier_extraction_fixture.dart';

SupplierExtractionSnapshot _parse({
  Map<String, Object?>? root,
  List<SupplierExtractionStoredDocument>? days,
  List<SupplierExtractionStoredDocument>? facts,
  List<SupplierExtractionStoredDocument>? issues,
  Iterable<String> sourceFileIds = const ['file-1'],
  String expectedTripId = 'trip-1',
  String expectedExtractionId = 'extraction-1',
}) => SupplierExtractionSnapshot.fromStoredDocuments(
  expectedTripId: expectedTripId,
  expectedExtractionId: expectedExtractionId,
  root: root ?? supplierExtractionRoot(),
  dayDocuments: days ?? supplierExtractionDayDocuments(),
  factDocuments: facts ?? supplierExtractionFactDocuments(),
  reviewIssueDocuments: issues ?? supplierExtractionReviewIssueDocuments(),
  trustedSourceFileIds: sourceFileIds,
);

void main() {
  test('complete chronological Snapshot retains ordered days and services', () {
    final snapshot = _parse();

    expect(snapshot.extractionId, 'extraction-1');
    expect(snapshot.persistenceState, 'complete');
    expect(snapshot.schemaVersion, supplierExtractionSnapshotSchemaVersion);
    expect(snapshot.tripId, 'trip-1');
    expect(snapshot.sourcePackageId, 'package-1');
    expect(snapshot.jobId, 'job-1');
    expect(snapshot.requestedByUid, 'agent-1');
    expect(snapshot.createdAt, supplierExtractionCreatedAt);
    expect(snapshot.title.text, 'Japan Discovery');
    expect(snapshot.days.map((day) => day.id), [
      'staged-day-1',
      'staged-day-2',
    ]);
    expect(snapshot.days.first.sourceDayNumber, 3);
    expect(snapshot.days.last.sourceDayNumber, 7);
    expect(snapshot.days.first.date, DateTime.utc(2027, 4, 10));
    expect(snapshot.days.first.assignedServiceIds, ['staged-service-1']);
    expect(snapshot.facts.map((fact) => fact.snapshotOrder), [
      for (var order = 1; order <= 10; order++) order,
    ]);
  });

  test('zero-day Snapshot preserves unassigned services without fake days', () {
    final service = supplierExtractionService(
      id: 'staged-service-1',
      order: 1,
      scope: {'kind': 'unassigned'},
      serviceType: 'activity',
      title: 'Tea ceremony',
      activityDetails: {
        'activityName': 'Tea ceremony',
        'duration': null,
        'activityType': null,
      },
    );
    final snapshot = _parse(
      root: supplierExtractionRoot(
        counts: supplierExtractionCounts(
          days: 0,
          assignedServices: 0,
          unassignedServices: 1,
          packageFacts: 0,
          ancillaryFlights: 0,
          ancillaryVisas: 0,
          commercialIndicators: 0,
          reviewIssues: 0,
        ),
      ),
      days: const [],
      facts: [supplierExtractionChild(service, 1)],
      issues: const [],
    );

    expect(snapshot.days, isEmpty);
    expect(snapshot.facts.single, isA<SupplierExtractionServiceFact>());
    expect(
      (snapshot.facts.single as SupplierExtractionServiceFact).scope,
      isA<SupplierExtractionUnassignedScope>(),
    );
  });

  test('mixed assigned and unassigned service scopes remain distinct', () {
    final services = _parse().facts.whereType<SupplierExtractionServiceFact>();
    expect(
      services.where((fact) => fact.scope is SupplierExtractionDayScope),
      hasLength(2),
    );
    expect(
      services.where((fact) => fact.scope is SupplierExtractionUnassignedScope),
      hasLength(1),
    );
  });

  test('package accommodation keeps unknown dates absent', () {
    final accommodation = _parse().facts
        .whereType<SupplierExtractionPackageAccommodationFact>()
        .single;
    expect(accommodation.details.hotelName, 'Example Tokyo Hotel');
    expect(accommodation.details.orSimilar, isTrue);
    expect(accommodation.details.nightCount, 2);
    expect(accommodation.details.checkInDate, isNull);
    expect(accommodation.details.checkOutDate, isNull);
  });

  test('package inclusions exclusions and conditions stay typed', () {
    final facts = _parse().facts;
    final inclusion = facts
        .whereType<SupplierExtractionPackageStatementFact>()
        .firstWhere(
          (fact) =>
              fact.factKind == SupplierExtractionFactKind.packageInclusion,
        );
    final exclusion = facts
        .whereType<SupplierExtractionPackageStatementFact>()
        .firstWhere(
          (fact) =>
              fact.factKind == SupplierExtractionFactKind.packageExclusion,
        );
    final condition = facts
        .whereType<SupplierExtractionPackageConditionFact>()
        .single;
    expect(inclusion.quantity, 3);
    expect(inclusion.frequency, 'per stay');
    expect(exclusion.text, 'Lunches not stated as included');
    expect(condition.kind, SupplierExtractionConditionKind.operatingBasis);
    expect(condition.appliesTo, [
      SupplierExtractionServiceType.transfer,
      SupplierExtractionServiceType.sightseeing,
    ]);
  });

  test('ancillary flight retains structured non-commercial fields', () {
    final flight = _parse().facts
        .whereType<SupplierExtractionFlightFact>()
        .single;
    expect(flight.airline, 'Example Air');
    expect(flight.flightNumber, 'EA 101');
    expect(flight.origin, 'DEL');
    expect(flight.destination, 'NRT');
    expect(flight.departureDate, DateTime.utc(2027, 4, 9));
    expect(flight.departureTime, '22:15');
    expect(flight.arrivalDate, DateTime.utc(2027, 4, 10));
    expect(flight.cabinClass, 'Economy');
    expect(
      flight.conditions.single.kind,
      SupplierExtractionConditionKind.travelClass,
    );
  });

  test('ancillary visa retains controlled disposition and text', () {
    final visa = _parse().facts.whereType<SupplierExtractionVisaFact>().single;
    expect(visa.disposition, SupplierExtractionVisaDisposition.requirement);
    expect(visa.text, 'Visa required before travel.');
  });

  test('commercial content is presence-only controlled categories', () {
    final commercial = _parse().facts
        .whereType<SupplierExtractionCommercialPresenceFact>()
        .single;
    expect(commercial.categories, [
      SupplierExtractionCommercialCategory.packagePrice,
      SupplierExtractionCommercialCategory.paymentTerms,
    ]);
    final dynamic dynamicCommercial = commercial;
    expect(() => dynamicCommercial.amount, throwsNoSuchMethodError);
    expect(() => dynamicCommercial.currency, throwsNoSuchMethodError);
  });

  test('every persisted review target kind resolves to its typed entity', () {
    final issues = _parse().reviewIssues;
    expect(issues.map((issue) => issue.snapshotOrder), [1, 2, 3, 4, 5, 6]);
    expect(issues.map((issue) => issue.target.kind), [
      SupplierExtractionReviewTargetKind.snapshot,
      SupplierExtractionReviewTargetKind.day,
      SupplierExtractionReviewTargetKind.service,
      SupplierExtractionReviewTargetKind.service,
      SupplierExtractionReviewTargetKind.packageFact,
      SupplierExtractionReviewTargetKind.ancillaryFact,
    ]);
    expect(issues[2].target.entityId, 'staged-service-1');
    expect(issues[3].target.entityId, 'staged-service-3');
  });

  test('writing root is rejected as incomplete', () {
    expect(
      () => _parse(root: supplierExtractionRoot(persistenceState: 'writing')),
      throwsA(isA<SupplierExtractionIncompleteException>()),
    );
  });

  test('unsupported schema and root path mismatches are rejected', () {
    expect(
      () =>
          _parse(root: supplierExtractionRoot(schemaVersion: 'future_version')),
      throwsFormatException,
    );
    expect(
      () => _parse(root: supplierExtractionRoot(tripId: 'trip-2')),
      throwsFormatException,
    );
    expect(
      () => _parse(root: supplierExtractionRoot(extractionId: 'extraction-2')),
      throwsFormatException,
    );
  });

  test('child document and entity identity mismatch is rejected', () {
    final days = _copyDocuments(supplierExtractionDayDocuments());
    days[0] = (documentId: 'wrong-day', data: days[0].data);
    expect(() => _parse(days: days), throwsFormatException);
  });

  test('duplicate gap and zero snapshot order are rejected', () {
    for (final orders in [
      [1, 1],
      [1, 3],
      [0, 2],
    ]) {
      final days = _copyDocuments(supplierExtractionDayDocuments());
      for (var index = 0; index < days.length; index++) {
        days[index].data['snapshotOrder'] = orders[index];
      }
      expect(() => _parse(days: days), throwsFormatException);
    }
  });

  test('derived root count mismatch is rejected', () {
    expect(
      () => _parse(
        root: supplierExtractionRoot(
          counts: supplierExtractionCounts(assignedServices: 99),
        ),
      ),
      throwsFormatException,
    );
  });

  test('assigned service referencing a missing day is rejected', () {
    final facts = _copyDocuments(supplierExtractionFactDocuments());
    final service = facts.first.data['value']! as Map<String, Object?>;
    service['scope'] = {'kind': 'day', 'dayId': 'staged-day-99'};
    expect(() => _parse(facts: facts), throwsFormatException);
  });

  test('day referencing a missing service is rejected', () {
    final days = _copyDocuments(supplierExtractionDayDocuments());
    final day = days.first.data['value']! as Map<String, Object?>;
    day['assignedServiceIds'] = ['staged-service-99'];
    expect(() => _parse(days: days), throwsFormatException);
  });

  test('incompatible service detail branch is rejected', () {
    final facts = _copyDocuments(supplierExtractionFactDocuments());
    final service = facts.first.data['value']! as Map<String, Object?>;
    service['serviceType'] = 'transfer';
    expect(() => _parse(facts: facts), throwsFormatException);
  });

  test('review target missing or wrong entity kind is rejected', () {
    for (final target in [
      {'kind': 'day', 'entityId': 'staged-day-99'},
      {'kind': 'package_fact', 'entityId': 'staged-service-1'},
      {'kind': 'ancillary_fact', 'entityId': 'package-fact-1'},
    ]) {
      final issues = _copyDocuments(supplierExtractionReviewIssueDocuments());
      final issue = issues.first.data['value']! as Map<String, Object?>;
      issue['target'] = target;
      expect(() => _parse(issues: issues), throwsFormatException);
    }
  });

  test('unknown fact kind is rejected', () {
    final facts = _copyDocuments(supplierExtractionFactDocuments());
    final fact = facts.first.data['value']! as Map<String, Object?>;
    fact['factKind'] = 'unknown';
    expect(() => _parse(facts: facts), throwsFormatException);
  });

  test('malformed package or file provenance is rejected', () {
    final wrongPackage = _copyDocuments(supplierExtractionFactDocuments());
    final packageFact =
        wrongPackage.first.data['value']! as Map<String, Object?>;
    packageFact['sources'] = [supplierExtractionSource(packageId: 'package-2')];
    expect(() => _parse(facts: wrongPackage), throwsFormatException);

    final wrongFile = _copyDocuments(supplierExtractionFactDocuments());
    final fileFact = wrongFile.first.data['value']! as Map<String, Object?>;
    fileFact['sources'] = [supplierExtractionSource(fileId: 'file-99')];
    expect(() => _parse(facts: wrongFile), throwsFormatException);
  });

  test('commercial value fields and semantic amount leakage are rejected', () {
    final leakedField = _copyDocuments(supplierExtractionFactDocuments());
    final commercial = leakedField.last.data['value']! as Map<String, Object?>;
    commercial['amount'] = 5000;
    expect(() => _parse(facts: leakedField), throwsFormatException);

    final leakedText = _copyDocuments(supplierExtractionFactDocuments());
    final statement = leakedText[4].data['value']! as Map<String, Object?>;
    statement['text'] = 'Dinner package costs INR 5000';
    expect(() => _parse(facts: leakedText), throwsFormatException);
  });

  test('returned ordering is deterministic and lists are immutable', () {
    final days = _copyDocuments(supplierExtractionDayDocuments()).reversed;
    final facts = _copyDocuments(supplierExtractionFactDocuments()).reversed;
    final issues = _copyDocuments(
      supplierExtractionReviewIssueDocuments(),
    ).reversed;
    final snapshot = _parse(
      days: days.toList(),
      facts: facts.toList(),
      issues: issues.toList(),
    );

    expect(snapshot.days.map((day) => day.snapshotOrder), [1, 2]);
    expect(snapshot.facts.first.id, 'staged-service-1');
    expect(snapshot.facts.last.id, 'commercial-presence-1');
    expect(snapshot.reviewIssues.first.id, 'review-1');
    expect(() => snapshot.days.clear(), throwsUnsupportedError);
    expect(() => snapshot.facts.clear(), throwsUnsupportedError);
    expect(() => snapshot.reviewIssues.clear(), throwsUnsupportedError);
    expect(
      () => snapshot.days.first.assignedServiceIds.clear(),
      throwsUnsupportedError,
    );
  });
}

List<SupplierExtractionStoredDocument> _copyDocuments(
  Iterable<SupplierExtractionStoredDocument> documents,
) => documents
    .map(
      (document) =>
          (documentId: document.documentId, data: _copyMap(document.data)),
    )
    .toList();

Map<String, Object?> _copyMap(Map<String, Object?> value) =>
    value.map((key, nested) => MapEntry(key, _copyValue(nested)));

Object? _copyValue(Object? value) => switch (value) {
  Map value => _copyMap(Map<String, Object?>.from(value)),
  List value => value.map(_copyValue).toList(),
  _ => value,
};
