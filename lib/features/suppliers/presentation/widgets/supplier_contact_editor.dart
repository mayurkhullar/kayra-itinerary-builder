import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/kayra_supplier.dart';

/// Controllers belong to the form, so adding/removing rows preserves other edits.
class SupplierContactDraft {
  SupplierContactDraft({SupplierContact? contact, bool primary = false})
    : name = TextEditingController(text: contact?.name),
      phone = TextEditingController(text: contact?.phone),
      email = TextEditingController(text: contact?.email),
      isPrimary = contact?.isPrimary ?? primary;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  bool isPrimary;

  SupplierContact toContact() => SupplierContact(
    name: name.text,
    phone: phone.text,
    email: email.text,
    isPrimary: isPrimary,
  );
  String? validate() {
    try {
      toContact();
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
  }
}

class SupplierContactEditor extends StatelessWidget {
  const SupplierContactEditor({
    super.key,
    required this.draft,
    required this.index,
    required this.enabled,
    required this.onRemove,
  });
  final SupplierContactDraft draft;
  final int index;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => FormField<void>(
    validator: (_) => draft.validate(),
    autovalidateMode: AutovalidateMode.onUserInteraction,
    builder: (state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Contact ${index + 1}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              key: ValueKey('supplier-remove-$index'),
              tooltip: 'Remove contact',
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            Widget field(
              String label,
              TextEditingController controller,
              TextInputType type,
            ) => TextField(
              key: ValueKey('supplier-contact-$index-$label'),
              controller: controller,
              enabled: enabled,
              decoration: InputDecoration(
                labelText: label == 'Name' ? 'Name *' : label,
              ),
              keyboardType: type,
              textCapitalization: label == 'Name'
                  ? TextCapitalization.words
                  : TextCapitalization.none,
              textInputAction: TextInputAction.next,
              onChanged: (_) => state.didChange(null),
            );
            final name = field('Name', draft.name, TextInputType.name);
            final phone = field('Phone', draft.phone, TextInputType.phone);
            return Column(
              children: [
                if (constraints.maxWidth >= 500 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 20)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: AppSpacing.s16),
                      Expanded(child: phone),
                    ],
                  )
                else ...[
                  name,
                  const SizedBox(height: AppSpacing.s16),
                  phone,
                ],
                const SizedBox(height: AppSpacing.s16),
                field('Email', draft.email, TextInputType.emailAddress),
              ],
            );
          },
        ),
        RadioListTile<SupplierContactDraft>(
          key: ValueKey('supplier-primary-$index'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Primary contact'),
          value: draft,
          enabled: enabled,
        ),
        if (state.hasError)
          Semantics(
            liveRegion: true,
            child: Text(
              state.errorText!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    ),
  );
}
