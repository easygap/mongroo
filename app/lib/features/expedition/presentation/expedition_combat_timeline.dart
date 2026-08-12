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

  /// 적 공격 스프라이트와 피격 피드백이 같은 접촉 프레임을 공유하는 구간이다.
  static double enemyEffectStart(ExpeditionActionCue cue) =>
      cue.playsPartyEffect ? .52 : .24;

  static double enemyEffectEnd(ExpeditionActionCue cue) =>
      cue.playsPartyEffect ? .91 : .94;

  static const double partyEffectStart = .03;
  static const double partyEffectEnd = .58;

  static double partyContactProgress(ExpeditionActionCue cue) =>
      partyEffectStart +
      (partyEffectEnd - partyEffectStart) * cue.partyEffect.contactProgress;

  static double enemyContactProgress(ExpeditionActionCue cue) {
    final start = enemyEffectStart(cue);
    final end = enemyEffectEnd(cue);
    return start + (end - start) * cue.enemyEffect.contactProgress;
  }

  static double floatingOpacity(double value, double start, double end) {
    final local = segment(value, start, end);
    return math.sin(local * math.pi).clamp(0.0, 1.0);
  }

  /// 피격 순간에만 무대를 흔든다. 진폭은 멀미를 줄이기 위해 3.5px로 제한한다.
  static Offset impactShake(double value, [ExpeditionActionCue? cue]) {
    final contact = cue == null ? .72 : enemyContactProgress(cue);
    final local = segment(value, contact - .05, contact + .11);
    if (local <= 0 || local >= 1) return Offset.zero;
    final amplitude = (cue?.motion?.impactShakePx ?? 3.5).clamp(0.0, 3.5);
    final strength = math.sin(local * math.pi) * amplitude;
    return Offset(math.sin(local * math.pi * 8) * strength, 0);
  }

  /// 대원의 공격이 장벽에 닿는 순간만 짧게 흔든다.
  static Offset partyImpactShake(double value, [ExpeditionActionCue? cue]) {
    final contact = cue == null ? .34 : partyContactProgress(cue);
    final local = segment(value, contact - .04, contact + .10);
    if (local <= 0 || local >= 1) return Offset.zero;
    final amplitude = (cue?.motion?.impactShakePx ?? 2.8).clamp(0.0, 3.5);
    final strength = math.sin(local * math.pi) * amplitude;
    return Offset(math.sin(local * math.pi * 7) * strength, 0);
  }

  /// 캐릭터가 스킬을 준비하고 되밀리는 동선을 계산한다.
  static Offset actorOffset(double value, ExpeditionActionCue? cue) {
    if (cue == null) return Offset.zero;
    if (cue.isCombatRound && !cue.playsPartyAttack) {
      final contact = enemyContactProgress(cue);
      final recoil =
          math.sin(segment(value, contact - .06, contact + .20) * math.pi) *
              -18;
      return Offset(
        recoil,
        4 * math.sin(segment(value, contact - .06, contact + .20) * math.pi),
      );
    }
    final motion = cue.motion;
    final archetype = motion?.archetype ?? 'cast';
    final anticipationEnd = motion?.phaseEnd('anticipation') ?? .18;
    final releaseStart = motion?.phaseStart('release') ?? anticipationEnd;
    final contactEnd = motion?.phaseEnd('contact') ?? .62;
    final reactionEnd = motion?.phaseEnd('reaction') ?? .78;
    final travelRatio = (motion?.travelRatio ?? .18).clamp(0.0, 1.0);
    final windUp = math.sin(segment(value, 0, anticipationEnd) * math.pi);
    final action = math.sin(segment(value, releaseStart, contactEnd) * math.pi);
    final settle = math.sin(segment(value, contactEnd, reactionEnd) * math.pi);
    final direction = motion?.facing == 'left' ? -1.0 : 1.0;
    return switch (archetype) {
      'dash' => Offset(
          direction * (18 + 40 * travelRatio) * action - direction * 8 * settle,
          -9 * action,
        ),
      'draw' => Offset(
          direction * (-9 * windUp + (12 + 12 * travelRatio) * action),
          3 * windUp - 5 * action,
        ),
      'brace' => Offset(direction * (-5 * windUp + 3 * settle), 4 * action),
      'channel' => Offset(
          direction * math.sin(value * math.pi * 4) * 3 * action,
          -9 * action - 2 * windUp,
        ),
      'leap' => Offset(
          direction * (12 + 30 * travelRatio) * action - direction * 5 * settle,
          -22 * action,
        ),
      _ => Offset(
          direction * (4 + 8 * travelRatio) * action - direction * 3 * settle,
          -11 * action,
        ),
    };
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
