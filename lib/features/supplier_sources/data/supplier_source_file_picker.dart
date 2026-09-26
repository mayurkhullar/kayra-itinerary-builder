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
        final contentType = SupplierSourceUploadCandidate.contentTypeFor(
          file.name,
        );
        final length = file.lengthSync() ?? await file.length();
        if (length != null) {
          SupplierSourceFile.validateMetadata(
            originalFileName: file.name,
            contentType: contentType,
            sizeBytes: length,
          );
        }
        final bytes = await file.readAsBytes();
        if (length != null && length != bytes.length) {
          throw const FormatException('Source file changed during selection.');
        }
        candidates.add(
          SupplierSourceUploadCandidate(
            originalFileName: file.name,
            bytes: bytes,
          ),
        );
      }
      return List.unmodifiable(candidates);
    } catch (_) {
      throw SupplierSourceUploadFailure(
        SupplierSourceUploadFailureKind.validation,
      );
    }
  }
}
