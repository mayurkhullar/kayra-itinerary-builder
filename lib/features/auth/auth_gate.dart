import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/widgets/kayra_logo.dart';
import '../dashboard/presentation/pages/dashboard_page.dart';
import 'data/auth_service.dart';
import 'presentation/pages/sign_in_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.authService});

  final AuthService? authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth;
  late final StreamSubscription<User?> _subscription;
  User? _user;
  bool _isLoading = true;
  bool _isSigningIn = false;
  bool _isSigningOut = false;
  bool _isRejectingUser = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? FirebaseAuthService();
    _subscription = _auth.authStateChanges().listen(
      _onAuthStateChanged,
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _user = null;
          _errorMessage =
              'We couldn’t check your session. Please sign in again.';
        });
      },
    );
  }

  void _onAuthStateChanged(User? user) {
    if (!mounted) return;
    final isRejected = user != null && !AuthService.hasCompanyEmail(user);
    setState(() {
      _isLoading = false;
      // Never render the workspace for an unvalidated, restored session.
      _user = isRejected ? null : user;
      if (isRejected) {
        _errorMessage = AuthService.domainError;
      } else if (user != null) {
        _errorMessage = null;
      }
    });
    if (isRejected) unawaited(_rejectUser());
  }

  Future<void> _rejectUser() async {
    if (_isRejectingUser) return;
    setState(() => _isRejectingUser = true);
    try {
      await _auth.signOut();
    } catch (_) {
      // Keep access blocked even if local session cleanup fails.
    } finally {
      if (mounted) setState(() => _isRejectingUser = false);
    }
  }

  Future<void> _signIn() async {
    if (_isSigningIn || _isRejectingUser) return;
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    try {
      await _auth.signInWithGoogle();
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'We couldn’t sign you in. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      await _auth.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('We couldn’t sign you out. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _SessionLoadingPage();

    final user = _user;
    if (user != null && !_isSigningIn && !_isRejectingUser) {
      return DashboardPage(
        user: user,
        onSignOut: _signOut,
        isSigningOut: _isSigningOut,
      );
    }

    return SignInPage(
      onSignIn: _signIn,
      isSigningIn: _isSigningIn || _isRejectingUser,
      errorMessage: _errorMessage,
    );
  }
}

class _SessionLoadingPage extends StatelessWidget {
  const _SessionLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KayraLogo(),
              SizedBox(height: 32),
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: 'Opening your Kayra workspace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
