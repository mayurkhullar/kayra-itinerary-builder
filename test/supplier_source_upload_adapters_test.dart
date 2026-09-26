import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_cleanup_client.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_storage_uploader.dart';

void main() {
  test(
    'Storage adapter normalizes bytes and preserves metadata and progress',
    () async {
      final storage = _Storage();
      final uploader = FirebaseSupplierSourceStorageUploader(storage: storage);
      final progress = <(int, int)>[];
      final backingBytes = Uint8List.fromList([9, 1, 2, 8]);
      final candidateBytes = Uint8List.sublistView(
        backingBytes,
        1,
        3,
      ).asUnmodifiableView();
      final result = uploader.upload(
        storagePath: 'trips/t/supplier_sources/f/quote.pdf',
        bytes: candidateBytes,
        contentType: 'application/pdf',
        customMetadata: {'packageId': 'p', 'uploadedByUid': 'u'},
        onProgress: (bytes, total) => progress.add((bytes, total)),
      );
      final uploadedBytes = storage.reference.bytes;
      expect(uploadedBytes, isA<Uint8List>());
      expect(identical(uploadedBytes, candidateBytes), isFalse);
      expect(uploadedBytes, [1, 2]);
      expect(uploadedBytes, hasLength(candidateBytes.length));
      backingBytes[1] = 7;
      expect(uploadedBytes, [1, 2]);
      storage.task.events.add(_Snapshot(1, 2));
      await Future<void>.delayed(Duration.zero);
      storage.task.done.complete(_Snapshot(2, 2));
      await result;
      expect(storage.path, 'trips/t/supplier_sources/f/quote.pdf');
      expect(storage.reference.bytes, [1, 2]);
      expect(storage.reference.metadata!.contentType, 'application/pdf');
      expect(storage.reference.metadata!.customMetadata, {
        'packageId': 'p',
        'uploadedByUid': 'u',
      });
      expect(progress, [(1, 2), (2, 2)]);
      expect(storage.reference.downloadUrlCalls, 0);
      expect(storage.task.events.hasListener, isFalse);
      await storage.task.events.close();
    },
  );
  test(
    'Storage adapter awaits task failure and releases progress subscription',
    () async {
      final storage = _Storage();
      final result = FirebaseSupplierSourceStorageUploader(storage: storage)
          .upload(
            storagePath: 'path',
            bytes: Uint8List(1),
            contentType: 'text/plain',
            customMetadata: {},
            onProgress: (_, _) {},
          );
      final assertion = expectLater(result, throwsStateError);
      storage.task.events.addError(StateError('SDK progress failure'));
      storage.task.done.completeError(StateError('SDK task failure'));
      await assertion;
      expect(storage.task.events.hasListener, isFalse);
      await storage.task.events.close();
    },
  );
  test('callable adapter uses the exact name and four-field payload', () async {
    final functions = _Functions();
    await CallableSupplierSourceCleanupClient(functions: functions).cleanup(
      tripId: 't',
      packageId: 'p',
      sourceFileId: 'f',
      fileName: 'quote.pdf',
    );
    expect(functions.name, 'cleanupSupplierSourceUpload');
    expect(functions.callable.parameters, {
      'tripId': 't',
      'packageId': 'p',
      'sourceFileId': 'f',
      'fileName': 'quote.pdf',
    });
  });
  for (final response in <Object?>[
    null,
    true,
    'cleaned',
    {},
    {'cleaned': false, 'storageDeleted': true, 'metadataDeleted': true},
    {'cleaned': true, 'storageDeleted': 'true', 'metadataDeleted': true},
    {'cleaned': true, 'storageDeleted': true},
    {
      'cleaned': true,
      'storageDeleted': true,
      'metadataDeleted': true,
      'unexpected': 'data',
    },
  ]) {
    test('callable rejects unconfirmed/malformed result: $response', () async {
      final functions = _Functions()..callable.response = response;
      await expectLater(
        CallableSupplierSourceCleanupClient(functions: functions).cleanup(
          tripId: 't',
          packageId: 'p',
          sourceFileId: 'f',
          fileName: 'quote.pdf',
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'already absent object and metadata is a valid successful cleanup',
    () async {
      final functions = _Functions()
        ..callable.response = {
          'cleaned': true,
          'storageDeleted': false,
          'metadataDeleted': false,
        };
      await CallableSupplierSourceCleanupClient(functions: functions).cleanup(
        tripId: 't',
        packageId: 'p',
        sourceFileId: 'f',
        fileName: 'quote.pdf',
      );
    },
  );
}

class _Storage extends Fake implements FirebaseStorage {
  final task = _Task();
  late final reference = _Reference(task);
  String? path;
  @override
  Reference ref([String? path]) {
    this.path = path;
    return reference;
  }
}

class _Reference extends Fake implements Reference {
  _Reference(this.task);
  final _Task task;
  Uint8List? bytes;
  SettableMetadata? metadata;
  int downloadUrlCalls = 0;
  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    bytes = data;
    this.metadata = metadata;
    return task;
  }

  @override
  Future<String> getDownloadURL() async {
    downloadUrlCalls += 1;
    return 'https://example.invalid/source';
  }
}

class _Task extends Fake implements UploadTask {
  final done = Completer<TaskSnapshot>();
  final events = StreamController<TaskSnapshot>();
  @override
  Stream<TaskSnapshot> get snapshotEvents => events.stream;
  @override
  Future<R> then<R>(
    FutureOr<R> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => done.future.then(onValue, onError: onError);
}

class _Snapshot extends Fake implements TaskSnapshot {
  _Snapshot(this.bytesTransferred, this.totalBytes);
  @override
  final int bytesTransferred;
  @override
  final int totalBytes;
}

class _Functions extends Fake implements FirebaseFunctions {
  final callable = _Callable();
  String? name;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    this.name = name;
    return callable;
  }
}

class _Callable extends Fake implements HttpsCallable {
  Object? parameters;
  Object? response = {
    'cleaned': true,
    'storageDeleted': true,
    'metadataDeleted': true,
  };
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    this.parameters = parameters;
    return _Result<T>(response as T);
  }
}

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}
