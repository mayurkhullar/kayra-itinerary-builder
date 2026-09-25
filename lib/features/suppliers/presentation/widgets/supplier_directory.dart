import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/kayra_supplier.dart';

String formatSupplierUpdated(DateTime value) {
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
  return '${date.day} ${months[date.month - 1]} ${date.year}, $hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'}';
}

class SupplierDirectory extends StatelessWidget {
  const SupplierDirectory({
    super.key,
    required this.suppliers,
    required this.onOpen,
  });
  final List<KayraSupplier> suppliers;
  final ValueChanged<KayraSupplier> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context).textTheme;
      if (constraints.maxWidth >= 1100 &&
          MediaQuery.textScalerOf(context).scale(16) <= 20) {
        return Card(
          clipBehavior: Clip.antiAlias,
          child: DataTable(
            showCheckboxColumn: false,
            horizontalMargin: AppSpacing.s16,
            columnSpacing: AppSpacing.s20,
            headingRowColor: const WidgetStatePropertyAll(AppColors.background),
            dataRowColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? AppColors.navyTint
                  : null,
            ),
            headingTextStyle: theme.titleSmall,
            dataTextStyle: theme.bodyMedium,
            dataRowMinHeight: 84,
            dataRowMaxHeight: 88,
            columns: [
              for (final entry in {
                'Supplier': 2.0,
                'Primary Contact': 2.1,
                'Destinations': 2.0,
                'Services': 1.7,
                'Status': 1.0,
                'Updated': 1.7,
              }.entries)
                DataColumn(
                  label: Text(entry.key),
                  columnWidth: FlexColumnWidth(entry.value),
                ),
            ],
            rows: [
              for (final supplier in suppliers)
                DataRow(
                  key: ValueKey('supplier-row-${supplier.id}'),
                  mouseCursor: const WidgetStatePropertyAll(
                    SystemMouseCursors.click,
                  ),
                  onSelectChanged: (_) => onOpen(supplier),
                  cells: [
                    DataCell(
                      Text(
                        supplier.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleSmall,
                      ),
                    ),
                    DataCell(_PrimaryContact(supplier: supplier)),
                    DataCell(
                      Text(
                        _destinations(supplier),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DataCell(_Services(supplier: supplier)),
                    DataCell(_Status(supplier: supplier)),
                    DataCell(
                      Text(
                        formatSupplierUpdated(supplier.updatedAt),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final supplier in suppliers)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('supplier-row-${supplier.id}'),
                  onTap: () => onOpen(supplier),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                supplier.name,
                                style: theme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        _PrimaryContact(supplier: supplier),
                        const SizedBox(height: AppSpacing.s12),
                        Text(_destinations(supplier), style: theme.bodyMedium),
                        const SizedBox(height: AppSpacing.s8),
                        _Services(supplier: supplier),
                        const SizedBox(height: AppSpacing.s12),
                        _Status(supplier: supplier),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

String _destinations(KayraSupplier supplier) {
  final values = supplier.destinationCoverage;
  if (values.isEmpty) return '—';
  return [
    ...values.take(3),
    if (values.length > 3) '+${values.length - 3} more',
  ].join(' · ');
}

class _PrimaryContact extends StatelessWidget {
  const _PrimaryContact({required this.supplier});
  final KayraSupplier supplier;
  @override
  Widget build(BuildContext context) {
    if (supplier.contacts.isEmpty) return const Text('—');
    final contact = supplier.contacts.firstWhere(
      (c) => c.isPrimary,
      orElse: () => supplier.contacts.first,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(contact.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          contact.phone ?? contact.email ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Services extends StatelessWidget {
  const _Services({required this.supplier});
  final KayraSupplier supplier;
  @override
  Widget build(BuildContext context) {
    if (supplier.serviceCategories.isEmpty) return const Text('—');
    return Wrap(
      spacing: AppSpacing.s4,
      runSpacing: AppSpacing.s4,
      children: [
        for (final category in supplier.serviceCategories.take(2))
          DecoratedBox(
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
                category.label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        if (supplier.serviceCategories.length > 2)
          Text(
            '+${supplier.serviceCategories.length - 2} more',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.supplier});
  final KayraSupplier supplier;
  @override
  Widget build(BuildContext context) => Text(
    supplier.status == SupplierStatus.active ? 'Active' : 'Inactive',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: supplier.status == SupplierStatus.active
          ? AppColors.navy
          : AppColors.textSecondary,
    ),
  );
}
