part of 'expedition_screen.dart';

/// 스테이지 세션의 필드와 비전투 장면 — 직접 걷기·사건·쉼터·귀환.
///
/// 개편 설계서 5.4의 필드 연출 계약을 따른다. 사건은 카드 텍스트 더미가
/// 아니라 배경 장면 위의 말풍선 하나로 말하고, 선택지는 어울리는 힘과
/// 성공 예상 세 단어만 크게 보여 준다. 정확한 수치는 길게 누르면 열린다.
class _ImmersiveStageScene extends ConsumerWidget {
  const _ImmersiveStageScene({required this.expedition});

  final ExpeditionSnapshot expedition;

  Future<void> _confirmRetreat(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지금 안전하게 돌아갈까요?'),
        content: const Text('아직 확정하지 않은 발견물과 보상은 가져갈 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('계속 진행'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('돌아가기'),
          ),
        ],
      ),
    );
    if (leave != true || !context.mounted) return;
    HapticFeedback.mediumImpact();
    await ref.read(expeditionControllerProvider.notifier).retreat();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expeditionControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final node = expedition.nodes.firstWhere(
      (item) => item.code == expedition.run.currentNodeCode,
    );
    final event = expedition.currentEvent;
    final fieldStory = expedition.memory['stage_field'] is Map<String, dynamic>
        ? expedition.memory['stage_field'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final walkingField = event == null &&
        !expedition.run.objectiveSecured &&
        expedition.availableMoveCodes.isNotEmpty;
    if (walkingField) {
      return _StageWalkingField(
        expedition: expedition,
        story: fieldStory,
        locked: state.interactionLocked,
        onRetreat: () => _confirmRetreat(context, ref),
      );
    }
    final scene =
        expeditionSceneTheme(node.sceneKey, regionCode: expedition.region.code);
    final actor = expedition.party
            .where(
              (member) =>
                  member.id ==
                  (state.actionCue?.actorId ?? state.selectedMemberId),
            )
            .firstOrNull ??
        expedition.party.firstOrNull;
    final resolution = expedition.lastResolution;
    final finished = event == null && expedition.run.objectiveSecured;
    final resting = node.type == 'camp';
    // 5.4: 화면 말풍선은 28자 1줄이다. 예전에는 사건 원고가 곧 말풍선이라
    // 33~58자가 그대로 나갔다. 원고는 `event.text`에 남아 길게 누르면 열린다.
    final bubbleText = event != null
        ? event.bubble
        : resting
            ? '등불을 채우고 장비를 정리했다.'
            : resolution != null
                // 결과 문장은 서버가 주므로 길이를 여기서 못 정한다. 뒤에
                // 붙는 안내만 짧게 둔다(5.4의 `즉시 결과 18자 이하`).
                ? resolution.displayText
                : '조사를 마쳤다.';
    // 길게 누르면 열리는 원고. 사건일 때만 있다.
    final bubbleDetail =
        event != null && event.text != event.bubble ? event.text : null;

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          constraints.maxWidth >= 720 ? 32 : 12,
          8,
          constraints.maxWidth >= 720 ? 32 : 12,
          28,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (expedition.run.stageNo != null) ...[
                    _StageProgressRail(stageNo: expedition.run.stageNo!),
                    const SizedBox(height: 2),
                  ],
                  SizedBox(
                    // 이 줄에 후퇴 버튼이 들어간다. 44로 두면 버튼이 그 높이로
                    // 눌려 48dp 입력 영역을 못 채운다.
                    height: 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: LayoutBuilder(
                              builder: (context, tagConstraints) => MongrooTag(
                                label:
                                    '${node.depthLabel} · ${finished ? '조사 완료' : node.sceneLabel}',
                                icon: finished
                                    ? Icons.flag_circle_rounded
                                    : scene.icon,
                                maxWidth: tagConstraints.maxWidth,
                                backgroundColor:
                                    scheme.secondaryContainer.withAlpha(120),
                              ),
                            ),
                          ),
                        ),
                        if (!finished)
                          IconButton(
                            key: const ValueKey('stage-scene-retreat'),
                            onPressed: state.interactionLocked
                                ? null
                                : () => _confirmRetreat(context, ref),
                            tooltip: '지금 안전하게 돌아가기',
                            icon: const Icon(Icons.keyboard_return_outlined),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  MongrooPanel(
                    key: const ValueKey('stage-scene-stage'),
                    padding: EdgeInsets.zero,
                    radius: 18,
                    borderColor: scene.accent.withAlpha(105),
                    child: ExpeditionSceneBackdrop(
                      scene: scene,
                      regionCode: expedition.region.code,
                      sceneKey: node.sceneKey,
                      borderRadius: BorderRadius.circular(18),
                      semanticLabel:
                          '${node.sceneLabel}. ${node.sceneDescription}',
                      child: AspectRatio(
                        aspectRatio: 4 / 3.1,
                        child: Stack(
                          children: [
                            ExpeditionEncounterStage(
                              encounter: null,
                              regionCode: expedition.region.code,
                              actor: actor,
                              party: expedition.party,
                              cue: state.actionCue,
                              onCueCompleted: ref
                                  .read(expeditionControllerProvider.notifier)
                                  .clearActionCue,
                            ),
                            if (state.actionCue == null)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 10,
                                child: _SceneSpeechBubble(
                                  key: const ValueKey('stage-scene-bubble'),
                                  title: event?.title ??
                                      (resting ? '잠깐의 쉼' : node.name),
                                  text: bubbleText,
                                  detail: bubbleDetail,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (event != null) ...[
                    _StageActorPicker(
                      party: expedition.party,
                      selectedMemberId: actor?.id,
                      locked: state.interactionLocked,
                      onSelect: (memberId) => ref
                          .read(expeditionControllerProvider.notifier)
                          .selectMember(memberId),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${koreanTopic(actor?.name ?? '탐험대')} 어떻게 할까요?',
                      key: const ValueKey('stage-scene-prompt'),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    for (final choice in event.choices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _StageChoiceCard(
                          key: ValueKey('stage-choice-${choice.code}'),
                          choice: choice,
                          preview: actor == null
                              ? null
                              : choice.previewFor(actor.id),
                          enabled: !state.interactionLocked,
                          onPressed: () => ref
                              .read(expeditionControllerProvider.notifier)
                              .choose(choice.code),
                        ),
                      ),
                  ] else ...[
                    if (resolution?.finding != null ||
                        (resolution?.lightRecovered ?? 0) > 0)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                              resolution?.finding != null
                                  ? '수첩에 기록: ${resolution!.finding}'
                                  : '길빛 +${resolution!.lightRecovered}',
                              key: const ValueKey('stage-decision-consequence'),
                              style: Theme.of(context).textTheme.titleSmall)),
                    if (expedition.loot.isNotEmpty)
                      MongrooPanel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 20,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                expedition.loot
                                    .map(
                                      (loot) =>
                                          '${loot.name} ×${loot.quantity}',
                                    )
                                    .join(' · '),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (expedition.canExtract)
                      FilledButton.icon(
                        key: const ValueKey('stage-scene-extract'),
                        onPressed: state.interactionLocked
                            ? null
                            : () => ref
                                .read(expeditionControllerProvider.notifier)
                                .extract(),
                        icon: const Icon(Icons.home_outlined),
                        label: const Text('탐험 마치기'),
                      ),
                    // 이 걸음을 마쳤고 다음 걸음이 남았으면, 결과도 다음
                    // 출발도 이 무대 위에서 끝난다.
                    if (stageAdvanceAvailable(state))
                      _StageAdvancePanel(expedition: expedition),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 한 스테이지의 입구에서 목적 랜드마크까지 직접 걷는 필드.
///
/// 작은 모서리 미니맵이 아니라 지역 원화를 그대로 보행 공간으로 쓴다. 빈 길을
/// 누른 채 끌면 그 자리에 스틱이 생기고, 스크린리더·키보드 사용자는 목적
/// 랜드마크 버튼을 눌러 같은 서버 이동에 도달한다.
class _StageWalkingField extends StatelessWidget {
  const _StageWalkingField(
      {required this.expedition,
      required this.story,
      required this.locked,
      required this.onRetreat});
  final ExpeditionSnapshot expedition;
  final Map<String, dynamic> story;
  final bool locked;
  final VoidCallback onRetreat;

  @override
  Widget build(BuildContext context) {
    final destination = expedition.nodes.firstWhere(
        (node) => expedition.availableMoveCodes.contains(node.code));
    final title = story['title'] as String? ?? destination.name;
    final objective =
        story['objective'] as String? ?? destination.sceneDescription;
    final approach = story['approach'] as String? ?? '';
    final hint = story['destination_hint'] as String? ?? '깃발이 있는 곳으로 이동하세요.';
    void readObjective() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(objective),
                  if (approach.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(approach)
                  ],
                  const SizedBox(height: 16),
                  Text(hint),
                ])));
    return ColoredBox(
        color: _atlasPaper,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Row(children: [
                IconButton(
                    tooltip: '탐험 지도',
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/explore'),
                    icon: const Icon(Icons.arrow_back_rounded)),
                Expanded(
                    child: _StageProgressRail(
                        stageNo: expedition.run.stageNo ?? 1, title: title)),
                IconButton(
                    key: const ValueKey('stage-field-retreat'),
                    onPressed: locked ? null : onRetreat,
                    tooltip: '탐험 중단',
                    icon: const Icon(Icons.logout_rounded)),
              ])),
          Expanded(
              child: LayoutBuilder(
                  builder: (context, constraints) =>
                      Stack(key: const ValueKey('stage-field-map'), children: [
                        Positioned.fill(
                            child: _ExpeditionTileWorld(
                                expedition: expedition,
                                destination: destination)),
                        Positioned(
                          left: 10,
                          top: 10,
                          child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxWidth: math.max(
                                      120, constraints.maxWidth - 148)),
                              child: Material(
                                  color: _atlasPaper,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: const BorderSide(color: _atlasInk)),
                                  child: InkWell(
                                      key: const ValueKey('stage-field-story'),
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: readObjective,
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.search_rounded,
                                                    size: 20, color: _atlasInk),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                    child: Text('조사할 것',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .labelLarge
                                                            ?.copyWith(
                                                                color:
                                                                    _atlasInk))),
                                              ]))))),
                        ),
                      ]))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text('끌어서 이동 · 방향키 지원',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall)),
        ]));
  }
}

/// 장면 위 말풍선. 5.4의 28자 1줄을 담고, 원고는 길게 누르면 열린다.
class _SceneSpeechBubble extends StatelessWidget {
  const _SceneSpeechBubble({
    super.key,
    required this.title,
    required this.text,
    this.detail,
  });

  final String title;
  final String text;

  /// 사건 원고 전문. 있으면 길게 눌러 열 수 있다.
  final String? detail;

  Future<void> _showDetail(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(
                  detail!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        button: detail != null,
        onTap: detail == null ? null : () => _showDetail(context),
        label: [
          title,
          text,
          if (detail != null) '눌러서 기록 읽기',
        ].join('. '),
        child: GestureDetector(
          onTap: detail == null ? null : () => _showDetail(context),
          onLongPress: detail == null ? null : () => _showDetail(context),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MongrooPalette.of(context).night.withAlpha(216),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withAlpha(40)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.onNight.withAlpha(200),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.onNight, height: 1.35),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 6),
                    Text('기록 읽기  ›',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.onNight,
                            )),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _StageActorPicker extends StatelessWidget {
  const _StageActorPicker({
    required this.party,
    required this.selectedMemberId,
    required this.locked,
    required this.onSelect,
  });

  final List<ExpeditionMember> party;
  final int? selectedMemberId;
  final bool locked;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final member in party) ...[
          if (member.id != party.first.id) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              container: true,
              selected: member.id == selectedMemberId,
              button: true,
              label: '${member.name}에게 맡기기',
              child: Material(
                color: member.id == selectedMemberId
                    ? scheme.primaryContainer
                    : scheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: member.id == selectedMemberId
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: member.id == selectedMemberId ? 1.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: locked ? null : () => onSelect(member.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: PlantView(
                            stage: member.stage,
                            form: PlantGrowthForm.fromCode(member.form),
                            speciesCode: member.speciesCode,
                            speciesName: member.speciesName,
                            spritePose: PlantSpritePose.idle,
                            outfitKey: member.outfitKey,
                            width: 26,
                            height: 38,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 사건 선택 카드 — 어울리는 힘과 성공 예상 세 단어만 크게.
class _StageChoiceCard extends StatelessWidget {
  const _StageChoiceCard(
      {super.key,
      required this.choice,
      required this.preview,
      required this.enabled,
      required this.onPressed});
  final ExpeditionChoice choice;
  final ExpeditionChoicePreview? preview;
  final bool enabled;
  final VoidCallback onPressed;

  Future<void> _showDetail(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(choice.label,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  if (choice.consequence.isNotEmpty) Text(choice.consequence),
                  if (preview != null && !choice.safe) ...[
                    const SizedBox(height: 12),
                    Text(preview!.label),
                    const SizedBox(height: 8),
                    Text('성공 예상 ${preview!.chance}%. 대원 능력에 1~4를 더해 판정합니다.'),
                  ],
                  const SizedBox(height: 8),
                  Text(choice.safe
                      ? '판정과 자원 소모 없이 지나갑니다.'
                      : '실패하면 결의 ${preview?.failureResolveCost ?? choice.resolveCost} 소모. 발견물과 회복 효과는 얻지 못합니다.'),
                ])),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chance = preview?.chance;
    final forecast = choice.safe
        ? '그냥 지나가기'
        : chance == null
            ? ''
            : '성공 $chance%';
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
            child: InkWell(
          onTap: enabled ? onPressed : null,
          onLongPress: () => _showDetail(context),
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(choice.label,
                        style: Theme.of(context).textTheme.titleSmall),
                    if (choice.consequence.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(choice.consequence,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 8),
                    Text(
                        [
                          if (preview?.statLabel != null) preview!.statLabel!,
                          forecast,
                          if (!choice.safe)
                            '실패 시 결의 −${preview?.failureResolveCost ?? choice.resolveCost}'
                        ].where((s) => s.isNotEmpty).join(' / '),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: chance != null && chance == 0 && !choice.safe
                                ? scheme.error
                                : scheme.onSurfaceVariant)),
                  ])),
        )),
        IconButton(
            onPressed: () => _showDetail(context),
            tooltip: '${choice.label} 판정 정보',
            icon: const Icon(Icons.info_outline, size: 20)),
      ]),
    );
  }
}
