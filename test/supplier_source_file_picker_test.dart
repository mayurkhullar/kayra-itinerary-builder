import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_file_picker.dart';
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

  test(
    'multi-select restricts extensions and preserves selection order',
    () async {
      platform.files = [_File('second.PDF'), _File('first.xlsx')];
      final files = await picker.pickFiles();
      expect(files.map((f) => f.originalFileName), [
        'second.PDF',
        'first.xlsx',
      ]);
      expect(platform.type, FileType.custom);
      expect(
        platform.extensions,
        SupplierSourceUploadCandidate.contentTypesByExtension.keys,
      );
      expect(files.map((f) => f.bytes.length), [2, 2]);
      expect(() => files.clear(), throwsUnsupportedError);
    },
  );
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
    platform.files = [_File('x.pdf', size: null)];
    expect((await picker.pickFiles()).single.sizeBytes, 2);
  });
  test('size changing while reading is rejected', () async {
    platform.files = [_File('x.pdf', size: 3)];
    await expectLater(
      picker.pickFiles(),
      throwsA(isA<SupplierSourceUploadFailure>()),
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
}

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
  _File(this.name, {this.size = 2});
  @override
  final String name;
  final int? size;
  int reads = 0;
  @override
  Uri get uri => Uri.parse('memory:test');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  Stream<Uint8List> readAsByteStream() => throw UnimplementedError();
  @override
  int? lengthSync() => size;
  @override
  Future<int?> length() async => size;
  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return Uint8List.fromList([1, 2]);
  }
}
