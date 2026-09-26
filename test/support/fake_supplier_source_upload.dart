import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_file_picker.dart';
import 'package:kayra_crm_v1/features/supplier_sources/data/supplier_source_upload_service.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_candidate.dart';
import 'package:kayra_crm_v1/features/supplier_sources/domain/supplier_source_upload_progress.dart';

class FakeSupplierSourceFilePicker implements SupplierSourceFilePicker {
  final selections = <List<SupplierSourceUploadCandidate>>[];
  int calls = 0;
  Object? error;

  @override
  Future<List<SupplierSourceUploadCandidate>> pickFiles() async {
    calls++;
    if (error != null) throw error!;
    if (selections.isEmpty) return const [];
    return selections.removeAt(0);
  }
}

typedef FakeUploadCall = ({
  String tripId,
  String uploadedByUid,
  List<SupplierSourceUploadCandidate> candidates,
  String? supplierId,
  String? supplierNameSnapshot,
});

class FakeSupplierSourceUploadExecutor implements SupplierSourceUploadExecutor {
  final calls = <FakeUploadCall>[];
  Future<CompletedSupplierSourceUpload> Function(FakeUploadCall call)? handler;
  void Function(SupplierSourceUploadProgress progress)? _onProgress;

  void emit(SupplierSourceUploadProgress progress) =>
      _onProgress?.call(progress);

  @override
  Future<CompletedSupplierSourceUpload> upload({
    required String tripId,
    required String uploadedByUid,
    required List<SupplierSourceUploadCandidate> candidates,
    String? supplierId,
    String? supplierNameSnapshot,
    void Function(SupplierSourceUploadProgress progress)? onProgress,
  }) {
    final call = (
      tripId: tripId,
      uploadedByUid: uploadedByUid,
      candidates: List<SupplierSourceUploadCandidate>.unmodifiable(candidates),
      supplierId: supplierId,
      supplierNameSnapshot: supplierNameSnapshot,
    );
    calls.add(call);
    _onProgress = onProgress;
    return handler?.call(call) ??
        Future.value(
          CompletedSupplierSourceUpload(
            tripId: tripId,
            packageId: 'package-${calls.length}',
            fileIds: [
              for (var index = 0; index < candidates.length; index++)
                'file-$index',
            ],
          ),
        );
  }
}
