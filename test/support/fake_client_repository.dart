import 'package:kayra_crm_v1/features/clients/data/client_repository.dart';
import 'package:kayra_crm_v1/features/clients/domain/kayra_client.dart';

class FakeClientRepository implements ClientRepository {
  final clients = <KayraClient>[];
  final ownerQueries = <String>[];
  int adminQueries = 0;
  final creations = <({ClientDetails details, String uid})>[];
  final updates = <({String id, ClientDetails details})>[];
  Future<void> Function()? beforeLoad;
  Future<void> Function()? beforeSave;
  int _nextId = 0;

  @override
  Future<List<KayraClient>> listOwnedClients(String ownerUid) async {
    ownerQueries.add(ownerUid);
    await beforeLoad?.call();
    return clients.where((client) => client.createdByUid == ownerUid).toList();
  }

  @override
  Future<List<KayraClient>> listAllClientsForAdmin() async {
    adminQueries++;
    await beforeLoad?.call();
    return List.of(clients);
  }

  @override
  Future<String> createClient({
    required ClientDetails details,
    required String currentUserUid,
  }) async {
    creations.add((details: details, uid: currentUserUid));
    await beforeSave?.call();
    final id = 'created-${++_nextId}';
    clients.add(
      KayraClient(
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
  Future<void> updateClient({
    required String clientId,
    required ClientDetails details,
  }) async {
    updates.add((id: clientId, details: details));
    await beforeSave?.call();
    final index = clients.indexWhere((client) => client.id == clientId);
    final old = clients[index];
    clients[index] = KayraClient(
      id: old.id,
      details: details,
      createdByUid: old.createdByUid,
      createdAt: old.createdAt,
      updatedAt: DateTime.utc(2026, 9, 25),
    );
  }

  @override
  Future<KayraClient?> getClientById(String clientId) async {
    for (final client in clients) {
      if (client.id == clientId) return client;
    }
    return null;
  }
}
