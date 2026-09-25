import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/trips/data/trip_repository.dart';
import '../features/auth/auth_gate.dart';
import '../features/auth/data/auth_service.dart';
import '../features/clients/data/client_repository.dart';
import '../features/users/data/user_profile_repository.dart';

class KayraApp extends StatelessWidget {
  const KayraApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kayra Holiday Maps',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AuthGate(
        authService: authService,
        userProfileRepository: userProfileRepository,
        clientRepository: clientRepository,
        tripRepository: tripRepository,
      ),
    );
  }
}
