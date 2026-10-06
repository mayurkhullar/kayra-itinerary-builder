import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import '../../../domain/supplier_import_resolution_mutation.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import 'review_exclusion_note.dart';
import 'staged_service_correction.dart';
import 'staged_service_correction_editor.dart';
import 'staged_service_corrections.dart';
import 'staged_service_review_data.dart';

enum _ServiceAction { retain, assign, exclude, revert }

class StagedServiceDecisionDialog extends StatefulWidget {
  const StagedServiceDecisionDialog({
    super.key,
    required this.service,
    required this.review,
  });
  final SupplierExtractionServiceFact service;
  final StagedServiceReviewData review;

  @override
  State<StagedServiceDecisionDialog> createState() =>
      _StagedServiceDecisionDialogState();
}

class _StagedServiceDecisionDialogState
    extends State<StagedServiceDecisionDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _correctionEditor = GlobalKey<StagedServiceCorrectionEditorState>();
  StagedServiceCorrectionField? _correctionField;
  _ServiceAction? _action;
  SupplierExtractionStagedDay? _day;
  SupplierImportExclusionReason? _reason;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (_correctionField != null) {
      _correctionEditor.currentState?.submit();
      return;
    }
    if (!_form.currentState!.validate()) return;
    final review = widget.review;
    final service = widget.service;
    final SupplierImportResolutionMutationCommand? command = switch (_action) {
      _ServiceAction.retain => SupplierImportSetDecisionCommand(
        review.retain(service),
      ),
      _ServiceAction.assign when _day != null =>
        SupplierImportSetDecisionCommand(review.assign(service, _day!)),
      _ServiceAction.exclude when _reason != null =>
        SupplierImportSetDecisionCommand(
          review.exclude(
            service,
            _reason!,
            _normalizedNote.isEmpty ? null : _normalizedNote,
          ),
        ),
      _ServiceAction.revert => SupplierImportRemoveDecisionCommand(service.id),
      _ => null,
    };
    if (command != null) Navigator.of(context).pop(command);
  }

  String get _normalizedNote =>
      _note.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final service = widget.service;
    final assigned = review.sourceDayId(service) != null;
    final targets = review.targetsFor(service);
    final decision = review.decisionFor(service.id);
    final canSave = switch (_action) {
      _ServiceAction.retain || _ServiceAction.revert => true,
      _ServiceAction.assign => _day != null,
      _ServiceAction.exclude => _reason != null,
      null => false,
    };
    final media = MediaQuery.of(context);
    return Dialog(
      key: const ValueKey('service-decision-dialog'),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s20,
        vertical: AppSpacing.s24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: (media.size.height - media.viewInsets.bottom) * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review service',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    service.title ??
                        service.hotelDetails?.hotelName ??
                        service.activityDetails?.activityName ??
                        'Extracted service',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  child: _correctionField != null
                      ? StagedServiceCorrectionEditor(
                          key: _correctionEditor,
                          service: service,
                          field: _correctionField!,
                          review: review,
                          onSubmit: (command) =>
                              Navigator.of(context).pop(command),
                        )
                      : Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Source placement: ${review.sourcePlacement(service)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: AppSpacing.s12),
                              RadioGroup<_ServiceAction>(
                                groupValue: _action,
                                onChanged: (value) =>
                                    setState(() => _action = value),
                                child: Column(
                                  children: [
                                    if (review.canRetainSource(service))
                                      RadioListTile<_ServiceAction>(
                                        key: const ValueKey(
                                          'service-action-retain',
                                        ),
                                        value: _ServiceAction.retain,
                                        title: const Text(
                                          'Retain source placement',
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    if (targets.isNotEmpty)
                                      RadioListTile<_ServiceAction>(
                                        key: const ValueKey(
                                          'service-action-assign',
                                        ),
                                        value: _ServiceAction.assign,
                                        title: Text(
                                          assigned
                                              ? 'Move to another day'
                                              : 'Assign to a day',
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    RadioListTile<_ServiceAction>(
                                      key: const ValueKey(
                                        'service-action-exclude',
                                      ),
                                      value: _ServiceAction.exclude,
                                      title: const Text('Exclude from import'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    if (decision != null)
                                      RadioListTile<_ServiceAction>(
                                        key: const ValueKey(
                                          'service-action-revert',
                                        ),
                                        value: _ServiceAction.revert,
                                        title: const Text('Revert decision'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                  ],
                                ),
                              ),
                              if (targets.isEmpty &&
                                  !review.canRetainSource(service))
                                const Text(
                                  'No retained source days are available for assignment.',
                                ),
                              if (_action == _ServiceAction.assign) ...[
                                const SizedBox(height: AppSpacing.s16),
                                Text(
                                  'Choose a source day',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: AppSpacing.s4),
                                const Text(
                                  'Place after the current services on the selected day. The original source placement stays unchanged.',
                                ),
                                RadioGroup<SupplierExtractionStagedDay>(
                                  groupValue: _day,
                                  onChanged: (value) =>
                                      setState(() => _day = value),
                                  child: Column(
                                    children: [
                                      for (final day in targets)
                                        RadioListTile<
                                          SupplierExtractionStagedDay
                                        >(
                                          key: ValueKey(
                                            'service-target-${day.id}',
                                          ),
                                          value: day,
                                          title: Text(stagedDayLabel(day)),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              if (_action == _ServiceAction.exclude) ...[
                                const SizedBox(height: AppSpacing.s16),
                                Text(
                                  'Exclusion reason',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                RadioGroup<SupplierImportExclusionReason>(
                                  groupValue: _reason,
                                  onChanged: (value) =>
                                      setState(() => _reason = value),
                                  child: Column(
                                    children: [
                                      for (final reason
                                          in SupplierImportExclusionReason
                                              .values)
                                        RadioListTile<
                                          SupplierImportExclusionReason
                                        >(
                                          key: ValueKey(
                                            'service-reason-${reason.value}',
                                          ),
                                          value: reason,
                                          title: Text(
                                            exclusionReasonLabel(reason),
                                          ),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s12),
                                TextFormField(
                                  key: const ValueKey('service-exclusion-note'),
                                  controller: _note,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    labelText:
                                        _reason ==
                                            SupplierImportExclusionReason.other
                                        ? 'Exclusion note (required)'
                                        : 'Exclusion note (optional)',
                                    helperText:
                                        'Explain the exclusion only. Do not include commercial details.',
                                    helperMaxLines: 3,
                                  ),
                                  validator: (_) =>
                                      validateServiceExclusionNote(
                                        _normalizedNote,
                                        _reason,
                                      ),
                                ),
                              ],
                              if (_action == _ServiceAction.revert) ...[
                                const SizedBox(height: AppSpacing.s16),
                                const Text(
                                  'Remove the entire consultant decision: placement, disposition, order and all field corrections. Supplier source content and review history stay unchanged.',
                                ),
                              ] else if (decision != null &&
                                  decision.overrides.toMap().isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.s16),
                                const Text(
                                  'Existing field corrections will be kept.',
                                ),
                              ],
                              if (_action == null)
                                StagedServiceCorrections(
                                  service: service,
                                  review: review,
                                  onCorrect: (field) =>
                                      setState(() => _correctionField = field),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: AppSpacing.s12,
                overflowSpacing: AppSpacing.s8,
                children: [
                  if (_correctionField != null)
                    TextButton(
                      onPressed: () => setState(() => _correctionField = null),
                      child: const Text('Back'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const ValueKey('save-service-decision'),
                    onPressed: canSave || _correctionField != null
                        ? _save
                        : null,
                    child: Text(
                      _correctionField != null
                          ? 'Save correction'
                          : _action == _ServiceAction.revert
                          ? 'Revert decision'
                          : 'Save decision',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors the callable's exclusion-note input limits for immediate feedback;
/// authorization and semantic validity remain server-owned.
String? validateServiceExclusionNote(
  String note,
  SupplierImportExclusionReason? reason,
) => validateReviewExclusionNote(note, reason, subject: 'service');
