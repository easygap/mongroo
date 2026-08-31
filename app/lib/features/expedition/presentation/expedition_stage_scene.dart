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
    if (leave != true) return;
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
    final bubbleText = event != null
        ? event.text
        : resting
            ? '따뜻한 불가에 앉아 숨을 골랐어요. 길빛과 결의가 조금 차올랐어요.'
            : resolution != null
                ? '${resolution.outcome} 이제 기록을 안고 돌아갈 수 있어요.'
                : '이 걸음의 일을 마쳤어요. 기록을 안고 돌아갈 수 있어요.';

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
                                    '${node.depthLabel} · ${finished ? '걸음 완료' : node.sceneLabel}',
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
                        label: const Text('기록을 안고 귀환'),
                      ),
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
  const _StageWalkingField({
    required this.expedition,
    required this.story,
    required this.locked,
    required this.onRetreat,
  });

  final ExpeditionSnapshot expedition;
  final Map<String, dynamic> story;
  final bool locked;
  final VoidCallback onRetreat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destination = expedition.nodes.firstWhere(
      (node) => expedition.availableMoveCodes.contains(node.code),
    );
    final chapter = story['chapter'] is num
        ? (story['chapter'] as num).toInt()
        : expedition.run.stageNo;
    final title = story['title'] as String? ?? destination.name;
    final approach =
        story['approach'] as String? ?? '랜드마크 사이의 길이 천천히 모습을 드러내요.';
    final objective =
        story['objective'] as String? ?? destination.sceneDescription;
    final hint =
        story['destination_hint'] as String? ?? '빛나는 표식에 닿으면 다음 장면이 시작돼요.';

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
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: LayoutBuilder(
                              builder: (context, tagConstraints) => MongrooTag(
                                label:
                                    '${chapter == null ? '던전' : '$chapter장'} · 직접 걷기',
                                icon: Icons.directions_walk_rounded,
                                maxWidth: tagConstraints.maxWidth,
                                backgroundColor:
                                    scheme.secondaryContainer.withAlpha(138),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('stage-field-retreat'),
                          onPressed: locked ? null : onRetreat,
                          tooltip: '지금 안전하게 돌아가기',
                          icon: const Icon(Icons.keyboard_return_outlined),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    container: true,
                    liveRegion: true,
                    label: '$title. $approach $objective',
                    child: MongrooPanel(
                      key: const ValueKey('stage-field-story'),
                      color: scheme.tertiaryContainer.withAlpha(150),
                      borderColor: scheme.tertiary.withAlpha(70),
                      shadowOffset: const Offset(0, 3),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Text(approach),
                          const SizedBox(height: 6),
                          Text(
                            objective,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onTertiaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  MongrooPanel(
                    key: const ValueKey('stage-field-map'),
                    padding: EdgeInsets.zero,
                    radius: 20,
                    borderColor: expeditionSceneTheme(
                      destination.sceneKey,
                      regionCode: expedition.region.code,
                    ).accent.withAlpha(120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio:
                              constraints.maxWidth < 520 ? 1.45 : 16 / 9,
                          child: _ExpeditionTileWorld(
                            expedition: expedition,
                            destination: destination,
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(20),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(13, 10, 13, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.touch_app_rounded,
                                  size: 22,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '화면을 누른 채 원하는 방향으로 끌어 걸어요',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '카메라가 따라오며, 벽·물·조형물은 통과할 수 없어요.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  MongrooPanel(
                    color: scheme.secondaryContainer.withAlpha(120),
                    shadowOffset: Offset.zero,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          color: scheme.secondary,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                story['destination_name'] as String? ??
                                    destination.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(hint),
                            ],
                          ),
                        ),
                      ],
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

/// 장면 위 말풍선. 사건 본문은 90자 계약을 따르므로 한 덩이면 충분하다.
class _SceneSpeechBubble extends StatelessWidget {
  const _SceneSpeechBubble(
      {super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: '$title. $text',
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
              ],
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
  const _StageChoiceCard({
    super.key,
    required this.choice,
    required this.preview,
    required this.enabled,
    required this.onPressed,
  });

  final ExpeditionChoice choice;
  final ExpeditionChoicePreview? preview;
  final bool enabled;
  final VoidCallback onPressed;

  Future<void> _showDetail(BuildContext context) async {
    final detail = preview;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(choice.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (detail != null)
                Text(
                  detail.safe ? '판정 없이 안전하게 진행돼요. 잃는 것도 없어요.' : detail.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              if (!choice.safe) ...[
                const SizedBox(height: 8),
                Text(
                  '뜻대로 되지 않으면 우회로가 열리고 결의를 ${choice.resolveCost} 써요. '
                  '우회도 실패가 아니라 시간이 더 드는 안전한 해결이에요.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outlook = preview?.outlook ?? (choice.safe ? '안전하게 진행돼요' : '');
    final statLabel = preview?.statLabel;
    return Semantics(
      button: true,
      enabled: enabled,
      label:
          '${choice.label}. ${statLabel != null ? '어울리는 힘 $statLabel. ' : ''}$outlook. 길게 눌러 자세히 보기',
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: choice.safe
                ? scheme.outlineVariant
                : scheme.primary.withAlpha(120),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          onLongPress: () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        choice.label,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      // 큰 글자에서는 태그가 줄을 바꾸고, 그래도 길면 말줄임한다.
                      LayoutBuilder(
                        builder: (context, tagConstraints) => Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (statLabel != null)
                              MongrooTag(
                                label: '어울리는 힘 · $statLabel',
                                icon: Icons.auto_awesome_outlined,
                                maxWidth: tagConstraints.maxWidth,
                                backgroundColor:
                                    scheme.secondaryContainer.withAlpha(120),
                              ),
                            if (outlook.isNotEmpty)
                              MongrooTag(
                                label: outlook,
                                icon: choice.safe
                                    ? Icons.shield_outlined
                                    : Icons.explore_outlined,
                                maxWidth: tagConstraints.maxWidth,
                                backgroundColor: outlook == '어려워 보여요'
                                    ? scheme.errorContainer.withAlpha(110)
                                    : scheme.tertiaryContainer.withAlpha(110),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
