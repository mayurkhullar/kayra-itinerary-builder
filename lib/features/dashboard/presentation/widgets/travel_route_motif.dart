import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Decorative route artwork; it does not represent trips or geographic data.
class TravelRouteMotif extends StatelessWidget {
  const TravelRouteMotif({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AspectRatio(
          aspectRatio: compact ? 5 : 1.9,
          child: CustomPaint(painter: _RoutePainter(compact: compact)),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({required this.compact});

  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.inkOnNavy.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    if (!compact) {
      for (var x = 0.15; x < 1; x += 0.2) {
        for (var y = 0.15; y < 1; y += 0.25) {
          final point = Offset(size.width * x, size.height * y);
          canvas.drawLine(
            point - const Offset(3, 0),
            point + const Offset(3, 0),
            gridPaint,
          );
          canvas.drawLine(
            point - const Offset(0, 3),
            point + const Offset(0, 3),
            gridPaint,
          );
        }
      }
    }

    final start = Offset(size.width * 0.08, size.height * 0.8);
    final end = Offset(size.width * 0.9, size.height * 0.18);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * 0.44,
        size.height * 0.82,
        size.width * 0.3,
        size.height * 0.06,
        size.width * 0.62,
        size.height * 0.27,
      )
      ..cubicTo(
        size.width * 0.75,
        size.height * 0.4,
        size.width * 0.8,
        size.height * 0.32,
        end.dx,
        end.dy,
      );
    final linePaint = Paint()
      ..color = AppColors.inkOnNavy.withValues(alpha: compact ? 0.3 : 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(route, linePaint);
    if (compact) {
      canvas.drawCircle(start, 1.5, linePaint);
      canvas.drawCircle(end, 1.5, Paint()..color = AppColors.subtleOnNavy);
      return;
    }
    canvas.drawCircle(start, 4, linePaint);
    final destinationPin = Path()
      ..moveTo(end.dx, end.dy)
      ..cubicTo(
        end.dx - 14,
        end.dy - 14,
        end.dx - 10,
        end.dy - 26,
        end.dx,
        end.dy - 26,
      )
      ..cubicTo(
        end.dx + 10,
        end.dy - 26,
        end.dx + 14,
        end.dy - 14,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      destinationPin,
      linePaint..color = AppColors.inkOnNavy.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      end - const Offset(0, 17),
      2.5,
      Paint()..color = AppColors.inkOnNavy.withValues(alpha: 0.7),
    );

    // A small directional mark continues the ascending sweep of the Kayra logo.
    final arrow = Path()
      ..moveTo(end.dx - 26, end.dy + 17)
      ..lineTo(end.dx - 16, end.dy + 10)
      ..lineTo(end.dx - 20, end.dy + 23);
    canvas.drawPath(
      arrow,
      linePaint..color = AppColors.inkOnNavy.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.compact != compact;
}
