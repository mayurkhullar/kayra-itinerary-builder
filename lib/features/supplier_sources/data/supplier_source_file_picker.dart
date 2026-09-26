import 'package:file_picker/file_picker.dart';

import '../domain/supplier_source_file.dart';
import '../domain/supplier_source_upload_candidate.dart';
import '../domain/supplier_source_upload_failure.dart';

abstract interface class SupplierSourceFilePicker {
  /// Cancelling selection returns an empty list. Upload cancellation is separate
  /// and deliberately unsupported by the upload engine.
  Future<List<SupplierSourceUploadCandidate>> pickFiles();
}

final class PlatformSupplierSourceFilePicker
    implements SupplierSourceFilePicker {
  @override
  Future<List<SupplierSourceUploadCandidate>> pickFiles() async {
    try {
      // file_picker 13 pickFiles selects multiple files; readAsBytes supports
      // Web blobs and Android content URIs without shared dart:io code.
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: SupplierSourceUploadCandidate
            .contentTypesByExtension
            .keys
            .toList(),
      );
      final candidates = <SupplierSourceUploadCandidate>[];
      for (final file in files) {
        try {
          SupplierSourceUploadCandidate.contentTypeFor(file.name);
        } on FormatException {
          throw SupplierSourceUploadFailure(
            SupplierSourceUploadFailureKind.validation,
            validationIssue:
                SupplierSourceUploadValidationIssue.unsupportedType,
          );
        }
        final length = await _knownLength(file);
        if (length != null) {
          _validateSize(length);
        }
        final bytes = await file.readAsBytes();
        _validateSize(bytes.length);
        candidates.add(
          SupplierSourceUploadCandidate(
            originalFileName: file.name,
            bytes: bytes,
          ),
        );
      }
      return List.unmodifiable(candidates);
    } on SupplierSourceUploadFailure {
      rethrow;
    } catch (_) {
      throw SupplierSourceUploadFailure(
        SupplierSourceUploadFailureKind.validation,
        validationIssue: SupplierSourceUploadValidationIssue.unknown,
      );
    }
  }

  Future<int?> _knownLength(PlatformFile file) async {
    try {
      final length = file.lengthSync();
      if (length != null) return length;
    } catch (_) {
      // A readable browser blob may not expose synchronous metadata.
    }
    try {
      return await file.length();
    } catch (_) {
      // The bytes remain the authoritative size when metadata is unavailable.
      return null;
    }
  }

  void _validateSize(int sizeBytes) {
    if (sizeBytes == 0) {
      throw SupplierSourceUploadFailure(
        SupplierSourceUploadFailureKind.validation,
        validationIssue: SupplierSourceUploadValidationIssue.emptyFile,
      );
    }
    if (sizeBytes < 0 || sizeBytes > SupplierSourceFile.maxSizeBytes) {
      throw SupplierSourceUploadFailure(
        SupplierSourceUploadFailureKind.validation,
        validationIssue: SupplierSourceUploadValidationIssue.tooLarge,
      );
    }
  }
}
