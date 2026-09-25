import 'package:kayra_crm_v1/features/suppliers/data/supplier_repository.dart';
import 'package:kayra_crm_v1/features/suppliers/domain/kayra_supplier.dart';

class FakeSupplierRepository implements SupplierRepository {
  final suppliers = <KayraSupplier>[];
  int listCalls = 0;
  final creations = <({SupplierDetails details, String uid})>[];
  final updates = <({String id, SupplierDetails details})>[];
  Future<void> Function()? beforeLoad;
  Future<void> Function()? beforeSave;
  int _nextId = 0;

  @override
  Future<List<KayraSupplier>> listSuppliers() async {
    listCalls++;
    await beforeLoad?.call();
    return List.of(suppliers);
  }

  @override
  Future<String> createSupplier({
    required SupplierDetails details,
    required String currentUserUid,
  }) async {
    creations.add((details: details, uid: currentUserUid));
    await beforeSave?.call();
    final id = 'created-${++_nextId}';
    suppliers.add(
      KayraSupplier(
        id: id,
        details: details,
        createdByUid: currentUserUid,
        createdAt: DateTime.utc(2026, 9, 25),
        updatedAt: DateTime.utc(2026, 9, 25),
      ),
    );
    return id;
  }

  @override
  Future<void> updateSupplier({
    required String supplierId,
    required SupplierDetails details,
  }) async {
    updates.add((id: supplierId, details: details));
    await beforeSave?.call();
    final index = suppliers.indexWhere((supplier) => supplier.id == supplierId);
    final old = suppliers[index];
    suppliers[index] = KayraSupplier(
      id: old.id,
      status: old.status,
      details: details,
      createdByUid: old.createdByUid,
      createdAt: old.createdAt,
      updatedAt: DateTime.utc(2026, 9, 25),
    );
  }

  @override
  Future<KayraSupplier?> getSupplierById(String supplierId) async {
    for (final supplier in suppliers) {
      if (supplier.id == supplierId) return supplier;
    }
    return null;
  }
}
