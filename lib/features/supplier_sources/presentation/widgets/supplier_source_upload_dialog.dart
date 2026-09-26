import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../suppliers/data/supplier_repository.dart';
import '../../../suppliers/domain/kayra_supplier.dart';
import '../../../suppliers/presentation/widgets/supplier_form.dart';
import '../../data/supplier_source_file_picker.dart';
import '../../data/supplier_source_upload_service.dart';
import '../../domain/supplier_source_upload_candidate.dart';
import '../../domain/supplier_source_upload_failure.dart';
import '../../domain/supplier_source_upload_progress.dart';

final class SupplierSourceUploadDialogResult {
  const SupplierSourceUploadDialogResult({
    required this.uploadAttempted,
    required this.succeeded,
  });

  final bool uploadAttempted;
  final bool succeeded;
}

enum _UploadSurfacePhase { editing, uploading, succeeded, failed }

class SupplierSourceUploadDialog extends StatefulWidget {
  const SupplierSourceUploadDialog({
    super.key,
    required this.tripId,
    required this.uploadedByUid,
    required this.supplierRepository,
    required this.picker,
    required this.uploadExecutor,
  });

  final String tripId;
  final String uploadedByUid;
  final SupplierRepository supplierRepository;
  final SupplierSourceFilePicker picker;
  final SupplierSourceUploadExecutor uploadExecutor;

  @override
  State<SupplierSourceUploadDialog> createState() =>
      _SupplierSourceUploadDialogState();
}

class _SupplierSourceUploadDialogState
    extends State<SupplierSourceUploadDialog> {
  final _supplierSearch = TextEditingController();
  final _fileScroll = ScrollController();
  List<KayraSupplier>? _suppliers;
  KayraSupplier? _selectedSupplier;
  final _candidates = <SupplierSourceUploadCandidate>[];
  bool _supplierLoadFailed = false;
  bool _picking = false;
  String? _selectionError;
  String? _failureMessage;
  SupplierSourceUploadProgress? _progress;
  _UploadSurfacePhase _phase = _UploadSurfacePhase.editing;

  bool get _editing => _phase == _UploadSurfacePhase.editing;
  bool get _uploading => _phase == _UploadSurfacePhase.uploading;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _supplierSearch.addListener(_searchChanged);
  }

  @override
  void dispose() {
    _supplierSearch
      ..removeListener(_searchChanged)
      ..dispose();
    _fileScroll.dispose();
    super.dispose();
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSuppliers({String? selectSupplierId}) async {
    try {
      final suppliers = await widget.supplierRepository.listSuppliers();
      if (!mounted) return;
      final active =
          suppliers
              .where((supplier) => supplier.status == SupplierStatus.active)
              .toList()
            ..sort((a, b) => a.normalizedName.compareTo(b.normalizedName));
      setState(() {
        _suppliers = List.unmodifiable(active);
        _supplierLoadFailed = false;
        if (selectSupplierId != null) {
          _selectedSupplier = active
              .where((supplier) => supplier.id == selectSupplierId)
              .firstOrNull;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _supplierLoadFailed = true);
    }
  }

  Future<void> _createSupplier() async {
    if (!_editing) return;
    String? createdSupplierId;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplierForm(
        onSave: (details) async {
          createdSupplierId = await widget.supplierRepository.createSupplier(
            details: details,
            currentUserUid: widget.uploadedByUid,
          );
        },
      ),
    );
    if (!mounted || saved != true || createdSupplierId == null) return;
    _supplierSearch.clear();
    await _loadSuppliers(selectSupplierId: createdSupplierId);
  }

  List<KayraSupplier> get _matchingSuppliers {
    final query = _supplierSearch.text.trim().toLowerCase();
    final suppliers = _suppliers ?? const <KayraSupplier>[];
    if (query.isEmpty) return suppliers;
    return suppliers.where((supplier) {
      return supplier.normalizedName.contains(query) ||
          supplier.destinationCoverage.any(
            (destination) => destination.toLowerCase().contains(query),
          );
    }).toList();
  }

  Future<void> _chooseFiles() async {
    if (!_editing || _picking) return;
    setState(() {
      _picking = true;
      _selectionError = null;
    });
    try {
      final selected = await widget.picker.pickFiles();
      if (!mounted) return;
      setState(() => _candidates.addAll(selected));
    } on SupplierSourceUploadFailure catch (error) {
      if (mounted) setState(() => _selectionError = _pickerMessage(error));
    } catch (_) {
      if (mounted) {
        setState(() {
          _selectionError =
              'Files couldn’t be selected. Please choose them again.';
        });
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _startUpload() async {
    if (!_editing || _candidates.isEmpty) return;
    final supplier = _selectedSupplier;
    setState(() {
      _phase = _UploadSurfacePhase.uploading;
      _selectionError = null;
      _progress = SupplierSourceUploadProgress(
        state: SupplierSourceUploadState.validating,
        totalFiles: _candidates.length,
      );
    });
    try {
      await widget.uploadExecutor.upload(
        tripId: widget.tripId,
        uploadedByUid: widget.uploadedByUid,
        candidates: List.unmodifiable(_candidates),
        supplierId: supplier?.id,
        supplierNameSnapshot: supplier?.name,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _phase = _UploadSurfacePhase.succeeded;
        _progress = SupplierSourceUploadProgress(
          state: SupplierSourceUploadState.completed,
          totalFiles: _candidates.length,
        );
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) {
        Navigator.of(context).pop(
          const SupplierSourceUploadDialogResult(
            uploadAttempted: true,
            succeeded: true,
          ),
        );
      }
    } on SupplierSourceUploadFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UploadSurfacePhase.failed;
        _failureMessage =
            error.kind == SupplierSourceUploadFailureKind.rollbackIncomplete
            ? 'Upload couldn’t be completed and some cleanup could not be confirmed. Please contact an administrator before uploading these files again.'
            : 'Upload couldn’t be completed. No incomplete source files were kept.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _UploadSurfacePhase.failed;
        _failureMessage =
            'Upload couldn’t be completed. Please contact an administrator before uploading these files again.';
      });
    }
  }

  void _close() {
    if (_uploading || _phase == _UploadSurfacePhase.succeeded) return;
    Navigator.of(context).pop(
      SupplierSourceUploadDialogResult(
        uploadAttempted: _phase == _UploadSurfacePhase.failed,
        succeeded: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final mobile = media.size.width < AppLayout.mobileBreakpoint;
    final availableHeight =
        (media.size.height - media.viewInsets.bottom - AppSpacing.s24)
            .clamp(360.0, media.size.height * 0.9)
            .toDouble();
    return PopScope(
      canPop: _editing,
      child: Dialog(
        key: const ValueKey('supplier-source-upload-dialog'),
        insetPadding: EdgeInsets.all(mobile ? AppSpacing.s12 : AppSpacing.s20),
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: availableHeight,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                enabled:
                    _phase == _UploadSurfacePhase.editing ||
                    _phase == _UploadSurfacePhase.failed,
                onClose: _close,
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  child: switch (_phase) {
                    _UploadSurfacePhase.editing => _editableContent(context),
                    _UploadSurfacePhase.uploading => _progressContent(context),
                    _UploadSurfacePhase.succeeded => _successContent(context),
                    _UploadSurfacePhase.failed => _failureContent(context),
                  },
                ),
              ),
              const Divider(height: 1),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editableContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final title = Text(
            'Supplier',
            style: Theme.of(context).textTheme.titleMedium,
          );
          final action = TextButton(
            key: const ValueKey('add-new-supplier'),
            onPressed: _createSupplier,
            child: const Text('+ Add new supplier'),
          );
          if (constraints.maxWidth >= 520) {
            return Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: AppSpacing.s12),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: AppSpacing.s4),
              action,
            ],
          );
        },
      ),
      const SizedBox(height: AppSpacing.s4),
      Text(
        'Link these files to a Supplier if known.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.s12),
      _SupplierOption(
        key: const ValueKey('supplier-option-unassigned'),
        title: 'Supplier not assigned',
        selected: _selectedSupplier == null,
        onTap: () => setState(() => _selectedSupplier = null),
      ),
      if (_suppliers == null && !_supplierLoadFailed) ...[
        const SizedBox(height: AppSpacing.s12),
        const Row(
          children: [
            SizedBox.square(
              dimension: AppSpacing.s16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.s8),
            Text('Loading Suppliers…'),
          ],
        ),
      ] else if (_supplierLoadFailed) ...[
        const SizedBox(height: AppSpacing.s12),
        Text(
          'Suppliers couldn’t be loaded. You can continue without assigning one.',
          key: const ValueKey('supplier-load-error'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ] else ...[
        const SizedBox(height: AppSpacing.s12),
        TextField(
          key: const ValueKey('supplier-source-supplier-search'),
          controller: _supplierSearch,
          decoration: const InputDecoration(
            labelText: 'Search Suppliers',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 168),
          child: _matchingSuppliers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                  child: Text(
                    _suppliers!.isEmpty
                        ? 'No active Suppliers available.'
                        : 'No matching Suppliers.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _matchingSuppliers.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s4),
                  itemBuilder: (context, index) {
                    final supplier = _matchingSuppliers[index];
                    return _SupplierOption(
                      key: ValueKey('supplier-option-${supplier.id}'),
                      title: supplier.name,
                      subtitle: supplier.destinationCoverage.isEmpty
                          ? null
                          : supplier.destinationCoverage.join(' · '),
                      selected: _selectedSupplier?.id == supplier.id,
                      onTap: () => setState(() => _selectedSupplier = supplier),
                    );
                  },
                ),
        ),
      ],
      const SizedBox(height: AppSpacing.s24),
      Text('Files', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: AppSpacing.s4),
      Text(
        'PDF, Word, Excel, CSV, TXT, JPG, PNG or WebP · Maximum 25 MB per file',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.s12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('choose-supplier-source-files'),
          onPressed: _picking ? null : _chooseFiles,
          icon: const Icon(Icons.attach_file_rounded),
          label: Text(_candidates.isEmpty ? 'Choose files' : 'Add more files'),
        ),
      ),
      if (_selectionError != null) ...[
        const SizedBox(height: AppSpacing.s12),
        Semantics(
          liveRegion: true,
          child: Text(
            _selectionError!,
            key: const ValueKey('file-selection-error'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
      if (_candidates.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.s12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Scrollbar(
            controller: _fileScroll,
            child: ListView.separated(
              controller: _fileScroll,
              shrinkWrap: true,
              itemCount: _candidates.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _SelectedFileRow(
                key: ValueKey('selected-source-file-$index'),
                candidate: _candidates[index],
                onRemove: () => setState(() => _candidates.removeAt(index)),
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Widget _progressContent(BuildContext context) {
    final progress = _progress;
    final transferred = progress?.bytesTransferred;
    final total = progress?.totalBytes;
    final showBytes = transferred != null && total != null && total > 0;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
        child: Column(
          children: [
            const SizedBox.square(
              dimension: AppSpacing.s32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(
              _progressMessage(progress),
              key: const ValueKey('supplier-source-progress-message'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (progress?.currentFileName != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                progress!.currentFileName!,
                key: const ValueKey('supplier-source-progress-filename'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (showBytes) ...[
              const SizedBox(height: AppSpacing.s20),
              LinearProgressIndicator(
                key: const ValueKey('supplier-source-byte-progress'),
                value: (transferred / total).clamp(0.0, 1.0),
                minHeight: AppSpacing.s4,
                borderRadius: BorderRadius.circular(AppRadius.r8),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                '${readableFileSize(transferred)} of ${readableFileSize(total)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _successContent(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s40),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: AppSpacing.s40),
          const SizedBox(height: AppSpacing.s16),
          Text(
            'Supplier source uploaded',
            key: const ValueKey('supplier-source-upload-success'),
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _failureContent(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s32),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, size: AppSpacing.s40),
          const SizedBox(height: AppSpacing.s16),
          Text(
            _failureMessage!,
            key: const ValueKey('supplier-source-upload-failure'),
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _footer(BuildContext context) {
    if (_uploading || _phase == _UploadSurfacePhase.succeeded) {
      return const SizedBox(height: AppSpacing.s20);
    }
    if (_phase == _UploadSurfacePhase.failed) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _close, child: const Text('Close')),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.s8,
        runSpacing: AppSpacing.s8,
        children: [
          TextButton(onPressed: _close, child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('upload-supplier-source'),
            onPressed: _candidates.isEmpty ? null : _startUpload,
            child: const Text('Upload Supplier Source'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.enabled, required this.onClose});

  final bool enabled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s20,
      AppSpacing.s16,
      AppSpacing.s12,
      AppSpacing.s16,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Supplier Source',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Upload the supplier quotation or itinerary files received for this trip.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        IconButton(
          key: const ValueKey('close-supplier-source-upload'),
          tooltip: 'Close',
          onPressed: enabled ? onClose : null,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _SupplierOption extends StatelessWidget {
  const _SupplierOption({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.navyTint : AppColors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.r8),
      side: BorderSide(color: selected ? AppColors.navy : AppColors.border),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: AppSpacing.s20,
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SelectedFileRow extends StatelessWidget {
  const _SelectedFileRow({
    super.key,
    required this.candidate,
    required this.onRemove,
  });

  final SupplierSourceUploadCandidate candidate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
    child: Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.navyTint,
            borderRadius: BorderRadius.circular(AppRadius.r8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            child: Text(
              fileTypeLabel(candidate.originalFileName),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                candidate.originalFileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                readableFileSize(candidate.sizeBytes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove ${candidate.originalFileName}',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
  );
}

String _pickerMessage(SupplierSourceUploadFailure error) =>
    switch (error.validationIssue) {
      SupplierSourceUploadValidationIssue.unsupportedType =>
        'This file type isn’t supported.',
      SupplierSourceUploadValidationIssue.emptyFile =>
        'This file is empty and can’t be uploaded.',
      SupplierSourceUploadValidationIssue.tooLarge =>
        'Each file must be 25 MB or smaller.',
      SupplierSourceUploadValidationIssue.changedDuringSelection ||
      SupplierSourceUploadValidationIssue.unknown ||
      null => 'Files couldn’t be selected. Please choose them again.',
    };

String _progressMessage(SupplierSourceUploadProgress? progress) {
  if (progress == null) return 'Preparing upload…';
  return switch (progress.state) {
    SupplierSourceUploadState.validating ||
    SupplierSourceUploadState.preparing => 'Preparing upload…',
    SupplierSourceUploadState.uploading =>
      'Uploading ${(progress.currentFileIndex ?? 0) + 1} of ${progress.totalFiles}…',
    SupplierSourceUploadState.finalizing => 'Finalising…',
    SupplierSourceUploadState.rollingBack => 'Cleaning up…',
    SupplierSourceUploadState.completed => 'Upload complete',
    SupplierSourceUploadState.failed => 'Upload couldn’t be completed.',
  };
}

String readableFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String fileTypeLabel(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? 'FILE' : fileName.substring(dot + 1).toUpperCase();
}
