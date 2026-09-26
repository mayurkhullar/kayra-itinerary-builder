import 'supplier_source_cleanup_client.dart';
import 'supplier_source_file_picker.dart';
import 'supplier_source_repository.dart';
import 'supplier_source_storage_uploader.dart';
import 'supplier_source_upload_service.dart';

final class SupplierSourceUploadDependencies {
  const SupplierSourceUploadDependencies({
    required this.picker,
    required this.executor,
  });

  factory SupplierSourceUploadDependencies.firebase({
    required SupplierSourceRepository repository,
  }) => SupplierSourceUploadDependencies(
    picker: PlatformSupplierSourceFilePicker(),
    executor: SupplierSourceUploadService(
      repository: repository,
      storage: FirebaseSupplierSourceStorageUploader(),
      cleanup: CallableSupplierSourceCleanupClient(),
    ),
  );

  final SupplierSourceFilePicker picker;
  final SupplierSourceUploadExecutor executor;
}
