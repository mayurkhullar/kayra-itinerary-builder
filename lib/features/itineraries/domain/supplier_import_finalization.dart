import 'itinerary_draft_v2.dart';
import 'supplier_import_resolution_parsing.dart';

/// Uses the existing canonical policy constant. Backend policy changes require
/// a coordinated Flutter update until capability discovery exists.
final class SupplierImportFinalizationRequest {
  SupplierImportFinalizationRequest({
    required String tripId,
    required String extractionId,
    required String commandId,
    required this.expectedRevision,
    this.policyVersion = itineraryDraftV2ImportPolicy,
  }) : tripId = _id(tripId, maximum: 256),
       extractionId = _id(extractionId, maximum: 256),
       commandId = _id(commandId, maximum: 128) {
    if (expectedRevision < 1 ||
        expectedRevision >= 9007199254740991 ||
        policyVersion != itineraryDraftV2ImportPolicy) {
      throw const FormatException("Invalid finalization request.");
    }
  }
  final String tripId, extractionId, commandId, policyVersion;
  final int expectedRevision;
  Map<String, Object?> toMap() => {
    "tripId": tripId,
    "extractionId": extractionId,
    "commandId": commandId,
    "expectedRevision": expectedRevision,
    "policyVersion": policyVersion,
  };
}

enum SupplierImportFinalizationBlockerCode {
  resolutionAlreadyFinalized('resolution_already_finalized'),
  missingDayTitle('missing_day_title'),
  duplicateDayOrder('duplicate_day_order'),
  unresolvedUnassignedService('unresolved_unassigned_service'),
  missingServiceDay('missing_service_day'),
  missingServiceOrder('missing_service_order'),
  missingServiceType('missing_service_type'),
  missingServiceTitle('missing_service_title'),
  missingRequiredServiceDetails('missing_required_service_details'),
  duplicateServiceOrder('duplicate_service_order'),
  unsupportedServiceContent('unsupported_service_content'),
  unresolvedPackageAccommodation('unresolved_package_accommodation'),
  incompletePackageAccommodation('incomplete_package_accommodation'),
  unsupportedPackageAccommodationContent(
    'unsupported_package_accommodation_content',
  ),
  packageLevelDestinationUnavailable('package_level_destination_unavailable'),
  unresolvedPackageFact('unresolved_package_fact'),
  unresolvedAncillaryFact('unresolved_ancillary_fact'),
  unresolvedReviewIssue('unresolved_review_issue'),
  structuralReviewIssueUnresolved('structural_review_issue_unresolved'),
  invalidSnapshot('invalid_snapshot'),
  invalidResolution('invalid_resolution'),
  invalidAssemblyContext('invalid_assembly_context'),
  unsupportedPackageMapping('unsupported_package_mapping'),
  packageRecordLimitExceeded('package_record_limit_exceeded'),
  canonicalValidationFailed('canonical_validation_failed');

  const SupplierImportFinalizationBlockerCode(this.value);
  final String value;
}

enum SupplierImportFinalizationWarningCode {
  reviewIssueOverrideAvailable('review_issue_override_available'),
  snapshotWarningOpen('snapshot_warning_open'),
  snapshotWarningAcknowledged('snapshot_warning_acknowledged'),
  reviewIssueOverridden('review_issue_overridden');

  const SupplierImportFinalizationWarningCode(this.value);
  final String value;
}

enum SupplierImportFinalizationTargetKind {
  resolution('resolution'),
  day('day'),
  service('service'),
  packageFact('package_fact'),
  ancillaryFact('ancillary_fact'),
  reviewIssue('review_issue'),
  commercialFact('commercial_fact');

  const SupplierImportFinalizationTargetKind(this.value);
  final String value;
}

enum SupplierImportFinalizationCapacityBoundary {
  canonical('canonical'),
  packageContent('package_content'),
  receipt('receipt'),
  resolution('resolution'),
  event('event'),
  commit('commit'),
  inputs('inputs'),
  nesting('nesting'),
  firestore('firestore');

  const SupplierImportFinalizationCapacityBoundary(this.value);
  final String value;
}

final class SupplierImportFinalizationFinding<T extends Enum> {
  const SupplierImportFinalizationFinding._(
    this.code,
    this.targetKind,
    this.targetId,
  );
  final T code;
  final SupplierImportFinalizationTargetKind targetKind;
  final String? targetId;
}

sealed class SupplierImportFinalizationOutcome {
  const SupplierImportFinalizationOutcome(this.resolutionId);
  final String resolutionId;
  factory SupplierImportFinalizationOutcome.fromMap(Object? input) {
    final m = SupplierImportResolutionParsing.record(
      input,
      'Finalization response',
    );
    final outcome = m['outcome'];
    if (outcome == 'not_ready') {
      _exact(m, {'outcome', 'assessment'});
      final a = _exact(m['assessment'], {
        'resolutionId',
        'evaluatedRevision',
        'canFinalize',
        'blockers',
        'warnings',
      });
      if (a['canFinalize'] != false) {
        throw const FormatException('Invalid readiness.');
      }
      final blockers = _findings(
        a['blockers'],
        SupplierImportFinalizationBlockerCode.values,
        (v) => v.value,
      );
      if (blockers.isEmpty) throw const FormatException('Missing blockers.');
      return SupplierImportFinalizationNotReady._(
        _id(a['resolutionId']),
        _revision(a['evaluatedRevision']),
        blockers,
        _findings(
          a['warnings'],
          SupplierImportFinalizationWarningCode.values,
          (v) => v.value,
        ),
      );
    }
    final id = _id(m['resolutionId']);
    switch (outcome) {
      case 'applied':
      case 'already_applied':
        _exact(m, {'outcome', 'resolutionId', 'revision', 'resultingDraftId'});
        final revision = _revision(m['revision']);
        if (revision < 2) {
          throw const FormatException('Invalid finalized revision.');
        }
        return SupplierImportFinalizationSuccess._(
          id,
          revision,
          _id(m['resultingDraftId']),
          alreadyApplied: outcome == 'already_applied',
        );
      case 'resolution_conflict':
        _exact(m, {'outcome', 'resolutionId', 'currentRevision'});
        return SupplierImportFinalizationConflict._(
          id,
          _revision(m['currentRevision'], allowZero: true),
        );
      case 'resolution_not_started':
        _exact(m, {'outcome', 'resolutionId', 'revision'});
        if (m['revision'] is! int || m['revision'] != 0) {
          throw const FormatException('Invalid absent revision.');
        }
        return SupplierImportFinalizationNotStarted._(id);
      case 'resolution_finalized':
        _exact(m, {'outcome', 'resolutionId', 'revision'});
        final revision = _revision(m['revision']);
        if (revision < 2) {
          throw const FormatException('Invalid finalized revision.');
        }
        return SupplierImportFinalizationFinalized._(id, revision);
      case 'persistence_capacity_exceeded':
        _exact(m, {'outcome', 'resolutionId', 'boundary'});
        return SupplierImportFinalizationCapacityExceeded._(
          id,
          SupplierImportResolutionParsing.enumValue(
            m['boundary'],
            SupplierImportFinalizationCapacityBoundary.values,
            (v) => v.value,
            'Capacity boundary',
          ),
        );
      default:
        throw const FormatException('Unsupported finalization outcome.');
    }
  }
}

final class SupplierImportFinalizationSuccess
    extends SupplierImportFinalizationOutcome {
  const SupplierImportFinalizationSuccess._(
    super.resolutionId,
    this.revision,
    this.resultingDraftId, {
    required this.alreadyApplied,
  });
  final int revision;
  final String resultingDraftId;
  final bool alreadyApplied;
}

final class SupplierImportFinalizationNotReady
    extends SupplierImportFinalizationOutcome {
  const SupplierImportFinalizationNotReady._(
    super.resolutionId,
    this.evaluatedRevision,
    this.blockers,
    this.warnings,
  );
  final int evaluatedRevision;
  bool get canFinalize => false;
  final List<
    SupplierImportFinalizationFinding<SupplierImportFinalizationBlockerCode>
  >
  blockers;
  final List<
    SupplierImportFinalizationFinding<SupplierImportFinalizationWarningCode>
  >
  warnings;
}

final class SupplierImportFinalizationConflict
    extends SupplierImportFinalizationOutcome {
  const SupplierImportFinalizationConflict._(
    super.resolutionId,
    this.currentRevision,
  );
  final int currentRevision;
}

final class SupplierImportFinalizationNotStarted
    extends SupplierImportFinalizationOutcome {
  const SupplierImportFinalizationNotStarted._(super.resolutionId);
  int get revision => 0;
}

final class SupplierImportFinalizationFinalized
    extends SupplierImportFinalizationOutcome {
  const SupplierImportFinalizationFinalized._(
    super.resolutionId,
    this.revision,
  );
  final int revision;
}

final class SupplierImportFinalizationCapacityExceeded
    extends SupplierImportFinalizationOutcome {
  const SupplierImportFinalizationCapacityExceeded._(
    super.resolutionId,
    this.boundary,
  );
  final SupplierImportFinalizationCapacityBoundary boundary;
}

Map<String, Object?> _exact(Object? v, Set<String> fields) =>
    SupplierImportResolutionParsing.exact(v, fields, 'Finalization response');
String _id(Object? v, {int? maximum}) {
  if (v is! String ||
      v.isEmpty ||
      v.trim() != v ||
      v == '.' ||
      v == '..' ||
      RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(v)) {
    throw const FormatException('Invalid finalization identity.');
  }
  final id = v;
  if (maximum != null && id.length > maximum) {
    throw const FormatException('Finalization identity too long.');
  }
  return id;
}

int _revision(Object? v, {bool allowZero = false}) {
  if (v is! int || v < (allowZero ? 0 : 1) || v > 9007199254740991) {
    throw const FormatException('Invalid finalization revision.');
  }
  return v;
}

List<SupplierImportFinalizationFinding<T>> _findings<T extends Enum>(
  Object? v,
  List<T> codes,
  String Function(T) value,
) => List.unmodifiable(
  SupplierImportResolutionParsing.list(v, 'Findings').map((item) {
    final m = _exact(item, {'code', 'targetKind', 'targetId'});
    return SupplierImportFinalizationFinding._(
      SupplierImportResolutionParsing.enumValue(
        m['code'],
        codes,
        value,
        'Finding code',
      ),
      SupplierImportResolutionParsing.enumValue(
        m['targetKind'],
        SupplierImportFinalizationTargetKind.values,
        (v) => v.value,
        'Finding target',
      ),
      m['targetId'] == null ? null : _id(m['targetId']),
    );
  }),
);
