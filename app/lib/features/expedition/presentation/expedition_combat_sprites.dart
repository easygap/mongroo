import 'dart:math' as math;
import 'dart:ui' show BlendMode, ImageFilter;

import 'package:flutter/material.dart';

import 'expedition_action_cue.dart';
import 'expedition_combat_effect_catalog.dart';
import 'expedition_combat_timeline.dart';

int expeditionCombatEffectFrameCountFor(String effectKey) =>
    expeditionCombatEffectForKey(effectKey).frameCount;

int expeditionCombatEffectFrameForProgress(
  String effectKey,
  double progress,
) {
  return expeditionCombatEffectForKey(effectKey).frameForProgress(progress);
}

String expeditionCombatEffectAsset(String effectKey, int frame) {
  return expeditionCombatEffectForKey(effectKey).asset(frame);
}

List<String> expeditionCombatEffectAssets(String effectKey) => List.generate(
      expeditionCombatEffectFrameCountFor(effectKey),
      (frame) => expeditionCombatEffectAsset(effectKey, frame),
      growable: false,
    );

List<String> expeditionCombatEffectAssetsFor(
  ExpeditionCombatEffectSpec effect,
) =>
    List.generate(effect.frameCount, effect.asset, growable: false);

List<String> get expeditionCombatEffectFirstFrames =>
    expeditionCombatEffectsByFamily.values
        .map((effect) => effect.asset(0))
        .toSet()
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
                  effect: cue.partyEffect,
                  progress: progress,
                  start: ExpeditionCombatTimeline.partyEffectStart,
                  end: ExpeditionCombatTimeline.partyEffectEnd,
                  reduceMotion: reduceMotion,
                ),
              );
            }
            if (cue.playsEnemyAttack) {
              children.add(
                _EffectSequence(
                  key: const ValueKey('combat-enemy-effect-sequence'),
                  effect: cue.enemyEffect,
                  progress: progress,
                  start: ExpeditionCombatTimeline.enemyEffectStart(cue),
                  end: ExpeditionCombatTimeline.enemyEffectEnd(cue),
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
    required this.effect,
    required this.progress,
    required this.start,
    required this.end,
    required this.reduceMotion,
  });

  final ExpeditionCombatEffectSpec effect;
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
    final frame = effect.frameForProgress(normalized);
    final edgeOpacity = reduceMotion
        ? 1.0
        : math.min(
            ExpeditionCombatTimeline.segment(
                progress, start - .02, start + .03),
            1 - ExpeditionCombatTimeline.segment(progress, end, end + .08),
          );
    final asset = effect.asset(frame);
    final image = Image.asset(
      asset,
      key: ValueKey('combat-effect-${effect.family}-frame-$frame'),
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
    return Opacity(
      opacity: edgeOpacity.clamp(0.0, 1.0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!reduceMotion)
            Opacity(
              opacity: .16,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  color: _effectBlendColor(effect),
                  colorBlendMode: BlendMode.srcIn,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          image,
        ],
      ),
    );
  }
}

Color _effectBlendColor(ExpeditionCombatEffectSpec effect) =>
    switch (effect.kel) {
      'sunny' => const Color(0xFFFFD99B),
      'rainy' => const Color(0xFF91DFF2),
      'ember' => const Color(0xFFFF9A6E),
      'moonlit' => const Color(0xFF9EDFE8),
      'sparkling' => const Color(0xFFCAB5FF),
      'mosaic' => const Color(0xFFB7D4CB),
      _ => const Color(0xFFC8EFE5),
    };
