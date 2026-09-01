part of 'expedition_screen.dart';

/// 걸음과 걸음 사이 — 결과를 무대 위에 얹고 다음 걸음으로 바로 넘긴다.
///
/// 개편 설계서 3.6의 `advance` 장면이다: `획득 표식이 기록장으로 이동하고
/// 파티가 다음 랜드마크 방향으로 돌아섬 · 계속·경로·나가기의 짧은 행동만.`
/// 같은 절에 `스테이지 사이에는 불투명 로딩 카드나 흰 결과 페이지를 끼우지
/// 않는다`고도 적혀 있는데, 지금까지는 한 판이 끝나면 전체 화면 결과 페이지가
/// 무대를 덮고 그 다음엔 허브까지 다녀와야 했다.
///
/// 그래서 이 판은 화면을 갈아 끼우지 않는다. 방금 걸은 무대를 그대로 두고
/// 그 아래에 결과와 세 행동만 붙인다.

/// 마친 걸음 다음으로 곧장 이어 갈 수 있는가.
///
/// 후퇴는 제외한다 — 물러난 사람은 돌아가려던 것이지 이어 걸으려던 것이
/// 아니다. 지역의 마지막 걸음도 제외한다: 지역을 마친 순간에는 다음 지역이
/// 열렸다는 소식과 전환기가 있는 기존 결과 화면이 할 말이 더 많다.
bool stageAdvanceAvailable(ExpeditionUiState state) {
  final expedition = state.expedition;
  final stageMap = state.stageMap;
  if (expedition == null || stageMap == null) return false;
  final run = expedition.run;
  final stageNo = run.stageNo;
  if (run.isActive || run.status != 'completed') return false;
  if (stageNo == null || stageNo >= stageMap.total) return false;
  // 마친 판의 무대를 그대로 쓰므로, 서버가 지도를 접어 보낸 응답에서는
  // 그릴 것이 없다. 그때는 기존 결과 화면이 안전하다.
  return expedition.nodes.any((node) => node.code == run.currentNodeCode);
}

/// 방금 [justFinished]를 마쳤을 때 다음에 걸을 번호.
///
/// `마친 번호 + 1`로 두면 **재도전에서 틀린다** — 6까지 걸어 둔 사람이 3을
/// 다시 걸고 나면 다음은 4가 아니라 7이다. 반대로 캐시된 지도의
/// `nextStageNo`만 믿어도 틀린다: 그 지도는 이 걸음을 마치기 전에 받은 것이라
/// 방금 마친 번호를 그대로 가리킨다. 그래서 두 사실을 합쳐 **아직 안 걸은
/// 가장 앞 번호**를 직접 고른다.
int stageAdvanceNextNo(ExpeditionStageMap stageMap, int justFinished) {
  for (final stage in stageMap.stages) {
    if (stage.no == justFinished) continue;
    if (!stage.cleared) return stage.no;
  }
  // 이 걸음으로 지역을 다 걸었다. 그때는 이 판 자체가 서지 않는다.
  return justFinished;
}

/// 무대 아래에 붙는 결과와 세 행동.
class _StageAdvancePanel extends ConsumerWidget {
  const _StageAdvancePanel({required this.expedition});

  final ExpeditionSnapshot expedition;

  /// 이야기 컷이 딸린 걸음이면 그 컷과 번호.
  static (ExpeditionStageStory, int)? _storyOf(ExpeditionSnapshot expedition) {
    final cue = expedition.summary?['story_cue'];
    if (cue is! Map<String, dynamic>) return null;
    final stageNo = cue['stage_no'];
    if (stageNo is! num) return null;
    return (ExpeditionStageStory.fromJson(cue), stageNo.toInt());
  }

  /// 이 걸음이 남긴 성장·씨앗. 재도전이면 지급이 없어 비어 있다.
  static Map<String, dynamic>? _rewardOf(ExpeditionSnapshot expedition) {
    final reward = expedition.summary?['reward'];
    if (reward is! Map<String, dynamic>) return null;
    final events = reward['events'];
    if (events is! List || events.isEmpty) return null;
    final first = events.first;
    return first is Map<String, dynamic> ? first : null;
  }

  Future<void> _markStorySeen(WidgetRef ref) async {
    final story = _storyOf(expedition);
    if (story == null) return;
    await ref
        .read(expeditionControllerProvider.notifier)
        .markStageStorySeen(story.$2);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final advancing = ref.watch(
      expeditionControllerProvider.select((state) => state.advancing),
    );
    final locked = ref.watch(
      expeditionControllerProvider.select((state) => state.interactionLocked),
    );
    final notifier = ref.read(expeditionControllerProvider.notifier);
    final busy = advancing || locked;
    final story = _storyOf(expedition);
    final reward = _rewardOf(expedition);
    final stageNo = expedition.run.stageNo ?? 0;
    final stageMap = ref.watch(
      expeditionControllerProvider.select((state) => state.stageMap),
    );
    final nextNo =
        stageMap == null ? stageNo + 1 : stageAdvanceNextNo(stageMap, stageNo);
    final audioEnabled = ref.watch(
      expeditionBattleSettingsProvider.select(
        (settings) => settings.audioEnabled,
      ),
    );

    return Column(
      key: const ValueKey('stage-advance-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (story != null) ...[
          _StageStoryRevealCard(
            key: ValueKey('stage-story-${story.$1.code}'),
            story: story.$1,
            audioEnabled: audioEnabled,
          ),
          const SizedBox(height: 10),
        ],
        if (reward != null)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              MongrooTag(
                label: '성장 +${reward['exp_delta'] ?? 0}',
                icon: Icons.trending_up,
              ),
              MongrooTag(
                label: '씨앗 +${reward['seed_delta'] ?? 0}',
                icon: Icons.grass_outlined,
              ),
            ],
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('stage-advance-continue'),
          onPressed: busy
              ? null
              : () async {
                  HapticFeedback.selectionClick();
                  await _markStorySeen(ref);
                  await notifier.advanceToNextStage();
                },
          icon: advancing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward_rounded),
          label: Text(advancing ? '다음 걸음을 여는 중' : '계속 · $nextNo장으로'),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                key: const ValueKey('stage-advance-route'),
                onPressed: busy
                    ? null
                    : () => _openStageRouteOverlay(context, stageNo: stageNo),
                icon: const Icon(Icons.route_rounded, size: 19),
                label: const Text('경로'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                key: const ValueKey('stage-advance-leave'),
                onPressed: busy
                    ? null
                    : () async {
                        await _markStorySeen(ref);
                        await notifier.leaveSummary();
                      },
                icon: const Icon(Icons.home_outlined, size: 19),
                label: const Text('나가기'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
