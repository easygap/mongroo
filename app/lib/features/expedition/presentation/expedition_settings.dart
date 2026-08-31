import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/expedition_settings_store.dart';
import 'expedition_combat_audio.dart';

/// AUTO의 두 단계. `보조`는 다음 한 행동만 맡기고 꺼지며, `연속`은 전투가
/// 끝날 때까지 유지된다. 수동 지휘 계약의 보조/연속 구분을 그대로 옮겼다.
enum ExpeditionAutoMode { off, assist, continuous }

class ExpeditionBattleSettings {
  const ExpeditionBattleSettings({
    this.autoMode = ExpeditionAutoMode.off,
    this.pace = 1,
    this.shortEffects = false,
    this.audioMode = ExpeditionAudioMode.all,
  });

  final ExpeditionAutoMode autoMode;

  /// 연출 배속(1 또는 2). 판정·프레임 스킵 없이 타임라인만 줄인다.
  final int pace;

  /// 짧은 연출 모드. 시동·여운을 줄이되 판정 정보는 유지한다.
  final bool shortEffects;

  /// 음악·효과음 조합. 어느 단계에서도 판정 정보는 시각·촉각으로 남는다.
  final ExpeditionAudioMode audioMode;

  bool get musicEnabled => audioMode == ExpeditionAudioMode.all;
  bool get sfxEnabled => audioMode != ExpeditionAudioMode.muted;

  /// 소리가 하나라도 나는지 — 기존 단일 토글 호출부가 읽는 값이다.
  bool get audioEnabled => audioMode != ExpeditionAudioMode.muted;

  String get audioLabel => switch (audioMode) {
        ExpeditionAudioMode.all => '음악·효과음',
        ExpeditionAudioMode.sfxOnly => '효과음만',
        ExpeditionAudioMode.muted => '소리 꺼짐',
      };

  ExpeditionBattleSettings copyWith({
    ExpeditionAutoMode? autoMode,
    int? pace,
    bool? shortEffects,
    ExpeditionAudioMode? audioMode,
  }) =>
      ExpeditionBattleSettings(
        autoMode: autoMode ?? this.autoMode,
        pace: pace ?? this.pace,
        shortEffects: shortEffects ?? this.shortEffects,
        audioMode: audioMode ?? this.audioMode,
      );

  static const _schemaVersion = 1;

  /// 기기에 남길 설정만 직렬화한다.
  ///
  /// **AUTO는 일부러 저장하지 않는다.** 품질 기준이 `자동 지휘는 초기 OFF`를
  /// 요구한다 — 지난번에 켜 뒀다는 이유로 이번 전투를 앱이 대신 지휘하기
  /// 시작하면, 사용자가 조작하지 않은 사이에 결과가 확정된다.
  String encode() => jsonEncode({
        'schema_version': _schemaVersion,
        'audio_mode': audioMode.name,
        'pace': pace,
        'short_effects': shortEffects,
      });

  /// 저장된 문자열을 설정으로 되돌린다. 알 수 없는 값은 기본값으로 떨어진다.
  factory ExpeditionBattleSettings.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        decoded['schema_version'] != _schemaVersion) {
      throw const FormatException('지원하지 않는 전투 설정입니다.');
    }
    final rawMode = decoded['audio_mode'] as String?;
    final rawPace = decoded['pace'];
    return ExpeditionBattleSettings(
      audioMode: ExpeditionAudioMode.values
              .where((mode) => mode.name == rawMode)
              .firstOrNull ??
          ExpeditionAudioMode.all,
      // 배속은 1과 2만 있다. 저장값이 깨져도 판정이 바뀌지 않게 좁힌다.
      pace: rawPace == 2 ? 2 : 1,
      shortEffects: decoded['short_effects'] == true,
    );
  }
}

class ExpeditionBattleSettingsNotifier
    extends Notifier<ExpeditionBattleSettings> {
  /// 저장된 설정을 다 읽기 전에는 저장하지 않는다. 앱을 켜자마자 기본값으로
  /// 덮어써 지난 선택을 지우는 일을 막는다.
  bool _restored = false;

  @override
  ExpeditionBattleSettings build() {
    unawaited(_restore());
    return const ExpeditionBattleSettings();
  }

  Future<void> _restore() async {
    final encoded = await ref.read(expeditionSettingsStoreProvider).load();
    if (encoded != null) {
      try {
        // AUTO는 저장하지 않으므로 되살린 뒤에도 항상 꺼진 상태로 시작한다.
        state = ExpeditionBattleSettings.decode(encoded);
      } on Object {
        // 이전 스키마나 손상된 값이면 기본 설정으로 계속 진행한다.
      }
    }
    _restored = true;
  }

  void _persist() {
    if (!_restored) return;
    unawaited(ref.read(expeditionSettingsStoreProvider).save(state.encode()));
  }

  void cycleAutoMode() {
    state = state.copyWith(
      autoMode: switch (state.autoMode) {
        ExpeditionAutoMode.off => ExpeditionAutoMode.assist,
        ExpeditionAutoMode.assist => ExpeditionAutoMode.continuous,
        ExpeditionAutoMode.continuous => ExpeditionAutoMode.off,
      },
    );
  }

  void finishAssist() {
    if (state.autoMode == ExpeditionAutoMode.assist) {
      state = state.copyWith(autoMode: ExpeditionAutoMode.off);
    }
  }

  void togglePace() {
    state = state.copyWith(pace: state.pace == 1 ? 2 : 1);
    _persist();
  }

  void toggleShortEffects() {
    state = state.copyWith(shortEffects: !state.shortEffects);
    _persist();
  }

  /// 음악·효과음 → 효과음만 → 소리 꺼짐 순으로 돈다.
  void cycleAudioMode() {
    state = state.copyWith(
      audioMode: switch (state.audioMode) {
        ExpeditionAudioMode.all => ExpeditionAudioMode.sfxOnly,
        ExpeditionAudioMode.sfxOnly => ExpeditionAudioMode.muted,
        ExpeditionAudioMode.muted => ExpeditionAudioMode.all,
      },
    );
    _persist();
  }
}

/// 전투 표준 장비(AUTO·배속·짧은 연출·소리) 상태.
/// 소리·배속·짧은 연출은 기기에 남고, AUTO만 매번 꺼진 채로 시작한다.
/// 계정 간 동기화는 서버 설정과 함께 붙일 때까지 미룬다.
///
/// 이름은 전투에서 시작했지만 `audioMode`가 다스리는 범위는 그보다 넓다 —
/// 던전 발걸음, 지도 확정음, 모험 탭 cue, 발견음이 모두 이 값을 읽는다.
/// 그래서 계정 화면에서도 같은 provider를 본다. 전투에 들어가야만 끌 수 있는
/// 소리는 접근성 기준의 `음악·효과음을 각각 끌 수 있다`를 만족하지 못한다.
final expeditionBattleSettingsProvider = NotifierProvider<
    ExpeditionBattleSettingsNotifier, ExpeditionBattleSettings>(
  ExpeditionBattleSettingsNotifier.new,
);
