import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/bundled_assets.dart';
import '../../../core/text/korean_particles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/expedition_models.dart';
import 'expedition_action_cue.dart';
import 'expedition_controller.dart';
import 'expedition_battle_dock.dart';
import 'expedition_combat_overlay.dart';
import 'expedition_combat_audio.dart';
import 'expedition_discovery_audio.dart';
import 'expedition_walk_path.dart';
import 'expedition_free_walk.dart';
import 'expedition_lighting.dart';
import 'expedition_walk_area.dart';
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
part 'expedition_progress_rail.dart';
part 'expedition_stage_advance.dart';
part 'expedition_stage_map.dart';
part 'expedition_stage_scene.dart';
part 'expedition_tile_world.dart';
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
        ref
            .read(expeditionControllerProvider.notifier)
            .clearUnlockedSkillBooks();
      },
    );
    final shell = ref.watch(
      expeditionControllerProvider.select(
        (state) => (
          loading: state.loading,
          expedition: state.expedition,
          shellView: state.shellView,
          advancing: stageAdvanceAvailable(state),
        ),
      ),
    );
    final expedition = shell.expedition;
    final notifier = ref.read(expeditionControllerProvider.notifier);
    final title = expedition?.region.name ?? '함께 떠나는 탐험';
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
                // 지도·편성 화면은 본문 머리에 `허브로` 버튼을 이미 들고 있다.
                // 앱바 화살표까지 두면 같은 자리에 똑같은 화살표가 두 개
                // 겹쳐 보이고, 둘 다 같은 곳으로 간다.
                automaticallyImplyLeading: expedition != null ||
                    shell.shellView == ExpeditionShellView.hub,
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
                  // 마친 걸음도 무대를 그대로 쓴다. 결과 페이지로 갈아 끼우면
                  // 설계서 3.6이 금지한 `흰 결과 페이지`가 되고 다음 걸음까지
                  // 장면도 음악도 한 번 끊긴다. 지역을 다 걸었을 때만 다음
                  // 지역 안내가 있는 기존 결과 화면으로 간다.
                  ? expedition.run.isActive || shell.advancing
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

class _ActiveExpeditionState extends ConsumerState<_ActiveExpedition>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ExpeditionDiscoveryAudio _discoveries = ExpeditionDiscoveryAudio();

  /// 지역 음악은 이 화면이 든다.
  ///
  /// 예전에는 전장 위젯이 들고 있었다. 그래서 전투가 끝나 전장이 사라질 때마다
  /// 곡이 함께 죽었고, 걸음이 넘어갈 때는 물론이고 **한 걸음 안에서도**
  /// 전투가 끝나면 음악이 끊겼다. 설계서 3.6은 `approach → encounter →
  /// combat → release`가 같은 지역 loop의 재생 위치를 유지하고 stem만
  /// 교차하라고 적어 뒀다.
  ///
  /// 이 State는 걸음이 넘어가도 살아남는다 — 마친 판을 비우지 않고 새 판
  /// 스냅숏으로 갈아 끼우기 때문이다([ExpeditionController.advanceToNextStage]).
  /// 그래서 재생 세션의 경계가 설계서가 말한 대로 `지역 pack 교체`와
  /// 탐험 화면을 벗어나는 순간뿐이 된다.
  ///
  /// 효과음은 여기서 들지 않는다. 접촉·예고·풀려남은 연출 시각과 맞물려야
  /// 해서 전장이 그대로 들고 있는 편이 맞다.
  final ExpeditionCombatAudio _music =
      ExpeditionCombatAudio(musicEnabled: false, sfxEnabled: false);

  ExpeditionAudioMode? _appliedAudioMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_syncRegionMusic());
  }

  /// 앱이 뒤로 가면 곡을 줄여 멈추고 돌아오면 같은 위치에서 되살린다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_music.handleAppResumed());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_music.handleAppPaused());
    }
  }

  /// 지금 스냅숏이 요구하는 stem으로 갈아 끼운다.
  ///
  /// 지역이 같으면 [ExpeditionCombatAudio.playMusic]이 재생 위치를 물려주므로
  /// 걸음이 넘어가도 곡은 이어진다. 지역이 바뀌면 곡 자체가 달라 처음부터
  /// 시작하는데, 그것이 설계서가 둔 유일한 재생 세션 경계다.
  Future<void> _syncRegionMusic() async {
    final mode = ref.read(expeditionBattleSettingsProvider).audioMode;
    if (mode != _appliedAudioMode) {
      _appliedAudioMode = mode;
      // 채널을 먼저 켜고 나서 곡을 건다. 순서가 바뀌면 아직 꺼져 있는 채널이
      // 재생 요청을 그대로 버린다.
      await _music.setChannels(
        music: mode == ExpeditionAudioMode.all,
        sfx: false,
      );
      if (!mounted) return;
    }
    if (mode != ExpeditionAudioMode.all) return;
    final expedition = widget.expedition;
    final battle = expedition.currentEvent?.battle;
    final encounter = expedition.currentEvent?.encounter;
    final musicState = battle?.enemyKind == 'guardian' ||
            encounter?.kind == 'guardian'
        ? ExpeditionMusicState.guardian
        : battle != null
            ? ExpeditionMusicState.combat
            : ExpeditionMusicState.base;
    await _music.playMusic(musicState, regionCode: expedition.region.code);
  }

  @override
  void didUpdateWidget(covariant _ActiveExpedition oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_syncRegionMusic());
    // 지도 걷기·스테이지 필드·전투가 각자 다른 화면을 그리지만 스냅숏은 전부
    // 여기를 지난다. 발견을 알아채는 자리를 하나만 두려고 build가 아니라
    // 여기에서 본다 - build는 스크롤에도 다시 돌아 같은 소식을 되풀이한다.
    final cue = expeditionDiscoveryCueFor(oldWidget.expedition, widget.expedition);
    if (cue == null) return;
    unawaited(
      _discoveries.play(
        cue,
        enabled: ref.read(expeditionBattleSettingsProvider).sfxEnabled,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    unawaited(_discoveries.dispose());
    unawaited(_music.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 전장 설정 시트에서 음악을 껐다 켜면 그 시트만 다시 그려진다. 부모인
    // 여기는 didUpdateWidget이 돌지 않으므로, 설정을 직접 듣지 않으면 다음
    // 스냅숏이 올 때까지 곡이 그대로 흐르거나 그대로 멈춰 있다.
    ref.listen(
      expeditionBattleSettingsProvider.select((settings) => settings.audioMode),
      (previous, next) => unawaited(_syncRegionMusic()),
    );
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
        child: _MapColumn(expedition: expedition),
      ),
      if (width >= 820)
        const SizedBox(width: 16)
      else
        const SizedBox(height: 16),
      Expanded(
        flex: 4,
        child: _DecisionColumn(expedition: expedition),
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
                            _MapColumn(expedition: expedition),
                            const SizedBox(height: 16),
                            _DecisionColumn(expedition: expedition),
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
