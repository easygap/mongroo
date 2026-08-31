import 'package:audioplayers/audioplayers.dart';

import '../domain/expedition_models.dart';

/// 탐험에서 무언가를 찾은 세 순간.
///
/// 셋은 세기가 아니라 **무게**가 다르다. 음 수가 하나씩 늘고 마지막 음이
/// `정원으로 돌아가는 동기`의 뒤쪽으로 가서, 목표를 찾았을 때가 가장 멀리
/// 간다. 제작 스크립트(`build_expedition_field_audio.py`)가 그 순서를 만들고
/// 검수기가 강제한다.
enum ExpeditionDiscoveryCue {
  /// 새 장소를 찾았다 — 발견 노드에 닿았다.
  place,

  /// 이야기가 한 걸음 나아갔다.
  story,

  /// 이번 걸음의 목표를 확보했다.
  objective,
}

/// 두 스냅숏 사이에 무엇을 찾았는지 고른다. 없으면 `null`.
///
/// 한 번의 갱신에서 여러 가지가 동시에 열릴 수 있다(목표를 확보하면 이야기도
/// 결말로 넘어간다). 그때 소리를 두 번 내지 않고 **가장 무거운 것 하나만**
/// 낸다. 기준 문서가 한 순간의 또렷한 transient를 셋으로 제한하는데, 발견음은
/// 이미 다른 판정음과 같은 순간에 얹히기 때문이다.
///
/// 오디오와 떼어 둔 이유는 이 판단이 소리보다 오래 살기 때문이다. 무엇을
/// `찾았다`고 볼지는 규칙이고, 규칙은 테스트로 고정할 수 있어야 한다.
ExpeditionDiscoveryCue? expeditionDiscoveryCueFor(
  ExpeditionSnapshot? previous,
  ExpeditionSnapshot next,
) {
  if (previous == null) return null;
  // 다른 탐험으로 갈아탄 것은 발견이 아니다.
  if (previous.run.id != next.run.id) return null;

  if (!previous.run.objectiveSecured && next.run.objectiveSecured) {
    // 전투로 목표를 확보했다면 지역 풀려남 cadence가 이미 결과음이다.
    // 같은 순간에 발견음을 또 얹으면 무엇이 끝났는지가 오히려 흐려진다.
    final wonThisUpdate = next.lastCombatExchange.any(
      (event) => event.isVictoryOutcome,
    );
    return wonThisUpdate ? null : ExpeditionDiscoveryCue.objective;
  }

  final threadBefore = previous.runThread['current_text'];
  final threadAfter = next.runThread['current_text'];
  if (threadAfter is String &&
      threadAfter.isNotEmpty &&
      threadAfter != threadBefore) {
    return ExpeditionDiscoveryCue.story;
  }

  if (_discoveryCount(next) > _discoveryCount(previous)) {
    return ExpeditionDiscoveryCue.place;
  }
  return null;
}

int _discoveryCount(ExpeditionSnapshot snapshot) {
  final found = snapshot.memory['discoveries'];
  return found is List ? found.length : 0;
}

/// 발견 순간의 짧은 소리 셋.
///
/// 전투 오디오와 분리한 이유는 `AdventureCueAudio`와 같다. 전투 쪽은 공용음
/// 서른한 개를 미리 올리는데 여기서 필요한 것은 셋뿐이고, 이 소리들은 연출
/// 타임라인이 아니라 **서버가 확정한 상태 변화**에 붙는다.
class ExpeditionDiscoveryAudio {
  ExpeditionDiscoveryAudio() : _ready = _loadPools();

  static const _paths = {
    ExpeditionDiscoveryCue.place: 'adventure/sfx/discover-normal.wav',
    ExpeditionDiscoveryCue.story: 'adventure/sfx/discover-story.wav',
    ExpeditionDiscoveryCue.objective: 'adventure/sfx/discover-target.wav',
  };

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    // 발견음이 무음 스위치를 우회하거나 듣던 음악을 끊지 않게 한다.
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  /// 접촉음(0.72×0.147 ≈ 0.106)보다 낮게. 발견은 결과가 아니라 소식이다.
  static const _volume = .58;

  final Future<Map<ExpeditionDiscoveryCue, AudioPool>> _ready;
  DateTime? _lastPlayedAt;
  bool _disposed = false;

  static Future<Map<ExpeditionDiscoveryCue, AudioPool>> _loadPools() async {
    final pools = <ExpeditionDiscoveryCue, AudioPool>{};
    try {
      for (final entry in _paths.entries) {
        pools[entry.key] = await AudioPool.create(
          source: AssetSource(entry.value),
          minPlayers: 1,
          maxPlayers: 1,
          audioContext: _context,
        );
      }
      return pools;
    } on Object {
      await Future.wait(pools.values.map((pool) => pool.dispose()));
      return const {};
    }
  }

  /// [enabled]가 false면 아무것도 하지 않는다 — 효과음을 끈 사용자에게도
  /// 찾은 것은 화면에 그대로 남는다.
  Future<void> play(
    ExpeditionDiscoveryCue cue, {
    required bool enabled,
  }) async {
    if (_disposed || !enabled) return;
    // 셋 중 무엇이든 한 번에 하나만 울린다. 발견이 연달아 열려도 소리는
    // 겹치지 않는다.
    final now = DateTime.now();
    final last = _lastPlayedAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 700)) {
      return;
    }
    _lastPlayedAt = now;
    try {
      final pools = await _ready;
      if (_disposed) return;
      await pools[cue]?.start(volume: _volume);
    } on Object {
      // 소리가 안 나도 발견은 화면과 기록에 남는다.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      final pools = await _ready;
      await Future.wait(pools.values.map((pool) => pool.dispose()));
    } on Object {
      // 초기화가 실패한 플랫폼에는 해제할 pool이 없다.
    }
  }
}
