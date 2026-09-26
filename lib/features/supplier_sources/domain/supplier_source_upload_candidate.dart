import 'dart:typed_data';

import 'supplier_source_file.dart';

/// Owns an immutable copy of the selected bytes. MIME comes only from extension.
final class SupplierSourceUploadCandidate {
  factory SupplierSourceUploadCandidate({
    required String originalFileName,
    required Uint8List bytes,
  }) {
    final contentType = contentTypeFor(originalFileName);
    SupplierSourceFile.validateMetadata(
      originalFileName: originalFileName,
      contentType: contentType,
      sizeBytes: bytes.length,
    );
    return SupplierSourceUploadCandidate._(
      originalFileName,
      normalizeFileName(originalFileName),
      Uint8List.fromList(bytes).asUnmodifiableView(),
      contentType,
    );
  }

  const SupplierSourceUploadCandidate._(
    this.originalFileName,
    this.storageFileName,
    this.bytes,
    this.contentType,
  );

  static const contentTypesByExtension = <String, String>{
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv': 'text/csv',
    'txt': 'text/plain',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  final String originalFileName;
  final String storageFileName;
  final Uint8List bytes;
  final String contentType;
  int get sizeBytes => bytes.length;

  static String _extension(String name) {
    final trimmed = name.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot <= 0 || dot == trimmed.length - 1) {
      throw const FormatException('A supported file extension is required.');
    }
    final extension = trimmed.substring(dot + 1).toLowerCase();
    if (!contentTypesByExtension.containsKey(extension)) {
      throw const FormatException('Unsupported source file extension.');
    }
    return extension;
  }

  static String contentTypeFor(String name) =>
      contentTypesByExtension[_extension(name)]!;

  static String normalizeFileName(String name) {
    final extension = _extension(name);
    final trimmed = name.trim();
    var stem = trimmed
        .substring(0, trimmed.lastIndexOf('.'))
        .replaceAll(RegExp(r'[/\\\x00-\x1f\x7f<>:"|?*]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '_')
        .trim();
    if (stem.isEmpty || stem == '.') stem = 'source';
    return '$stem.$extension';
  }

  void validate() {
    SupplierSourceFile.validateMetadata(
      originalFileName: originalFileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
    );
    if (contentType != contentTypeFor(originalFileName) ||
        storageFileName != normalizeFileName(originalFileName)) {
      throw const FormatException('Invalid source candidate.');
    }
  }
}
