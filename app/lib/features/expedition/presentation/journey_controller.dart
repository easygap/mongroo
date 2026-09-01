import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../data/journey_repository.dart';
import '../domain/journey_models.dart';

/// 장거리 개척 화면 상태.
///
/// 화면이 셋뿐이라 상태도 얇다 — 방향 고르기, 구간 편성, 야영지. 어디에
/// 있는지는 서버가 준 개척 상태에서 읽어 낸다. 앱이 따로 단계를 세면 앱을
/// 껐다 켰을 때 서버와 어긋난다.
class JourneyUiState {
  const JourneyUiState({
    this.loading = true,
    this.entry,
    this.journey,
    this.busy,
    this.error,
  });

  final bool loading;
  final JourneyEntry? entry;
  final Journey? journey;

  /// 진행 중인 요청 이름. 같은 버튼을 두 번 누르지 못하게 한다.
  final String? busy;

  final String? error;

  /// 편성 화면을 보여야 하는가 — 야영지이고 아직 갈 구간이 남았다.
  bool get needsFormation => journey?.canContinue == true;

  /// 걷는 중인 구간이 있는가. 있으면 탐험 화면으로 보낸다.
  bool get walking => journey?.activeRunId != null;

  JourneyUiState copyWith({
    bool? loading,
    JourneyEntry? entry,
    Object? journey = _unset,
    Object? busy = _unset,
    Object? error = _unset,
  }) =>
      JourneyUiState(
        loading: loading ?? this.loading,
        entry: entry ?? this.entry,
        journey: journey == _unset ? this.journey : journey as Journey?,
        busy: busy == _unset ? this.busy : busy as String?,
        error: error == _unset ? this.error : error as String?,
      );
}

const Object _unset = Object();

class JourneyController extends Notifier<JourneyUiState> {
  final _uuid = const Uuid();

  /// 요청 이름 → 멱등 키. 실패해서 다시 눌러도 같은 키를 보내야 서버가
  /// 두 번 만들지 않는다.
  final Map<String, String> _keys = {};

  @override
  JourneyUiState build() {
    Future.microtask(load);
    return const JourneyUiState();
  }

  JourneyRepository get _repository => ref.read(journeyRepositoryProvider);

  String _key(String name) => _keys.putIfAbsent(name, () => _uuid.v4());

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final entry = await _repository.getEntry();
      state = state.copyWith(
        loading: false,
        entry: entry,
        journey: entry.active,
      );
    } on ApiException catch (error) {
      state = state.copyWith(loading: false, error: error.message);
    }
  }

  Future<void> start({
    required String directionCode,
    required String mode,
  }) async {
    if (state.busy != null) return;
    state = state.copyWith(busy: 'start', error: null);
    try {
      final journey = await _repository.start(
        directionCode: directionCode,
        mode: mode,
        idempotencyKey: _key('start:$directionCode:$mode'),
      );
      _keys.clear();
      state = state.copyWith(busy: null, journey: journey);
    } on ApiException catch (error) {
      state = state.copyWith(busy: null, error: error.message);
    }
  }

  /// 다음 구간을 연다. 성공하면 탐험 화면으로 보낼 수 있게 `walking`이 된다.
  Future<bool> departLeg({
    required String routeCode,
    required List<int> plantIds,
  }) async {
    final journey = state.journey;
    if (journey == null || state.busy != null) return false;
    state = state.copyWith(busy: 'leg', error: null);
    try {
      final updated = await _repository.createLeg(
        journeyId: journey.id,
        routeCode: routeCode,
        plantIds: plantIds,
        guideCount: journey.partySize - plantIds.length,
        expectedRevision: journey.revision,
        idempotencyKey: _key('leg:${journey.id}:${journey.currentLegIndex}'),
      );
      _keys.clear();
      state = state.copyWith(busy: null, journey: updated);
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(busy: null, error: error.message);
      return false;
    }
  }

  /// 귀환한다. 고른 것이 없으면 서버가 가치 예산을 채운다.
  Future<void> returnHome({List<int> selectedLootIds = const []}) async {
    final journey = state.journey;
    if (journey == null || state.busy != null) return;
    state = state.copyWith(busy: 'return', error: null);
    try {
      final finished = await _repository.returnHome(
        journeyId: journey.id,
        expectedRevision: journey.revision,
        // 고른 조합이 거절되면(예산 초과) 다시 고르게 해야 하므로, 같은 키로
        // 되풀이하지 않도록 고른 목록을 키에 넣는다.
        idempotencyKey: _key('return:${journey.id}:${selectedLootIds.join(",")}'),
        selectedLootIds: selectedLootIds,
      );
      _keys.clear();
      state = state.copyWith(busy: null, journey: finished);
    } on ApiException catch (error) {
      state = state.copyWith(busy: null, error: error.message);
    }
  }

  /// 기록을 닫고 입구로 돌아간다.
  Future<void> closeSummary() async {
    state = state.copyWith(journey: null);
    await load();
  }
}

final journeyControllerProvider =
    NotifierProvider<JourneyController, JourneyUiState>(JourneyController.new);
