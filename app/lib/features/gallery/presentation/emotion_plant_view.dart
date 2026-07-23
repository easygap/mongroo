import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/harvested_plant.dart';

/// 수확 시점의 감정 분포가 만든 최종 형태를 그리는 박물관 전용 식물.
///
/// 모든 형태가 같은 무광 셀 셰이딩 재질과 갈색 외곽선을 공유한다. 색을 보지
/// 못해도 꽃과 잎의 큰 외곽만으로 형태를 구분할 수 있으며, 정적인 painter라
/// reduced motion 설정에서도 추가 움직임을 만들지 않는다.
class EmotionPlantView extends StatelessWidget {
  const EmotionPlantView({
    super.key,
    required this.form,
    this.speciesCode = 'basic_sprout',
    this.speciesName,
    this.size = 180,
  });

  final PlantFinalForm form;
  final String speciesCode;
  final String? speciesName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolvedSpeciesName = speciesName?.trim().isNotEmpty == true
        ? speciesName!.trim()
        : _fallbackSpeciesName(speciesCode);
    return Semantics(
      image: true,
      label: '$resolvedSpeciesName 품종, ${form.label}, '
          '${form.emotionLabel}의 기록으로 자란 식물',
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          isComplex: true,
          willChange: false,
          painter: EmotionPlantPainter(form, speciesCode: speciesCode),
        ),
      ),
    );
  }
}

class EmotionPlantPainter extends CustomPainter {
  const EmotionPlantPainter(
    this.form, {
    this.speciesCode = 'basic_sprout',
  });

  final PlantFinalForm form;
  final String speciesCode;

  static const _ink = Color(0xFF493B32);
  static const _inkSoft = Color(0x99493B32);
  static const _pot = Color(0xFFC87955);
  static const _potLight = Color(0xFFD99570);
  static const _potShadow = Color(0xFFA95F45);
  static const _soil = Color(0xFF69503E);

  _PlantPalette get _palette => switch (form) {
        PlantFinalForm.sunny => const _PlantPalette(
            leaf: Color(0xFF668A58),
            leafLight: Color(0xFF8DA778),
            leafShadow: Color(0xFF486844),
            bloom: Color(0xFFE4B449),
            bloomLight: Color(0xFFF0C968),
            bloomShadow: Color(0xFFB87D31),
            core: Color(0xFFC86F4D),
            coreShadow: Color(0xFF9F503E),
          ),
        PlantFinalForm.rainy => const _PlantPalette(
            leaf: Color(0xFF628478),
            leafLight: Color(0xFF87A59A),
            leafShadow: Color(0xFF45665F),
            bloom: Color(0xFF719BB1),
            bloomLight: Color(0xFF9AB8C7),
            bloomShadow: Color(0xFF4D7289),
            core: Color(0xFFDBB861),
            coreShadow: Color(0xFFAD8337),
          ),
        PlantFinalForm.ember => const _PlantPalette(
            leaf: Color(0xFF6C8054),
            leafLight: Color(0xFF91A371),
            leafShadow: Color(0xFF4C633F),
            bloom: Color(0xFFD9684E),
            bloomLight: Color(0xFFE9915B),
            bloomShadow: Color(0xFFA9443D),
            core: Color(0xFFE1AD48),
            coreShadow: Color(0xFFAC7432),
          ),
        PlantFinalForm.moonlit => const _PlantPalette(
            leaf: Color(0xFF647369),
            leafLight: Color(0xFF89948B),
            leafShadow: Color(0xFF46564F),
            bloom: Color(0xFF8178A2),
            bloomLight: Color(0xFFA89FC2),
            bloomShadow: Color(0xFF5D567E),
            core: Color(0xFFE0C779),
            coreShadow: Color(0xFFAA8C43),
          ),
        PlantFinalForm.sparkling => const _PlantPalette(
            leaf: Color(0xFF5C8B71),
            leafLight: Color(0xFF82A58C),
            leafShadow: Color(0xFF3E6956),
            bloom: Color(0xFFD97879),
            bloomLight: Color(0xFFE9A19A),
            bloomShadow: Color(0xFFA84F59),
            core: Color(0xFFE1B84F),
            coreShadow: Color(0xFFAA8037),
          ),
        PlantFinalForm.mosaic => const _PlantPalette(
            leaf: Color(0xFF647E60),
            leafLight: Color(0xFF8C9F7B),
            leafShadow: Color(0xFF465F49),
            bloom: Color(0xFFC97A62),
            bloomLight: Color(0xFF8FA6AC),
            bloomShadow: Color(0xFFB49258),
            core: Color(0xFFD8BC62),
            coreShadow: Color(0xFF9C7C3F),
          ),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 180;
    final dx = (size.width - 180 * scale) / 2;
    final dy = (size.height - 180 * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    _drawGroundShadow(canvas);
    _drawSpeciesSilhouette(canvas);
    switch (form) {
      case PlantFinalForm.sunny:
        _drawSunny(canvas);
      case PlantFinalForm.rainy:
        _drawRainy(canvas);
      case PlantFinalForm.ember:
        _drawEmber(canvas);
      case PlantFinalForm.moonlit:
        _drawMoonlit(canvas);
      case PlantFinalForm.sparkling:
        _drawSparkling(canvas);
      case PlantFinalForm.mosaic:
        _drawMosaic(canvas);
    }
    _drawPot(canvas);
    canvas.restore();
  }

  void _drawSpeciesSilhouette(Canvas canvas) {
    switch (speciesCode.trim().toLowerCase()) {
      case 'cactus':
        _drawCactusSilhouette(canvas);
      case 'sunflower':
        _drawSunflowerSilhouette(canvas);
    }
  }

  void _drawCactusSilhouette(Canvas canvas) {
    final paths = [
      Path()
        ..moveTo(78, 128)
        ..cubicTo(76, 109, 70, 92, 61, 88)
        ..cubicTo(54, 85, 56, 75, 56, 69),
      Path()
        ..moveTo(103, 127)
        ..cubicTo(104, 108, 109, 96, 119, 92)
        ..cubicTo(126, 89, 124, 79, 125, 73),
    ];
    for (final path in paths) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = _palette.leafShadow.withAlpha(225)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    final spine = Paint()
      ..color = _palette.leafLight
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final point in const [
      Offset(59, 74),
      Offset(64, 89),
      Offset(72, 104),
      Offset(123, 78),
      Offset(119, 94),
      Offset(108, 109),
    ]) {
      canvas.drawLine(point.translate(-3, 0), point.translate(3, 0), spine);
    }
  }

  void _drawSunflowerSilhouette(Canvas canvas) {
    _drawLeaf(
      canvas,
      const Offset(84, 122),
      const Offset(31, 107),
      breadth: 20,
    );
    _drawLeaf(
      canvas,
      const Offset(96, 119),
      const Offset(149, 99),
      breadth: 20,
    );
    for (var index = 0; index < 12; index++) {
      canvas.save();
      canvas.translate(90, 51);
      canvas.rotate(index * math.pi / 6);
      final petal = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(0, -39),
          width: 14,
          height: 30,
        ),
        const Radius.circular(9),
      );
      canvas.drawRRect(
        petal,
        Paint()..color = _palette.bloomLight.withAlpha(175),
      );
      canvas.drawRRect(
        petal,
        Paint()
          ..color = _ink.withAlpha(190)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
      canvas.restore();
    }
  }

  void _drawGroundShadow(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(90, 174), width: 82, height: 12),
      Paint()..color = _ink.withAlpha(38),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(90, 173), width: 56, height: 7),
      Paint()..color = _ink.withAlpha(24),
    );
  }

  void _drawSunny(Canvas canvas) {
    final stem = Path()
      ..moveTo(90, 133)
      ..cubicTo(86, 106, 94, 75, 90, 49);
    _drawStem(canvas, stem, width: 5.8);
    _drawLeaf(
      canvas,
      const Offset(89, 111),
      const Offset(45, 88),
      breadth: 17,
    );
    _drawLeaf(
      canvas,
      const Offset(91, 94),
      const Offset(137, 72),
      breadth: 17,
    );
    _drawRadialFlower(
      canvas,
      const Offset(90, 43),
      petals: 10,
      outerRadius: 38,
      pointed: false,
      face: _FaceMood.happy,
    );
  }

  void _drawRainy(Canvas canvas) {
    final stem = Path()
      ..moveTo(90, 133)
      ..cubicTo(85, 108, 75, 86, 82, 58);
    _drawStem(canvas, stem, width: 5.5);
    _drawLeaf(
      canvas,
      const Offset(87, 111),
      const Offset(43, 126),
      breadth: 13,
    );
    _drawLeaf(
      canvas,
      const Offset(83, 92),
      const Offset(126, 108),
      breadth: 13,
    );
    _drawStem(
      canvas,
      Path()
        ..moveTo(84, 91)
        ..quadraticBezierTo(105, 80, 126, 78),
      width: 3.2,
    );
    _drawRainBell(canvas, const Offset(82, 50));
    _drawDropBud(canvas, const Offset(126, 78));
  }

  void _drawEmber(Canvas canvas) {
    final stem = Path()
      ..moveTo(90, 133)
      ..cubicTo(92, 108, 87, 78, 91, 55);
    _drawStem(canvas, stem, width: 6);
    _drawSerratedLeaf(
      canvas,
      const Offset(90, 112),
      const Offset(44, 82),
      breadth: 12,
    );
    _drawSerratedLeaf(
      canvas,
      const Offset(90, 92),
      const Offset(138, 65),
      breadth: 12,
    );
    _drawFlameFlower(canvas, const Offset(91, 48));
  }

  void _drawMoonlit(Canvas canvas) {
    final stem = Path()
      ..moveTo(90, 133)
      ..cubicTo(70, 105, 73, 72, 90, 53);
    _drawStem(canvas, stem, width: 5.2);
    _drawLeaf(
      canvas,
      const Offset(83, 111),
      const Offset(45, 83),
      breadth: 8,
    );
    _drawLeaf(
      canvas,
      const Offset(80, 91),
      const Offset(117, 72),
      breadth: 8,
    );
    _drawMoonFlower(canvas, const Offset(91, 44));
  }

  void _drawSparkling(Canvas canvas) {
    final mainStem = Path()
      ..moveTo(90, 133)
      ..cubicTo(90, 103, 91, 73, 91, 48);
    _drawStem(canvas, mainStem, width: 5.4);
    _drawStem(
      canvas,
      Path()
        ..moveTo(89, 94)
        ..quadraticBezierTo(75, 77, 64, 62),
      width: 3.4,
    );
    _drawStem(
      canvas,
      Path()
        ..moveTo(92, 99)
        ..quadraticBezierTo(108, 81, 119, 66),
      width: 3.4,
    );
    _drawHeartLeaf(canvas, const Offset(88, 112), const Offset(50, 95));
    _drawHeartLeaf(canvas, const Offset(92, 95), const Offset(131, 88));
    _drawStarBloom(canvas, const Offset(91, 42), radius: 22, large: true);
    _drawStarBloom(canvas, const Offset(61, 59), radius: 16);
    _drawStarBloom(canvas, const Offset(122, 62), radius: 16);
  }

  void _drawMosaic(Canvas canvas) {
    final stem = Path()
      ..moveTo(90, 133)
      ..cubicTo(96, 106, 84, 76, 92, 50);
    _drawStem(canvas, stem, width: 5.7);
    _drawStem(
      canvas,
      Path()
        ..moveTo(90, 106)
        ..quadraticBezierTo(68, 91, 53, 75),
      width: 3.2,
    );
    _drawLeaf(
      canvas,
      const Offset(91, 114),
      const Offset(45, 106),
      breadth: 17,
    );
    _drawSerratedLeaf(
      canvas,
      const Offset(91, 94),
      const Offset(137, 76),
      breadth: 10,
    );
    _drawHeartLeaf(canvas, const Offset(54, 76), const Offset(35, 58));
    _drawPinwheelFlower(canvas, const Offset(92, 44));
  }

  void _drawStem(Canvas canvas, Path path, {required double width}) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _palette.leafShadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _palette.leafLight.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawLeaf(
    Canvas canvas,
    Offset base,
    Offset tip, {
    required double breadth,
  }) {
    final vector = tip - base;
    final length = vector.distance;
    final normal = Offset(-vector.dy / length, vector.dx / length);
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(
        base.dx + vector.dx * .34 + normal.dx * breadth,
        base.dy + vector.dy * .34 + normal.dy * breadth,
        base.dx + vector.dx * .72 + normal.dx * breadth * .82,
        base.dy + vector.dy * .72 + normal.dy * breadth * .82,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        base.dx + vector.dx * .72 - normal.dx * breadth * .82,
        base.dy + vector.dy * .72 - normal.dy * breadth * .82,
        base.dx + vector.dx * .34 - normal.dx * breadth,
        base.dy + vector.dy * .34 - normal.dy * breadth,
        base.dx,
        base.dy,
      )
      ..close();
    _fillPath(canvas, path, _palette.leaf);
    final shade = Path()
      ..moveTo(base.dx, base.dy)
      ..lineTo(tip.dx, tip.dy)
      ..cubicTo(
        base.dx + vector.dx * .7 - normal.dx * breadth * .72,
        base.dy + vector.dy * .7 - normal.dy * breadth * .72,
        base.dx + vector.dx * .3 - normal.dx * breadth * .85,
        base.dy + vector.dy * .3 - normal.dy * breadth * .85,
        base.dx,
        base.dy,
      )
      ..close();
    canvas.drawPath(shade, Paint()..color = _palette.leafShadow.withAlpha(190));
    _strokePath(canvas, path, width: 3);
    canvas.drawLine(
      base,
      Offset.lerp(base, tip, .78)!,
      Paint()
        ..color = _inkSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawSerratedLeaf(
    Canvas canvas,
    Offset base,
    Offset tip, {
    required double breadth,
  }) {
    final vector = tip - base;
    final length = vector.distance;
    final normal = Offset(-vector.dy / length, vector.dx / length);
    final points = <Offset>[base];
    for (var index = 1; index <= 5; index++) {
      final t = index / 6;
      final wave = index.isEven ? .6 : 1.0;
      points.add(
        base + vector * t + normal * breadth * math.sin(math.pi * t) * wave,
      );
    }
    points.add(tip);
    for (var index = 5; index >= 1; index--) {
      final t = index / 6;
      final wave = index.isEven ? .6 : 1.0;
      points.add(
        base + vector * t - normal * breadth * math.sin(math.pi * t) * wave,
      );
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    _fillPath(canvas, path, _palette.leaf);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          base.dx + vector.dx * .45 - normal.dx * breadth * .55,
          base.dy + vector.dy * .45 - normal.dy * breadth * .55,
        )
        ..close(),
      Paint()..color = _palette.leafShadow.withAlpha(190),
    );
    _strokePath(canvas, path, width: 3);
    canvas.drawLine(
      base,
      Offset.lerp(base, tip, .8)!,
      Paint()
        ..color = _inkSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawHeartLeaf(Canvas canvas, Offset base, Offset tip) {
    final vector = tip - base;
    final length = vector.distance;
    final normal = Offset(-vector.dy / length, vector.dx / length);
    final shoulder = base + vector * .38;
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(
        shoulder.dx + normal.dx * 18,
        shoulder.dy + normal.dy * 18,
        tip.dx + normal.dx * 16,
        tip.dy + normal.dy * 16,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        tip.dx - normal.dx * 16,
        tip.dy - normal.dy * 16,
        shoulder.dx - normal.dx * 18,
        shoulder.dy - normal.dy * 18,
        base.dx,
        base.dy,
      )
      ..quadraticBezierTo(
        shoulder.dx,
        shoulder.dy,
        base.dx,
        base.dy,
      )
      ..close();
    _fillPath(canvas, path, _palette.leaf);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..lineTo(tip.dx, tip.dy)
        ..quadraticBezierTo(
          shoulder.dx - normal.dx * 13,
          shoulder.dy - normal.dy * 13,
          base.dx,
          base.dy,
        )
        ..close(),
      Paint()..color = _palette.leafShadow.withAlpha(185),
    );
    _strokePath(canvas, path, width: 3);
    canvas.drawLine(
      base,
      Offset.lerp(base, tip, .72)!,
      Paint()
        ..color = _inkSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawRadialFlower(
    Canvas canvas,
    Offset center, {
    required int petals,
    required double outerRadius,
    required bool pointed,
    required _FaceMood face,
  }) {
    for (var index = 0; index < petals; index++) {
      final angle = index * math.pi * 2 / petals - math.pi / 2;
      _drawPetal(
        canvas,
        center,
        angle: angle,
        length: outerRadius,
        breadth: pointed ? 8 : 11,
        pointed: pointed,
        color: index.isEven ? _palette.bloom : _palette.bloomLight,
      );
    }
    _drawCore(canvas, center, radius: 15, face: face);
  }

  void _drawPetal(
    Canvas canvas,
    Offset center, {
    required double angle,
    required double length,
    required double breadth,
    required bool pointed,
    required Color color,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final path = Path()..moveTo(4, 0);
    if (pointed) {
      path
        ..quadraticBezierTo(length * .55, -breadth, length, 0)
        ..quadraticBezierTo(length * .55, breadth, 4, 0);
    } else {
      path
        ..cubicTo(
          length * .45,
          -breadth,
          length * .92,
          -breadth,
          length,
          0,
        )
        ..cubicTo(
          length * .92,
          breadth,
          length * .45,
          breadth,
          4,
          0,
        );
    }
    path.close();
    _fillPath(canvas, path, color);
    canvas.drawPath(
      Path()
        ..moveTo(length * .45, 1)
        ..lineTo(length * .92, 0)
        ..quadraticBezierTo(
            length * .7, breadth * .75, length * .4, breadth * .45)
        ..close(),
      Paint()..color = _palette.bloomShadow.withAlpha(178),
    );
    _strokePath(canvas, path, width: pointed ? 3 : 2.8);
    canvas.drawLine(
      const Offset(8, -1.5),
      Offset(length * .55, -1.5),
      Paint()
        ..color = Colors.white.withAlpha(75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _drawRainBell(Canvas canvas, Offset center) {
    final bell = Path()
      ..moveTo(center.dx - 27, center.dy - 13)
      ..quadraticBezierTo(
          center.dx, center.dy - 30, center.dx + 27, center.dy - 13)
      ..cubicTo(
        center.dx + 25,
        center.dy + 6,
        center.dx + 18,
        center.dy + 21,
        center.dx + 10,
        center.dy + 22,
      )
      ..quadraticBezierTo(
          center.dx + 3, center.dy + 12, center.dx, center.dy + 22)
      ..quadraticBezierTo(
          center.dx - 7, center.dy + 12, center.dx - 12, center.dy + 22)
      ..cubicTo(
        center.dx - 22,
        center.dy + 17,
        center.dx - 26,
        center.dy + 4,
        center.dx - 27,
        center.dy - 13,
      )
      ..close();
    _fillPath(canvas, bell, _palette.bloom);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx + 8, center.dy - 18)
        ..quadraticBezierTo(
            center.dx + 27, center.dy - 5, center.dx + 11, center.dy + 20)
        ..quadraticBezierTo(
            center.dx + 2, center.dy + 10, center.dx + 2, center.dy - 15)
        ..close(),
      Paint()..color = _palette.bloomShadow.withAlpha(190),
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: center.translate(-5, -6),
        width: 30,
        height: 22,
      ),
      3.45,
      1.15,
      false,
      Paint()
        ..color = _palette.bloomLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    _strokePath(canvas, bell, width: 3.4);
    _drawFace(canvas, center.translate(0, 2), 5.2, _FaceMood.sad);
  }

  void _drawDropBud(Canvas canvas, Offset center) {
    final drop = Path()
      ..moveTo(center.dx, center.dy - 16)
      ..cubicTo(
        center.dx - 14,
        center.dy - 1,
        center.dx - 12,
        center.dy + 13,
        center.dx,
        center.dy + 15,
      )
      ..cubicTo(
        center.dx + 12,
        center.dy + 13,
        center.dx + 14,
        center.dy - 1,
        center.dx,
        center.dy - 16,
      )
      ..close();
    _fillPath(canvas, drop, _palette.bloomLight);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx + 1, center.dy - 13)
        ..quadraticBezierTo(
            center.dx + 13, center.dy + 2, center.dx + 2, center.dy + 13)
        ..quadraticBezierTo(
            center.dx + 7, center.dy, center.dx + 1, center.dy - 13)
        ..close(),
      Paint()..color = _palette.bloomShadow.withAlpha(175),
    );
    _strokePath(canvas, drop, width: 2.8);
  }

  void _drawFlameFlower(Canvas canvas, Offset center) {
    for (var index = 0; index < 7; index++) {
      final angle = index * math.pi * 2 / 7 - math.pi / 2;
      final length = index == 0 ? 43.0 : (index.isEven ? 36.0 : 31.0);
      _drawPetal(
        canvas,
        center,
        angle: angle,
        length: length,
        breadth: 8,
        pointed: true,
        color: index.isEven ? _palette.bloom : _palette.bloomLight,
      );
    }
    _drawCore(
      canvas,
      center,
      radius: 15,
      face: _FaceMood.determined,
    );
  }

  void _drawMoonFlower(Canvas canvas, Offset center) {
    final outer = Path()..addOval(Rect.fromCircle(center: center, radius: 32));
    final inner = Path()
      ..addOval(Rect.fromCircle(center: center.translate(13, -8), radius: 25));
    final crescent = Path.combine(PathOperation.difference, outer, inner);
    _fillPath(canvas, crescent, _palette.bloom);
    canvas.save();
    canvas.clipPath(crescent);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-10, 12),
        width: 45,
        height: 34,
      ),
      Paint()..color = _palette.bloomShadow,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center.translate(-2, -2), radius: 25),
      2.75,
      1.15,
      false,
      Paint()
        ..color = _palette.bloomLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    _strokePath(canvas, crescent, width: 3.3);
    _drawCore(
      canvas,
      center.translate(-8, 11),
      radius: 11,
      face: _FaceMood.sleepy,
    );
  }

  void _drawStarBloom(
    Canvas canvas,
    Offset center, {
    required double radius,
    bool large = false,
  }) {
    final path = _starPath(center, radius, radius * .48, points: 6);
    _fillPath(
      canvas,
      path,
      large ? _palette.bloom : _palette.bloomLight,
    );
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      _starPath(center.translate(3, 4), radius * .72, radius * .35, points: 6),
      Paint()..color = _palette.bloomShadow.withAlpha(165),
    );
    canvas.restore();
    _strokePath(canvas, path, width: large ? 3.2 : 2.7);
    final coreRadius = large ? 8.0 : 6.0;
    _drawCore(
      canvas,
      center,
      radius: coreRadius,
      face: large ? _FaceMood.surprised : null,
    );
  }

  void _drawPinwheelFlower(Canvas canvas, Offset center) {
    const lengths = [39.0, 31.0, 36.0, 28.0, 40.0, 32.0];
    final colors = [
      _palette.bloom,
      _palette.bloomLight,
      _palette.bloomShadow,
    ];
    for (var index = 0; index < lengths.length; index++) {
      final angle = index * math.pi * 2 / lengths.length - math.pi / 2;
      _drawPetal(
        canvas,
        center,
        angle: angle + .18,
        length: lengths[index],
        breadth: index.isEven ? 12 : 9,
        pointed: index.isOdd,
        color: colors[index % colors.length],
      );
    }
    _drawCore(
      canvas,
      center,
      radius: 14,
      face: _FaceMood.content,
    );
  }

  void _drawCore(
    Canvas canvas,
    Offset center, {
    required double radius,
    _FaceMood? face,
  }) {
    final core = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    _fillPath(canvas, core, _palette.core);
    canvas.save();
    canvas.clipPath(core);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(radius * .55, radius * .42),
        width: radius * 1.25,
        height: radius * 1.45,
      ),
      Paint()..color = _palette.coreShadow,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center.translate(-1, -2), radius: radius * .68),
      3.5,
      1.1,
      false,
      Paint()
        ..color = Colors.white.withAlpha(78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    _strokePath(canvas, core, width: math.max(2.3, radius * .21));
    if (face != null && radius >= 8) {
      _drawFace(canvas, center, math.max(3.3, radius * .35), face);
    }
  }

  Path _starPath(
    Offset center,
    double outer,
    double inner, {
    required int points,
  }) {
    final path = Path();
    for (var index = 0; index < points * 2; index++) {
      final radius = index.isEven ? outer : inner;
      final angle = -math.pi / 2 + index * math.pi / points;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  void _drawPot(Canvas canvas) {
    final body = Path()
      ..moveTo(61, 137)
      ..quadraticBezierTo(62, 157, 68, 170)
      ..quadraticBezierTo(90, 178, 112, 170)
      ..quadraticBezierTo(118, 157, 119, 137)
      ..close();
    _fillPath(canvas, body, _pot);
    canvas.drawPath(
      Path()
        ..moveTo(104, 139)
        ..quadraticBezierTo(112, 151, 108, 169)
        ..quadraticBezierTo(115, 166, 119, 137)
        ..close(),
      Paint()..color = _potShadow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(67, 141)
        ..quadraticBezierTo(69, 156, 74, 163)
        ..quadraticBezierTo(78, 165, 80, 162)
        ..quadraticBezierTo(75, 151, 76, 141)
        ..close(),
      Paint()..color = _potLight.withAlpha(150),
    );
    _strokePath(canvas, body, width: 3.4);

    final rim = RRect.fromRectAndRadius(
      const Rect.fromLTWH(55, 126, 70, 18),
      const Radius.circular(8),
    );
    canvas.drawRRect(rim, Paint()..color = _potLight);
    canvas.drawOval(
      const Rect.fromLTWH(61, 127, 58, 11),
      Paint()..color = _soil,
    );
    canvas.drawArc(
      const Rect.fromLTWH(58, 127, 64, 16),
      .1,
      math.pi * .82,
      false,
      Paint()
        ..color = _potShadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4,
    );
    _drawPotMark(canvas);
  }

  void _drawPotMark(Canvas canvas) {
    final paint = Paint()
      ..color = _inkSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (form) {
      case PlantFinalForm.sunny:
        canvas.drawCircle(const Offset(90, 156), 4.5, paint);
        for (var index = 0; index < 4; index++) {
          final angle = index * math.pi / 2;
          canvas.drawLine(
            Offset(90 + math.cos(angle) * 7, 156 + math.sin(angle) * 7),
            Offset(90 + math.cos(angle) * 9, 156 + math.sin(angle) * 9),
            paint,
          );
        }
      case PlantFinalForm.rainy:
        canvas.drawPath(
          Path()
            ..moveTo(90, 149)
            ..quadraticBezierTo(82, 160, 90, 163)
            ..quadraticBezierTo(98, 160, 90, 149),
          paint,
        );
      case PlantFinalForm.ember:
        canvas.drawPath(
          Path()
            ..moveTo(89, 164)
            ..quadraticBezierTo(82, 157, 91, 148)
            ..quadraticBezierTo(99, 157, 89, 164),
          paint,
        );
      case PlantFinalForm.moonlit:
        canvas.drawArc(
          const Rect.fromLTWH(84, 149, 13, 14),
          math.pi / 2,
          math.pi,
          false,
          paint,
        );
      case PlantFinalForm.sparkling:
        canvas.drawPath(
            _starPath(const Offset(90, 156), 7, 3, points: 4), paint);
      case PlantFinalForm.mosaic:
        canvas.drawCircle(const Offset(87, 154), 3, paint);
        canvas.drawCircle(const Offset(94, 159), 3, paint);
    }
  }

  void _drawFace(
    Canvas canvas,
    Offset center,
    double unit,
    _FaceMood mood,
  ) {
    final fill = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, unit * .3)
      ..strokeCap = StrokeCap.round;
    final eyeX = unit * .95;
    final eyeY = center.dy - unit * .3;

    if (mood == _FaceMood.happy ||
        mood == _FaceMood.sleepy ||
        mood == _FaceMood.content) {
      for (final direction in [-1.0, 1.0]) {
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(center.dx + direction * eyeX, eyeY),
            width: unit * .86,
            height: unit * .62,
          ),
          mood == _FaceMood.sleepy ? 0 : math.pi + .2,
          mood == _FaceMood.sleepy ? math.pi : math.pi - .4,
          false,
          stroke,
        );
      }
    } else {
      canvas.drawCircle(Offset(center.dx - eyeX, eyeY), unit * .2, fill);
      canvas.drawCircle(Offset(center.dx + eyeX, eyeY), unit * .2, fill);
      if (mood == _FaceMood.determined) {
        canvas.drawLine(
          Offset(center.dx - eyeX - unit * .35, eyeY - unit * .75),
          Offset(center.dx - eyeX + unit * .35, eyeY - unit * .5),
          stroke,
        );
        canvas.drawLine(
          Offset(center.dx + eyeX - unit * .35, eyeY - unit * .5),
          Offset(center.dx + eyeX + unit * .35, eyeY - unit * .75),
          stroke,
        );
      }
    }

    final mouth = Rect.fromCenter(
      center: center.translate(0, unit * .55),
      width: unit * 1.2,
      height: unit * .82,
    );
    switch (mood) {
      case _FaceMood.happy:
      case _FaceMood.content:
        canvas.drawArc(mouth, .45, math.pi - .9, false, stroke);
      case _FaceMood.sad:
        canvas.drawArc(
          mouth.translate(0, unit * .35),
          math.pi + .45,
          math.pi - .9,
          false,
          stroke,
        );
      case _FaceMood.determined:
      case _FaceMood.sleepy:
        canvas.drawLine(
          Offset(center.dx - unit * .38, center.dy + unit * .6),
          Offset(center.dx + unit * .38, center.dy + unit * .6),
          stroke,
        );
      case _FaceMood.surprised:
        canvas.drawOval(
          Rect.fromCenter(
            center: center.translate(0, unit * .65),
            width: unit * .55,
            height: unit * .75,
          ),
          stroke,
        );
    }
  }

  void _fillPath(Canvas canvas, Path path, Color color) {
    canvas.drawPath(path, Paint()..color = color);
  }

  void _strokePath(Canvas canvas, Path path, {required double width}) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant EmotionPlantPainter oldDelegate) =>
      oldDelegate.form != form || oldDelegate.speciesCode != speciesCode;
}

String _fallbackSpeciesName(String code) => switch (code.trim().toLowerCase()) {
      'basic_sprout' => '새싹몬',
      'cactus' => '가시니',
      'sunflower' => '해바라기',
      _ => '이름 없는 식물',
    };

enum _FaceMood { happy, sad, determined, sleepy, surprised, content }

class _PlantPalette {
  const _PlantPalette({
    required this.leaf,
    required this.leafLight,
    required this.leafShadow,
    required this.bloom,
    required this.bloomLight,
    required this.bloomShadow,
    required this.core,
    required this.coreShadow,
  });

  final Color leaf;
  final Color leafLight;
  final Color leafShadow;
  final Color bloom;
  final Color bloomLight;
  final Color bloomShadow;
  final Color core;
  final Color coreShadow;
}
