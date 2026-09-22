import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../quest/domain/daily_quest.dart';
import '../../quest/presentation/quest_controller.dart';

class TodayJourneyBoard extends ConsumerWidget {
  const TodayJourneyBoard({
    super.key,
    required this.onRecord,
    required this.onQuest,
    required this.onChat,
    required this.onSafety,
  });

  final VoidCallback onRecord;
  final VoidCallback onQuest;
  final VoidCallback onChat;
  final VoidCallback onSafety;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(questControllerProvider);
    return state.feed.when(
      loading: () => const _JourneyLoading(),
      error: (_, __) => _JourneyFallback(
        onRecord: onRecord,
        onRetry: () => ref.read(questControllerProvider.notifier).load(),
      ),
      data: (feed) => _JourneyContent(
        feed: feed,
        onRecord: onRecord,
        onQuest: onQuest,
        onChat: onChat,
        onSafety: onSafety,
      ),
    );
  }
}

class NextUnlockCard extends StatelessWidget {
  const NextUnlockCard({
    super.key,
    required this.progress,
    required this.onOpen,
  });

  final JourneyProgress progress;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final unlock = progress.nextUnlock;
    if (unlock == null) return const SizedBox.shrink();
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return MongrooPressable(
      onTap: onOpen,
      semanticLabel: '${unlock.name}, ${unlock.label}, ${unlock.progressLabel}',
      child: MongrooPanel(
        padding: EdgeInsets.zero,
        shadowOffset: const Offset(3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: unlock.eligible
                          ? palette.butter
                          : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      unlock.eligible
                          ? Icons.redeem_rounded
                          : Icons.lock_open_rounded,
                      color: unlock.eligible
                          ? palette.night
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unlock.eligible ? '지금 받을 수 있어요' : '다음에 열리는 것',
                          style: TextStyle(
                            color: palette.inkMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          unlock.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${unlock.typeLabel} · ${unlock.label}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.inkMuted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: palette.inkMuted),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: unlock.progress,
                            minHeight: 7,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        unlock.progressLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '이번 주 · 기록 ${progress.weeklyRecordedDays}일 · 작은 행동 ${progress.weeklyCompletedQuests}회',
                    style: TextStyle(color: palette.inkMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StepState { done, active, waiting, rested, paused }

class _JourneyContent extends StatelessWidget {
  const _JourneyContent({
    required this.feed,
    required this.onRecord,
    required this.onQuest,
    required this.onChat,
    required this.onSafety,
  });

  final DailyQuestFeed feed;
  final VoidCallback onRecord;
  final VoidCallback onQuest;
  final VoidCallback onChat;
  final VoidCallback onSafety;

  @override
  Widget build(BuildContext context) {
    final noRecord = feed.contextStatus == 'record_optional';
    final analyzing = feed.contextStatus == 'analyzing';
    final quest = feed.items.isEmpty ? null : feed.items.first;
    final questStatus = quest?.status;
    final recordStep = _JourneyStepData(
      icon: Icons.edit_note_rounded,
      title: '일기 쓰기',
      caption: noRecord ? '한 줄만 적어도 시작돼요' : '오늘 일기를 저장했어요',
      state: noRecord ? _StepState.active : _StepState.done,
      status: noRecord ? '지금' : '완료',
    );
    final analysisStep = _JourneyStepData(
      icon: Icons.auto_awesome_rounded,
      title: '오늘의 기분',
      caption: noRecord
          ? '일기를 쓰면 자동으로 정리해요'
          : analyzing
              ? '일기를 읽고 있어요'
              : feed.contextEmotionLabel == null
                  ? '오늘 일기를 읽었어요'
                  : '오늘 기록한 기분: ${feed.contextEmotionLabel}',
      state: noRecord
          ? _StepState.waiting
          : analyzing
              ? _StepState.active
              : _StepState.done,
      status: noRecord
          ? '다음'
          : analyzing
              ? '읽는 중'
              : '완료',
    );
    final questStep = _JourneyStepData(
      icon: Icons.flag_outlined,
      title: '작은 행동',
      caption: feed.suspended
          ? '도움을 받을 수 있는 곳을 확인해요'
          : questStatus == DailyQuestStatus.completed
              ? '경험치와 씨앗을 받았어요'
              : questStatus == DailyQuestStatus.skipped
                  ? '오늘은 쉬어 가기로 했어요'
                  : quest == null
                      ? '오늘 준비된 행동이 없어요'
                      : '${quest.quest.title} · ${quest.quest.estimatedMinutes}분',
      state: feed.suspended
          ? _StepState.paused
          : questStatus == DailyQuestStatus.completed
              ? _StepState.done
              : questStatus == DailyQuestStatus.skipped
                  ? _StepState.rested
                  : noRecord || analyzing
                      ? _StepState.waiting
                      : _StepState.active,
      status: feed.suspended
          ? '돌봄'
          : questStatus == DailyQuestStatus.completed
              ? '완료'
              : questStatus == DailyQuestStatus.skipped
                  ? '쉼'
                  : '선택',
    );

    final (title, description, cta, icon, action) = switch ((
      feed.suspended,
      noRecord,
      analyzing,
      questStatus,
    )) {
      (true, _, _, _) => (
          '도움이 필요할 때',
          '상담과 긴급 도움을 받을 수 있는 곳을 안내해요.',
          '지원 안내 보기',
          Icons.health_and_safety_outlined,
          onSafety,
        ),
      (_, true, _, _) => (
          '오늘은 무슨 일이 있었나요?',
          '기억에 남는 일을 적어 보세요. 한 줄도 괜찮아요.',
          '오늘 일기 쓰기',
          Icons.edit_note_rounded,
          onRecord,
        ),
      (_, _, true, _) => (
          '일기를 읽고 있어요',
          '다 읽으면 경험치를 받고 캐릭터가 자라요.',
          '캐릭터와 대화하기',
          Icons.chat_bubble_outline_rounded,
          onChat,
        ),
      (_, _, _, DailyQuestStatus.assigned) => (
          '오늘 해 볼 일',
          '하고 싶은 날만 이어 가세요. 건너뛰어도 기록과 성장은 그대로 남아요.',
          '오늘의 작은 행동 보기',
          Icons.flag_outlined,
          onQuest,
        ),
      (_, _, _, DailyQuestStatus.completed) => (
          '오늘 할 일을 마쳤어요',
          '경험치와 씨앗을 받았어요. 모은 씨앗은 상점에서 쓸 수 있어요.',
          '캐릭터와 대화하기',
          Icons.chat_bubble_outline_rounded,
          onChat,
        ),
      _ => (
          '오늘은 여기까지도 충분해요',
          '언제든 다시 와서 이어 할 수 있어요.',
          '캐릭터와 대화하기',
          Icons.chat_bubble_outline_rounded,
          onChat,
        ),
    };

    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.seed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, size: 20, color: AppTheme.onNight),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오늘 할 일',
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(color: palette.inkMuted, height: 1.45),
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.paperDeep.withAlpha(120),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.ink.withAlpha(18)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(child: _JourneyStamp(data: recordStep)),
                  VerticalDivider(
                    width: 1,
                    color: palette.ink.withAlpha(22),
                  ),
                  Expanded(child: _JourneyStamp(data: analysisStep)),
                  VerticalDivider(
                    width: 1,
                    color: palette.ink.withAlpha(22),
                  ),
                  Expanded(child: _JourneyStamp(data: questStep)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppTheme.seed,
              foregroundColor: AppTheme.onNight,
            ),
            onPressed: action,
            icon: Icon(icon),
            label: Text(cta),
          ),
        ],
      ),
    );
  }
}

class _JourneyStepData {
  const _JourneyStepData({
    required this.icon,
    required this.title,
    required this.caption,
    required this.state,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String caption;
  final _StepState state;
  final String status;
}

class _JourneyStamp extends StatelessWidget {
  const _JourneyStamp({required this.data});

  final _JourneyStepData data;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final active = data.state == _StepState.active;
    final done = data.state == _StepState.done;
    final foreground = active || done ? palette.ink : palette.inkMuted;
    final background = active
        ? palette.sky
        : done
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent;
    return Semantics(
      label: '${data.title}, ${data.status}, ${data.caption}',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 24,
                child: Icon(
                  done ? Icons.check_circle_rounded : data.icon,
                  size: 20,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                data.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyLoading extends StatelessWidget {
  const _JourneyLoading();

  @override
  Widget build(BuildContext context) {
    return MongrooPanel(
      child: const SizedBox(
        height: 176,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('오늘 할 일을 불러오고 있어요.'),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyFallback extends StatelessWidget {
  const _JourneyFallback({required this.onRecord, required this.onRetry});

  final VoidCallback onRecord;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '오늘은 무슨 일이 있었나요?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '진행 상태를 불러오지 못했지만 기록은 안전하게 시작할 수 있어요.',
            style: TextStyle(color: palette.inkMuted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.seed,
              foregroundColor: AppTheme.onNight,
            ),
            onPressed: onRecord,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('오늘 일기 쓰기'),
          ),
          TextButton(onPressed: onRetry, child: const Text('진행 상태 다시 불러오기')),
        ],
      ),
    );
  }
}
