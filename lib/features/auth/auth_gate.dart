import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../clients/data/client_repository.dart';
import '../trips/data/trip_repository.dart';
import '../dashboard/presentation/pages/dashboard_page.dart';
import '../users/data/user_profile_repository.dart';
import '../users/domain/kayra_user.dart';
import 'data/auth_service.dart';
import 'presentation/pages/session_status_page.dart';
import 'presentation/pages/sign_in_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.authService,
    this.userProfileRepository,
    this.clientRepository,
    this.tripRepository,
  });

  final AuthService? authService;
  final UserProfileRepository? userProfileRepository;
  final ClientRepository? clientRepository;
  final TripRepository? tripRepository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth;
  late final UserProfileRepository _profiles;
  late final StreamSubscription<User?> _subscription;
  User? _user;
  KayraUser? _profile;
  int _profileRequest = 0;
  bool _isLoadingProfile = false;
  bool _profileFailed = false;
  bool _isLoading = true;
  bool _isSigningIn = false;
  bool _isSigningOut = false;
  bool _isRejectingUser = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? FirebaseAuthService();
    _profiles =
        widget.userProfileRepository ?? FirestoreUserProfileRepository();
    _subscription = _auth.authStateChanges().listen(
      _onAuthStateChanged,
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _user = null;
          _clearProfile();
          _errorMessage =
              'We couldn’t check your session. Please sign in again.';
        });
      },
    );
  }

  void _onAuthStateChanged(User? user) {
    if (!mounted) return;
    final isRejected = user != null && !AuthService.hasCompanyEmail(user);
    final isSameSession =
        user != null &&
        _user?.uid == user.uid &&
        _user?.email?.trim().toLowerCase() == user.email?.trim().toLowerCase();
    setState(() {
      _isLoading = false;
      _user = isRejected ? null : user;
      if (!isSameSession || isRejected) _clearProfile();
      if (isRejected) {
        _errorMessage = AuthService.domainError;
      } else if (user != null) {
        _errorMessage = null;
      }
    });
    if (isRejected) unawaited(_rejectUser());
    if (user != null && !isRejected && !isSameSession) {
      unawaited(_loadProfile(user));
    }
  }

  void _clearProfile() {
    _profileRequest++;
    _profile = null;
    _isLoadingProfile = false;
    _profileFailed = false;
  }

  Future<void> _loadProfile(User user) async {
    if (!mounted || !_isCurrentUser(user)) return;
    final request = ++_profileRequest;
    setState(() {
      _profile = null;
      _isLoadingProfile = true;
      _profileFailed = false;
    });
    try {
      final profile = await _profiles.bootstrap(user);
      // A previous session or retry must never open the current workspace.
      if (!mounted || request != _profileRequest || !_isCurrentUser(user)) {
        return;
      }
      if (profile.uid != user.uid ||
          profile.email != user.email?.trim().toLowerCase()) {
        throw const FormatException('Profile identity mismatch');
      }
      setState(() => _profile = profile);
    } catch (_) {
      if (mounted && request == _profileRequest) {
        setState(() => _profileFailed = true);
      }
    } finally {
      if (mounted && request == _profileRequest) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  bool _isCurrentUser(User user) =>
      _user?.uid == user.uid &&
      _user?.email?.trim().toLowerCase() == user.email?.trim().toLowerCase();

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
    if (_isLoading) return const SessionStatusPage();

    final user = _user;
    if (user != null && !_isSigningIn && !_isRejectingUser) {
      if (_isLoadingProfile) return const SessionStatusPage();
      if (_profileFailed) {
        return SessionStatusPage(
          message: 'We couldn’t load your Kayra profile. Please try again.',
          onRetry: _isSigningOut ? null : () => _loadProfile(user),
          onSignOut: _signOut,
          isSigningOut: _isSigningOut,
        );
      }
      final profile = _profile;
      if (profile == null) return const SessionStatusPage();
      if (!profile.isActive) {
        return SessionStatusPage(
          message:
              'Your Kayra account is inactive. Please contact your administrator.',
          onSignOut: _signOut,
          isSigningOut: _isSigningOut,
        );
      }
      return DashboardPage(
        user: profile,
        userProfileRepository: _profiles,
        clientRepository: widget.clientRepository,
        tripRepository: widget.tripRepository,
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
