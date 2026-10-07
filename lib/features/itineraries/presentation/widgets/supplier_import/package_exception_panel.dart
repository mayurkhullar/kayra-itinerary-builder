import 'package:flutter/material.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import '../../controllers/supplier_import_review_state.dart';
import 'package_review_data.dart';
import 'review_components.dart';
import 'review_exclusion_note.dart';

class PackageExceptionPanel extends StatefulWidget {
  const PackageExceptionPanel({
    super.key,
    required this.data,
    required this.onSet,
    required this.onRemove,
  });
  final PackageReviewData data;
  final ValueChanged<SupplierImportDecisionPayload> onSet;
  final ValueChanged<String> onRemove;
  @override
  State<PackageExceptionPanel> createState() => _PackageExceptionPanelState();
}

class _PackageExceptionPanelState extends State<PackageExceptionPanel> {
  final _form = GlobalKey<FormState>();
  final _order = TextEditingController();
  final _note = TextEditingController();
  bool _changing = false;
  String? _action;
  SupplierImportDayReference? _day;
  SupplierImportServiceReference? _service;
  SupplierImportPackageDestination? _destination;
  SupplierImportExclusionReason? _reason;
  // Keep target objects stable while local form fields rebuild.
  late List<(SupplierImportDayReference, String)> _days;
  List<(SupplierImportServiceReference, String)> _services = [];
  @override
  void initState() {
    super.initState();
    _days = widget.data.days;
  }

  @override
  void didUpdateWidget(covariant PackageExceptionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.review.state != widget.data.review.state) {
      _changing = false;
      _action = null;
      _day = null;
      _service = null;
      _destination = null;
      _reason = null;
      _days = widget.data.days;
      _services = [];
      _order.clear();
      _note.clear();
    }
  }

  @override
  void dispose() {
    _order.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit(String action) {
    if (!widget.data.review.canReview) return;
    if (action != 'retain' && !_form.currentState!.validate()) return;
    widget.onSet(
      widget.data.choose(
        action,
        day: _day,
        order: int.tryParse(_order.text),
        service: _service,
        destination: _destination,
        reason: _reason,
        note: _reason == SupplierImportExclusionReason.other
            ? _note.text.trim()
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final decision = data.decision;
    final attention = data.needsAttention;
    if (!attention && decision == null && !data.isPending) {
      return const SizedBox.shrink();
    }
    final editable = data.review.canReview;
    final accommodation =
        data.fact is SupplierExtractionPackageAccommodationFact;
    final status = switch (decision) {
      SupplierImportPackageAccommodationDecision(:final disposition) =>
        disposition.value,
      SupplierImportPackageStatementDecision(:final disposition) =>
        disposition.value,
      SupplierImportPackageConditionDecision(:final disposition) =>
        disposition.value,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (attention)
            Text(
              'Needs attention',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          if (data.review.state is SupplierImportReviewSaving)
            const Text('Saving review…'),
          if (status != null)
            Text(switch (status) {
              'exclude' => 'Excluded from import',
              'map_to_service' || 'map_to_day_service' => 'Mapped',
              _ => 'Kept as package content',
            }, style: Theme.of(context).textTheme.bodySmall),
          if (editable && decision != null && !_changing)
            Wrap(
              spacing: AppSpacing.s8,
              children: [
                TextButton(
                  onPressed: () => setState(() => _changing = true),
                  child: const Text('Change'),
                ),
                TextButton(
                  onPressed: () => widget.onRemove(data.fact.id),
                  child: const Text('Revert decision'),
                ),
              ],
            ),
          if (editable && ((attention && decision == null) || _changing)) ...[
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                OutlinedButton(
                  onPressed: () => _submit('retain'),
                  child: Text(
                    accommodation
                        ? 'Keep as package stay'
                        : 'Keep at package level',
                  ),
                ),
                if (accommodation
                    ? _days.isNotEmpty
                    : data.destinations.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _action = 'map'),
                    child: Text(
                      accommodation ? 'Map to day' : 'Map to service',
                    ),
                  ),
                TextButton(
                  onPressed: () => setState(() => _action = 'exclude'),
                  child: const Text('Exclude'),
                ),
                if (_changing || _action != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _changing = false;
                      _action = null;
                    }),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
            if (_action != null)
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.s12),
                    if (_action == 'map' && accommodation) ...[
                      DropdownButtonFormField<SupplierImportDayReference>(
                        key: const ValueKey('package-map-day'),
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(labelText: 'Day'),
                        items: [
                          for (final (reference, label) in _days)
                            DropdownMenuItem(
                              value: reference,
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => _day = v,
                        validator: (v) =>
                            v == null ? 'Choose an existing day.' : null,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      TextFormField(
                        key: const ValueKey('package-map-order'),
                        controller: _order,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Service order within day',
                        ),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 1 || n > 9007199254740991
                              ? 'Enter a positive whole number.'
                              : null;
                        },
                      ),
                    ],
                    if (_action == 'map' && !accommodation) ...[
                      DropdownButtonFormField<SupplierImportPackageDestination>(
                        key: const ValueKey('package-map-destination'),
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(
                          labelText: 'Service field',
                        ),
                        items: [
                          for (final d in data.destinations)
                            DropdownMenuItem(
                              value: d,
                              child: Text(reviewLabel(d.value)),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _destination = v;
                          _service = null;
                          _services = v == null ? [] : data.services(v);
                        }),
                        validator: (v) =>
                            v == null ? 'Choose a service field.' : null,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      DropdownButtonFormField<SupplierImportServiceReference>(
                        key: ValueKey(
                          'package-map-service-${_destination?.value}',
                        ),
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(labelText: 'Service'),
                        items: [
                          for (final (reference, label) in _services)
                            DropdownMenuItem(
                              value: reference,
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => _service = v,
                        validator: (v) =>
                            v == null ? 'Choose an existing service.' : null,
                      ),
                    ],
                    if (_action == 'exclude') ...[
                      DropdownButtonFormField<SupplierImportExclusionReason>(
                        key: const ValueKey('package-exclusion-reason'),
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(
                          labelText: 'Reason for exclusion',
                        ),
                        items: [
                          for (final r in SupplierImportExclusionReason.values)
                            DropdownMenuItem(
                              value: r,
                              child: Text(reviewLabel(r.value)),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _reason = v;
                          _note.clear();
                        }),
                        validator: (v) => v == null ? 'Choose a reason.' : null,
                      ),
                      if (_reason == SupplierImportExclusionReason.other)
                        TextFormField(
                          controller: _note,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Explanation',
                            errorMaxLines: 3,
                          ),
                          validator: (_) => validateReviewExclusionNote(
                            _note.text.trim(),
                            _reason,
                            subject: 'package item',
                          ),
                        ),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _submit(_action!),
                        child: Text(
                          _action == 'map' ? 'Save mapping' : 'Save exclusion',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
