import '../domain/supplier_source_file.dart';
import '../domain/supplier_source_package.dart';
import '../domain/supplier_source_upload_candidate.dart';
import '../domain/supplier_source_upload_failure.dart';
import '../domain/supplier_source_upload_progress.dart';
import '../domain/supplier_source_validation.dart';
import 'supplier_source_cleanup_client.dart';
import 'supplier_source_repository.dart';
import 'supplier_source_storage_uploader.dart';

abstract interface class SupplierSourceUploadExecutor {
  Future<CompletedSupplierSourceUpload> upload({
    required String tripId,
    required String uploadedByUid,
    required List<SupplierSourceUploadCandidate> candidates,
    String? supplierId,
    String? supplierNameSnapshot,
    void Function(SupplierSourceUploadProgress progress)? onProgress,
  });
}

/// Sequential, one-package upload. Deliberately no user cancellation or retries.
/// Await writes/tasks to settle before cleanup; a local timeout would leave an
/// in-flight write/upload able to arrive after rollback.
final class SupplierSourceUploadService
    implements SupplierSourceUploadExecutor {
  SupplierSourceUploadService({
    required SupplierSourceRepository repository,
    required SupplierSourceStorageUploader storage,
    required SupplierSourceCleanupClient cleanup,
  }) : _repository = repository,
       _storage = storage,
       _cleanup = cleanup;

  final SupplierSourceRepository _repository;
  final SupplierSourceStorageUploader _storage;
  final SupplierSourceCleanupClient _cleanup;

  /// [uploadedByUid] must come from the current authenticated session.
  /// Progress observers are advisory: their exceptions cannot abort persistence.
  @override
  Future<CompletedSupplierSourceUpload> upload({
    required String tripId,
    required String uploadedByUid,
    required List<SupplierSourceUploadCandidate> candidates,
    String? supplierId,
    String? supplierNameSnapshot,
    void Function(SupplierSourceUploadProgress progress)? onProgress,
  }) async {
    final files = List<SupplierSourceUploadCandidate>.unmodifiable(candidates);
    void emit(
      SupplierSourceUploadState state, {
      int? index,
      int? bytes,
      int? total,
    }) {
      try {
        onProgress?.call(
          SupplierSourceUploadProgress(
            state: state,
            totalFiles: files.length,
            currentFileIndex: index,
            currentFileName: index == null
                ? null
                : files[index].originalFileName,
            bytesTransferred: bytes,
            totalBytes: total,
          ),
        );
      } catch (_) {
        // A view/observer failure must not corrupt the upload lifecycle.
      }
    }

    emit(SupplierSourceUploadState.validating);
    try {
      _validateSegment(tripId);
      _validateSegment(uploadedByUid);
      SupplierSourcePackage.validateSupplierLink(
        supplierId,
        supplierNameSnapshot,
      );
      if (supplierId != null) _validateSegment(supplierId);
      if (files.isEmpty) throw const FormatException('No files selected.');
      for (final file in files) {
        file.validate();
      }
    } catch (_) {
      emit(SupplierSourceUploadState.failed);
      throw SupplierSourceUploadFailure(
        SupplierSourceUploadFailureKind.validation,
      );
    }

    String? packageId;
    final attempts = <({String id, int index})>[];
    final completedIds = <String>[];
    var failureKind = SupplierSourceUploadFailureKind.packagePreparation;
    try {
      emit(SupplierSourceUploadState.preparing);
      packageId = await _repository.createPackage(
        tripId: tripId,
        currentUserUid: uploadedByUid,
        supplierId: supplierId,
        supplierNameSnapshot: supplierNameSnapshot,
        onIdentityAllocated: (id) => packageId = id,
      );
      _validateSegment(packageId!);
      failureKind = SupplierSourceUploadFailureKind.upload;
      for (var index = 0; index < files.length; index++) {
        final candidate = files[index];
        emit(
          SupplierSourceUploadState.uploading,
          index: index,
          bytes: 0,
          total: candidate.sizeBytes,
        );
        final fileId = await _repository.createFileMetadata(
          tripId: tripId,
          packageId: packageId!,
          originalFileName: candidate.originalFileName,
          storageFileName: candidate.storageFileName,
          contentType: candidate.contentType,
          sizeBytes: candidate.sizeBytes,
          currentUserUid: uploadedByUid,
          onIdentityAllocated: (id) => attempts.add((id: id, index: index)),
        );
        // Repositories implementing the contract must announce identity before
        // writing. Retain returned IDs too for older successful implementations.
        if (!attempts.any((attempt) => attempt.id == fileId)) {
          attempts.add((id: fileId, index: index));
        }
        _validateSegment(fileId);
        await _storage.upload(
          storagePath: SupplierSourceFile.buildStoragePath(
            tripId: tripId,
            fileId: fileId,
            storageFileName: candidate.storageFileName,
          ),
          bytes: candidate.bytes,
          contentType: candidate.contentType,
          customMetadata: {
            'packageId': packageId!,
            'uploadedByUid': uploadedByUid,
          },
          onProgress: (transferred, total) => emit(
            SupplierSourceUploadState.uploading,
            index: index,
            bytes: transferred,
            total: total,
          ),
        );
        completedIds.add(fileId);
      }
      failureKind = SupplierSourceUploadFailureKind.finalization;
      emit(SupplierSourceUploadState.finalizing);
      await _repository.updatePackageAfterUpload(
        tripId: tripId,
        packageId: packageId!,
        fileIds: completedIds,
        status: SupplierSourcePackageStatus.uploaded,
      );
    } catch (_) {
      final failedCleanup = <String>[];
      var packageFailureUnconfirmed = false;
      if (packageId != null) {
        emit(SupplierSourceUploadState.rollingBack);
        for (final attempt in attempts) {
          emit(SupplierSourceUploadState.rollingBack, index: attempt.index);
          try {
            await _cleanup.cleanup(
              tripId: tripId,
              packageId: packageId!,
              sourceFileId: attempt.id,
              fileName: files[attempt.index].storageFileName,
            );
          } catch (_) {
            failedCleanup.add(attempt.id);
          }
        }
        if (attempts.isEmpty) {
          try {
            final package = await _repository.getPackage(tripId, packageId!);
            if (package?.status == SupplierSourcePackageStatus.uploading) {
              await _repository.updatePackageAfterUpload(
                tripId: tripId,
                packageId: packageId!,
                fileIds: package!.fileIds,
                status: SupplierSourcePackageStatus.failed,
              );
            } else if (package?.status ==
                SupplierSourcePackageStatus.uploaded) {
              // Never reopen or directly delete evidence from a terminal package.
              packageFailureUnconfirmed = true;
            }
          } catch (_) {
            packageFailureUnconfirmed = true;
          }
        }
      }
      emit(SupplierSourceUploadState.failed);
      final incomplete = failedCleanup.isNotEmpty || packageFailureUnconfirmed;
      throw SupplierSourceUploadFailure(
        incomplete
            ? SupplierSourceUploadFailureKind.rollbackIncomplete
            : failureKind,
        packageId: packageId,
        originalKind: incomplete ? failureKind : null,
        cleanupFailedFileIds: failedCleanup,
        packageFailureUnconfirmed: packageFailureUnconfirmed,
      );
    }
    emit(SupplierSourceUploadState.completed);
    return CompletedSupplierSourceUpload(
      tripId: tripId,
      packageId: packageId!,
      fileIds: completedIds,
    );
  }

  static void _validateSegment(String value) {
    SupplierSourceValidation.id(value);
    if (RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException('Invalid rollback identity.');
    }
  }
}
