import 'supplier_import_resolution_overrides.dart';
import 'supplier_import_resolution_parsing.dart';

enum SupplierImportAuditAction {
  openReview('open_review'),
  setTitleDecision('set_title_decision'),
  revertTitleDecision('revert_title_decision'),
  setDayDecision('set_day_decision'),
  setDayOrder('set_day_order'),
  setServiceDecision('set_service_decision'),
  setServiceOrder('set_service_order'),
  setPackageFactDecision('set_package_fact_decision'),
  setAncillaryDecision('set_ancillary_decision'),
  setReviewIssueDecision('set_review_issue_decision'),
  upsertManualDay('upsert_manual_day'),
  removeManualDay('remove_manual_day'),
  upsertManualService('upsert_manual_service'),
  removeManualService('remove_manual_service'),
  revertDecision('revert_decision'),
  finalize('finalize');

  const SupplierImportAuditAction(this.value);
  final String value;
}

enum SupplierImportAuditTargetKind {
  resolution('resolution'),
  title('title'),
  day('day'),
  service('service'),
  packageFact('package_fact'),
  ancillaryFact('ancillary_fact'),
  reviewIssue('review_issue'),
  manualDay('manual_day'),
  manualService('manual_service'),
  finalization('finalization');

  const SupplierImportAuditTargetKind(this.value);
  final String value;
}

enum SupplierImportAuditDisposition {
  accept('accept'),
  overrideValue('override'),
  retain('retain'),
  exclude('exclude'),
  mapToDayService('map_to_day_service'),
  retainPackageLevel('retain_package_level'),
  mapToService('map_to_service'),
  routeToFlightWorkflow('route_to_flight_workflow'),
  routeToVisaWorkflow('route_to_visa_workflow'),
  handledSeparately('handled_separately'),
  acknowledged('acknowledged'),
  resolved('resolved'),
  overridden('overridden');

  const SupplierImportAuditDisposition(this.value);
  final String value;
}

enum SupplierImportAuditChangedField {
  title('title'),
  date('date'),
  summary('summary'),
  notes('notes'),
  canonicalOrder('canonicalOrder'),
  day('day'),
  serviceType('serviceType'),
  description('description'),
  startTime('startTime'),
  endTime('endTime'),
  location('location'),
  city('city'),
  inclusions('inclusions'),
  exclusions('exclusions'),
  hotelName('hotelName'),
  orSimilar('orSimilar'),
  checkInDate('checkInDate'),
  checkOutDate('checkOutDate'),
  nightCount('nightCount'),
  roomType('roomType'),
  mealPlan('mealPlan'),
  numberOfRooms('numberOfRooms'),
  supplierStarRating('supplierStarRating'),
  pickup('pickup'),
  dropoff('dropoff'),
  vehicleType('vehicleType'),
  transferType('transferType'),
  activityName('activityName'),
  duration('duration'),
  activityType('activityType'),
  category('category'),
  text('text'),
  quantity('quantity'),
  frequency('frequency'),
  appliesTo('appliesTo'),
  kind('kind'),
  fieldValue('value'),
  airline('airline'),
  flightNumber('flightNumber'),
  origin('origin'),
  destination('destination'),
  departureDate('departureDate'),
  departureTime('departureTime'),
  arrivalDate('arrivalDate'),
  arrivalTime('arrivalTime'),
  cabinClass('cabinClass'),
  bookingClass('bookingClass'),
  conditions('conditions'),
  disposition('disposition');

  const SupplierImportAuditChangedField(this.value);
  final String value;
}

sealed class SupplierImportAuditMetadata {
  const SupplierImportAuditMetadata();

  factory SupplierImportAuditMetadata.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.record(
      input,
      'Audit metadata',
    );
    if (data['kind'] == 'lifecycle') {
      final value = SupplierImportResolutionParsing.exact(data, const {
        'kind',
        'status',
      }, 'Lifecycle audit metadata');
      if (value['status'] != 'active' && value['status'] != 'finalized') {
        throw const FormatException('Audit lifecycle status is invalid.');
      }
      return SupplierImportLifecycleAuditMetadata(value['status'] as String);
    }
    if (data['kind'] == 'manual_item') {
      final value = SupplierImportResolutionParsing.exact(data, const {
        'kind',
        'itemKind',
        'operation',
      }, 'Manual-item audit metadata');
      if (!const {
            'consultant_day',
            'consultant_service',
          }.contains(value['itemKind']) ||
          !const {'added', 'updated', 'removed'}.contains(value['operation'])) {
        throw const FormatException('Manual-item audit metadata is invalid.');
      }
      return SupplierImportManualItemAuditMetadata(
        itemKind: value['itemKind'] as String,
        operation: value['operation'] as String,
      );
    }
    if (data['kind'] == 'decision') {
      final value = SupplierImportResolutionParsing.exact(data, const {
        'kind',
        'disposition',
        'changedFields',
        'exclusionReason',
        'referencedIds',
      }, 'Decision audit metadata');
      final changed =
          SupplierImportResolutionParsing.list(
                value['changedFields'],
                'Audit changed fields',
              )
              .map(
                (item) => SupplierImportResolutionParsing.enumValue(
                  item,
                  SupplierImportAuditChangedField.values,
                  (field) => field.value,
                  'Audit changed field',
                ),
              )
              .toList();
      final references =
          SupplierImportResolutionParsing.list(
                value['referencedIds'],
                'Audit references',
              )
              .map(
                (item) =>
                    SupplierImportResolutionParsing.id(item, 'Audit reference'),
              )
              .toList();
      SupplierImportResolutionParsing.unique(changed, 'audit changed fields');
      SupplierImportResolutionParsing.unique(references, 'audit references');
      return SupplierImportDecisionAuditMetadata(
        disposition: SupplierImportResolutionParsing.enumValue(
          value['disposition'],
          SupplierImportAuditDisposition.values,
          (item) => item.value,
          'Audit disposition',
        ),
        changedFields: changed,
        exclusionReason: parseSupplierImportExclusionReason(
          value['exclusionReason'],
          'Audit exclusion reason',
        ),
        referencedIds: references,
      );
    }
    throw const FormatException('Audit metadata kind is invalid.');
  }
}

final class SupplierImportLifecycleAuditMetadata
    extends SupplierImportAuditMetadata {
  const SupplierImportLifecycleAuditMetadata(this.status);
  final String status;
}

final class SupplierImportManualItemAuditMetadata
    extends SupplierImportAuditMetadata {
  const SupplierImportManualItemAuditMetadata({
    required this.itemKind,
    required this.operation,
  });
  final String itemKind;
  final String operation;
}

final class SupplierImportDecisionAuditMetadata
    extends SupplierImportAuditMetadata {
  SupplierImportDecisionAuditMetadata({
    required this.disposition,
    required List<SupplierImportAuditChangedField> changedFields,
    required this.exclusionReason,
    required List<String> referencedIds,
  }) : changedFields = List.unmodifiable(changedFields),
       referencedIds = List.unmodifiable(referencedIds);

  final SupplierImportAuditDisposition disposition;
  final List<SupplierImportAuditChangedField> changedFields;
  final SupplierImportExclusionReason? exclusionReason;
  final List<String> referencedIds;
}

final class SupplierImportAuditEvent {
  const SupplierImportAuditEvent._({
    required this.eventId,
    required this.resolutionId,
    required this.extractionId,
    required this.previousRevision,
    required this.resultingRevision,
    required this.actorUid,
    required this.occurredAt,
    required this.action,
    required this.targetKind,
    required this.targetId,
    required this.commandId,
    required this.metadata,
  });

  factory SupplierImportAuditEvent.fromMap(Object? input) {
    final data = SupplierImportResolutionParsing.exact(input, const {
      'eventId',
      'resolutionId',
      'extractionId',
      'previousRevision',
      'resultingRevision',
      'actorUid',
      'occurredAt',
      'action',
      'targetKind',
      'targetId',
      'commandId',
      'metadata',
    }, 'Resolution audit event');
    final eventId = SupplierImportResolutionParsing.id(
      data['eventId'],
      'Audit event',
    );
    final commandId = SupplierImportResolutionParsing.id(
      data['commandId'],
      'Audit command',
    );
    final previous = SupplierImportResolutionParsing.nonNegativeInt(
      data['previousRevision'],
      'Audit previous revision',
    );
    final resulting = SupplierImportResolutionParsing.positiveInt(
      data['resultingRevision'],
      'Audit resulting revision',
    );
    if (eventId.length > 128 ||
        commandId.length > 128 ||
        eventId != commandId ||
        resulting != previous + 1) {
      throw const FormatException('Audit identity or revision is invalid.');
    }
    return SupplierImportAuditEvent._(
      eventId: eventId,
      resolutionId: SupplierImportResolutionParsing.id(
        data['resolutionId'],
        'Audit resolution',
      ),
      extractionId: SupplierImportResolutionParsing.id(
        data['extractionId'],
        'Audit extraction',
      ),
      previousRevision: previous,
      resultingRevision: resulting,
      actorUid: SupplierImportResolutionParsing.id(
        data['actorUid'],
        'Audit actor',
      ),
      occurredAt: SupplierImportResolutionParsing.timestamp(
        data['occurredAt'],
        'Audit time',
      ),
      action: SupplierImportResolutionParsing.enumValue(
        data['action'],
        SupplierImportAuditAction.values,
        (item) => item.value,
        'Audit action',
      ),
      targetKind: SupplierImportResolutionParsing.enumValue(
        data['targetKind'],
        SupplierImportAuditTargetKind.values,
        (item) => item.value,
        'Audit target kind',
      ),
      targetId: SupplierImportResolutionParsing.nullableId(
        data['targetId'],
        'Audit target',
      ),
      commandId: commandId,
      metadata: SupplierImportAuditMetadata.fromMap(data['metadata']),
    );
  }

  final String eventId;
  final String resolutionId;
  final String extractionId;
  final int previousRevision;
  final int resultingRevision;
  final String actorUid;
  final DateTime occurredAt;
  final SupplierImportAuditAction action;
  final SupplierImportAuditTargetKind targetKind;
  final String? targetId;
  final String commandId;
  final SupplierImportAuditMetadata metadata;
}
