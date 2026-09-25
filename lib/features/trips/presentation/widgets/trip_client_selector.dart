import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../clients/domain/kayra_client.dart';

class TripClientSelector extends StatefulWidget {
  const TripClientSelector({
    super.key,
    required this.clients,
    required this.enabled,
    required this.onChanged,
  });
  final List<KayraClient> clients;
  final bool enabled;
  final ValueChanged<KayraClient?> onChanged;
  @override
  State<TripClientSelector> createState() => _TripClientSelectorState();
}

class _TripClientSelectorState extends State<TripClientSelector> {
  final _search = TextEditingController();
  final _selectorFocus = FocusNode();
  final _searchFocus = FocusNode();
  final _changeFocus = FocusNode();
  @override
  void dispose() {
    _search.dispose();
    _selectorFocus.dispose();
    _searchFocus.dispose();
    _changeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<KayraClient>(
    validator: (value) => value == null ? 'Select a Client.' : null,
    builder: (field) {
      final query = _search.text.trim().toLowerCase();
      final matches = widget.clients
          .where(
            (client) => [
              client.displayName,
              client.mobileNumber,
              client.email ?? '',
              client.company ?? '',
            ].any((value) => value.toLowerCase().contains(query)),
          )
          .toList();
      return TapRegion(
        onTapOutside: (_) => _selectorFocus.unfocus(),
        child: Focus(
          focusNode: _selectorFocus,
          skipTraversal: true,
          onFocusChange: (_) => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (field.value != null)
                InputDecorator(
                  key: const ValueKey('trip-selected-client'),
                  decoration: InputDecoration(
                    labelText: 'Client *',
                    errorText: field.errorText,
                    filled: true,
                    fillColor: AppColors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s12,
                      vertical: AppSpacing.s8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _identity(context, field.value!)),
                      const SizedBox(width: AppSpacing.s8),
                      TextButton(
                        focusNode: _changeFocus,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(
                            AppSpacing.s64,
                            AppSpacing.s48,
                          ),
                        ),
                        onPressed: widget.enabled
                            ? () {
                                field.didChange(null);
                                _search.clear();
                                widget.onChanged(null);
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) _searchFocus.requestFocus();
                                });
                              }
                            : null,
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                )
              else ...[
                TextField(
                  key: const ValueKey('trip-client-search'),
                  controller: _search,
                  focusNode: _searchFocus,
                  // The surrounding region includes results, so pointer selection
                  // does not dismiss them before the result receives its tap.
                  onTapOutside: (_) {},
                  enabled: widget.enabled,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Client *',
                    hintText: 'Search name, mobile, email or company',
                    hintMaxLines: 2,
                    errorText: field.errorText,
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
                if (_selectorFocus.hasFocus) ...[
                  const SizedBox(height: AppSpacing.s8),
                  if (matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.s12),
                      child: Text('No matching clients'),
                    )
                  else
                    SizedBox(
                      height: matches.length == 1 ? 92 : 172,
                      width: double.maxFinite,
                      child: ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final client = matches[index];
                          return ListTile(
                            key: ValueKey('select-client-${client.id}'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s12,
                              vertical: AppSpacing.s4,
                            ),
                            title: Text(client.displayName),
                            subtitle: Text(
                              [
                                client.mobileNumber,
                                if (client.company != null) client.company!,
                              ].join(' · '),
                            ),
                            onTap: widget.enabled
                                ? () {
                                    field.didChange(client);
                                    widget.onChanged(client);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted) {
                                            _changeFocus.requestFocus();
                                          }
                                        });
                                  }
                                : null,
                          );
                        },
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
  Widget _identity(BuildContext context, KayraClient client) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(client.displayName, style: Theme.of(context).textTheme.titleSmall),
      Text(
        [
          client.mobileNumber,
          if (client.company != null) client.company!,
        ].join(' · '),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}
