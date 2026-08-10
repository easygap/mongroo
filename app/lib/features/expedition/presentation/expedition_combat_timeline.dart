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
      cue.playsPartyAttack ? .52 : .24;

  static double enemyEffectEnd(ExpeditionActionCue cue) =>
      cue.playsPartyAttack ? .91 : .94;

  static double enemyContactProgress(ExpeditionActionCue cue) =>
      cue.playsPartyAttack ? .72 : .62;

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
    final profile = cue.motionProfile ?? '';
    if (profile.contains('venom-draw') || profile.contains('undying-chain')) {
      final windUp = math.sin(segment(value, .02, .18) * math.pi);
      final release = math.sin(segment(value, .14, .34) * math.pi);
      return Offset(-8 * windUp + 14 * release, 3 * windUp - 5 * release);
    }
    if (profile.contains('shadow-cross')) {
      final dash = math.sin(segment(value, .04, .52) * math.pi);
      final settle = math.sin(segment(value, .55, .82) * math.pi);
      return Offset(48 * dash - 8 * settle, -10 * dash);
    }
    if (profile.contains('counter-punch') ||
        profile.contains('iron-uppercut') ||
        profile.contains('forward-brawler') ||
        profile.contains('command-draw') ||
        profile.contains('steel-verdict') ||
        profile.contains('spotlight-step') ||
        profile.contains('ribbon-finale')) {
      final strike = math.sin(segment(value, .04, .50) * math.pi);
      final recoil = math.sin(segment(value, .54, .80) * math.pi);
      return Offset(38 * strike - 7 * recoil, -12 * strike);
    }
    if (profile.contains('circling-tempest')) {
      final orbit = segment(value, .04, .68);
      final envelope = math.sin(orbit * math.pi);
      return Offset(
        math.sin(orbit * math.pi * 2) * 22 * envelope,
        -15 * envelope,
      );
    }
    if (profile.isNotEmpty) {
      // 주문·지휘·지원기는 자리를 지킨 채 떠오른다. 공격 본체와 궤적은 이
      // 좌표식이 아니라 검수된 래스터 프레임 시퀀스가 전담한다.
      final channel = math.sin(segment(value, .04, .68) * math.pi);
      return Offset(
        math.sin(segment(value, .04, .68) * math.pi * 2) * 4 * channel,
        -10 * channel,
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
