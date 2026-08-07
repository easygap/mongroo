import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'expedition_combat_effects.dart';
import 'expedition_combat_timeline.dart';

/// 서버가 확정한 수호 장벽 수치를 전투 진행률에 맞춰 표시한다.
class ExpeditionEnemyGuardHud extends StatelessWidget {
  const ExpeditionEnemyGuardHud({
    super.key,
    required this.enemyName,
    required this.maxGuard,
    required this.before,
    required this.after,
    required this.progress,
  });

  final String enemyName;
  final int maxGuard;
  final int before;
  final int after;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final guard = ExpeditionCombatTimeline.guardValue(
      before: before,
      after: after,
      progress: progress,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MongrooPalette.of(context).night.withAlpha(222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD3B36A).withAlpha(120)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 15,
                  color: Color(0xFFDCC77A),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '수호 장벽',
                        textScaler: TextScaler.noScaling,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFFDCC77A),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        enemyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: AppTheme.onNight,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${guard.round()}/$maxGuard',
                  textScaler: TextScaler.noScaling,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.onNightMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: maxGuard <= 0 ? 0 : (guard / maxGuard).clamp(0, 1),
                minHeight: 6,
                color: const Color(0xFFDCC77A),
                backgroundColor: Colors.white.withAlpha(34),
              ),
            ),
          ],
        ),
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
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: MongrooPalette.of(context).night.withAlpha(225),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB68A).withAlpha(105)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Color(0xFFFFB68A),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$attackName 예고 · $text',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.onNight,
                        height: 1.3,
                      ),
                ),
              ),
            ],
          ),
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MongrooPalette.of(context).night.withAlpha(220),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withAlpha(48)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: Color(0xFFFFE4A0),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$actorName · $actionName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.onNight,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF4B1F28).withAlpha(228),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF7968).withAlpha(60),
                blurRadius: 14,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 17,
                  color: Color(0xFFFFB29F),
                ),
                const SizedBox(width: 6),
                Text(
                  attackName,
                  textScaler: TextScaler.noScaling,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFFFFE1D8),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
}

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
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 7),
                  Shadow(color: Colors.black, offset: Offset(0, 2)),
                ],
              ),
            ),
            Text(
              caption,
              textScaler: TextScaler.noScaling,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.onNight,
                fontWeight: FontWeight.w700,
                shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
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
      child: Transform.scale(
        scale: .92 + entry * .08,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MongrooPalette.of(context).night.withAlpha(235),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(80),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: expeditionCombatEffectColor(effectKey).withAlpha(65),
                blurRadius: 16,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
      ),
    );
  }
}
