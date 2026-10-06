import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import '../../../domain/supplier_import_resolution_mutation.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import 'review_exclusion_note.dart';
import 'staged_day_review_data.dart';
import 'staged_service_review_data.dart';

enum _DayAction { retain, order, exclude, revert }

class StagedDayDecisionDialog extends StatefulWidget {
  const StagedDayDecisionDialog({
    super.key,
    required this.day,
    required this.review,
  });
  final SupplierExtractionStagedDay day;
  final StagedDayReviewData review;

  @override
  State<StagedDayDecisionDialog> createState() =>
      _StagedDayDecisionDialogState();
}

class _StagedDayDecisionDialogState extends State<StagedDayDecisionDialog> {
  final _form = GlobalKey<FormState>();
  final _order = TextEditingController();
  final _note = TextEditingController();
  _DayAction? _action;
  SupplierImportExclusionReason? _reason;

  @override
  void dispose() {
    _order.dispose();
    _note.dispose();
    super.dispose();
  }

  String? get _blocker => switch (_action) {
    _DayAction.retain => widget.review.orderError(
      widget.day,
      widget.review.effectiveOrder(widget.day),
    ),
    _DayAction.exclude => widget.review.exclusionBlocker(widget.day),
    _DayAction.revert => widget.review.orderError(widget.day, widget.day.order),
    _ => null,
  };
  int? get _parsedOrder => RegExp(r'^[0-9]+$').hasMatch(_order.text.trim())
      ? int.tryParse(_order.text.trim())
      : null;

  void _save() {
    if (_blocker != null || !_form.currentState!.validate()) return;
    final review = widget.review;
    final day = widget.day;
    final note = _note.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final SupplierImportResolutionMutationCommand? command = switch (_action) {
      _DayAction.retain => SupplierImportSetDecisionCommand(review.retain(day)),
      _DayAction.order when _parsedOrder != null =>
        SupplierImportSetDecisionCommand(
          review.retain(day, order: _parsedOrder),
        ),
      _DayAction.exclude when _reason != null =>
        SupplierImportSetDecisionCommand(
          review.exclude(day, _reason!, note.isEmpty ? null : note),
        ),
      _DayAction.revert => SupplierImportRemoveDecisionCommand(day.id),
      _ => null,
    };
    if (command != null) Navigator.of(context).pop(command);
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final day = widget.day;
    final decision = review.decisionFor(day);
    final media = MediaQuery.of(context);
    final canSave =
        _action != null &&
        _blocker == null &&
        (_action != _DayAction.exclude || _reason != null);
    return Dialog(
      key: const ValueKey('day-decision-dialog'),
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
              child: Text(
                'Review day',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          stagedDayLabel(day),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          'Source position ${day.order} · ${day.assignedServiceIds.length} source services',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${review.effectiveServiceCount(day)} extracted services currently assigned here',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        RadioGroup<_DayAction>(
                          groupValue: _action,
                          onChanged: (value) => setState(() => _action = value),
                          child: Column(
                            children: [
                              const RadioListTile<_DayAction>(
                                key: ValueKey('day-action-retain'),
                                value: _DayAction.retain,
                                title: Text('Retain day'),
                                contentPadding: EdgeInsets.zero,
                              ),
                              RadioListTile<_DayAction>(
                                key: const ValueKey('day-action-order'),
                                value: _DayAction.order,
                                title: Text(
                                  review.review.isRetainedDay(day)
                                      ? 'Change consultant order'
                                      : 'Retain with consultant order',
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              const RadioListTile<_DayAction>(
                                key: ValueKey('day-action-exclude'),
                                value: _DayAction.exclude,
                                title: Text('Exclude from import'),
                                contentPadding: EdgeInsets.zero,
                              ),
                              if (decision != null)
                                const RadioListTile<_DayAction>(
                                  key: ValueKey('day-action-revert'),
                                  value: _DayAction.revert,
                                  title: Text('Revert decision'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        ),
                        if (_action == _DayAction.order) ...[
                          const SizedBox(height: AppSpacing.s16),
                          const Text(
                            'Choose an unused positive order number. Only this day changes; other days keep their order. The source itinerary stays in supplier order.',
                          ),
                          const SizedBox(height: AppSpacing.s16),
                          TextFormField(
                            key: const ValueKey('day-consultant-order'),
                            controller: _order,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Consultant order',
                              errorMaxLines: 3,
                            ),
                            validator: (_) =>
                                review.orderError(day, _parsedOrder),
                          ),
                          const SizedBox(height: AppSpacing.s16),
                          Text(
                            'Current retained days',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          for (final retained in review.retainedDaysByOrder)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.s8,
                              ),
                              child: Text(
                                '${review.effectiveOrder(retained)} · ${stagedDayLabel(retained)}',
                              ),
                            ),
                        ],
                        if (_action == _DayAction.exclude &&
                            _blocker == null) ...[
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
                                    in SupplierImportExclusionReason.values)
                                  RadioListTile<SupplierImportExclusionReason>(
                                    key: ValueKey('day-reason-${reason.value}'),
                                    value: reason,
                                    title: Text(exclusionReasonLabel(reason)),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          TextFormField(
                            key: const ValueKey('day-exclusion-note'),
                            controller: _note,
                            minLines: 2,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText:
                                  _reason == SupplierImportExclusionReason.other
                                  ? 'Exclusion note (required)'
                                  : 'Exclusion note (optional)',
                              helperText:
                                  'Explain the exclusion only. Do not include commercial details.',
                              helperMaxLines: 3,
                            ),
                            validator: (_) => validateReviewExclusionNote(
                              _note.text.trim().replaceAll(RegExp(r'\s+'), ' '),
                              _reason,
                              subject: 'day',
                            ),
                          ),
                        ],
                        if (_blocker case final message?) ...[
                          const SizedBox(height: AppSpacing.s16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              message,
                              key: const ValueKey('day-decision-blocker'),
                            ),
                          ),
                        ],
                        if (_action == _DayAction.revert) ...[
                          const SizedBox(height: AppSpacing.s16),
                          const Text(
                            'Remove the current day decision, including any recorded field corrections, and restore the source order proposal. Supplier content, services and review history stay unchanged.',
                          ),
                        ] else if (decision != null &&
                            decision.overrides.toMap().isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.s16),
                          const Text(
                            'Existing field corrections will be kept.',
                          ),
                        ],
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
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const ValueKey('save-day-decision'),
                    onPressed: canSave ? _save : null,
                    child: Text(
                      _action == _DayAction.revert
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
