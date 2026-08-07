import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'expedition_action_cue.dart';
import 'expedition_combat_timeline.dart';

const int expeditionCombatEffectFrameCount = 8;

const Map<String, String> _expeditionCombatEffectDirectories = {
  'care_vines': 'care-vines',
  'safe_guard': 'safe-guard',
  'ember_arc': 'ember-arc',
  'prism_burst': 'prism-burst',
  'mist_dash': 'mist-dash',
  'insight_arc': 'insight-arc',
  'echo_wave': 'echo-wave',
  'enemy_wave': 'enemy-wave',
};

String expeditionCombatEffectAsset(String effectKey, int frame) {
  final directory =
      _expeditionCombatEffectDirectories[effectKey] ?? 'echo-wave';
  final safeFrame = frame.clamp(0, expeditionCombatEffectFrameCount - 1);
  return 'assets/adventure/effects/$directory/frame-${safeFrame.toString().padLeft(2, '0')}.webp';
}

List<String> expeditionCombatEffectAssets(String effectKey) => List.generate(
      expeditionCombatEffectFrameCount,
      (frame) => expeditionCombatEffectAsset(effectKey, frame),
      growable: false,
    );

List<String> get expeditionCombatEffectFirstFrames =>
    _expeditionCombatEffectDirectories.keys
        .map((effectKey) => expeditionCombatEffectAsset(effectKey, 0))
        .toList(growable: false);

/// 검수된 래스터 시퀀스만 재생하는 전투 이펙트 레이어.
///
/// 전투 판정과 프레임 선택은 분리한다. 서버가 보낸 효과 키와 타임라인 구간만
/// 읽고, 공격 궤적이나 충돌 모양을 런타임에서 다시 그리지 않는다.
class ExpeditionCombatSpriteLayer extends StatelessWidget {
  const ExpeditionCombatSpriteLayer({
    super.key,
    required this.action,
    required this.cue,
    required this.reduceMotion,
  });

  final Animation<double> action;
  final ExpeditionActionCue cue;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: action,
          builder: (context, _) {
            final progress = action.value;
            final children = <Widget>[];
            if (cue.playsPartyAttack) {
              children.add(
                _EffectSequence(
                  key: const ValueKey('combat-party-effect-sequence'),
                  effectKey: cue.effectKey,
                  progress: progress,
                  start: .03,
                  end: .58,
                  reduceMotion: reduceMotion,
                ),
              );
            }
            if (cue.playsEnemyAttack) {
              children.add(
                _EffectSequence(
                  key: const ValueKey('combat-enemy-effect-sequence'),
                  effectKey: 'enemy_wave',
                  progress: progress,
                  start: cue.playsPartyAttack ? .52 : .12,
                  end: cue.playsPartyAttack ? .91 : .84,
                  reduceMotion: reduceMotion,
                ),
              );
            }
            return Stack(fit: StackFit.expand, children: children);
          },
        ),
      );
}

class _EffectSequence extends StatelessWidget {
  const _EffectSequence({
    super.key,
    required this.effectKey,
    required this.progress,
    required this.start,
    required this.end,
    required this.reduceMotion,
  });

  final String effectKey;
  final double progress;
  final double start;
  final double end;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (!reduceMotion && (progress < start || progress > end + .08)) {
      return const SizedBox.shrink();
    }
    final normalized = reduceMotion
        ? .82
        : ExpeditionCombatTimeline.segment(progress, start, end);
    final frame = math.min(
      expeditionCombatEffectFrameCount - 1,
      (normalized * expeditionCombatEffectFrameCount).floor(),
    );
    final edgeOpacity = reduceMotion
        ? 1.0
        : math.min(
            ExpeditionCombatTimeline.segment(
                progress, start - .02, start + .03),
            1 - ExpeditionCombatTimeline.segment(progress, end, end + .08),
          );
    return Opacity(
      opacity: edgeOpacity.clamp(0.0, 1.0),
      child: Image.asset(
        expeditionCombatEffectAsset(effectKey, frame),
        key: ValueKey('combat-effect-$effectKey-frame-$frame'),
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
    );
  }
}
