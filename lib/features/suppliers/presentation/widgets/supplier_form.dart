import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/kayra_supplier.dart';
import 'supplier_contact_editor.dart';

class SupplierForm extends StatefulWidget {
  const SupplierForm({super.key, this.supplier, required this.onSave});
  final KayraSupplier? supplier;
  final Future<void> Function(SupplierDetails details) onSave;
  @override
  State<SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name);
  final _destination = TextEditingController();
  final _destinationFocus = FocusNode();
  late final _contacts = widget.supplier == null
      ? [SupplierContactDraft(primary: true)]
      : widget.supplier!.contacts
            .map((contact) => SupplierContactDraft(contact: contact))
            .toList();
  late List<String> _destinations = List.of(
    widget.supplier?.destinationCoverage ?? [],
  );
  late final _categories = <SupplierServiceCategory>{
    ...?widget.supplier?.serviceCategories,
  };
  bool _saving = false;
  bool _failed = false;
  bool get _editing => widget.supplier != null;

  @override
  void dispose() {
    _name.dispose();
    _destination.dispose();
    _destinationFocus.dispose();
    for (final contact in _contacts) {
      contact.dispose();
    }
    super.dispose();
  }

  void _addDestination({bool focus = true}) {
    if (_saving) return;
    setState(() {
      _destinations = SupplierValidation.destinations([
        ..._destinations,
        _destination.text,
      ]);
      _destination.clear();
    });
    if (focus) _destinationFocus.requestFocus();
  }

  void _removeContact(SupplierContactDraft contact) {
    setState(() {
      _contacts.remove(contact);
      if (_contacts.isNotEmpty &&
          !_contacts.any((contact) => contact.isPrimary)) {
        _contacts.first.isPrimary = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => contact.dispose());
  }

  Future<void> _save() async {
    if (_saving) return;
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 200),
      );
      return;
    }
    _addDestination(focus: false);
    final details = SupplierDetails(
      name: _name.text,
      contacts: _contacts.map((contact) => contact.toContact()).toList(),
      destinationCoverage: _destinations,
      serviceCategories: _categories.toList(),
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(details);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final availableHeight = (media.size.height - media.viewInsets.vertical - 40)
        .clamp(0.0, double.infinity);
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpacing.s20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: SizedBox(
          key: const ValueKey('supplier-dialog-content'),
          width: 736,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: media.size.width >= 640
                  ? availableHeight * 0.85
                  : availableHeight,
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
                        _editing ? 'Edit Supplier' : 'New Supplier',
                        style: text.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        _editing
                            ? 'Update this supplier’s shared profile.'
                            : 'Add a supplier to Kayra’s shared master.',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('supplier-form-scroll'),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s20,
                      AppSpacing.s8,
                      AppSpacing.s20,
                      0,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            key: const ValueKey('supplier-name'),
                            controller: _name,
                            enabled: !_saving,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            decoration: const InputDecoration(
                              labelText: 'Supplier Name *',
                              errorMaxLines: 2,
                            ),
                            validator: (value) {
                              try {
                                SupplierValidation.requiredText(
                                  value ?? '',
                                  'Supplier name',
                                );
                                return null;
                              } on FormatException catch (error) {
                                return error.message;
                              }
                            },
                          ),
                          const SizedBox(height: AppSpacing.s24),
                          Text('Contacts', style: text.titleMedium),
                          Text(
                            'Use a phone number or email for each contact.',
                            style: text.bodySmall,
                          ),
                          RadioGroup<SupplierContactDraft>(
                            groupValue: _contacts
                                .where((contact) => contact.isPrimary)
                                .firstOrNull,
                            onChanged: (selected) {
                              if (_saving || selected == null) return;
                              setState(() {
                                for (final contact in _contacts) {
                                  contact.isPrimary = identical(
                                    contact,
                                    selected,
                                  );
                                }
                              });
                            },
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < _contacts.length;
                                  index++
                                ) ...[
                                  SupplierContactEditor(
                                    key: ObjectKey(_contacts[index]),
                                    draft: _contacts[index],
                                    index: index,
                                    enabled: !_saving,
                                    onRemove: () =>
                                        _removeContact(_contacts[index]),
                                  ),
                                  const Divider(),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                      () => _contacts.add(
                                        SupplierContactDraft(
                                          primary: _contacts.isEmpty,
                                        ),
                                      ),
                                    ),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add Contact'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s16),
                          Text('Destination Coverage', style: text.titleMedium),
                          const SizedBox(height: AppSpacing.s12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('supplier-destination'),
                                  controller: _destination,
                                  focusNode: _destinationFocus,
                                  enabled: !_saving,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Destination',
                                  ),
                                  onSubmitted: (_) => _addDestination(),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              IconButton(
                                tooltip: 'Add destination',
                                onPressed: _saving ? null : _addDestination,
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          Wrap(
                            spacing: AppSpacing.s8,
                            runSpacing: AppSpacing.s4,
                            children: [
                              for (final destination in _destinations)
                                InputChip(
                                  label: Text(
                                    destination,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  deleteButtonTooltipMessage:
                                      'Remove $destination',
                                  onDeleted: _saving
                                      ? null
                                      : () => setState(
                                          () => _destinations = _destinations
                                              .where(
                                                (value) => value != destination,
                                              )
                                              .toList(),
                                        ),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s20),
                          Text('Service Categories', style: text.titleMedium),
                          const SizedBox(height: AppSpacing.s8),
                          Wrap(
                            spacing: AppSpacing.s8,
                            runSpacing: AppSpacing.s4,
                            children: [
                              for (final category
                                  in SupplierServiceCategory.values)
                                FilterChip(
                                  label: Text(category.label),
                                  selected: _categories.contains(category),
                                  selectedColor: AppColors.navyTint,
                                  backgroundColor: AppColors.white,
                                  side: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                  onSelected: _saving
                                      ? null
                                      : (selected) => setState(() {
                                          if (selected) {
                                            _categories.add(category);
                                          } else {
                                            _categories.remove(category);
                                          }
                                        }),
                                ),
                            ],
                          ),
                          if (_editing) ...[
                            const SizedBox(height: AppSpacing.s16),
                            Text(
                              'Status: ${widget.supplier!.status == SupplierStatus.active ? 'Active' : 'Inactive'}',
                              style: text.bodySmall,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.s20),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_failed)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.s12,
                          ),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _editing
                                  ? 'Supplier couldn’t be updated. Please try again.'
                                  : 'Supplier couldn’t be created. Please try again.',
                              style: text.bodyMedium,
                            ),
                          ),
                        ),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpacing.s8,
                        runSpacing: AppSpacing.s8,
                        children: [
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox.square(
                                    dimension: AppSpacing.s20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.white,
                                      semanticsLabel: 'Saving supplier',
                                    ),
                                  )
                                : Text(
                                    _editing
                                        ? 'Save Changes'
                                        : 'Create Supplier',
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
