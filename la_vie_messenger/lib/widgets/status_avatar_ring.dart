import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// WhatsApp-style Status Avatar Ring widget.
/// Draws a vibrant gradient or segmented arc border if there are active statuses,
/// or a subtle muted ring if all statuses have been viewed.
class StatusAvatarRing extends StatelessWidget {
  final Widget child;
  final int itemCount;
  final bool hasUnseen;
  final double radius;
  final double strokeWidth;
  final double spacing;
  final VoidCallback? onTap;

  const StatusAvatarRing({
    super.key,
    required this.child,
    this.itemCount = 0,
    this.hasUnseen = false,
    this.radius = 24,
    this.strokeWidth = 2.4,
    this.spacing = 3.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) {
      // No active status, render plain child
      return GestureDetector(
        onTap: onTap,
        child: child,
      );
    }

    final totalSize = (radius * 2) + (spacing * 2) + (strokeWidth * 2);
    final isDark = AppTheme.isDarkMode(context);
    final activeColor = AppTheme.mintColor(context);
    final viewedColor = isDark
        ? Colors.white.withValues(alpha: 0.28)
        : Colors.black.withValues(alpha: 0.22);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: totalSize,
        height: totalSize,
        child: CustomPaint(
          painter: _StatusRingPainter(
            itemCount: itemCount,
            hasUnseen: hasUnseen,
            strokeWidth: strokeWidth,
            activeColor: activeColor,
            viewedColor: viewedColor,
          ),
          child: Center(
            child: SizedBox(
              width: radius * 2,
              height: radius * 2,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRingPainter extends CustomPainter {
  final int itemCount;
  final bool hasUnseen;
  final double strokeWidth;
  final Color activeColor;
  final Color viewedColor;

  _StatusRingPainter({
    required this.itemCount,
    required this.hasUnseen,
    required this.strokeWidth,
    required this.activeColor,
    required this.viewedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final ringColor = hasUnseen ? activeColor : viewedColor;
    paint.color = ringColor;

    if (itemCount <= 1) {
      // Single continuous ring
      canvas.drawCircle(center, radius, paint);
      return;
    }

    // Segmented ring (WhatsApp style)
    final double gapAngle = (itemCount <= 4 ? 0.16 : 0.08) * math.pi; // Gap in radians
    final double totalGaps = gapAngle * itemCount;
    final double availableArc = (2 * math.pi) - totalGaps;
    final double arcLength = availableArc / itemCount;

    double startAngle = -math.pi / 2; // Start from 12 o'clock

    for (int i = 0; i < itemCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        arcLength,
        false,
        paint,
      );
      startAngle += arcLength + gapAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _StatusRingPainter oldDelegate) {
    return oldDelegate.itemCount != itemCount ||
        oldDelegate.hasUnseen != hasUnseen ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.viewedColor != viewedColor;
  }
}
