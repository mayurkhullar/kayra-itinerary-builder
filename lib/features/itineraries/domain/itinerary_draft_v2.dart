import 'package:cloud_firestore/cloud_firestore.dart';

import 'kayra_itinerary_details.dart';
import 'kayra_itinerary_review_issue.dart';
import 'kayra_itinerary_service.dart';
import 'supplier_extraction_parsing.dart';
import 'supplier_extraction_values.dart';

part 'itinerary_draft_v2_parsing.dart';
part 'itinerary_draft_v2_timeline.dart';
part 'itinerary_draft_v2_service.dart';
part 'itinerary_draft_v2_import_result.dart';
part 'itinerary_draft_v2_package_content.dart';
part 'itinerary_draft_v2_provenance.dart';

const itineraryDraftV2SchemaVersion = 'itinerary_draft_v2';
const itineraryDraftV2ImportPolicy = 'supplier_import_exception_review_v1';
const optionalChronologyImportPolicy = 'supplier_import_optional_chronology_v2';

final class UnsupportedItineraryDraftV2Schema implements Exception {
  const UnsupportedItineraryDraftV2Schema();
}

/// Read-only canonical value. No V1 dispatch, write serializer or receipt data.
final class ItineraryDraftV2 {
  ItineraryDraftV2._({
    required this.id,
    required this.tripId,
    required this.title,
    required this.days,
    required this.unscheduledServices,
    required this.sourcePackageIds,
    required this.reviewIssues,
    required this.createdByUid,
    required this.createdAt,
    required this.updatedAt,
    required this.packageContent,
    required this.importResult,
  });

  factory ItineraryDraftV2.fromFirestore(
    Map<String, Object?> data, {
    required String documentId,
  }) {
    if (data['schemaVersion'] != itineraryDraftV2SchemaVersion) {
      throw const UnsupportedItineraryDraftV2Schema();
    }
    final m = _V2.optionalRecord(
      data,
      {
        'tripId',
        'schemaVersion',
        'title',
        'days',
        'sourcePackageIds',
        'reviewIssues',
        'createdByUid',
        'createdAt',
        'updatedAt',
        'packageContent',
        'importResult',
      },
      {'unscheduledServices'},
    );
    final id = _V2.id(documentId);
    final imported = ItineraryDraftV2ImportResult._parse(m['importResult']);
    final packages = _V2.list(m['sourcePackageIds'], _V2.id);
    _V2.unique(packages);
    if (!packages.contains(imported.sourcePackageId)) _V2.invalid();
    final days = _parseV2Timeline(m['days'], packages);
    final unscheduled = m.containsKey('unscheduledServices')
        ? _V2.list(
            m['unscheduledServices'],
            (v) => _parseV2Service(v, packages),
          )
        : null;
    final issues = _V2.list(m['reviewIssues'], (value) {
      final issue = _V2.record(value, {
        'id',
        'fieldPath',
        'message',
        'severity',
      });
      return KayraItineraryReviewIssue(
        id: _V2.id(issue['id']),
        fieldPath: _V2.text(issue['fieldPath']),
        message: _V2.text(issue['message']),
        severity: KayraItineraryReviewSeverity.parse(issue['severity']),
      );
    });
    final content = ItineraryDraftV2PackageContent._parse(
      m['packageContent'],
      imported,
    );
    _V2.unique([
      id,
      ...?unscheduled?.map((s) => s.id),
      ...issues.map((i) => i.id),
      for (final day in days) ...day.services.map((s) => s.id),
      for (final hotel in content.accommodations) ...[
        hotel.id,
        ...hotel.options.map((o) => o.id),
      ],
      ...content.inclusions.map((s) => s.id),
      ...content.exclusions.map((s) => s.id),
      ...content.conditions.map((s) => s.id),
    ]);
    final created = _V2.timestamp(m['createdAt']);
    final updated = _V2.timestamp(m['updatedAt']);
    if (updated.isBefore(created)) _V2.invalid();
    return ItineraryDraftV2._(
      id: id,
      tripId: _V2.id(m['tripId']),
      title: _V2.text(m['title']),
      days: days,
      unscheduledServices: unscheduled,
      sourcePackageIds: packages,
      reviewIssues: issues,
      createdByUid: _V2.id(m['createdByUid']),
      createdAt: created,
      updatedAt: updated,
      packageContent: content,
      importResult: imported,
    );
  }

  final String id, tripId, title, createdByUid;
  String get schemaVersion => itineraryDraftV2SchemaVersion;
  final List<ItineraryDraftV2Day> days;
  final List<ItineraryDraftV2Service>? unscheduledServices;
  final List<String> sourcePackageIds;
  final List<KayraItineraryReviewIssue> reviewIssues;
  final DateTime createdAt, updatedAt;
  final ItineraryDraftV2PackageContent packageContent;
  final ItineraryDraftV2ImportResult importResult;
}
