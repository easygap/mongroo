import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

enum ExpeditionCombatSound {
  command,
  hit,
  weakness,
  enemy,
  guard,
  victory,
  defeat,
}

/// 짧은 전투 효과음을 미리 로드하고 재사용한다.
///
/// 오디오 장치가 없거나 브라우저가 자동 재생을 막아도 전투 흐름은
/// 멈추지 않도록 재생 오류는 합법적으로 무시한다.
class ExpeditionCombatAudio {
  ExpeditionCombatAudio() : _ready = _loadPools();

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    // 짧은 효과음이 무음 스위치를 우회하거나 다른 오디오를
    // 끊지 않도록 ambient 세션을 사용한다.
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  static const _paths = {
    ExpeditionCombatSound.command: 'adventure/sfx/combat-command.wav',
    ExpeditionCombatSound.hit: 'adventure/sfx/combat-hit.wav',
    ExpeditionCombatSound.weakness: 'adventure/sfx/combat-weakness.wav',
    ExpeditionCombatSound.enemy: 'adventure/sfx/combat-enemy.wav',
    ExpeditionCombatSound.guard: 'adventure/sfx/combat-guard.wav',
    ExpeditionCombatSound.victory: 'adventure/sfx/combat-victory.wav',
    ExpeditionCombatSound.defeat: 'adventure/sfx/combat-defeat.wav',
  };

  final Future<Map<ExpeditionCombatSound, AudioPool>> _ready;
  bool _disposed = false;

  static Future<Map<ExpeditionCombatSound, AudioPool>> _loadPools() async {
    final pools = <ExpeditionCombatSound, AudioPool>{};
    try {
      for (final entry in _paths.entries) {
        pools[entry.key] = await AudioPool.create(
          source: AssetSource(entry.value),
          minPlayers: 1,
          maxPlayers: 2,
          audioContext: _context,
        );
      }
      return pools;
    } on Object {
      await Future.wait(pools.values.map((pool) => pool.dispose()));
      return const {};
    }
  }

  Future<void> play(
    ExpeditionCombatSound sound, {
    double volume = 0.72,
  }) async {
    if (_disposed) return;
    try {
      final pools = await _ready;
      if (_disposed) return;
      await pools[sound]?.start(volume: volume);
    } on Object {
      // 시각·행틱 피드백은 계속 제공되므로 오디오 오류만 건너뛴다.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      final pools = await _ready;
      await Future.wait(pools.values.map((pool) => pool.dispose()));
    } on Object {
      // 초기화가 실패한 플랫폼에서는 해제할 플레이어가 없다.
    }
  }
}
