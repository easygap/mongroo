part of 'expedition_screen.dart';

class ExpeditionJournalScreen extends ConsumerWidget {
  const ExpeditionJournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expeditionControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('현장 수첩'),
        leading: IconButton(
          tooltip: '탐험 지도로',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/explore'),
        ),
      ),
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.stageMap == null
                ? _CenteredMessage(
                    icon: Icons.cloud_off_outlined,
                    title: '수첩을 불러오지 못했습니다',
                    description: state.error ?? '연결을 확인해 주세요.',
                    actionLabel: '다시 불러오기',
                    onAction:
                        ref.read(expeditionControllerProvider.notifier).load)
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: Center(
                        child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: const ExpeditionStoryJournal(),
                    )),
                  ),
      ),
    );
  }
}

/// 직접 탐험에서 얻은 이야기를 순찰 기록과 별개로 보관한다.
class ExpeditionStoryJournal extends ConsumerWidget {
  const ExpeditionStoryJournal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stageMap = ref
        .watch(expeditionControllerProvider.select((state) => state.stageMap));
    if (stageMap == null) return const SizedBox.shrink();
    final collected = stageMap.stages
        .where((stage) => stage.cleared && stage.story != null)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${stageMap.region.name} · 현장 기록',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text('${stageMap.total}곳 중 ${stageMap.clearedCount}곳 조사 완료',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      if (collected.isEmpty) const Text('탐험을 마치고 돌아오면 이곳에 이야기가 남습니다.'),
      for (final stage in collected)
        ExpansionTile(
          key:
              PageStorageKey('field-story-${stageMap.region.code}-${stage.no}'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
                width: 58,
                height: 58,
                child: Builder(builder: (context) {
                  final art = _AtlasArt.forRegion(stageMap.region.code);
                  final stop = art.stops[(stage.no - 1).clamp(0, 7)];
                  return Stack(children: [
                    Positioned(
                        left: 29 - stop.dx * 210,
                        top: 48 - stop.dy * 315,
                        width: 210,
                        height: 315,
                        child: Image.asset(art.asset,
                            fit: BoxFit.fill, excludeFromSemantics: true)),
                  ]);
                })),
          ),
          title: Text('${stage.no}. ${stage.story!.title}'),
          onExpansionChanged: (open) {
            if (open && !stage.storySeen) {
              unawaited(ref
                  .read(expeditionControllerProvider.notifier)
                  .markStageStorySeen(stage.no));
            }
          },
          children: [
            Align(
                alignment: Alignment.centerLeft,
                child: Text(stage.story!.caption))
          ],
        ),
      const Divider(height: 24),
    ]);
  }
}

/// 모험 허브 — `지금 누를 것 하나`를 크게, 나머지를 작게.
///
/// 개편 설계서 5.1. 배지·빨간 점·카운트다운으로 재촉하지 않고, 오늘의 보상
/// 상태는 사실만 한 줄로 알린다.
class _ExpeditionHub extends ConsumerWidget {
  const _ExpeditionHub(
      {this.embedded = false,
      this.onPatrol,
      this.onJournal,
      this.mapOnly = false});

  final bool embedded;
  final VoidCallback? onPatrol;
  final VoidCallback? onJournal;
  final bool mapOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (embedded) {
      ref.listen(expeditionControllerProvider.select((state) => state.error),
          (previous, next) {
        if (next == null || previous == next) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next)));
        ref.read(expeditionControllerProvider.notifier).clearError();
      });
    }
    final state = ref.watch(expeditionControllerProvider);
    final catalog = state.catalog;
    final stageMap = state.stageMap;
    if (state.loading) return const Center(child: CircularProgressIndicator());
    if (catalog == null || stageMap == null) {
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
    final notifier = ref.read(expeditionControllerProvider.notifier);
    return _ExpeditionAtlas(
      stageMap: stageMap,
      roster: state.roster,
      selectedPlantIds: state.selectedPlantIds,
      resume: state.expedition?.run.isActive == true,
      busy: state.busyAction != null,
      onRefresh: notifier.load,
      onBack: !embedded && Navigator.canPop(context)
          ? () => context.pop()
          : mapOnly
              ? notifier.goBackInShell
              : null,
      onDepart: () {
        if (state.expedition?.run.isActive != true) {
          unawaited(notifier.continueNextStage());
        }
        if (embedded) context.push('/expedition');
      },
      onParty: () {
        final stage = stageMap.nextStage ?? stageMap.stages.lastOrNull;
        if (stage == null) return;
        notifier.openStagePreparation(stage.no);
        if (embedded) context.push('/expedition');
      },
      onStage: (stage) => _openAtlasStage(context, ref, stage),
      onPrepare: (stage) {
        if (!stage.unlocked || state.expedition?.run.isActive == true) return;
        notifier.openStagePreparation(stage.no);
        if (embedded) context.push('/expedition');
      },
      onRegions: () => _openRegions(context, ref),
      onJournal: onJournal ??
          () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: const ExpeditionStoryJournal()))),
      onRoutes: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('다른 탐험',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        for (final entry in _hubEntries(context, ref, stageMap))
                          Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _HubEntryTile(
                                  entry: _HubEntry(
                                      icon: entry.icon,
                                      title: entry.title,
                                      description: entry.description,
                                      lockReason: entry.lockReason,
                                      onTap: entry.onTap == null
                                          ? null
                                          : () {
                                              Navigator.pop(sheetContext);
                                              entry.onTap!();
                                            }))),
                        const SizedBox(height: 8),
                        _TodayRewardLine(catalog: catalog),
                      ])))),
    );
  }

  Future<void> _openAtlasStage(
      BuildContext context, WidgetRef ref, ExpeditionStage stage) async {
    final state = ref.read(expeditionControllerProvider);
    if (state.busyAction != null) return;
    final active = state.expedition?.run.isActive == true;
    if (active && stage.no == state.expedition?.run.stageNo) {
      if (embedded) context.push('/expedition');
      return;
    }
    final region = state.stageMap!.region.code;
    final depart = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .88),
          child: SingleChildScrollView(
              child: _StageDetailSheet(
                  stage: stage, regionCode: region, canDepart: !active))),
    );
    if (depart != true || !context.mounted) return;
    ref
        .read(expeditionControllerProvider.notifier)
        .openStagePreparation(stage.no);
    if (embedded) context.push('/expedition');
  }

  void _openRegions(BuildContext context, WidgetRef ref) {
    final map = ref.read(expeditionControllerProvider).stageMap!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('탐험 지역',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    for (final region in map.regions)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey('region-chip-${region.code}'),
                              onTap: !region.unlocked
                                  ? null
                                  : () {
                                      Navigator.pop(sheetContext);
                                      ref
                                          .read(expeditionControllerProvider
                                              .notifier)
                                          .selectRegion(region.code);
                                    },
                              child: Row(children: [
                                SizedBox(
                                    width: 86,
                                    height: 106,
                                    child: Image.asset(
                                        _AtlasArt.forRegion(region.code).asset,
                                        fit: BoxFit.cover,
                                        excludeFromSemantics: true)),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(region.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall),
                                              const SizedBox(height: 6),
                                              Text(
                                                  region.unlocked
                                                      ? '${region.clearedCount}/${region.total}곳 탐험'
                                                      : region.lockReason ??
                                                          '앞 지역을 마치면 열립니다.',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall),
                                            ]))),
                                Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Icon(!region.unlocked
                                        ? Icons.lock_outline_rounded
                                        : region.code == map.region.code
                                            ? Icons.check_circle_outline_rounded
                                            : Icons.chevron_right_rounded)),
                              ]),
                            ),
                          )),
                  ]))),
    );
  }

  /// 허브에서 갈 수 있는 다른 길.
  ///
  /// **누를 수 없는 것을 열린 것처럼 두지 않는다.** 예전에는 네 항목이 모두
  /// 그냥 판이라, 잠기지 않은 `자동 순찰`·`깊은 조사`를 눌러도 아무 일이 없고
  /// 아직 만들지 않은 `합동 수호전`은 지역을 깨면 열린 모습이 되었다.
  /// 지금은 둘로 갈린다 — 갈 수 있으면 [_HubEntry.onTap]이 있고, 조건이
  /// 모자라면 [_HubEntry.lockReason]이 이유를 문장으로 말한다.
  ///
  /// `준비 중` 상태는 없앴다. 장거리 개척까지 들어와서 허브의 네 길이 전부
  /// 서버에 있다 — 남은 것은 `아직 못 여는 길`뿐이고, 그건 잠김이 말한다.
  List<_HubEntry> _hubEntries(
    BuildContext context,
    WidgetRef ref,
    ExpeditionStageMap stageMap,
  ) {
    final notifier = ref.read(expeditionControllerProvider.notifier);
    // 깊은 조사는 **지금 보고 있는 지역**의 8스테이지를 마쳐야 열린다.
    // 카탈로그의 `deepAvailable`은 첫 지역 기준이라, 지역을 옮기고 나면
    // 잠긴 곳이 열린 것처럼 보인다.
    final deepAvailable = stageMap.regionCleared;
    // 합동 수호전은 지역별이 아니라 계정 단위로 열린다. 한 지역이라도
    // 수호짐승을 만나 봤으면 입구가 선다.
    final jointGuardOpen = stageMap.regions.any((region) => region.cleared) ||
        stageMap.regionCleared;
    // 장거리 개척은 **우물정원을 완주**해야 첫 방향이 열린다(설계서 9.8).
    // 진짜 관문은 서버에 있고 여기는 문패일 뿐이라, 조건이 어긋나도 잠긴
    // 이유를 개척 화면이 방향마다 다시 읽어 준다.
    final journeyOpen = stageMap.regions
        .any((region) => region.code == 'echo_well' && region.cleared);
    return [
      _HubEntry(
        icon: Icons.hiking_rounded,
        title: '자동 순찰',
        description: '대원을 보내 두고 나중에 발견물을 받습니다.',
        lockReason: null,
        // 순찰 보내기는 모험 탭(`오늘의 순찰`)이 들고 있다. 같은 것을 두 곳에
        // 만들지 않고, 여기서는 그 화면으로 돌려보낸다.
        onTap: onPatrol ?? () => context.push('/patrol'),
      ),
      _HubEntry(
        icon: Icons.travel_explore_rounded,
        title: '깊은 조사',
        description: '등불을 관리하며 갈림길과 숨은 방을 조사합니다.',
        // 사유는 지역 이름을 넣어 직접 만든다. 서버도 같은 뜻을 보내지만
        // `지역의 8스테이지`라고만 해서, 지금 보고 있는 곳이 어디인지 모른다.
        lockReason:
            deepAvailable ? null : '${stageMap.region.shortName} 8까지 완주하면 열려요.',
        onTap: deepAvailable
            ? () {
                notifier.openDeepPreparation();
                if (embedded) context.push('/expedition');
              }
            : null,
      ),
      _HubEntry(
        icon: Icons.groups_2_rounded,
        title: '합동 수호전',
        description: '대원 여섯 명의 역할을 나눠 수호짐승과 맞섭니다.',
        // 수호짐승의 장벽을 **어디서든** 한 번 열면 입구가 상시 열린다.
        // 지금 보고 있는 지역으로 재면, 첫 지역을 깬 사람이 다음 지역
        // 지도를 보는 동안 잠긴 것처럼 보인다.
        lockReason: jointGuardOpen ? null : '수호짐승의 장벽을 한 번 열면 관리인이 편지를 보내요.',
        onTap: jointGuardOpen ? () => context.push('/joint-guard') : null,
      ),
      _HubEntry(
        icon: Icons.map_outlined,
        title: '장거리 개척',
        description: '구간마다 탐험대를 배치해 온실 밖을 조사합니다.',
        // 우물정원을 완주하면 첫 방향이 열린다(설계서 9.8). 합동 수호전과
        // 달리 **지역을 끝까지** 걸어야 하므로 조건이 한 칸 더 높다.
        lockReason: journeyOpen ? null : '우물정원을 완주하면 온실 밖으로 나가는 길이 열려요.',
        onTap: journeyOpen ? () => context.push('/journey') : null,
      ),
    ];
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
        ? '오늘의 탐험 보상을 받을 수 있습니다.'
        : catalog.diaryReady
            ? '오늘 보상 수령 완료. 탐험은 계속할 수 있습니다.'
            : '지금 바로 탐험할 수 있습니다. 일기를 쓴 날에는 추가 보상을 받습니다.';
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
  });

  final IconData icon;
  final String title;
  final String description;
  final String? lockReason;

  /// 갈 수 있는 길만 값을 갖는다. 없으면 판만 그린다.
  final VoidCallback? onTap;

  /// 조건이 모자란 것이 아니라 아직 만들지 않은 길. 자물쇠 대신 공사 표시를
  /// 쓴다 — 자물쇠는 `무언가를 하면 열린다`는 약속인데 그럴 조건이 없다.
}

class _HubEntryTile extends StatelessWidget {
  const _HubEntryTile({required this.entry});

  final _HubEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = entry.lockReason != null;
    final onTap = entry.onTap;
    final leading = locked ? Icons.lock_outline_rounded : entry.icon;
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
      container: true,
      button: onTap != null,
      label: locked
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

/// Returning from party preparation restores the same spatial map.
class _ExpeditionStageMapView extends StatelessWidget {
  const _ExpeditionStageMapView();
  @override
  Widget build(BuildContext context) => const _ExpeditionHub(mapOnly: true);
}

IconData _stageIcon(ExpeditionStage stage) => switch (stage.kind) {
      ExpeditionStageKind.event => Icons.chat_bubble_outline_rounded,
      ExpeditionStageKind.camp => Icons.local_fire_department_outlined,
      ExpeditionStageKind.boss => Icons.pets_rounded,
      ExpeditionStageKind.battle => Icons.directions_walk_rounded,
    };

/// 스테이지 상세 시트 — 종류, 등장 엉킴과 약점, 예상 시간, 출발.
class _StageDetailSheet extends ConsumerWidget {
  const _StageDetailSheet(
      {required this.stage, required this.regionCode, this.canDepart = true});

  final ExpeditionStage stage;
  final bool canDepart;

  /// 이야기 컷이 지역 전용 원화를 고르는 데 쓴다.
  final String regionCode;

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
                onPressed: () =>
                    _showStory(context, ref, stage.story!, regionCode),
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
            else if (!canDepart)
              const Text('현재 탐험을 마치면 이곳으로 이동할 수 있습니다.',
                  textAlign: TextAlign.center)
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
    String regionCode,
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
                  regionCode: regionCode,
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
