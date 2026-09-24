import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/auth_gate.dart';
import '../features/auth/data/auth_service.dart';
import '../features/users/data/user_profile_repository.dart';

class KayraApp extends StatelessWidget {
  const KayraApp({super.key, this.authService, this.userProfileRepository});

  final AuthService? authService;
  final UserProfileRepository? userProfileRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kayra Holiday Maps',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AuthGate(
        authService: authService,
        userProfileRepository: userProfileRepository,
      ),
    );
  }
}
