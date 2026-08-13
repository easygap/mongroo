import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/text/korean_particles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/expedition_models.dart';
import 'expedition_action_cue.dart';
import 'expedition_controller.dart';
import 'expedition_battle_dock.dart';
import 'expedition_battle_panel.dart';
import 'expedition_combat_overlay.dart';
import 'expedition_combat_audio.dart';
import 'expedition_scene.dart';
import 'moss_archive_scene.dart';

// 화면 전용 위젯은 외부 API로 노출하지 않되, 준비·지도·선택·결과의 책임별로
// 파일을 나눠 탐험 흐름을 수정할 때 영향을 받는 범위를 작게 유지한다.
part 'expedition_active_scene.dart';
part 'expedition_battle_scene.dart';
part 'expedition_decision.dart';
part 'expedition_event_decision.dart';
part 'expedition_map.dart';
part 'expedition_preparation.dart';
part 'expedition_stage_map.dart';
part 'expedition_stage_scene.dart';
part 'expedition_summary.dart';

class ExpeditionScreen extends ConsumerWidget {
  const ExpeditionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(
      expeditionControllerProvider.select((state) => state.error),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        ref.read(expeditionControllerProvider.notifier).clearError();
      },
    );
    ref.listen(
      expeditionControllerProvider.select((state) => state.unlockedSkillBooks),
      (previous, next) {
        if (next.isEmpty) return;
        final book = next.first;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            // 해금은 계정 단위라 어느 캐릭터로 보낼지 정할 수 없다. 대신 어디서
            // 장착하는지를 문장으로 알려 주고 이동은 사용자가 고르게 둔다.
            SnackBar(
              content: Text(book.notice),
              duration: const Duration(seconds: 6),
            ),
          );
        ref.read(expeditionControllerProvider.notifier).clearUnlockedSkillBooks();
      },
    );
    final shell = ref.watch(
      expeditionControllerProvider.select(
        (state) => (
          loading: state.loading,
          expedition: state.expedition,
          shellView: state.shellView,
        ),
      ),
    );
    final expedition = shell.expedition;
    final notifier = ref.read(expeditionControllerProvider.notifier);
    final title = expedition?.region.name ?? '함께 떠나는 모험';
    final immersiveCombat = expedition?.run.isActive == true &&
        expedition?.currentEvent?.battle != null;
    // 허브 안쪽 화면에서는 시스템 뒤로가기가 화면을 닫지 않고 한 단계만 돌아간다.
    final canPopShell =
        expedition != null || shell.shellView == ExpeditionShellView.hub;
    return PopScope(
      canPop: canPopShell,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) notifier.goBackInShell();
      },
      child: Scaffold(
        appBar: immersiveCombat
            ? null
            : AppBar(
                title: Text(title),
                actions: [
                  if (expedition?.run.mode == 'tutorial' &&
                      expedition?.run.isActive == true)
                    IconButton(
                      onPressed: notifier.replayTutorialHelp,
                      tooltip: '현재 조작 도움말 다시 보기',
                      icon: const Icon(Icons.help_outline_rounded),
                    ),
                ],
              ),
        body: SafeArea(
          top: immersiveCombat,
          child: shell.loading
              ? const Center(child: CircularProgressIndicator())
              : expedition != null
                  ? expedition.run.isActive
                      ? _ActiveExpedition(expedition: expedition)
                      : _ExpeditionSummary(expedition: expedition)
                  : switch (shell.shellView) {
                      ExpeditionShellView.hub => const _ExpeditionHub(),
                      ExpeditionShellView.stageMap =>
                        const _ExpeditionStageMapView(),
                      ExpeditionShellView.preparation =>
                        const _ExpeditionPreparation(),
                    },
        ),
      ),
    );
  }
}

class _ActiveExpedition extends ConsumerStatefulWidget {
  const _ActiveExpedition({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  ConsumerState<_ActiveExpedition> createState() => _ActiveExpeditionState();
}

class _ActiveExpeditionState extends ConsumerState<_ActiveExpedition> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _encounterStageKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showEncounterStage() async {
    final stageContext = _encounterStageKey.currentContext;
    if (!mounted || stageContext == null) return;
    await Scrollable.ensureVisible(
      stageContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: .08,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final expedition = widget.expedition;
    if (expedition.currentEvent?.battle != null) {
      return _ImmersiveExpeditionBattle(expedition: expedition);
    }
    if (expedition.run.stageNo != null) {
      // 스테이지 세션은 노드 지도를 걷지 않는다. 사건·쉼터·귀환을
      // 한 장면으로 보여 주는 필드 연출 화면을 쓴다.
      return _ImmersiveStageScene(expedition: expedition);
    }
    final width = MediaQuery.sizeOf(context).width;
    final content = [
      Expanded(
        flex: 6,
        child: _MapColumn(
          expedition: expedition,
          encounterStageKey: _encounterStageKey,
        ),
      ),
      if (width >= 820)
        const SizedBox(width: 16)
      else
        const SizedBox(height: 16),
      Expanded(
        flex: 4,
        child: _DecisionColumn(
          expedition: expedition,
          onCombatTurnStarted: _showEncounterStage,
        ),
      ),
    ];
    return RefreshIndicator(
      onRefresh: ref.read(expeditionControllerProvider.notifier).load,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            width >= 720 ? 24 : 12, 12, width >= 720 ? 24 : 12, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ActiveTutorialCoach(),
                  _ExpeditionStatusBar(expedition: expedition),
                  const SizedBox(height: 12),
                  width >= 820
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: content,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MapColumn(
                              expedition: expedition,
                              encounterStageKey: _encounterStageKey,
                            ),
                            const SizedBox(height: 16),
                            _DecisionColumn(
                              expedition: expedition,
                              onCombatTurnStarted: _showEncounterStage,
                            ),
                          ],
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

/// 도움말 단계만 구독해 버튼 로딩 상태가 바뀔 때 탐험 화면 전체가 재빌드되지 않게 한다.
class _ActiveTutorialCoach extends ConsumerWidget {
  const _ActiveTutorialCoach();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(
      expeditionControllerProvider.select(
        (state) => state.tutorialCoachStep,
      ),
    );
    if (step == null || step == 3 || step == 4) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TutorialCoachCard(
          step: step,
          onDismiss: ref
              .read(expeditionControllerProvider.notifier)
              .dismissTutorialCoach,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
