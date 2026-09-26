import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_repository.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_file.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_package.dart';

class FakeSupplierSourceRepository implements SupplierSourceRepository {
  final packages = <SupplierSourcePackage>[];
  final packageQueries = <String>[];
  Future<void> Function()? beforePackageList;
  Object? packageListError;

  @override
  Future<List<SupplierSourcePackage>> listPackagesForTrip(String tripId) async {
    packageQueries.add(tripId);
    await beforePackageList?.call();
    if (packageListError != null) throw packageListError!;
    return packages.where((package) => package.tripId == tripId).toList();
  }

  @override
  Future<String> createPackage({
    required String tripId,
    required String currentUserUid,
    String? supplierId,
    String? supplierNameSnapshot,
    void Function(String id)? onIdentityAllocated,
  }) => throw UnimplementedError();

  @override
  Future<String> createFileMetadata({
    required String tripId,
    required String packageId,
    required String originalFileName,
    required String storageFileName,
    required String contentType,
    required int sizeBytes,
    required String currentUserUid,
    void Function(String id)? onIdentityAllocated,
  }) => throw UnimplementedError();

  @override
  Future<SupplierSourcePackage?> getPackage(String tripId, String packageId) =>
      throw UnimplementedError();

  @override
  Future<SupplierSourceFile?> getFile(String tripId, String fileId) =>
      throw UnimplementedError();

  @override
  Future<List<SupplierSourceFile>> listFilesForPackage(
    String tripId,
    String packageId,
  ) => throw UnimplementedError();

  @override
  Future<void> updatePackageAfterUpload({
    required String tripId,
    required String packageId,
    required List<String> fileIds,
    required SupplierSourcePackageStatus status,
  }) => throw UnimplementedError();
}
