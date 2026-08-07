import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'expedition_action_cue.dart';

/// 전투 연출의 시간 구간과 보간식을 한곳에서 관리한다.
///
/// 서버 판정은 이미 끝난 상태에서 이 값들은 결과를 읽기 쉬운 순서로 보여 주는
/// 역할만 한다. 연출 시간을 바꿀 때는 개별 위젯 대신 이 파일의 구간을 조정한다.
abstract final class ExpeditionCombatTimeline {
  static const guardianDuration = Duration(milliseconds: 1900);
  static const skillDuration = Duration(milliseconds: 1250);
  static const partyCommandDuration = Duration(milliseconds: 760);
  static const enemyCommandDuration = Duration(milliseconds: 940);
  static const resultHoldDuration = Duration(milliseconds: 620);
  static const commandHoldDuration = Duration(milliseconds: 110);
  static const enemyHoldDuration = Duration(milliseconds: 210);
  // 마지막 타격 뒤 쓰러진 수호자를 읽을 시간을 보장한다. 이보다 짧으면
  // 서버 결과 화면 전환이 처치 프레임을 덮어 승리감이 약해진다.
  static const terminalOutcomeHoldDuration = Duration(milliseconds: 1100);
  static const reducedMotionResultHoldDuration = Duration(milliseconds: 700);
  static const reducedMotionCommandHoldDuration = Duration(milliseconds: 240);

  static double segment(double value, double start, double end) =>
      ((value - start) / (end - start)).clamp(0.0, 1.0);

  static double floatingOpacity(double value, double start, double end) {
    final local = segment(value, start, end);
    return math.sin(local * math.pi).clamp(0.0, 1.0);
  }

  /// 피격 순간에만 무대를 흔든다. 진폭은 멀미를 줄이기 위해 3.5px로 제한한다.
  static Offset impactShake(double value) {
    final local = segment(value, .70, .84);
    if (local <= 0 || local >= 1) return Offset.zero;
    final strength = math.sin(local * math.pi) * 3.5;
    return Offset(math.sin(local * math.pi * 8) * strength, 0);
  }

  /// 대원의 공격이 장벽에 닿는 순간만 짧게 흔든다.
  static Offset partyImpactShake(double value) {
    final local = segment(value, .31, .48);
    if (local <= 0 || local >= 1) return Offset.zero;
    final strength = math.sin(local * math.pi) * 2.8;
    return Offset(math.sin(local * math.pi * 7) * strength, 0);
  }

  /// 캐릭터가 스킬을 준비하고 되밀리는 동선을 계산한다.
  static Offset actorOffset(double value, ExpeditionActionCue? cue) {
    if (cue == null) return Offset.zero;
    if (cue.isCombatRound && !cue.playsPartyAttack) {
      final recoil = math.sin(segment(value, .38, .76) * math.pi) * -18;
      return Offset(
        recoil,
        4 * math.sin(segment(value, .38, .76) * math.pi),
      );
    }
    final cast = segment(value, .04, cue.isGuardianExchange ? .44 : .72);
    final lunge = math.sin(cast * math.pi) * 30;
    final recoil = cue.isGuardianExchange
        ? math.sin(segment(value, .68, .88) * math.pi) * -9
        : 0.0;
    return Offset(lunge + recoil, -math.sin(cast * math.pi) * 7);
  }

  static double guardValue({
    required int before,
    required int after,
    required double progress,
  }) =>
      before +
      (after - before) *
          Curves.easeOutCubic.transform(segment(progress, .30, .62));
}
