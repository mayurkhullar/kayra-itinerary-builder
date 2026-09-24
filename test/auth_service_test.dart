import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kayra_crm_v1/features/auth/data/auth_service.dart';

void main() {
  group('Company email validation', () {
    final cases = <String?, bool>{
      'agent@kholidaymaps.com': true,
      'AGENT@KHOLIDAYMAPS.COM': true,
      ' agent@kholidaymaps.com ': true,
      null: false,
      '': false,
      '@kholidaymaps.com': false,
      'agent@gmail.com': false,
      'agent@team.kholidaymaps.com': false,
      'agent@notkholidaymaps.com': false,
      'agent@kholidaymaps.com.example.com': false,
    };

    for (final entry in cases.entries) {
      test('checks ${entry.key ?? '(missing email)'}', () {
        expect(AuthService.hasCompanyEmail(_TestUser(entry.key)), entry.value);
      });
    }
  });

  group('FirebaseAuthService', () {
    test('exposes the Firebase user and authentication stream', () async {
      final user = _TestUser('agent@kholidaymaps.com');
      final firebaseAuth = _FakeFirebaseAuth()..user = user;
      final service = FirebaseAuthService(firebaseAuth: firebaseAuth);

      expect(service.currentUser, same(user));
      await expectLater(service.authStateChanges(), emits(user));
    });

    test('native sign-in fails safely without opening a popup', () async {
      final firebaseAuth = _FakeFirebaseAuth();
      final service = FirebaseAuthService(
        firebaseAuth: firebaseAuth,
        isWeb: false,
      );

      await expectLater(
        service.signInWithGoogle(),
        _failsWith(
          'Google sign-in is currently available in the Web app. '
          'Please open Kayra in your browser.',
        ),
      );
      expect(firebaseAuth.popupCalls, 0);
    });

    test('opens Google popup directly with identity scopes only', () async {
      final user = _TestUser('agent@kholidaymaps.com');
      final firebaseAuth = _FakeFirebaseAuth()..popupUser = user;
      final service = FirebaseAuthService(
        firebaseAuth: firebaseAuth,
        isWeb: true,
      );

      final signIn = service.signInWithGoogle();

      // A popup must be invoked in the button's user gesture, without an
      // earlier asynchronous operation that could cause browser blocking.
      expect(firebaseAuth.popupCalls, 1);
      expect(firebaseAuth.receivedProvider, isA<GoogleAuthProvider>());
      final provider = firebaseAuth.receivedProvider! as GoogleAuthProvider;
      expect(provider.scopes, isEmpty);
      expect(provider.parameters, {'prompt': 'select_account'});

      await signIn;
      expect(service.currentUser, same(user));
      expect(firebaseAuth.signOutCalls, 0);
    });

    for (final email in <String?>['agent@gmail.com', null]) {
      test('rejects and signs out an account with email $email', () async {
        final firebaseAuth = _FakeFirebaseAuth()..popupUser = _TestUser(email);
        final service = FirebaseAuthService(
          firebaseAuth: firebaseAuth,
          isWeb: true,
        );

        await expectLater(
          service.signInWithGoogle(),
          _failsWith(AuthService.domainError),
        );

        expect(firebaseAuth.signOutCalls, 1);
        expect(service.currentUser, isNull);
      });
    }

    test('rejects a popup result without a user', () async {
      final firebaseAuth = _FakeFirebaseAuth();
      final service = FirebaseAuthService(
        firebaseAuth: firebaseAuth,
        isWeb: true,
      );

      await expectLater(
        service.signInWithGoogle(),
        _failsWith(AuthService.domainError),
      );
      expect(firebaseAuth.signOutCalls, 1);
    });

    test('retains domain rejection even when sign-out fails', () async {
      final firebaseAuth = _FakeFirebaseAuth()
        ..popupUser = _TestUser('agent@gmail.com')
        ..signOutError = StateError('Private cleanup failure');
      final service = FirebaseAuthService(
        firebaseAuth: firebaseAuth,
        isWeb: true,
      );

      await expectLater(
        service.signInWithGoogle(),
        _failsWith(AuthService.domainError),
      );
      expect(firebaseAuth.signOutCalls, 1);
    });

    final errorMessages = {
      'popup-closed-by-user':
          'Sign-in was cancelled. Please try again when you’re ready.',
      'cancelled-popup-request':
          'Sign-in was cancelled. Please try again when you’re ready.',
      'user-cancelled':
          'Sign-in was cancelled. Please try again when you’re ready.',
      'popup-blocked':
          'Your browser blocked the sign-in window. Allow popups for Kayra and try again.',
      'network-request-failed':
          'Unable to connect. Check your internet connection and try again.',
      'too-many-requests':
          'There have been too many sign-in attempts. Please try again shortly.',
      'user-disabled':
          'This account is unavailable. Please contact your Kayra administrator.',
      'unauthorized-domain': 'We couldn’t sign you in. Please try again.',
      'unknown-code': 'We couldn’t sign you in. Please try again.',
    };

    for (final entry in errorMessages.entries) {
      test('shows a safe message for ${entry.key}', () async {
        final firebaseAuth = _FakeFirebaseAuth()
          ..popupError = FirebaseAuthException(
            code: entry.key,
            message: 'Private Firebase diagnostic details',
          );
        final service = FirebaseAuthService(
          firebaseAuth: firebaseAuth,
          isWeb: true,
        );

        await expectLater(service.signInWithGoogle(), _failsWith(entry.value));
      });
    }

    test('does not expose unexpected authentication errors', () async {
      final firebaseAuth = _FakeFirebaseAuth()
        ..popupError = StateError('Private unexpected error');
      final service = FirebaseAuthService(
        firebaseAuth: firebaseAuth,
        isWeb: true,
      );

      await expectLater(
        service.signInWithGoogle(),
        _failsWith('We couldn’t sign you in. Please try again.'),
      );
    });

    test(
      'coalesces concurrent sign-outs from stream and popup checks',
      () async {
        final completion = Completer<void>();
        final firebaseAuth = _FakeFirebaseAuth()
          ..user = _TestUser('agent@gmail.com')
          ..signOutCompletion = completion.future;
        final service = FirebaseAuthService(firebaseAuth: firebaseAuth);

        final first = service.signOut();
        final second = service.signOut();
        expect(firebaseAuth.signOutCalls, 1);

        completion.complete();
        await Future.wait([first, second]);
        expect(service.currentUser, isNull);
      },
    );

    test('sign-out failure is safe and allows a later retry', () async {
      final firebaseAuth = _FakeFirebaseAuth()
        ..user = _TestUser('agent@kholidaymaps.com')
        ..signOutError = StateError('Private sign-out failure');
      final service = FirebaseAuthService(firebaseAuth: firebaseAuth);

      await expectLater(
        service.signOut(),
        _failsWith('We couldn’t sign you out. Please try again.'),
      );
      expect(service.currentUser, isNotNull);

      firebaseAuth.signOutError = null;
      await service.signOut();
      expect(firebaseAuth.signOutCalls, 2);
      expect(service.currentUser, isNull);
    });
  });
}

Matcher _failsWith(String message) => throwsA(
  isA<AuthFailure>().having((failure) => failure.message, 'message', message),
);

class _TestUser extends Fake implements User {
  _TestUser(this.email);

  @override
  final String? email;
}

class _TestUserCredential extends Fake implements UserCredential {
  _TestUserCredential(this.user);

  @override
  final User? user;
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {
  User? user;
  User? popupUser;
  Object? popupError;
  Object? signOutError;
  Future<void>? signOutCompletion;
  AuthProvider? receivedProvider;
  int popupCalls = 0;
  int signOutCalls = 0;

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() => Stream.value(user);

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) async {
    popupCalls++;
    receivedProvider = provider;
    final error = popupError;
    if (error != null) throw error;
    user = popupUser;
    return _TestUserCredential(user);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final error = signOutError;
    if (error != null) throw error;
    final completion = signOutCompletion;
    if (completion != null) await completion;
    user = null;
  }
}
