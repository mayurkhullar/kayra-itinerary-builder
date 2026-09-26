import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_cleanup_client.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_repository.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_storage_uploader.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_upload_service.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_candidate.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_failure.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_progress.dart';

SupplierSourceUploadCandidate _candidate(String name) =>
    SupplierSourceUploadCandidate(
      originalFileName: name,
      bytes: Uint8List.fromList([1, 2, 3]),
    );

void main() {
  late _Repository repository;
  late _Storage storage;
  late _Cleanup cleanup;
  late SupplierSourceUploadService service;
  late List<String> events;
  late List<SupplierSourceUploadProgress> progress;
  setUp(() {
    events = [];
    progress = [];
    repository = _Repository(events);
    storage = _Storage(events);
    cleanup = _Cleanup(events, repository);
    service = SupplierSourceUploadService(
      repository: repository,
      storage: storage,
      cleanup: cleanup,
    );
  });

  Future<CompletedSupplierSourceUpload> upload({
    List<SupplierSourceUploadCandidate>? files,
  }) => service.upload(
    tripId: 'trip',
    uploadedByUid: 'agent',
    candidates: files ?? [_candidate('second.PDF'), _candidate('first.txt')],
    onProgress: progress.add,
  );

  Future<SupplierSourceUploadFailure> failure(Future<Object> future) async {
    try {
      await future;
      fail('Expected failure');
    } on SupplierSourceUploadFailure catch (error) {
      return error;
    }
  }

  test('empty selection rejected before any repository write', () async {
    expect(
      (await failure(upload(files: []))).kind,
      SupplierSourceUploadFailureKind.validation,
    );
    expect(events, isEmpty);
    expect(progress.map((p) => p.state), [
      SupplierSourceUploadState.validating,
      SupplierSourceUploadState.failed,
    ]);
  });
  for (final id in ['', 'a/b', r'a\b', 'a\u0000b', '..', ' a']) {
    test('invalid rollback identity rejected before writes: $id', () async {
      final error = await failure(
        service.upload(
          tripId: id,
          uploadedByUid: 'agent',
          candidates: [_candidate('x.pdf')],
        ),
      );
      expect(error.kind, SupplierSourceUploadFailureKind.validation);
      expect(events, isEmpty);
    });
  }
  test('invalid supplier linkage rejected before writes', () async {
    final error = await failure(
      service.upload(
        tripId: 'trip',
        uploadedByUid: 'agent',
        candidates: [_candidate('x.pdf')],
        supplierId: 'supplier',
      ),
    );
    expect(error.kind, SupplierSourceUploadFailureKind.validation);
    expect(events, isEmpty);
  });
  test(
    'successful sequence, canonical paths, MIME, identity and selected order',
    () async {
      final result = await upload();
      expect(events, [
        'package',
        'allocate:f1',
        'metadata:f1',
        'upload:f1',
        'allocate:f2',
        'metadata:f2',
        'upload:f2',
        'complete:uploaded',
      ]);
      expect(result.packageId, 'package');
      expect(result.tripId, 'trip');
      expect(result.fileIds, ['f1', 'f2']);
      expect(() => result.fileIds.clear(), throwsUnsupportedError);
      expect(repository.completedIds, ['f1', 'f2']);
      expect(repository.status, SupplierSourcePackageStatus.uploaded);
      expect(repository.records.first, {
        'tripId': 'trip',
        'packageId': 'package',
        'originalFileName': 'second.PDF',
        'storageFileName': 'second.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 3,
        'currentUserUid': 'agent',
      });
      expect(storage.uploads.map((u) => u.path), [
        'trips/trip/supplier_sources/f1/second.pdf',
        'trips/trip/supplier_sources/f2/first.txt',
      ]);
      expect(storage.uploads.map((u) => u.mime), [
        'application/pdf',
        'text/plain',
      ]);
      for (final record in storage.uploads) {
        expect(record.metadata, {
          'packageId': 'package',
          'uploadedByUid': 'agent',
        });
        expect(record.bytes, [1, 2, 3]);
      }
      expect(cleanup.calls, isEmpty);
    },
  );
  test('known supplier linkage passed through without lookup', () async {
    await service.upload(
      tripId: 'trip',
      uploadedByUid: 'agent',
      candidates: [_candidate('x.pdf')],
      supplierId: 'supplier',
      supplierNameSnapshot: 'DMC',
    );
    expect(repository.supplierId, 'supplier');
    expect(repository.supplierName, 'DMC');
  });
  test(
    'sequential uploads await completion before creating next metadata',
    () async {
      final barrier = Completer<void>();
      storage.wait = barrier.future;
      final result = upload();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['package', 'allocate:f1', 'metadata:f1', 'upload:f1']);
      expect(repository.status, SupplierSourcePackageStatus.uploading);
      barrier.complete();
      await result;
      expect(storage.maxActive, 1);
    },
  );
  test('progress states and per-file byte identity are meaningful', () async {
    await upload();
    expect(progress.first.state, SupplierSourceUploadState.validating);
    expect(progress[1].state, SupplierSourceUploadState.preparing);
    expect(
      progress[progress.length - 2].state,
      SupplierSourceUploadState.finalizing,
    );
    expect(progress.last.state, SupplierSourceUploadState.completed);
    expect(progress.every((p) => p.totalFiles == 2), isTrue);
    final uploading = progress
        .where((p) => p.state == SupplierSourceUploadState.uploading)
        .toList();
    expect(uploading.map((p) => p.currentFileIndex), [0, 0, 0, 1, 1, 1]);
    expect(uploading.map((p) => p.bytesTransferred), [0, 1, 3, 0, 1, 3]);
    expect(
      uploading.take(3).map((p) => p.currentFileName),
      everyElement('second.PDF'),
    );
    expect(
      uploading.skip(3).map((p) => p.currentFileName),
      everyElement('first.txt'),
    );
    expect(uploading.map((p) => p.totalBytes), everyElement(3));
  });
  test(
    'progress observer exceptions cannot abort persistence or completion',
    () async {
      await service.upload(
        tripId: 'trip',
        uploadedByUid: 'agent',
        candidates: [_candidate('x.pdf')],
        onProgress: (_) => throw StateError('view disposed'),
      );
      expect(repository.status, SupplierSourcePackageStatus.uploaded);
      expect(cleanup.calls, isEmpty);
    },
  );
  test(
    'caller selection mutation cannot change an in-flight package',
    () async {
      final files = [_candidate('one.pdf')];
      await service.upload(
        tripId: 'trip',
        uploadedByUid: 'agent',
        candidates: files,
        onProgress: (_) => files.clear(),
      );
      expect(repository.completedIds, ['f1']);
    },
  );
  for (final failAt in [1, 2]) {
    test('upload $failAt failure cleans every allocated attempt', () async {
      storage.failAt = failAt;
      final error = await failure(upload());
      expect(error.kind, SupplierSourceUploadFailureKind.upload);
      expect(
        cleanup.calls.map((c) => c.sourceFileId),
        failAt == 1 ? ['f1'] : ['f1', 'f2'],
      );
      expect(repository.status, SupplierSourcePackageStatus.failed);
      expect(events, isNot(contains('complete:uploaded')));
      expect(progress.last.state, SupplierSourceUploadState.failed);
      expect(
        progress.any((p) => p.state == SupplierSourceUploadState.rollingBack),
        isTrue,
      );
      expect(error.toString(), isNot(contains('private')));
    });
  }
  test(
    'rollback continues after cleanup failure and reports unresolved identities',
    () async {
      storage.failAt = 2;
      cleanup.failIds.add('f1');
      final error = await failure(upload());
      expect(cleanup.calls.map((c) => c.sourceFileId), ['f1', 'f2']);
      expect(error.kind, SupplierSourceUploadFailureKind.rollbackIncomplete);
      expect(error.originalKind, SupplierSourceUploadFailureKind.upload);
      expect(error.cleanupFailedFileIds, ['f1']);
      expect(error.packageId, 'package');
      expect(() => error.cleanupFailedFileIds.clear(), throwsUnsupportedError);
    },
  );
  test('metadata write failure still cleans its allocated identity', () async {
    repository.metadataFailAt = 2;
    final error = await failure(upload());
    expect(error.kind, SupplierSourceUploadFailureKind.upload);
    expect(storage.uploads, hasLength(1));
    expect(cleanup.calls.map((c) => c.sourceFileId), ['f1', 'f2']);
  });
  test('first metadata write failure cleans even an absent object', () async {
    repository.metadataFailAt = 1;
    await failure(upload());
    expect(storage.uploads, isEmpty);
    expect(cleanup.calls.map((c) => c.sourceFileId), ['f1']);
  });
  test(
    'failure before a file identity leaves already failed package immutable',
    () async {
      repository.failBeforeAllocation = true;
      repository.status = SupplierSourcePackageStatus.failed;
      await failure(upload());
      expect(events, ['package', 'get-package']);
      expect(cleanup.calls, isEmpty);
    },
  );
  test(
    'allocated package whose write never persisted requires no update',
    () async {
      repository.failPackageAfterWrite = true;
      repository.packageExists = false;
      final error = await failure(upload());
      expect(error.kind, SupplierSourceUploadFailureKind.packagePreparation);
      expect(events, ['package', 'get-package']);
      expect(cleanup.calls, isEmpty);
    },
  );
  test(
    'first metadata failure before allocation marks package failed directly',
    () async {
      repository.failBeforeAllocation = true;
      expect(
        (await failure(upload())).kind,
        SupplierSourceUploadFailureKind.upload,
      );
      expect(cleanup.calls, isEmpty);
      expect(repository.status, SupplierSourcePackageStatus.failed);
      expect(events, ['package', 'get-package', 'complete:failed']);
    },
  );
  test(
    'failed direct package failure is reported as rollback incomplete',
    () async {
      repository.failBeforeAllocation = true;
      repository.failOutcome = SupplierSourcePackageStatus.failed;
      final error = await failure(upload());
      expect(error.kind, SupplierSourceUploadFailureKind.rollbackIncomplete);
      expect(error.packageFailureUnconfirmed, isTrue);
      expect(cleanup.calls, isEmpty);
    },
  );
  test('package creation failure before identity needs no cleanup', () async {
    repository.failPackageBeforeAllocation = true;
    expect(
      (await failure(upload())).kind,
      SupplierSourceUploadFailureKind.packagePreparation,
    );
    expect(cleanup.calls, isEmpty);
    expect(events, ['package']);
  });
  test(
    'ambiguous package creation failure retains ID and fails persisted package',
    () async {
      repository.failPackageAfterWrite = true;
      final error = await failure(upload());
      expect(error.kind, SupplierSourceUploadFailureKind.packagePreparation);
      expect(error.packageId, 'package');
      expect(repository.status, SupplierSourcePackageStatus.failed);
      expect(cleanup.calls, isEmpty);
    },
  );
  test('unconfirmed package existence reports unresolved rollback', () async {
    repository.failPackageAfterWrite = true;
    repository.failRead = true;
    final error = await failure(upload());
    expect(error.kind, SupplierSourceUploadFailureKind.rollbackIncomplete);
    expect(error.packageFailureUnconfirmed, isTrue);
  });
  test('completion failure rolls back all uploaded sources', () async {
    repository.failOutcome = SupplierSourcePackageStatus.uploaded;
    final error = await failure(upload());
    expect(error.kind, SupplierSourceUploadFailureKind.finalization);
    expect(cleanup.calls.map((c) => c.sourceFileId), ['f1', 'f2']);
    expect(repository.status, SupplierSourcePackageStatus.failed);
  });
  test(
    'ambiguous committed completion is never reopened or directly deleted',
    () async {
      repository.failAfterCompletion = true;
      final error = await failure(upload());
      expect(error.kind, SupplierSourceUploadFailureKind.rollbackIncomplete);
      expect(error.originalKind, SupplierSourceUploadFailureKind.finalization);
      expect(cleanup.calls, hasLength(2));
      expect(repository.status, SupplierSourcePackageStatus.uploaded);
      expect(error.cleanupFailedFileIds, ['f1', 'f2']);
    },
  );
  test(
    'cleanup receives storage filename, never original name or full path',
    () async {
      storage.failAt = 1;
      await failure(upload(files: [_candidate(r'../folder\quote..PDF.pdf')]));
      expect(cleanup.calls.single.fileName, '__folder_quote_PDF.pdf');
      expect(cleanup.calls.single.tripId, 'trip');
      expect(cleanup.calls.single.packageId, 'package');
    },
  );
}

class _Repository extends Fake implements SupplierSourceRepository {
  _Repository(this.events);
  final List<String> events;
  final records = <Map<String, Object?>>[];
  List<String> completedIds = [];
  SupplierSourcePackageStatus status = SupplierSourcePackageStatus.uploading;
  String? supplierId;
  String? supplierName;
  bool failPackageBeforeAllocation = false;
  bool failPackageAfterWrite = false;
  bool failBeforeAllocation = false;
  bool failRead = false;
  bool packageExists = true;
  bool failAfterCompletion = false;
  int? metadataFailAt;
  SupplierSourcePackageStatus? failOutcome;

  @override
  Future<String> createPackage({
    required String tripId,
    required String currentUserUid,
    String? supplierId,
    String? supplierNameSnapshot,
    void Function(String)? onIdentityAllocated,
  }) async {
    events.add('package');
    if (failPackageBeforeAllocation) throw StateError('private failure');
    onIdentityAllocated?.call('package');
    this.supplierId = supplierId;
    supplierName = supplierNameSnapshot;
    if (failPackageAfterWrite) throw StateError('private ambiguous failure');
    return 'package';
  }

  @override
  Future<String> createFileMetadata({
    required String tripId,
    required String packageId,
    required String originalFileName,
    required String storageFileName,
    required String contentType,
    required int sizeBytes,
    required String currentUserUid,
    void Function(String)? onIdentityAllocated,
  }) async {
    if (failBeforeAllocation) throw StateError('private metadata failure');
    final id = 'f${records.length + 1}';
    events.add('allocate:$id');
    onIdentityAllocated?.call(id);
    records.add({
      'tripId': tripId,
      'packageId': packageId,
      'originalFileName': originalFileName,
      'storageFileName': storageFileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'currentUserUid': currentUserUid,
    });
    events.add('metadata:$id');
    if (metadataFailAt == records.length) {
      throw StateError('private metadata failure');
    }
    return id;
  }

  @override
  Future<SupplierSourcePackage?> getPackage(
    String tripId,
    String packageId,
  ) async {
    events.add('get-package');
    if (failRead) throw StateError('private read failure');
    if (!packageExists) return null;
    return SupplierSourcePackage(
      id: packageId,
      tripId: tripId,
      uploadedByUid: 'agent',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      status: status,
      fileIds: completedIds,
    );
  }

  @override
  Future<void> updatePackageAfterUpload({
    required String tripId,
    required String packageId,
    required List<String> fileIds,
    required SupplierSourcePackageStatus status,
  }) async {
    events.add('complete:${status.value}');
    if (status == failOutcome) throw StateError('private completion failure');
    this.status = status;
    completedIds = List.of(fileIds);
    if (failAfterCompletion) throw StateError('private ambiguous completion');
  }
}

class _Storage implements SupplierSourceStorageUploader {
  _Storage(this.events);
  final List<String> events;
  final uploads =
      <
        ({
          String path,
          Uint8List bytes,
          String mime,
          Map<String, String> metadata,
        })
      >[];
  int? failAt;
  Future<void>? wait;
  int active = 0;
  int maxActive = 0;
  @override
  Future<void> upload({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
    required void Function(int, int) onProgress,
  }) async {
    active++;
    if (active > maxActive) maxActive = active;
    events.add('upload:${storagePath.split('/')[3]}');
    uploads.add((
      path: storagePath,
      bytes: bytes,
      mime: contentType,
      metadata: customMetadata,
    ));
    onProgress(1, bytes.length);
    await wait;
    active--;
    if (uploads.length == failAt) throw StateError('private upload failure');
    onProgress(bytes.length, bytes.length);
  }
}

class _Cleanup implements SupplierSourceCleanupClient {
  _Cleanup(this.events, this.repository);
  final List<String> events;
  final _Repository repository;
  final failIds = <String>{};
  final calls =
      <
        ({
          String tripId,
          String packageId,
          String sourceFileId,
          String fileName,
        })
      >[];
  @override
  Future<void> cleanup({
    required String tripId,
    required String packageId,
    required String sourceFileId,
    required String fileName,
  }) async {
    events.add('cleanup:$sourceFileId');
    calls.add((
      tripId: tripId,
      packageId: packageId,
      sourceFileId: sourceFileId,
      fileName: fileName,
    ));
    if (failIds.contains(sourceFileId) ||
        repository.status == SupplierSourcePackageStatus.uploaded) {
      throw StateError('private cleanup failure');
    }
    repository.status = SupplierSourcePackageStatus.failed;
  }
}
