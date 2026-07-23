import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../data/plant_repository.dart';
import '../domain/plant.dart';

/// 활성 식물 상태.
class HomeController extends AsyncNotifier<ActivePlant?> {
  static const _uuid = Uuid();

  /// 수확 재시도 시 같은 Idempotency-Key를 재사용하기 위해 보관한다.
  String? _harvestKey;
  int? _harvestPlantId;
  Timer? _analysisTimer;
  Future<String?>? _plantFuture;
  int _analysisPollAttempt = 0;
  int _pollGeneration = 0;

  static const _maxAnalysisPolls = 12;
  // worker의 30초 + 120초 재시도 창을 넘겨 terminal 상태까지 확인하되,
  // 요청 수는 12회로 제한한다. 총 관찰 창은 약 178초다.
  static const _analysisBackoffSeconds = [2, 3, 5, 8, 13, 21];

  @override
  Future<ActivePlant?> build() async {
    ref.onDispose(() {
      _analysisTimer?.cancel();
      _pollGeneration++;
    });
    final plant = await ref.watch(plantRepositoryProvider).getActivePlant();
    _scheduleAnalysisPoll(plant, reset: true);
    return plant;
  }

  Future<void> refresh() async {
    _analysisTimer?.cancel();
    final generation = ++_pollGeneration;
    state = const AsyncLoading();
    final refreshed = await AsyncValue.guard(
        () => ref.read(plantRepositoryProvider).getActivePlant());
    if (generation != _pollGeneration) return;
    state = refreshed;
    _scheduleAnalysisPoll(state.valueOrNull, reset: true);
  }

  /// 본문 분석은 worker에서 끝나므로, pending인 동안만 짧게
  /// 뒤에서 상태를 다시 읽는다. 중복 타이머를 막고 최대 12회 후
  /// 멈춰 네트워크와 배터리를 소모하지 않는다.
  void _scheduleAnalysisPoll(ActivePlant? plant, {bool reset = false}) {
    _analysisTimer?.cancel();
    if (reset) _analysisPollAttempt = 0;
    if (plant == null ||
        plant.emotionProfile.pendingCount <= 0 ||
        _analysisPollAttempt >= _maxAnalysisPolls) {
      return;
    }
    final generation = _pollGeneration;
    final delaySeconds = _analysisBackoffSeconds[
        _analysisPollAttempt.clamp(0, _analysisBackoffSeconds.length - 1)];
    _analysisTimer = Timer(Duration(seconds: delaySeconds), () async {
      _analysisPollAttempt++;
      try {
        final refreshed =
            await ref.read(plantRepositoryProvider).getActivePlant();
        if (generation != _pollGeneration) return;
        state = AsyncData(refreshed);
        _scheduleAnalysisPoll(refreshed);
      } on Object {
        if (generation != _pollGeneration) return;
        _scheduleAnalysisPoll(plant);
      }
    });
  }

  /// 수확. 성공 시 null, 실패 시 표시할 오류 message를 돌려준다.
  Future<String?> harvest(int plantId) async {
    if (_harvestPlantId != plantId) {
      _harvestPlantId = plantId;
      _harvestKey = _uuid.v4();
    }
    try {
      await ref.read(plantRepositoryProvider).harvest(
            plantId: plantId,
            idempotencyKey: _harvestKey!,
          );
      _harvestKey = null;
      _harvestPlantId = null;
      await refresh();
      return null;
    } on ApiException catch (e) {
      if (e.code == 'PLANT_NOT_HARVESTABLE' ||
          e.code == 'PLANT_ANALYSIS_PENDING' ||
          e.code == 'PLANT_EMOTION_EVIDENCE_REQUIRED') {
        // 이미 수확된 경우 등 - 상태만 새로 읽는다.
        _harvestKey = null;
        _harvestPlantId = null;
        await refresh();
      }
      return e.message;
    }
  }

  /// 새 식물 심기. 성공 시 null, 실패 시 오류 message.
  Future<String?> plantNew({int? speciesId, String? name}) {
    final active = _plantFuture;
    if (active != null) return active;
    late final Future<String?> tracked;
    tracked = _performPlantNew(speciesId: speciesId, name: name).whenComplete(
      () {
        if (identical(_plantFuture, tracked)) _plantFuture = null;
      },
    );
    _plantFuture = tracked;
    return tracked;
  }

  Future<String?> _performPlantNew({int? speciesId, String? name}) async {
    try {
      await ref
          .read(plantRepositoryProvider)
          .createPlant(speciesId: speciesId, name: name);
      await refresh();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }
}

final homeControllerProvider =
    AsyncNotifierProvider<HomeController, ActivePlant?>(HomeController.new);

/// 새 일기가 식물에 반영됐음을 알리는 일시적 UI 표시.
///
/// 수동 기분 점수를 표정에 연결하지 않고, 식물의 기본 표정·성격은
/// 오직 일기 본문 분석 분기를 따른다.
class PlantReactionController extends Notifier<bool> {
  static const reactionDuration = Duration(seconds: 6);

  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void acknowledgeAnalysis() {
    _timer?.cancel();
    state = true;
    _timer = Timer(reactionDuration, () => state = false);
  }
}

final plantReactionProvider = NotifierProvider<PlantReactionController, bool>(
    PlantReactionController.new);
