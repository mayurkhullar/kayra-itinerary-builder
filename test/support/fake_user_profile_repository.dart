import 'package:firebase_auth/firebase_auth.dart';
import 'package:kayra_crm_v1/features/users/data/user_profile_repository.dart';
import 'package:kayra_crm_v1/features/users/domain/kayra_user.dart';

KayraUser testProfile(
  User user, {
  KayraUserRole role = KayraUserRole.agent,
  KayraUserStatus status = KayraUserStatus.active,
}) => KayraUser(
  uid: user.uid,
  email: user.email!.trim().toLowerCase(),
  displayName: user.displayName,
  photoUrl: user.photoURL,
  role: role,
  status: status,
  createdAt: DateTime.utc(2026),
  lastLoginAt: DateTime.utc(2026, 9),
);

class FakeUserProfileRepository implements UserProfileRepository {
  Future<KayraUser> Function(User)? onBootstrap;
  final List<User> calls = [];

  @override
  Future<KayraUser> bootstrap(User user) async {
    calls.add(user);
    return onBootstrap == null ? testProfile(user) : await onBootstrap!(user);
  }
}
