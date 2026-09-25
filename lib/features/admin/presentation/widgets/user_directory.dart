import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_user_avatar.dart';
import '../../../users/domain/kayra_user.dart';

String formatLastLogin(DateTime? value) {
  if (value == null) return '—';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = value.toLocal();
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${months[date.month - 1]} ${date.year}, $hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
}

class UserDirectory extends StatelessWidget {
  const UserDirectory({
    super.key,
    required this.users,
    required this.currentUserId,
    required this.onChangeRole,
  });

  final List<KayraUser> users;
  final String currentUserId;
  final ValueChanged<KayraUser> onChangeRole;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use structured rows until the columns have comfortable space.
        final table =
            constraints.maxWidth >= 1100 &&
            MediaQuery.textScalerOf(context).scale(16) <= 20;
        if (table) {
          return _UserTable(
            users: users,
            currentUserId: currentUserId,
            onChangeRole: onChangeRole,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < users.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.s12),
              _UserListRow(
                user: users[index],
                isCurrentUser: users[index].uid == currentUserId,
                onChangeRole: onChangeRole,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _UserTable extends StatelessWidget {
  const _UserTable({
    required this.users,
    required this.currentUserId,
    required this.onChangeRole,
  });

  final List<KayraUser> users;
  final String currentUserId;
  final ValueChanged<KayraUser> onChangeRole;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s16,
      ),
      child: child,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(3),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.2),
          4: FlexColumnWidth(2.1),
          5: FixedColumnWidth(144),
        },
        border: const TableBorder(
          horizontalInside: BorderSide(color: AppColors.border),
        ),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.background),
            children: [
              for (final title in [
                'User',
                'Email',
                'Role',
                'Status',
                'Last Login',
                'Actions',
              ])
                cell(
                  Semantics(
                    header: true,
                    child: Text(title, style: textTheme.titleSmall),
                  ),
                ),
            ],
          ),
          for (final user in users)
            TableRow(
              children: [
                cell(
                  _UserIdentity(
                    user: user,
                    isCurrentUser: user.uid == currentUserId,
                  ),
                ),
                cell(
                  Text(user.email.toLowerCase(), style: textTheme.bodyMedium),
                ),
                cell(
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _RoleBadge(user: user),
                  ),
                ),
                cell(_UserStatus(user: user)),
                cell(
                  Text(
                    formatLastLogin(user.lastLoginAt),
                    style: textTheme.bodyMedium,
                  ),
                ),
                cell(
                  user.uid == currentUserId
                      ? const SizedBox.shrink()
                      : _ChangeRoleAction(
                          user: user,
                          onChangeRole: onChangeRole,
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _UserListRow extends StatelessWidget {
  const _UserListRow({
    required this.user,
    required this.isCurrentUser,
    required this.onChangeRole,
  });

  final KayraUser user;
  final bool isCurrentUser;
  final ValueChanged<KayraUser> onChangeRole;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _UserIdentity(
              user: user,
              isCurrentUser: isCurrentUser,
              showEmail: true,
            ),
            const SizedBox(height: AppSpacing.s16),
            Wrap(
              spacing: AppSpacing.s16,
              runSpacing: AppSpacing.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _RoleBadge(user: user),
                _UserStatus(user: user),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Last login · ${formatLastLogin(user.lastLoginAt)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            if (!isCurrentUser) ...[
              const SizedBox(height: AppSpacing.s8),
              _ChangeRoleAction(user: user, onChangeRole: onChangeRole),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChangeRoleAction extends StatelessWidget {
  const _ChangeRoleAction({required this.user, required this.onChangeRole});

  final KayraUser user;
  final ValueChanged<KayraUser> onChangeRole;

  @override
  Widget build(BuildContext context) => TextButton(
    key: ValueKey('change-role-${user.uid}'),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
    ),
    onPressed: () => onChangeRole(user),
    child: const Text('Change role'),
  );
}

class _UserIdentity extends StatelessWidget {
  const _UserIdentity({
    required this.user,
    required this.isCurrentUser,
    this.showEmail = false,
  });

  final KayraUser user;
  final bool isCurrentUser;
  final bool showEmail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        KayraUserAvatar(
          photoURL: user.photoUrl,
          displayName: user.displayName,
          email: user.email,
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(user.displayLabel, style: textTheme.titleSmall),
                  if (isCurrentUser) Text('You', style: textTheme.bodySmall),
                ],
              ),
              if (showEmail) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(
                  user.email.toLowerCase(),
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.user});
  final KayraUser user;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.navyTint,
      borderRadius: BorderRadius.circular(AppRadius.r8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      child: Text(
        user.role.label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.navy),
      ),
    ),
  );
}

class _UserStatus extends StatelessWidget {
  const _UserStatus({required this.user});
  final KayraUser user;

  @override
  Widget build(BuildContext context) => Text(
    user.isActive ? 'Active' : 'Inactive',
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: user.isActive ? AppColors.navy : AppColors.textSecondary,
    ),
  );
}
