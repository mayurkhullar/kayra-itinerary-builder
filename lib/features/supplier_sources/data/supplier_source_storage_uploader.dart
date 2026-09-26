import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

abstract interface class SupplierSourceStorageUploader {
  Future<void> upload({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
    required void Function(int transferred, int total) onProgress,
  });
}

/// Supplier Source putData only; no public download URLs or client deletes.
final class FirebaseSupplierSourceStorageUploader
    implements SupplierSourceStorageUploader {
  FirebaseSupplierSourceStorageUploader({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<void> upload({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
    required void Function(int transferred, int total) onProgress,
  }) async {
    // Browser/file-picker bytes can be backed by typed-data views that do not
    // cross firebase_storage_web's `data.toJS` boundary reliably. Give the
    // Firebase adapter a fresh, owned Uint8List with identical contents.
    final normalizedBytes = Uint8List.fromList(bytes);
    final task = _storage
        .ref(storagePath)
        .putData(
          normalizedBytes,
          SettableMetadata(
            contentType: contentType,
            customMetadata: customMetadata,
          ),
        );
    final subscription = task.snapshotEvents.listen(
      (snapshot) => onProgress(snapshot.bytesTransferred, snapshot.totalBytes),
      // Awaiting the task is authoritative for failure; avoid a second unhandled
      // error from the progress stream.
      onError: (Object _) {},
    );
    try {
      final snapshot = await task;
      onProgress(snapshot.bytesTransferred, snapshot.totalBytes);
    } finally {
      await subscription.cancel();
    }
  }
}
