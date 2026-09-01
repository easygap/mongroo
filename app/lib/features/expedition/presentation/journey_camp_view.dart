part of 'journey_screen.dart';

/// 구간을 걷는 중 — 개척 화면으로 들어왔지만 진행 중인 구간이 있다.
///
/// 앱을 껐다 켜거나 탐험 화면에서 뒤로 나온 사람이 여기로 온다. 개척이
/// 어디까지 왔는지 먼저 보여 주고, 걷던 자리로 돌려보낸다.
class _JourneyWalkingView extends ConsumerWidget {
  const _JourneyWalkingView({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      children: [
        _JourneyRibbon(journey: journey),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('걷던 구간이 있어요', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                '${journey.currentLegIndex + 1}구간을 아직 걷고 있어요. '
                '이어서 걸으면 야영지에서 다음 길을 고를 수 있어요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('journey-resume'),
                onPressed: () async {
                  // 걷던 자리로 돌려보내기 전에 탐험 상태를 다시 받는다.
                  await ref.read(expeditionControllerProvider.notifier).load();
                  if (!context.mounted) return;
                  await context.push('/expedition');
                  if (!context.mounted) return;
                  await ref.read(journeyControllerProvider.notifier).load();
                },
                icon: const Icon(Icons.directions_walk_rounded),
                label: const Text('이어서 걷기'),
              ),
              const SizedBox(height: 20),
              _JourneyLegList(legs: journey.legs),
            ],
          ),
        ),
      ],
    );
  }
}

/// 야영지 — 더 갈 구간이 없을 때.
///
/// 갈 곳이 남아 있으면 편성 화면이 곧 야영지라 여기로 오지 않는다. 이 화면은
/// 마지막 구간까지 걸은 사람만 본다.
class _JourneyCampView extends ConsumerWidget {
  const _JourneyCampView({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final busy = ref.watch(
      journeyControllerProvider.select((value) => value.busy != null),
    );
    final secured = journey.legs.where((leg) => leg.objectiveSecured).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      children: [
        _JourneyRibbon(journey: journey),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('마지막 야영지예요', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                '$secured개 구간의 기록을 안고 있어요. 돌아가면 가장 멀리 간 곳을 '
                '기준으로 오늘의 보상을 한 번 받아요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (journey.deepestRegionName != null) ...[
                const SizedBox(height: 12),
                MongrooPanel(
                  child: Row(
                    children: [
                      const Icon(Icons.flag_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '가장 먼 곳 · ${journey.deepestRegionName}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (journey.rewardExp != null)
                        MongrooTag(
                          label: '${journey.rewardExp} XP · '
                              '씨앗 ${journey.rewardSeeds ?? 0}',
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('journey-return'),
                onPressed: busy
                    ? null
                    : () =>
                        ref.read(journeyControllerProvider.notifier).returnHome(),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.home_outlined),
                label: const Text('원정 기록을 안고 돌아가기'),
              ),
              const SizedBox(height: 6),
              Text(
                '여기서 쉬고 나중에 이어할 수도 있어요. 앱을 닫아도 개척은 그대로 남아요.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _JourneyLegList(legs: journey.legs),
            ],
          ),
        ),
      ],
    );
  }
}

/// 원정 기록 — 구간별 조와 해결을 이어 붙이고 마지막에 귀환을 보여 준다.
class _JourneySummaryView extends ConsumerWidget {
  const _JourneySummaryView({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = journey.summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      children: [
        _JourneyRibbon(journey: journey),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary?.title ?? '오늘은 여기까지 기록했어요',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                summary == null
                    ? '기록을 남겼어요.'
                    : '${summary.legCount}개 구간을 걸었고 '
                        '${summary.securedCount}개에서 목표를 안고 왔어요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (summary != null && summary.rewarded) ...[
                const SizedBox(height: 12),
                MongrooPanel(
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${summary.deepestRegionName ?? '가장 먼 곳'} 기준 보상',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      MongrooTag(
                        label: '${summary.rewardExp ?? 0} XP · '
                            '씨앗 ${summary.rewardSeeds ?? 0}',
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _JourneyLegList(legs: summary?.legs ?? journey.legs),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('journey-close-summary'),
                onPressed: () =>
                    ref.read(journeyControllerProvider.notifier).closeSummary(),
                child: const Text('다음 개척 준비하기'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
