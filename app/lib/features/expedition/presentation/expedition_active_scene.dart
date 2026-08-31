part of 'expedition_screen.dart';

// 진행 중인 위치 원화와 상태 HUD를 유지하는 장면 컨테이너.
class _ExpeditionStatusBar extends StatelessWidget {
  const _ExpeditionStatusBar({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '길빛 ${expedition.run.trailLight}, 결의 ${expedition.run.resolve}',
      child: MongrooPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
            final trailLight = _ResourceMeter(
              icon: Icons.light_mode_outlined,
              label: '길빛',
              value: expedition.run.trailLight,
              max: 12,
              color: scheme.tertiary,
            );
            final resolve = _ResourceMeter(
              icon: Icons.shield_outlined,
              label: '결의',
              value: expedition.run.resolve,
              max: 6,
              color: scheme.secondary,
            );
            if (largeText || constraints.maxWidth < 280) {
              return Column(
                children: [
                  trailLight,
                  const SizedBox(height: 12),
                  resolve,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: trailLight),
                const SizedBox(width: 16),
                Expanded(child: resolve),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResourceMeter extends StatelessWidget {
  const _ResourceMeter({
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text('$label $value/$max',
                  style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
              value: value / max, color: color, minHeight: 6),
        ],
      );
}

class _MapColumn extends StatelessWidget {
  const _MapColumn({
    required this.expedition,
  });

  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context) {
    final threadText = expedition.runThread['current_text'] as String?;
    final threadTitle = expedition.runThread['title'] as String?;
    final threadStage = switch (expedition.runThread['stage']) {
      'echo' => '이어진 단서',
      'payoff' => '이번 탐험의 결말',
      _ => '새로운 이야기',
    };
    final relationshipCue =
        expedition.memory['relationship_cue'] is Map<String, dynamic>
            ? expedition.memory['relationship_cue'] as Map<String, dynamic>
            : null;
    final relationshipCaption = relationshipCue?['caption'] as String?;
    final duetStory = expedition.memory['duet_story'] is Map<String, dynamic>
        ? expedition.memory['duet_story'] as Map<String, dynamic>
        : null;
    final duetNarration = duetStory?['narration'] as String? ?? '';
    final duetLines = (duetStory?['lines'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final current = expedition.nodes.firstWhere(
      (node) => node.code == expedition.run.currentNodeCode,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (threadText != null && threadText.isNotEmpty) ...[
          MongrooPanel(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            shadowOffset: Offset.zero,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_stories_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (threadTitle != null && threadTitle.isNotEmpty) ...[
                        Text(
                          '$threadStage · $threadTitle',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(threadText),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (relationshipCaption != null && relationshipCaption.isNotEmpty) ...[
          MongrooPanel(
            color: Theme.of(context).colorScheme.secondaryContainer,
            shadowOffset: Offset.zero,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.group_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relationshipCue?['title'] as String? ?? '탐험대 이야기',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(relationshipCaption),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (duetStory != null && duetLines.isNotEmpty) ...[
          Semantics(
            container: true,
            label: '야영지에서 이어진 두 탐험대원의 관계 이야기',
            child: MongrooPanel(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shadowOffset: Offset.zero,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.local_fire_department_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          duetStory['title'] as String? ?? '불빛 곁의 이야기',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (duetNarration.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            duetNarration,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                        const SizedBox(height: 6),
                        for (final line in duetLines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text.rich(
                              TextSpan(
                                style: Theme.of(context).textTheme.bodyMedium,
                                children: [
                                  TextSpan(
                                    text:
                                        '${line['speaker_name'] as String? ?? '탐험대원'}  ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: line['text'] as String? ?? '',
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        MongrooPanel(
          padding: EdgeInsets.zero,
          radius: 20,
          borderColor:
              expeditionSceneTheme(current.sceneKey).accent.withAlpha(90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => AspectRatio(
                  aspectRatio: constraints.maxWidth < 600 ? 1.55 : 16 / 9,
                  child: _ExpeditionMap(expedition: expedition),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 4,
                      height: 34,
                      decoration: BoxDecoration(
                        color: expeditionSceneTheme(current.sceneKey).accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${current.sceneLabel} · ${current.depthLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ThreatIndicator(level: current.threatLevel),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CurrentLocationScene(node: current, expedition: expedition),
        const SizedBox(height: 8),
        Text(
          expedition.run.phase == 'awaiting_event'
              ? '현장 상황을 해결하면 지형 너머의 다음 길이 열려요.'
              : '빛이 머무는 입구를 눌러 이동해요. 탐험대는 지형에 그려진 길을 따라갑니다.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _CurrentLocationScene extends ConsumerWidget {
  const _CurrentLocationScene({
    required this.node,
    required this.expedition,
  });

  final ExpeditionNode node;
  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interaction = ref.watch(
      expeditionControllerProvider.select(
        (state) => (
          selectedMemberId: state.selectedMemberId,
          actionCue: state.actionCue,
          pendingExpedition: state.pendingExpedition,
        ),
      ),
    );
    final guardianBattle = node.sceneKey == 'monster_den' &&
        (node.type == 'guardian' ||
            expedition.currentEvent?.encounter?.kind == 'guardian' ||
            interaction.actionCue?.isGuardianExchange == true);
    final scene = guardianBattle
        ? expeditionGuardianBattleScene
        : expeditionSceneTheme(node.sceneKey,
            regionCode: expedition.region.code);
    final nextSnapshot = interaction.pendingExpedition ?? expedition;
    final preloadScenes = nextSnapshot.nodes
        .where((item) => nextSnapshot.availableMoveCodes.contains(item.code))
        .map((item) => expeditionSceneTheme(
              item.sceneKey,
              regionCode: nextSnapshot.region.code,
            ))
        .toList(growable: false);
    final explored = expedition.nodes
        .where((item) => item.status == 'visited' || item.status == 'resolved')
        .length;
    final total = expedition.nodes.length;
    return MongrooPanel(
      padding: EdgeInsets.zero,
      radius: 20,
      borderColor: scene.accent.withAlpha(95),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => AspectRatio(
              aspectRatio: constraints.maxWidth < 600 ? 4 / 3 : 16 / 9,
              child: ExpeditionSceneBackdrop(
                scene: scene,
                regionCode: expedition.region.code,
                sceneKey: node.sceneKey,
                preloadScenes: preloadScenes,
                preloadDelay: interaction.actionCue == null
                    ? Duration.zero
                    : const Duration(milliseconds: 650),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                semanticLabel:
                    '${node.sceneLabel}. ${node.depthLabel}. ${node.sceneDescription}',
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              _SceneHudTag(
                                icon: scene.icon,
                                label: '현장 · ${node.sceneLabel}',
                                color: scene.accent,
                              ),
                              _SceneHudTag(
                                icon: Icons.explore_outlined,
                                label: '$explored/$total 탐색',
                                color: AppTheme.onNight,
                              ),
                            ],
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    ExpeditionEncounterStage(
                      encounter: expedition.currentEvent?.encounter,
                      battle: expedition.currentEvent?.battle,
                      regionCode: expedition.region.code,
                      actor: expedition.party
                              .where((member) =>
                                  member.id ==
                                  (interaction.actionCue?.actorId ??
                                      interaction.selectedMemberId))
                              .firstOrNull ??
                          expedition.party.firstOrNull,
                      party: expedition.party,
                      cue: interaction.actionCue,
                      // 연출이 끝난 뒤에만 다음 조작을 열어 레이어가 중간에
                      // 바뀌는 프레임을 만들지 않는다.
                      onCueCompleted: ref
                          .read(expeditionControllerProvider.notifier)
                          .clearActionCue,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final depth = Row(
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          size: 18,
                          color: scene.accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            node.depthLabel,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    );
                    if (MediaQuery.textScalerOf(context).scale(1) >= 1.5 ||
                        constraints.maxWidth < 300) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          depth,
                          const SizedBox(height: 7),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: _ThreatIndicator(level: node.threatLevel),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: depth),
                        const SizedBox(width: 8),
                        _ThreatIndicator(level: node.threatLevel),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  node.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  node.sceneDescription,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneHudTag extends StatelessWidget {
  const _SceneHudTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: MongrooPalette.of(context).night.withAlpha(215),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(75),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                textScaler: TextScaler.noScaling,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.onNight,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      );
}

class _ThreatIndicator extends StatelessWidget {
  const _ThreatIndicator({required this.level});

  final int level;

  static const _labels = ['안전', '경계', '위험', '수호자'];

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      0 => MongrooPalette.of(context).leaf,
      1 => const Color(0xFFC9913D),
      2 => const Color(0xFFC56845),
      _ => Theme.of(context).colorScheme.error,
    };
    return Semantics(
      label: '위험도 ${_labels[level]}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < 3; index++)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Container(
                width: 7,
                height: 14,
                decoration: BoxDecoration(
                  color: index < level ? color : color.withAlpha(42),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Text(
            _labels[level],
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
