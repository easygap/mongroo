part of 'expedition_screen.dart';

// 서버가 허용한 이동 경로를 읽기 쉬운 선택 카드로 변환한다.
class _DecisionColumn extends ConsumerWidget {
  const _DecisionColumn({
    required this.expedition,
    required this.onCombatTurnStarted,
  });

  final ExpeditionSnapshot expedition;
  final Future<void> Function() onCombatTurnStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expeditionControllerProvider);
    final event = expedition.currentEvent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.tutorialCoachStep == 3 ||
            state.tutorialCoachStep == 4 ||
            state.tutorialCoachStep == 7) ...[
          _TutorialCoachCard(
            step: state.tutorialCoachStep!,
            onDismiss: ref
                .read(expeditionControllerProvider.notifier)
                .dismissTutorialCoach,
          ),
          const SizedBox(height: 10),
        ],
        // 라운드 결과를 반영하는 32ms 동안도 패널을 유지한다.
        // 여기서 대체 위젯을 그리면 사용자가 켠 자동 지휘가
        // 라운드마다 초기화되고 화면도 짧게 깜빡인다.
        if (event?.battle != null)
          ExpeditionBattlePanel(
            expedition: expedition,
            event: event!,
            state: state,
            onTurnStarted: onCombatTurnStarted,
          )
        else if (state.settlingResult)
          _ResultSettlingPanel(expedition: expedition)
        else if (event == null)
          _TravelDecisionPanel(state: state, expedition: expedition)
        else
          _EventDecisionPanel(
            state: state,
            expedition: expedition,
            event: event,
          ),
      ],
    );
  }
}

/// 지도와 다음 선택지를 같은 프레임에 모두 조립하지 않도록 한 프레임만 가볍게 유지한다.
class _ResultSettlingPanel extends StatelessWidget {
  const _ResultSettlingPanel({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context) {
    final outcome = expedition.lastResolution?.outcome;
    return MongrooPanel(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(outcome ?? '다음 길을 정리하고 있어요.')),
        ],
      ),
    );
  }
}

class _TutorialCoachCard extends StatelessWidget {
  const _TutorialCoachCard({required this.step, required this.onDismiss});

  final int step;
  final VoidCallback? onDismiss;

  static const _titles = {
    1: '첫 탐험은 가볍게 연습해요',
    2: '연결된 방을 직접 골라요',
    3: '사건에 맞는 캐릭터를 골라요',
    4: '고유 스킬로 판정을 바꿔 보세요',
    5: '다른 길도 틀린 길은 아니에요',
    6: '목표를 확보했어요',
    7: '수호전은 직접 지휘해요',
  };
  static const _descriptions = {
    1: '현재 자라는 캐릭터와 안내자가 함께해요. 보상과 관계없이 언제든 다시 연습할 수 있어요.',
    2: '밝게 표시된 방을 누르면 길빛 비용과 방 종류를 확인하고 이동해요.',
    3: '능력치 미리보기를 비교한 뒤 행동할 캐릭터와 선택지를 고르세요.',
    4: '강조된 고유 스킬은 이번 사건의 판정이나 손실을 즉시 바꿔요. 그냥 해결해도 괜찮아요.',
    5: '목표 방향과 발견 방향 중 원하는 길을 골라요. 이 연습에서는 되돌아가도 불이익이 없어요.',
    6: '지금 귀환하면 발견과 기록이 저장돼요. 더 살펴보고 싶다면 다른 길을 먼저 둘러봐도 돼요.',
    7: '적의 약점과 다음 공격을 보고 대원 전원의 행동과 순서를 예약해요. 자동 지휘는 선택 기능이며 기본은 수동이에요.',
  };

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: '튜토리얼 $step단계. ${_titles[step]}. ${_descriptions[step]}',
        child: MongrooPanel(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderColor: Theme.of(context).colorScheme.primary.withAlpha(90),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    child: Text('$step'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_titles[step] ?? '탐험 조작 안내',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(_descriptions[step] ?? ''),
                      ],
                    ),
                  ),
                ],
              ),
              if (onDismiss != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onDismiss,
                    child: Text(step == 3 ? '다음: 스킬 보기' : '알겠어요'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _TravelDecisionPanel extends ConsumerWidget {
  const _TravelDecisionPanel({required this.state, required this.expedition});

  final ExpeditionUiState state;
  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = expedition.nodes.firstWhere(
      (node) => node.code == expedition.run.currentNodeCode,
    );
    final currentScene = expeditionSceneTheme(current.sceneKey);
    final destinations = expedition.nodes
        .where((node) => expedition.availableMoveCodes.contains(node.code))
        .toList(growable: false);
    final busy = state.interactionLocked;
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(currentScene.icon, size: 36, color: currentScene.accent),
          const SizedBox(height: 10),
          Text(current.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            expedition.run.objectiveSecured
                ? '기억 서랍을 확보했어요. 귀환 통로를 찾아 무사히 돌아가요.'
                : '지도에서 다음 장소를 직접 골라 주세요. 갈림길마다 다른 사건과 회복 지점이 있어요.',
            textAlign: TextAlign.center,
          ),
          if (destinations.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              '다음 구역 선택',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '입구와 물길, 계단이 이어지는 모습과 위험도를 보고 길을 골라요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            for (final destination in destinations)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DestinationChoiceCard(
                  node: destination,
                  busy: busy,
                  onTap: () async {
                    final moved = await ref
                        .read(expeditionControllerProvider.notifier)
                        .move(destination.code);
                    if (moved) HapticFeedback.selectionClick();
                  },
                ),
              ),
          ],
          const SizedBox(height: 20),
          Text('누가 길을 살펴볼까요?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _PartySelector(
            expedition: expedition,
            selectedMemberId:
                state.selectedMemberId ?? expedition.party.first.id,
            busy: busy,
          ),
          const SizedBox(height: 12),
          _MemberSkillActions(
            selected: expedition.party.firstWhere(
              (member) =>
                  member.id ==
                  (state.selectedMemberId ?? expedition.party.first.id),
            ),
            busy: busy,
          ),
          if (expedition.loot.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...expedition.loot.map(
              (loot) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(loot.name),
                subtitle: Text(
                  loot.disposition == 'candidate'
                      ? '귀환하면 수집함에 담겨요.'
                      : '이번 탐험의 발견 기록이에요.',
                ),
                trailing: Text('×${loot.quantity}'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (expedition.canExtract)
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () =>
                      ref.read(expeditionControllerProvider.notifier).extract(),
              icon: const Icon(Icons.home_outlined),
              label: const Text('목표를 안고 귀환'),
            ),
          if (expedition.canRetreat) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: busy ? null : () => _confirmRetreat(context, ref),
              icon: const Icon(Icons.keyboard_return_outlined),
              label: const Text('지금 안전하게 돌아가기'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRetreat(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지금 돌아갈까요?'),
        content: const Text('확보하지 못한 보상은 받지 않지만, 캐릭터와 남긴 선택 기록은 보존돼요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 탐험')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('안전 귀환'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(expeditionControllerProvider.notifier).retreat();
    }
  }
}

class _DestinationChoiceCard extends StatefulWidget {
  const _DestinationChoiceCard({
    required this.node,
    required this.busy,
    required this.onTap,
  });

  final ExpeditionNode node;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_DestinationChoiceCard> createState() => _DestinationChoiceCardState();
}

class _DestinationChoiceCardState extends State<_DestinationChoiceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scene = expeditionSceneTheme(widget.node.sceneKey);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: !widget.busy,
      label:
          '${widget.node.name}. ${widget.node.sceneLabel}. ${widget.node.depthLabel}. 위험도 ${widget.node.threatLevel}. 길빛 ${widget.node.cost} 사용.',
      child: AnimatedScale(
        scale: _pressed && !widget.busy ? .96 : 1,
        duration: reduceMotion ? Duration.zero : MongrooMotion.quick,
        curve: Curves.easeOut,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          shadowColor: Colors.black.withAlpha(80),
          elevation: _pressed ? 1 : 3,
          child: InkWell(
            onTap: widget.busy ? null : widget.onTap,
            onHighlightChanged: (pressed) {
              if (_pressed == pressed) return;
              setState(() => _pressed = pressed);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 520;
                final preview = _DestinationScenePreview(
                  node: widget.node,
                  scene: scene,
                );
                final details = _DestinationSceneDetails(
                  node: widget.node,
                  scene: scene,
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(aspectRatio: 16 / 7.2, child: preview),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                        child: details,
                      ),
                    ],
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      SizedBox(width: 144, height: 94, child: preview),
                      const SizedBox(width: 12),
                      Expanded(child: details),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationScenePreview extends StatelessWidget {
  const _DestinationScenePreview({required this.node, required this.scene});

  final ExpeditionNode node;
  final ExpeditionSceneTheme scene;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: expeditionSceneImageProvider(context, scene.assetPath),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    MongrooPalette.of(context).night.withAlpha(182),
                  ],
                  stops: const [.48, 1],
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 9,
              child: Text(
                node.sceneLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.onNight,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Positioned(
              right: 9,
              top: 9,
              child: _SceneHudTag(
                icon: Icons.shield_outlined,
                label: '위험 ${node.threatLevel}',
                color: scene.accent,
              ),
            ),
          ],
        ),
      );
}

class _DestinationSceneDetails extends StatelessWidget {
  const _DestinationSceneDetails({required this.node, required this.scene});

  final ExpeditionNode node;
  final ExpeditionSceneTheme scene;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MediaQuery.withNoTextScaling(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scene.accent.withAlpha(35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '길빛 -${node.cost}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${node.sceneLabel} · ${node.depthLabel}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scene.accent,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  node.sceneDescription,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded),
        ],
      );
}
