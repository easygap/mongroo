import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../domain/daily_quest.dart';
import 'quest_controller.dart';

class DailyQuestSummaryCard extends ConsumerWidget {
  const DailyQuestSummaryCard({
    super.key,
    required this.onOpen,
  });

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(questControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final feed = state.feed.valueOrNull;
    final next = feed?.nextAssigned;

    return MongrooPressable(
      onTap: onOpen,
      semanticLabel: '오늘의 작은 행동 열기',
      child: MongrooPanel(
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: scheme.secondary),
                  ),
                  child: Icon(
                    feed?.suspended == true
                        ? Icons.health_and_safety_outlined
                        : next == null
                            ? Icons.task_alt
                            : Icons.auto_awesome_outlined,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: state.feed.when(
                    loading: () => const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('오늘의 작은 행동',
                            style: TextStyle(
                              fontFamily: AppTheme.pixelFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            )),
                        SizedBox(height: 6),
                        LinearProgressIndicator(),
                      ],
                    ),
                    error: (_, __) => const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('오늘의 작은 행동',
                            style: TextStyle(
                              fontFamily: AppTheme.pixelFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            )),
                        SizedBox(height: 2),
                        Text('내용을 불러오려면 눌러 주세요.'),
                      ],
                    ),
                    data: (data) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          data.contextTitle,
                          style: const TextStyle(
                              fontFamily: AppTheme.pixelFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          data.suspended
                              ? '오늘은 작은 행동을 쉬어 가요.'
                              : next?.quest.title ??
                                  (data.items.isEmpty
                                      ? '오늘 준비된 작은 행동이 없어요.'
                                      : '오늘 할 일을 모두 마쳤어요.'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuestCard extends StatelessWidget {
  const QuestCard({
    super.key,
    required this.userQuest,
    required this.busy,
    required this.onComplete,
    required this.onSkip,
  });

  final DailyQuest userQuest;
  final bool busy;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final quest = userQuest.quest;
    final completed = userQuest.status == DailyQuestStatus.completed;
    final skipped = userQuest.status == DailyQuestStatus.skipped;

    return MongrooPanel(
      padding: EdgeInsets.zero,
      color: completed ? scheme.primaryContainer.withAlpha(96) : null,
      borderColor: completed ? palette.leaf : palette.night.withAlpha(90),
      shadowOffset: const Offset(4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: completed ? palette.leaf : palette.night,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MongrooTag(
                    icon: Icons.spa_outlined,
                    label: quest.categoryLabel,
                  ),
                  _QuestFact(
                    icon: Icons.schedule,
                    label: '${quest.estimatedMinutes}분',
                    color: AppTheme.onNightMuted,
                  ),
                  _QuestFact(
                    icon: Icons.air_rounded,
                    label: quest.burdenLabel,
                    color: AppTheme.onNightMuted,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quest.title,
                  style: const TextStyle(
                    fontFamily: AppTheme.pixelFont,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (quest.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    quest.description,
                    style: const TextStyle(height: 1.5),
                  ),
                ],
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.butter.withAlpha(92),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: palette.wood.withAlpha(100)),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        _RewardFact(
                          icon: Icons.local_florist_outlined,
                          label: '최대 +${quest.rewardExp} XP',
                          color: palette.coral,
                        ),
                        _RewardFact(
                          icon: Icons.eco_rounded,
                          label: '+${quest.rewardSeeds} 씨앗',
                          color: palette.leaf,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (completed)
                  _StatusPanel(
                    icon: Icons.check_circle,
                    message: '완료 · 보상을 받았어요.',
                    color: scheme.primary,
                  )
                else if (skipped)
                  _StatusPanel(
                    icon: Icons.fast_forward_outlined,
                    message: '건너뜀 · 연속 기록은 그대로예요.',
                    color: scheme.onSurfaceVariant,
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack = constraints.maxWidth < 360;
                      final complete = FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(144, 48),
                          backgroundColor: palette.coral,
                          foregroundColor: scheme.onTertiary,
                        ),
                        onPressed: busy ? null : onComplete,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: const Text('완료했어요'),
                      );
                      final skip = TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(112, 48),
                        ),
                        onPressed: busy ? null : onSkip,
                        child: const Text('오늘은 건너뛰기'),
                      );
                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [complete, const SizedBox(height: 8), skip],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: complete),
                          const SizedBox(width: 8),
                          skip,
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestFact extends StatelessWidget {
  const _QuestFact({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: resolvedColor),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: resolvedColor)),
      ],
    );
  }
}

class _RewardFact extends StatelessWidget {
  const _RewardFact({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 5),
          // 보상 숫자는 줄이면 안 되는 값이라 말줄임 대신 줄바꿈으로 접는다.
          // 320px에 글자 200%면 `최대 +20 XP` 한 줄이 이 칸을 49px 넘겼다.
          Flexible(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(height: 1.4))),
          ],
        ),
      );
}
