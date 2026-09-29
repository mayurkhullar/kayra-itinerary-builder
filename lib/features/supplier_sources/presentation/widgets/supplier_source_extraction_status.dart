import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../itineraries/domain/kayra_itinerary_extraction_job.dart';
import '../../../itineraries/presentation/controllers/itinerary_extraction_controller.dart';

class SupplierSourceExtractionStatus extends StatelessWidget {
  const SupplierSourceExtractionStatus({
    super.key,
    required this.packageId,
    required this.state,
    required this.onRequest,
  });

  final String packageId;
  final ItineraryExtractionPackageState state;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final completedResultIsValid = switch (state.resultType) {
      KayraItineraryExtractionResultType.itineraryDraft =>
        state.resultingDraftId != null &&
            state.resultingDraftId!.trim().isNotEmpty &&
            state.resultingExtractionId == null,
      KayraItineraryExtractionResultType.supplierExtraction =>
        state.resultingExtractionId != null &&
            state.resultingExtractionId!.trim().isNotEmpty &&
            state.resultingDraftId == null,
    };
    final effectiveState =
        state.kind == ItineraryExtractionPackageStateKind.completed &&
            !completedResultIsValid
        ? ItineraryExtractionPackageState(
            kind: ItineraryExtractionPackageStateKind.error,
            resultType: state.resultType,
            message:
                state.resultType ==
                    KayraItineraryExtractionResultType.itineraryDraft
                ? 'We couldn’t build the itinerary draft. Please try again.'
                : 'We couldn’t complete the supplier extraction. Please try again.',
          )
        : state;
    final isSupplierExtraction =
        effectiveState.resultType ==
        KayraItineraryExtractionResultType.supplierExtraction;
    return Semantics(
      liveRegion: true,
      container: true,
      child: switch (effectiveState.kind) {
        ItineraryExtractionPackageStateKind.unavailable =>
          const SizedBox.shrink(),
        ItineraryExtractionPackageStateKind.loading => const _BusyStatus(
          label: 'Loading draft status…',
        ),
        ItineraryExtractionPackageStateKind.idle => OutlinedButton(
          key: ValueKey('generate-draft-$packageId'),
          onPressed: onRequest,
          child: const Text('Generate Draft'),
        ),
        ItineraryExtractionPackageStateKind.requesting => OutlinedButton.icon(
          key: ValueKey('generate-draft-$packageId'),
          onPressed: null,
          icon: const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Starting draft…'),
        ),
        ItineraryExtractionPackageStateKind.queued => _BusyStatus(
          label: isSupplierExtraction
              ? 'Preparing extraction…'
              : 'Preparing draft…',
        ),
        ItineraryExtractionPackageStateKind.processing => _BusyStatus(
          label: isSupplierExtraction
              ? 'Reading supplier itinerary…'
              : 'Building itinerary draft…',
        ),
        ItineraryExtractionPackageStateKind.completed => _SuccessStatus(
          label: isSupplierExtraction
              ? 'Extraction ready for review'
              : 'Draft ready',
        ),
        ItineraryExtractionPackageStateKind.failed ||
        ItineraryExtractionPackageStateKind.error => _FailureStatus(
          packageId: packageId,
          title: isSupplierExtraction
              ? 'Couldn’t extract itinerary'
              : 'Couldn’t build draft',
          message:
              effectiveState.message ??
              'We couldn’t build the itinerary draft. Please try again.',
          onRetry: onRequest,
        ),
      },
    );
  }
}

class _BusyStatus extends StatelessWidget {
  const _BusyStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: AppSpacing.s8),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
    ],
  );
}

class _SuccessStatus extends StatelessWidget {
  const _SuccessStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.check_circle_outline_rounded, size: 18),
      const SizedBox(width: AppSpacing.s8),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
    ],
  );
}

class _FailureStatus extends StatelessWidget {
  const _FailureStatus({
    required this.packageId,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String packageId;
  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 300),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s4),
        TextButton(
          key: ValueKey('retry-draft-$packageId'),
          onPressed: onRetry,
          child: const Text('Try Again'),
        ),
      ],
    ),
  );
}
