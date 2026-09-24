import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/auth_gate.dart';
import '../features/auth/data/auth_service.dart';

class KayraApp extends StatelessWidget {
  const KayraApp({super.key, this.authService});

  final AuthService? authService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kayra Holiday Maps',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AuthGate(authService: authService),
    );
  }
}
