import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/supplier_source_repository.dart';
import '../../domain/supplier_source_package.dart';

class SupplierSourcesSection extends StatefulWidget {
  const SupplierSourcesSection({
    super.key,
    required this.tripId,
    required this.repository,
  });

  final String tripId;
  final SupplierSourceRepository repository;

  @override
  State<SupplierSourcesSection> createState() => _SupplierSourcesSectionState();
}

class _SupplierSourcesSectionState extends State<SupplierSourcesSection> {
  List<SupplierSourcePackage>? _packages;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SupplierSourcesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _packages = null;
      _failed = false;
    });
    try {
      final packages = List<SupplierSourcePackage>.of(
        await widget.repository.listPackagesForTrip(widget.tripId),
      );
      if (!mounted || request != _request) return;
      packages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _packages = List.unmodifiable(packages));
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Supplier Sources', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.s4),
        Text(
          'Original supplier quotations and itinerary files linked to this trip.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s20),
        if (_packages == null && !_failed)
          const _SourceState(
            key: ValueKey('supplier-sources-loading'),
            title: 'Loading supplier sources…',
            loading: true,
          )
        else if (_failed)
          _SourceState(
            key: const ValueKey('supplier-sources-error'),
            title: 'Supplier sources couldn’t be loaded.',
            action: OutlinedButton(
              onPressed: _load,
              child: const Text('Try again'),
            ),
          )
        else if (_packages!.isEmpty)
          const _SourceState(
            key: ValueKey('supplier-sources-empty'),
            title: 'No supplier sources yet',
            subtitle:
                'Supplier quotations and itinerary files will appear here once added.',
          )
        else
          _PackageList(packages: _packages!),
      ],
    );
  }
}

class _PackageList extends StatelessWidget {
  const _PackageList({required this.packages});

  final List<SupplierSourcePackage> packages;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final useTable =
          constraints.maxWidth >= AppLayout.workspaceSplitBreakpoint &&
          MediaQuery.textScalerOf(context).scale(16) <= 20;
      if (useTable) {
        return Card(
          clipBehavior: Clip.antiAlias,
          child: DataTable(
            horizontalMargin: AppSpacing.s20,
            columnSpacing: AppSpacing.s24,
            headingRowColor: const WidgetStatePropertyAll(AppColors.background),
            columns: const [
              DataColumn(
                label: Text('Supplier'),
                columnWidth: FlexColumnWidth(3),
              ),
              DataColumn(label: Text('Files'), columnWidth: FlexColumnWidth(1)),
              DataColumn(
                label: Text('Status'),
                columnWidth: FlexColumnWidth(1.4),
              ),
              DataColumn(
                label: Text('Added'),
                columnWidth: FlexColumnWidth(1.8),
              ),
            ],
            rows: [
              for (final package in packages)
                DataRow(
                  cells: [
                    DataCell(Text(_supplierName(package))),
                    DataCell(Text(_fileCount(package.fileIds.length))),
                    DataCell(_PackageStatus(status: package.status)),
                    DataCell(Text(_dateLabel(package.createdAt))),
                  ],
                ),
            ],
          ),
        );
      }
      return Column(
        children: [
          for (var index = 0; index < packages.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.s12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _supplierName(packages[index]),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Wrap(
                      spacing: AppSpacing.s16,
                      runSpacing: AppSpacing.s8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(_fileCount(packages[index].fileIds.length)),
                        _PackageStatus(status: packages[index].status),
                        Text(
                          'Added ${_dateLabel(packages[index].createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _PackageStatus extends StatelessWidget {
  const _PackageStatus({required this.status});

  final SupplierSourcePackageStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (status) {
      SupplierSourcePackageStatus.uploading => (
        'Uploading',
        AppColors.navyTint,
        AppColors.navy,
      ),
      SupplierSourcePackageStatus.uploaded => (
        'Uploaded',
        const Color(0xFFEDF3F1),
        const Color(0xFF315E52),
      ),
      SupplierSourcePackageStatus.failed => (
        'Failed',
        const Color(0xFFF7F0EA),
        const Color(0xFF7A4526),
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

class _SourceState extends StatelessWidget {
  const _SourceState({
    super.key,
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
                dimension: AppSpacing.s20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: AppSpacing.s12),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
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

String _supplierName(SupplierSourcePackage package) =>
    package.supplierNameSnapshot ?? 'Supplier not assigned';

String _fileCount(int count) => '$count ${count == 1 ? 'file' : 'files'}';

String _dateLabel(DateTime value) {
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
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
