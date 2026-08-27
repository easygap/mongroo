part of 'expedition_screen.dart';

/// 전투 중에는 지도·장소 설명·지휘 패널을 세로로 나열하지 않는다.
/// 스테이지 개편(stage-battle-v2.0)의 세로 3존 — 상단 정보 바, 대치 무대,
/// 순차 명령 카드 독 — 을 한 화면에 고정해 현재 행동과 다음 입력을 함께 읽는다.
class _ImmersiveExpeditionBattle extends ConsumerWidget {
  const _ImmersiveExpeditionBattle({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expeditionControllerProvider);
    final settings = ref.watch(expeditionBattleSettingsProvider);
    final event = expedition.currentEvent!;
    final battle = event.battle!;
    final node = expedition.nodes.firstWhere(
      (item) => item.code == expedition.run.currentNodeCode,
    );
    final actor = expedition.party
            .where(
              (member) =>
                  member.id ==
                  (state.actionCue?.actorId ?? state.selectedMemberId),
            )
            .firstOrNull ??
        expedition.party.firstOrNull;

    final Widget commandDock = kSequentialCommandDock
        ? ExpeditionSequentialCommandDock(
            expedition: expedition,
            event: event,
            state: state,
          )
        : ExpeditionBattlePanel(
            expedition: expedition,
            event: event,
            state: state,
            compact: true,
            onTurnStarted: () async {},
          );
    final topBar = ExpeditionBattleTopBar(
      battle: battle,
      locked: state.interactionLocked,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHud = constraints.maxWidth < 820;
        final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final mobileDockHeight =
            largeText || constraints.maxWidth < 340 ? 300.0 : 238.0;
        // 좁은 화면에서는 상단 바가 두 줄이 된다. 넓은 화면은 상단 바를 무대
        // 위에 겹치지 않고 Column으로 쌓으니 밀어낼 것이 없다.
        // 폭 계산은 아래 Stack의 여백과 같다 - 바깥 4+4, Positioned 6+6,
        // 패널 안쪽 4+4.
        final topHudInset = compactHud
            ? ExpeditionBattleTopBar.heightFor(constraints.maxWidth - 28) -
                ExpeditionBattleTopBar.lineHeight
            : 0.0;
        final stage = _ImmersiveBattleStage(
          node: node,
          expedition: expedition,
          actor: actor,
          cue: state.actionCue,
          paceScale: settings.pace.toDouble(),
          shortEffects: settings.shortEffects,
          audioMode: settings.audioMode,
          bottomHudInset: compactHud ? mobileDockHeight - 12 : 0,
          topHudInset: topHudInset,
          onCueCompleted:
              ref.read(expeditionControllerProvider.notifier).clearActionCue,
        );
        if (constraints.maxWidth >= 820) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    topBar,
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 7, child: stage),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 410,
                            child: SingleChildScrollView(child: commandDock),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              stage,
              Positioned(
                top: 4,
                left: 6,
                right: 6,
                child: MongrooPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  radius: 14,
                  color: scheme.surface.withAlpha(232),
                  shadowOffset: const Offset(0, 2),
                  child: topBar,
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 4,
                height: mobileDockHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SingleChildScrollView(
                    key: const ValueKey('immersive-combat-command-scroll'),
                    reverse: true,
                    child: commandDock,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ImmersiveBattleStage extends StatelessWidget {
  const _ImmersiveBattleStage({
    required this.node,
    required this.expedition,
    required this.actor,
    required this.cue,
    required this.paceScale,
    required this.shortEffects,
    required this.audioMode,
    required this.bottomHudInset,
    required this.topHudInset,
    required this.onCueCompleted,
  });

  final ExpeditionNode node;
  final ExpeditionSnapshot expedition;
  final ExpeditionMember? actor;
  final ExpeditionActionCue? cue;
  final double paceScale;
  final bool shortEffects;
  final ExpeditionAudioMode audioMode;
  final double bottomHudInset;
  final double topHudInset;
  final VoidCallback onCueCompleted;

  @override
  Widget build(BuildContext context) {
    final battle = expedition.currentEvent!.battle!;
    return MongrooPanel(
      key: const ValueKey('immersive-combat-stage'),
      padding: EdgeInsets.zero,
      radius: 18,
      borderColor: expeditionGuardianBattleScene.accent.withAlpha(105),
      child: ExpeditionSceneBackdrop(
        scene: expeditionGuardianBattleScene,
        regionCode: expedition.region.code,
        borderRadius: BorderRadius.circular(18),
        semanticLabel: '${node.sceneLabel} '
            '${battle.isTangle ? '엉킴' : '수호전'}. '
            '${battle.enemy.name} 장벽 ${battle.enemy.guard}/${battle.enemy.maxGuard}.',
        child: ExpeditionEncounterStage(
          encounter: expedition.currentEvent?.encounter,
          battle: battle,
          regionCode: expedition.region.code,
          actor: actor,
          party: expedition.party,
          cue: cue,
          paceScale: paceScale,
          shortEffects: shortEffects,
          audioMode: audioMode,
          bottomHudInset: bottomHudInset,
          topHudInset: topHudInset,
          onCueCompleted: onCueCompleted,
        ),
      ),
    );
  }
}
