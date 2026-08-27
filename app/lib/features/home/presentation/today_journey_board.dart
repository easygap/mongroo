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
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          unlock.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.pixelFont,
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
                          fontWeight: FontWeight.w900,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '이번 주 · 기록 ${progress.weeklyRecordedDays}일 · 작은 행동 ${progress.weeklyCompletedQuests}회',
                    style: TextStyle(color: palette.inkMuted, fontSize: 11),
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
      title: '이야기 남기기',
      caption: noRecord ? '한 줄만 적어도 시작돼요' : '오늘 이야기가 화분에 닿았어요',
      state: noRecord ? _StepState.active : _StepState.done,
      status: noRecord ? '지금' : '완료',
    );
    final analysisStep = _JourneyStepData(
      icon: Icons.auto_awesome_rounded,
      title: '마음빛 읽기',
      caption: noRecord
          ? '기록 뒤 식물이 자동으로 읽어요'
          : analyzing
              ? '글에서 마음의 결을 찾고 있어요'
              : feed.contextEmotionLabel == null
                  ? '읽을 수 있는 만큼 천천히 살폈어요'
                  : '${feed.contextEmotionLabel}의 단서를 찾았어요',
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
          ? '오늘은 작은 행동 대신 돌봄을 먼저 봐요'
          : questStatus == DailyQuestStatus.completed
              ? '보상이 식물과 씨앗에 반영됐어요'
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
          '오늘은 돌봄을 먼저 봐요',
          '작은 행동과 보상보다 지금 연결할 수 있는 지원을 앞에 두었어요.',
          '지원 안내 보기',
          Icons.health_and_safety_outlined,
          onSafety,
        ),
      (_, true, _, _) => (
          '오늘 이야기부터 시작해요',
          '감정을 고르지 않아도 돼요. 있었던 일을 적으면 식물이 다음 칸을 열어요.',
          '오늘 이야기 남기기',
          Icons.edit_note_rounded,
          onRecord,
        ),
      (_, _, true, _) => (
          '식물이 마음빛을 읽는 중',
          '분석이 끝나면 외형 단서와 오늘의 작은 행동이 자연스럽게 이어져요.',
          '읽는 동안 식물과 대화하기',
          Icons.chat_bubble_outline_rounded,
          onChat,
        ),
      (_, _, _, DailyQuestStatus.assigned) => (
          '이야기 다음의 작은 행동',
          '하고 싶은 날만 이어 가세요. 건너뛰어도 기록과 성장은 그대로 남아요.',
          '오늘의 작은 행동 보기',
          Icons.flag_outlined,
          onQuest,
        ),
      (_, _, _, DailyQuestStatus.completed) => (
          '오늘의 온실 루트 완료',
          '남긴 이야기와 행동이 식물의 다음 장면, 그리고 다음 해금에 쌓였어요.',
          '식물과 한마디 나누기',
          Icons.chat_bubble_outline_rounded,
          onChat,
        ),
      _ => (
          '오늘은 여기까지도 충분해요',
          '쉬어 가기로 한 선택도 오늘의 기록을 지우지 않아요.',
          '식물과 한마디 나누기',
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
                  child: Icon(icon, size: 20, color: palette.night),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오늘의 다음 한 칸',
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
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
              foregroundColor: palette.night,
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
            ? AppTheme.seed
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
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
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
              Text('오늘의 다음 한 칸을 살펴보고 있어요.'),
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
            '오늘 이야기부터 시작해요',
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
              foregroundColor: palette.night,
            ),
            onPressed: onRecord,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('오늘 이야기 남기기'),
          ),
          TextButton(onPressed: onRetry, child: const Text('진행 상태 다시 불러오기')),
        ],
      ),
    );
  }
}
