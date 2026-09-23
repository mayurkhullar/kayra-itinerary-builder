import 'package:flutter/material.dart';

import '../../../../shared/widgets/kayra_app_header.dart';
import '../widgets/workspace_intro.dart';
import '../widgets/workspace_preview.dart';

/// A temporary shell for reviewing the design system before feature work.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

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
            KayraAppHeader(onPreviewAction: () => _showPreviewMessage(context)),
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
