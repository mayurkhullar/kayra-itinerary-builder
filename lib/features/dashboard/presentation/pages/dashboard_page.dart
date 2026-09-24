import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/kayra_app_header.dart';
import '../widgets/workspace_intro.dart';
import '../widgets/workspace_preview.dart';

/// The authenticated workspace shell, with business features still in preview.
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.user,
    required this.onSignOut,
    this.isSigningOut = false,
  });

  final User user;
  final VoidCallback onSignOut;
  final bool isSigningOut;

  void _showPreviewMessage(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('This is a design preview.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            KayraAppHeader(
              displayName: user.displayName,
              email: user.email,
              photoURL: user.photoURL,
              onSignOut: onSignOut,
              isSigningOut: isSigningOut,
              onPreviewAction: () => _showPreviewMessage(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const WorkspaceIntro(),
                    WorkspacePreview(
                      onPreviewAction: () => _showPreviewMessage(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
