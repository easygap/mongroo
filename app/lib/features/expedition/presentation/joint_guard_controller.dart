import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../data/joint_guard_repository.dart';
import '../domain/expedition_combat_models.dart';
import '../domain/joint_guard_models.dart';
import 'expedition_action_cue.dart';

/// 합동 수호전 화면 상태.
///
/// 스테이지 탐험 컨트롤러와 같은 리듬을 쓴다 — 서버 결과는 곧바로 확정되지만,
/// 연출이 끝날 때까지 이전 장면을 들고 있다가 큐가 비면 갈아 끼운다. 그래야
/// 예고 두 줄이 화면에 남은 채로 다음 라운드 숫자가 먼저 바뀌는 일이 없다.
class JointGuardUiState {
  const JointGuardUiState({
    this.loading = true,
    this.entry,
    this.run,
    this.pendingRun,
    this.actionCue,
    this.busy,
    this.error,
    this.selectedMemberId,
  });

  final bool loading;
  final JointGuardEntry? entry;
  final JointGuardRun? run;

  /// 연출이 끝난 뒤 갈아 끼울 판. 큐가 도는 동안만 값이 있다.
  final JointGuardRun? pendingRun;

  final ExpeditionActionCue? actionCue;

  /// 진행 중인 요청 이름. 같은 버튼을 두 번 누르지 못하게 한다.
  final String? busy;

  final String? error;
  final int? selectedMemberId;

  bool get interactionLocked =>
      busy != null || actionCue != null || pendingRun != null;

  JointGuardState? get state => run?.state;

  JointGuardUiState copyWith({
    bool? loading,
    JointGuardEntry? entry,
    Object? run = _unset,
    Object? pendingRun = _unset,
    Object? actionCue = _unset,
    Object? busy = _unset,
    Object? error = _unset,
    Object? selectedMemberId = _unset,
  }) =>
      JointGuardUiState(
        loading: loading ?? this.loading,
        entry: entry ?? this.entry,
        run: run == _unset ? this.run : run as JointGuardRun?,
        pendingRun:
            pendingRun == _unset ? this.pendingRun : pendingRun as JointGuardRun?,
        actionCue: actionCue == _unset
            ? this.actionCue
            : actionCue as ExpeditionActionCue?,
        busy: busy == _unset ? this.busy : busy as String?,
        error: error == _unset ? this.error : error as String?,
        selectedMemberId: selectedMemberId == _unset
            ? this.selectedMemberId
            : selectedMemberId as int?,
      );
}

const Object _unset = Object();

class JointGuardController extends Notifier<JointGuardUiState> {
  final _uuid = const Uuid();
  final List<ExpeditionActionCue> _queued = [];
  final Map<String, String> _actionKeys = {};
  int _cueSequence = 0;

  @override
  JointGuardUiState build() {
    Future.microtask(load);
    return const JointGuardUiState();
  }

  JointGuardRepository get _repository => ref.read(jointGuardRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final entry = await _repository.getEntry();
      final run = await _repository.getActive();
      state = state.copyWith(
        loading: false,
        entry: entry,
        run: run,
        selectedMemberId: run?.state.front.firstOrNull?.memberId,
      );
    } on ApiException catch (error) {
      state = state.copyWith(loading: false, error: error.message);
    }
  }

  void selectMember(int memberId) =>
      state = state.copyWith(selectedMemberId: memberId);

  void clearError() => state = state.copyWith(error: null);

  Future<bool> start({
    required String beastCode,
    required String difficulty,
    required List<Map<String, Object?>> formation,
  }) async {
    if (state.interactionLocked) return false;
    final action = 'start:$beastCode:$difficulty';
    state = state.copyWith(busy: action, error: null);
    try {
      final key = _actionKeys.putIfAbsent(action, _uuid.v4);
      final run = await _repository.start(
        beastCode: beastCode,
        difficulty: difficulty,
        formation: formation,
        idempotencyKey: key,
      );
      _actionKeys.remove(action);
      state = state.copyWith(
        busy: null,
        run: run,
        selectedMemberId: run.state.front.firstOrNull?.memberId,
      );
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(busy: null, error: error.message);
      return false;
    }
  }

  Future<bool> submitCommand(ExpeditionCombatCommand command) async {
    final run = state.run;
    if (run == null || state.interactionLocked) return false;
    final action = 'turn:${run.revision}:${command.memberId}:${command.action}';
    return _perform(
      action,
      (key) => _repository.submitTurn(
        runId: run.runId,
        command: command,
        expectedRevision: run.revision,
        clientActionId: key,
      ),
    );
  }

  Future<bool> swap({required int outMemberId, required int inMemberId}) async {
    final run = state.run;
    if (run == null || state.interactionLocked) return false;
    final action = 'swap:${run.revision}:$outMemberId:$inMemberId';
    return _perform(
      action,
      (key) => _repository.swap(
        runId: run.runId,
        outMemberId: outMemberId,
        inMemberId: inMemberId,
        expectedRevision: run.revision,
        clientActionId: key,
      ),
    );
  }

  Future<bool> _perform(
    String action,
    Future<JointGuardRun> Function(String key) request,
  ) async {
    final previous = state.run;
    state = state.copyWith(busy: action, error: null);
    try {
      final key = _actionKeys.putIfAbsent(action, _uuid.v4);
      final result = await request(key);
      _actionKeys.remove(action);
      final cues = _cuesFor(previous: previous, result: result);
      if (cues.isEmpty) {
        _queued.clear();
        state = state.copyWith(
          busy: null,
          run: result,
          pendingRun: null,
          actionCue: null,
          selectedMemberId: result.state.front.firstOrNull?.memberId,
        );
      } else {
        // 서버 결과는 확정됐지만 연출이 끝날 때까지 이전 장면을 유지한다.
        _queued
          ..clear()
          ..addAll(cues.skip(1));
        state = state.copyWith(
          busy: null,
          actionCue: cues.first,
          pendingRun: result,
        );
      }
      return true;
    } on ApiException catch (error) {
      _queued.clear();
      _actionKeys.remove(action);
      if (error.code == 'EXPEDITION_REVISION_CONFLICT') {
        await load();
        state = state.copyWith(error: error.message);
      } else {
        state = state.copyWith(busy: null, error: error.message);
      }
      return false;
    }
  }

  /// 이번 응답에서 새로 일어난 일들을 연출 큐로 편다.
  ///
  /// 대원은 **이전 판**에서 찾는다. 결과 판에서 찾으면 방금 교대로 나간 대원의
  /// 연출이 사라진다.
  List<ExpeditionActionCue> _cuesFor({
    required JointGuardRun? previous,
    required JointGuardRun result,
  }) {
    if (previous == null) return const [];
    final events = result.state.battle.lastExchange
        .where((event) => event.isPartyAction || event.isEnemyAction)
        .toList(growable: false);
    if (events.isEmpty) return const [];

    final roster = [...previous.state.front, ...previous.state.reserves];
    final enemy = result.state.battle.enemy;
    final terminal = result.state.battle.lastExchange
        .where((event) => event.outcome != null)
        .lastOrNull;

    final cues = <ExpeditionActionCue>[];
    for (final (index, event) in events.indexed) {
      final memberId = event.memberId ?? event.targets.firstOrNull?.memberId;
      final member = roster
          .where((entry) => entry.memberId == memberId)
          .firstOrNull
          ?.member;
      if (member == null) continue;
      cues.add(
        ExpeditionActionCue.combatRound(
          id: ++_cueSequence,
          event: event,
          member: member,
          enemy: enemy,
          terminalResult:
              index == events.length - 1 ? terminal?.outcome : null,
          terminalCaption:
              index == events.length - 1 ? terminal?.caption : null,
        ),
      );
    }
    return cues;
  }

  /// 연출 한 컷이 끝났다. 남은 큐가 있으면 이어서, 없으면 판을 갈아 끼운다.
  void clearActionCue() {
    if (_queued.isNotEmpty) {
      state = state.copyWith(actionCue: _queued.removeAt(0));
      return;
    }
    final pending = state.pendingRun;
    if (pending == null) {
      state = state.copyWith(actionCue: null);
      return;
    }
    state = state.copyWith(
      run: pending,
      pendingRun: null,
      actionCue: null,
      selectedMemberId: pending.state.front.firstOrNull?.memberId,
    );
  }

  /// 판을 닫고 입구로 돌아온다.
  Future<void> leave() async {
    _queued.clear();
    _actionKeys.clear();
    state = state.copyWith(
      run: null,
      pendingRun: null,
      actionCue: null,
      busy: null,
    );
    await load();
  }
}

final jointGuardControllerProvider =
    NotifierProvider<JointGuardController, JointGuardUiState>(
  JointGuardController.new,
);
