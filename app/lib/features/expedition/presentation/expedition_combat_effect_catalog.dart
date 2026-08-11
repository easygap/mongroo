import 'dart:math' as math;

part 'expedition_combat_effect_catalog.g.dart';

/// `assets/adventure/effects/manifest.json`에서 생성되는 런타임 VFX 계약.
class ExpeditionCombatEffectSpec {
  const ExpeditionCombatEffectSpec({
    required this.family,
    required this.effectKeys,
    required this.kel,
    required this.directory,
    required this.frameCount,
    required this.frameWidth,
    required this.frameHeight,
    required this.frameDurationsMs,
    required this.contactFrame,
    required this.pivotX,
    required this.pivotY,
    required this.anchor,
    required this.productionReady,
    required this.sourceHash,
    required this.runtimeHash,
  });

  final String family;
  final List<String> effectKeys;
  final String? kel;
  final String directory;
  final int frameCount;
  final int frameWidth;
  final int frameHeight;
  final List<int> frameDurationsMs;
  final int contactFrame;
  final double pivotX;
  final double pivotY;
  final String anchor;
  final bool productionReady;
  final String sourceHash;
  final String runtimeHash;

  int get totalDurationMs =>
      frameDurationsMs.fold<int>(0, (total, duration) => total + duration);

  double get contactProgress {
    if (frameDurationsMs.isEmpty || totalDurationMs <= 0) return .5;
    final safeContact = contactFrame.clamp(0, frameDurationsMs.length - 1);
    final before = frameDurationsMs
        .take(safeContact)
        .fold<int>(0, (total, duration) => total + duration);
    return (before + frameDurationsMs[safeContact] * .5) / totalDurationMs;
  }

  int frameForProgress(double progress) {
    final safeProgress = progress.clamp(0.0, 1.0);
    if (frameDurationsMs.isEmpty) {
      return math.min(frameCount - 1, (safeProgress * frameCount).floor());
    }
    if (safeProgress >= 1) return frameDurationsMs.length - 1;
    final elapsedMs = safeProgress * totalDurationMs;
    var frameEndMs = 0;
    for (var frame = 0; frame < frameDurationsMs.length; frame++) {
      frameEndMs += frameDurationsMs[frame];
      if (elapsedMs < frameEndMs) return frame;
    }
    return frameDurationsMs.length - 1;
  }

  String asset(int frame) {
    final safeFrame = frame.clamp(0, frameCount - 1);
    return 'assets/adventure/effects/$directory/'
        'frame-${safeFrame.toString().padLeft(2, '0')}.webp';
  }
}

ExpeditionCombatEffectSpec resolveExpeditionCombatEffect({
  String? vfxFamily,
  String? kelFallbackFamily,
  String? legacyEffectKey,
}) {
  final exact = expeditionCombatEffectsByFamily[vfxFamily];
  if (exact != null) return exact;
  final kelFallback = expeditionCombatEffectsByFamily[kelFallbackFamily];
  if (kelFallback != null) return kelFallback;
  final legacyFamily = expeditionCombatFamilyByEffectKey[legacyEffectKey];
  final legacy = expeditionCombatEffectsByFamily[legacyFamily];
  if (legacy != null) return legacy;
  return expeditionCombatEffectsByFamily[expeditionCombatEffectFallbackFamily]!;
}

ExpeditionCombatEffectSpec expeditionCombatEffectForKey(String effectKey) =>
    resolveExpeditionCombatEffect(legacyEffectKey: effectKey);

List<String> get expeditionCombatEffectKeys =>
    expeditionCombatFamilyByEffectKey.keys.toList(growable: false);
