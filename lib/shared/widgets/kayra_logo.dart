import 'package:flutter/material.dart';

/// Displays the original brand artwork without cropping or recoloring it.
class KayraLogo extends StatelessWidget {
  const KayraLogo({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/kayra_logo.png',
      width: compact ? 140 : 166,
      height: compact ? 58 : 68,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      semanticLabel: 'Kayra Holiday Maps',
    );
  }
}
