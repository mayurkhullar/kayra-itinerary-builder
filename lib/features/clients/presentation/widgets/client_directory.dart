import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_user_avatar.dart';
import '../../domain/kayra_client.dart';

String formatClientUpdated(DateTime value) {
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

class ClientDirectory extends StatelessWidget {
  const ClientDirectory({
    super.key,
    required this.clients,
    required this.onOpen,
  });
  final List<KayraClient> clients;
  final ValueChanged<KayraClient> onOpen;

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
            columnSpacing: AppSpacing.s24,
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
            dataRowMinHeight: 72,
            dataRowMaxHeight: double.infinity,
            columns: [
              for (final entry in {
                'Client': 2.2,
                'Mobile': 1.5,
                'Email': 2.0,
                'City': 1.1,
                'Company': 1.4,
                'Updated': 1.8,
              }.entries)
                DataColumn(
                  label: Text(entry.key),
                  columnWidth: FlexColumnWidth(entry.value),
                ),
            ],
            rows: [
              for (final client in clients)
                DataRow(
                  key: ValueKey('client-row-${client.id}'),
                  mouseCursor: const WidgetStatePropertyAll(
                    SystemMouseCursors.click,
                  ),
                  onSelectChanged: (_) => onOpen(client),
                  cells: [
                    DataCell(
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s16,
                        ),
                        child: _ClientIdentity(client: client),
                      ),
                    ),
                    DataCell(Text(client.mobileNumber)),
                    DataCell(Text(client.email ?? '—')),
                    DataCell(Text(client.city ?? '—')),
                    DataCell(Text(client.company ?? '—')),
                    DataCell(Text(formatClientUpdated(client.updatedAt))),
                  ],
                ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < clients.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.s12),
            _ClientListRow(
              client: clients[index],
              onOpen: () => onOpen(clients[index]),
            ),
          ],
        ],
      );
    },
  );
}

class _ClientListRow extends StatelessWidget {
  const _ClientListRow({required this.client, required this.onOpen});
  final KayraClient client;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('client-row-${client.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _ClientIdentity(client: client)),
                const SizedBox(width: AppSpacing.s8),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(client.mobileNumber),
            if (client.email != null) Text(client.email!),
            if (client.city != null || client.company != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                [client.city, client.company].whereType<String>().join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Updated ${formatClientUpdated(client.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ClientIdentity extends StatelessWidget {
  const _ClientIdentity({required this.client});
  final KayraClient client;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      KayraUserAvatar(
        photoURL: null,
        displayName: client.displayName,
        email: client.email,
      ),
      const SizedBox(width: AppSpacing.s12),
      Expanded(
        child: Text(
          client.displayName,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    ],
  );
}
