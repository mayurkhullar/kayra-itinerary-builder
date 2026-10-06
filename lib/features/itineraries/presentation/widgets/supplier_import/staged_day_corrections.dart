import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_snapshot.dart';
import 'review_components.dart';
import 'staged_day_correction.dart';
import 'staged_day_review_data.dart';

class StagedDayCorrections extends StatelessWidget {
  const StagedDayCorrections({
    super.key,
    required this.day,
    required this.review,
    this.onCorrect,
  });
  final SupplierExtractionStagedDay day;
  final StagedDayReviewData review;
  final ValueChanged<StagedDayCorrectionField>? onCorrect;

  @override
  Widget build(BuildContext context) {
    final overrides = review.decisionFor(day)?.overrides;
    final fields = StagedDayCorrectionField.values.where(
      (field) => onCorrect != null || field.overrideIn(overrides) != null,
    );
    if (fields.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: ValueKey('day-corrections-${day.id}'),
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
          if (!review.review.isRetainedDay(day))
            const Text(
              'Corrections are kept while this day is excluded. Retain the day to edit them.',
            ),
          for (final field in fields)
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
                        field.sourceValue(day) ?? 'Not provided',
                      ),
                    (
                      'Consultant correction',
                      dayCorrectionLabel(field.overrideIn(overrides)),
                    ),
                  ]),
                  if (onCorrect != null && review.canCorrect(day))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey('correct-day-${field.name}'),
                        onPressed: () => onCorrect!(field),
                        child: Text('Correct ${field.label.toLowerCase()}'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
