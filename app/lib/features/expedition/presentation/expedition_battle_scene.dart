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

    final stage = _ImmersiveBattleStage(
      node: node,
      expedition: expedition,
      actor: actor,
      cue: state.actionCue,
      paceScale: settings.pace.toDouble(),
      shortEffects: settings.shortEffects,
      onCueCompleted:
          ref.read(expeditionControllerProvider.notifier).clearActionCue,
    );
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            children: [
              topBar,
              const SizedBox(height: 4),
              Expanded(flex: 56, child: stage),
              const SizedBox(height: 7),
              Flexible(
                flex: 44,
                child: SingleChildScrollView(
                  key: const ValueKey('immersive-combat-command-scroll'),
                  child: commandDock,
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
    required this.onCueCompleted,
  });

  final ExpeditionNode node;
  final ExpeditionSnapshot expedition;
  final ExpeditionMember? actor;
  final ExpeditionActionCue? cue;
  final double paceScale;
  final bool shortEffects;
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
        borderRadius: BorderRadius.circular(18),
        semanticLabel:
            '${node.sceneLabel} 수호전. ${battle.enemy.name} 장벽 ${battle.enemy.guard}/${battle.enemy.maxGuard}.',
        child: ExpeditionEncounterStage(
          encounter: expedition.currentEvent?.encounter,
          battle: battle,
          actor: actor,
          party: expedition.party,
          cue: cue,
          paceScale: paceScale,
          shortEffects: shortEffects,
          onCueCompleted: onCueCompleted,
        ),
      ),
    );
  }
}
