import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import '../../../domain/supplier_import_resolution_mutation.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import 'review_components.dart';
import 'staged_day_correction.dart';
import 'staged_day_review_data.dart';
import 'staged_service_review_data.dart';

enum _CorrectionAction { set, clear, reset }

class StagedDayCorrectionEditor extends StatefulWidget {
  const StagedDayCorrectionEditor({
    super.key,
    required this.day,
    required this.field,
    required this.review,
    required this.onSubmit,
  });
  final SupplierExtractionStagedDay day;
  final StagedDayCorrectionField field;
  final StagedDayReviewData review;
  final ValueChanged<SupplierImportSetDecisionCommand> onSubmit;

  @override
  State<StagedDayCorrectionEditor> createState() =>
      StagedDayCorrectionEditorState();
}

class StagedDayCorrectionEditorState extends State<StagedDayCorrectionEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _value;
  _CorrectionAction _action = _CorrectionAction.set;
  bool _datePickerOpen = false;
  bool _submitted = false;

  SupplierImportFieldOverride<String>? get _current =>
      widget.field.overrideIn(widget.review.decisionFor(widget.day)?.overrides);

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(
      text: switch (_current) {
        SupplierImportSetOverride<String>(:final value) => value,
        _ => '',
      },
    );
    if (_current is SupplierImportClearOverride<String>) {
      _action = _CorrectionAction.clear;
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    if (_datePickerOpen) return;
    _datePickerOpen = true;
    // Calendar focus is not a correction. Only an explicit selection fills
    // the editor, and only Save correction sends a mutation.
    final initial = validateDayCorrection(widget.field, _value.text) == null
        ? DateTime.parse(normalizeDayCorrection(_value.text))
        : widget.day.date ?? DateTime.now();
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (_) => DatePickerDialog(
        initialDate: initial,
        firstDate: DateTime(0),
        lastDate: DateTime(9999, 12, 31),
      ),
    );
    _datePickerOpen = false;
    if (mounted && selected != null) {
      _value.text = selected.toIso8601String().substring(0, 10);
    }
  }

  void submit() {
    if (_submitted || !widget.review.canCorrect(widget.day)) return;
    if (_action == _CorrectionAction.set && !_form.currentState!.validate()) {
      return;
    }
    final SupplierImportFieldOverride<String>? override = switch (_action) {
      _CorrectionAction.set => SupplierImportSetOverride(
        normalizeDayCorrection(_value.text),
      ),
      _CorrectionAction.clear => const SupplierImportClearOverride(),
      _CorrectionAction.reset => null,
    };
    final decision = widget.review.correctField(
      widget.day,
      widget.field,
      override,
    );
    _submitted = true;
    widget.onSubmit(SupplierImportSetDecisionCommand(decision));
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            stagedDayLabel(widget.day),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ReviewFields([
            (
              'Supplier source',
              field.sourceValue(widget.day) ?? 'Not provided',
            ),
            ('Current consultant correction', dayCorrectionLabel(_current)),
          ]),
          const SizedBox(height: AppSpacing.s16),
          RadioGroup<_CorrectionAction>(
            groupValue: _action,
            onChanged: (value) {
              if (value != null) setState(() => _action = value);
            },
            child: Column(
              children: [
                const RadioListTile<_CorrectionAction>(
                  key: ValueKey('correction-action-set'),
                  value: _CorrectionAction.set,
                  title: Text('Set consultant value'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (field.canClear)
                  const RadioListTile<_CorrectionAction>(
                    key: ValueKey('correction-action-clear'),
                    value: _CorrectionAction.clear,
                    title: Text('Clear value'),
                    contentPadding: EdgeInsets.zero,
                  ),
                if (_current != null)
                  const RadioListTile<_CorrectionAction>(
                    key: ValueKey('correction-action-reset'),
                    value: _CorrectionAction.reset,
                    title: Text('Use supplier value'),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_action == _CorrectionAction.set)
            TextFormField(
              key: const ValueKey('day-correction-value'),
              controller: _value,
              minLines: field.multiline ? 3 : 1,
              maxLines: field.multiline
                  ? 6
                  : field == StagedDayCorrectionField.title
                  ? 3
                  : 1,
              keyboardType: field == StagedDayCorrectionField.date
                  ? TextInputType.datetime
                  : field.multiline
                  ? TextInputType.multiline
                  : TextInputType.text,
              textInputAction: field.multiline
                  ? TextInputAction.newline
                  : TextInputAction.done,
              onFieldSubmitted: field.multiline ? null : (_) => submit(),
              decoration: InputDecoration(
                labelText: 'Consultant ${field.label.toLowerCase()}',
                hintText: field == StagedDayCorrectionField.date
                    ? 'YYYY-MM-DD'
                    : null,
                helperText: field == StagedDayCorrectionField.date
                    ? 'Changes this day only.'
                    : 'Non-commercial content only. Up to 2,000 characters.',
                helperMaxLines: 3,
                errorMaxLines: 3,
                suffixIcon: field == StagedDayCorrectionField.date
                    ? IconButton(
                        tooltip: 'Choose date',
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                      )
                    : null,
              ),
              validator: (_) => validateDayCorrection(field, _value.text),
            ),
          if (_action == _CorrectionAction.clear)
            Text(
              'The ${field.label.toLowerCase()} will be explicitly cleared for import. Supplier source evidence stays unchanged.',
            ),
          if (_action == _CorrectionAction.reset)
            Text(
              'Remove only the ${field.label.toLowerCase()} correction and use the supplier value. Day disposition, order and other corrections stay unchanged.',
            ),
        ],
      ),
    );
  }
}
