import 'package:flutter/material.dart';

/// Rounded block used by the Flame playfield.
void paintGem(
  Canvas canvas,
  Rect rect,
  Color color, {
  required bool dark,
  bool pale = false,
}) {
  final paint = pale ? color.withValues(alpha: 0.42) : color;
  final radius = Radius.circular(rect.shortestSide * 0.24);
  final body = RRect.fromRectAndRadius(rect, radius);
  canvas.drawRRect(body, Paint()..color = paint);
  if (!pale) {
    final gloss = Rect.fromLTWH(
      rect.left + rect.width * 0.16,
      rect.top + rect.height * 0.1,
      rect.width * 0.42,
      rect.height * 0.24,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(gloss, Radius.circular(rect.shortestSide * 0.14)),
      Paint()..color = Colors.white.withValues(alpha: dark ? 0.32 : 0.46),
    );
  }
  canvas.drawRRect(
    body,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(
        alpha: pale ? 0.18 : (dark ? 0.22 : 0.45),
      ),
  );
}

void paintBomb(Canvas canvas, Rect rect, {double glow = 1}) {
  final side = rect.shortestSide;
  final center = rect.center + Offset(0, side * 0.05);
  final radius = side * 0.36;
  canvas.drawCircle(
    center,
    radius * 1.28,
    Paint()..color = const Color(0xFFF0943A).withValues(alpha: 0.22 * glow),
  );
  canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF2A2623));
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.045
      ..color = const Color(0xFFFFB15A),
  );
  final ember = center.translate(0, side * 0.01);
  final emberRadius = radius * 0.36;
  canvas.drawCircle(
    ember,
    emberRadius,
    Paint()..color = const Color(0xFFFF9A2E),
  );
  final fuseStart = center + Offset(radius * 0.42, -radius * 0.78);
  final fuseEnd = center + Offset(radius * 0.9, -radius * 1.28);
  canvas.drawLine(
    fuseStart,
    fuseEnd,
    Paint()
      ..color = const Color(0xFFE2C08A)
      ..strokeWidth = side * 0.07
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawCircle(
    fuseEnd,
    side * 0.065,
    Paint()..color = const Color(0xFFFFE7A3),
  );
}
