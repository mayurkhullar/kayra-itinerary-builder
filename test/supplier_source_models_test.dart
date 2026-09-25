import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_file.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';

final _time = DateTime.utc(2026, 9, 25);

SupplierSourcePackage _package({
  List<String> fileIds = const [],
  SupplierSourcePackageStatus status = SupplierSourcePackageStatus.uploading,
  String? supplierId,
  String? supplierNameSnapshot,
}) => SupplierSourcePackage(
  id: 'package-1',
  tripId: 'trip-1',
  fileIds: fileIds,
  status: status,
  supplierId: supplierId,
  supplierNameSnapshot: supplierNameSnapshot,
  uploadedByUid: 'agent-1',
  createdAt: _time,
  updatedAt: _time,
);

SupplierSourceFile _file({
  String originalFileName = 'Supplier quote.pdf',
  String contentType = 'application/pdf',
  int sizeBytes = 1024,
  String storagePath = 'trips/trip-1/supplier_sources/file-1/quote.pdf',
}) => SupplierSourceFile(
  id: 'file-1',
  tripId: 'trip-1',
  packageId: 'package-1',
  originalFileName: originalFileName,
  storagePath: storagePath,
  contentType: contentType,
  sizeBytes: sizeBytes,
  uploadedByUid: 'agent-1',
  createdAt: _time,
);

SupplierSourcePackage _parsePackage(Map<String, Object?> data) =>
    SupplierSourcePackage.fromMap(
      data,
      documentId: 'package-1',
      expectedTripId: 'trip-1',
    );

SupplierSourceFile _parseFile(Map<String, Object?> data) =>
    SupplierSourceFile.fromMap(
      data,
      documentId: 'file-1',
      expectedTripId: 'trip-1',
    );

void main() {
  test('new package is uploading with unresolved Supplier and no files', () {
    final package = SupplierSourcePackage(
      id: 'package-1',
      tripId: 'trip-1',
      uploadedByUid: 'agent-1',
      createdAt: _time,
      updatedAt: _time,
    );
    expect(package.status, SupplierSourcePackageStatus.uploading);
    expect(package.supplierId, isNull);
    expect(package.supplierNameSnapshot, isNull);
    expect(package.fileIds, isEmpty);
    expect(_parsePackage(package.toMap()).toMap(), package.toMap());
    expect(package.toMap().containsKey('id'), isFalse);
  });

  test('known Supplier identity and name snapshot survive round trip', () {
    final package = _package(
      supplierId: 'supplier-1',
      supplierNameSnapshot: 'Example DMC',
    );
    final parsed = _parsePackage(package.toMap());
    expect(parsed.supplierId, 'supplier-1');
    expect(parsed.supplierNameSnapshot, 'Example DMC');
  });

  test(
    'file order is preserved and immutable including input/map mutations',
    () {
      final input = ['file-3', 'file-1', 'file-2'];
      final package = _package(fileIds: input);
      input.clear();
      expect(package.fileIds, ['file-3', 'file-1', 'file-2']);
      expect(() => package.fileIds.clear(), throwsUnsupportedError);
      final map = package.toMap();
      (map['fileIds'] as List).clear();
      expect(package.fileIds, hasLength(3));
      expect(_parsePackage(package.toMap()).fileIds, package.fileIds);
    },
  );

  for (final ids in <List<String>>[
    ['same', 'same'],
    [''],
    [' '],
    ['x/y'],
    ['.'],
    ['..'],
    [' a'],
  ]) {
    test('rejects invalid or duplicate package file IDs: $ids', () {
      expect(() => _package(fileIds: ids), throwsFormatException);
      expect(
        () => _parsePackage({..._package().toMap(), 'fileIds': ids}),
        throwsFormatException,
      );
    });
  }

  test('uploaded requires files, failed accepts empty or partial files', () {
    expect(
      () => _package(status: SupplierSourcePackageStatus.uploaded),
      throwsFormatException,
    );
    for (final status in SupplierSourcePackageStatus.values) {
      final parsed = _parsePackage(
        _package(status: status, fileIds: ['file-1']).toMap(),
      );
      expect(parsed.status, status);
      expect(parsed.status.value, status.name);
    }
    expect(
      _parsePackage(
        _package(status: SupplierSourcePackageStatus.failed).toMap(),
      ).status,
      SupplierSourcePackageStatus.failed,
    );
  });

  for (final link in [
    (id: 'supplier-1', name: null),
    (id: null, name: 'Example DMC'),
    (id: '', name: 'Example DMC'),
    (id: 'supplier-1', name: ' '),
  ]) {
    test('rejects incomplete or blank Supplier linkage: $link', () {
      expect(
        () => _package(supplierId: link.id, supplierNameSnapshot: link.name),
        throwsFormatException,
      );
    });
  }

  // Explicit expectations independently cover the Storage rules allowlist.
  const contentTypes = [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv',
    'text/plain',
    'image/jpeg',
    'image/png',
    'image/webp',
  ];
  for (final type in contentTypes) {
    test('accepts and round-trips $type metadata', () {
      final file = _file(contentType: type);
      final parsed = _parseFile(file.toMap());
      expect(parsed.contentType, type);
      expect(parsed.toMap(), file.toMap());
      expect(parsed.id, 'file-1');
      expect(parsed.originalFileName, 'Supplier quote.pdf');
      expect(parsed.createdAt.isUtc, isTrue);
      expect(
        file.toMap().keys,
        unorderedEquals([
          'tripId',
          'packageId',
          'originalFileName',
          'storagePath',
          'contentType',
          'sizeBytes',
          'uploadedByUid',
          'createdAt',
        ]),
      );
    });
  }
  for (final type in [
    '',
    'application/zip',
    'image/gif',
    'text/plain; charset=utf-8',
  ]) {
    test('rejects unsupported MIME $type', () {
      expect(() => _file(contentType: type), throwsFormatException);
    });
  }
  for (final size in [-1, 0, 25 * 1024 * 1024 + 1]) {
    test('rejects size $size', () {
      expect(() => _file(sizeBytes: size), throwsFormatException);
    });
  }
  test('accepts exactly 25 MB and one byte', () {
    expect(_file(sizeBytes: 25 * 1024 * 1024).sizeBytes, 26214400);
    expect(_file(sizeBytes: 1).sizeBytes, 1);
  });
  for (final name in ['', '  ', '\n']) {
    test('original filename required: $name', () {
      expect(() => _file(originalFileName: name), throwsFormatException);
    });
  }
  test(
    'Storage path uses Trip and generated file identity without rewriting name',
    () {
      expect(
        SupplierSourceFile.buildStoragePath(
          tripId: 'trip-1',
          fileId: 'generated-42',
          storageFileName: 'Quote 01.pdf',
        ),
        'trips/trip-1/supplier_sources/generated-42/Quote 01.pdf',
      );
    },
  );
  for (final name in ['', ' ', 'a/b.pdf', '.', '..', ' a.pdf']) {
    test('rejects invalid Storage filename segment: $name', () {
      expect(
        () => SupplierSourceFile.buildStoragePath(
          tripId: 'trip-1',
          fileId: 'file-1',
          storageFileName: name,
        ),
        throwsFormatException,
      );
    });
  }
  for (final path in [
    'trips/other/supplier_sources/file-1/quote.pdf',
    'trips/trip-1/supplier_sources/other/quote.pdf',
    'trips/trip-1/supplier_sources/file-1/nested/quote.pdf',
    'trips/trip-1/supplier_sources/file-1/',
    'https://example.com/quote.pdf',
  ]) {
    test('rejects mismatched or nested Storage path: $path', () {
      expect(() => _file(storagePath: path), throwsFormatException);
    });
  }

  test(
    'package parsing rejects missing, extra, mistyped and malformed data',
    () {
      final valid = _package().toMap();
      final invalid = [
        for (final key in valid.keys)
          Map<String, Object?>.of(valid)..remove(key),
        for (final patch in <Map<String, Object?>>[
          {'id': 'invented'},
          {'tripId': 'other'},
          {'tripId': 1},
          {'uploadedByUid': ''},
          {'uploadedByUid': null},
          {'supplierId': 1},
          {'supplierNameSnapshot': 3},
          {'fileIds': 'file-1'},
          {
            'fileIds': [1],
          },
          {'status': null},
          {'status': 'extracting'},
          {'status': 'uploaded'},
          {'createdAt': '2026-09-25'},
          {'updatedAt': null},
        ])
          {...valid, ...patch},
      ];
      for (final record in invalid) {
        expect(
          () => _parsePackage(record),
          throwsFormatException,
          reason: '$record',
        );
      }
    },
  );
  test('file parsing rejects missing, extra, mistyped and malformed data', () {
    final valid = _file().toMap();
    final invalid = [
      for (final key in valid.keys) Map<String, Object?>.of(valid)..remove(key),
      for (final patch in <Map<String, Object?>>[
        {'updatedAt': _time},
        {'downloadUrl': 'https://example.com'},
        {'tripId': 'other'},
        {'tripId': null},
        {'packageId': ''},
        {'uploadedByUid': ' '},
        {'originalFileName': ''},
        {'originalFileName': 1},
        {'storagePath': null},
        {'contentType': 'invalid'},
        {'sizeBytes': -1},
        {'sizeBytes': 0},
        {'sizeBytes': 26214401},
        {'sizeBytes': 1.5},
        {'sizeBytes': '1'},
        {'createdAt': null},
      ])
        {...valid, ...patch},
    ];
    for (final record in invalid) {
      expect(
        () => _parseFile(record),
        throwsFormatException,
        reason: '$record',
      );
    }
  });
  for (final id in ['', ' ', 'a/b', '.', '..']) {
    test('document identities are validated: $id', () {
      expect(
        () => SupplierSourcePackage.fromMap(
          _package().toMap(),
          documentId: id,
          expectedTripId: 'trip-1',
        ),
        throwsFormatException,
      );
      expect(
        () => SupplierSourceFile.fromMap(
          _file().toMap(),
          documentId: id,
          expectedTripId: 'trip-1',
        ),
        throwsFormatException,
      );
    });
  }
}
