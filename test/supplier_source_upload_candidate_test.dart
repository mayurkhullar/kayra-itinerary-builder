import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_file.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_candidate.dart';

void main() {
  for (final entry
      in SupplierSourceUploadCandidate.contentTypesByExtension.entries) {
    test('${entry.key} maps to the secured MIME type, including uppercase', () {
      final file = SupplierSourceUploadCandidate(
        originalFileName: 'Quote.${entry.key.toUpperCase()}',
        bytes: Uint8List(1),
      );
      expect(file.contentType, entry.value);
      expect(file.storageFileName, 'Quote.${entry.key}');
      expect(SupplierSourceFile.supportedContentTypes, contains(entry.value));
      file.validate();
    });
  }
  test('mapping matches the existing secured MIME allowlist exactly', () {
    expect(
      SupplierSourceUploadCandidate.contentTypesByExtension.values.toSet(),
      SupplierSourceFile.supportedContentTypes,
    );
    expect(SupplierSourceUploadCandidate.contentTypesByExtension.keys, [
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'csv',
      'txt',
      'jpg',
      'jpeg',
      'png',
      'webp',
    ]);
  });
  for (final name in [
    'quote',
    '.pdf',
    'quote.',
    'quote.exe',
    'quote.zip',
    'quote.eml',
    'quote.msg',
    'quote.pdf.exe',
    '',
  ]) {
    test('rejects unsupported or missing extension: $name', () {
      expect(
        () => SupplierSourceUploadCandidate(
          originalFileName: name,
          bytes: Uint8List(1),
        ),
        throwsFormatException,
      );
    });
  }
  for (final size in [0, SupplierSourceFile.maxSizeBytes + 1]) {
    test('rejects $size bytes', () {
      expect(
        () => SupplierSourceUploadCandidate(
          originalFileName: 'quote.pdf',
          bytes: Uint8List(size),
        ),
        throwsFormatException,
      );
    });
  }
  test('accepts exactly 25 MB', () {
    final file = SupplierSourceUploadCandidate(
      originalFileName: 'quote.pdf',
      bytes: Uint8List(SupplierSourceFile.maxSizeBytes),
    );
    expect(file.sizeBytes, 26214400);
  });
  test('bytes are defensively copied and unmodifiable', () {
    final bytes = Uint8List.fromList([1, 2]);
    final file = SupplierSourceUploadCandidate(
      originalFileName: 'a.pdf',
      bytes: bytes,
    );
    bytes[0] = 9;
    expect(file.bytes, [1, 2]);
    expect(() => file.bytes[0] = 9, throwsUnsupportedError);
    expect(
      () => file.bytes.buffer.asUint8List()[0] = 9,
      throwsUnsupportedError,
    );
  });
  for (final name in [
    ' ../Quotes\\summer..rates.PDF ',
    'folder/a\u0000b\u001fc\u007f.txt',
    'a<>:"|?*.xlsx',
    '...pdf',
  ]) {
    test('normalizes unsafe segments and preserves original: $name', () {
      final file = SupplierSourceUploadCandidate(
        originalFileName: name,
        bytes: Uint8List(1),
      );
      expect(file.originalFileName, name);
      expect(file.storageFileName, isNot(contains('/')));
      expect(file.storageFileName, isNot(contains('\\')));
      expect(file.storageFileName, isNot(contains('..')));
      expect(
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(file.storageFileName),
        isFalse,
      );
      expect(file.storageFileName, file.storageFileName.trim());
      expect(
        SupplierSourceUploadCandidate.contentTypeFor(file.storageFileName),
        file.contentType,
      );
    });
  }
  test('keeps ordinary names and Unicode recognisable', () {
    expect(
      SupplierSourceUploadCandidate.normalizeFileName(
        '  Summer दिल्ली Quote.PDF ',
      ),
      'Summer दिल्ली Quote.pdf',
    );
  });
}
