enum SupplierSourceUploadState {
  validating,
  preparing,
  uploading,
  finalizing,
  rollingBack,
  completed,
  failed,
}

final class SupplierSourceUploadProgress {
  const SupplierSourceUploadProgress({
    required this.state,
    required this.totalFiles,
    this.currentFileIndex,
    this.currentFileName,
    this.bytesTransferred,
    this.totalBytes,
  });

  final SupplierSourceUploadState state;
  final int totalFiles;

  /// Zero-based; null when no particular file is active.
  final int? currentFileIndex;
  final String? currentFileName;

  /// Per-file byte counts, not aggregate package counts.
  final int? bytesTransferred;
  final int? totalBytes;
}

/// Returned after the completion write succeeds; no extra read is necessary.
final class CompletedSupplierSourceUpload {
  CompletedSupplierSourceUpload({
    required this.tripId,
    required this.packageId,
    required List<String> fileIds,
  }) : fileIds = List.unmodifiable(fileIds);

  final String tripId;
  final String packageId;
  final List<String> fileIds;
}
