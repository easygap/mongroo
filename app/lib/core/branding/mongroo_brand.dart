import 'package:flutter/material.dart';

/// Interface identity, revised 2026-09-22. See the dated design research.
abstract final class MongrooBrandColors {
  static const action = Color(0xFF242424);
  static const ink = Color(0xFF202020);
  static const signal = Color(0xFFC53B49);
  static const paper = Color(0xFFFFFFFF);

  // Compatibility with the existing illustrations and shared components.
  static const sprout = action;
  static const soil = ink;
}

/// 작은 화면에서도 잎과 m의 윤곽이 남는 두 색 심볼.
class MongrooBrandMark extends StatelessWidget {
  const MongrooBrandMark({
    super.key,
    this.size = 48,
    this.withPlate = false,
    this.semanticLabel = '몽그루',
  });

  static const assetPath = 'assets/brand/mongroo-symbol.webp';

  final double size;
  final bool withPlate;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    const mark = CustomPaint(painter: _MongrooMarkPainter());

    return Semantics(
      image: true,
      label: semanticLabel,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: withPlate
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: MongrooBrandColors.paper,
                    borderRadius: BorderRadius.circular(size * 0.24),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.08),
                    child: mark,
                  ),
                )
              : mark,
        ),
      ),
    );
  }
}

class _MongrooMarkPainter extends CustomPainter {
  const _MongrooMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final stem = Paint()
      ..color = MongrooBrandColors.soil
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(16, 80)
          ..lineTo(16, 45)
          ..cubicTo(16, 18, 49, 18, 49, 45)
          ..lineTo(49, 80)
          ..moveTo(49, 45)
          ..cubicTo(49, 18, 82, 18, 82, 45)
          ..lineTo(82, 80),
        stem);
    canvas.drawPath(
        Path()
          ..moveTo(66, 24)
          ..quadraticBezierTo(62, 3, 90, 7)
          ..quadraticBezierTo(90, 30, 66, 24)
          ..close(),
        Paint()..color = MongrooBrandColors.sprout);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MongrooMarkPainter oldDelegate) => false;
}
