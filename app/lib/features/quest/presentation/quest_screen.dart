import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/presentation/today_journey_board.dart';
import '../domain/daily_quest.dart';
import 'quest_controller.dart';
import 'quest_widgets.dart';

class QuestScreen extends ConsumerWidget {
  const QuestScreen({super.key});

  Future<void> _complete(
    BuildContext context,
    WidgetRef ref,
    DailyQuest userQuest,
  ) async {
    final result =
        await ref.read(questControllerProvider.notifier).complete(userQuest.id);
    if (result == null || !context.mounted) return;

    final reward = result.reward;
    final openPlant = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome,
                  size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              const Text(
                '퀘스트 완료!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.pixelFont,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reward == null
                    ? '오늘의 퀘스트를 완료했어요.'
                    : '경험치 +${reward.totalExp} · 씨앗 +${reward.totalSeeds}\n'
                        '보상이 지금 키우는 식물에 반영됐어요.',
                textAlign: TextAlign.center,
              ),
              if (result.journey.nextUnlock case final unlock?) ...[
                const SizedBox(height: 12),
                Text(
                  '${unlock.name} · ${unlock.progressLabel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('계속 보기'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.spa_outlined),
                      label: const Text('식물 변화 보기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (openPlant == true && context.mounted) {
      context.go('/home');
    }
  }

  Future<void> _skip(
    BuildContext context,
    WidgetRef ref,
    DailyQuest userQuest,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오늘은 쉬어 갈까요?'),
        content: const Text('건너뛰어도 기록, 성장, 연속 일수에는 불이익이 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('조금 더 볼게요'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('오늘은 쉬기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final skipped =
        await ref.read(questControllerProvider.notifier).skip(userQuest.id);
    if (!skipped || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('오늘은 건너뛰었어요. 불이익은 없어요.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(questControllerProvider);
    ref.listen(
      questControllerProvider.select((value) => value.actionError),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next)),
        );
        ref.read(questControllerProvider.notifier).clearActionError();
      },
    );

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('오늘의 퀘스트'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(questControllerProvider.notifier).load(),
        child: state.feed.when(
          loading: () => const _LoadingBody(),
          error: (error, _) => _ErrorBody(
            message: ApiException.from(error).message,
            onRetry: () => ref.read(questControllerProvider.notifier).load(),
          ),
          data: (feed) => _QuestBody(
            feed: feed,
            busyQuestIds: state.busyQuestIds,
            onComplete: (quest) => _complete(context, ref, quest),
            onSkip: (quest) => _skip(context, ref, quest),
            onRecord: () => context.push('/record'),
            onGarden: () => context.go('/garden?tab=1'),
            onHome: () => context.go('/home'),
          ),
        ),
      ),
    );
  }
}

class _QuestBody extends StatelessWidget {
  const _QuestBody({
    required this.feed,
    required this.busyQuestIds,
    required this.onComplete,
    required this.onSkip,
    required this.onRecord,
    required this.onGarden,
    required this.onHome,
  });

  final DailyQuestFeed feed;
  final Set<int> busyQuestIds;
  final ValueChanged<DailyQuest> onComplete;
  final ValueChanged<DailyQuest> onSkip;
  final VoidCallback onRecord;
  final VoidCallback onGarden;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MongrooPanel(
                  color: palette.night,
                  borderColor: palette.night,
                  shadowOffset: const Offset(4, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MongrooTag(
                        label: '오늘 1개',
                        icon: Icons.flag_outlined,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              feed.contextTitle,
                              style: const TextStyle(
                                color: AppTheme.onNight,
                                fontFamily: AppTheme.pixelFont,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              feed.contextDescription,
                              style: const TextStyle(
                                color: AppTheme.onNightMuted,
                                height: 1.45,
                              ),
                            ),
                            if (feed.contextStatus == 'record_optional') ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.onNight,
                                  side: const BorderSide(
                                    color: AppTheme.onNightMuted,
                                  ),
                                ),
                                onPressed: onRecord,
                                icon: const Icon(Icons.edit_note_rounded),
                                label: const Text('오늘 이야기 남기기'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (feed.suspended)
                  const _SuspendedCard()
                else if (feed.items.isEmpty)
                  const _EmptyCard()
                else ...[
                  for (final userQuest in feed.items) ...[
                    QuestCard(
                      userQuest: userQuest,
                      busy: busyQuestIds.contains(userQuest.id),
                      onComplete: () => onComplete(userQuest),
                      onSkip: () => onSkip(userQuest),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (feed.allFinished)
                    _FinishedCard(
                      completed: feed.items.any(
                        (item) => item.status == DailyQuestStatus.completed,
                      ),
                      onHome: onHome,
                      onGarden: onGarden,
                    ),
                  if (feed.journey.nextUnlock != null) ...[
                    const SizedBox(height: 12),
                    NextUnlockCard(
                      progress: feed.journey,
                      onOpen: onGarden,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SuspendedCard extends StatelessWidget {
  const _SuspendedCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MongrooPanel(
      color: scheme.tertiaryContainer.withAlpha(110),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.health_and_safety_outlined,
              size: 42, color: scheme.onTertiaryContainer),
          const SizedBox(height: 12),
          const Text(
            '오늘 퀘스트는 쉬어 갑니다',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '보상과 연속 기록은 그대로예요. 지금 연결할 수 있는 도움부터 확인해 주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(180, 48),
            ),
            onPressed: () => context.push('/safety'),
            icon: const Icon(Icons.support_agent),
            label: const Text('지원 안내 보기'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) => const MongrooPanel(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.nights_stay_outlined, size: 40),
            SizedBox(height: 12),
            Text('오늘 배정된 퀘스트가 없어요.'),
            SizedBox(height: 4),
            Text('감정 기록과 정원 꾸미기는 그대로 이용할 수 있어요.'),
          ],
        ),
      );
}

class _FinishedCard extends StatelessWidget {
  const _FinishedCard({
    required this.completed,
    required this.onHome,
    required this.onGarden,
  });

  final bool completed;
  final VoidCallback onHome;
  final VoidCallback onGarden;

  @override
  Widget build(BuildContext context) => MongrooPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.task_alt, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    completed
                        ? '오늘의 작은 행동을 마쳤어요. 이 변화는 식물과 다음 해금에 남아요.'
                        : '오늘은 쉬어 가기로 했어요. 기록과 식물 성장은 그대로 남아요.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onGarden,
                    child: const Text('다음 해금 보기'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onHome,
                    child: const Text('식물에게 가기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(child: Text('오늘의 마음 퀘스트를 준비하고 있어요.')),
        ],
      );
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(144, 48),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ),
        ],
      );
}
