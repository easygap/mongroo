part of 'joint_guard_screen.dart';

/// 짐승마다 다른 꿈의 배경.
///
/// 넷이 같은 수호전 무대를 쓰면 `깊은 꿈`이 그냥 한 판 더가 된다. 짐승이
/// 무엇을 끌어안고 있는지가 배경에 그대로 보여야 한다 — 눈처럼 내리는 페이지,
/// 물결로 보이는 소리, 모래처럼 쌓이는 별빛, 물결치는 나이테.
const _dreamSceneAssets = <String, String>{
  'ledger_keeper': 'assets/adventure/joint-guard-dream-ledger-keeper-v1.webp',
  'echo_keeper': 'assets/adventure/joint-guard-dream-echo-keeper-v1.webp',
  'seed_keeper': 'assets/adventure/joint-guard-dream-seed-keeper-v1.webp',
  'record_keeper': 'assets/adventure/joint-guard-dream-record-keeper-v1.webp',
};

/// 각 꿈의 강조색. 그 배경에서 실제로 빛나는 색을 골랐다.
const _dreamAccents = <String, Color>{
  'ledger_keeper': Color(0xFFE8C77A),
  'echo_keeper': Color(0xFF72D6DD),
  'seed_keeper': Color(0xFFCBB6F2),
  'record_keeper': Color(0xFFE0A76A),
};

/// 짐승의 꿈 무대. 아직 원화가 없는 짐승은 공용 수호전 무대로 물러난다.
ExpeditionSceneTheme dreamSceneFor(String beastCode) => ExpeditionSceneTheme(
      assetPath: _dreamSceneAssets[beastCode] ??
          expeditionGuardianBattleScene.assetPath,
      icon: Icons.bedtime_rounded,
      accent: _dreamAccents[beastCode] ?? expeditionGuardianBattleScene.accent,
    );

/// 판 — 무대, 여섯 슬롯, 그리고 뒤에서 기다리는 셋.
///
/// 무대와 명령 슬롯은 스테이지 수호전과 **같은 위젯**을 쓴다. 사본을 만들면
/// 비용·잠금·상성 표시가 조용히 갈라진다. 이 화면이 더 들고 있는 것은 겹
/// 진행도, 예고 두 줄, 그리고 교대다.
class _JointGuardBattleView extends ConsumerWidget {
  const _JointGuardBattleView({required this.run});

  final JointGuardRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(jointGuardControllerProvider);
    final settings = ref.watch(expeditionBattleSettingsProvider);
    final notifier = ref.read(jointGuardControllerProvider.notifier);
    final state = run.state;

    if (!state.isActive) {
      return _JointGuardOutcome(state: state, onLeave: notifier.leave);
    }

    final members = [
      for (final entry in [...state.front, ...state.reserves]) entry.member,
    ];
    final actor = state.front
        .where((entry) => entry.memberId == ui.selectedMemberId)
        .firstOrNull
        ?.member;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        return Column(
          children: [
            _LayerBar(state: state),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 6 : 10),
                child: MongrooPanel(
                  padding: EdgeInsets.zero,
                  radius: 18,
                  // 무대는 자기 자리를 `Positioned`로 잡는다. 배경이 Stack을
                  // 열어 주지 않으면 부모 종류가 안 맞아 화면 전체가 무너진다.
                  // 지역 보정색은 넘기지 않는다. 이 배경은 그 꿈 전용으로
                  // 그린 원화라, 지역 색을 한 번 더 얹으면 두 번 물든다.
                  child: ExpeditionSceneBackdrop(
                    scene: dreamSceneFor(state.beast.code),
                    borderRadius: BorderRadius.circular(18),
                    semanticLabel: '${state.beast.name}의 꿈. '
                        '${state.layer.name}. '
                        '장벽 ${state.battle.enemy.guard}/'
                        '${state.battle.enemy.maxGuard}.',
                    child: ExpeditionEncounterStage(
                      encounter: null,
                      battle: state.battle,
                      regionCode: state.beast.regionCode,
                      actor: actor,
                      party: members,
                      cue: ui.actionCue,
                      paceScale: settings.pace.toDouble(),
                      shortEffects: settings.shortEffects,
                      audioMode: settings.audioMode,
                      onCueCompleted: notifier.clearActionCue,
                    ),
                  ),
                ),
              ),
            ),
            _ReserveRow(state: state, locked: ui.interactionLocked),
            // 높이를 고정하지 않는다. 예고가 두 줄이 되면 독이 그만큼
            // 길어지는데, 숫자를 박아 두면 그때마다 아래가 잘린다. 무대가
            // 남는 자리를 가져가고 독은 제 키대로 선다.
            ExpeditionSequentialCommandDock(
              battle: state.battle,
              members: members,
              locked: ui.interactionLocked,
              fingerprintSeed: '${run.runId}:${run.revision}',
              selectedMemberId: ui.selectedMemberId,
              onSelectMember: notifier.selectMember,
              onSubmit: notifier.submitCommand,
            ),
          ],
        );
      },
    );
  }
}

/// 겹 진행도와 이번 겹의 상성. 색만으로 구분하지 않고 이름으로 읽어 준다.
class _LayerBar extends StatelessWidget {
  const _LayerBar({required this.state});

  final JointGuardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layer = state.layer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MongrooTag(
                key: const ValueKey('joint-guard-layer'),
                label: '${layer.name} · ${layer.progressLabel}',
                icon: Icons.bedtime_rounded,
              ),
              MongrooTag(
                label: '잘 통해요 ${layer.weakKelLabel}',
                icon: Icons.trending_up_rounded,
              ),
              MongrooTag(
                label: '잘 안 통해요 ${layer.resistKelLabel}',
                icon: Icons.trending_down_rounded,
              ),
            ],
          ),
          if (layer.warning case final JointGuardMomentWarning warning) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: MongrooPanel(
                key: const ValueKey('joint-guard-moment-warning'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${warning.name} · ${warning.inRounds}라운드 뒤',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(warning.text, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    // 예고와 우회를 반드시 함께 읽어 준다. 역할이 없어도 넘을
                    // 수 있다는 것이 이 콘텐츠의 약속이다.
                    Text(
                      warning.bypass,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 뒤에서 기다리는 셋. 누르면 지금 무대에 선 대원과 바꾼다.
class _ReserveRow extends ConsumerWidget {
  const _ReserveRow({required this.state, required this.locked});

  final JointGuardState state;
  final bool locked;

  Future<void> _swap(BuildContext context, WidgetRef ref, int inMemberId) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('누구와 바꿀까요?'),
            ),
            for (final entry in state.front)
              ListTile(
                key: ValueKey('joint-guard-swap-out-${entry.memberId}'),
                title: Text(entry.name),
                subtitle: Text('체력 ${entry.hp}/${entry.maxHp}'),
                onTap: () => Navigator.of(context).pop(entry.memberId),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await ref
        .read(jointGuardControllerProvider.notifier)
        .swap(outMemberId: choice, inMemberId: inMemberId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (state.reserves.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '기다리는 대원',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              Text(
                state.swapsLeft > 0
                    ? '이번 라운드 교대 ${state.swapsLeft}번'
                    : '이번 라운드 교대를 썼어요',
                key: const ValueKey('joint-guard-swaps-left'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in state.reserves)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ReserveCard(
                      entry: entry,
                      enabled:
                          !locked && state.canSwap && entry.canSwapIn,
                      onTap: () => _swap(context, ref, entry.memberId),
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

class _ReserveCard extends StatelessWidget {
  const _ReserveCard({
    required this.entry,
    required this.enabled,
    required this.onTap,
  });

  final JointGuardMember entry;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = entry.isDown
        ? '${entry.name}, 지쳐서 물러났어요'
        : '${entry.name}, 체력 ${entry.hp} / ${entry.maxHp}. 눌러서 교대해요';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 128,
          child: OutlinedButton(
            key: ValueKey('joint-guard-reserve-${entry.memberId}'),
            onPressed: enabled ? onTap : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 56),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: entry.hpRatio,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.isDown ? '지쳐서 물러남' : '${entry.hp}/${entry.maxHp}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 판이 끝난 자리. 깨어났거나, 꿈이 다시 깊어졌거나.
class _JointGuardOutcome extends StatelessWidget {
  const _JointGuardOutcome({required this.state, required this.onLeave});

  final JointGuardState state;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final awake = state.isAwake;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      children: [
        Icon(
          awake ? Icons.wb_twilight_rounded : Icons.bedtime_outlined,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          awake ? '${state.beast.name}가 깨어났어요' : '꿈이 다시 깊어졌어요',
          key: const ValueKey('joint-guard-outcome'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          state.latestLine,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Text(
          // 반복 보상이 없다는 것을 숨기지 않는다. 다시 오는 이유는 재화가
          // 아니라 연출과 숙련이라고 처음부터 말해 둔다.
          awake
              ? '씨앗과 성장은 오가지 않아요. 남는 것은 이 장면과 다음에 더 나아질 손끝이에요.'
              : '아무도 다치지 않았어요. 다음에 다시 와 주세요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('joint-guard-leave'),
          onPressed: onLeave,
          child: const Text('돌아가기'),
        ),
      ],
    );
  }
}
