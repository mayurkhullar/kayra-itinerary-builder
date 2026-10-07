import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_values.dart';
import '../../../domain/supplier_import_resolution_mutation.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import 'review_components.dart';
import 'staged_service_correction.dart';
import 'staged_service_correction_validation.dart';
import 'staged_service_corrections.dart';
import 'staged_service_list_editor.dart';
import 'staged_service_condition_editor.dart';
import 'staged_service_review_data.dart';

enum _CorrectionAction { set, clear, reset }

class StagedServiceCorrectionEditor extends StatefulWidget {
  const StagedServiceCorrectionEditor({
    super.key,
    required this.service,
    required this.field,
    required this.review,
    required this.onSubmit,
  });
  final SupplierExtractionServiceFact service;
  final StagedServiceCorrectionField field;
  final StagedServiceReviewData review;
  final ValueChanged<SupplierImportSetDecisionCommand> onSubmit;

  @override
  State<StagedServiceCorrectionEditor> createState() =>
      StagedServiceCorrectionEditorState();
}

class StagedServiceCorrectionEditorState
    extends State<StagedServiceCorrectionEditor> {
  final _form = GlobalKey<FormState>();
  final _conditions = GlobalKey<StagedServiceConditionEditorState>();
  final _list = GlobalKey<StagedServiceListEditorState>();
  late final TextEditingController _value;
  Object? _choice;
  _CorrectionAction _action = _CorrectionAction.set;
  String? _error;
  bool _submitted = false;

  SupplierImportFieldOverride<Object?>? get _current => widget.field.overrideIn(
    widget.review.decisionFor(widget.service.id)?.overrides,
  );
  Object? get _currentValue => switch (_current) {
    SupplierImportSetOverride(:final value) => value,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(
      text: _currentValue is String || _currentValue is int
          ? _currentValue.toString()
          : '',
    );
    _choice = _currentValue;
    if (_current is SupplierImportClearOverride) {
      _action = _CorrectionAction.clear;
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void submit() {
    if (_submitted ||
        !widget.review.canCorrectField(widget.service, widget.field)) {
      return;
    }
    if (_action == _CorrectionAction.set && !_form.currentState!.validate()) {
      return;
    }
    final field = widget.field;
    final SupplierImportFieldOverride<Object?>? override = switch (_action) {
      _CorrectionAction.clear => const SupplierImportClearOverride(),
      _CorrectionAction.reset => null,
      _CorrectionAction.set => SupplierImportSetOverride(switch (field.input) {
        ServiceCorrectionInput.boolean ||
        ServiceCorrectionInput.serviceType ||
        ServiceCorrectionInput.transferType => _choice!,
        ServiceCorrectionInput.conditions => _conditions.currentState!.values,
        ServiceCorrectionInput.list => _list.currentState!.values,
        _ => parseServiceCorrection(field, _value.text),
      }),
    };
    final decision = widget.review.correctField(
      widget.service,
      field,
      override,
    );
    final error = validateServiceCorrectionComposition(
      widget.service,
      field,
      decision.overrides,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _submitted = true;
    widget.onSubmit(SupplierImportSetDecisionCommand(decision));
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Correct ${widget.field.label.toLowerCase()}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ServiceCorrectionSource(field: widget.field, service: widget.service),
        ReviewFields([
          ('Current consultant correction', serviceCorrectionLabel(_current)),
        ]),
        const SizedBox(height: AppSpacing.s16),
        RadioGroup<_CorrectionAction>(
          groupValue: _action,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _action = value;
                _error = null;
              });
            }
          },
          child: Column(
            children: [
              const RadioListTile<_CorrectionAction>(
                key: ValueKey('service-correction-set'),
                value: _CorrectionAction.set,
                title: Text('Set consultant value'),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.field.canClear)
                const RadioListTile<_CorrectionAction>(
                  key: ValueKey('service-correction-clear'),
                  value: _CorrectionAction.clear,
                  title: Text('Clear value'),
                  contentPadding: EdgeInsets.zero,
                ),
              if (_current != null)
                const RadioListTile<_CorrectionAction>(
                  key: ValueKey('service-correction-reset'),
                  value: _CorrectionAction.reset,
                  title: Text('Use supplier value'),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        if (_action == _CorrectionAction.set) _input(),
        if (_action == _CorrectionAction.clear)
          Text(
            'The ${widget.field.label.toLowerCase()} will be explicitly cleared for import. Supplier source evidence stays unchanged.',
          ),
        if (_action == _CorrectionAction.reset)
          Text(
            'Remove only the ${widget.field.label.toLowerCase()} correction and use the supplier value. Placement, disposition, order and other corrections stay unchanged.',
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s12),
            child: Semantics(liveRegion: true, child: Text(_error!)),
          ),
      ],
    ),
  );

  Widget _input() {
    final field = widget.field;
    final options = switch (field.input) {
      ServiceCorrectionInput.boolean => <Object>[true, false],
      ServiceCorrectionInput.serviceType =>
        SupplierExtractionServiceType.values,
      ServiceCorrectionInput.transferType =>
        SupplierExtractionTransferType.values,
      _ => <Object>[],
    };
    if (options.isNotEmpty) {
      return DropdownButtonFormField<Object>(
        key: const ValueKey('service-correction-choice'),
        initialValue: options.contains(_choice) ? _choice : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Consultant ${field.label.toLowerCase()}',
          errorMaxLines: 3,
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(serviceCorrectionValueLabel(option)),
            ),
        ],
        onChanged: (value) => setState(() {
          _choice = value;
          _error = null;
        }),
        validator: (value) => value == null ? 'Choose a value.' : null,
      );
    }
    if (field.input == ServiceCorrectionInput.conditions) {
      return StagedServiceConditionEditor(
        key: _conditions,
        initialValues: _currentValue is List<SupplierImportResolutionCondition>
            ? _currentValue! as List<SupplierImportResolutionCondition>
            : _current is SupplierImportClearOverride
            ? const []
            : [
                for (final c in widget.service.conditions)
                  SupplierImportResolutionCondition(
                    kind: c.kind,
                    value: c.value,
                  ),
              ],
      );
    }
    if (field.input == ServiceCorrectionInput.list) {
      return StagedServiceListEditor(
        key: _list,
        label: field.label,
        initialValues: _currentValue is List<String>
            ? _currentValue! as List<String>
            : const [],
      );
    }
    final multiline = field.input == ServiceCorrectionInput.multiline;
    return TextFormField(
      key: const ValueKey('service-correction-value'),
      controller: _value,
      minLines: multiline ? 3 : 1,
      maxLines: multiline
          ? 6
          : field.input == ServiceCorrectionInput.text
          ? 3
          : 1,
      keyboardType: switch (field.input) {
        ServiceCorrectionInput.date ||
        ServiceCorrectionInput.time => TextInputType.datetime,
        ServiceCorrectionInput.count => TextInputType.number,
        ServiceCorrectionInput.multiline => TextInputType.multiline,
        _ => TextInputType.text,
      },
      textInputAction: multiline
          ? TextInputAction.newline
          : TextInputAction.done,
      onFieldSubmitted: multiline ? null : (_) => submit(),
      decoration: InputDecoration(
        labelText: 'Consultant ${field.label.toLowerCase()}',
        hintText: switch (field.input) {
          ServiceCorrectionInput.date => 'YYYY-MM-DD',
          ServiceCorrectionInput.time => 'HH:mm',
          _ => null,
        },
        helperText: switch (field.input) {
          ServiceCorrectionInput.date =>
            'Enter this hotel date explicitly. Other dates and nights stay unchanged.',
          ServiceCorrectionInput.time =>
            '24-hour time. Other times stay unchanged.',
          ServiceCorrectionInput.count =>
            'Positive whole number. No automatic calculation.',
          _ => 'Non-commercial content only. Up to 2,000 characters.',
        },
        helperMaxLines: 4,
        errorMaxLines: 4,
      ),
      validator: (_) => validateServiceCorrectionInput(field, _value.text),
    );
  }
}
