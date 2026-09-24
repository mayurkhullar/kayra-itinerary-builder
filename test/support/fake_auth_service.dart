import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:kayra_crm_v1/features/auth/data/auth_service.dart';

class TestUser implements User {
  TestUser({
    this.uid = 'test-user',
    this.email = 'maya@kholidaymaps.com',
    this.displayName = 'Maya Kapoor',
    this.photoURL,
  });

  @override
  final String? email;
  @override
  final String? displayName;
  @override
  final String? photoURL;
  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthService implements AuthService {
  FakeAuthService({User? user, this.emitInitialState = true}) : _user = user;

  User? _user;
  final bool emitInitialState;
  late final StreamController<User?> _controller =
      StreamController<User?>.broadcast(
        onListen: () {
          if (emitInitialState) _controller.add(_user);
        },
      );
  Future<void> Function()? onGoogleSignIn;
  Future<void> Function()? onSignOut;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> authStateChanges() => _controller.stream;

  void emit(User? user) {
    _user = user;
    _controller.add(user);
  }

  void emitError(Object error) => _controller.addError(error);

  @override
  Future<void> signInWithGoogle() async {
    signInCalls++;
    await onGoogleSignIn?.call();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (onSignOut != null) {
      await onSignOut!();
    } else {
      emit(null);
    }
  }

  Future<void> dispose() => _controller.close();
}
