import 'package:flutter/material.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_values.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import 'review_components.dart';
import 'staged_service_correction_validation.dart';

/// Ordered, typed replacement inside the existing service correction form.
class StagedServiceConditionEditor extends StatefulWidget {
  const StagedServiceConditionEditor({super.key, required this.initialValues});
  final List<SupplierImportResolutionCondition> initialValues;
  @override
  State<StagedServiceConditionEditor> createState() =>
      StagedServiceConditionEditorState();
}

class StagedServiceConditionEditorState
    extends State<StagedServiceConditionEditor> {
  late final _rows = [
    for (final c in widget.initialValues) _ConditionRow(c.kind, c.value),
  ];
  final _retired = <_ConditionRow>[];
  List<SupplierImportResolutionCondition> get values => [
    for (final row in _rows)
      SupplierImportResolutionCondition(
        kind: row.kind!,
        value: normalizeServiceCorrection(row.value.text),
      ),
  ];
  @override
  void dispose() {
    for (final row in [..._rows, ..._retired]) {
      row.value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Conditions remain attached to this service in the order shown.',
      ),
      for (final (index, row) in _rows.indexed)
        Padding(
          key: ObjectKey(row),
          padding: const EdgeInsets.only(top: AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<SupplierExtractionConditionKind>(
                initialValue: row.kind,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Condition ${index + 1} kind',
                ),
                items: [
                  for (final kind in SupplierExtractionConditionKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(reviewLabel(kind.value)),
                    ),
                ],
                onChanged: (kind) => setState(() => row.kind = kind),
                validator: (kind) =>
                    kind == null ? 'Choose a condition kind.' : null,
              ),
              const SizedBox(height: AppSpacing.s12),
              TextFormField(
                controller: row.value,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Condition ${index + 1} value',
                  errorMaxLines: 3,
                ),
                validator: (value) =>
                    validateServiceCorrectionText(value ?? ''),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _rows.remove(row);
                    _retired.add(row);
                  }),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove condition'),
                ),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('service-condition-add'),
          onPressed: () => setState(() => _rows.add(_ConditionRow(null, ''))),
          icon: const Icon(Icons.add),
          label: const Text('Add condition'),
        ),
      ),
    ],
  );
}

final class _ConditionRow {
  _ConditionRow(this.kind, String text)
    : value = TextEditingController(text: text);
  SupplierExtractionConditionKind? kind;
  final TextEditingController value;
}
