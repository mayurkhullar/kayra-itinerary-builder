import 'package:cloud_functions/cloud_functions.dart';

abstract interface class SupplierSourceCleanupClient {
  Future<void> cleanup({
    required String tripId,
    required String packageId,
    required String sourceFileId,
    required String fileName,
  });
}

final class CallableSupplierSourceCleanupClient
    implements SupplierSourceCleanupClient {
  CallableSupplierSourceCleanupClient({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south2');

  final FirebaseFunctions _functions;

  @override
  Future<void> cleanup({
    required String tripId,
    required String packageId,
    required String sourceFileId,
    required String fileName,
  }) async {
    final response = await _functions
        .httpsCallable('cleanupSupplierSourceUpload')
        .call<Object?>({
          'tripId': tripId,
          'packageId': packageId,
          'sourceFileId': sourceFileId,
          'fileName': fileName,
        });
    final data = response.data;
    if (data is! Map ||
        data.length != 3 ||
        data['cleaned'] != true ||
        data['storageDeleted'] is! bool ||
        data['metadataDeleted'] is! bool) {
      throw const FormatException('Unconfirmed source cleanup result.');
    }
  }
}
