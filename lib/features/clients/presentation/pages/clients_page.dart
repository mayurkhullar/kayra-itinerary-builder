import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../../../users/domain/kayra_user.dart';
import '../../data/client_repository.dart';
import '../../domain/kayra_client.dart';
import '../widgets/client_directory.dart';
import '../widgets/client_form.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({
    super.key,
    required this.currentUser,
    required this.repository,
  });
  final KayraUser currentUser;
  final ClientRepository repository;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  List<KayraClient>? _clients;
  final _search = TextEditingController();
  bool _failed = false;
  int _request = 0;
  DialogRoute<bool>? _formRoute;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClientsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.uid != widget.currentUser.uid ||
        oldWidget.currentUser.role != widget.currentUser.role ||
        oldWidget.currentUser.status != widget.currentUser.status ||
        oldWidget.repository != widget.repository) {
      _dismissForm();
      _search.clear();
      _load();
    }
  }

  void _dismissForm() {
    final route = _formRoute;
    _formRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    });
  }

  @override
  void dispose() {
    _dismissForm();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _clients = null;
      _failed = false;
    });
    if (!widget.currentUser.isActive) return;
    try {
      final clients = widget.currentUser.isActiveAdmin
          ? await widget.repository.listAllClientsForAdmin()
          : await widget.repository.listOwnedClients(widget.currentUser.uid);
      if (!mounted || request != _request) return;
      final sorted = List<KayraClient>.of(clients)
        ..sort((a, b) {
          final name = a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
          return name == 0 ? a.id.compareTo(b.id) : name;
        });
      setState(() => _clients = sorted);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  bool _canEdit(KayraClient? client) =>
      widget.currentUser.isActive &&
      (client == null ||
          widget.currentUser.isActiveAdmin ||
          client.createdByUid == widget.currentUser.uid);

  Future<void> _openForm([KayraClient? client]) async {
    if (_formRoute != null || !_canEdit(client)) return;
    final request = _request;
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClientForm(
        client: client,
        onSave: (details) async {
          if (!mounted || request != _request || !_canEdit(client)) {
            throw StateError('Session changed');
          }
          if (client == null) {
            await widget.repository.createClient(
              details: details,
              currentUserUid: widget.currentUser.uid,
            );
          } else {
            await widget.repository.updateClient(
              clientId: client.id,
              details: details,
            );
          }
        },
      ),
    );
    _formRoute = route;
    final saved = await Navigator.of(context).push(route);
    if (_formRoute == route) _formRoute = null;
    if (saved == true && mounted && request == _request) {
      _search.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final clients = _clients;
    final query = _search.text.trim().toLowerCase();
    final filtered = clients
        ?.where(
          (client) => [
            client.firstName,
            client.lastName,
            client.displayName,
            client.mobileNumber,
            client.email ?? '',
            client.company ?? '',
          ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList();
    final Widget content;
    if (!widget.currentUser.isActive) {
      content = const _ClientState(title: 'Client access is unavailable.');
    } else if (_failed) {
      content = _ClientState(
        title: 'Client data couldn’t be loaded.',
        action: OutlinedButton(
          onPressed: _load,
          child: const Text('Try again'),
        ),
      );
    } else if (clients == null) {
      content = const _ClientState(title: 'Loading clients…', loading: true);
    } else if (clients.isEmpty) {
      content = _ClientState(
        title: 'No clients yet',
        subtitle: 'Create your first client to start building journeys.',
        action: OutlinedButton(
          onPressed: _openForm,
          child: const Text('New Client'),
        ),
      );
    } else if (filtered!.isEmpty) {
      content = const _ClientState(
        title: 'No matching clients',
        subtitle: 'Try another name, mobile, email or company.',
      );
    } else {
      content = ClientDirectory(clients: filtered, onOpen: _openForm);
    }
    return SingleChildScrollView(
      child: KayraContentFrame(
        maxWidth: AppLayout.dashboardMaxContentWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Clients', style: textTheme.headlineMedium),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        widget.currentUser.isActiveAdmin
                            ? 'Manage Kayra clients across the team and start new journeys from an existing profile.'
                            : 'Manage the clients you work with and start new journeys from an existing profile.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  );
                  final action = FilledButton(
                    onPressed: widget.currentUser.isActive ? _openForm : null,
                    child: const Text('New Client'),
                  );
                  if (constraints.maxWidth < 700 ||
                      MediaQuery.textScalerOf(context).scale(16) > 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        const SizedBox(height: AppSpacing.s20),
                        action,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: AppSpacing.s24),
                      action,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.s24),
              TextField(
                controller: _search,
                enabled: clients != null && widget.currentUser.isActive,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search clients by name, mobile, email or company',
                  hintMaxLines: 2,
                  prefixIcon: Icon(Icons.search_rounded),
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

class _ClientState extends StatelessWidget {
  const _ClientState({
    required this.title,
    this.subtitle,
    this.action,
    this.loading = false,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) => Card(
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
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s16),
              action!,
            ],
          ],
        ),
      ),
    ),
  );
}
