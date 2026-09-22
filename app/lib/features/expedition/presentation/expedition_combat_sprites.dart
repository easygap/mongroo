import 'dart:math' as math;

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
    this.actorAnchor,
    this.enemyAnchor,
    this.stageBounds,
  });

  final Animation<double> action;
  final ExpeditionActionCue cue;
  final bool reduceMotion;
  final Offset? actorAnchor;
  final Offset? enemyAnchor;
  final Rect? stageBounds;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: action,
          builder: (context, _) {
            final progress = action.value;
            final children = <Widget>[];
            if (cue.playsPartyEffect) {
              children.add(
                _EffectSequence(
                  key: const ValueKey('combat-party-effect-sequence'),
                  effect: cue.partyEffect,
                  progress: progress,
                  start: ExpeditionCombatTimeline.partyEffectStart,
                  end: ExpeditionCombatTimeline.partyEffectEnd,
                  reduceMotion: reduceMotion,
                  tint: _combatHexColor(cue.emotionVfxPrimary),
                  secondaryTint: _combatHexColor(cue.emotionVfxSecondary),
                  intensity: cue.vfxIntensity,
                  actorAnchor: actorAnchor,
                  enemyAnchor: enemyAnchor,
                  stageBounds: stageBounds,
                ),
              );
              final fusion = cue.fusionEffect;
              if (fusion != null &&
                  cue.presentationTier >= 3 &&
                  !cue.isBossPhase) {
                children.add(
                  _EffectSequence(
                    key: const ValueKey('combat-emotion-fusion-sequence'),
                    effect: fusion,
                    progress: progress,
                    start: ExpeditionCombatTimeline.partyEffectStart + .035,
                    end: ExpeditionCombatTimeline.partyEffectEnd + .025,
                    reduceMotion: reduceMotion,
                    tint: _combatHexColor(cue.emotionVfxSecondary),
                    secondaryTint: _combatHexColor(cue.emotionVfxPrimary),
                    intensity: 1.08,
                    opacityScale: .26,
                    scale: 1.04,
                    actorAnchor: actorAnchor,
                    enemyAnchor: enemyAnchor,
                    stageBounds: stageBounds,
                  ),
                );
              }
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
                  intensity: 1,
                  actorAnchor: actorAnchor,
                  enemyAnchor: enemyAnchor,
                  stageBounds: stageBounds,
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
    required this.intensity,
    this.tint,
    this.secondaryTint,
    this.opacityScale = 1,
    this.scale = 1,
    this.actorAnchor,
    this.enemyAnchor,
    this.stageBounds,
  });

  final ExpeditionCombatEffectSpec effect;
  final double progress;
  final double start;
  final double end;
  final bool reduceMotion;
  final double intensity;
  final Color? tint;
  final Color? secondaryTint;
  final double opacityScale;
  final double scale;
  final Offset? actorAnchor;
  final Offset? enemyAnchor;
  final Rect? stageBounds;

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
    // 도트 무대 위의 이펙트도 도트다. 원화를 1/4로 디코드한 뒤 보간 없이
    // 키우면 붓 그림이던 연출이 무대와 같은 굵기의 도트로 읽힌다. 흐린 광채
    // 겹은 걷어 냈다 — 번짐이 곧 도트를 뭉개는 것이었다.
    final image = Image.asset(
      asset,
      key: ValueKey('combat-effect-${effect.family}-frame-$frame'),
      cacheWidth: math.max(96, effect.frameWidth ~/ 4),
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.none,
      isAntiAlias: false,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
    final safeIntensity = intensity.clamp(.8, 1.2).toDouble();
    final visual = Transform.scale(
      scale: scale * (1 + (safeIntensity - 1) * .08),
      child: Opacity(
        opacity: (edgeOpacity * opacityScale).clamp(0.0, 1.0),
        child: tint == null || reduceMotion
            ? image
            : Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  // 성장 타입 색은 흐림 없이 얇게 한 겹만 얹는다.
                  Opacity(
                    opacity: .12,
                    child: Image.asset(
                      asset,
                      cacheWidth: math.max(96, effect.frameWidth ~/ 4),
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      color: tint,
                      colorBlendMode: BlendMode.srcIn,
                      filterQuality: FilterQuality.none,
                      isAntiAlias: false,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                    ),
                  ),
                ],
              ),
      ),
    );
    final bounds = stageBounds;
    final actor = actorAnchor;
    final enemy = enemyAnchor;
    if (bounds == null || actor == null || enemy == null) return visual;
    final rect = expeditionEffectRect(effect,
        stageBounds: bounds, actor: actor, enemy: enemy);
    return Positioned.fromRect(
      rect: bounds,
      child: ClipRect(
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fromRect(
            rect: rect.shift(-bounds.topLeft),
            child: visual,
          ),
        ]),
      ),
    );
  }
}

/// Place authored pivots in the playable space, independent of HUD height.
Rect expeditionEffectRect(
  ExpeditionCombatEffectSpec effect, {
  required Rect stageBounds,
  required Offset actor,
  required Offset enemy,
}) {
  final center = Offset.lerp(actor, enemy, .5)!;
  final anchor = switch (effect.anchor) {
    'actor_hand_r' || 'actor_center' || 'party_all' => actor,
    'tangle_center' ||
    'beast_center' ||
    'guardian_center' ||
    'guardian_foreleg_r' =>
      enemy,
    _ => center,
  };
  final aspect = effect.frameWidth / effect.frameHeight;
  var width = math.min(stageBounds.width * .94, stageBounds.height * aspect);
  if (effect.anchor == 'actor_hand_r') {
    // The cast sheet travels from its left pivot towards the right contact.
    width = math.min(width, (enemy.dx - actor.dx).abs() / .78);
  } else if (effect.anchor == 'actor_center' || effect.anchor == 'party_all') {
    width *= .72;
  }
  final height = width / aspect;
  return Rect.fromLTWH(anchor.dx - width * effect.pivotX,
      anchor.dy - height * effect.pivotY, width, height);
}

Color? _combatHexColor(String? value) {
  if (value == null) return null;
  final hex = value.replaceFirst('#', '');
  if (hex.length != 6) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(0xFF000000 | parsed);
}
