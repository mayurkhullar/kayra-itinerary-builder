import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../../../users/data/user_profile_repository.dart';
import '../../../users/domain/kayra_user.dart';
import '../widgets/user_directory.dart';

/// Read-only content hosted inside the authenticated application shell.
class UserManagementPage extends StatefulWidget {
  const UserManagementPage({
    super.key,
    required this.currentUser,
    required this.repository,
  });

  final KayraUser currentUser;
  final UserProfileRepository repository;

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  List<KayraUser>? _users;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void didUpdateWidget(covariant UserManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.uid != widget.currentUser.uid ||
        oldWidget.currentUser.isActiveAdmin !=
            widget.currentUser.isActiveAdmin ||
        oldWidget.repository != widget.repository) {
      _loadUsers();
    }
  }

  Future<void> _loadUsers() async {
    final request = ++_request;
    setState(() {
      _users = null;
      _failed = false;
    });
    // Hidden navigation is not the page guard. Never fetch for a denied user.
    if (!widget.currentUser.isActiveAdmin) return;
    try {
      final users = await widget.repository.listUsers();
      if (!mounted ||
          request != _request ||
          !widget.currentUser.isActiveAdmin) {
        return;
      }
      setState(() => _users = users);
    } catch (_) {
      if (!mounted ||
          request != _request ||
          !widget.currentUser.isActiveAdmin) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final users = _users;
    final Widget content;
    if (!widget.currentUser.isActiveAdmin) {
      content = const _DirectoryState(
        message:
            'Access denied. User Management is available to active Admins only.',
      );
    } else if (_failed) {
      content = _DirectoryState(
        message: 'User data couldn’t be loaded.',
        onRetry: _loadUsers,
      );
    } else if (users == null) {
      content = const _DirectoryState(message: 'Loading users…', loading: true);
    } else if (users.isEmpty) {
      content = const _DirectoryState(message: 'No users found');
    } else {
      content = UserDirectory(
        users: users,
        currentUserId: widget.currentUser.uid,
      );
    }

    return SingleChildScrollView(
      child: KayraContentFrame(
        maxWidth: AppLayout.dashboardMaxContentWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text('User Management', style: textTheme.headlineMedium),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                'View Kayra team members, roles and account status.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              content,
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryState extends StatelessWidget {
  const _DirectoryState({
    required this.message,
    this.loading = false,
    this.onRetry,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s32),
        child: Semantics(
          liveRegion: true,
          child: Column(
            children: [
              if (loading) ...[
                const SizedBox.square(
                  dimension: AppSpacing.s24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: AppSpacing.s16),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.s16),
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
