import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../users/domain/kayra_user.dart';

class ChangeRoleDialog extends StatefulWidget {
  const ChangeRoleDialog({super.key, required this.user, required this.onSave});

  final KayraUser user;
  final Future<void> Function(KayraUserRole role) onSave;

  @override
  State<ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<ChangeRoleDialog> {
  late KayraUserRole _role = widget.user.role;
  bool _saving = false;
  bool _failed = false;

  Future<void> _save() async {
    if (_saving || _role == widget.user.role) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave(_role);
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
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r12),
          side: const BorderSide(color: AppColors.border),
        ),
        insetPadding: const EdgeInsets.all(AppSpacing.s20),
        scrollable: true,
        title: const Text('Change role'),
        content: SizedBox(
          width: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('User', style: textTheme.bodySmall),
              Text(widget.user.displayLabel, style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.s16),
              Text(
                'Current role: ${widget.user.role.label}',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.s20),
              DropdownButtonFormField<KayraUserRole>(
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'New role'),
                items: [
                  for (final role in KayraUserRole.values)
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: _saving
                    ? null
                    : (role) {
                        if (role != null) {
                          setState(() {
                            _role = role;
                            _failed = false;
                          });
                        }
                      },
              ),
              if (_role != widget.user.role) ...[
                const SizedBox(height: AppSpacing.s16),
                Text(
                  _role == KayraUserRole.admin
                      ? 'Admins can view and manage Kayra users.'
                      : 'This user will lose Admin access.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (_failed) ...[
                const SizedBox(height: AppSpacing.s16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Role couldn’t be updated. Please try again.',
                    style: textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving || _role == widget.user.role ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: AppSpacing.s20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: 'Updating role',
                    ),
                  )
                : const Text('Update role'),
          ),
        ],
      ),
    );
  }
}
