import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 엉킴의 절차적 몸체.
///
/// 엉킴 12종의 원화가 아직 없으므로, 개편 설계서 3.3의 인상 규칙 —
/// "뭉치고 엉킨 실루엣에 눈만 붙은, 곤란해 보이는" — 을 코드로 그린다.
/// 이름 문자열을 시드로 써서 같은 엉킴은 언제나 같은 모습이고, 장벽이 0이
/// 되면 소멸이 아니라 뭉치가 바깥으로 풀리며 사라진다(풀려남).
class ExpeditionTangleBody extends StatelessWidget {
  const ExpeditionTangleBody({
    super.key,
    required this.seedText,
    required this.elite,
    required this.hit,
    required this.attack,
    required this.released,
    required this.flash,
  });

  /// 엉킴 이름. 같은 이름은 같은 실뭉치 배치를 그린다.
  final String seedText;
  final bool elite;

  /// 0~1. 공격을 맞은 순간의 움츠림.
  final double hit;

  /// 0~1. 예고 공격을 실행하는 순간의 들썩임.
  final double attack;

  /// 0~1. 풀려남 — 뭉치가 흩어지며 원래 물건으로 돌아가는 연출.
  final double released;

  /// 0~1. 피격 섬광.
  final double flash;

  @override
  Widget build(BuildContext context) => CustomPaint(
        key: const ValueKey('tangle-body'),
        painter: _TangleBodyPainter(
          seed: seedText.hashCode,
          elite: elite,
          hit: hit.clamp(0, 1),
          attack: attack.clamp(0, 1),
          released: released.clamp(0, 1),
          flash: flash.clamp(0, 1),
        ),
      );
}

class _TangleBodyPainter extends CustomPainter {
  const _TangleBodyPainter({
    required this.seed,
    required this.elite,
    required this.hit,
    required this.attack,
    required this.released,
    required this.flash,
  });

  final int seed;
  final bool elite;
  final double hit;
  final double attack;
  final double released;
  final double flash;

  // 지역 톤과 어울리는 네 가지 실 색. 시드로 하나를 고른다.
  static const _palettes = [
    (Color(0xFF8A9A5B), Color(0xFF57683A)), // 이끼 초록
    (Color(0xFFB99A6B), Color(0xFF7C6142)), // 낡은 장부 갈색
    (Color(0xFF7B93B5), Color(0xFF4C617E)), // 물빛 남색
    (Color(0xFFA98BB0), Color(0xFF6F567A)), // 별가루 보라
  ];

  double _random(int index) {
    final value = math.sin((seed % 100000) * .017 + index * 12.9898) * 43758.5453;
    return value - value.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .62);
    final base = math.min(size.width, size.height) *
        (elite ? .30 : .24) *
        (1 + attack * .04);
    final (bodyColor, lineColor) = _palettes[seed.abs() % _palettes.length];
    final opacity = (1 - released).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    canvas.save();
    // 피격 순간에는 살짝 움츠러들고, 공격 순간에는 앞으로 기운다.
    canvas.translate(center.dx, center.dy);
    canvas.scale(1 + hit * .08, 1 - hit * .10);
    canvas.rotate(-attack * .05);
    canvas.translate(-center.dx, -center.dy);

    final fill = Paint()..color = bodyColor.withValues(alpha: opacity);
    final outline = Paint()
      ..color = lineColor.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = elite ? 5 : 3.4
      ..strokeCap = StrokeCap.round;

    // 실뭉치: 겹친 원 일곱 개가 시드에 따라 제멋대로 뭉친다.
    // 풀려날 때는 각 뭉치가 자기 방향으로 흩어진다.
    for (var index = 0; index < 7; index++) {
      final angle = _random(index) * math.pi * 2;
      final distance = base * (.16 + _random(index + 20) * .52);
      final radius = base * (.34 + _random(index + 40) * .40);
      final scatter = released * base * (1.3 + _random(index + 60));
      final blob = center +
          Offset(math.cos(angle), math.sin(angle) * .78) * distance +
          Offset(math.cos(angle), math.sin(angle)) * scatter;
      canvas.drawCircle(blob, radius * (1 - released * .45), fill);
      // 실 가닥: 뭉치 위를 지나는 곡선 한 가닥씩.
      final thread = Path()
        ..addArc(
          Rect.fromCircle(center: blob, radius: radius * .78),
          angle + _random(index + 80) * 2,
          math.pi * (1.05 + _random(index + 90) * .6),
        );
      canvas.drawPath(thread, outline);
    }
    // 흘러내린 실 꼬리 — 엉킴이 물건이었음을 보여 주는 실마리.
    final tail = Path()
      ..moveTo(center.dx - base * .1, center.dy + base * .78)
      ..quadraticBezierTo(
        center.dx + base * (.3 + released * .8),
        center.dy + base * (1.02 + released * .5),
        center.dx + base * (.72 + released * 1.6),
        center.dy + base * (.92 + released * .3),
      );
    canvas.drawPath(tail, outline);

    // 곤란한 눈: 아래를 보는 눈동자와 팔자 눈썹.
    final eyeOpacity = (1 - released * 2).clamp(0.0, 1.0);
    if (eyeOpacity > 0) {
      final eyeOffset = base * .30;
      final eyeRadius = base * (elite ? .15 : .13);
      final white = Paint()..color = Colors.white.withValues(alpha: eyeOpacity);
      final pupil = Paint()
        ..color = const Color(0xFF33302B).withValues(alpha: eyeOpacity);
      final brow = Paint()
        ..color = lineColor.withValues(alpha: eyeOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (final side in const [-1.0, 1.0]) {
        final eye = center + Offset(eyeOffset * side, -base * .18);
        canvas.drawOval(
          Rect.fromCenter(
            center: eye,
            width: eyeRadius * 2,
            height: eyeRadius * 2.3,
          ),
          white,
        );
        canvas.drawCircle(
          eye + Offset(eyeRadius * .2 * side, eyeRadius * (.45 + hit * .3)),
          eyeRadius * .45,
          pupil,
        );
        canvas.drawLine(
          eye + Offset(-eyeRadius * side, -eyeRadius * 1.6),
          eye + Offset(eyeRadius * .6 * side, -eyeRadius * 1.15),
          brow,
        );
      }
    }

    // 피격 섬광 — 흰빛이 뭉치 위로 잠깐 스친다.
    if (flash > .02) {
      canvas.drawCircle(
        center,
        base * 1.05,
        Paint()..color = Colors.white.withValues(alpha: flash * .5 * opacity),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TangleBodyPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.elite != elite ||
      oldDelegate.hit != hit ||
      oldDelegate.attack != attack ||
      oldDelegate.released != released ||
      oldDelegate.flash != flash;
}
