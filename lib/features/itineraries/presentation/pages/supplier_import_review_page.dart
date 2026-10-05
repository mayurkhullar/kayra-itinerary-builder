import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/kayra_content_frame.dart';
import '../controllers/supplier_import_review_controller.dart';
import '../controllers/supplier_import_review_dependencies.dart';
import '../controllers/supplier_import_review_state.dart';
import '../widgets/supplier_import/review_components.dart';
import '../widgets/supplier_import/review_session_panel.dart';
import '../widgets/supplier_import/review_summary.dart';
import '../widgets/supplier_import/snapshot_itinerary.dart';
import '../widgets/supplier_import/snapshot_package_facts.dart';

class SupplierImportReviewPage extends StatefulWidget {
  const SupplierImportReviewPage({
    super.key,
    required this.tripId,
    required this.extractionId,
    required this.dependencies,
    required this.onBack,
  });
  final String tripId;
  final String extractionId;
  final SupplierImportReviewDependencies dependencies;
  final VoidCallback onBack;
  @override
  State<SupplierImportReviewPage> createState() =>
      _SupplierImportReviewPageState();
}

class _SupplierImportReviewPageState extends State<SupplierImportReviewPage> {
  late SupplierImportReviewController _controller;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() {
    _controller = widget.dependencies.createController(
      widget.tripId,
      widget.extractionId,
    )..addListener(_changed);
    _controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SupplierImportReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId ||
        oldWidget.extractionId != widget.extractionId ||
        oldWidget.dependencies != widget.dependencies) {
      _release();
      _initialize();
    }
  }

  void _release() {
    _controller
      ..removeListener(_changed)
      ..dispose();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final loaded = state.loaded;
    final busy =
        state is SupplierImportReviewInitial ||
        state is SupplierImportReviewLoading ||
        state is SupplierImportReviewSaving;
    final refreshing = state is SupplierImportReviewLoading;
    return SingleChildScrollView(
      key: const ValueKey('supplier-import-review-scroll'),
      child: KayraContentFrame(
        maxWidth: AppLayout.dashboardMaxContentWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('back-to-trip-workspace'),
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to Trip Workspace'),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              Semantics(
                header: true,
                child: Text(
                  'Review supplier extraction',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                'Machine-extracted supplier content for consultant review.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.s16),
              Wrap(
                spacing: AppSpacing.s16,
                runSpacing: AppSpacing.s12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (loaded != null)
                    Semantics(
                      liveRegion: true,
                      child: ReviewBadge(reviewStatusLabel(loaded)),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('refresh-supplier-review'),
                    onPressed: busy ? null : _controller.refresh,
                    icon: refreshing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      refreshing && loaded != null ? 'Refreshing…' : 'Refresh',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s24),
              ReviewStateNotice(
                state: state,
                onRefresh: _controller.refresh,
                onRetry: _controller.retryPendingMutation,
              ),
              if (loaded == null && busy)
                const _ReviewLoading()
              else if (loaded != null) ...[
                Semantics(
                  header: true,
                  child: Text(
                    loaded.snapshot.title.text.trim().isEmpty
                        ? 'Supplier itinerary extraction'
                        : loaded.snapshot.title.text,
                    key: const ValueKey('review-snapshot-title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                ReviewSources(loaded.snapshot.title.sources),
                const SizedBox(height: AppSpacing.s24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final rail = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ReviewSessionPanel(
                          state: state,
                          onStart: _controller.startReview,
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        ReviewSummary(snapshot: loaded.snapshot),
                      ],
                    );
                    final content = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SnapshotReviewIssues(snapshot: loaded.snapshot),
                        SnapshotItinerary(snapshot: loaded.snapshot),
                        SnapshotPackageFacts(snapshot: loaded.snapshot),
                        ReviewHistory(loaded: loaded),
                      ],
                    );
                    if (constraints.maxWidth >= AppLayout.desktopBreakpoint &&
                        MediaQuery.textScalerOf(context).scale(16) <= 20) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: content),
                          const SizedBox(width: AppSpacing.s32),
                          SizedBox(width: 300, child: rail),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        rail,
                        const SizedBox(height: AppSpacing.s32),
                        content,
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewLoading extends StatelessWidget {
  const _ReviewLoading();
  @override
  Widget build(BuildContext context) => ReviewPanel(
    key: const ValueKey('review-loading'),
    child: Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
        child: Column(
          children: [
            const SizedBox.square(
              dimension: AppSpacing.s24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Loading supplier extraction…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s8),
            const Text(
              'Preparing the source content and current review record.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
