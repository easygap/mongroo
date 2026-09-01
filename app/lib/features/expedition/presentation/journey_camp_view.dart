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
class _JourneyCampView extends ConsumerStatefulWidget {
  const _JourneyCampView({required this.journey});

  final Journey journey;

  @override
  ConsumerState<_JourneyCampView> createState() => _JourneyCampViewState();
}

class _JourneyCampViewState extends ConsumerState<_JourneyCampView> {
  /// 담아 갈 후보. **비어 있으면 서버가 예산을 채운다.**
  ///
  /// 앱이 자동 채우기를 흉내 내지 않는다. 같은 규칙을 두 곳에 두면 언젠가
  /// 갈라지고, 그때 화면이 약속한 것과 실제로 담아 온 것이 달라진다.
  final Set<int> _picked = {};

  int get _spent => widget.journey.returnCandidates
      .where((loot) => _picked.contains(loot.id))
      .fold(0, (sum, loot) => sum + loot.valueUnits);

  bool _canAdd(JourneyLoot loot) {
    final budget = widget.journey.returnBudget;
    return _picked.length < budget.slots &&
        _spent + loot.valueUnits <= budget.valueUnits;
  }

  void _toggle(JourneyLoot loot) {
    setState(() {
      if (_picked.remove(loot.id)) return;
      if (_canAdd(loot)) _picked.add(loot.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journey = widget.journey;
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
              if (journey.returnCandidates.isNotEmpty) ...[
                const SizedBox(height: 18),
                _ReturnBudgetPicker(
                  candidates: journey.returnCandidates,
                  budget: journey.returnBudget,
                  picked: _picked,
                  spent: _spent,
                  canAdd: _canAdd,
                  onToggle: busy ? null : _toggle,
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('journey-return'),
                onPressed: busy
                    ? null
                    : () => ref
                        .read(journeyControllerProvider.notifier)
                        .returnHome(selectedLootIds: _picked.toList()),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.home_outlined),
                label: Text(
                  _picked.isEmpty
                      ? '예산만큼 담아 돌아가기'
                      : '고른 ${_picked.length}개만 담아 돌아가기',
                ),
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

/// 담아 올 재료를 고르는 자리.
///
/// 설계서 10.3의 `귀환 sheet`다. 예산은 사용자에게 화폐처럼 보여 주지 않으므로
/// 숫자 대신 **몇 칸 중 몇 칸**과 남은 여유로 읽어 준다.
class _ReturnBudgetPicker extends StatelessWidget {
  const _ReturnBudgetPicker({
    required this.candidates,
    required this.budget,
    required this.picked,
    required this.spent,
    required this.canAdd,
    required this.onToggle,
  });

  final List<JourneyLoot> candidates;
  final JourneyBudget budget;
  final Set<int> picked;
  final int spent;
  final bool Function(JourneyLoot loot) canAdd;
  final void Function(JourneyLoot loot)? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.backpack_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text('담아 올 재료', style: theme.textTheme.titleSmall),
              ),
              MongrooTag(label: '${picked.length}/${budget.slots}칸'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            picked.isEmpty
                ? '고르지 않으면 목표 재료부터 예산만큼 담아 와요.'
                : '남은 여유 ${budget.valueUnits - spent}. 나머지는 기록으로만 남아요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          // 판 위에 얹은 타일이라 잉크 물결이 판 배경에 가려진다. 투명한
          // `Material`을 한 겹 두면 누른 자리가 실제로 보인다.
          for (final loot in candidates)
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: ValueKey('journey-loot-${loot.id}'),
                value: picked.contains(loot.id),
                onChanged: onToggle == null ||
                        (!picked.contains(loot.id) && !canAdd(loot))
                    ? null
                    : (_) => onToggle!(loot),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(loot.name),
                subtitle: Text(
                  loot.isObjective ? '목표 재료' : '현장 재료',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                secondary: loot.valueUnits > 1
                    ? MongrooTag(label: '두 칸 값')
                    : null,
              ),
            ),
        ],
      ),
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
              if (summary != null && summary.granted.isNotEmpty) ...[
                const SizedBox(height: 16),
                MongrooPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('담아 온 재료', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(
                        summary.granted
                            .map((loot) => loot.name)
                            .join(', '),
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (summary.recorded.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          // 마지막 이름에 맞춰 조사를 고른다. 자리표시자를
                          // 그대로 두면 저장소 검사가 잡는다.
                          '${koreanTopic(summary.recorded.map((loot) => loot.name).join(', '))} '
                          '기록으로만 남았어요.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
