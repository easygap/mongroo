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

class ExpeditionUiState {
  const ExpeditionUiState({
    this.loading = true,
    this.catalog,
    this.roster = const [],
    this.expedition,
    this.selectedPlantIds = const {},
    this.selectedMemberId,
    this.busyAction,
    this.error,
    this.tutorialCoachStep,
    this.actionCue,
    this.pendingExpedition,
    this.settlingResult = false,
  });

  final bool loading;
  final ExpeditionCatalog? catalog;
  final List<ExpeditionRosterItem> roster;
  final ExpeditionSnapshot? expedition;
  final Set<int> selectedPlantIds;
  final int? selectedMemberId;
  final String? busyAction;
  final String? error;
  final int? tutorialCoachStep;
  final ExpeditionActionCue? actionCue;
  final ExpeditionSnapshot? pendingExpedition;
  final bool settlingResult;

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
    Set<int>? selectedPlantIds,
    Object? selectedMemberId = _unset,
    Object? busyAction = _unset,
    Object? error = _unset,
    Object? tutorialCoachStep = _unset,
    Object? actionCue = _unset,
    Object? pendingExpedition = _unset,
    bool? settlingResult,
  }) =>
      ExpeditionUiState(
        loading: loading ?? this.loading,
        catalog:
            catalog == _unset ? this.catalog : catalog as ExpeditionCatalog?,
        roster: roster ?? this.roster,
        expedition: expedition == _unset
            ? this.expedition
            : expedition as ExpeditionSnapshot?,
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
      ]);
      final catalog = results[0] as ExpeditionCatalog;
      final roster = results[1] as List<ExpeditionRosterItem>;
      final expedition = results[2] as ExpeditionSnapshot?;
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
    final action = 'start:$mode:${plantIds.join(',')}';
    return _perform(
      action,
      (key) => ref.read(expeditionRepositoryProvider).start(
            mode: mode,
            plantIds: plantIds,
            guideCount: mode == 'tutorial' ? 1 : 0,
            idempotencyKey: key,
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
          .where((event) => event.isPartyAction || event.isEnemyAction)
          .toList(growable: false);
      final terminal = result.lastCombatExchange
          .where((event) => event.type == 'outcome')
          .lastOrNull;
      for (final (index, event) in actionEvents.indexed) {
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
