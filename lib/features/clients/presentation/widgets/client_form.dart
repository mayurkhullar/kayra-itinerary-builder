import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/kayra_client.dart';

class ClientForm extends StatefulWidget {
  const ClientForm({super.key, this.client, required this.onSave});

  final KayraClient? client;
  final Future<void> Function(ClientDetails details) onSave;

  @override
  State<ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<ClientForm> {
  final _formKey = GlobalKey<FormState>();
  late final _fields = <String, TextEditingController>{
    'First Name': TextEditingController(text: widget.client?.firstName),
    'Last Name': TextEditingController(text: widget.client?.lastName),
    'Mobile Number': TextEditingController(text: widget.client?.mobileNumber),
    'Email': TextEditingController(text: widget.client?.email),
    'City': TextEditingController(text: widget.client?.city),
    'Company': TextEditingController(text: widget.client?.company),
  };
  late final _focusNodes = {
    for (final label in _fields.keys) label: FocusNode(),
  };
  bool _saving = false;
  bool _failed = false;
  bool get _editing => widget.client != null;

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      final firstInvalid = _fields.keys.firstWhere(
        (label) => _validate(label, _fields[label]!.text) != null,
      );
      final node = _focusNodes[firstInvalid]!;
      node.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.context != null) {
          Scrollable.ensureVisible(
            node.context!,
            alignment: 0.1,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
      return;
    }
    final details = ClientDetails(
      firstName: _fields['First Name']!.text,
      lastName: _fields['Last Name']!.text,
      mobileNumber: _fields['Mobile Number']!.text,
      email: _fields['Email']!.text,
      city: _fields['City']!.text,
      company: _fields['Company']!.text,
    );
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

  String? _validate(String label, String? value) => switch (label) {
    'Mobile Number' => ClientValidation.mobileNumberError(value),
    'Email' => ClientValidation.emailError(value),
    'First Name' ||
    'Last Name' => ClientValidation.requiredTextError(value, label: label),
    _ => null,
  };

  Widget _field(String label) => TextFormField(
    key: ValueKey('client-$label'),
    controller: _fields[label],
    focusNode: _focusNodes[label],
    enabled: !_saving,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: InputDecoration(
      labelText: ['First Name', 'Last Name', 'Mobile Number'].contains(label)
          ? '$label *'
          : label,
      errorMaxLines: 2,
    ),
    keyboardType: label == 'Mobile Number'
        ? TextInputType.phone
        : label == 'Email'
        ? TextInputType.emailAddress
        : TextInputType.text,
    textCapitalization: label == 'Email' || label == 'Mobile Number'
        ? TextCapitalization.none
        : TextCapitalization.words,
    textInputAction: label == 'Company'
        ? TextInputAction.done
        : TextInputAction.next,
    onFieldSubmitted: label == 'Company' ? (_) => _save() : null,
    validator: (value) => _validate(label, value),
  );

  Widget _pair(String first, String second, bool twoColumns) => twoColumns
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(first)),
            const SizedBox(width: AppSpacing.s16),
            Expanded(child: _field(second)),
          ],
        )
      : Column(
          children: [
            _field(first),
            const SizedBox(height: AppSpacing.s16),
            _field(second),
          ],
        );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 640 &&
          MediaQuery.textScalerOf(context).scale(16) <= 20;
      return PopScope(
        canPop: !_saving,
        child: AlertDialog(
          backgroundColor: AppColors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(AppSpacing.s20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            side: const BorderSide(color: AppColors.border),
          ),
          scrollable: true,
          title: Text(_editing ? 'Edit Client' : 'New Client'),
          content: SizedBox(
            width: 552,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '* Required fields',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.s20),
                  _pair('First Name', 'Last Name', twoColumns),
                  const SizedBox(height: AppSpacing.s16),
                  _field('Mobile Number'),
                  const SizedBox(height: AppSpacing.s16),
                  _field('Email'),
                  const SizedBox(height: AppSpacing.s16),
                  _pair('City', 'Company', twoColumns),
                  if (_failed) ...[
                    const SizedBox(height: AppSpacing.s16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _editing
                            ? 'Client couldn’t be updated. Please try again.'
                            : 'Client couldn’t be created. Please try again.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
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
                        semanticsLabel: 'Saving client',
                      ),
                    )
                  : Text(_editing ? 'Save Changes' : 'Create Client'),
            ),
          ],
        ),
      );
    },
  );
}
