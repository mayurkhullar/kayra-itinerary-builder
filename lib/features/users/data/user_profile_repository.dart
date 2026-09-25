import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/kayra_user.dart';

abstract class UserProfileRepository {
  Future<KayraUser> bootstrap(User firebaseUser);
  Future<List<KayraUser>> listUsers();
  Future<void> updateUserRole({
    required KayraUser currentUser,
    required String userId,
    required KayraUserRole role,
  });
}

class FirestoreUserProfileRepository implements UserProfileRepository {
  FirestoreUserProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Application safeguard; deployed Firestore rules authorize the caller.
  @override
  Future<void> updateUserRole({
    required KayraUser currentUser,
    required String userId,
    required KayraUserRole role,
  }) async {
    if (!currentUser.isActiveAdmin || currentUser.uid == userId) {
      throw StateError('Role changes require an Admin editing another user.');
    }
    if (!KayraUser.isValidUid(userId)) {
      throw const FormatException('Invalid profile identity.');
    }
    // update (rather than set) preserves every other field and never creates a user.
    await _firestore.collection('users').doc(userId).update({
      'role': role.name,
    });
  }

  @override
  Future<KayraUser> bootstrap(User firebaseUser) =>
      _bootstrap(firebaseUser).timeout(const Duration(seconds: 30));

  /// A server-only read: Firestore rules authorize the authenticated caller.
  @override
  Future<List<KayraUser>> listUsers() async {
    final snapshot = await _firestore
        .collection('users')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    final users = snapshot.docs
        .map(
          (document) => _readProfile(
            document,
            expectedUid: document.id,
            allowMissingLastLoginAt: true,
          ),
        )
        .toList();
    users.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      final nameOrder = a.displayLabel.toLowerCase().compareTo(
        b.displayLabel.toLowerCase(),
      );
      if (nameOrder != 0) return nameOrder;
      final emailOrder = a.email.compareTo(b.email);
      return emailOrder != 0 ? emailOrder : a.uid.compareTo(b.uid);
    });
    return List.unmodifiable(users);
  }

  Future<KayraUser> _bootstrap(User firebaseUser) async {
    final uid = firebaseUser.uid;
    final email = firebaseUser.email?.trim().toLowerCase();
    if (!KayraUser.isValidUid(uid) ||
        email == null ||
        !KayraUser.isCompanyEmail(email)) {
      throw const FormatException('Invalid authenticated profile identity.');
    }

    final reference = _firestore.collection('users').doc(uid);
    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        transaction.set(reference, {
          'uid': uid,
          'email': email,
          'displayName': firebaseUser.displayName,
          'photoUrl': firebaseUser.photoURL,
          'role': KayraUserRole.agent.name,
          'status': KayraUserStatus.active.name,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final profile = _readProfile(
        snapshot,
        expectedUid: uid,
        expectedEmail: email,
      );
      if (!profile.isActive) return;

      // A transaction retry re-reads the profile and preserves access fields.
      transaction.update(reference, {
        'displayName': firebaseUser.displayName,
        'photoUrl': firebaseUser.photoURL,
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    });

    // Resolve server timestamps and access status without cached fallbacks.
    final snapshot = await reference.get(
      const GetOptions(source: Source.server),
    );
    return _readProfile(snapshot, expectedUid: uid, expectedEmail: email);
  }

  KayraUser _readProfile(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String expectedUid,
    String? expectedEmail,
    bool allowMissingLastLoginAt = false,
  }) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null || snapshot.id != expectedUid) {
      throw const FormatException('User profile is unavailable.');
    }
    final createdAt = data['createdAt'];
    final lastLoginAt = data['lastLoginAt'];
    if (createdAt is! Timestamp ||
        (lastLoginAt is! Timestamp &&
            !(allowMissingLastLoginAt && lastLoginAt == null))) {
      throw const FormatException('User profile timestamps are unavailable.');
    }

    final profile = KayraUser.fromMap(
      {
        ...data,
        'createdAt': createdAt.toDate().toUtc(),
        'lastLoginAt': (lastLoginAt as Timestamp?)?.toDate().toUtc(),
      },
      documentId: expectedUid,
      allowMissingLastLoginAt: allowMissingLastLoginAt,
    );
    if (expectedEmail != null && profile.email != expectedEmail) {
      throw const FormatException('User profile email does not match.');
    }
    return profile;
  }
}
