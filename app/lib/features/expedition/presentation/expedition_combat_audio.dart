import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'expedition_signature_audio.dart';

enum ExpeditionCombatSound {
  command,
  hit,
  weakness,
  enemy,
  guard,
  victory,
  defeat,
  storyReveal,
  // 걸을 때 바닥에서 나는 소리. 재질은 지금 서 있는 장면이 정한다.
  stepLeaf,
  stepPot,
  stepWood,
  stepStone,
  skillLight,
  skillFull,
  skillSignature,
  bossPhaseBreak,
  contactLeaf,
  contactPaper,
  contactWater,
  contactWood,
  contactStone,
  contactGuard,
  telegraphLeaf,
  telegraphPaper,
  telegraphWater,
  telegraphWood,
  telegraphStone,
  releaseMossArchive,
  releaseEchoWell,
  releaseStarlightSeedVault,
  releaseHeartwoodObservatory,
}

enum ExpeditionMusicState { base, combat, guardian }

/// 탐험 소리의 세 단계. 접근성 기준의 `음악·효과음을 각각 끌 수 있다`를
/// 버튼 하나로 지킨다. 음악만 끄고 판정 소리는 남기고 싶은 요구가 가장
/// 흔해서 중간 단계를 `효과음만`으로 둔다.
///
/// 전장 HUD에서 시작했지만 지금은 걸음·지도 확정음·모험 탭 cue·발견음까지
/// 같은 값을 읽는다. 그래서 전장 밖(계정 화면)에도 같은 버튼을 둔다.
enum ExpeditionAudioMode { all, sfxOnly, muted }

/// 서버가 내려준 `contact_material`을 접촉음으로 옮긴다.
///
/// 여섯 재질은 색이 아니라 소리로 "무엇에 닿았는가"를 알려 준다. 모르는 값이나
/// 구버전 응답(값 없음)에서는 재질을 지어내지 않고 `null`을 돌려주어 호출부가
/// 기존 공용 타격음을 그대로 쓰게 한다.
ExpeditionCombatSound? expeditionContactSound(String? material) =>
    switch (material) {
      'leaf' => ExpeditionCombatSound.contactLeaf,
      'paper' => ExpeditionCombatSound.contactPaper,
      'water' => ExpeditionCombatSound.contactWater,
      'wood' => ExpeditionCombatSound.contactWood,
      'stone' => ExpeditionCombatSound.contactStone,
      'guard' => ExpeditionCombatSound.contactGuard,
      _ => null,
    };

/// 적 의도 preview — 무엇이 날아오는지 120ms 안에 알린다.
/// 지키기 재질에는 예고가 없다. 예고는 적이 만드는 소리이기 때문이다.
ExpeditionCombatSound? expeditionTelegraphSound(String? material) =>
    switch (material) {
      'leaf' => ExpeditionCombatSound.telegraphLeaf,
      'paper' => ExpeditionCombatSound.telegraphPaper,
      'water' => ExpeditionCombatSound.telegraphWater,
      'wood' => ExpeditionCombatSound.telegraphWood,
      'stone' => ExpeditionCombatSound.telegraphStone,
      _ => null,
    };

/// 엉킴이 제자리로 돌아간 순간의 두 음. 지역마다 음색이 다르지만 음정 관계는
/// 같아 어느 지역에서든 `풀렸다`로 읽힌다.
ExpeditionCombatSound expeditionReleaseSound(String? regionCode) =>
    switch (regionCode) {
      'echo_well' => ExpeditionCombatSound.releaseEchoWell,
      'starlight_seed_vault' => ExpeditionCombatSound.releaseStarlightSeedVault,
      'heartwood_observatory' =>
        ExpeditionCombatSound.releaseHeartwoodObservatory,
      _ => ExpeditionCombatSound.releaseMossArchive,
    };

/// 짧은 전투 효과음을 미리 로드하고 재사용한다.
///
/// 오디오 장치가 없거나 브라우저가 자동 재생을 막아도 전투 흐름은
/// 멈추지 않도록 재생 오류는 합법적으로 무시한다.
class ExpeditionCombatAudio {
  ExpeditionCombatAudio({
    bool enabled = true,
    bool? musicEnabled,
    bool? sfxEnabled,
  })  : _musicEnabled = musicEnabled ?? enabled,
        _sfxEnabled = sfxEnabled ?? enabled,
        _ready = _loadPools();

  /// 백그라운드 진입 fade out과 복귀 fade in 시간.
  /// 기준 문서의 `300ms fade out / 500ms fade in`을 그대로 따른다.
  static const backgroundFadeOut = Duration(milliseconds: 300);
  static const foregroundFadeIn = Duration(milliseconds: 500);
  static const _fadeSteps = 6;

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
    ExpeditionCombatSound.stepLeaf: 'adventure/sfx/step-leaf.wav',
    ExpeditionCombatSound.stepPot: 'adventure/sfx/step-pot.wav',
    ExpeditionCombatSound.stepWood: 'adventure/sfx/step-wood.wav',
    ExpeditionCombatSound.stepStone: 'adventure/sfx/step-stone.wav',
    ExpeditionCombatSound.skillLight: 'adventure/sfx/skill-tier-light.wav',
    ExpeditionCombatSound.skillFull: 'adventure/sfx/skill-tier-full.wav',
    ExpeditionCombatSound.skillSignature:
        'adventure/sfx/skill-tier-signature.wav',
    ExpeditionCombatSound.bossPhaseBreak: 'adventure/sfx/boss-phase-break.wav',
    ExpeditionCombatSound.contactLeaf: 'adventure/sfx/contact-leaf.wav',
    ExpeditionCombatSound.contactPaper: 'adventure/sfx/contact-paper.wav',
    ExpeditionCombatSound.contactWater: 'adventure/sfx/contact-water.wav',
    ExpeditionCombatSound.contactWood: 'adventure/sfx/contact-wood.wav',
    ExpeditionCombatSound.contactStone: 'adventure/sfx/contact-stone.wav',
    ExpeditionCombatSound.contactGuard: 'adventure/sfx/contact-guard.wav',
    ExpeditionCombatSound.telegraphLeaf: 'adventure/sfx/telegraph-leaf.wav',
    ExpeditionCombatSound.telegraphPaper: 'adventure/sfx/telegraph-paper.wav',
    ExpeditionCombatSound.telegraphWater: 'adventure/sfx/telegraph-water.wav',
    ExpeditionCombatSound.telegraphWood: 'adventure/sfx/telegraph-wood.wav',
    ExpeditionCombatSound.telegraphStone: 'adventure/sfx/telegraph-stone.wav',
    ExpeditionCombatSound.releaseMossArchive:
        'adventure/sfx/release-moss-archive.wav',
    ExpeditionCombatSound.releaseEchoWell:
        'adventure/sfx/release-echo-well.wav',
    ExpeditionCombatSound.releaseStarlightSeedVault:
        'adventure/sfx/release-starlight-seed-vault.wav',
    ExpeditionCombatSound.releaseHeartwoodObservatory:
        'adventure/sfx/release-heartwood-observatory.wav',
  };

  static const _musicSlugs = {
    'moss_archive': 'moss-archive',
    'echo_well': 'echo-well',
    'starlight_seed_vault': 'starlight-seed-vault',
    'heartwood_observatory': 'heartwood-observatory',
  };

  static const _musicStateSuffix = {
    ExpeditionMusicState.base: 'base',
    ExpeditionMusicState.combat: 'combat',
    ExpeditionMusicState.guardian: 'guardian',
  };

  /// 지역 곡 경로. 모르는 지역은 첫 지역 곡으로 떨어져 무음이 되지 않는다.
  static String musicPath(String? regionCode, ExpeditionMusicState state) {
    final slug = _musicSlugs[regionCode] ?? 'moss-archive';
    return 'adventure/music/$slug-${_musicStateSuffix[state]}.m4a';
  }

  /// 이 장면을 걸을 때 나는 발소리.
  ///
  /// 재질을 앱이 지어내지 않고 **장면이 정한다** — 젖은 동굴에서 나무 소리가
  /// 나면 눈과 귀가 다른 말을 한다. 모르는 장면은 화분 자신의 소리로 떨어져
  /// 무음이 되지 않는다(주인공은 화분이라 자기 몸이 바닥에 닿는 소리가 있다).
  static ExpeditionCombatSound stepSoundFor(String? sceneKey) =>
      switch (sceneKey) {
        'root_tunnel' => ExpeditionCombatSound.stepLeaf,
        'flooded_cave' || 'echo_well' => ExpeditionCombatSound.stepStone,
        'treasure_vault' || 'monster_den' => ExpeditionCombatSound.stepStone,
        'moon_tower' => ExpeditionCombatSound.stepWood,
        'dungeon_gate' => ExpeditionCombatSound.stepStone,
        _ => ExpeditionCombatSound.stepPot,
      };

  /// 지역 ambience 경로. A는 바닥, B는 공기다.
  ///
  /// 두 층의 길이가 서로 달라(32초·40초) 겹쳐 틀면 실제 반복 주기가 160초로
  /// 늘어난다. 그래서 둘을 **각자 loop**시키고 위치를 맞추지 않는다 — 맞추면
  /// 길이를 다르게 둔 뜻이 사라진다.
  static String ambiencePath(String? regionCode, String layer) {
    final slug = _musicSlugs[regionCode] ?? 'moss-archive';
    return 'adventure/ambience/$slug-$layer.m4a';
  }

  /// 전투에 들어가면 배경을 2dB 낮춘다(기준 문서 `연속 무대의 적응형 레이어`).
  /// 진폭으로는 약 0.79배다.
  static const _ambienceDuck = 0.79;

  final Future<Map<ExpeditionCombatSound, AudioPool>> _ready;
  final Map<ExpeditionCombatSound, DateTime> _lastPlayedAt = {};

  /// 품종·성장결·엉킴 저마다의 소리. 공용음과 달리 필요할 때 올린다.
  final ExpeditionSignatureAudioCache _signatures =
      ExpeditionSignatureAudioCache(audioContext: _context);

  /// signature도 겹침 방지를 받아야 한다. 공용음은 enum이 키라서 같이 못 쓴다.
  final Map<String, DateTime> _lastSignatureAt = {};
  AudioPlayer _activeMusic = AudioPlayer();
  AudioPlayer _standbyMusic = AudioPlayer();
  final AudioPlayer _ambienceA = AudioPlayer();
  final AudioPlayer _ambienceB = AudioPlayer();
  String? _ambienceRegion;
  ExpeditionMusicState? _musicState;

  /// 지금 울리고 있는 지역 곡. 지역이 바뀌면 재생 세션을 새로 연다.
  String? _musicRegion;
  bool _musicEnabled;
  bool _sfxEnabled;

  /// 앱이 뒤로 갔을 때만 참이다. 사용자가 끈 것과 구분해야 복귀 시 원래 설정을
  /// 그대로 되살릴 수 있다.
  bool _backgrounded = false;
  bool _disposed = false;
  int _transitionGeneration = 0;

  /// 마지막으로 요청받은 지역 음악 음량. 페이드가 이 값을 목표로 돌아온다.
  double _musicVolume = 0.18;

  /// ambience 기준 음량. 마스터가 이미 -28 LUFS로 조용해서 곡보다 조금 낮게
  /// 얹으면 충분하다. 전투에서는 여기에 duck 계수를 곱한다.
  double _ambienceVolume = 0.12;

  /// 효과음이 하나라도 나갈 수 있는 상태인지. 판정·촉각은 이 값과 무관하다.
  bool get _enabled => _sfxEnabled && !_backgrounded;
  bool get _musicPlayable => _musicEnabled && !_backgrounded;

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

  /// 접촉 프레임의 재질 소리. 믹스 우선순위 1순위다.
  ///
  /// 서버가 재질을 알려 주면 그 재질로, 구버전 응답이면 기존 공용 타격음으로
  /// 떨어진다. 약점 적중은 재질 위에 더 조용한 강조음 한 겹만 얹어 같은 순간에
  /// 또렷한 transient가 세 개를 넘지 않게 한다.
  Future<void> playContact({
    String? material,
    bool weakness = false,
    double volume = .72,
  }) async {
    if (_disposed || !_enabled) return;
    final sound = expeditionContactSound(material);
    if (sound == null) {
      await play(
        weakness ? ExpeditionCombatSound.weakness : ExpeditionCombatSound.hit,
        volume: volume,
      );
      return;
    }
    if (!_claimTransient(sound)) return;
    await play(sound, volume: volume);
    if (weakness && !_disposed && _enabled) {
      await Future<void>.delayed(const Duration(milliseconds: 42));
      await play(ExpeditionCombatSound.weakness, volume: volume * .34);
    }
  }

  /// 적 의도 preview — 다음 선택에 필요한 정보라 접촉음 바로 아래 크기다.
  Future<void> playTelegraph(String? material, {double volume = .34}) async {
    final sound = expeditionTelegraphSound(material);
    if (sound == null || !_claimTransient(sound)) return;
    await play(sound, volume: volume);
  }

  /// 엉킴이 풀린 순간의 두 음. stem을 걷은 뒤 한 번만 재생한다.
  Future<void> playRelease(String? regionCode, {double volume = .58}) async {
    final sound = expeditionReleaseSound(regionCode);
    if (!_claimTransient(sound, window: const Duration(milliseconds: 900))) {
      return;
    }
    await play(sound, volume: volume);
  }

  /// 같은 소리가 촘촘히 겹쳐 한 덩어리로 들리는 것을 막는다.
  /// 기준 문서의 `120ms 안에 중복 요청되면 한 번만 재생한다`를 구현한다.
  bool _claimTransient(
    ExpeditionCombatSound sound, {
    Duration window = const Duration(milliseconds: 120),
  }) {
    final now = DateTime.now();
    final last = _lastPlayedAt[sound];
    if (last != null && now.difference(last) < window) return false;
    _lastPlayedAt[sound] = now;
    return true;
  }

  /// 시전자 signature의 재생 이득.
  ///
  /// 마스터가 이미 접촉음보다 낮게 정규화돼 있다(50ms 최대 RMS 0.108 대 접촉
  /// 0.147). 그래서 접촉과 **비슷한 이득으로 틀어야** 기준 문서의 믹스 순서가
  /// 그대로 나온다 — 접촉 0.72×0.147 = 0.106, signature 0.78×0.108 = 0.084.
  /// tier 대체음(RMS 0.374)을 쓰던 시절에는 이 자리가 접촉의 두 배였는데,
  /// 그건 순서표가 1순위로 정한 접촉을 시전음이 덮고 있었다는 뜻이다.
  static const _skillBed = .78;
  static const _skillTop = .88;

  /// 이 스킬만의 소리를 내고, 없으면 tier 대체음으로 떨어진다.
  ///
  /// 소리로 답해야 하는 질문은 `누가 무엇을 했는가`인데 tier 세 종류로는
  /// `얼마나 컸는가`밖에 답하지 못한다. 그래서 코드가 있으면 그 스킬의 음원을
  /// 먼저 쓰고, 아직 만들지 않은 스킬만 tier 대체음을 쓴다. 어느 쪽이든 크기와
  /// 궁극기 강조는 tier가 정한다.
  Future<void> playSkill({
    required String? code,
    required int tier,
    required bool ultimate,
  }) async {
    if (_disposed || !_enabled) return;
    final safeTier = tier.clamp(1, 3);
    final asset = expeditionSkillSignatureAsset(code);
    if (asset == null) {
      await playSkillTier(tier: safeTier, ultimate: ultimate);
      return;
    }
    if (!_claimSignature(asset)) return;
    await _signatures.play(asset, volume: safeTier == 3 ? _skillTop : _skillBed);
    if (safeTier == 3 && ultimate && !_disposed && _enabled) {
      await Future<void>.delayed(const Duration(milliseconds: 56));
      await play(ExpeditionCombatSound.weakness, volume: .20);
    }
  }

  /// 엉킴·수호짐승이 저마다 내는 공격 예고음. 없으면 재질 예고음으로 떨어진다.
  ///
  /// 재질만으로는 `종이 뭉치가 온다`까지만 알 수 있고 열두 엉킴이 셋씩 같은
  /// 소리를 낸다. 개별 signature가 붙으면 어떤 공격인지가 눈을 떼고도 구분된다.
  Future<void> playEnemyAttack({
    required String? code,
    String? material,
    double volume = .34,
  }) async {
    if (_disposed || !_enabled) return;
    final asset = expeditionEnemySignatureAsset(code);
    if (asset == null) {
      await playTelegraph(material, volume: volume);
      return;
    }
    if (!_claimSignature(asset)) return;
    await _signatures.play(asset, volume: volume);
  }

  /// 같은 signature가 120ms 안에 두 번 요청되면 한 번만 낸다.
  bool _claimSignature(String asset) {
    final now = DateTime.now();
    final last = _lastSignatureAt[asset];
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 120)) {
      return false;
    }
    _lastSignatureAt[asset] = now;
    return true;
  }

  /// light/full/signature가 서로 다른 어택·화음·잔향을 사용한다.
  Future<void> playSkillTier({
    required int tier,
    required bool ultimate,
  }) async {
    final safeTier = tier.clamp(1, 3);
    final sound = switch (safeTier) {
      1 => ExpeditionCombatSound.skillLight,
      2 => ExpeditionCombatSound.skillFull,
      _ => ExpeditionCombatSound.skillSignature,
    };
    await play(sound, volume: safeTier == 3 ? .64 : .56);
    if (safeTier == 3 && ultimate && !_disposed && _enabled) {
      await Future<void>.delayed(const Duration(milliseconds: 56));
      await play(ExpeditionCombatSound.weakness, volume: .20);
    }
  }

  Future<void> playBossPhaseBreak() =>
      play(ExpeditionCombatSound.bossPhaseBreak, volume: .68);

  /// 지역 ambience 두 층을 틀거나 지역이 바뀌면 갈아 끼운다.
  ///
  /// 같은 지역이면 다시 시작하지 않는다. 배경이 장면마다 처음으로 돌아가면
  /// 그 순간이 오히려 사건처럼 들린다.
  Future<void> playAmbience(
    String? regionCode, {
    ExpeditionMusicState state = ExpeditionMusicState.base,
    double volume = 0.12,
  }) async {
    if (_disposed || !_musicPlayable) return;
    _ambienceVolume = volume;
    final target = _ambienceLevel(state);
    if (_ambienceRegion == regionCode) {
      // 지역이 그대로면 음량만 옮긴다 — 전투 진입·이탈이 여기로 온다.
      await _setAmbienceVolume(target);
      return;
    }
    try {
      for (final (player, layer) in [(_ambienceA, 'a'), (_ambienceB, 'b')]) {
        await player.setReleaseMode(ReleaseMode.loop);
        await player.play(
          AssetSource(ambiencePath(regionCode, layer)),
          volume: target,
          ctx: _musicContext,
        );
      }
      if (!_disposed) _ambienceRegion = regionCode;
    } on Object {
      // 배경이 안 깔려도 탐험은 계속된다. 소리는 거들 뿐이다.
    }
  }

  double _ambienceLevel(ExpeditionMusicState state) =>
      state == ExpeditionMusicState.base
          ? _ambienceVolume
          : _ambienceVolume * _ambienceDuck;

  Future<void> _setAmbienceVolume(double volume) async {
    if (_ambienceRegion == null) return;
    try {
      await Future.wait([
        _ambienceA.setVolume(volume),
        _ambienceB.setVolume(volume),
      ]);
    } on Object {
      // 볼륨을 못 바꿔도 재생은 유지한다.
    }
  }

  Future<void> stopAmbience() async {
    _ambienceRegion = null;
    try {
      await Future.wait([_ambienceA.stop(), _ambienceB.stop()]);
    } on Object {
      // 이미 멈춰 있으면 할 일이 없다.
    }
  }

  /// 16초 마디를 처음부터 다시 틀지 않고 지역 음악을 시작하거나 교차 전환한다.
  Future<void> playMusic(
    ExpeditionMusicState state, {
    String? regionCode,
    double volume = 0.18,
  }) async {
    if (_disposed || !_musicPlayable) return;
    final regionChanged = _musicRegion != regionCode;
    // 배경은 곡보다 먼저 자리를 잡는다. 곡 상태가 바뀌면 duck도 따라간다.
    await playAmbience(regionCode, state: state, volume: _ambienceVolume);
    if (_musicState == state && !regionChanged) return;
    _musicVolume = volume;
    final generation = ++_transitionGeneration;
    try {
      final path = musicPath(regionCode, state);
      if (_musicState == null) {
        await _activeMusic.setReleaseMode(ReleaseMode.loop);
        await _activeMusic.play(
          AssetSource(path),
          volume: volume,
          ctx: _musicContext,
        );
        if (!_disposed && generation == _transitionGeneration) {
          _musicState = state;
          _musicRegion = regionCode;
        }
        return;
      }

      // 같은 지역 안에서는 재생 위치를 지켜 stem만 갈아 끼운다. 지역이 바뀌면
      // 곡 자체가 달라(BPM·마디가 다름) 위치를 물려받을 수 없으므로 처음부터
      // 시작한다 — 기준 문서가 `지역 pack 교체`만 재생 세션 경계로 둔 이유다.
      final position = regionChanged
          ? Duration.zero
          : await _activeMusic.getCurrentPosition() ?? Duration.zero;
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
      _musicRegion = regionCode;
    } on Object {
      // 음악 로드 실패도 전투 입력과 효과음 재생을 막지 않는다.
    }
  }

  /// 음악과 효과음을 한 번에 켜고 끈다. 기존 단일 토글 호출부의 진입점이다.
  Future<void> setEnabled(bool value) => setChannels(music: value, sfx: value);

  /// 음악·효과음을 따로 조절한다.
  ///
  /// 접근성 기준의 `촉각·음악·효과음을 각각 끌 수 있다`를 만족시킨다. 효과음을
  /// 꺼도 피해·방어·약점은 화면과 촉각으로 그대로 읽힌다.
  Future<void> setChannels({bool? music, bool? sfx}) async {
    if (_disposed) return;
    final nextMusic = music ?? _musicEnabled;
    final nextSfx = sfx ?? _sfxEnabled;
    if (nextMusic == _musicEnabled && nextSfx == _sfxEnabled) return;
    final wasPlayable = _musicPlayable;
    _musicEnabled = nextMusic;
    _sfxEnabled = nextSfx;
    if (wasPlayable == _musicPlayable) return;
    await _applyMusicPlayback(resume: _musicPlayable);
  }

  /// 앱이 뒤로 가면 300ms 동안 줄인 뒤 멈춘다.
  ///
  /// 곧바로 끊으면 다른 앱의 소리 위로 뚝 끊기는 인상이 남는다. 재생 위치는
  /// 유지해 복귀 때 같은 마디에서 이어진다.
  Future<void> handleAppPaused() async {
    if (_disposed || _backgrounded) return;
    _backgrounded = true;
    await _applyMusicPlayback(resume: false);
  }

  /// 복귀하면 500ms에 걸쳐 원래 음량으로 돌아온다.
  Future<void> handleAppResumed() async {
    if (_disposed || !_backgrounded) return;
    _backgrounded = false;
    if (!_musicPlayable) return;
    await _applyMusicPlayback(resume: true);
  }

  Future<void> _applyMusicPlayback({required bool resume}) async {
    final generation = ++_transitionGeneration;
    try {
      if (resume) {
        if (_musicState == null) return;
        // 배경도 함께 돌아온다. 곡만 살아나고 배경이 죽어 있으면 복귀한
        // 장면이 원래보다 얇게 들린다.
        await _resumeAmbience();
        await _activeMusic.setVolume(0);
        await _activeMusic.resume();
        await _fadeActiveMusic(
          from: 0,
          to: _musicVolume,
          duration: foregroundFadeIn,
          generation: generation,
        );
        return;
      }
      await _fadeActiveMusic(
        from: _musicVolume,
        to: 0,
        duration: backgroundFadeOut,
        generation: generation,
      );
      await Future.wait([
        _activeMusic.pause(),
        _standbyMusic.pause(),
        _ambienceA.pause(),
        _ambienceB.pause(),
      ]);
    } on Object {
      // 오디오 장치 상태와 무관하게 설정과 화면은 즉시 바뀐다.
    }
  }

  Future<void> _resumeAmbience() async {
    if (_ambienceRegion == null) return;
    try {
      await Future.wait([_ambienceA.resume(), _ambienceB.resume()]);
      await _setAmbienceVolume(_ambienceLevel(_musicState ?? ExpeditionMusicState.base));
    } on Object {
      // 배경이 안 돌아와도 곡과 판정은 계속된다.
    }
  }

  Future<void> _fadeActiveMusic({
    required double from,
    required double to,
    required Duration duration,
    required int generation,
  }) async {
    final step = Duration(
      milliseconds: (duration.inMilliseconds / _fadeSteps).round(),
    );
    for (var index = 1; index <= _fadeSteps; index++) {
      if (_disposed || generation != _transitionGeneration) return;
      await _activeMusic.setVolume(from + (to - from) * index / _fadeSteps);
      await Future<void>.delayed(step);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    ++_transitionGeneration;
    await _signatures.dispose();
    try {
      final pools = await _ready;
      await Future.wait([
        ...pools.values.map((pool) => pool.dispose()),
        _activeMusic.dispose(),
        _standbyMusic.dispose(),
        _ambienceA.dispose(),
        _ambienceB.dispose(),
      ]);
    } on Object {
      // 초기화가 실패한 플랫폼에서는 해제할 플레이어가 없다.
    }
  }
}
