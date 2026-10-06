part of 'itinerary_draft_v2.dart';

enum ItineraryDraftV2Field {
  hotelName,
  city,
  orSimilar,
  checkInDate,
  checkOutDate,
  nightCount,
  roomType,
  mealPlan,
  numberOfRooms,
  supplierStarRating,
  category,
  text,
  quantity,
  frequency,
  appliesTo,
  kind,
  value,
}

enum ItineraryDraftV2FieldOperation { set, clear }

final class ItineraryDraftV2FieldChange {
  const ItineraryDraftV2FieldChange._(this.field, this.operation);
  final ItineraryDraftV2Field field;
  final ItineraryDraftV2FieldOperation operation;
}

final class ItineraryDraftV2SourceLocator {
  const ItineraryDraftV2SourceLocator._(
    this.supplierSourceFileId,
    this.sourceLabel,
  );
  final String? supplierSourceFileId, sourceLabel;
}

final class ItineraryDraftV2Contributor {
  const ItineraryDraftV2Contributor._(this.stagedFactId, this.sources);
  final String stagedFactId;
  final List<ItineraryDraftV2SourceLocator> sources;
}

final class ItineraryDraftV2Provenance {
  const ItineraryDraftV2Provenance._(
    this.extractionId,
    this.sourcePackageId,
    this.resolutionId,
    this.evaluatedRevision,
    this.contributors,
    this.decisionIds,
    this.fieldChanges,
  );
  factory ItineraryDraftV2Provenance._parse(
    Object? input,
    ItineraryDraftV2ImportResult imported,
    Set<ItineraryDraftV2Field> fields,
    Set<ItineraryDraftV2Field> clearable,
  ) {
    final m = _V2.record(input, {
      'origin',
      'extractionId',
      'sourcePackageId',
      'contributors',
      'resolutionId',
      'evaluatedRevision',
      'decisionIds',
      'fieldChanges',
    });
    final extraction = _V2.id(m['extractionId']),
        package = _V2.id(m['sourcePackageId']),
        resolution = _V2.id(m['resolutionId']);
    final revision = _V2.positive(m['evaluatedRevision']);
    if (m['origin'] != 'supplier' ||
        extraction != imported.extractionId ||
        package != imported.sourcePackageId ||
        resolution != imported.resolutionId ||
        revision != imported.evaluatedRevision) {
      _V2.invalid();
    }
    final contributors = _V2.list(m['contributors'], (value) {
      final c = _V2.record(value, {'stagedFactId', 'sources'});
      final sources = _V2.list(c['sources'], (value) {
        final s = _V2.record(value, {'supplierSourceFileId', 'sourceLabel'});
        return ItineraryDraftV2SourceLocator._(
          s['supplierSourceFileId'] == null
              ? null
              : _V2.id(s['supplierSourceFileId']),
          _V2.label(s['sourceLabel']),
        );
      });
      if (sources.isEmpty) _V2.invalid();
      _V2.unique(sources.map((s) => (s.supplierSourceFileId, s.sourceLabel)));
      return ItineraryDraftV2Contributor._(_V2.id(c['stagedFactId']), sources);
    });
    if (contributors.isEmpty) _V2.invalid();
    _V2.unique(contributors.map((c) => c.stagedFactId));
    final decisions = _V2.list(m['decisionIds'], _V2.id);
    _V2.unique(decisions);
    final changes = _V2.list(m['fieldChanges'], (value) {
      final c = _V2.record(value, {'field', 'operation'});
      final field = _V2.enumeration(c['field'], fields, (v) => v.name);
      final operation = _V2.enumeration(
        c['operation'],
        ItineraryDraftV2FieldOperation.values,
        (v) => v.name,
      );
      if (operation == ItineraryDraftV2FieldOperation.clear &&
          !clearable.contains(field)) {
        _V2.invalid();
      }
      return ItineraryDraftV2FieldChange._(field, operation);
    });
    _V2.unique(changes.map((c) => c.field));
    if (changes.isNotEmpty && decisions.isEmpty) _V2.invalid();
    return ItineraryDraftV2Provenance._(
      extraction,
      package,
      resolution,
      revision,
      contributors,
      decisions,
      changes,
    );
  }
  String get origin => 'supplier';
  final String extractionId, sourcePackageId, resolutionId;
  final int evaluatedRevision;
  final List<ItineraryDraftV2Contributor> contributors;
  final List<String> decisionIds;
  final List<ItineraryDraftV2FieldChange> fieldChanges;
}
