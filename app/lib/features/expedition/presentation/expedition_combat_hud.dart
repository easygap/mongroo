import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'expedition_combat_effects.dart';
import 'expedition_combat_timeline.dart';
import 'expedition_pixel_art.dart';

/// 전투 HUD의 공통 색. 무대가 도트이므로 HUD도 도트 판이다 — 유리·그림자
/// 번짐·둥근 모서리를 쓰지 않는다.
abstract final class ExpeditionCombatHudColors {
  static const panel = Color(0xF21B1612);
  static const border = Color(0xFF0C0907);
  static const guardBar = Color(0xFFE2C46A);
  static const enemyName = Color(0xFFFFF1D2);
  static const warning = Color(0xFFFFB68A);
  static const heal = Color(0xFF9FE7D2);
  static const hurt = Color(0xFFFF8D78);
}

/// 서버가 확정한 수호 장벽 수치를 전투 진행률에 맞춰 표시한다.
class ExpeditionEnemyGuardHud extends StatelessWidget {
  const ExpeditionEnemyGuardHud({
    super.key,
    required this.enemyName,
    required this.maxGuard,
    required this.before,
    required this.after,
    required this.progress,
    this.elite = false,
  });

  final String enemyName;
  final int maxGuard;
  final int before;
  final int after;
  final double progress;
  final bool elite;

  @override
  Widget build(BuildContext context) {
    final guard = ExpeditionCombatTimeline.guardValue(
      before: before,
      after: after,
      progress: progress,
    );
    return PixelPanel(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  elite ? '$enemyName ★' : enemyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: ExpeditionPixelArt.text(
                    13,
                    color: ExpeditionCombatHudColors.enemyName,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${guard.round()}/$maxGuard',
                textScaler: TextScaler.noScaling,
                style: ExpeditionPixelArt.text(
                  11,
                  color: AppTheme.onNightMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          PixelBar(
            value: maxGuard <= 0 ? 0 : (guard / maxGuard).clamp(0, 1),
            color: ExpeditionCombatHudColors.guardBar,
            lowColor: ExpeditionCombatHudColors.guardBar,
            height: 8,
          ),
        ],
      ),
    );
  }
}

/// 선택 전 수호자의 다음 공격을 미리 알려 주는 고정 안내판이다.
class ExpeditionTelegraphChip extends StatelessWidget {
  const ExpeditionTelegraphChip({
    super.key,
    required this.attackName,
    required this.text,
  });

  final String attackName;
  final String text;

  @override
  Widget build(BuildContext context) => PixelPanel(
        padding: const EdgeInsets.fromLTRB(6, 3, 6, 4),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: ExpeditionCombatHudColors.warning,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '$attackName 예고 · $text',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.onNight,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      );
}

class ExpeditionActorBadge extends StatelessWidget {
  const ExpeditionActorBadge({
    super.key,
    required this.actorName,
    required this.actionName,
  });

  final String actorName;
  final String actionName;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: PixelPanel(
          padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
          child: Text(
            '$actorName · $actionName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: ExpeditionPixelArt.text(12),
          ),
        ),
      );
}

class ExpeditionAttackCallout extends StatelessWidget {
  const ExpeditionAttackCallout({
    super.key,
    required this.attackName,
    required this.progress,
  });

  final String attackName;
  final double progress;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: ExpeditionCombatTimeline.floatingOpacity(progress, .55, .83),
        child: PixelPanel(
          fill: const Color(0xF2431C22),
          padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 15,
                color: ExpeditionCombatHudColors.warning,
              ),
              const SizedBox(width: 5),
              Text(
                attackName,
                textScaler: TextScaler.noScaling,
                style: ExpeditionPixelArt.text(
                  13,
                  color: const Color(0xFFFFE1D8),
                ),
              ),
            ],
          ),
        ),
      );
}

/// 뜨는 피해 숫자. 도트 글꼴에 한 칸 그림자 — 흐린 글로우는 쓰지 않는다.
class ExpeditionDamageNumber extends StatelessWidget {
  const ExpeditionDamageNumber({
    super.key,
    required this.label,
    required this.caption,
    required this.color,
    required this.opacity,
  });

  final String label;
  final String caption;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textScaler: TextScaler.noScaling,
              style: ExpeditionPixelArt.text(
                26,
                color: color,
                shadowOffset: 3,
              ),
            ),
            Text(
              caption,
              textScaler: TextScaler.noScaling,
              style: ExpeditionPixelArt.text(
                11,
                color: AppTheme.onNight,
              ),
            ),
          ],
        ),
      );
}

class ExpeditionOutcomeBadge extends StatelessWidget {
  const ExpeditionOutcomeBadge({
    super.key,
    required this.label,
    required this.effectKey,
    required this.progress,
  });

  final String label;
  final String effectKey;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final entry = Curves.easeOutCubic.transform(
      ExpeditionCombatTimeline.segment(progress, .86, 1),
    );
    return Opacity(
      opacity: entry,
      child: Transform.translate(
        offset: Offset(0, (1 - entry) * 6),
        child: PixelPanel(
          highlight: expeditionCombatEffectColor(effectKey).withAlpha(120),
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppTheme.onNight,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}
