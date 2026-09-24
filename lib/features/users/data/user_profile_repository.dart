import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/kayra_user.dart';

abstract class UserProfileRepository {
  Future<KayraUser> bootstrap(User firebaseUser);
}

class FirestoreUserProfileRepository implements UserProfileRepository {
  FirestoreUserProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<KayraUser> bootstrap(User firebaseUser) =>
      _bootstrap(firebaseUser).timeout(const Duration(seconds: 30));

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
    required String expectedEmail,
  }) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null || snapshot.id != expectedUid) {
      throw const FormatException('User profile is unavailable.');
    }
    final createdAt = data['createdAt'];
    final lastLoginAt = data['lastLoginAt'];
    if (createdAt is! Timestamp || lastLoginAt is! Timestamp) {
      throw const FormatException('User profile timestamps are unavailable.');
    }

    final profile = KayraUser.fromMap({
      ...data,
      'createdAt': createdAt.toDate().toUtc(),
      'lastLoginAt': lastLoginAt.toDate().toUtc(),
    }, documentId: expectedUid);
    if (profile.email != expectedEmail) {
      throw const FormatException('User profile email does not match.');
    }
    return profile;
  }
}
