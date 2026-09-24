import 'package:flutter/material.dart';

import '../../core/layout/app_layout.dart';
import '../../core/theme/app_spacing.dart';

class KayraContentFrame extends StatelessWidget {
  const KayraContentFrame({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppLayout.mobileBreakpoint;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? AppSpacing.s20 : AppSpacing.s40,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        );
      },
    );
  }
}
