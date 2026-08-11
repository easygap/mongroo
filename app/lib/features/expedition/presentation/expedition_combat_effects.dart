import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 배경 원화 위에 전투원의 접지면과 시선 유도광만 더한다.
/// 정적인 한 장으로 유지해 스킬 애니메이션 중에는 다시 그리지 않는다.
class ExpeditionBattleGroundPainter extends CustomPainter {
  const ExpeditionBattleGroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final floor = Offset(size.width * .52, size.height * .82);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [.38, 1],
          colors: [Colors.transparent, Color(0xA8121725)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: floor,
        width: size.width * .92,
        height: size.height * .30,
      ),
      Paint()
        ..color = const Color(0x5C07121D)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    for (var ring = 0; ring < 3; ring++) {
      canvas.drawArc(
        Rect.fromCenter(
          center: floor,
          width: size.width * (.52 + ring * .14),
          height: size.height * (.12 + ring * .035),
        ),
        math.pi * .08,
        math.pi * .84,
        false,
        Paint()
          ..color = const Color(0xFF8CE8DF).withAlpha(34 - ring * 7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    const motes = <Offset>[
      Offset(.09, .43),
      Offset(.18, .27),
      Offset(.38, .34),
      Offset(.61, .22),
      Offset(.82, .32),
      Offset(.91, .48),
    ];
    for (var index = 0; index < motes.length; index++) {
      final point = Offset(
        size.width * motes[index].dx,
        size.height * motes[index].dy,
      );
      canvas.drawCircle(
        point,
        index.isEven ? 1.8 : 1.2,
        Paint()
          ..color = const Color(0xFFB8F3E9).withAlpha(90)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ExpeditionBattleGroundPainter oldDelegate) =>
      false;
}

/// 공격 전에만 보이는 범위 표식이다. 실제 투사체와 충돌 연출은 검수한
/// 래스터 시퀀스가 담당하며 이 painter는 입력 예고 UI만 그린다.
class ExpeditionGuardianIntentPainter extends CustomPainter {
  const ExpeditionGuardianIntentPainter({
    required this.phase,
    required this.reduceMotion,
  });

  final double phase;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .75, size.height * .50);
    final wave = reduceMotion ? .55 : (math.sin(phase * math.pi * 2) + 1) / 2;
    final color = const Color(0xFF8CE8DF);
    final radius = 34 + wave * 11;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: radius * 2.2, height: radius),
      Paint()
        ..color = color.withAlpha((30 + wave * 28).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 5),
      -math.pi / 2,
      math.pi * (1.15 + wave * .55),
      false,
      Paint()
        ..color = color.withAlpha((100 + wave * 80).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      center,
      6.2 + wave * 2.8,
      Paint()
        ..color = color.withAlpha((95 + wave * 80).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant ExpeditionGuardianIntentPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.reduceMotion != reduceMotion;
}

Color expeditionCombatEffectColor(String key) => switch (key) {
      'care_vines' => const Color(0xFF8EE0A8),
      'safe_guard' => const Color(0xFF9FE7D2),
      'ember_arc' => const Color(0xFFFF9B71),
      'prism_burst' => const Color(0xFFD7B8FF),
      'mist_dash' => const Color(0xFF9EDCF3),
      'venom_seam' => const Color(0xFF9C55D8),
      'insight_arc' => const Color(0xFF8ED7FF),
      'enemy_wave' => const Color(0xFFFF7968),
      'paper_flurry' => const Color(0xFFBDEAF0),
      _ => const Color(0xFFFFD98A),
    };
