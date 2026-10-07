import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import '../../../domain/supplier_import_resolution_overrides.dart';
import '../../controllers/supplier_import_review_state.dart';
import 'review_components.dart';
import 'review_exclusion_note.dart';
import 'staged_service_review_data.dart';

/// Disposition only. Source facts and existing corrections remain untouched.
class AncillaryDecisionPanel extends StatefulWidget {
  const AncillaryDecisionPanel({
    super.key,
    required this.fact,
    required this.review,
    required this.onSet,
    required this.onRemove,
  });
  final SupplierExtractionFact fact;
  final StagedServiceReviewData review;
  final ValueChanged<SupplierImportDecisionPayload> onSet;
  final ValueChanged<String> onRemove;
  @override
  State<AncillaryDecisionPanel> createState() => _AncillaryDecisionPanelState();
}

class _AncillaryDecisionPanelState extends State<AncillaryDecisionPanel> {
  bool _changing = false;
  bool _excluding = false;
  SupplierImportExclusionReason? _reason;
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();

  SupplierImportDecisionPayload? get _decision => widget
      .review
      .resolution
      ?.decisions
      .where(
        (item) =>
            item.payload.targetEntityId == widget.fact.id &&
            item.payload.decisionKind == widget.fact.factKind.value,
      )
      .firstOrNull
      ?.payload;

  @override
  void didUpdateWidget(covariant AncillaryDecisionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.review.state != widget.review.state) {
      _changing = false;
      _excluding = false;
      _reason = null;
      _note.clear();
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save({required bool exclude}) {
    if (!widget.review.canReview) return;
    if (exclude && !_form.currentState!.validate()) return;
    final old = _decision;
    final note = _note.text.trim();
    final SupplierImportDecisionPayload value;
    if (widget.fact is SupplierExtractionFlightFact) {
      value = SupplierImportFlightDecision(
        targetEntityId: widget.fact.id,
        disposition: exclude
            ? SupplierImportFlightDisposition.exclude
            : SupplierImportFlightDisposition.handledSeparately,
        destinationId: null,
        overrides: old is SupplierImportFlightDecision
            ? old.overrides
            : const SupplierImportFlightOverrides(),
        exclusionReason: exclude ? _reason : null,
        exclusionNote: exclude && note.isNotEmpty ? note : null,
      );
    } else if (widget.fact is SupplierExtractionVisaFact) {
      value = SupplierImportVisaDecision(
        targetEntityId: widget.fact.id,
        disposition: exclude
            ? SupplierImportVisaDecisionDisposition.exclude
            : SupplierImportVisaDecisionDisposition.handledSeparately,
        destinationId: null,
        overrides: old is SupplierImportVisaDecision
            ? old.overrides
            : const SupplierImportVisaOverrides(),
        exclusionReason: exclude ? _reason : null,
        exclusionNote: exclude && note.isNotEmpty ? note : null,
      );
    } else {
      return;
    }
    widget.onSet(value);
  }

  @override
  Widget build(BuildContext context) {
    final decision = _decision;
    final editable = widget.review.canReview;
    final saving = widget.review.state is SupplierImportReviewSaving;
    final disposition = switch (decision) {
      SupplierImportFlightDecision(:final disposition) => disposition.value,
      SupplierImportVisaDecision(:final disposition) => disposition.value,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              saving
                  ? 'Saving review…'
                  : switch (disposition) {
                      'handled_separately' => 'Handled separately',
                      'exclude' => 'Excluded from itinerary import',
                      'route_to_flight_workflow' => 'Routed to flight workflow',
                      'route_to_visa_workflow' => 'Routed to visa workflow',
                      _ =>
                        'Choose how to handle this item outside the itinerary.',
                    },
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (editable && decision != null && !_changing)
            Wrap(
              spacing: AppSpacing.s8,
              children: [
                TextButton(
                  onPressed: () => setState(() => _changing = true),
                  child: const Text('Change'),
                ),
                TextButton(
                  onPressed: () => widget.onRemove(widget.fact.id),
                  child: const Text('Revert decision'),
                ),
              ],
            ),
          if (editable && (decision == null || _changing)) ...[
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                OutlinedButton(
                  onPressed: () => _save(exclude: false),
                  child: const Text('Handle separately'),
                ),
                TextButton(
                  onPressed: () => setState(() => _excluding = !_excluding),
                  child: const Text('Exclude'),
                ),
                if (_changing)
                  TextButton(
                    onPressed: () => setState(() {
                      _changing = false;
                      _excluding = false;
                    }),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
            if (_excluding)
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.s12),
                    DropdownButtonFormField<SupplierImportExclusionReason>(
                      key: ValueKey('ancillary-reason-${widget.fact.id}'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Reason for exclusion',
                      ),
                      items: [
                        for (final reason
                            in SupplierImportExclusionReason.values)
                          DropdownMenuItem(
                            value: reason,
                            child: Text(reviewLabel(reason.value)),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        _reason = value;
                        _note.clear();
                      }),
                      validator: (value) =>
                          value == null ? 'Choose a reason.' : null,
                    ),
                    if (_reason == SupplierImportExclusionReason.other) ...[
                      const SizedBox(height: AppSpacing.s12),
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
                          subject: 'item',
                        ),
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _save(exclude: true),
                        child: const Text('Save exclusion'),
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
