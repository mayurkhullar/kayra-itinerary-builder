import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_file_picker.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_file.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_candidate.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_failure.dart';

void main() {
  late FilePickerPlatform original;
  late _Picker platform;
  final picker = PlatformSupplierSourceFilePicker();
  setUp(() {
    original = FilePickerPlatform.instance;
    platform = _Picker();
    FilePickerPlatform.instance = platform;
  });
  tearDown(() => FilePickerPlatform.instance = original);

  test('v13 multi-select reads bytes and preserves selection order', () async {
    final second = _File('second.PDF', bytes: Uint8List.fromList([2, 2, 2]));
    final first = _File('first.xlsx', bytes: Uint8List.fromList([1, 1]));
    platform.files = [second, first];
    final files = await picker.pickFiles();
    expect(files.map((f) => f.originalFileName), ['second.PDF', 'first.xlsx']);
    expect(platform.type, FileType.custom);
    expect(
      platform.extensions,
      SupplierSourceUploadCandidate.contentTypesByExtension.keys,
    );
    expect(files.map((f) => f.bytes), [
      [2, 2, 2],
      [1, 1],
    ]);
    expect(files.map((f) => f.sizeBytes), [3, 2]);
    expect([second.reads, first.reads], [1, 1]);
    expect(() => files.clear(), throwsUnsupportedError);
  });
  test('Web-style file without a local path succeeds', () async {
    final file = _File('quote.pdf');
    expect(file.path, isNull);
    platform.files = [file];
    final candidate = (await picker.pickFiles()).single;
    expect(candidate.originalFileName, 'quote.pdf');
    expect(candidate.bytes, [1, 2]);
  });
  test('picker cancellation returns an empty selection', () async {
    expect(await picker.pickFiles(), isEmpty);
  });
  for (final file in [
    _File('x.zip'),
    _File('x.pdf', size: 0),
    _File('x.pdf', size: 26214401),
  ]) {
    test(
      'rejects invalid file before reading its bytes: ${file.name}/${file.size}',
      () async {
        platform.files = [file];
        await expectLater(
          picker.pickFiles(),
          throwsA(isA<SupplierSourceUploadFailure>()),
        );
        expect(file.reads, 0);
      },
    );
  }
  test('unknown size is validated against actual bytes', () async {
    platform.files = [_File('x.pdf', size: null, asyncSize: null)];
    expect((await picker.pickFiles()).single.sizeBytes, 2);
  });
  test('actual bytes are authoritative when metadata length differs', () async {
    platform.files = [
      _File('x.pdf', size: 30, bytes: Uint8List.fromList([1, 2, 3])),
    ];
    final candidate = (await picker.pickFiles()).single;
    expect(candidate.sizeBytes, 3);
    expect(candidate.bytes, [1, 2, 3]);
  });
  test('falls back from unavailable length metadata to actual bytes', () async {
    platform.files = [
      _File(
        'x.pdf',
        size: null,
        asyncSize: null,
        lengthSyncError: StateError('no synchronous Web metadata'),
        lengthError: StateError('no asynchronous Web metadata'),
      ),
    ];
    expect((await picker.pickFiles()).single.sizeBytes, 2);
  });
  test('zero actual bytes are rejected when metadata is unavailable', () async {
    platform.files = [
      _File('x.pdf', size: null, asyncSize: null, bytes: Uint8List(0)),
    ];
    await expectLater(
      picker.pickFiles(),
      _validationIssue(SupplierSourceUploadValidationIssue.emptyFile),
    );
  });
  test('exactly 25 MB is accepted', () async {
    final bytes = Uint8List(SupplierSourceFile.maxSizeBytes);
    platform.files = [_File('x.pdf', size: bytes.length, bytes: bytes)];
    expect(
      (await picker.pickFiles()).single.sizeBytes,
      SupplierSourceFile.maxSizeBytes,
    );
  });
  test('later invalid file aborts entire selection', () async {
    platform.files = [_File('good.pdf'), _File('bad.zip')];
    await expectLater(
      picker.pickFiles(),
      throwsA(isA<SupplierSourceUploadFailure>()),
    );
  });
  test('picker failures are sanitized', () async {
    platform.error = StateError('private native error');
    try {
      await picker.pickFiles();
      fail('expected failure');
    } on SupplierSourceUploadFailure catch (error) {
      expect(error.kind, SupplierSourceUploadFailureKind.validation);
      expect(error.toString(), isNot(contains('private')));
    }
  });
  test('genuine read failures are sanitized', () async {
    platform.files = [
      _File('x.pdf', readError: StateError('private browser details')),
    ];
    await expectLater(
      picker.pickFiles(),
      throwsA(
        isA<SupplierSourceUploadFailure>()
            .having(
              (error) => error.validationIssue,
              'validation issue',
              SupplierSourceUploadValidationIssue.unknown,
            )
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('private')),
            ),
      ),
    );
  });
}

Matcher _validationIssue(SupplierSourceUploadValidationIssue issue) => throwsA(
  isA<SupplierSourceUploadFailure>().having(
    (error) => error.validationIssue,
    'validation issue',
    issue,
  ),
);

class _Picker extends FilePickerPlatform {
  List<PlatformFile> files = [];
  FileType? type;
  List<String>? extensions;
  Object? error;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.type = type;
    extensions = allowedExtensions;
    if (error != null) throw error!;
    return files;
  }
}

final class _File extends PlatformFile {
  _File(
    this.name, {
    this.size = 2,
    int? asyncSize,
    Uint8List? bytes,
    this.lengthSyncError,
    this.lengthError,
    this.readError,
  }) : asyncSize = asyncSize ?? size,
       bytes = bytes ?? Uint8List.fromList([1, 2]);
  @override
  final String name;
  final int? size;
  final int? asyncSize;
  final Uint8List bytes;
  final Object? lengthSyncError;
  final Object? lengthError;
  final Object? readError;
  int reads = 0;
  @override
  Uri get uri => Uri.parse('blob:https://kayra.local/source-file');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  Stream<Uint8List> readAsByteStream() => throw UnimplementedError();
  @override
  int? lengthSync() {
    if (lengthSyncError case final error?) throw error;
    return size;
  }

  @override
  Future<int?> length() async {
    if (lengthError case final error?) throw error;
    return asyncSize;
  }

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    if (readError case final error?) throw error;
    return bytes;
  }
}
