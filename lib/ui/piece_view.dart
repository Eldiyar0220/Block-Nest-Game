import 'package:flutter/material.dart';

import '../game/geometry.dart';

class CellMetrics {
  static double gap(double cell) => cell * 0.14;

  static double block(double cell) => cell - gap(cell);

  static double offset(int index, double cell) => index * cell + gap(cell) / 2;

  static double radius(double cell) => block(cell) * 0.24;
}

class BlockGem extends StatelessWidget {
  const BlockGem({
    super.key,
    required this.color,
    required this.radius,
    this.pale = false,
  });

  final Color color;
  final double radius;
  final bool pale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paint = pale ? color.withValues(alpha: 0.42) : color;
    final highlight = Color.lerp(
      paint,
      Colors.white,
      pale ? 0.12 : (isDark ? 0.32 : 0.4),
    )!;
    final shade = Color.lerp(
      paint,
      Colors.black,
      pale ? 0 : (isDark ? 0.18 : 0.1),
    )!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [highlight, paint, shade],
          stops: const [0, 0.42, 1],
        ),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: pale ? 0.18 : (isDark ? 0.22 : 0.45),
          ),
        ),
        boxShadow: pale
            ? const []
            : [
                BoxShadow(
                  color: (isDark ? color : const Color(0xFF2C2824)).withValues(
                    alpha: isDark ? 0.38 : 0.16,
                  ),
                  blurRadius: isDark ? 10 : 5,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
    );
  }
}

class PieceView extends StatelessWidget {
  const PieceView({
    super.key,
    required this.cells,
    required this.color,
    required this.cellSize,
    this.pale = false,
  });

  final List<Point> cells;
  final Color color;
  final double cellSize;
  final bool pale;

  @override
  Widget build(BuildContext context) {
    var maxR = 0;
    var maxC = 0;
    for (final cell in cells) {
      if (cell.r > maxR) maxR = cell.r;
      if (cell.c > maxC) maxC = cell.c;
    }
    return SizedBox(
      width: (maxC + 1) * cellSize,
      height: (maxR + 1) * cellSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final cell in cells)
            Positioned(
              left: CellMetrics.offset(cell.c, cellSize),
              top: CellMetrics.offset(cell.r, cellSize),
              width: CellMetrics.block(cellSize),
              height: CellMetrics.block(cellSize),
              child: BlockGem(
                color: color,
                radius: CellMetrics.radius(cellSize),
                pale: pale,
              ),
            ),
        ],
      ),
    );
  }
}

class BombGem extends StatelessWidget {
  const BombGem({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _BombPainter());
  }
}

class _BombPainter extends CustomPainter {
  const _BombPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2 + side * 0.05);
    final radius = side * 0.36;

    canvas.drawCircle(
      center,
      radius * 1.2,
      Paint()
        ..color = const Color(0xFFF0943A).withValues(alpha: 0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [Color(0xFF6E6560), Color(0xFF2A2623), Color(0xFF120F0D)],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
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
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFF6D0), Color(0xFFFF9A2E), Color(0xFFE25822)],
          stops: [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: ember, radius: emberRadius)),
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

  @override
  bool shouldRepaint(covariant _BombPainter oldDelegate) => false;
}
