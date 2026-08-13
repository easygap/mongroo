import 'package:audioplayers/audioplayers.dart';

/// 모험 탭의 네 순간에만 쓰는 짧은 소리.
///
/// `design-system/ADVENTURE_AUDIO.md`의 `효과음과 촉각`이 순간마다 재료와 길이
/// 상한을 정해 뒀고, 지금까지는 촉각만 붙어 있었다. 전투 오디오와 분리한 이유는
/// 두 가지다. 전투 쪽은 27개 pool을 미리 올리는데 모험 탭에는 그 대부분이 필요
/// 없고, 이 소리들은 전투 연출 타임라인이 아니라 사용자의 확정 동작에 붙는다.
enum AdventureCue { patrolDepart, patrolReturn, dungeonClear, researchComplete }

class AdventureCueAudio {
  AdventureCueAudio() : _ready = _loadPools();

  static const _paths = {
    AdventureCue.patrolDepart: 'adventure/sfx/cue-patrol-depart.wav',
    AdventureCue.patrolReturn: 'adventure/sfx/cue-patrol-return.wav',
    AdventureCue.dungeonClear: 'adventure/sfx/cue-dungeon-clear.wav',
    AdventureCue.researchComplete: 'adventure/sfx/cue-research-complete.wav',
  };

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    // 확정음이 무음 스위치를 우회하거나 사용자가 듣던 음악을 끊지 않게 한다.
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final Future<Map<AdventureCue, AudioPool>> _ready;
  final Map<AdventureCue, DateTime> _lastPlayedAt = {};
  bool _disposed = false;

  static Future<Map<AdventureCue, AudioPool>> _loadPools() async {
    final pools = <AdventureCue, AudioPool>{};
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

  /// 확정 순간의 소리를 한 번 낸다.
  ///
  /// [enabled]가 false면 아무것도 하지 않는다 — 효과음을 끈 사용자에게도
  /// 문구와 촉각은 그대로 남아 결과를 알 수 있다.
  Future<void> play(AdventureCue cue, {required bool enabled}) async {
    if (_disposed || !enabled) return;
    // 보상이 여러 개여도 소리는 한 번이다. 기준 문서가 재화 수만큼 반복하지
    // 말라고 정해 둔 규칙을 여기서 지킨다.
    final now = DateTime.now();
    final last = _lastPlayedAt[cue];
    if (last != null && now.difference(last) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastPlayedAt[cue] = now;
    try {
      final pools = await _ready;
      if (_disposed) return;
      await pools[cue]?.start(volume: .62);
    } on Object {
      // 오디오 초기화 실패가 보상 수령이나 화면 전환을 막지 않는다.
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
