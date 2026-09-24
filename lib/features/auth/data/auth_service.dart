import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

abstract class AuthService {
  User? get currentUser;
  Stream<User?> authStateChanges();
  Future<void> signInWithGoogle();
  Future<void> signOut();

  static const domainError =
      'Kayra Holiday Maps is available only to authorised '
      '@kholidaymaps.com accounts.';

  static bool hasCompanyEmail(User user) {
    final email = user.email?.trim().toLowerCase();
    const suffix = '@kholidaymaps.com';
    // This gate is for UI access. Server-side authorization will be enforced
    // with Firestore Security Rules when Firestore is introduced.
    return email != null &&
        email.length > suffix.length &&
        email.endsWith(suffix);
  }
}

/// Only safe, user-facing messages cross the service/UI boundary.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? firebaseAuth, bool isWeb = kIsWeb})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _isWeb = isWeb;

  final FirebaseAuth _firebaseAuth;
  final bool _isWeb;
  Future<void>? _pendingSignOut;

  @override
  User? get currentUser => _firebaseAuth.currentUser;

  @override
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  @override
  Future<void> signInWithGoogle() async {
    if (!_isWeb) {
      throw const AuthFailure(
        'Google sign-in is currently available in the Web app. '
        'Please open Kayra in your browser.',
      );
    }

    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      // Open directly from the button action, before any asynchronous work,
      // so the browser retains the user gesture needed for a popup.
      final credential = await _firebaseAuth.signInWithPopup(provider);
      final user = credential.user;
      if (user == null || !AuthService.hasCompanyEmail(user)) {
        try {
          await signOut();
        } finally {
          throw const AuthFailure(AuthService.domainError);
        }
      }
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_signInMessage(error.code));
    } catch (_) {
      throw const AuthFailure('We couldn’t sign you in. Please try again.');
    }
  }

  @override
  Future<void> signOut() {
    // The auth stream and popup result can both reject the same account.
    return _pendingSignOut ??= _signOut().whenComplete(() {
      _pendingSignOut = null;
    });
  }

  Future<void> _signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (_) {
      throw const AuthFailure('We couldn’t sign you out. Please try again.');
    }
  }

  static String _signInMessage(String code) => switch (code) {
    'popup-closed-by-user' || 'cancelled-popup-request' || 'user-cancelled' =>
      'Sign-in was cancelled. Please try again when you’re ready.',
    'popup-blocked' =>
      'Your browser blocked the sign-in window. Allow popups for Kayra and try again.',
    'network-request-failed' =>
      'Unable to connect. Check your internet connection and try again.',
    'too-many-requests' =>
      'There have been too many sign-in attempts. Please try again shortly.',
    'user-disabled' =>
      'This account is unavailable. Please contact your Kayra administrator.',
    _ => 'We couldn’t sign you in. Please try again.',
  };
}
