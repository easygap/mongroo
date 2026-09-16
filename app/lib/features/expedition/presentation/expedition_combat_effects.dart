import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 배경 원화 위에 전투원의 접지면만 더한다.
///
/// 도트 무대라 번짐이 없다. 발밑 그림자는 두 톤의 납작한 타원이고, 그 타원도
/// 도트 격자([unit])에 물린다. 정적인 한 장으로 유지해 스킬 애니메이션 중에는
/// 다시 그리지 않는다.
class ExpeditionBattleGroundPainter extends CustomPainter {
  const ExpeditionBattleGroundPainter({
    this.unit = 3,
    this.enemyFoot = const Offset(.70, .50),
    this.enemyWidth = 150,
    this.partyFoot = const Offset(.30, .88),
    this.partyWidth = 96,
  });

  /// 도트 한 칸의 논리 픽셀 수.
  final double unit;

  /// 무대 폭·높이에 대한 비율 좌표.
  final Offset enemyFoot;
  final double enemyWidth;
  final Offset partyFoot;
  final double partyWidth;

  @override
  void paint(Canvas canvas, Size size) {
    _shadow(
      canvas,
      Offset(size.width * enemyFoot.dx, size.height * enemyFoot.dy),
      enemyWidth,
    );
    _shadow(
      canvas,
      Offset(size.width * partyFoot.dx, size.height * partyFoot.dy),
      partyWidth,
    );
  }

  void _shadow(Canvas canvas, Offset foot, double width) {
    final flat = Paint()..isAntiAlias = false;
    final height = math.max(unit * 3, width * .22);
    // 타원을 격자에 맞춘 가로 띠들로 그린다 — 안티앨리어싱 없는 타원.
    final rows = (height / unit).round();
    for (var row = 0; row < rows; row++) {
      final t = (row + .5) / rows * 2 - 1;
      final halfWidth = width / 2 * math.sqrt(math.max(0, 1 - t * t));
      final left = ((foot.dx - halfWidth) / unit).round() * unit;
      final right = ((foot.dx + halfWidth) / unit).round() * unit;
      final y = ((foot.dy - height / 2) / unit).round() * unit + row * unit;
      final edge = halfWidth < width * .32;
      canvas.drawRect(
        Rect.fromLTRB(left, y, right, y + unit),
        flat..color = Color.fromRGBO(8, 6, 4, edge ? .22 : .34),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ExpeditionBattleGroundPainter oldDelegate) =>
      oldDelegate.unit != unit ||
      oldDelegate.enemyFoot != enemyFoot ||
      oldDelegate.enemyWidth != enemyWidth ||
      oldDelegate.partyFoot != partyFoot ||
      oldDelegate.partyWidth != partyWidth;
}

/// 공격 전에만 보이는 범위 표식이다. 실제 투사체와 충돌 연출은 검수한
/// 래스터 시퀀스가 담당하며 이 painter는 입력 예고 UI만 그린다.
///
/// 형태는 색을 못 봐도 갈리게 셋이다 — 앞열은 겹화살표, 전체는 동심 고리,
/// 최저 체력은 조준점. 도트 무대라 선도 칸 단위로 끊어 그린다.
class ExpeditionGuardianIntentPainter extends CustomPainter {
  const ExpeditionGuardianIntentPainter({
    required this.phase,
    required this.reduceMotion,
    this.target = 'front',
    this.unit = 3,
    this.anchor = const Offset(.70, .34),
  });

  final double phase;
  final bool reduceMotion;
  final String target;
  final double unit;

  /// 표식의 중심. 무대 비율 좌표.
  final Offset anchor;

  @override
  void paint(Canvas canvas, Size size) {
    final wave = reduceMotion ? .55 : (math.sin(phase * math.pi * 2) + 1) / 2;
    final center = Offset(
      (size.width * anchor.dx / unit).round() * unit,
      (size.height * anchor.dy / unit).round() * unit,
    );
    final color = Color.fromRGBO(140, 232, 223, .55 + wave * .45);
    final flat = Paint()
      ..isAntiAlias = false
      ..color = color;
    final step = unit;
    final reach = (unit * (9 + wave * 2)).roundToDouble();

    void dot(double x, double y) => canvas.drawRect(
          Rect.fromLTWH(
            (x / unit).round() * unit,
            (y / unit).round() * unit,
            unit,
            unit,
          ),
          flat,
        );

    switch (target) {
      case 'all':
        // 세 겹의 납작한 고리.
        for (var ring = 0; ring < 3; ring++) {
          final rx = reach * (.7 + ring * .45);
          final ry = rx * .45;
          final points = (rx / step * 2).round().clamp(12, 64);
          for (var index = 0; index < points; index++) {
            final angle = index / points * math.pi * 2;
            dot(center.dx + math.cos(angle) * rx, center.dy + math.sin(angle) * ry);
          }
        }
      case 'lowest':
        // 조준점: 작은 고리와 네 방향의 짧은 선.
        final r = reach * .6;
        final points = (r / step * 2).round().clamp(10, 40);
        for (var index = 0; index < points; index++) {
          final angle = index / points * math.pi * 2;
          dot(center.dx + math.cos(angle) * r, center.dy + math.sin(angle) * r);
        }
        for (var k = 2; k <= 4; k++) {
          dot(center.dx + k * step + r * .6, center.dy);
          dot(center.dx - k * step - r * .6, center.dy);
          dot(center.dx, center.dy + k * step + r * .6);
          dot(center.dx, center.dy - k * step - r * .6);
        }
      default:
        // 앞열: 왼쪽을 가리키는 겹화살표 둘.
        for (final shift in [0.0, step * 5]) {
          for (var k = 0; k <= 5; k++) {
            dot(center.dx + shift + k * step - step * 2, center.dy - k * step);
            dot(center.dx + shift + k * step - step * 2, center.dy + k * step);
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant ExpeditionGuardianIntentPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.reduceMotion != reduceMotion ||
      oldDelegate.target != target ||
      oldDelegate.unit != unit ||
      oldDelegate.anchor != anchor;
}

/// 색을 보지 않아도 앞열·전체·최저 체력 예고를 구분하는 공용 형태 언어다.
IconData expeditionIntentTargetIcon(String target) => switch (target) {
      'all' => Icons.blur_circular_rounded,
      'lowest' => Icons.gps_fixed_rounded,
      _ => Icons.keyboard_double_arrow_up_rounded,
    };

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
      'ink_mist' => const Color(0xFF73B8C7),
      'petal_dart' => const Color(0xFFFFAA72),
      _ => const Color(0xFFFFD98A),
    };
