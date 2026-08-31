part of 'expedition_screen.dart';

// 지역 선택, 파티 편성, 출발 조건을 담당하는 탐험 준비 화면.
class _ExpeditionPreparation extends ConsumerWidget {
  const _ExpeditionPreparation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expeditionControllerProvider);
    final catalog = state.catalog;
    if (catalog == null) {
      return _CenteredMessage(
        icon: Icons.cloud_off_outlined,
        title: '탐험 준비를 불러오지 못했어요',
        description: state.error ?? '연결을 확인하고 다시 시도해 주세요.',
        actionLabel: '다시 불러오기',
        onAction: ref.read(expeditionControllerProvider.notifier).load,
      );
    }
    if (catalog.suspended) {
      return const _CenteredMessage(
        icon: Icons.health_and_safety_outlined,
        title: '오늘은 안전 지원을 먼저 살펴봐요',
        description: '마음이 급한 날에는 탐험을 쉬어도 성장 기록은 사라지지 않아요.',
      );
    }
    // 출발은 `지도에서 보고 있는 지역`으로 간다(`start`가 그렇게 보낸다).
    // 여기서 목록의 첫 칸을 집으면 네 지역이 이름·설명·권장 단계·보상이 다
    // 다른데도 늘 이끼 기억서고를 안내하게 된다.
    final region = expeditionDestinationRegion(
      catalog.regions,
      state.stageMap?.region.code,
    );
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: ref.read(expeditionControllerProvider.notifier).load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth >= 720 ? 32 : 16,
            16,
            constraints.maxWidth >= 720 ? 32 : 16,
            40,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.selectedStage case final stage?) ...[
                      _StagePreparationHeader(stage: stage),
                      const SizedBox(height: 14),
                    ] else ...[
                      _PreparationHero(catalog: catalog),
                      const SizedBox(height: 24),
                      Text('1. 목적지',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      if (region != null) _RegionCard(region: region),
                      const SizedBox(height: 24),
                    ],
                    Text('탐험대 편성',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      '최대 3명. 이번 길에서 활약시키고 싶은 캐릭터를 직접 골라요.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 10),
                    if (state.roster.isEmpty)
                      const MongrooPanel(
                        child: Text('새싹 단계 이상의 캐릭터가 생기면 함께 탐험할 수 있어요.'),
                      )
                    else
                      ...state.roster.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RosterTile(
                            item: item,
                            selected:
                                state.selectedPlantIds.contains(item.plantId),
                            enabled: state.busyAction == null,
                            onChanged: item.eligible
                                ? () => ref
                                    .read(expeditionControllerProvider.notifier)
                                    .togglePlant(item.plantId)
                                : null,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text('출발 방식',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    if (!catalog.tutorialCompleted) ...[
                      _TutorialCoachCard(
                        step: 1,
                        onDismiss: null,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _StartActions(state: state),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 스테이지 지도에서 넘어왔을 때의 편성 화면 머리말.
/// 어느 스테이지로 떠나는지와 돌아가는 길을 함께 보여 준다.
class _StagePreparationHeader extends ConsumerWidget {
  const _StagePreparationHeader({required this.stage});

  final ExpeditionStage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return MongrooPanel(
      key: const ValueKey('stage-preparation-header'),
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 12),
      borderColor: scheme.primary.withAlpha(85),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            key: const ValueKey('stage-preparation-back'),
            onPressed:
                ref.read(expeditionControllerProvider.notifier).goBackInShell,
            tooltip: '스테이지 지도로',
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stage.label} · ${stage.kindLabel}',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stage.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stage.summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparationHero extends StatelessWidget {
  const _PreparationHero({required this.catalog});

  final ExpeditionCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MongrooPanel(
      borderColor: scheme.primary.withAlpha(80),
      radius: 18,
      padding: EdgeInsets.zero,
      child: ExpeditionSceneBackdrop(
        scene: expeditionSceneTheme('dungeon_gate'),
        borderRadius: BorderRadius.circular(18),
        semanticLabel: '온실 아래 석문과 계단이 이어지는 이끼 기억서고 던전 입구',
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                MongrooPalette.of(context).night.withAlpha(205),
                MongrooPalette.of(context).night.withAlpha(84),
                Colors.transparent,
              ],
              stops: const [0, .62, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MongrooTag(
                  label: '첫 지역 · 이끼 기억서고',
                  icon: Icons.map_outlined,
                  backgroundColor: scheme.surface.withAlpha(232),
                ),
                const SizedBox(height: 72),
                Text(
                  '내가 키운 캐릭터와\n직접 길을 골라요',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.onNight,
                      ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Text(
                    catalog.diaryReady
                        ? '오늘 마음 일기가 탐험의 공명을 열었어요. 이동과 선택, 스킬 판정을 직접 진행해요.'
                        : '자유 탐험은 언제든 가능해요. 오늘 마음 일기를 쓰면 성장과 씨앗이 있는 공명 탐험이 열려요.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onNightMuted,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RegionCard extends StatelessWidget {
  const _RegionCard({required this.region});

  final ExpeditionRegion region;

  static const _zones = <({String key, String label})>[
    (key: 'dungeon_gate', label: '폐허 던전'),
    (key: 'flooded_cave', label: '침수 동굴'),
    (key: 'root_tunnel', label: '뿌리 땅굴'),
    (key: 'monster_den', label: '몬스터 소굴'),
    (key: 'treasure_vault', label: '압화 보물고'),
    (key: 'moon_tower', label: '기억탑'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, color: palette.leaf),
              const SizedBox(width: 10),
              Expanded(
                child: Text(region.name,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              MongrooTag(
                label: '권장 ${region.recommendedStage}단계',
                icon: Icons.spa_outlined,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(region.description),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MongrooTag(
                  label: '성장 +${region.rewardExp}', icon: Icons.trending_up),
              MongrooTag(
                  label: '씨앗 +${region.rewardSeeds}',
                  icon: Icons.grass_outlined),
              const MongrooTag(label: '8개 노드', icon: Icons.route_outlined),
            ],
          ),
          const SizedBox(height: 16),
          Text('이번 탐험의 구역', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _zones.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final zone = _zones[index];
                final scene = expeditionSceneTheme(zone.key);
                return Semantics(
                  image: true,
                  label: zone.label,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 132,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            scene.assetPath,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            excludeFromSemantics: true,
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  palette.night.withAlpha(220),
                                ],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Icon(scene.icon,
                                      size: 17, color: scene.accent),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      zone.label,
                                      textScaler: TextScaler.noScaling,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: AppTheme.onNight,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final ExpeditionRosterItem item;
  final bool selected;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MongrooPressable(
      onTap: enabled ? onChanged : null,
      semanticLabel: '${item.name}, ${selected ? '탐험대에서 제외' : '탐험대에 추가'}',
      borderRadius: BorderRadius.circular(16),
      child: MongrooPanel(
        shadowOffset: Offset.zero,
        borderColor: selected ? scheme.primary : scheme.outlineVariant,
        color: selected ? scheme.primaryContainer.withAlpha(125) : null,
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    '${item.speciesName} · ${item.stage}단계 · ${_formLabel(item.form)}'
                    '${item.isActive ? ' · 성장 중' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  if (!item.eligible) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.ineligibleReason ?? '아직 탐험할 수 없어요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            MongrooTag(
              label:
                  '최고 ${item.stats.values.fold<int>(0, (a, b) => a > b ? a : b)}',
              icon: Icons.auto_graph_outlined,
            ),
            // 출발 전에만 장착을 바꾼다. 전투 중에는 이 입구가 없다.
            IconButton(
              key: ValueKey('prep-skill-books-${item.plantId}'),
              tooltip: '${item.name}의 마음결 기록서',
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () => context.push(
                '/skill-books/${item.plantId}?name=${Uri.encodeComponent(item.name)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartActions extends ConsumerWidget {
  const _StartActions({required this.state});

  final ExpeditionUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(expeditionControllerProvider.notifier);
    final busy = state.busyAction != null;
    final hasParty = state.selectedPlantIds.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: !busy && hasParty && state.catalog!.heartResonanceAvailable
              ? () => controller.start('heart_resonance')
              : null,
          icon: busy && state.busyAction?.startsWith('start:heart') == true
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.favorite_outline),
          label: const Text('마음 공명 탐험 시작'),
        ),
        const SizedBox(height: 8),
        Text(
          state.catalog!.heartResonanceAvailable
              ? '오늘 1회, 목표를 확보하고 귀환하면 성장과 씨앗을 받아요.'
              : '마음 공명 보상은 오늘 50자 이상의 마음 일기를 쓴 뒤 열려요.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: !busy && hasParty && state.catalog!.freeExploreAvailable
              ? () => controller.start('free_explore')
              : null,
          icon: const Icon(Icons.route_outlined),
          label: const Text('보상 없이 자유 탐험'),
        ),
        // 깊은 조사는 지역 자유 지도를 쓰므로 스테이지를 고르고 들어온 편성에는
        // 내놓지 않는다. 고른 스테이지를 조용히 무시하는 버튼이 되기 때문이다.
        // 허브의 `깊은 조사`로 들어오면 스테이지가 비어 있어 여기가 켜진다.
        // 잠겼을 때도 버튼을 남기고 서버가 준 사유를 그대로 말한다 — 빼 버리면
        // 있는 줄도 모른다.
        if (state.selectedStageNo == null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('prep-start-deep'),
            onPressed: !busy && hasParty && state.catalog!.deepAvailable
                ? () => controller.start('deep')
                : null,
            icon: busy && state.busyAction?.startsWith('start:deep') == true
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_outlined),
            label: const Text('깊은 조사 떠나기'),
          ),
          const SizedBox(height: 8),
          Text(
            state.catalog!.deepAvailable
                ? '엉킴이 더 단단해지는 대신, 처음 여는 기록서와 이야기를 만나요. 씨앗은 늘지 않아요.'
                : state.catalog!.deepLockedReason ??
                    '지역의 8스테이지를 모두 마치면 열려요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed:
              !busy && hasParty ? () => controller.start('tutorial') : null,
          icon: const Icon(Icons.school_outlined),
          label: const Text('안내자와 조작 연습'),
        ),
      ],
    );
  }
}
