import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../home/presentation/home_controller.dart';
import '../data/expedition_repository.dart';
import '../domain/expedition_models.dart';
import 'expedition_action_cue.dart';

const _unset = Object();

/// 진행 중인 탐험이 없을 때 보여 줄 화면.
///
/// 개편 설계서 5.1·5.2의 `허브 → 스테이지 지도 → 편성` 순서를 그대로 따른다.
enum ExpeditionShellView { hub, stageMap, preparation }

class ExpeditionUiState {
  const ExpeditionUiState({
    this.loading = true,
    this.catalog,
    this.roster = const [],
    this.expedition,
    this.stageMap,
    this.shellView = ExpeditionShellView.hub,
    this.selectedStageNo,
    this.selectedPlantIds = const {},
    this.selectedMemberId,
    this.busyAction,
    this.error,
    this.tutorialCoachStep,
    this.actionCue,
    this.pendingExpedition,
    this.settlingResult = false,
    this.unlockedSkillBooks = const [],
  });

  final bool loading;
  final ExpeditionCatalog? catalog;
  final List<ExpeditionRosterItem> roster;
  final ExpeditionSnapshot? expedition;
  final ExpeditionStageMap? stageMap;
  final ExpeditionShellView shellView;

  /// 지도에서 고른 스테이지. 편성 화면과 출발 요청이 함께 읽는다.
  final int? selectedStageNo;
  final Set<int> selectedPlantIds;
  final int? selectedMemberId;
  final String? busyAction;
  final String? error;
  final int? tutorialCoachStep;
  final ExpeditionActionCue? actionCue;
  final ExpeditionSnapshot? pendingExpedition;
  final bool settlingResult;

  /// 방금 조건을 채워 열린 기록서. 한 번 알린 뒤 비운다.
  final List<ExpeditionUnlockedSkillBook> unlockedSkillBooks;

  ExpeditionStage? get selectedStage => stageMap?.stageOf(selectedStageNo);

  bool get interactionLocked =>
      busyAction != null ||
      actionCue != null ||
      pendingExpedition != null ||
      settlingResult;

  ExpeditionUiState copyWith({
    bool? loading,
    Object? catalog = _unset,
    List<ExpeditionRosterItem>? roster,
    Object? expedition = _unset,
    Object? stageMap = _unset,
    ExpeditionShellView? shellView,
    Object? selectedStageNo = _unset,
    Set<int>? selectedPlantIds,
    Object? selectedMemberId = _unset,
    Object? busyAction = _unset,
    Object? error = _unset,
    Object? tutorialCoachStep = _unset,
    Object? actionCue = _unset,
    Object? pendingExpedition = _unset,
    bool? settlingResult,
    List<ExpeditionUnlockedSkillBook>? unlockedSkillBooks,
  }) =>
      ExpeditionUiState(
        loading: loading ?? this.loading,
        catalog:
            catalog == _unset ? this.catalog : catalog as ExpeditionCatalog?,
        roster: roster ?? this.roster,
        expedition: expedition == _unset
            ? this.expedition
            : expedition as ExpeditionSnapshot?,
        stageMap: stageMap == _unset
            ? this.stageMap
            : stageMap as ExpeditionStageMap?,
        shellView: shellView ?? this.shellView,
        selectedStageNo: selectedStageNo == _unset
            ? this.selectedStageNo
            : selectedStageNo as int?,
        selectedPlantIds: selectedPlantIds ?? this.selectedPlantIds,
        selectedMemberId: selectedMemberId == _unset
            ? this.selectedMemberId
            : selectedMemberId as int?,
        busyAction:
            busyAction == _unset ? this.busyAction : busyAction as String?,
        error: error == _unset ? this.error : error as String?,
        tutorialCoachStep: tutorialCoachStep == _unset
            ? this.tutorialCoachStep
            : tutorialCoachStep as int?,
        actionCue: actionCue == _unset
            ? this.actionCue
            : actionCue as ExpeditionActionCue?,
        pendingExpedition: pendingExpedition == _unset
            ? this.pendingExpedition
            : pendingExpedition as ExpeditionSnapshot?,
        settlingResult: settlingResult ?? this.settlingResult,
        unlockedSkillBooks: unlockedSkillBooks ?? this.unlockedSkillBooks,
      );
}

class ExpeditionController extends Notifier<ExpeditionUiState> {
  static const _uuid = Uuid();
  final Map<String, String> _actionKeys = {};
  final Set<int> _dismissedTutorialSteps = {};
  final List<ExpeditionActionCue> _queuedCues = [];
  int _cueSequence = 0;
  Timer? _settlingTimer;

  @override
  ExpeditionUiState build() {
    ref.onDispose(() => _settlingTimer?.cancel());
    Future.microtask(load);
    return const ExpeditionUiState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final repository = ref.read(expeditionRepositoryProvider);
      final results = await Future.wait([
        repository.getCatalog(),
        repository.getRoster(),
        repository.getActive(),
        repository.getStageMap(),
      ]);
      final catalog = results[0] as ExpeditionCatalog;
      final roster = results[1] as List<ExpeditionRosterItem>;
      final expedition = results[2] as ExpeditionSnapshot?;
      final stageMap = results[3] as ExpeditionStageMap;
      final selected = state.selectedPlantIds
          .where(
              (id) => roster.any((item) => item.plantId == id && item.eligible))
          .toSet();
      if (selected.isEmpty) {
        final first = roster.where((item) => item.eligible).firstOrNull;
        if (first != null) selected.add(first.plantId);
      }
      state = state.copyWith(
        loading: false,
        catalog: catalog,
        roster: roster,
        expedition: expedition,
        stageMap: stageMap,
        // 지도를 새로 받으면 허브부터 다시 보여 준다. 진행 중 화면이 남아
        // 이전 스테이지 선택으로 출발하는 일을 막는다.
        shellView: ExpeditionShellView.hub,
        selectedStageNo: null,
        selectedPlantIds: selected,
        selectedMemberId: _defaultMember(expedition),
        tutorialCoachStep: _deriveTutorialStep(expedition),
        actionCue: null,
        pendingExpedition: null,
        settlingResult: false,
      );
      _queuedCues.clear();
    } on ApiException catch (error) {
      state = state.copyWith(loading: false, error: error.message);
    }
  }

  int? _defaultMember(ExpeditionSnapshot? expedition) {
    if (expedition == null || expedition.party.isEmpty) return null;
    final spotlight = expedition.currentEvent?.spotlightMemberId;
    if (spotlight != null &&
        expedition.party.any((item) => item.id == spotlight)) {
      return spotlight;
    }
    return expedition.party.first.id;
  }

  int? _deriveTutorialStep(
    ExpeditionSnapshot? expedition, {
    bool respectDismissed = true,
  }) {
    if (expedition == null ||
        !expedition.run.isActive ||
        expedition.run.mode != 'tutorial') {
      return null;
    }
    bool visible(int step) =>
        !respectDismissed || !_dismissedTutorialSteps.contains(step);
    if (expedition.run.objectiveSecured) return visible(6) ? 6 : null;
    if (expedition.currentEvent?.battle?.isActive == true) {
      return visible(7) ? 7 : null;
    }
    final outcomes = expedition.memory['outcomes'];
    final outcomeCount = outcomes is List ? outcomes.length : 0;
    if (outcomeCount > 0) return visible(5) ? 5 : null;
    if (expedition.run.phase == 'awaiting_event') {
      if (visible(3)) return 3;
      final actorId = state.selectedMemberId ?? _defaultMember(expedition);
      final actor = expedition.party
          .where((member) => member.id == actorId && !member.isGuide)
          .firstOrNull;
      if (actor != null && !actor.signatureUsed && visible(4)) return 4;
      return null;
    }
    if (expedition.run.currentNodeCode == 'entrance') {
      return visible(2) ? 2 : null;
    }
    return visible(5) ? 5 : null;
  }

  void dismissTutorialCoach() {
    final step = state.tutorialCoachStep;
    if (step == null) return;
    _dismissedTutorialSteps.add(step);
    state = state.copyWith(
      tutorialCoachStep: _deriveTutorialStep(state.expedition),
    );
  }

  void replayTutorialHelp() {
    final expedition = state.expedition;
    final step = _deriveTutorialStep(expedition, respectDismissed: false);
    if (step == null) return;
    _dismissedTutorialSteps.remove(step);
    state = state.copyWith(tutorialCoachStep: step);
  }

  void togglePlant(int plantId) {
    if (state.busyAction != null) return;
    final selected = {...state.selectedPlantIds};
    if (!selected.remove(plantId)) {
      if (selected.length >= 3) {
        state = state.copyWith(error: '탐험대는 최대 3명까지 편성할 수 있어요.');
        return;
      }
      selected.add(plantId);
    }
    state = state.copyWith(selectedPlantIds: selected, error: null);
  }

  void selectMember(int memberId) {
    state = state.copyWith(selectedMemberId: memberId);
  }

  /// 허브에서 스테이지 지도를 연다.
  void openStageMap() =>
      state = state.copyWith(shellView: ExpeditionShellView.stageMap);

  /// 지도에서 스테이지를 고르고 편성 화면으로 넘어간다.
  /// 잠긴 스테이지는 사유만 알리고 이동하지 않는다.
  void openStagePreparation(int stageNo) {
    final stage = state.stageMap?.stageOf(stageNo);
    if (stage == null) return;
    if (!stage.unlocked) {
      state = state.copyWith(error: stage.lockReason);
      return;
    }
    state = state.copyWith(
      shellView: ExpeditionShellView.preparation,
      selectedStageNo: stageNo,
      error: null,
    );
  }

  /// 한 단계 뒤로. 편성 → 지도 → 허브 순서로 돌아간다.
  bool goBackInShell() {
    switch (state.shellView) {
      case ExpeditionShellView.preparation:
        state = state.copyWith(
          shellView: ExpeditionShellView.stageMap,
          selectedStageNo: null,
        );
        return true;
      case ExpeditionShellView.stageMap:
        state = state.copyWith(shellView: ExpeditionShellView.hub);
        return true;
      case ExpeditionShellView.hub:
        return false;
    }
  }

  /// 스테이지 이야기 컷을 읽었다고 서버에 남긴다. 실패해도 진행을 막지 않는다.
  Future<void> markStageStorySeen(int stageNo) async {
    final stageMap = state.stageMap;
    if (stageMap == null) return;
    try {
      await ref.read(expeditionRepositoryProvider).markStageStorySeen(
            regionCode: stageMap.region.code,
            stageNo: stageNo,
          );
      state = state.copyWith(
        stageMap: await ref.read(expeditionRepositoryProvider).getStageMap(),
      );
    } on ApiException {
      // 이야기 확인 표시는 보조 정보다. 실패를 사용자에게 알리지 않는다.
    }
  }

  Future<bool> start(String mode) async {
    final catalog = state.catalog;
    if (state.selectedPlantIds.isEmpty || catalog == null) {
      state = state.copyWith(error: '함께 탐험할 캐릭터를 한 명 이상 골라 주세요.');
      return false;
    }
    if (mode == 'heart_resonance' && !catalog.heartResonanceAvailable) {
      state = state.copyWith(error: '오늘 마음 일기를 먼저 기록해 주세요.');
      return false;
    }
    final plantIds = mode == 'tutorial'
        ? [
            state.roster
                .firstWhere(
                  (item) => item.isActive && item.eligible,
                  orElse: () => state.roster.firstWhere(
                    (item) => state.selectedPlantIds.contains(item.plantId),
                  ),
                )
                .plantId,
          ]
        : state.selectedPlantIds.toList(growable: false);
    final stageNo = mode == 'tutorial' ? null : state.selectedStageNo;
    final action = 'start:$mode:${plantIds.join(',')}:${stageNo ?? '-'}';
    return _perform(
      action,
      (key) => ref.read(expeditionRepositoryProvider).start(
            mode: mode,
            plantIds: plantIds,
            guideCount: mode == 'tutorial' ? 1 : 0,
            idempotencyKey: key,
            stageNo: stageNo,
          ),
    );
  }

  Future<bool> move(String nodeCode) {
    final expedition = state.expedition;
    if (expedition == null) return Future.value(false);
    return _perform(
      'move:${expedition.run.revision}:$nodeCode',
      (key) => ref.read(expeditionRepositoryProvider).move(
            runId: expedition.run.id,
            nodeCode: nodeCode,
            expectedRevision: expedition.run.revision,
            clientActionId: key,
          ),
    );
  }

  Future<bool> choose(String choiceCode) {
    final expedition = state.expedition;
    final memberId = state.selectedMemberId;
    if (expedition == null || memberId == null) return Future.value(false);
    return _perform(
      'choice:${expedition.run.revision}:$choiceCode:$memberId',
      (key) => ref.read(expeditionRepositoryProvider).choose(
            runId: expedition.run.id,
            choiceCode: choiceCode,
            memberId: memberId,
            expectedRevision: expedition.run.revision,
            clientActionId: key,
          ),
    );
  }

  Future<bool> useSkill(String skillType, {String? modeCode}) {
    final expedition = state.expedition;
    final memberId = state.selectedMemberId;
    if (expedition == null || memberId == null) return Future.value(false);
    return _perform(
      'skill:${expedition.run.revision}:$skillType:$memberId:${modeCode ?? 'default'}',
      (key) => ref.read(expeditionRepositoryProvider).useSkill(
            runId: expedition.run.id,
            memberId: memberId,
            skillType: skillType,
            modeCode: modeCode,
            expectedRevision: expedition.run.revision,
            clientActionId: key,
          ),
    );
  }

  Future<bool> resolveCombatTurn(List<ExpeditionCombatCommand> commands) {
    final expedition = state.expedition;
    if (expedition == null || commands.isEmpty) return Future.value(false);
    final signature = commands
        .map((command) => '${command.memberId}-${command.action}')
        .join(',');
    return _perform(
      'combat:${expedition.run.revision}:$signature',
      (key) => ref.read(expeditionRepositoryProvider).resolveCombatTurn(
            runId: expedition.run.id,
            commands: commands,
            expectedRevision: expedition.run.revision,
            clientActionId: key,
          ),
    );
  }

  /// 순차 명령 — 대원 한 명의 행동을 즉시 서버 판정으로 보낸다.
  ///
  /// 응답의 `last_combat_exchange`에는 이번 행동으로 새로 일어난 이벤트만
  /// 담기므로 기존 큐 연출 파이프라인이 그대로 그 변화를 재생한다.
  Future<bool> resolveCombatAction(ExpeditionCombatCommand command) {
    final expedition = state.expedition;
    if (expedition == null) return Future.value(false);
    return _perform(
      'combat:${expedition.run.revision}:seq:${command.memberId}-${command.action}',
      (key) => ref.read(expeditionRepositoryProvider).resolveCombatTurn(
            runId: expedition.run.id,
            commands: [command],
            partial: true,
            expectedRevision: expedition.run.revision,
            clientActionId: key,
          ),
    );
  }

  Future<bool> extract() {
    final expedition = state.expedition;
    if (expedition == null) return Future.value(false);
    return _perform(
      'extract:${expedition.run.revision}',
      (key) => ref.read(expeditionRepositoryProvider).extract(
            runId: expedition.run.id,
            expectedRevision: expedition.run.revision,
            clientActionId: key,
          ),
    );
  }

  Future<bool> retreat() {
    final expedition = state.expedition;
    if (expedition == null) return Future.value(false);
    return _perform(
      'retreat:${expedition.run.revision}',
      (key) => ref.read(expeditionRepositoryProvider).retreat(
            runId: expedition.run.id,
            expectedRevision: expedition.run.revision,
            clientActionId: key,
          ),
    );
  }

  Future<bool> _perform(
    String action,
    Future<ExpeditionSnapshot> Function(String key) request,
  ) async {
    if (state.interactionLocked) {
      return false;
    }
    final previousExpedition = state.expedition;
    final previousMemberId = state.selectedMemberId;
    state = state.copyWith(busyAction: action, error: null);
    try {
      final key = _actionKeys.putIfAbsent(action, _uuid.v4);
      final expedition = await request(key);
      _actionKeys.remove(action);
      final balance = expedition.rewardedSeedBalance;
      if (balance != null) {
        ref.read(authControllerProvider.notifier).updateSeedBalance(balance);
      }
      ref.invalidate(homeControllerProvider);
      // 조건을 채워 열린 기록서는 연출과 무관하게 즉시 알린다.
      if (expedition.unlockedSkillBooks.isNotEmpty) {
        state = state.copyWith(
          unlockedSkillBooks: expedition.unlockedSkillBooks,
        );
      }
      final actionCues = _actionCuesFor(
        action,
        previousExpedition: previousExpedition,
        previousMemberId: previousMemberId,
        result: expedition,
      );
      if (actionCues.isEmpty) {
        _queuedCues.clear();
        state = state.copyWith(
          expedition: expedition,
          selectedMemberId: _defaultMember(expedition),
          busyAction: null,
          tutorialCoachStep: _deriveTutorialStep(expedition),
          actionCue: null,
          pendingExpedition: null,
          settlingResult: false,
        );
      } else {
        // 서버 결과는 확정됐지만 전투 연출이 끝날 때까지 이전 장면을 유지한다.
        // 다음 화면과 전투 첫 프레임을 한 번에 빌드하면 저사양 기기에서 긴 프레임이 생긴다.
        _queuedCues
          ..clear()
          ..addAll(actionCues.skip(1));
        state = state.copyWith(
          busyAction: null,
          actionCue: actionCues.first,
          pendingExpedition: expedition,
          settlingResult: false,
        );
      }
      return true;
    } on ApiException catch (error) {
      _queuedCues.clear();
      if (error.code == 'EXPEDITION_REVISION_CONFLICT') {
        _actionKeys.remove(action);
        await _reloadActive(error.message);
      } else {
        state = state.copyWith(busyAction: null, error: error.message);
      }
      return false;
    }
  }

  List<ExpeditionActionCue> _actionCuesFor(
    String action, {
    required ExpeditionSnapshot? previousExpedition,
    required int? previousMemberId,
    required ExpeditionSnapshot result,
  }) {
    if (action.startsWith('combat:') && previousExpedition != null) {
      final enemy = previousExpedition.currentEvent?.battle?.enemy;
      if (enemy == null) return const [];
      final cues = <ExpeditionActionCue>[];
      final actionEvents = result.lastCombatExchange
          .where(
            (event) =>
                event.isPartyAction || event.isEnemyAction || event.isBossPhase,
          )
          .toList(growable: false);
      final terminal = result.lastCombatExchange
          .where((event) => event.type == 'outcome')
          .lastOrNull;
      // 엉킴이 풀리면 그 라운드는 거기서 끝나므로, 마지막 행동이 곧 풀어 준
      // 행동이다. 그 연출이 끝난 뒤 지역별 두 음 cadence를 한 번 얹는다.
      final released = result.lastCombatExchange
          .where(
            (event) =>
                event.isWaveCleared ||
                (event.isVictoryOutcome && event.regionCode != null),
          )
          .lastOrNull;
      for (final (index, event) in actionEvents.indexed) {
        if (event.isBossPhase) {
          final member = previousExpedition.party.firstOrNull;
          if (member != null) {
            cues.add(
              ExpeditionActionCue.bossPhase(
                id: ++_cueSequence,
                event: event,
                member: member,
                enemy: enemy,
              ),
            );
          }
          continue;
        }
        final memberId = event.memberId ?? event.targets.firstOrNull?.memberId;
        final member = previousExpedition.party
            .where((item) => item.id == memberId)
            .firstOrNull;
        if (member == null) continue;
        cues.add(
          ExpeditionActionCue.combatRound(
            id: ++_cueSequence,
            event: event,
            member: member,
            enemy: enemy,
            terminalResult:
                index == actionEvents.length - 1 ? terminal?.outcome : null,
            terminalCaption:
                index == actionEvents.length - 1 ? terminal?.caption : null,
            releaseRegionCode:
                index == actionEvents.length - 1 ? released?.regionCode : null,
          ),
        );
      }
      return cues;
    }
    if (action.startsWith('choice:')) {
      final resolution = result.lastResolution;
      final member = previousExpedition?.party
          .where((item) => item.id == previousMemberId)
          .firstOrNull;
      if (resolution == null || member == null) return const [];
      return [
        ExpeditionActionCue.resolution(
          id: ++_cueSequence,
          resolution: resolution,
          member: member,
        ),
      ];
    }
    if (!action.startsWith('skill:') ||
        previousExpedition == null ||
        previousMemberId == null) {
      return const [];
    }
    final parts = action.split(':');
    if (parts.length < 3) return const [];
    final member = previousExpedition.party
        .where((item) => item.id == previousMemberId)
        .firstOrNull;
    if (member == null) return const [];
    final skill = parts[2] == 'form' ? member.formSkill : member.signatureSkill;
    return [
      ExpeditionActionCue.skill(
        id: ++_cueSequence,
        member: member,
        skill: skill,
      ),
    ];
  }

  Future<void> _reloadActive(String message) async {
    try {
      final expedition =
          await ref.read(expeditionRepositoryProvider).getActive();
      state = state.copyWith(
        expedition: expedition,
        selectedMemberId: _defaultMember(expedition),
        busyAction: null,
        error: message,
        tutorialCoachStep: _deriveTutorialStep(expedition),
        actionCue: null,
        pendingExpedition: null,
        settlingResult: false,
      );
      _queuedCues.clear();
    } on ApiException catch (error) {
      state = state.copyWith(busyAction: null, error: error.message);
    }
  }

  Future<void> leaveSummary() async {
    _dismissedTutorialSteps.clear();
    _queuedCues.clear();
    state = state.copyWith(
      expedition: null,
      tutorialCoachStep: null,
      actionCue: null,
      pendingExpedition: null,
      settlingResult: false,
    );
    await load();
  }

  void clearError() => state = state.copyWith(error: null);

  /// 새 기록서 안내를 한 번 보여 준 뒤 비운다. 같은 소식을 반복하지 않는다.
  void clearUnlockedSkillBooks() =>
      state = state.copyWith(unlockedSkillBooks: const []);

  void clearActionCue() {
    if (_queuedCues.isNotEmpty) {
      final next = _queuedCues.removeAt(0);
      state = state.copyWith(
        actionCue: next,
        selectedMemberId: next.actorId,
      );
      return;
    }
    final pending = state.pendingExpedition;
    if (pending == null) {
      state = state.copyWith(actionCue: null);
      return;
    }
    state = state.copyWith(
      expedition: pending,
      selectedMemberId: _defaultMember(pending),
      tutorialCoachStep: _deriveTutorialStep(pending),
      actionCue: null,
      pendingExpedition: null,
      settlingResult: true,
    );
    _settlingTimer?.cancel();
    final revision = pending.run.revision;
    _settlingTimer = Timer(const Duration(milliseconds: 32), () {
      if (state.expedition?.run.revision != revision || !state.settlingResult) {
        return;
      }
      state = state.copyWith(settlingResult: false);
    });
  }
}

final expeditionControllerProvider =
    NotifierProvider<ExpeditionController, ExpeditionUiState>(
  ExpeditionController.new,
);
