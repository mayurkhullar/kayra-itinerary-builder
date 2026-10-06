import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import 'staged_service_correction_validation.dart';

class StagedServiceListEditor extends StatefulWidget {
  const StagedServiceListEditor({
    super.key,
    required this.label,
    required this.initialValues,
  });
  final String label;
  final List<String> initialValues;

  @override
  State<StagedServiceListEditor> createState() =>
      StagedServiceListEditorState();
}

class StagedServiceListEditorState extends State<StagedServiceListEditor> {
  late final _items = [
    for (final value in widget.initialValues)
      TextEditingController(text: value),
  ];
  final _retired = <TextEditingController>[];

  List<String> get values => _items
      .map((item) => normalizeServiceCorrection(item.text))
      .where((value) => value.isNotEmpty)
      .toList();

  @override
  void dispose() {
    for (final item in [..._items, ..._retired]) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Replace this service list only. Each row is one item; empty rows are omitted. Supplier evidence stays unchanged.',
      ),
      for (final (index, item) in _items.indexed)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: ObjectKey(item),
                  controller: item,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: '${widget.label} item ${index + 1}',
                    errorMaxLines: 3,
                  ),
                  validator: (_) {
                    final value = normalizeServiceCorrection(item.text);
                    if (value.isEmpty) return null;
                    final error = validateServiceCorrectionText(value);
                    if (error != null) return error;
                    return values.where((other) => other == value).length > 1
                        ? 'Use each item once.'
                        : null;
                  },
                ),
              ),
              IconButton(
                tooltip:
                    'Remove ${widget.label.toLowerCase()} item ${index + 1}',
                onPressed: () => setState(() {
                  _items.remove(item);
                  // Keep controllers alive until their removed fields have unmounted.
                  _retired.add(item);
                }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      if (_items.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.s12),
          child: Text('Empty replacement list'),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('service-list-add'),
          onPressed: () => setState(() => _items.add(TextEditingController())),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
      ),
    ],
  );
}
