part of 'expedition_screen.dart';

/// 모험 허브 — `지금 누를 것 하나`를 크게, 나머지를 작게.
///
/// 개편 설계서 5.1. 배지·빨간 점·카운트다운으로 재촉하지 않고, 오늘의 보상
/// 상태는 사실만 한 줄로 알린다.
class _ExpeditionHub extends ConsumerWidget {
  const _ExpeditionHub();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expeditionControllerProvider);
    final catalog = state.catalog;
    final stageMap = state.stageMap;
    if (catalog == null || stageMap == null) {
      return _CenteredMessage(
        icon: Icons.cloud_off_outlined,
        title: '모험 준비를 불러오지 못했어요',
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
    final notifier = ref.read(expeditionControllerProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: notifier.load,
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
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ContinueAdventureCard(
                      stageMap: stageMap,
                      roster: state.roster,
                      busy: state.busyAction != null,
                      onTap: notifier.openStageMap,
                    ),
                    const SizedBox(height: 10),
                    _TodayRewardLine(catalog: catalog),
                    const SizedBox(height: 22),
                    Text('다른 길',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    ..._hubEntries(context, ref, stageMap).map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _HubEntryTile(entry: entry),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 허브에서 갈 수 있는 다른 길.
  ///
  /// **누를 수 없는 것을 열린 것처럼 두지 않는다.** 예전에는 네 항목이 모두
  /// 그냥 판이라, 잠기지 않은 `자동 순찰`·`깊은 조사`를 눌러도 아무 일이 없고
  /// 아직 만들지 않은 `합동 수호전`은 지역을 깨면 열린 모습이 되었다.
  /// 지금은 셋으로 갈린다 — 갈 수 있으면 [_HubEntry.onTap]이 있고, 조건이
  /// 모자라면 [_HubEntry.lockReason], 서버에 아직 없는 길은
  /// [_HubEntry.comingSoon]이다.
  List<_HubEntry> _hubEntries(
    BuildContext context,
    WidgetRef ref,
    ExpeditionStageMap stageMap,
  ) {
    final notifier = ref.read(expeditionControllerProvider.notifier);
    final catalog = ref.read(expeditionControllerProvider).catalog;
    final deepAvailable = catalog?.deepAvailable ?? stageMap.regionCleared;
    return [
      _HubEntry(
        icon: Icons.hiking_rounded,
        title: '자동 순찰',
        description: '앱을 닫아 두면 캐릭터가 혼자 다녀와요.',
        lockReason: null,
        // 순찰 보내기는 모험 탭(`오늘의 순찰`)이 들고 있다. 같은 것을 두 곳에
        // 만들지 않고, 여기서는 그 화면으로 돌려보낸다.
        onTap: () => Navigator.of(context).maybePop(),
      ),
      _HubEntry(
        icon: Icons.travel_explore_rounded,
        title: '깊은 조사',
        description: '지도를 직접 읽으며 숨은 길과 원본 서고를 찾아요.',
        // 사유는 지역 이름을 넣어 직접 만든다. 서버도 같은 뜻을 보내지만
        // `지역의 8스테이지`라고만 해서, 지금 보고 있는 곳이 어디인지 모른다.
        lockReason: deepAvailable
            ? null
            : '${stageMap.region.shortName} 8까지 완주하면 열려요.',
        onTap: deepAvailable ? notifier.openDeepPreparation : null,
      ),
      const _HubEntry(
        icon: Icons.groups_2_rounded,
        title: '합동 수호전',
        description: '여섯이서 깊이 잠든 수호짐승을 깨워 줘요.',
        lockReason: '아직 만들고 있어요.',
        comingSoon: true,
      ),
      const _HubEntry(
        icon: Icons.map_outlined,
        title: '장거리 개척',
        description: '여러 구간을 다른 조로 나눠 멀리까지 다녀와요.',
        lockReason: '아직 만들고 있어요.',
        comingSoon: true,
      ),
    ];
  }
}

class _ContinueAdventureCard extends StatelessWidget {
  const _ContinueAdventureCard({
    required this.stageMap,
    required this.roster,
    required this.busy,
    required this.onTap,
  });

  final ExpeditionStageMap stageMap;
  final List<ExpeditionRosterItem> roster;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = stageMap.nextStage;
    final headline = stageMap.regionCleared
        ? '${koreanObject(stageMap.region.shortName)} 모두 걸었어요'
        : '이어서 모험하기';
    final detail = next?.label ?? '${stageMap.region.name} 완주';
    final party = roster.where((item) => item.eligible).take(3).toList();
    return Semantics(
      button: true,
      label: '$headline, $detail. '
          '${stageMap.clearedCount}/${stageMap.total} 스테이지 완주',
      child: MongrooPanel(
        padding: EdgeInsets.zero,
        radius: 20,
        borderColor: scheme.primary.withAlpha(95),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('hub-continue-card'),
            borderRadius: BorderRadius.circular(20),
            onTap: busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              headline,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (next != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                next.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded, color: scheme.primary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _StageProgressBar(
                    cleared: stageMap.clearedCount,
                    total: stageMap.total,
                  ),
                  if (party.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final item in party)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: SizedBox(
                              width: 34,
                              child: PlantView(
                                stage: item.stage,
                                form: PlantGrowthForm.fromCode(item.form),
                                speciesCode: item.speciesCode,
                                speciesName: item.speciesName,
                                spritePose: PlantSpritePose.idle,
                                outfitKey: item.outfitKey,
                                width: 34,
                                height: 50,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            '출발 전에 함께 갈 캐릭터를 고를 수 있어요.',
                            maxLines: 2,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayRewardLine extends StatelessWidget {
  const _TodayRewardLine({required this.catalog});

  final ExpeditionCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = catalog.heartResonanceAvailable;
    final text = ready
        ? '오늘 일기를 써서 마음 공명이 준비됐어요.'
        : catalog.diaryReady
            ? '오늘의 마음 공명 보상은 이미 받았어요. 지금부터는 자유 모험이에요.'
            : '마음 일기를 쓰면 오늘의 보상 모험이 열려요. 그전에도 자유롭게 다녀올 수 있어요.';
    return Row(
      children: [
        Icon(
          ready ? Icons.auto_awesome_rounded : Icons.explore_outlined,
          size: 18,
          color: ready ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _HubEntry {
  const _HubEntry({
    required this.icon,
    required this.title,
    required this.description,
    required this.lockReason,
    this.onTap,
    this.comingSoon = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? lockReason;

  /// 갈 수 있는 길만 값을 갖는다. 없으면 판만 그린다.
  final VoidCallback? onTap;

  /// 조건이 모자란 것이 아니라 아직 만들지 않은 길. 자물쇠 대신 공사 표시를
  /// 쓴다 — 자물쇠는 `무언가를 하면 열린다`는 약속인데 그럴 조건이 없다.
  final bool comingSoon;
}

class _HubEntryTile extends StatelessWidget {
  const _HubEntryTile({required this.entry});

  final _HubEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = entry.lockReason != null;
    final onTap = entry.onTap;
    final leading = entry.comingSoon
        ? Icons.handyman_outlined
        : locked
            ? Icons.lock_outline_rounded
            : entry.icon;
    final panel = MongrooPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            leading,
            size: 22,
            color: locked ? scheme.onSurfaceVariant : scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                // 잠긴 길도 무엇인지는 알려 준다. 사유만 남기면 `합동 수호전
                // · 아직 만들고 있어요`처럼 이름 말고는 아무것도 못 읽는다.
                // 시맨틱 라벨은 이미 설명을 읽어 주고 있었다.
                Text(
                  entry.description,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (entry.lockReason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.lockReason!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),
          // 갈 수 있는 길에만 화살표를 둔다. 이어서 모험하기 카드와 같은 신호다.
          if (onTap != null)
            Icon(Icons.chevron_right_rounded,
                size: 22, color: scheme.onSurfaceVariant),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: entry.comingSoon
          ? '${entry.title}, 준비 중. ${entry.description}'
          : locked
              ? '${entry.title}, 잠김. ${entry.description} ${entry.lockReason}'
              : '${entry.title}. ${entry.description}',
      // 잠김은 아이콘과 사유 줄이 이미 말한다. 여기에 불투명도까지 곱하면
      // 설명·사유가 쓰는 `onSurfaceVariant`(4.62:1)가 2.35:1로 떨어져서,
      // 정작 무엇을 하는 길인지 읽을 수 없게 된다.
      child: onTap == null
          ? panel
          : Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('hub-entry-${entry.title}'),
                borderRadius: BorderRadius.circular(15),
                onTap: onTap,
                child: panel,
              ),
            ),
    );
  }
}

/// 스테이지 지도 — 8개 점이 완만한 길로 이어진다.
///
/// 개편 설계서 5.2. 별점·점수·랭킹은 만들지 않고 클리어 체크와 이야기
/// 책갈피만 남긴다.
class _ExpeditionStageMapView extends ConsumerWidget {
  const _ExpeditionStageMapView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expeditionControllerProvider);
    final stageMap = state.stageMap;
    if (stageMap == null) {
      return const _CenteredMessage(
        icon: Icons.map_outlined,
        title: '지도를 불러오는 중이에요',
        description: '잠시만 기다려 주세요.',
      );
    }
    final notifier = ref.read(expeditionControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageMapHeader(stageMap: stageMap, onBack: notifier.goBackInShell),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                constraints.maxWidth >= 720 ? 32 : 14,
                6,
                constraints.maxWidth >= 720 ? 32 : 14,
                32,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final stage in stageMap.stages)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _StagePointTile(
                              key: ValueKey('stage-point-${stage.no}'),
                              stage: stage,
                              isNext: stage.no == stageMap.nextStageNo,
                              onTap: () => _openStageSheet(context, ref, stage),
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
      ],
    );
  }

  Future<void> _openStageSheet(
    BuildContext context,
    WidgetRef ref,
    ExpeditionStage stage,
  ) async {
    HapticFeedback.selectionClick();
    final start = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _StageDetailSheet(stage: stage),
    );
    if (start != true) return;
    ref.read(expeditionControllerProvider.notifier).openStagePreparation(
          stage.no,
        );
  }
}

class _StageMapHeader extends StatelessWidget {
  const _StageMapHeader({required this.stageMap, required this.onBack});

  final ExpeditionStageMap stageMap;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 4),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('stage-map-back'),
              onPressed: onBack,
              tooltip: '모험 허브로',
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stageMap.region.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  _StageProgressBar(
                    cleared: stageMap.clearedCount,
                    total: stageMap.total,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _StageProgressBar extends StatelessWidget {
  const _StageProgressBar({required this.cleared, required this.total});

  final int cleared;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$total개 중 $cleared개 완주',
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : cleared / total,
                minHeight: 6,
                backgroundColor: scheme.outlineVariant.withAlpha(90),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$cleared/$total',
            textScaler: TextScaler.noScaling,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

IconData _stageIcon(ExpeditionStage stage) => switch (stage.kind) {
      ExpeditionStageKind.event => Icons.chat_bubble_outline_rounded,
      ExpeditionStageKind.camp => Icons.local_fire_department_outlined,
      ExpeditionStageKind.boss => Icons.pets_rounded,
      ExpeditionStageKind.battle => Icons.directions_walk_rounded,
    };

class _StagePointTile extends StatelessWidget {
  const _StagePointTile({
    super.key,
    required this.stage,
    required this.isNext,
    required this.onTap,
  });

  final ExpeditionStage stage;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = !stage.unlocked;
    return Semantics(
      button: true,
      label: '${stage.label} ${stage.kindLabel}, ${stage.title}. '
          '${locked ? stage.lockReason ?? '잠김' : stage.cleared ? '완주함' : '아직 걷지 않음'}'
          '${stage.hasUnreadStory ? ', 못 본 이야기 있음' : ''}',
      // 잠긴 스테이지도 배지와 사유 줄이 이미 잠김을 말한다. 여기에 불투명도를
      // 곱하면 표기와 사유가 쓰는 `onSurfaceVariant`가 2.3:1로 내려간다.
      child: MongrooPanel(
          padding: EdgeInsets.zero,
          radius: 14,
          borderColor: isNext
              ? scheme.primary.withAlpha(140)
              : scheme.outlineVariant.withAlpha(120),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    _StagePointBadge(stage: stage, isNext: isNext),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 큰 글자에서는 표기와 종류 태그가 자연스럽게 아래로 접힌다.
                          LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  stage.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                                MongrooTag(
                                  label: stage.elite
                                      ? '${stage.kindLabel} · 큰 엉킴'
                                      : stage.kindLabel,
                                  icon: _stageIcon(stage),
                                  maxWidth: constraints.maxWidth,
                                  backgroundColor:
                                      scheme.secondaryContainer.withAlpha(120),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            stage.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (locked) ...[
                            const SizedBox(height: 2),
                            Text(
                              stage.lockReason ?? '',
                              maxLines: 2,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (stage.hasUnreadStory)
                      Icon(
                        Icons.bookmark_added_outlined,
                        size: 18,
                        color: scheme.tertiary,
                      ),
                    if (isNext && !stage.cleared)
                      Icon(Icons.play_arrow_rounded, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

class _StagePointBadge extends StatelessWidget {
  const _StagePointBadge({required this.stage, required this.isNext});

  final ExpeditionStage stage;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = stage.cleared
        ? scheme.primary
        : isNext
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final foreground = stage.cleared
        ? scheme.onPrimary
        : isNext
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(
          color: stage.elite ? scheme.error.withAlpha(170) : Colors.transparent,
          width: stage.elite ? 2 : 0,
        ),
      ),
      child: stage.cleared
          ? Icon(Icons.check_rounded, size: 22, color: foreground)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_stageIcon(stage), size: 16, color: foreground),
                Text(
                  '${stage.no}',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 스테이지 상세 시트 — 종류, 등장 엉킴과 약점, 예상 시간, 출발.
class _StageDetailSheet extends ConsumerWidget {
  const _StageDetailSheet({required this.stage});

  final ExpeditionStage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locked = !stage.unlocked;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: Text(
                      '${stage.label} · ${stage.title}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  MongrooTag(
                    label: stage.elite
                        ? '${stage.kindLabel} · 큰 엉킴'
                        : stage.kindLabel,
                    icon: _stageIcon(stage),
                    maxWidth: constraints.maxWidth,
                    backgroundColor: scheme.secondaryContainer.withAlpha(130),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(stage.summary),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  stage.estimatedLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (stage.weaknessLabel case final weakness?) ...[
                  const SizedBox(width: 14),
                  Icon(
                    Icons.gps_fixed_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '약점 $weakness',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
            if (stage.tangles.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('여기서 만나요', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final tangle in stage.tangles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        tangle.catalogued
                            ? Icons.menu_book_rounded
                            : Icons.help_outline_rounded,
                        size: 18,
                        color: scheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tangle.name,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              tangle.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            if (tangle.catalogued &&
                                tangle.skills.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 5,
                                runSpacing: 5,
                                children: [
                                  for (final skill in tangle.skills)
                                    MongrooTag(
                                      label: skill,
                                      icon: Icons.bolt_rounded,
                                      backgroundColor: scheme.tertiaryContainer
                                          .withAlpha(118),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (stage.cleared) ...[
              const SizedBox(height: 12),
              Text(
                '${stage.clearCount}번 다녀왔어요. 다시 걸어도 보상은 늘지 않아요.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 18),
            if (stage.cleared && stage.story != null) ...[
              OutlinedButton.icon(
                key: const ValueKey('stage-story-replay'),
                onPressed: () => _showStory(context, ref, stage.story!),
                icon: const Icon(Icons.auto_stories_outlined),
                label: const Text('이야기 다시 보기'),
              ),
              const SizedBox(height: 8),
            ],
            if (locked)
              Text(
                stage.lockReason ?? '아직 열리지 않은 길이에요.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              FilledButton.icon(
                key: const ValueKey('stage-sheet-start'),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(stage.cleared ? '다시 걷기' : '출발'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStory(
    BuildContext context,
    WidgetRef ref,
    ExpeditionStageStory story,
  ) async {
    final sfxEnabled = ref.read(expeditionBattleSettingsProvider).sfxEnabled;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StageStoryRevealCard(
                  story: story,
                  audioEnabled: sfxEnabled,
                  replay: true,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('기록 덮기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    await ref
        .read(expeditionControllerProvider.notifier)
        .markStageStorySeen(stage.no);
  }
}
