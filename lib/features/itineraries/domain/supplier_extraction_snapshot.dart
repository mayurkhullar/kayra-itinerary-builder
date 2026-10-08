import 'supplier_extraction_fact.dart';
import 'supplier_extraction_parsing.dart';
import 'supplier_extraction_values.dart';

const supplierExtractionSnapshotSchemaVersion =
    'supplier_extraction_snapshot_v1';

typedef SupplierExtractionStoredDocument = ({
  String documentId,
  Map<String, Object?> data,
});

enum SupplierExtractionReviewSeverity {
  warning('warning'),
  blocker('blocker');

  const SupplierExtractionReviewSeverity(this.value);
  final String value;
}

enum SupplierExtractionReviewCode {
  chronologyUnknown('chronology_unknown'),
  accommodationSpanUnknown('accommodation_span_unknown'),
  classificationAmbiguous('classification_ambiguous'),
  conflictingDates('conflicting_dates'),
  globalMappingRequired('global_mapping_required'),
  sourceConflict('source_conflict'),
  other('other');

  const SupplierExtractionReviewCode(this.value);
  final String value;
}

enum SupplierExtractionReviewTargetKind {
  snapshot('snapshot'),
  day('day'),
  service('service'),
  packageFact('package_fact'),
  ancillaryFact('ancillary_fact');

  const SupplierExtractionReviewTargetKind(this.value);
  final String value;
}

final class SupplierExtractionReviewTarget {
  SupplierExtractionReviewTarget._({
    required this.kind,
    required this.entityId,
  });

  factory SupplierExtractionReviewTarget.fromMap(Map<String, Object?> data) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'kind',
      'entityId',
    }, 'Stored review target');
    final kind = SupplierExtractionParsing.enumValue(
      value['kind'],
      SupplierExtractionReviewTargetKind.values,
      (item) => item.value,
      'review target kind',
    );
    if (kind == SupplierExtractionReviewTargetKind.snapshot) {
      if (value['entityId'] != null) {
        throw const FormatException('Snapshot review target is invalid.');
      }
      return SupplierExtractionReviewTarget._(kind: kind, entityId: null);
    }
    return SupplierExtractionReviewTarget._(
      kind: kind,
      entityId: SupplierExtractionParsing.id(
        value['entityId'],
        'Review target entity',
      ),
    );
  }

  final SupplierExtractionReviewTargetKind kind;
  final String? entityId;
}

final class SupplierExtractionReviewIssue {
  SupplierExtractionReviewIssue._({
    required this.id,
    required this.structureBasis,
    required this.snapshotOrder,
    required this.code,
    required this.severity,
    required this.message,
    required this.target,
    required this.resolutionRequired,
    required List<SupplierExtractionSourceReference> sources,
  }) : sources = SupplierExtractionParsing.immutableList(sources);

  factory SupplierExtractionReviewIssue.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
  }) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'code',
      'severity',
      'message',
      'target',
      'resolutionRequired',
      'sources',
      if (data.containsKey('structureBasis')) 'structureBasis',
    }, 'Stored review issue');
    final basis = value['structureBasis'];
    if (value.containsKey('structureBasis') &&
        (!{'absence_only', 'explicit_relationship'}.contains(basis) ||
            !{
              'chronology_unknown',
              'global_mapping_required',
              'accommodation_span_unknown',
            }.contains(value['code']))) {
      throw const FormatException('Invalid review structure evidence.');
    }
    return SupplierExtractionReviewIssue._(
      structureBasis: basis as String?,
      id: SupplierExtractionParsing.id(value['id'], 'Review issue'),
      snapshotOrder: snapshotOrder,
      code: SupplierExtractionParsing.enumValue(
        value['code'],
        SupplierExtractionReviewCode.values,
        (code) => code.value,
        'review code',
      ),
      severity: SupplierExtractionParsing.enumValue(
        value['severity'],
        SupplierExtractionReviewSeverity.values,
        (severity) => severity.value,
        'review severity',
      ),
      message: SupplierExtractionParsing.semanticText(
        value['message'],
        'Review message',
      ),
      target: SupplierExtractionReviewTarget.fromMap(
        SupplierExtractionParsing.record(
          value['target'],
          'Stored review target',
        ),
      ),
      resolutionRequired: SupplierExtractionParsing.boolean(
        value['resolutionRequired'],
        'Review resolution requirement',
      ),
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final String id;
  final String? structureBasis;
  final int snapshotOrder;
  final SupplierExtractionReviewCode code;
  final SupplierExtractionReviewSeverity severity;
  final String message;
  final SupplierExtractionReviewTarget target;
  final bool resolutionRequired;
  final List<SupplierExtractionSourceReference> sources;
}

final class SupplierExtractionStagedDay {
  SupplierExtractionStagedDay._({
    required this.id,
    required this.snapshotOrder,
    required this.order,
    required this.sourceDayNumber,
    required this.date,
    required this.title,
    required this.summary,
    required this.notes,
    required List<String> assignedServiceIds,
    required List<SupplierExtractionSourceReference> sources,
  }) : assignedServiceIds = SupplierExtractionParsing.immutableList(
         assignedServiceIds,
       ),
       sources = SupplierExtractionParsing.immutableList(sources);

  factory SupplierExtractionStagedDay.fromMap(
    Map<String, Object?> data, {
    required int snapshotOrder,
  }) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'id',
      'order',
      'sourceDayNumber',
      'date',
      'title',
      'summary',
      'notes',
      'assignedServiceIds',
      'sources',
    }, 'Stored staged day');
    final order = SupplierExtractionParsing.positiveInteger(
      value['order'],
      'Staged day order',
    );
    if (order != snapshotOrder) {
      throw const FormatException('Staged day order is not deterministic.');
    }
    final sourceDayNumber = SupplierExtractionParsing.nullablePositiveInteger(
      value['sourceDayNumber'],
      'Source day number',
    );
    final date = SupplierExtractionParsing.nullableDate(
      value['date'],
      'Staged day date',
    );
    final title = SupplierExtractionParsing.nullableSemanticText(
      value['title'],
      'Staged day title',
    );
    if (sourceDayNumber == null && date == null && title == null) {
      throw const FormatException(
        'Stored staged day requires identifying chronology or a title.',
      );
    }
    final assignedServiceIds =
        SupplierExtractionParsing.list(
              value['assignedServiceIds'],
              'Assigned service identities',
            )
            .map(
              (item) => SupplierExtractionParsing.id(item, 'Assigned service'),
            )
            .toList();
    SupplierExtractionParsing.unique(
      assignedServiceIds,
      'assigned service references',
    );
    return SupplierExtractionStagedDay._(
      id: SupplierExtractionParsing.id(value['id'], 'Staged day'),
      snapshotOrder: snapshotOrder,
      order: order,
      sourceDayNumber: sourceDayNumber,
      date: date,
      title: title,
      summary: SupplierExtractionParsing.nullableSemanticText(
        value['summary'],
        'Staged day summary',
      ),
      notes: SupplierExtractionParsing.nullableSemanticText(
        value['notes'],
        'Staged day notes',
      ),
      assignedServiceIds: assignedServiceIds,
      sources: parseSupplierExtractionSources(value['sources']),
    );
  }

  final String id;
  final int snapshotOrder;
  final int order;
  final int? sourceDayNumber;
  final DateTime? date;
  final String? title;
  final String? summary;
  final String? notes;
  final List<String> assignedServiceIds;
  final List<SupplierExtractionSourceReference> sources;
}

final class SupplierExtractionSnapshotCounts {
  SupplierExtractionSnapshotCounts._({
    required this.days,
    required this.assignedServices,
    required this.unassignedServices,
    required this.packageFacts,
    required this.ancillaryFlights,
    required this.ancillaryVisas,
    required this.commercialIndicators,
    required this.reviewIssues,
  });

  factory SupplierExtractionSnapshotCounts.fromMap(Map<String, Object?> data) {
    final value = SupplierExtractionParsing.exactRecord(data, {
      'days',
      'assignedServices',
      'unassignedServices',
      'packageFacts',
      'ancillaryFlights',
      'ancillaryVisas',
      'commercialIndicators',
      'reviewIssues',
    }, 'Stored snapshot counts');
    return SupplierExtractionSnapshotCounts._(
      days: SupplierExtractionParsing.nonNegativeInteger(
        value['days'],
        'Snapshot days count',
      ),
      assignedServices: SupplierExtractionParsing.nonNegativeInteger(
        value['assignedServices'],
        'Snapshot assignedServices count',
      ),
      unassignedServices: SupplierExtractionParsing.nonNegativeInteger(
        value['unassignedServices'],
        'Snapshot unassignedServices count',
      ),
      packageFacts: SupplierExtractionParsing.nonNegativeInteger(
        value['packageFacts'],
        'Snapshot packageFacts count',
      ),
      ancillaryFlights: SupplierExtractionParsing.nonNegativeInteger(
        value['ancillaryFlights'],
        'Snapshot ancillaryFlights count',
      ),
      ancillaryVisas: SupplierExtractionParsing.nonNegativeInteger(
        value['ancillaryVisas'],
        'Snapshot ancillaryVisas count',
      ),
      commercialIndicators: SupplierExtractionParsing.nonNegativeInteger(
        value['commercialIndicators'],
        'Snapshot commercialIndicators count',
      ),
      reviewIssues: SupplierExtractionParsing.nonNegativeInteger(
        value['reviewIssues'],
        'Snapshot reviewIssues count',
      ),
    );
  }

  final int days;
  final int assignedServices;
  final int unassignedServices;
  final int packageFacts;
  final int ancillaryFlights;
  final int ancillaryVisas;
  final int commercialIndicators;
  final int reviewIssues;
}

final class SupplierExtractionSnapshot {
  SupplierExtractionSnapshot._({
    required this.extractionId,
    required this.tripId,
    required this.sourcePackageId,
    required this.jobId,
    required this.requestedByUid,
    required this.createdAt,
    required this.providerVersion,
    required this.title,
    required List<SupplierExtractionStagedDay> days,
    required List<SupplierExtractionFact> facts,
    required List<SupplierExtractionReviewIssue> reviewIssues,
    required this.counts,
  }) : days = SupplierExtractionParsing.immutableList(days),
       facts = SupplierExtractionParsing.immutableList(facts),
       reviewIssues = SupplierExtractionParsing.immutableList(reviewIssues);

  factory SupplierExtractionSnapshot.fromStoredDocuments({
    required String expectedTripId,
    required String expectedExtractionId,
    required Map<String, Object?> root,
    required Iterable<SupplierExtractionStoredDocument> dayDocuments,
    required Iterable<SupplierExtractionStoredDocument> factDocuments,
    required Iterable<SupplierExtractionStoredDocument> reviewIssueDocuments,
    required Iterable<String> trustedSourceFileIds,
  }) {
    SupplierExtractionParsing.id(expectedTripId, 'Trip');
    SupplierExtractionParsing.id(expectedExtractionId, 'Supplier extraction');
    final data = SupplierExtractionParsing.exactRecord(root, {
      'persistenceState',
      'schemaVersion',
      'extractionId',
      'tripId',
      'sourcePackageId',
      'jobId',
      'requestedByUid',
      'createdAt',
      'providerVersion',
      'title',
      'counts',
    }, 'Stored extraction root');
    if (data['persistenceState'] != 'complete') {
      throw const SupplierExtractionIncompleteException();
    }
    if (data['schemaVersion'] != supplierExtractionSnapshotSchemaVersion) {
      throw const FormatException(
        'Stored Supplier Extraction schema version is invalid.',
      );
    }
    final extractionId = SupplierExtractionParsing.id(
      data['extractionId'],
      'Supplier extraction',
    );
    final tripId = SupplierExtractionParsing.id(data['tripId'], 'Trip');
    if (tripId != expectedTripId || extractionId != expectedExtractionId) {
      throw const FormatException(
        'Stored Supplier Extraction path identity is inconsistent.',
      );
    }

    final days = _orderedChildren(dayDocuments, 'staged days')
        .map(
          (child) => SupplierExtractionStagedDay.fromMap(
            child.value,
            snapshotOrder: child.snapshotOrder,
          ),
        )
        .toList();
    final facts = _orderedChildren(factDocuments, 'staged facts')
        .map(
          (child) => parseSupplierExtractionFact(
            child.value,
            snapshotOrder: child.snapshotOrder,
          ),
        )
        .toList();
    final reviewIssues = _orderedChildren(reviewIssueDocuments, 'review issues')
        .map(
          (child) => SupplierExtractionReviewIssue.fromMap(
            child.value,
            snapshotOrder: child.snapshotOrder,
          ),
        )
        .toList();
    final sourcePackageId = SupplierExtractionParsing.id(
      data['sourcePackageId'],
      'Supplier Source package',
    );
    final trustedFiles = trustedSourceFileIds
        .map((id) => SupplierExtractionParsing.id(id, 'Supplier Source file'))
        .toSet();
    if (trustedFiles.length != trustedSourceFileIds.length) {
      throw const FormatException(
        'Duplicate trusted Supplier Source file identities.',
      );
    }
    final snapshot = SupplierExtractionSnapshot._(
      extractionId: extractionId,
      tripId: tripId,
      sourcePackageId: sourcePackageId,
      jobId: SupplierExtractionParsing.id(data['jobId'], 'Extraction job'),
      requestedByUid: SupplierExtractionParsing.id(
        data['requestedByUid'],
        'Requesting user',
      ),
      createdAt: SupplierExtractionParsing.timestamp(
        data['createdAt'],
        'Snapshot creation time',
      ),
      providerVersion: SupplierExtractionParsing.nullableText(
        data['providerVersion'],
        'Provider version',
      ),
      title: SupplierExtractionTitle.fromMap(
        SupplierExtractionParsing.record(data['title'], 'Stored title'),
      ),
      days: days,
      facts: facts,
      reviewIssues: reviewIssues,
      counts: SupplierExtractionSnapshotCounts.fromMap(
        SupplierExtractionParsing.record(
          data['counts'],
          'Stored snapshot counts',
        ),
      ),
    );
    _validateSnapshot(snapshot, trustedFiles);
    return snapshot;
  }

  final String extractionId;
  String get persistenceState => 'complete';
  String get schemaVersion => supplierExtractionSnapshotSchemaVersion;
  final String tripId;
  final String sourcePackageId;
  final String jobId;
  final String requestedByUid;
  final DateTime createdAt;
  final String? providerVersion;
  final SupplierExtractionTitle title;
  final List<SupplierExtractionStagedDay> days;
  final List<SupplierExtractionFact> facts;
  final List<SupplierExtractionReviewIssue> reviewIssues;
  final SupplierExtractionSnapshotCounts counts;
}

final class SupplierExtractionIncompleteException implements Exception {
  const SupplierExtractionIncompleteException();
}

typedef _OrderedChild = ({int snapshotOrder, Map<String, Object?> value});

List<_OrderedChild> _orderedChildren(
  Iterable<SupplierExtractionStoredDocument> documents,
  String label,
) {
  final children =
      documents.map((document) {
        final envelope = SupplierExtractionParsing.exactRecord(document.data, {
          'snapshotOrder',
          'value',
        }, 'Stored $label envelope');
        final value = SupplierExtractionParsing.record(
          envelope['value'],
          'Stored $label value',
        );
        if (value['id'] != document.documentId) {
          throw FormatException('Stored $label document identity is invalid.');
        }
        return (
          snapshotOrder: SupplierExtractionParsing.positiveInteger(
            envelope['snapshotOrder'],
            'Stored $label snapshot order',
          ),
          value: value,
        );
      }).toList()..sort(
        (left, right) => left.snapshotOrder.compareTo(right.snapshotOrder),
      );
  for (var index = 0; index < children.length; index++) {
    if (children[index].snapshotOrder != index + 1) {
      throw FormatException('Stored $label snapshot order is invalid.');
    }
  }
  return children;
}

void _validateSnapshot(
  SupplierExtractionSnapshot snapshot,
  Set<String> trustedFileIds,
) {
  SupplierExtractionParsing.unique(
    snapshot.days.map((day) => day.id),
    'staged day identities',
  );
  SupplierExtractionParsing.unique(
    snapshot.facts.map((fact) => fact.id),
    'staged fact identities',
  );
  SupplierExtractionParsing.unique(
    snapshot.reviewIssues.map((issue) => issue.id),
    'review issue identities',
  );
  _validateSources(
    snapshot.title.sources,
    snapshot.sourcePackageId,
    trustedFileIds,
  );
  final daysById = {for (final day in snapshot.days) day.id: day};
  final factsById = {for (final fact in snapshot.facts) fact.id: fact};

  for (var index = 0; index < snapshot.days.length; index++) {
    final day = snapshot.days[index];
    if (day.id != 'staged-day-${index + 1}') {
      throw const FormatException(
        'Stored staged day identity is not deterministic.',
      );
    }
    _validateSources(day.sources, snapshot.sourcePackageId, trustedFileIds);
    for (final serviceId in day.assignedServiceIds) {
      final fact = factsById[serviceId];
      if (fact is! SupplierExtractionServiceFact ||
          fact.scope is! SupplierExtractionDayScope ||
          (fact.scope as SupplierExtractionDayScope).dayId != day.id) {
        throw const FormatException(
          'Staged day points to an incompatible or missing service.',
        );
      }
    }
  }

  var serviceIndex = 0;
  var packageIndex = 0;
  var flightIndex = 0;
  var visaIndex = 0;
  for (final fact in snapshot.facts) {
    _validateSources(fact.sources, snapshot.sourcePackageId, trustedFileIds);
    switch (fact) {
      case SupplierExtractionServiceFact service:
        serviceIndex++;
        if (service.id != 'staged-service-$serviceIndex') {
          throw const FormatException(
            'Stored service identity is not deterministic.',
          );
        }
        switch (service.scope) {
          case SupplierExtractionDayScope scope:
            final day = daysById[scope.dayId];
            if (day == null || !day.assignedServiceIds.contains(service.id)) {
              throw const FormatException(
                'Assigned service points to a missing staged day.',
              );
            }
          case SupplierExtractionUnassignedScope():
            break;
        }
        for (final statement in [
          ...service.inclusions,
          ...service.exclusions,
        ]) {
          _validateSources(
            statement.sources,
            snapshot.sourcePackageId,
            trustedFileIds,
          );
        }
        for (final condition in service.conditions) {
          _validateSources(
            condition.sources,
            snapshot.sourcePackageId,
            trustedFileIds,
          );
        }
      case SupplierExtractionPackageAccommodationFact() ||
          SupplierExtractionPackageStatementFact() ||
          SupplierExtractionPackageConditionFact():
        packageIndex++;
        if (fact.id != 'package-fact-$packageIndex' ||
            fact.order != packageIndex) {
          throw const FormatException(
            'Stored package fact identity or order is not deterministic.',
          );
        }
      case SupplierExtractionFlightFact flight:
        flightIndex++;
        if (flight.id != 'ancillary-flight-$flightIndex' ||
            flight.order != flightIndex) {
          throw const FormatException(
            'Stored flight identity or order is not deterministic.',
          );
        }
        for (final condition in flight.conditions) {
          _validateSources(
            condition.sources,
            snapshot.sourcePackageId,
            trustedFileIds,
          );
        }
      case SupplierExtractionVisaFact():
        visaIndex++;
        if (fact.id != 'ancillary-visa-$visaIndex' || fact.order != visaIndex) {
          throw const FormatException(
            'Stored visa identity or order is not deterministic.',
          );
        }
      case SupplierExtractionCommercialPresenceFact():
        if (fact.id != 'commercial-presence-1' || fact.order != 1) {
          throw const FormatException(
            'Stored commercial indicator identity is not deterministic.',
          );
        }
    }
  }

  for (var index = 0; index < snapshot.reviewIssues.length; index++) {
    final issue = snapshot.reviewIssues[index];
    if (issue.id != 'review-${index + 1}') {
      throw const FormatException(
        'Stored review issue identity is not deterministic.',
      );
    }
    _validateSources(issue.sources, snapshot.sourcePackageId, trustedFileIds);
    final entityId = issue.target.entityId;
    switch (issue.target.kind) {
      case SupplierExtractionReviewTargetKind.snapshot:
        if (entityId != null) {
          throw const FormatException('Snapshot review target is invalid.');
        }
      case SupplierExtractionReviewTargetKind.day:
        if (!daysById.containsKey(entityId)) {
          throw const FormatException('Review issue targets a missing day.');
        }
      case SupplierExtractionReviewTargetKind.service:
        if (factsById[entityId] is! SupplierExtractionServiceFact) {
          throw const FormatException(
            'Review issue targets a missing or incompatible entity.',
          );
        }
      case SupplierExtractionReviewTargetKind.packageFact:
        if (factsById[entityId] case final fact?
            when fact.factKind !=
                    SupplierExtractionFactKind.packageAccommodation &&
                fact.factKind != SupplierExtractionFactKind.packageInclusion &&
                fact.factKind != SupplierExtractionFactKind.packageExclusion &&
                fact.factKind != SupplierExtractionFactKind.packageCondition) {
          throw const FormatException(
            'Review issue targets a missing or incompatible entity.',
          );
        } else if (!factsById.containsKey(entityId)) {
          throw const FormatException(
            'Review issue targets a missing or incompatible entity.',
          );
        }
      case SupplierExtractionReviewTargetKind.ancillaryFact:
        final fact = factsById[entityId];
        if (fact is! SupplierExtractionFlightFact &&
            fact is! SupplierExtractionVisaFact) {
          throw const FormatException(
            'Review issue targets a missing or incompatible entity.',
          );
        }
    }
  }

  final expected = SupplierExtractionSnapshotCounts._(
    days: snapshot.days.length,
    assignedServices: snapshot.facts
        .whereType<SupplierExtractionServiceFact>()
        .where((fact) => fact.scope is SupplierExtractionDayScope)
        .length,
    unassignedServices: snapshot.facts
        .whereType<SupplierExtractionServiceFact>()
        .where((fact) => fact.scope is SupplierExtractionUnassignedScope)
        .length,
    packageFacts: snapshot.facts
        .where(
          (fact) =>
              fact.factKind ==
                  SupplierExtractionFactKind.packageAccommodation ||
              fact.factKind == SupplierExtractionFactKind.packageInclusion ||
              fact.factKind == SupplierExtractionFactKind.packageExclusion ||
              fact.factKind == SupplierExtractionFactKind.packageCondition,
        )
        .length,
    ancillaryFlights: snapshot.facts
        .whereType<SupplierExtractionFlightFact>()
        .length,
    ancillaryVisas: snapshot.facts
        .whereType<SupplierExtractionVisaFact>()
        .length,
    commercialIndicators: snapshot.facts
        .whereType<SupplierExtractionCommercialPresenceFact>()
        .length,
    reviewIssues: snapshot.reviewIssues.length,
  );
  if (!_sameCounts(snapshot.counts, expected)) {
    throw const FormatException('Snapshot derived counts are inconsistent.');
  }
}

void _validateSources(
  Iterable<SupplierExtractionSourceReference> sources,
  String sourcePackageId,
  Set<String> trustedFileIds,
) {
  for (final source in sources) {
    if (source.supplierSourcePackageId != sourcePackageId ||
        (source.supplierSourceFileId != null &&
            !trustedFileIds.contains(source.supplierSourceFileId))) {
      throw const FormatException(
        'Trusted source reference is outside the snapshot package.',
      );
    }
  }
}

bool _sameCounts(
  SupplierExtractionSnapshotCounts left,
  SupplierExtractionSnapshotCounts right,
) =>
    left.days == right.days &&
    left.assignedServices == right.assignedServices &&
    left.unassignedServices == right.unassignedServices &&
    left.packageFacts == right.packageFacts &&
    left.ancillaryFlights == right.ancillaryFlights &&
    left.ancillaryVisas == right.ancillaryVisas &&
    left.commercialIndicators == right.commercialIndicators &&
    left.reviewIssues == right.reviewIssues;
