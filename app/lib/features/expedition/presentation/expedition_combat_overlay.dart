import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/text/korean_particles.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/expedition_models.dart';
import 'expedition_action_cue.dart';
import 'expedition_combat_audio.dart';
import 'expedition_combat_effect_catalog.dart';
import 'expedition_combat_effects.dart';
import 'expedition_combat_hud.dart';
import 'expedition_combat_sprites.dart';
import 'expedition_combat_timeline.dart';
import 'expedition_music_mix.dart';
import 'expedition_pixel_art.dart';
import 'expedition_pixel_sprites.dart';

/// 탐험 결과를 짧은 전투 연출로 보여 주는 도트 무대다.
///
/// 서버가 계산한 [ExpeditionActionCue]를 재생할 뿐 판정을 다시 계산하지 않는다.
/// 배경, 캐릭터, 적, 이펙트, HUD는 서로 다른 갱신·리페인트 경계를 사용해
/// 한 애니메이션이 정적인 레이어까지 다시 그리지 않도록 구성한다.
///
/// 무대의 문법은 포켓몬식 대치다 — 적은 오른쪽 위 제 자리에, 우리 편은 왼쪽
/// 아래에 서고, 행동 대원이 앞에 나온다. 모든 그림은 같은 정수 배율의 도트다.
class ExpeditionEncounterStage extends StatefulWidget {
  const ExpeditionEncounterStage({
    super.key,
    required this.encounter,
    this.battle,
    this.regionCode,
    this.guardianCode,
    required this.actor,
    this.party = const [],
    required this.cue,
    required this.onCueCompleted,
    this.paceScale = 1.0,
    this.shortEffects = false,
    this.audioMode = ExpeditionAudioMode.all,
    this.ownsMusic = true,
    this.bottomHudInset = 0,
    this.topHudInset = 0,
    this.onContact,
  });

  final ExpeditionEncounter? encounter;
  final ExpeditionBattle? battle;
  final String? regionCode;

  /// 수호짐승 코드(`ledger_keeper` 등). 합동 수호전이 넘긴다. 없으면 지역의
  /// 수호짐승으로 떨어진다.
  final String? guardianCode;
  final ExpeditionMember? actor;
  final List<ExpeditionMember> party;
  final ExpeditionActionCue? cue;
  final VoidCallback onCueCompleted;
  final ValueChanged<ExpeditionActionCue>? onContact;

  /// 연출 배속. 2.0이면 같은 타임라인을 절반 시간에 재생한다.
  /// 프레임을 건너뛰지 않고 판정 결과도 바꾸지 않는다.
  final double paceScale;

  /// 짧은 연출 모드. 시동·여운 구간을 약 40% 줄이되 판정 정보(행동·피해·
  /// 승패)는 전부 유지한다. `disableAnimations` 접근성 설정과는 독립이다.
  final bool shortEffects;

  /// 음악·효과음 단계. 어느 단계에서도 시각·촉각 판정은 그대로 남는다.
  final ExpeditionAudioMode audioMode;

  /// 이 전장이 지역 음악까지 드는가.
  ///
  /// 탐험 스테이지에서는 화면 쪽이 들고 있어서 `false`다 — 전장이 들면 전투가
  /// 끝나 위젯이 사라질 때마다 곡이 함께 죽는다. 합동 수호전처럼 전장 하나가
  /// 곧 한 판인 화면은 그대로 자기가 든다.
  final bool ownsMusic;

  bool get audioEnabled => audioMode != ExpeditionAudioMode.muted;

  /// 전장을 줄이지 않고 가장자리 명령 HUD가 차지하는 하단 영역만 피한다.
  final double bottomHudInset;

  /// 상단 바가 한 줄보다 길어진 만큼. 좁은 화면에서 조작이 아랫줄로 내려가면
  /// 그만큼 장벽 HUD도 같이 내려가야 서로 겹치지 않는다.
  final double topHudInset;

  @override
  State<ExpeditionEncounterStage> createState() =>
      _ExpeditionEncounterStageState();
}

/// 무대 위 배우들의 자리. 무대 크기 비율로 두고 배율은 따로 곱한다.
///
/// 배치는 포켓몬·최근 도트 RPG의 대치 문법을 따른다 — 적은 오른쪽 위 제
/// 자리에, 우리 편은 왼쪽 아래에 서고 행동 대원이 맨 앞이다. 하단 명령 독이
/// 덮는 만큼([ExpeditionEncounterStage.bottomHudInset])은 무대에서 뺀다.
class _StageLayout {
  _StageLayout({
    required Size size,
    required double topInset,
    required double bottomInset,
    required this.unit,
  })  : usableTop = 56 + topInset,
        usableBottom = math.max(220, size.height - bottomInset),
        width = size.width {
    final usable = usableBottom - usableTop;
    enemyFoot = Offset(
      _snapValue(width * .70),
      _snapValue(usableTop + usable * .52),
    );
    actorFoot = Offset(
      _snapValue(width * .30),
      _snapValue(usableBottom - unit * 3),
    );
    backlineFeet = [
      Offset(_snapValue(width * .12), _snapValue(actorFoot.dy - unit * 12)),
      Offset(_snapValue(width * .03), _snapValue(actorFoot.dy - unit * 24)),
    ];
  }

  final double unit;
  final double width;
  final double usableTop;
  final double usableBottom;
  late final Offset enemyFoot;
  late final Offset actorFoot;
  late final List<Offset> backlineFeet;

  double _snapValue(double value) => (value / unit).round() * unit;

  Offset snap(Offset offset) =>
      Offset(_snapValue(offset.dx), _snapValue(offset.dy));
}

class _ExpeditionEncounterStageState extends State<ExpeditionEncounterStage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _actionController;
  late Animation<double> _presentation;
  late final AnimationController _ambientController;
  late final ExpeditionCombatAudio _audio;
  Timer? _holdTimer;
  int? _playingCueId;
  double _previousProgress = 0;
  String? _precacheSignature;
  String? _effectPrecacheSignature;
  String? _telegraphSignature;

  @override
  void initState() {
    super.initState();
    _actionController = AnimationController(vsync: this)
      ..addListener(_handleTimelineFeedback)
      ..addStatusListener(_handleActionStatus);
    _presentation = _actionController;
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _audio = ExpeditionCombatAudio(
      musicEnabled:
          widget.ownsMusic && widget.audioMode == ExpeditionAudioMode.all,
      sfxEnabled: widget.audioEnabled,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  /// 앱이 뒤로 가면 음악을 300ms 동안 줄여 멈추고, 복귀하면 같은 재생 위치에서
  /// 500ms에 걸쳐 돌아온다. 다른 앱의 소리를 갑자기 자르지 않기 위해서다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Effects must also stay silent while the app is in the background.
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_audio.handleAppResumed());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_audio.handleAppPaused());
    }
  }

  /// 배속·짧은 연출을 하나의 시간 배율로 합친다. 승리·패배 프레임은
  /// 배속에서도 읽을 시간을 지키도록 호출부에서 하한을 둔다.
  Duration _scaled(Duration duration, {int floorMs = 1}) {
    final multiplier =
        (widget.shortEffects ? .6 : 1.0) / widget.paceScale.clamp(1.0, 3.0);
    final scaled = (duration.inMilliseconds * multiplier).round();
    return Duration(milliseconds: scaled < floorMs ? floorMs : scaled);
  }

  void _handleActionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || widget.cue == null) return;
    _holdTimer?.cancel();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final cue = widget.cue!;
    final holdDuration = reduceMotion
        ? cue.isCombatRound
            ? ExpeditionCombatTimeline.reducedMotionCommandHoldDuration
            : ExpeditionCombatTimeline.reducedMotionResultHoldDuration
        : cue.isCombatRound
            ? cue.isTerminalCombatOutcome
                ? _scaled(
                    ExpeditionCombatTimeline.terminalOutcomeHoldDuration,
                    floorMs: 700,
                  )
                : cue.playsEnemyAttack
                    ? _scaled(ExpeditionCombatTimeline.enemyHoldDuration)
                    : _scaled(ExpeditionCombatTimeline.commandHoldDuration)
            : _scaled(ExpeditionCombatTimeline.resultHoldDuration);
    _holdTimer = Timer(
      holdDuration,
      () {
        if (mounted && widget.cue?.id == _playingCueId) {
          widget.onCueCompleted();
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheEnemyImages();
    _precacheRelevantEffects();
    _warmUpAudio();
    _syncMusic();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ambientController
        ..stop()
        ..value = .5;
    } else if (!_ambientController.isAnimating) {
      _ambientController.repeat();
    }
    _playTelegraphIfNeeded();
    _playCueIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ExpeditionEncounterStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.battle?.enemyKind != widget.battle?.enemyKind ||
        oldWidget.battle?.wave?.code != widget.battle?.wave?.code ||
        oldWidget.guardianCode != widget.guardianCode) {
      _precacheEnemyImages();
    }
    _precacheRelevantEffects();
    _warmUpAudio();
    if (oldWidget.audioMode != widget.audioMode) {
      unawaited(_applyAudioMode());
    }
    _syncMusic();
    _playTelegraphIfNeeded();
    if (oldWidget.cue?.id != widget.cue?.id) {
      _playCueIfNeeded();
    }
  }

  Future<void> _applyAudioMode() async {
    await _audio.setChannels(
      music: widget.ownsMusic && widget.audioMode == ExpeditionAudioMode.all,
      sfx: widget.audioEnabled,
    );
    if (!mounted) return;
    // 효과음만으로 입장한 경우에는 아직 재개할 BGM 상태가 없다. 채널 전환이
    // 끝난 뒤 현재 전장 stem을 새로 동기화해야 음악을 켠 즉시 재생된다.
    _syncMusic();
    _warmUpAudio();
    _playTelegraphIfNeeded();
  }

  /// 새 예고가 걸리면 무엇이 날아올지 짧게 들려준다.
  ///
  /// 예고는 화면을 보지 않아도 다음 선택을 정할 수 있게 하는 정보라 라운드마다
  /// 한 번만, 접촉음보다 조용하게 낸다. 예고에는 촉각을 쓰지 않는다 —
  /// 사용자가 조작하지 않은 순간에 진동을 만들지 않기 위해서다.
  void _playTelegraphIfNeeded() {
    final battle = widget.battle;
    if (battle == null || !widget.audioEnabled) return;
    // 연출이 도는 동안에는 접촉 결과가 우선이라 예고를 겹치지 않는다.
    if (widget.cue != null) return;
    final signature = '${battle.round}:${battle.enemy.intent.code}';
    if (signature == _telegraphSignature) return;
    _telegraphSignature = signature;
    unawaited(
      _audio.playEnemyAttack(
        code: battle.enemy.intent.code,
        material: battle.enemy.intent.contactMaterial,
      ),
    );
  }

  void _syncMusic() {
    if (!widget.ownsMusic) return;
    if (widget.audioMode != ExpeditionAudioMode.all) return;
    final mix = expeditionMusicMix(
        battle: widget.battle,
        guardianEncounter: widget.encounter?.kind == 'guardian');
    final regionCode = widget.regionCode ?? widget.battle?.regionCode;
    // 지역마다 다른 곡을 쓴다. 지역을 모르는 구버전 응답은 첫 지역 곡으로
    // 떨어지므로 무음이 되지 않는다.
    unawaited(
      _audio.playMusic(mix.state, regionCode: regionCode, volume: mix.volume),
    );
  }

  void _warmUpAudio() {
    final battle = widget.battle;
    final member = battle?.party
            .where((m) => m.memberId == widget.actor?.id)
            .firstOrNull ??
        battle?.party.firstOrNull;
    unawaited(_audio.warmUp(
      sounds: {
        ExpeditionCombatSound.hit,
        ExpeditionCombatSound.weakness,
        ExpeditionCombatSound.guard,
        ExpeditionCombatSound.contactGuard,
        ExpeditionCombatSound.victory,
        ExpeditionCombatSound.defeat,
        ExpeditionCombatSound.skillLight,
        ExpeditionCombatSound.skillFull,
        ExpeditionCombatSound.skillSignature,
        ExpeditionCombatSound.bossPhaseBreak,
        expeditionReleaseSound(widget.regionCode ?? battle?.regionCode),
        if (expeditionContactSound(battle?.enemy.intent.contactMaterial)
            case final sound?)
          sound,
        if (expeditionContactSound(widget.cue?.contactMaterial)
            case final sound?)
          sound,
      },
      skillCodes: member == null
          ? const []
          : [
              member.kit.basic.code,
              for (final skill in member.kit.combatSkills)
                if (skill.available) skill.code,
            ],
      enemyCodes: [battle?.enemy.intent.code],
    ));
  }

  String get _enemyAsset => expeditionPixelEnemyAsset(
        enemyKind: widget.battle?.enemyKind ?? 'guardian',
        enemyCode: widget.battle?.wave?.code ?? '',
        guardianCode: widget.guardianCode,
        regionCode: widget.regionCode ?? widget.battle?.regionCode,
      );

  void _precacheEnemyImages() {
    final asset = _enemyAsset;
    if (_precacheSignature == asset) return;
    _precacheSignature = asset;
    // 디코드는 첫 공격보다 먼저 시작하되 화면 진입은 기다리지 않는다.
    for (final pose in ['idle', 'attack', 'hit', 'release', 'defeated']) {
      final artwork = expeditionEnemyPoseAsset(asset, pose);
      precacheImage(
        ResizeImage.resizeIfNeeded(
          artwork.endsWith('.webp') ? 512 : null,
          null,
          AssetImage(artwork),
        ),
        context,
      ).ignore();
    }
  }

  void _precacheRelevantEffects() {
    final battle = widget.battle;
    final firstFrames = <String, ExpeditionCombatEffectSpec>{};
    final fullSequences = <String, ExpeditionCombatEffectSpec>{};

    void addFirstFrame({
      String? vfxFamily,
      String? kelFallbackFamily,
      String? effectKey,
    }) {
      final effect = resolveExpeditionCombatEffect(
        vfxFamily: vfxFamily,
        kelFallbackFamily: kelFallbackFamily,
        legacyEffectKey: effectKey,
      );
      firstFrames[effect.family] = effect;
    }

    if (battle != null) {
      final intent = battle.enemy.intent;
      final enemyEffect = resolveExpeditionCombatEffect(
        vfxFamily: intent.vfxFamily,
        kelFallbackFamily: intent.kelFallbackFamily,
        legacyEffectKey: intent.effectKey,
      );
      // 다음 적 행동은 예고가 노출되는 동안 전 프레임을 디코드한다. 아군은
      // 선택 전 첫 프레임만 준비하고, 실제 선택 뒤 나머지를 병렬로 올린다.
      fullSequences[enemyEffect.family] = enemyEffect;
      for (final member in battle.party) {
        for (final action in <ExpeditionBattleAction>[
          member.kit.basic,
          ...member.kit.combatSkills,
          member.kit.guard,
        ]) {
          if (!action.available) continue;
          addFirstFrame(
            vfxFamily: action.vfxFamily,
            kelFallbackFamily: action.kelFallbackFamily,
            effectKey: action.effectKey,
          );
        }
      }
    } else if (widget.encounter?.kind == 'guardian') {
      for (final effectKey in const ['ledger_claw', 'enemy_wave']) {
        final effect = expeditionCombatEffectForKey(effectKey);
        fullSequences[effect.family] = effect;
      }
    }

    final firstFamilies = firstFrames.keys.toList()..sort();
    final fullFamilies = fullSequences.keys.toList()..sort();
    final signature = '${firstFamilies.join(',')}|${fullFamilies.join(',')}';
    if (_effectPrecacheSignature == signature) return;
    _effectPrecacheSignature = signature;

    for (final effect in {...firstFrames.values, ...fullSequences.values}) {
      final assets = fullSequences.containsKey(effect.family)
          ? expeditionCombatEffectAssetsFor(effect)
          : [effect.asset(0)];
      for (final asset in assets) {
        precacheImage(
                ResizeImage(AssetImage(asset),
                    width: math.max(96, effect.frameWidth ~/ 4)),
                context)
            .ignore();
      }
    }
  }

  Future<void> _precacheCueEffects(ExpeditionActionCue cue) async {
    final effects = {
      if (cue.playsPartyEffect) cue.partyEffect,
      if (cue.playsPartyEffect && cue.fusionEffect != null) cue.fusionEffect!,
      if (cue.playsEnemyAttack) cue.enemyEffect,
    };
    await Future.wait<void>([
      for (final effect in effects)
        for (final asset in expeditionCombatEffectAssetsFor(effect))
          precacheImage(
              ResizeImage(AssetImage(asset),
                  width: math.max(96, effect.frameWidth ~/ 4)),
              context),
    ]);
  }

  void _playCueIfNeeded() {
    final cue = widget.cue;
    if (cue == null || cue.id == _playingCueId) return;
    _playingCueId = cue.id;
    _previousProgress = 0;
    _holdTimer?.cancel();
    _actionController
      ..stop()
      ..value = 0;
    // 수호전은 명령을 고르는 동안 필요한 시퀀스를 먼저 디코드한다. 이벤트
    // 스킬처럼 바로 들어온 큐도 재생과 병렬로 나머지 프레임을 캐시에 올린다.
    unawaited(_precacheCueEffects(cue));
    final serverMotionMs = cue.motion?.totalMs ?? 0;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 1)
        : cue.isCombatRound && serverMotionMs > 0
            ? _scaled(Duration(milliseconds: serverMotionMs))
            : cue.isCombatRound
                ? cue.playsEnemyAttack
                    ? _scaled(ExpeditionCombatTimeline.enemyCommandDuration)
                    : _scaled(ExpeditionCombatTimeline.partyCommandDuration)
                : cue.isGuardianExchange
                    ? _scaled(ExpeditionCombatTimeline.guardianDuration)
                    : _scaled(ExpeditionCombatTimeline.skillDuration);
    final impact = ExpeditionImpactCurve(
      cue: cue,
      motionDuration: motionDuration,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
    _presentation = _actionController.drive(CurveTween(curve: impact));
    _actionController.duration = impact.duration;
    _actionController.forward(from: 0);
    if (cue.isBossPhase) {
      unawaited(_audio.playBossPhaseBreak());
    } else if (cue.isCombatRound) {
      if (cue.playsEnemyAttack) {
        // 적이 무엇을 날리는지 행동 시작에 먼저 들려주고, 실제 충돌음은
        // contact frame까지 미룬다. 두 소리를 분리해야 예고가 판정 정보가 된다.
        unawaited(
          _audio.playEnemyAttack(
            code: cue.skillCode,
            material: cue.contactMaterial,
          ),
        );
      } else if (cue.effectKey != 'safe_guard') {
        unawaited(
          _audio.playSkill(
            code: cue.skillCode,
            tier: cue.presentationTier,
            ultimate: cue.cameraProfile == 'ultimate',
          ),
        );
      }
    }
  }

  void _handleTimelineFeedback() {
    final cue = widget.cue;
    if (cue?.isGuardianExchange != true) {
      _previousProgress = _presentation.value;
      return;
    }
    final progress = _presentation.value;
    final partyContact = ExpeditionCombatTimeline.partyContactProgress(cue!);
    if (cue.playsPartyAttack &&
        cue.effectKey == 'safe_guard' &&
        _previousProgress < partyContact &&
        progress >= partyContact) {
      HapticFeedback.selectionClick();
      unawaited(_audio.play(ExpeditionCombatSound.guard, volume: .54));
    }
    if (cue.dealsGuardianDamage &&
        _previousProgress < partyContact &&
        progress >= partyContact) {
      HapticFeedback.lightImpact();
      // 우리 공격이 엉킴 몸체에 닿는 순간 — 무엇에 닿았는지를 재질로 들려준다.
      unawaited(
        _audio.playContact(
          material: cue.contactMaterial,
          weakness: cue.weaknessHit,
          volume: cue.weaknessHit ? .78 : .66,
        ),
      );
      // 이 타격으로 엉킴이 풀렸다면 접촉음이 지나간 뒤 두 음을 얹는다.
      // 무찌른 소리가 아니라 제자리로 돌아가는 소리라 팡파르를 쓰지 않는다.
      final releaseRegion = cue.releaseRegionCode;
      if (releaseRegion != null) {
        unawaited(
          Future<void>.delayed(
            _scaled(const Duration(milliseconds: 320), floorMs: 100),
            () {
              if (mounted && widget.cue?.id == cue.id) {
                return _audio.playRelease(releaseRegion);
              }
            },
          ),
        );
      }
    }
    if (cue.isTerminalCombatOutcome &&
        _previousProgress < .86 &&
        progress >= .86) {
      if (cue.combatResult == 'victory') {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.heavyImpact();
      }
      // 엉킴 전투는 contact 뒤 예약한 지역별 풀려남 cadence가 결과음 역할을 한다.
      // 수호자 승리와 패배만 기존 판정음을 사용해 짧은 소리가 겹치지 않게 한다.
      if (cue.releaseRegionCode == null || cue.combatResult != 'victory') {
        unawaited(
          _audio.play(
            cue.combatResult == 'victory'
                ? ExpeditionCombatSound.victory
                : ExpeditionCombatSound.defeat,
            volume: .82,
          ),
        );
      }
    }
    final enemyContact = ExpeditionCombatTimeline.enemyContactProgress(cue);
    if (cue.playsEnemyAttack &&
        _previousProgress < enemyContact &&
        progress >= enemyContact) {
      widget.onContact?.call(cue);
      final blocked = (cue.combat?.counterDamage ?? 0) == 0;
      if (blocked) {
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.mediumImpact();
      }
      // 맞은 순간은 날아온 물건의 재질, 받아 낸 순간은 우리 방어의 소리다.
      unawaited(
        _audio.playContact(
          material: cue.enemyContactMaterial,
          volume: blocked ? .58 : .76,
        ),
      );
    }
    _previousProgress = progress;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holdTimer?.cancel();
    _actionController.dispose();
    _ambientController.dispose();
    unawaited(_audio.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cue = widget.cue;
    final encounter = widget.encounter;
    final battle = widget.battle;
    if (cue == null &&
        encounter == null &&
        battle == null &&
        widget.actor == null) {
      return const SizedBox.shrink();
    }

    final combat = cue?.combat;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final guardianActive = battle != null ||
        encounter?.kind == 'guardian' ||
        cue?.isGuardianExchange == true;
    final actorStage = cue?.stage ?? widget.actor?.stage ?? 2;
    final enemyName =
        combat?.enemyName ?? battle?.enemy.name ?? encounter?.enemyName;
    final maxGuard = combat?.enemyMaxGuard ??
        battle?.enemy.maxGuard ??
        encounter?.enemyMaxGuard ??
        100;
    final currentGuard = battle?.enemy.guard ?? maxGuard;
    final currentTelegraph =
        battle?.enemy.intent.telegraph ?? encounter?.telegraph ?? '';
    final hasTelegraph = encounter != null || battle != null;
    final semantics = cue == null
        ? enemyName == null
            ? '${widget.actor?.name ?? '탐험대'}의 현재 위치'
            : '$enemyName 조우. $currentTelegraph'
        : cue.isTerminalCombatOutcome
            ? cue.outcome ?? '수호전이 끝났어요.'
            : cue.isBossPhase
                ? '${cue.actorName}의 ${cue.title}. ${cue.outcome ?? ''}'
                : cue.isCombatRound && cue.playsEnemyAttack
                    ? '${cue.actorName}의 ${cue.title}. '
                        '${combat!.damageTarget}에 '
                        '${combat.counterDamage > 0 ? '${combat.counterDamage} 피해.' : '피해를 막았어요.'}'
                    : cue.isGuardianExchange
                        ? '${cue.actorName}의 ${cue.title}. '
                            '${combat!.enemyName} 체력에 ${combat.guardDamage} 피해. '
                            '${cue.playsEnemyAttack ? combat.counterDamage > 0 ? '${combat.damageTarget} ${combat.counterDamage} 피해.' : '반격 방어.' : ''}'
                        : cue.kind == ExpeditionActionCueKind.resolution
                            ? '${cue.actorName}. ${cue.outcome ?? cue.title}'
                            : '${koreanSubject(cue.actorName)} ${cue.title} 스킬을 사용했어요.';
    final enemyAsset = _enemyAsset;
    final enemyNative = expeditionPixelSpriteSize(enemyAsset);
    final enemyKind = battle?.enemyKind ??
        (encounter?.kind == 'guardian' || cue?.isGuardianExchange == true
            ? 'guardian'
            : 'tangle');

    return Positioned.fill(
      child: Semantics(
        liveRegion: cue != null,
        label: semantics,
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final unit = PixelStageScale.of(context).toDouble();
              final layout = _StageLayout(
                size: size,
                topInset: widget.topHudInset,
                bottomInset: widget.bottomHudInset,
                unit: unit,
              );
              // 어린 대원은 한 배율 작게. 화분 시절의 캐릭터가 성체와 같은
              // 키로 서면 성장이 화면에서 사라진다.
              final actorUnit =
                  actorStage <= 2 ? math.max(2.0, unit - 1) : unit;
              final enemyBox = Size(
                enemyNative.width * unit,
                enemyNative.height * unit,
              );
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (guardianActive)
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('expedition-combat-ground'),
                          painter: ExpeditionBattleGroundPainter(
                            unit: unit,
                            enemyFoot: Offset(
                              layout.enemyFoot.dx / size.width,
                              layout.enemyFoot.dy / size.height,
                            ),
                            enemyWidth: enemyBox.width * .78,
                            partyFoot: Offset(
                              layout.actorFoot.dx / size.width,
                              layout.actorFoot.dy / size.height,
                            ),
                            partyWidth: unit * 22,
                          ),
                        ),
                      ),
                    ),
                  if (guardianActive && widget.party.length > 1)
                    Positioned.fill(
                      child: _CombatPartyFormation(
                        party: widget.party,
                        battle: battle,
                        activeMemberId: cue?.actorId ?? widget.actor?.id,
                        layout: layout,
                        ambient: _ambientController,
                        reduceMotion: reduceMotion,
                        action: _presentation,
                        cue: cue,
                      ),
                    ),
                  if (guardianActive)
                    Positioned(
                      left: layout.enemyFoot.dx - enemyBox.width / 2,
                      top: layout.enemyFoot.dy - enemyBox.height,
                      width: enemyBox.width,
                      height: enemyBox.height,
                      child: _PixelEnemy(
                        action: _presentation,
                        ambient: _ambientController,
                        cue: cue,
                        combat: combat,
                        reduceMotion: reduceMotion,
                        enemyKind: enemyKind,
                        asset: enemyAsset,
                        unit: unit,
                        box: enemyBox,
                      ),
                    ),
                  if ((cue != null && !cue.isBossPhase) ||
                      (cue == null && widget.actor != null))
                    Positioned.fill(
                      child: _PixelActor(
                        action: _presentation,
                        ambient: _ambientController,
                        cue: cue,
                        actor: widget.actor,
                        stage: actorStage,
                        unit: actorUnit,
                        foot: layout.actorFoot,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  if (guardianActive && cue == null)
                    Positioned.fill(
                      child: _GuardianIntentLayer(
                        ambient: _ambientController,
                        reduceMotion: reduceMotion,
                        target: battle?.enemy.intent.target ?? 'front',
                        unit: unit,
                        anchor: Offset(
                          layout.enemyFoot.dx / size.width,
                          (layout.enemyFoot.dy - enemyBox.height * .45) /
                              size.height,
                        ),
                      ),
                    ),
                  if (cue != null)
                    Positioned.fill(
                      child: ExpeditionCombatSpriteLayer(
                        action: _presentation,
                        cue: cue,
                        reduceMotion: reduceMotion,
                        actorAnchor:
                            layout.actorFoot - Offset(0, actorUnit * 18),
                        enemyAnchor:
                            layout.enemyFoot - Offset(0, enemyBox.height * .45),
                        stageBounds: Rect.fromLTRB(0, layout.usableTop,
                            size.width, layout.usableBottom),
                      ),
                    ),
                  // 적의 이름·장벽과 다음 공격 예고는 한 덩어리로 위에 붙인다.
                  //
                  // 예고를 무대 바닥에 두면 아군과 적의 얼굴을 가로질러 덮는다.
                  // 둘 다 아래쪽에 서 있어서 피할 자리가 없다. 같은 적을
                  // 설명하는 두 조각이니 위에서 붙여 두면 서로 겹치지도,
                  // 배우를 가리지도 않는다.
                  // 폭은 왼쪽 3분의 2까지만. 적은 오른쪽 위에 서 있으니 판이
                  // 화면을 가로지르면 적의 머리를 덮는다.
                  if (enemyName != null || (cue == null && hasTelegraph))
                    Positioned(
                      top: 60 + widget.topHudInset,
                      left: 10,
                      width: math.min(250.0, size.width * .64),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (enemyName != null)
                            SizedBox(
                              width: math.min(200.0, size.width * .53),
                              child: _AnimatedGuardHud(
                                action: _presentation,
                                enemyName: enemyName,
                                maxGuard: maxGuard,
                                before:
                                    combat?.enemyGuardBefore ?? currentGuard,
                                after: combat?.enemyGuardAfter ?? currentGuard,
                                animate: cue != null,
                                contactProgress: cue == null
                                    ? .30
                                    : ExpeditionCombatTimeline
                                        .partyContactProgress(cue),
                                elite: battle?.enemy.elite ?? false,
                              ),
                            ),
                          if (cue == null && hasTelegraph) ...[
                            const SizedBox(height: 6),
                            ExpeditionTelegraphChip(
                              attackName: battle?.enemy.intent.name ??
                                  encounter?.attackName ??
                                  '수호자의 공격',
                              text: battle == null
                                  ? currentTelegraph
                                  : '${battle.enemy.intent.targetLabel.replaceFirst('행동 순서 ', '')} · 피해 ${battle.enemy.intent.power}',
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (cue != null)
                    Positioned.fill(
                      child: _AnimatedCombatLabels(
                        action: _presentation,
                        cue: cue,
                        combat: combat,
                        layout: layout,
                        enemyBox: enemyBox,
                        reduceMotion: reduceMotion,
                        bottomInset: size.height - layout.usableBottom,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 적 하나. ambient/action 틱을 구독해 나머지 무대의 재빌드를 막는다.
///
/// 상태마다 다른 원화를 쓰던 것을 **한 장의 도트와 움직임**으로 바꿨다. 준비는
/// 뒤로 움츠림, 공격은 앞으로 내지름, 맞으면 하얗게 번쩍이며 밀리고, 풀리면
/// 화소 조각으로 흩어진다. 도트 게임의 적은 원래 그렇게 움직인다.
class _PixelEnemy extends StatelessWidget {
  const _PixelEnemy({
    required this.action,
    required this.ambient,
    required this.cue,
    required this.combat,
    required this.reduceMotion,
    required this.enemyKind,
    required this.asset,
    required this.unit,
    required this.box,
  });

  final Animation<double> action;
  final Animation<double> ambient;
  final ExpeditionActionCue? cue;
  final ExpeditionCombatFeedback? combat;
  final bool reduceMotion;
  final String enemyKind;
  final String asset;
  final double unit;

  /// 이 적이 차지하는 상자. 흩어지는 조각의 출발점을 여기서 잡는다.
  final Size box;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([action, ambient]),
          builder: (context, _) {
            final progress = cue == null ? 0.0 : action.value;
            final partyContact = cue == null
                ? .34
                : ExpeditionCombatTimeline.partyContactProgress(cue!);
            final enemyContact = cue == null
                ? .62
                : ExpeditionCombatTimeline.enemyContactProgress(cue!);
            final defeatedBlend = cue?.combatResult == 'victory'
                ? ExpeditionCombatTimeline.segment(
                    progress,
                    partyContact + .24,
                    partyContact + .34,
                  )
                : 0.0;
            final hitExit = cue?.combatResult == 'victory'
                ? ExpeditionCombatTimeline.segment(
                    progress,
                    partyContact + .24,
                    partyContact + .34,
                  )
                : ExpeditionCombatTimeline.segment(
                    progress,
                    partyContact + .18,
                    partyContact + .27,
                  );
            final hitBlend = cue?.dealsGuardianDamage == true
                ? math.min(
                    ExpeditionCombatTimeline.hitReaction(
                        progress, partyContact),
                    1 - hitExit)
                : 0.0;
            final attackBlend = cue?.playsEnemyAttack == true &&
                    combat?.counterResult != 'calmed'
                ? math.min(
                      ExpeditionCombatTimeline.segment(
                        progress,
                        enemyContact - .08,
                        enemyContact,
                      ),
                      1 -
                          ExpeditionCombatTimeline.segment(
                            progress,
                            enemyContact + .20,
                            enemyContact + .25,
                          ),
                    ) *
                    (1 - defeatedBlend) *
                    (1 - hitBlend)
                : 0.0;
            final guardianHit = cue?.dealsGuardianDamage == true
                ? ExpeditionCombatTimeline.segment(
                    progress,
                    partyContact,
                    partyContact + .22,
                  )
                : 0.0;
            final flash = cue?.dealsGuardianDamage == true
                ? ExpeditionCombatTimeline.hitReaction(progress, partyContact)
                : 0.0;
            // 숨쉬기: 도트 한 칸을 3.6초에 한 번 오르내린다. 소수 픽셀로
            // 흔들면 도트가 뭉개지므로 정수 칸으로만 움직인다.
            final breath = reduceMotion
                ? 0.0
                : (math.sin(ambient.value * math.pi * 2) > 0 ? 1.0 : 0.0);
            final windUp = cue?.playsEnemyAttack == true
                ? math.sin(
                    ExpeditionCombatTimeline.segment(
                          progress,
                          enemyContact - .22,
                          enemyContact - .08,
                        ) *
                        math.pi,
                  )
                : 0.0;
            final lunge = cue?.playsEnemyAttack == true &&
                    combat?.counterResult != 'calmed'
                ? math.sin(
                    ExpeditionCombatTimeline.segment(
                          progress,
                          enemyContact - .13,
                          enemyContact + .18,
                        ) *
                        math.pi,
                  )
                : 0.0;
            final shake = cue?.isGuardianExchange == true && !reduceMotion
                ? cue?.playsEnemyAttack == true
                    ? ExpeditionCombatTimeline.impactShake(progress, cue)
                    : cue?.dealsGuardianDamage == true
                        ? ExpeditionCombatTimeline.partyImpactShake(
                            progress, cue)
                        : Offset.zero
                : Offset.zero;
            final knockback = math.sin(guardianHit * math.pi * 7) *
                math.sin(guardianHit * math.pi);
            final rawOffset = reduceMotion
                ? Offset.zero
                : Offset(
                      windUp * unit * 3 -
                          lunge * unit * 8 +
                          knockback * unit * 2.5,
                      breath * unit + lunge * unit * 2,
                    ) +
                    shake;
            final offset = Offset(
              (rawOffset.dx / unit).round() * unit,
              (rawOffset.dy / unit).round() * unit,
            );
            final state = defeatedBlend > .001
                ? (enemyKind == 'tangle' ? 'release' : 'defeated')
                : hitBlend > .001
                    ? 'hit'
                    : attackBlend > .001
                        ? 'attack'
                        : 'idle';
            final keyPrefix =
                enemyKind == 'tangle' ? 'tangle-body' : 'ledger-keeper';
            final squashX = reduceMotion
                ? 1.0
                : 1 + lunge * .08 - hitBlend * .06 - windUp * .05;
            final squashY = reduceMotion
                ? 1.0
                : 1 - lunge * .06 + hitBlend * .08 + windUp * .05;
            return Transform.translate(
              offset: offset,
              child: Transform.scale(
                scaleX: squashX,
                scaleY: squashY * (1 - defeatedBlend * .35),
                alignment: Alignment.bottomCenter,
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: (1 - defeatedBlend).clamp(0.0, 1.0),
                      child: _PixelEnemyImage(
                        key: ValueKey('$keyPrefix-$state'),
                        asset: expeditionEnemyPoseAsset(asset, state),
                        flash: reduceMotion ? 0 : flash * .85,
                      ),
                    ),
                    if (defeatedBlend > 0 && !reduceMotion)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: PixelScatterPainter(
                            progress: defeatedBlend,
                            origin: Offset(box.width / 2, box.height * .55),
                            color: const Color(0xFFF3E6C8),
                            unit: unit,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class _PixelEnemyImage extends StatelessWidget {
  const _PixelEnemyImage({super.key, required this.asset, required this.flash});

  final String asset;
  final double flash;

  @override
  Widget build(BuildContext context) {
    final illustrated = asset.endsWith('.webp');
    final image = Image.asset(
      asset,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      cacheWidth: illustrated ? 512 : null,
      filterQuality: illustrated ? FilterQuality.medium : FilterQuality.none,
      isAntiAlias: illustrated,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
    if (flash <= .01) return image;
    // 몸의 모양대로만 하얗게. `srcATop`은 투명한 자리를 건드리지 않는다.
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Opacity(
          opacity: flash.clamp(0.0, 1.0),
          child: ColorFiltered(
            colorFilter:
                const ColorFilter.mode(Colors.white, BlendMode.srcATop),
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              cacheWidth: illustrated ? 512 : null,
              filterQuality:
                  illustrated ? FilterQuality.medium : FilterQuality.none,
              isAntiAlias: illustrated,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 행동 대원의 도트. 전투용 도트가 있으면 그것을, 없으면 걷기 시트의 옆모습 칸을 쓴다.
class _PixelActor extends StatelessWidget {
  const _PixelActor({
    required this.action,
    required this.ambient,
    required this.cue,
    required this.actor,
    required this.stage,
    required this.unit,
    required this.foot,
    required this.reduceMotion,
  });

  final Animation<double> action;
  final Animation<double> ambient;
  final ExpeditionActionCue? cue;
  final ExpeditionMember? actor;
  final int stage;
  final double unit;
  final Offset foot;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final speciesCode = cue?.speciesCode ?? actor?.speciesCode;
    final sprite = _PartySprite(
        speciesCode: speciesCode,
        unit: unit,
        stage: cue?.stage ?? actor?.stage ?? stage,
        form: cue?.form ?? actor?.form,
        outfitKey: actor?.outfitKey);
    final artwork = RepaintBoundary(
      key: const ValueKey('expedition-combat-actor-artwork'),
      child: sprite.build(flash: 0),
    );
    return AnimatedBuilder(
      key: const ValueKey('expedition-combat-actor'),
      animation: Listenable.merge([action, ambient]),
      child: artwork,
      builder: (context, child) {
        final progress = cue == null ? 0.0 : action.value;
        final shake = cue?.isGuardianExchange == true && !reduceMotion
            ? cue?.playsEnemyAttack == true
                ? ExpeditionCombatTimeline.impactShake(progress, cue) * .35
                : cue?.dealsGuardianDamage == true
                    ? ExpeditionCombatTimeline.partyImpactShake(progress, cue) *
                        .18
                    : Offset.zero
            : Offset.zero;
        final cast = !reduceMotion && cue?.playsPartyAttack == true
            ? math.sin(
                ExpeditionCombatTimeline.segment(progress, .04, .46) * math.pi,
              )
            : 0.0;
        final recoil = !reduceMotion &&
                cue?.playsEnemyAttack == true &&
                (cue?.combat?.counterDamage ?? 0) > 0
            ? ExpeditionCombatTimeline.hitReaction(
                progress, ExpeditionCombatTimeline.enemyContactProgress(cue!))
            : 0.0;
        final breath = reduceMotion || cue != null
            ? 0.0
            : (math.sin(ambient.value * math.pi * 2 + math.pi) > 0 ? 1.0 : 0.0);
        final rawOffset = (reduceMotion
                ? Offset.zero
                : ExpeditionCombatTimeline.actorOffset(progress, cue)) +
            shake +
            Offset(0, breath * unit);
        final offset = Offset(
          (rawOffset.dx / unit).round() * unit,
          (rawOffset.dy / unit).round() * unit,
        );
        final hurt = cue?.playsEnemyAttack == true &&
                (cue?.combat?.counterDamage ?? 0) > 0
            ? recoil
            : 0.0;
        final box = sprite.size;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: foot.dx - box.width / 2 + offset.dx,
              top: foot.dy - box.height + offset.dy,
              width: box.width,
              height: box.height,
              child: Transform.scale(
                scaleX: 1 + cast * .06 - recoil * .04,
                scaleY: 1 - cast * .03 + recoil * .05,
                alignment: Alignment.bottomCenter,
                child: hurt > .05
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          child!,
                          Opacity(
                            opacity: (hurt * .7).clamp(0.0, 1.0),
                            child: sprite.build(flash: 1),
                          ),
                        ],
                      )
                    : child,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The map, field, and encounter all render the actual selected plant.
/// A missing combat sprite must not replace it with an unrelated human walker.
class _PartySprite {
  const _PartySprite(
      {required this.speciesCode,
      required this.unit,
      required this.stage,
      required this.form,
      this.outfitKey});
  final String? speciesCode;
  final double unit;
  final int stage;
  final String? form;
  final String? outfitKey;
  Size get size => Size(60 * unit, 80 * unit);
  Widget build({required double flash}) {
    final artwork = PlantView(
        stage: stage,
        speciesCode: speciesCode ?? 'basic_sprout',
        form: PlantGrowthForm.fromCode(form),
        outfitKey: outfitKey,
        width: size.width,
        height: size.height);
    return flash <= 0
        ? artwork
        : ColorFiltered(
            colorFilter:
                const ColorFilter.mode(Colors.white, BlendMode.srcATop),
            child: artwork);
  }
}

/// 현재 행동 대원 뒤에서 나머지 탐험대가 자기 도트로 서 있는다.
/// 전투원 수가 늘어도 무대 밀도를 일정하게 유지하도록 후열은 최대 두 명만 보인다.
class _CombatPartyFormation extends StatelessWidget {
  const _CombatPartyFormation({
    required this.party,
    required this.battle,
    required this.activeMemberId,
    required this.layout,
    required this.ambient,
    required this.reduceMotion,
    required this.action,
    required this.cue,
  });

  final List<ExpeditionMember> party;
  final ExpeditionBattle? battle;
  final int? activeMemberId;
  final _StageLayout layout;
  final Animation<double> ambient;
  final bool reduceMotion;
  final Animation<double> action;
  final ExpeditionActionCue? cue;

  @override
  Widget build(BuildContext context) {
    final members = party
        .where((member) => member.id != activeMemberId)
        .take(2)
        .toList(growable: false);
    if (members.isEmpty) return const SizedBox.shrink();
    // 후열은 한 배율 작게 — 뒤에 서 있다는 뜻이다. 2배 아래로는 안 내려간다.
    final unit = math.max(2.0, layout.unit - 1);
    return RepaintBoundary(
      key: const ValueKey('expedition-combat-party-lineup'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < members.length; index++)
            _BacklineMember(
              member: members[index],
              status: battle?.party
                  .where((item) => item.memberId == members[index].id)
                  .firstOrNull,
              foot: layout.backlineFeet[index],
              unit: unit,
              ambient: ambient,
              reduceMotion: reduceMotion,
              phase: index,
              action: action,
              cue: cue,
            ),
        ],
      ),
    );
  }
}

class _BacklineMember extends StatelessWidget {
  const _BacklineMember({
    required this.member,
    required this.status,
    required this.foot,
    required this.unit,
    required this.ambient,
    required this.reduceMotion,
    required this.phase,
    required this.action,
    required this.cue,
  });

  final ExpeditionMember member;
  final ExpeditionBattleMember? status;
  final Offset foot;
  final double unit;
  final Animation<double> ambient;
  final bool reduceMotion;
  final int phase;
  final Animation<double> action;
  final ExpeditionActionCue? cue;

  @override
  Widget build(BuildContext context) {
    final health = status == null || status!.maxHp <= 0
        ? 1.0
        : (status!.hp / status!.maxHp).clamp(0.0, 1.0);
    final sprite = _PartySprite(
        speciesCode: member.speciesCode,
        unit: unit,
        stage: member.stage,
        form: member.form,
        outfitKey: member.outfitKey);
    final box = sprite.size;
    return AnimatedBuilder(
      animation: Listenable.merge([ambient, action]),
      child: Opacity(
        opacity: status?.isAlive == false ? .42 : 1,
        child: sprite.build(flash: 0),
      ),
      builder: (context, child) {
        final target =
            cue?.targets.where((t) => t.memberId == member.id).firstOrNull;
        final contact = cue == null
            ? 1.0
            : ExpeditionCombatTimeline.enemyContactProgress(cue!);
        final contacted =
            cue?.playsEnemyAttack == true && action.value >= contact;
        final reaction = !reduceMotion && contacted && (target?.damage ?? 0) > 0
            ? ExpeditionCombatTimeline.hitReaction(action.value, contact)
            : 0.0;
        final shownHealth =
            contacted && target != null && (status?.maxHp ?? 0) > 0
                ? (target.hpAfter / status!.maxHp).clamp(0.0, 1.0)
                : health;
        final breath = reduceMotion
            ? 0.0
            : (math.sin(ambient.value * math.pi * 2 + phase * 1.9) > 0
                ? 1.0
                : 0.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: foot.dx - box.width / 2 - reaction * 8,
              top: foot.dy - box.height + breath * unit,
              width: box.width,
              height: box.height,
              child: reaction > .05
                  ? Opacity(opacity: 1 - reaction * .35, child: child!)
                  : child!,
            ),
            Positioned(
              left: foot.dx - unit * 8,
              top: foot.dy + unit * 2,
              width: unit * 16,
              child: PixelBar(
                value: shownHealth,
                unit: math.max(1, unit / 2),
                height: unit * 2,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GuardianIntentLayer extends StatelessWidget {
  const _GuardianIntentLayer({
    required this.ambient,
    required this.reduceMotion,
    required this.target,
    required this.unit,
    required this.anchor,
  });

  final Animation<double> ambient;
  final bool reduceMotion;
  final String target;
  final double unit;
  final Offset anchor;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: ambient,
          builder: (context, _) => CustomPaint(
            painter: ExpeditionGuardianIntentPainter(
              phase: ambient.value,
              reduceMotion: reduceMotion,
              target: target,
              unit: unit,
              anchor: anchor,
            ),
          ),
        ),
      );
}

class _AnimatedGuardHud extends StatelessWidget {
  const _AnimatedGuardHud({
    required this.action,
    required this.enemyName,
    required this.maxGuard,
    required this.before,
    required this.after,
    required this.animate,
    required this.contactProgress,
    required this.elite,
  });

  final Animation<double> action;
  final String enemyName;
  final int maxGuard;
  final int before;
  final int after;
  final bool animate;
  final double contactProgress;
  final bool elite;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: action,
          builder: (context, _) => ExpeditionEnemyGuardHud(
            enemyName: enemyName,
            maxGuard: maxGuard,
            before: before,
            after: after,
            progress: animate ? action.value : 0,
            contactProgress: contactProgress,
            elite: elite,
          ),
        ),
      );
}

class _AnimatedCombatLabels extends StatelessWidget {
  const _AnimatedCombatLabels({
    required this.action,
    required this.cue,
    required this.combat,
    required this.layout,
    required this.enemyBox,
    required this.reduceMotion,
    required this.bottomInset,
  });

  final Animation<double> action;
  final ExpeditionActionCue cue;
  final ExpeditionCombatFeedback? combat;
  final _StageLayout layout;
  final Size enemyBox;
  final bool reduceMotion;
  final double bottomInset;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: action,
          builder: (context, _) {
            final progress = action.value;
            final partyContact =
                ExpeditionCombatTimeline.partyContactProgress(cue);
            final enemyContact =
                ExpeditionCombatTimeline.enemyContactProgress(cue);
            final unit = layout.unit;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (progress < .86)
                  Positioned(
                    left: 12,
                    bottom: bottomInset + 8,
                    child: ExpeditionActorBadge(
                      actorName: cue.actorName,
                      actionName: cue.title,
                    ),
                  ),
                if (progress >= partyContact && (combat?.guardDamage ?? 0) > 0)
                  Positioned(
                    left: layout.enemyFoot.dx - unit * 12,
                    top: math.max(
                        layout.usableTop + 48,
                        layout.enemyFoot.dy -
                            enemyBox.height -
                            unit * 4 -
                            (ExpeditionCombatTimeline.segment(
                                          progress,
                                          partyContact,
                                          partyContact + .25,
                                        ) *
                                        6)
                                    .round() *
                                unit),
                    child: ExpeditionDamageNumber(
                      label: '-${combat!.guardDamage}',
                      caption: cue.weaknessHit ? '약점!' : '체력 피해',
                      color: expeditionCombatEffectColor(cue.effectKey),
                      opacity: reduceMotion
                          ? 1
                          : ExpeditionCombatTimeline.damageOpacity(
                              progress, partyContact),
                    ),
                  ),
                if (cue.playsEnemyAttack && progress >= .18)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: layout.usableTop,
                    child: Center(
                      child: ExpeditionAttackCallout(
                        attackName: combat!.attackName,
                        progress: progress,
                        contactProgress: enemyContact,
                      ),
                    ),
                  ),
                if (cue.playsEnemyAttack && progress >= enemyContact)
                  Positioned(
                    left: layout.actorFoot.dx - unit * 4,
                    top: layout.actorFoot.dy -
                        unit * 40 -
                        (ExpeditionCombatTimeline.segment(
                                      progress,
                                      enemyContact,
                                      enemyContact + .34,
                                    ) *
                                    4)
                                .round() *
                            unit,
                    child: ExpeditionDamageNumber(
                      label: combat!.counterDamage > 0
                          ? '-${combat!.counterDamage}'
                          : combat!.counterResult == 'calmed'
                              ? '진정'
                              : '방어',
                      caption: cue.targets.length > 1
                          ? cue.targets
                              .map((target) =>
                                  '${target.name} ${target.damage > 0 ? '−${target.damage}' : '방어'}')
                              .join(' · ')
                          : combat!.counterDamage > 0
                              ? '${combat!.damageTarget} 피해'
                              : combat!.counterResult == 'calmed'
                                  ? '교전 없이 이탈'
                                  : '${combat!.attackName} 차단',
                      color: combat!.counterDamage > 0
                          ? ExpeditionCombatHudColors.hurt
                          : ExpeditionCombatHudColors.heal,
                      opacity: reduceMotion
                          ? 1
                          : ExpeditionCombatTimeline.damageOpacity(
                              progress, enemyContact),
                    ),
                  ),
                if (progress >= .86)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomInset + 8,
                    child: Center(
                      child: ExpeditionOutcomeBadge(
                        label: cue.outcome ?? '스킬 준비 완료',
                        effectKey: cue.effectKey,
                        progress: progress,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
