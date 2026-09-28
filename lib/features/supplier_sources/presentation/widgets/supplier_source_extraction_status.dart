import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
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
    final effectiveState =
        state.kind == ItineraryExtractionPackageStateKind.completed &&
            (state.resultingDraftId == null ||
                state.resultingDraftId!.trim().isEmpty)
        ? const ItineraryExtractionPackageState(
            kind: ItineraryExtractionPackageStateKind.error,
            message: 'We couldn’t build the itinerary draft. Please try again.',
          )
        : state;
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
        ItineraryExtractionPackageStateKind.queued => const _BusyStatus(
          label: 'Preparing draft…',
        ),
        ItineraryExtractionPackageStateKind.processing => const _BusyStatus(
          label: 'Building itinerary draft…',
        ),
        ItineraryExtractionPackageStateKind.completed => const _SuccessStatus(),
        ItineraryExtractionPackageStateKind.failed ||
        ItineraryExtractionPackageStateKind.error => _FailureStatus(
          packageId: packageId,
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
  const _SuccessStatus();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.check_circle_outline_rounded, size: 18),
      const SizedBox(width: AppSpacing.s8),
      Text('Draft ready', style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

class _FailureStatus extends StatelessWidget {
  const _FailureStatus({
    required this.packageId,
    required this.message,
    required this.onRetry,
  });

  final String packageId;
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
          'Couldn’t build draft',
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
