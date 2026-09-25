import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../../../users/domain/kayra_user.dart';
import '../../data/supplier_repository.dart';
import '../../domain/kayra_supplier.dart';
import '../widgets/supplier_directory.dart';
import '../widgets/supplier_form.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({
    super.key,
    required this.currentUser,
    required this.repository,
  });
  final KayraUser currentUser;
  final SupplierRepository repository;

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  List<KayraSupplier>? _suppliers;
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
  void didUpdateWidget(covariant SuppliersPage oldWidget) {
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
      _suppliers = null;
      _failed = false;
    });
    if (!widget.currentUser.isActive) return;
    try {
      final suppliers = await widget.repository.listSuppliers();
      if (!mounted || request != _request) return;
      final sorted = List<KayraSupplier>.of(suppliers)
        ..sort((a, b) {
          if (a.status != b.status) {
            return a.status == SupplierStatus.active ? -1 : 1;
          }
          final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return name == 0 ? a.id.compareTo(b.id) : name;
        });
      setState(() => _suppliers = sorted);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  bool _canEdit(KayraSupplier? supplier) => widget.currentUser.isActive;

  Future<void> _openForm([KayraSupplier? supplier]) async {
    if (_formRoute != null || !_canEdit(supplier)) return;
    final request = _request;
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplierForm(
        supplier: supplier,
        onSave: (details) async {
          if (!mounted || request != _request || !_canEdit(supplier)) {
            throw StateError('Session changed');
          }
          if (supplier == null) {
            await widget.repository.createSupplier(
              details: details,
              currentUserUid: widget.currentUser.uid,
            );
          } else {
            await widget.repository.updateSupplier(
              supplierId: supplier.id,
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
    final suppliers = _suppliers;
    final query = _search.text.trim().toLowerCase();
    final filtered = suppliers
        ?.where(
          (supplier) => [
            supplier.name,
            for (final contact in supplier.contacts) ...[
              contact.name,
              contact.phone ?? '',
              contact.email ?? '',
            ],
            ...supplier.destinationCoverage,
            ...supplier.serviceCategories.map((category) => category.label),
          ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList();
    final Widget content;
    if (!widget.currentUser.isActive) {
      content = const _SupplierState(title: 'Supplier access is unavailable.');
    } else if (_failed) {
      content = _SupplierState(
        title: 'Supplier data couldn’t be loaded.',
        action: OutlinedButton(
          onPressed: _load,
          child: const Text('Try again'),
        ),
      );
    } else if (suppliers == null) {
      content = const _SupplierState(
        title: 'Loading suppliers…',
        loading: true,
      );
    } else if (suppliers.isEmpty) {
      content = _SupplierState(
        title: 'No suppliers yet',
        subtitle:
            'Add your first supplier to start building Kayra’s shared network.',
        action: OutlinedButton(
          onPressed: _openForm,
          child: const Text('New Supplier'),
        ),
      );
    } else if (filtered!.isEmpty) {
      content = const _SupplierState(
        title: 'No matching suppliers',
        subtitle: 'Try another supplier, contact, destination or service.',
      );
    } else {
      content = SupplierDirectory(suppliers: filtered, onOpen: _openForm);
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
                        child: Text(
                          'Suppliers',
                          style: textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        'Manage Kayra’s shared supplier network and destination coverage.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  );
                  final action = FilledButton(
                    onPressed: widget.currentUser.isActive ? _openForm : null,
                    child: const Text('New Supplier'),
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
                key: const ValueKey('supplier-search'),
                controller: _search,
                enabled: suppliers != null && widget.currentUser.isActive,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText:
                      'Search suppliers, contacts, destinations or services',
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

class _SupplierState extends StatelessWidget {
  const _SupplierState({
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
