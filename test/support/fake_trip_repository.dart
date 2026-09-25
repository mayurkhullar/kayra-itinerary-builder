import 'package:kayra_crm_v1/features/clients/data/client_repository.dart';
import 'package:kayra_crm_v1/features/trips/data/trip_repository.dart';
import 'package:kayra_crm_v1/features/trips/domain/kayra_trip.dart';

class FakeTripRepository implements TripRepository {
  FakeTripRepository({this.clients});
  final ClientRepository? clients;
  final trips = <KayraTrip>[];
  final ownerQueries = <String>[];
  int adminQueries = 0;
  final creations = <({String clientId, TripBrief brief, String uid})>[];
  Future<void> Function()? beforeLoad;
  Future<void> Function()? beforeSave;
  @override
  Future<List<KayraTrip>> listOwnedTrips(String ownerUid) async {
    ownerQueries.add(ownerUid);
    await beforeLoad?.call();
    return trips.where((trip) => trip.ownerUid == ownerUid).toList();
  }

  @override
  Future<List<KayraTrip>> listAllTripsForAdmin() async {
    adminQueries++;
    await beforeLoad?.call();
    return List.of(trips);
  }

  @override
  Future<String> createTrip({
    required String clientId,
    required TripBrief brief,
    required String currentUserUid,
  }) async {
    creations.add((clientId: clientId, brief: brief, uid: currentUserUid));
    await beforeSave?.call();
    final client = await clients!.getClientById(clientId);
    final trip = KayraTrip.create(
      id: 'created-${creations.length}',
      clientId: clientId,
      clientFirstName: client!.firstName,
      clientLastName: client.lastName,
      clientCompany: client.company,
      brief: brief,
      currentUserUid: currentUserUid,
      createdAt: DateTime.utc(2026, 9, 25),
    );
    trips.add(trip);
    return trip.id;
  }

  @override
  Future<KayraTrip?> getTripById(String tripId) async {
    for (final trip in trips) {
      if (trip.id == tripId) return trip;
    }
    return null;
  }

  @override
  Future<void> updateTrip({required String tripId, required TripBrief brief}) =>
      throw UnimplementedError();
}
