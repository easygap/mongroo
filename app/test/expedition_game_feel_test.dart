import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/data/expedition_settings_store.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_action_cue.dart';
import 'package:mongroo/features/expedition/presentation/expedition_battle_dock.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_audio.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_effect_catalog.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_overlay.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_hud.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_sprites.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_timeline.dart';
import 'package:mongroo/features/expedition/presentation/expedition_music_mix.dart';
import 'package:mongroo/features/expedition/presentation/expedition_pixel_art.dart';
import 'package:mongroo/features/expedition/presentation/expedition_signature_audio.dart';

ExpeditionBattle _battle({int phase = 1, int hp = 10}) =>
    ExpeditionBattle.fromJson({
      'status': 'active',
      'round': 1,
      'max_rounds': 6,
      'focus': 3,
      'max_focus': 5,
      'enemy_kind': 'guardian',
      'boss_phase': {'index': phase, 'count': 3},
      'enemy': {
        'name': '장부지기',
        'guard': 80,
        'max_guard': 100,
        'intent': {
          'code': 'paper_flurry',
          'name': '종잇장 회오리',
          'target': 'all',
          'target_label': '모든 대원',
          'power': 1
        }
      },
      'party': [
        for (var id = 1; id <= 2; id++)
          {
            'member_id': id,
            'name': '대원$id',
            'hp': hp,
            'max_hp': 10,
            'kit': {
              'basic': {'name': '공격', 'power': 8, 'focus_delta': 1},
              'guard': {'name': '지키기', 'guard': 3, 'focus_delta': 2},
              'selected_skills': [
                {
                  'slot': 'selected_1',
                  'name': '대상 바꾸기',
                  'code': 'relay',
                  'choice_kind': 'member',
                  'choice_options': [
                    {'value': '1', 'label': '대원1에게'},
                    {'value': '2', 'label': '대원2에게'}
                  ]
                }
              ]
            }
          }
      ],
    });

ExpeditionActionCue _cue(
        {bool enemy = false, int damage = 8, bool victory = false}) =>
    ExpeditionActionCue(
        id: 1,
        kind: enemy
            ? ExpeditionActionCueKind.combatEnemy
            : ExpeditionActionCueKind.combatParty,
        actorName: '대원1',
        actorId: 1,
        speciesCode: 'baby-pot',
        speciesName: '뽀또',
        stage: 2,
        form: 'sunny',
        title: '공격',
        effectKey: enemy ? 'enemy_wave' : 'care_vines',
        outcome: '행동 완료',
        combatResult: victory ? 'victory' : null,
        combat: ExpeditionCombatFeedback(
            kind: 'guardian',
            enemyName: '장부지기',
            enemyMaxGuard: 100,
            enemyGuardBefore: 80,
            enemyGuardAfter: enemy ? 80 : 72,
            guardDamage: enemy ? 0 : damage,
            attackName: '파동',
            telegraph: '',
            damageTarget: '대원1',
            counterDamage: enemy ? damage : 0,
            counterResult: enemy ? (damage == 0 ? 'guarded' : 'hit') : 'none',
            effectKey: enemy ? 'enemy_wave' : 'care_vines'));

class _SettingsStorage implements ExpeditionSettingsStorage {
  final readGate = Completer<String?>();
  final writes = <String>[];
  @override
  Future<String?> read() => readGate.future;
  @override
  Future<void> write(String value) async {
    writes.add(value);
  }

  @override
  Future<void> clear() async {}
}

class _Pool implements AudioPool {
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  @override
  Future<StopFunction> start({double volume = 1}) async {
    starts++;
    return () async {
      stops++;
    };
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements AudioPlayer {
  @override
  double volume = 0;
  bool paused = true;
  bool disposed = false;
  String? path;
  Duration? lastPosition;
  int plays = 0;
  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}
  @override
  Future<void> play(Source source,
      {double? volume,
      double? balance,
      AudioContext? ctx,
      Duration? position,
      PlayerMode? mode}) async {
    path = (source as AssetSource).path;
    this.volume = volume ?? this.volume;
    lastPosition = position;
    paused = false;
    plays++;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> stop() async {
    paused = true;
  }

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<Duration?> getCurrentPosition() async => const Duration(seconds: 9);
  @override
  Future<void> dispose() async {
    disposed = true;
    paused = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('피해와 흔들림은 접촉 전 발생하지 않고 방어에는 밀림이 없다', () {
    final cue = _cue();
    final contact = ExpeditionCombatTimeline.partyContactProgress(cue);
    expect(
        ExpeditionCombatTimeline.guardValue(
            before: 80,
            after: 72,
            progress: contact - .001,
            contactProgress: contact),
        80);
    expect(ExpeditionCombatTimeline.partyImpactShake(contact - .001, cue),
        Offset.zero);
    expect(ExpeditionCombatTimeline.hitReaction(contact - .001, contact), 0);
    expect(ExpeditionCombatTimeline.hitReaction(contact, contact), 1);
    final blocked = _cue(enemy: true, damage: 0);
    final enemyContact = ExpeditionCombatTimeline.enemyContactProgress(blocked);
    expect(ExpeditionCombatTimeline.actorOffset(enemyContact + .04, blocked),
        Offset.zero);
    expect(ExpeditionCombatTimeline.impactShake(enemyContact + .04, blocked),
        Offset.zero);
  });

  test('타격 정지는 접촉 한 번만 고정하고 배속에서도 순서와 최종값을 지킨다', () {
    for (final ms in [228, 380, 760]) {
      final cue = _cue(victory: true);
      final curve = ExpeditionImpactCurve(
          cue: cue, motionDuration: Duration(milliseconds: ms));
      final contact = ExpeditionCombatTimeline.partyContactProgress(cue);
      final elapsedAt = contact * ms;
      final total = curve.duration.inMilliseconds;
      expect(
          curve.transform((elapsedAt + 10) / total), closeTo(contact, .000001));
      expect(
          curve.transform((elapsedAt + 60) / total), closeTo(contact, .000001));
      var previous = 0.0;
      for (var frame = 0; frame <= 200; frame++) {
        final current = curve.transform(frame / 200);
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
      expect(previous, 1);
      final reduced = ExpeditionImpactCurve(
          cue: cue,
          motionDuration: Duration(milliseconds: ms),
          reducedMotion: true);
      expect(reduced.duration.inMilliseconds, ms);
      expect(reduced.transform(.4), .4);
    }
  });

  test('이펙트 피벗이 실제 배우 위치를 따르고 하단 HUD가 커져도 비율을 지킨다', () {
    final effect =
        resolveExpeditionCombatEffect(vfxFamily: 'baby-pot.care-vines');
    for (final rect in [
      const Rect.fromLTWH(0, 94, 360, 270),
      const Rect.fromLTWH(0, 56, 720, 500)
    ]) {
      final actor = Offset(rect.width * .3, rect.bottom - 60);
      final enemy = Offset(rect.width * .7, rect.top + 80);
      final box = expeditionEffectRect(effect,
          stageBounds: rect, actor: actor, enemy: enemy);
      expect(box.left + box.width * effect.pivotX, closeTo(actor.dx, .01));
      expect(box.top + box.height * effect.pivotY, closeTo(actor.dy, .01));
      expect(box.width / box.height,
          closeTo(effect.frameWidth / effect.frameHeight, .000001));
      expect(box.height, lessThanOrEqualTo(rect.height));
    }
  });

  test('보스 단계와 위험에서 같은 지역 음악을 서서히 높인다', () {
    final first = expeditionMusicMix(battle: _battle());
    final finalPhase = expeditionMusicMix(battle: _battle(phase: 3));
    final pressured = expeditionMusicMix(battle: _battle(phase: 3, hp: 2));
    expect(finalPhase.state, first.state);
    expect(finalPhase.volume, greaterThan(first.volume));
    expect(pressured.volume, greaterThan(finalPhase.volume));
    expect(pressured.volume, lessThan(.30));
    expect(expeditionMusicMix().state, ExpeditionMusicState.base);
  });

  test('오디오 로드 중 소리를 끄면 이미 요청한 타격음도 나중에 울리지 않는다', () async {
    final gate = Completer<AudioPool>();
    final pool = _Pool();
    final cache = ExpeditionSignatureAudioCache(poolLoader: (_) => gate.future);
    var enabled = true;
    final playing = cache.play('hit', canPlay: () => enabled);
    enabled = false;
    gate.complete(pool);
    await playing;
    expect(pool.starts, 0);
    await cache.dispose();
    expect(pool.disposed, isTrue);
  });

  test('미리 읽기와 재생이 겹쳐도 음원은 한 번만 로드한다', () async {
    var loads = 0;
    final gate = Completer<AudioPool>();
    final pool = _Pool();
    final cache = ExpeditionSignatureAudioCache(poolLoader: (_) {
      loads++;
      return gate.future;
    });
    final ready = cache.preload(['guard', 'guard']);
    final playing = cache.play('guard');
    gate.complete(pool);
    await Future.wait([ready, playing]);
    expect(loads, 1);
    expect(pool.starts, 1);
    await cache.dispose();
  });

  test('음악 전환 도중 음소거와 복귀가 겹쳐도 마지막 요청 하나만 남는다', () async {
    final players = <_Player>[];
    final audio = ExpeditionCombatAudio(
        sfxEnabled: false,
        playerFactory: () {
          final player = _Player();
          players.add(player);
          return player;
        });
    await audio.playMusic(ExpeditionMusicState.base, regionCode: 'echo_well');
    final switching =
        audio.playMusic(ExpeditionMusicState.combat, regionCode: 'echo_well');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final mute = audio.setChannels(music: false);
    final resume = audio.setChannels(music: true);
    final latest = audio.playMusic(ExpeditionMusicState.guardian,
        regionCode: 'echo_well', volume: .25);
    await Future.wait([switching, mute, resume, latest]);
    final music = players.take(2).where((p) => !p.paused).toList();
    expect(music, hasLength(1));
    expect(music.single.path, endsWith('echo-well-guardian.m4a'));
    expect(music.single.lastPosition, const Duration(seconds: 9));
    expect(music.single.volume, closeTo(.25, .001));
    final plays = music.single.plays;
    await audio.playMusic(ExpeditionMusicState.guardian,
        regionCode: 'echo_well', volume: .27);
    expect(music.single.plays, plays);
    expect(music.single.volume, closeTo(.27, .001));
    await audio.handleAppPaused();
    expect(players.every((p) => p.paused), isTrue);
    await audio.dispose();
    expect(players.every((p) => p.disposed), isTrue);
  });

  test('설정 복원 중 바꾼 음량과 자동 전투를 늦은 저장값이 덮지 않는다', () async {
    final storage = _SettingsStorage();
    final scope = ProviderContainer(overrides: [
      expeditionSettingsStorageProvider.overrideWithValue(storage)
    ]);
    final settings = scope.read(expeditionBattleSettingsProvider.notifier);
    settings.cycleAudioMode();
    settings.cycleAutoMode();
    storage.readGate.complete(const ExpeditionBattleSettings().encode());
    await Future<void>.delayed(Duration.zero);
    expect(scope.read(expeditionBattleSettingsProvider).audioMode,
        ExpeditionAudioMode.sfxOnly);
    expect(scope.read(expeditionBattleSettingsProvider).autoMode,
        ExpeditionAutoMode.assist);
    expect(ExpeditionBattleSettings.decode(storage.writes.last).audioMode,
        ExpeditionAudioMode.sfxOnly);
    scope.dispose();
  });

  Future<ProviderContainer> pumpDock(WidgetTester tester,
      Future<bool> Function(ExpeditionCombatCommand) submit,
      {Map<int, int> presentedHp = const {}}) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _SettingsStorage()
      ..readGate.complete(
          const ExpeditionBattleSettings(audioMode: ExpeditionAudioMode.muted)
              .encode());
    await tester.pumpWidget(ProviderScope(
      overrides: [expeditionSettingsStorageProvider.overrideWithValue(storage)],
      child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
              body: ExpeditionSequentialCommandDock(
                  battle: _battle(),
                  members: const [],
                  locked: false,
                  fingerprintSeed: 'test:1',
                  selectedMemberId: 1,
                  presentedHp: presentedHp,
                  onSelectMember: (_) {},
                  onSubmit: submit))),
    ));
    await tester.pump();
    return ProviderScope.containerOf(
        tester.element(find.byType(ExpeditionSequentialCommandDock)));
  }

  testWidgets('자동 전투를 켜면 즉시 예약하고 시트가 열리면 멈췄다가 재개한다', (tester) async {
    var calls = 0;
    final scope = await pumpDock(tester, (_) async {
      calls++;
      return true;
    });
    scope.read(expeditionBattleSettingsProvider.notifier).cycleAutoMode();
    await tester.pump();
    scope.read(expeditionAutoPauseProvider.notifier).state++;
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, 0);
    scope.read(expeditionAutoPauseProvider.notifier).state--;
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, 1);
    expect(scope.read(expeditionBattleSettingsProvider).autoMode,
        ExpeditionAutoMode.off);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('명령 응답을 기다리는 동안 연타와 키 반복은 중복 제출하지 않는다', (tester) async {
    var calls = 0;
    final gate = Completer<bool>();
    await pumpDock(tester, (_) {
      calls++;
      return gate.future;
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(find.text('공격 준비 중…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.tap(find.byKey(const ValueKey('seq-dock-card-attack')));
    expect(calls, 1);
    gate.complete(true);
    await tester.pump();
    expect(find.text('공격 준비 중…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('대상 선택창을 취소하면 기술도 자동 행동도 소비하지 않는다', (tester) async {
    var calls = 0;
    await pumpDock(tester, (_) async {
      calls++;
      return true;
    });
    await tester.tap(find.byKey(const ValueKey('seq-dock-card-selected_1')));
    await tester.pumpAndSettle();
    expect(find.text('대원2에게'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, 0);
    final sheet = tester.element(find.text('대원2에게'));
    Navigator.of(sheet).pop();
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('seq-dock-card-attack')));
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('장벽 수치는 접촉 순간 확정값으로 바뀌고 감소한 구간만 여운을 남긴다', (tester) async {
    Future<void> show(double progress) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: ExpeditionEnemyGuardHud(
          enemyName: '장부지기',
          maxGuard: 100,
          before: 80,
          after: 72,
          progress: progress,
          contactProgress: .3,
        ))));
    await show(.299);
    expect(find.text('80/100'), findsOneWidget);
    for (final bar in find.byType(PixelBar).evaluate()) {
      expect((bar.renderObject as RenderBox).size.width, greaterThan(100),
          reason: '체력 막대가 Stack 안에서 너비 0으로 사라지면 안 된다.');
    }
    await show(.3);
    expect(find.text('72/100'), findsOneWidget);
    expect(ExpeditionCombatTimeline.damageOpacity(.3, .3), 1);
  });

  testWidgets('명령판은 연출의 피격 체력을 표시하고 기존 전투 스냅숏은 보존한다', (tester) async {
    await pumpDock(tester, (_) async => true, presentedHp: {1: 2});
    expect(find.text('2/10'), findsOneWidget);
    expect(find.text('10/10'), findsOneWidget);
    final dock = tester.widget<ExpeditionSequentialCommandDock>(
        find.byType(ExpeditionSequentialCommandDock));
    expect(dock.battle.party.first.hp, 10);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('적 접촉 통지는 히트 정지 중에도 한 번만 발생한다', (tester) async {
    var contacts = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: Stack(children: [
          ExpeditionEncounterStage(
              encounter: null,
              actor: null,
              cue: _cue(enemy: true),
              audioMode: ExpeditionAudioMode.muted,
              onContact: (_) => contacts++,
              onCueCompleted: () {})
        ]))));
    await tester.pump();
    expect(contacts, 0);
    for (var frame = 0; frame < 75; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(contacts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('움직임 줄이기에서도 실제 피해 숫자는 보이는 상태로 남는다', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
                body: Stack(children: [
              ExpeditionEncounterStage(
                  encounter: null,
                  actor: null,
                  cue: _cue(),
                  audioMode: ExpeditionAudioMode.muted,
                  onCueCompleted: () {})
            ])))));
    await tester.pump(const Duration(milliseconds: 2));
    final number = tester
        .widget<ExpeditionDamageNumber>(find.byType(ExpeditionDamageNumber));
    expect(number.label, '-8');
    expect(number.opacity, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
