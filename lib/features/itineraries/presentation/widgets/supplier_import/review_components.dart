import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/supplier_extraction_values.dart';

class ReviewSection extends StatelessWidget {
  const ReviewSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpacing.s16),
        child,
      ],
    ),
  );
}

class ReviewPanel extends StatelessWidget {
  const ReviewPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(AppSpacing.s20), child: child),
  );
}

class ReviewBadge extends StatelessWidget {
  const ReviewBadge(this.label, {super.key, this.strong = false});
  final String label;
  final bool strong;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: strong ? AppColors.navy : AppColors.navyTint,
      borderRadius: BorderRadius.circular(AppRadius.r8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: strong ? AppColors.white : AppColors.navy,
        ),
      ),
    ),
  );
}

class ReviewFields extends StatelessWidget {
  const ReviewFields(this.fields, {super.key, this.omitValues = const {}});
  final List<(String, String?)> fields;
  final Set<String> omitValues;
  @override
  Widget build(BuildContext context) {
    final visible = fields
        .where(
          (field) =>
              field.$2 != null &&
              field.$2!.trim().isNotEmpty &&
              !omitValues.contains(field.$2),
        )
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth >= 480 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 20
              ? 2
              : 1;
          final width =
              (constraints.maxWidth - AppSpacing.s20 * (columns - 1)) / columns;
          return Wrap(
            spacing: AppSpacing.s20,
            runSpacing: AppSpacing.s12,
            children: [
              for (final (label, value) in visible)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        value!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ReviewText extends StatelessWidget {
  const ReviewText(this.text, {super.key, this.label});
  final String? text;
  final String? label;
  @override
  Widget build(BuildContext context) => text == null || text!.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Text(label!, style: Theme.of(context).textTheme.labelMedium),
              Text(text!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        );
}

class ReviewSources extends StatelessWidget {
  const ReviewSources(this.sources, {super.key});
  final List<SupplierExtractionSourceReference> sources;
  @override
  Widget build(BuildContext context) {
    // Provenance captions are optional. Only simple page locators are shown;
    // arbitrary source labels and all trusted IDs stay out of the presentation.
    final labels = sources
        .map((source) => source.sourceLabel)
        .whereType<String>()
        .where(
          (label) => RegExp(r'^Pages? \d+(?:[–,\- ]+\d+)*$').hasMatch(label),
        )
        .toSet();
    if (labels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Text(
        'Source: ${labels.join(' · ')}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

List<Widget> reviewSeparated(Iterable<Widget> widgets) => [
  for (final (index, widget) in widgets.indexed) ...[
    if (index > 0)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s20),
        child: Divider(),
      ),
    widget,
  ],
];

String reviewLabel(String value) {
  final text = value.replaceAll('_', ' ');
  return text.isEmpty ? '' : '${text[0].toUpperCase()}${text.substring(1)}';
}

String? reviewDate(DateTime? date) {
  if (date == null) return null;
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
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String? reviewAppliesTo(List<SupplierExtractionServiceType> types) =>
    types.isEmpty
    ? null
    : types.map((type) => reviewLabel(type.value)).join(' · ');

class ReviewStatement extends StatelessWidget {
  const ReviewStatement(this.statement, {super.key});
  final SupplierExtractionStatement statement;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(statement.text, style: Theme.of(context).textTheme.bodyMedium),
      ReviewFields([
        ('Category', reviewLabel(statement.category.value)),
        ('Quantity', statement.quantity?.toString()),
        ('Frequency', statement.frequency),
        ('Applies to', reviewAppliesTo(statement.appliesTo)),
      ]),
      ReviewSources(statement.sources),
    ],
  );
}

class ReviewCondition extends StatelessWidget {
  const ReviewCondition(this.condition, {super.key});
  final SupplierExtractionCondition condition;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        reviewLabel(condition.kind.value),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      Text(condition.value, style: Theme.of(context).textTheme.bodyMedium),
      ReviewSources(condition.sources),
    ],
  );
}
