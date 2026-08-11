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
  storyReveal,
}

enum ExpeditionMusicState { base, combat, guardian }

/// 짧은 전투 효과음을 미리 로드하고 재사용한다.
///
/// 오디오 장치가 없거나 브라우저가 자동 재생을 막아도 전투 흐름은
/// 멈추지 않도록 재생 오류는 합법적으로 무시한다.
class ExpeditionCombatAudio {
  ExpeditionCombatAudio({bool enabled = true})
      : _enabled = enabled,
        _ready = _loadPools();

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

  static final _musicContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
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
    ExpeditionCombatSound.storyReveal: 'adventure/sfx/story-postcard.wav',
  };

  static const _musicPaths = {
    ExpeditionMusicState.base: 'adventure/music/moss-archive-base.m4a',
    ExpeditionMusicState.combat: 'adventure/music/moss-archive-combat.m4a',
    ExpeditionMusicState.guardian: 'adventure/music/moss-archive-guardian.m4a',
  };

  final Future<Map<ExpeditionCombatSound, AudioPool>> _ready;
  AudioPlayer _activeMusic = AudioPlayer();
  AudioPlayer _standbyMusic = AudioPlayer();
  ExpeditionMusicState? _musicState;
  bool _enabled;
  bool _disposed = false;
  int _transitionGeneration = 0;

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
    if (_disposed || !_enabled) return;
    try {
      final pools = await _ready;
      if (_disposed) return;
      await pools[sound]?.start(volume: volume);
    } on Object {
      // 시각·행틱 피드백은 계속 제공되므로 오디오 오류만 건너뛴다.
    }
  }

  /// 고레벨 스킬은 같은 원샷을 크게만 틀지 않고 짧은 두 번째 음색을 얹는다.
  /// 전용 음원이 없는 스킬도 티어 차이를 들을 수 있고, 레이어 간격이 짧아
  /// 명령 입력 피드백은 늦어지지 않는다.
  Future<void> playSkillTier({
    required int tier,
    required bool ultimate,
  }) async {
    final safeTier = tier.clamp(1, 3);
    await play(
      ExpeditionCombatSound.command,
      volume: switch (safeTier) {
        1 => .46,
        2 => .54,
        _ => .62,
      },
    );
    if (safeTier < 3 || _disposed || !_enabled) return;
    await Future<void>.delayed(const Duration(milliseconds: 42));
    await play(
      ExpeditionCombatSound.weakness,
      volume: ultimate ? .31 : .23,
    );
  }

  /// 16초 마디를 처음부터 다시 틀지 않고 지역 음악을 시작하거나 교차 전환한다.
  Future<void> playMusic(
    ExpeditionMusicState state, {
    double volume = 0.18,
  }) async {
    if (_disposed || !_enabled || _musicState == state) return;
    final generation = ++_transitionGeneration;
    try {
      final path = _musicPaths[state]!;
      if (_musicState == null) {
        await _activeMusic.setReleaseMode(ReleaseMode.loop);
        await _activeMusic.play(
          AssetSource(path),
          volume: volume,
          ctx: _musicContext,
        );
        if (!_disposed && generation == _transitionGeneration) {
          _musicState = state;
        }
        return;
      }

      final position = await _activeMusic.getCurrentPosition() ?? Duration.zero;
      await _standbyMusic.setReleaseMode(ReleaseMode.loop);
      await _standbyMusic.play(
        AssetSource(path),
        volume: 0,
        position: Duration(
          milliseconds: position.inMilliseconds %
              const Duration(seconds: 16).inMilliseconds,
        ),
        ctx: _musicContext,
      );
      for (var step = 1; step <= 8; step++) {
        if (_disposed || generation != _transitionGeneration) return;
        final progress = step / 8;
        await Future.wait([
          _activeMusic.setVolume(volume * (1 - progress)),
          _standbyMusic.setVolume(volume * progress),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await _activeMusic.stop();
      final previous = _activeMusic;
      _activeMusic = _standbyMusic;
      _standbyMusic = previous;
      _musicState = state;
    } on Object {
      // 음악 로드 실패도 전투 입력과 효과음 재생을 막지 않는다.
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed || _enabled == value) return;
    _enabled = value;
    ++_transitionGeneration;
    try {
      if (value) {
        final state = _musicState;
        _musicState = null;
        if (state != null) await playMusic(state);
      } else {
        await Future.wait([_activeMusic.pause(), _standbyMusic.pause()]);
      }
    } on Object {
      // 설정 변경은 오디오 장치 상태와 무관하게 즉시 UI에 반영한다.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    ++_transitionGeneration;
    try {
      final pools = await _ready;
      await Future.wait([
        ...pools.values.map((pool) => pool.dispose()),
        _activeMusic.dispose(),
        _standbyMusic.dispose(),
      ]);
    } on Object {
      // 초기화가 실패한 플랫폼에서는 해제할 플레이어가 없다.
    }
  }
}
