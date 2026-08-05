import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../home/presentation/home_controller.dart';
import '../data/expedition_repository.dart';
import '../domain/expedition_models.dart';

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
      );
}

class ExpeditionController extends Notifier<ExpeditionUiState> {
  static const _uuid = Uuid();
  final Map<String, String> _actionKeys = {};
  final Set<int> _dismissedTutorialSteps = {};

  @override
  ExpeditionUiState build() {
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
      );
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
    if (state.busyAction != null) return false;
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
      state = state.copyWith(
        expedition: expedition,
        selectedMemberId: _defaultMember(expedition),
        busyAction: null,
        tutorialCoachStep: _deriveTutorialStep(expedition),
      );
      return true;
    } on ApiException catch (error) {
      if (error.code == 'EXPEDITION_REVISION_CONFLICT') {
        _actionKeys.remove(action);
        await _reloadActive(error.message);
      } else {
        state = state.copyWith(busyAction: null, error: error.message);
      }
      return false;
    }
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
      );
    } on ApiException catch (error) {
      state = state.copyWith(busyAction: null, error: error.message);
    }
  }

  Future<void> leaveSummary() async {
    _dismissedTutorialSteps.clear();
    state = state.copyWith(expedition: null, tutorialCoachStep: null);
    await load();
  }

  void clearError() => state = state.copyWith(error: null);
}

final expeditionControllerProvider =
    NotifierProvider<ExpeditionController, ExpeditionUiState>(
  ExpeditionController.new,
);
