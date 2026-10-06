import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_fact.dart';
import '../../../domain/supplier_extraction_values.dart';
import '../../../domain/supplier_import_resolution_decision.dart';
import 'review_components.dart';
import 'staged_service_correction.dart';
import 'staged_service_review_data.dart';

class StagedServiceCorrections extends StatelessWidget {
  const StagedServiceCorrections({
    super.key,
    required this.service,
    required this.review,
    this.onCorrect,
  });
  final SupplierExtractionServiceFact service;
  final StagedServiceReviewData review;
  final ValueChanged<StagedServiceCorrectionField>? onCorrect;

  @override
  Widget build(BuildContext context) {
    final decision = review.decisionFor(service.id);
    final fields = StagedServiceCorrectionField.values
        .where(
          (field) =>
              (onCorrect != null && review.canCorrectField(service, field)) ||
              field.overrideIn(decision?.overrides) != null,
        )
        .toList();
    if (fields.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: ValueKey('service-corrections-${service.id}'),
      padding: const EdgeInsets.only(top: AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: AppSpacing.s12),
          Text(
            onCorrect == null ? 'Consultant corrections' : 'Corrections',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (decision?.disposition == SupplierImportRetainDisposition.exclude)
            const Text(
              'Corrections are kept while this service is excluded. Retain or assign the service to edit them.',
            ),
          for (final (index, field) in fields.indexed) ...[
            if (onCorrect != null &&
                (index == 0 || field.branch != fields[index - 1].branch))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s16),
                child: Text(
                  field.branch == null
                      ? 'Common fields'
                      : '${reviewLabel(field.branch!)} details',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    field.label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  ReviewFields([
                    if (onCorrect != null)
                      (
                        'Supplier source',
                        serviceCorrectionValueLabel(field.sourceValue(service)),
                      ),
                    (
                      'Consultant correction',
                      serviceCorrectionLabel(
                        field.overrideIn(decision?.overrides),
                      ),
                    ),
                  ]),
                  if (onCorrect != null &&
                      review.canCorrectField(service, field))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey('correct-service-${field.name}'),
                        onPressed: () => onCorrect!(field),
                        child: Text('Correct ${field.label.toLowerCase()}'),
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

/// Keep structured supplier list evidence visible; consultant replacements are
/// plain text lists and do not silently inherit quantity/category metadata.
class ServiceCorrectionSource extends StatelessWidget {
  const ServiceCorrectionSource({
    super.key,
    required this.field,
    required this.service,
  });
  final StagedServiceCorrectionField field;
  final SupplierExtractionServiceFact service;

  @override
  Widget build(BuildContext context) {
    final source = field.sourceValue(service);
    if (source is List<SupplierExtractionStatement> && source.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Supplier source', style: Theme.of(context).textTheme.bodySmall),
          ...reviewSeparated(source.map(ReviewStatement.new)),
        ],
      );
    }
    return ReviewFields([
      ('Supplier source', serviceCorrectionValueLabel(source)),
    ]);
  }
}
