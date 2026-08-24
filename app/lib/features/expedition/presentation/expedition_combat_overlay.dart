import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'expedition_scene.dart';

/// 탐험 결과를 짧은 전투 연출로 보여 주는 무대다.
///
/// 서버가 계산한 [ExpeditionActionCue]를 재생할 뿐 판정을 다시 계산하지 않는다.
/// 배경, 캐릭터, 수호자, 이펙트, HUD는 서로 다른 갱신·리페인트 경계를 사용해
/// 한 애니메이션이 정적인 레이어까지 다시 그리지 않도록 구성한다.
class ExpeditionEncounterStage extends StatefulWidget {
  const ExpeditionEncounterStage({
    super.key,
    required this.encounter,
    this.battle,
    this.regionCode,
    required this.actor,
    this.party = const [],
    required this.cue,
    required this.onCueCompleted,
    this.paceScale = 1.0,
    this.shortEffects = false,
    this.audioMode = ExpeditionAudioMode.all,
    this.bottomHudInset = 0,
  });

  final ExpeditionEncounter? encounter;
  final ExpeditionBattle? battle;
  final String? regionCode;
  final ExpeditionMember? actor;
  final List<ExpeditionMember> party;
  final ExpeditionActionCue? cue;
  final VoidCallback onCueCompleted;

  /// 연출 배속. 2.0이면 같은 타임라인을 절반 시간에 재생한다.
  /// 프레임을 건너뛰지 않고 판정 결과도 바꾸지 않는다.
  final double paceScale;

  /// 짧은 연출 모드. 시동·여운 구간을 약 40% 줄이되 판정 정보(행동·피해·
  /// 승패)는 전부 유지한다. `disableAnimations` 접근성 설정과는 독립이다.
  final bool shortEffects;

  /// 음악·효과음 단계. 어느 단계에서도 시각·촉각 판정은 그대로 남는다.
  final ExpeditionAudioMode audioMode;

  bool get audioEnabled => audioMode != ExpeditionAudioMode.muted;

  /// 전장을 줄이지 않고 가장자리 명령 HUD가 차지하는 하단 영역만 피한다.
  final double bottomHudInset;

  @override
  State<ExpeditionEncounterStage> createState() =>
      _ExpeditionEncounterStageState();
}

class _ExpeditionEncounterStageState extends State<ExpeditionEncounterStage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _actionController;
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
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _audio = ExpeditionCombatAudio(
      musicEnabled: widget.audioMode == ExpeditionAudioMode.all,
      sfxEnabled: widget.audioEnabled,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  /// 앱이 뒤로 가면 음악을 300ms 동안 줄여 멈추고, 복귀하면 같은 재생 위치에서
  /// 500ms에 걸쳐 돌아온다. 다른 앱의 소리를 갑자기 자르지 않기 위해서다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
        oldWidget.battle?.wave?.code != widget.battle?.wave?.code) {
      _precacheEnemyImages();
    }
    _precacheRelevantEffects();
    if (oldWidget.audioMode != widget.audioMode) {
      unawaited(_applyAudioMode());
    }
    if (oldWidget.battle?.enemyKind != widget.battle?.enemyKind ||
        oldWidget.battle?.regionCode != widget.battle?.regionCode ||
        oldWidget.regionCode != widget.regionCode ||
        oldWidget.encounter?.kind != widget.encounter?.kind) {
      _syncMusic();
    }
    _playTelegraphIfNeeded();
    if (oldWidget.cue?.id != widget.cue?.id) {
      _playCueIfNeeded();
    }
  }

  Future<void> _applyAudioMode() async {
    await _audio.setChannels(
      music: widget.audioMode == ExpeditionAudioMode.all,
      sfx: widget.audioEnabled,
    );
    if (!mounted) return;
    // 효과음만으로 입장한 경우에는 아직 재개할 BGM 상태가 없다. 채널 전환이
    // 끝난 뒤 현재 전장 stem을 새로 동기화해야 음악을 켠 즉시 재생된다.
    _syncMusic();
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
    unawaited(_audio.playTelegraph(battle.enemy.intent.contactMaterial));
  }

  void _syncMusic() {
    if (widget.audioMode != ExpeditionAudioMode.all) return;
    final state = widget.battle?.enemyKind == 'guardian' ||
            widget.encounter?.kind == 'guardian'
        ? ExpeditionMusicState.guardian
        : widget.battle != null
            ? ExpeditionMusicState.combat
            : ExpeditionMusicState.base;
    final regionCode = widget.regionCode ?? widget.battle?.regionCode;
    // 지역마다 다른 곡을 쓴다. 지역을 모르는 구버전 응답은 첫 지역 곡으로
    // 떨어지므로 무음이 되지 않는다.
    unawaited(
      _audio.playMusic(state, regionCode: regionCode),
    );
  }

  int _guardianCacheWidth(BuildContext context) {
    final media = MediaQuery.of(context);
    return (media.size.width * .55 * media.devicePixelRatio * 1.15)
        .round()
        .clamp(256, 1024);
  }

  void _precacheEnemyImages() {
    final cacheWidth = _guardianCacheWidth(context);
    final battle = widget.battle;
    final tangleCode = battle?.wave?.code ?? '';
    final isTangle = battle?.enemyKind == 'tangle';
    final assets = isTangle
        ? <String>{
            for (final state in expeditionTangleStates)
              expeditionTangleAssetPath(tangleCode, state),
          }
        : expeditionCombatAssets;
    final mobileWidth =
        isTangle ? expeditionMobileTangleWidth : expeditionMobileGuardianWidth;
    final signature = '$cacheWidth:$mobileWidth:${assets.join('|')}';
    if (_precacheSignature == signature) return;
    _precacheSignature = signature;
    for (final asset in assets) {
      final provider = expeditionRuntimeImageProvider(
        assetPath: asset,
        cacheWidth: cacheWidth,
        mobileAssetWidth: mobileWidth,
      );
      // 디코드는 첫 공격보다 먼저 시작하되 화면 진입은 기다리지 않는다.
      precacheImage(provider, context).ignore();
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

    for (final asset in <String>{
      for (final effect in firstFrames.values) effect.asset(0),
      for (final effect in fullSequences.values)
        ...expeditionCombatEffectAssetsFor(effect),
    }) {
      precacheImage(AssetImage(asset), context).ignore();
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
          precacheImage(AssetImage(asset), context),
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
    _actionController.duration = MediaQuery.disableAnimationsOf(context)
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
    _actionController.forward(from: 0);
    if (cue.isBossPhase) {
      unawaited(_audio.playBossPhaseBreak());
    } else if (cue.isCombatRound) {
      if (cue.playsEnemyAttack) {
        // 적이 무엇을 날리는지 행동 시작에 먼저 들려주고, 실제 충돌음은
        // contact frame까지 미룬다. 두 소리를 분리해야 예고가 판정 정보가 된다.
        unawaited(_audio.playTelegraph(cue.contactMaterial));
      } else if (cue.effectKey != 'safe_guard') {
        unawaited(
          _audio.playSkillTier(
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
      _previousProgress = _actionController.value;
      return;
    }
    final progress = _actionController.value;
    final partyContact = ExpeditionCombatTimeline.partyContactProgress(cue!);
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
            const Duration(milliseconds: 320),
            () => _audio.playRelease(releaseRegion),
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
    if (cue == null && encounter == null && battle == null) {
      return const SizedBox.shrink();
    }

    final combat = cue?.combat;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final guardianActive = battle != null ||
        encounter?.kind == 'guardian' ||
        cue?.isGuardianExchange == true;
    final actorStage = cue?.stage ?? widget.actor?.stage ?? 2;
    final actorScale = switch (actorStage) {
      <= 2 => 2.08,
      3 => 1.58,
      4 => 1.3,
      _ => 1.16,
    };
    final actorBottom = switch (actorStage) {
      <= 2 => 5.0,
      3 => 0.0,
      4 => -7.0,
      _ => -15.0,
    };
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
        ? '$enemyName 조우. $currentTelegraph'
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
                            '${combat!.enemyName} 수호 장벽에 ${combat.guardDamage} 피해. '
                            '${cue.playsEnemyAttack ? combat.counterDamage > 0 ? '${combat.damageTarget} ${combat.counterDamage} 피해.' : '반격 방어.' : ''}'
                        : '${cue.actorName}이 ${cue.title} 스킬을 사용했어요.';

    return Positioned.fill(
      child: Semantics(
        liveRegion: cue != null,
        label: semantics,
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final usableHeight =
                  math.max(220.0, size.height - widget.bottomHudInset);
              final actorWidth = math.min(152.0, size.width * .40);
              final actorHeight = usableHeight * .82;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (guardianActive)
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: ValueKey('expedition-combat-ground'),
                          painter: ExpeditionBattleGroundPainter(),
                        ),
                      ),
                    ),
                  if (guardianActive && widget.party.length > 1)
                    Positioned(
                      left: 0,
                      bottom: 1 + widget.bottomHudInset,
                      width: size.width * .39,
                      height: usableHeight * .52,
                      child: _CombatPartyFormation(
                        party: widget.party,
                        battle: battle,
                        activeMemberId: cue?.actorId ?? widget.actor?.id,
                      ),
                    ),
                  if (guardianActive)
                    Positioned(
                      right: -size.width * .035,
                      // 아군과 같은 [usableHeight]를 쓴다. 전체 높이로 잡으면
                      // 아래 지휘 독이 덮는 만큼 적이 잘려서, 얼굴이 있는
                      // 아래쪽이 화면 밖으로 밀린다.
                      top: usableHeight * .035,
                      width: size.width * .62,
                      height: usableHeight * .84,
                      child: _AnimatedGuardian(
                        action: _actionController,
                        ambient: _ambientController,
                        cue: cue,
                        combat: combat,
                        reduceMotion: reduceMotion,
                        imageCacheWidth: _guardianCacheWidth(context),
                        enemyKind: battle?.enemyKind ?? 'guardian',
                        enemyCode: battle?.wave?.code ?? '',
                      ),
                    ),
                  if ((cue != null && !cue.isBossPhase) ||
                      (cue == null && widget.actor != null))
                    Positioned(
                      left: size.width * .035,
                      bottom: actorBottom + widget.bottomHudInset,
                      width: actorWidth,
                      height: actorHeight,
                      child: _AnimatedCombatActor(
                        action: _actionController,
                        cue: cue,
                        actor: widget.actor,
                        stage: actorStage,
                        scale: actorScale,
                        width: actorWidth,
                        height: actorHeight,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  if (guardianActive && cue == null)
                    Positioned.fill(
                      child: _GuardianIntentLayer(
                        ambient: _ambientController,
                        reduceMotion: reduceMotion,
                        target: battle?.enemy.intent.target ?? 'front',
                      ),
                    ),
                  if (cue != null)
                    Positioned.fill(
                      child: ExpeditionCombatSpriteLayer(
                        action: _actionController,
                        cue: cue,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  // 적의 이름·장벽과 다음 공격 예고는 한 덩어리로 위에 붙인다.
                  //
                  // 예고를 무대 바닥(`bottom: 10 + inset`)에 두면 아군의 화분과
                  // 적의 얼굴을 가로질러 덮는다. 둘 다 아래쪽에 서 있어서
                  // 피할 자리가 없다. 같은 적을 설명하는 두 조각이니 위에서
                  // 붙여 두면 서로 겹치지도, 배우를 가리지도 않는다.
                  if (enemyName != null || (cue == null && hasTelegraph))
                    Positioned(
                      top: 47,
                      left: 10,
                      right: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (enemyName != null)
                            SizedBox(
                              width: math.min(200.0, size.width * .53),
                              child: _AnimatedGuardHud(
                                action: _actionController,
                                enemyName: enemyName,
                                maxGuard: maxGuard,
                                before:
                                    combat?.enemyGuardBefore ?? currentGuard,
                                after: combat?.enemyGuardAfter ?? currentGuard,
                                animate: cue != null,
                              ),
                            ),
                          if (cue == null && hasTelegraph) ...[
                            const SizedBox(height: 8),
                            ExpeditionTelegraphChip(
                              attackName: battle?.enemy.intent.name ??
                                  encounter?.attackName ??
                                  '수호자의 공격',
                              text: currentTelegraph,
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (cue != null)
                    Positioned.fill(
                      child: _AnimatedCombatLabels(
                        action: _actionController,
                        cue: cue,
                        combat: combat,
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

/// 수호자만 ambient/action 틱을 구독해 나머지 무대의 재빌드를 막는다.
class _AnimatedGuardian extends StatelessWidget {
  const _AnimatedGuardian({
    required this.action,
    required this.ambient,
    required this.cue,
    required this.combat,
    required this.reduceMotion,
    required this.imageCacheWidth,
    this.enemyKind = 'guardian',
    this.enemyCode = '',
  });

  final Animation<double> action;
  final Animation<double> ambient;
  final ExpeditionActionCue? cue;
  final ExpeditionCombatFeedback? combat;
  final bool reduceMotion;
  final int imageCacheWidth;

  /// 'tangle'이면 현재 웨이브 코드에 대응하는 전용 상태 원화를 그린다.
  final String enemyKind;
  final String enemyCode;

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
                    ExpeditionCombatTimeline.segment(
                      progress,
                      partyContact - .07,
                      partyContact,
                    ),
                    1 - hitExit,
                  )
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
                    partyContact - .03,
                    partyContact + .22,
                  )
                : 0.0;
            final guardianFlash = cue?.dealsGuardianDamage == true
                ? math.sin(
                    ExpeditionCombatTimeline.segment(
                          progress,
                          partyContact - .02,
                          partyContact + .14,
                        ) *
                        math.pi,
                  )
                : 0.0;
            final idle =
                reduceMotion ? 0.0 : math.sin(ambient.value * math.pi * 2);
            final attack = cue?.playsEnemyAttack == true &&
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
            final offset = Offset(
                  -attack * 20 +
                      math.sin(guardianHit * math.pi * 7) *
                          math.sin(guardianHit * math.pi) *
                          7,
                  idle * 2.4 + attack * 6,
                ) +
                shake;

            if (enemyKind == 'tangle') {
              // 상태별 알파 원화를 한 장만 유지한다. 반투명 레이어를 매 프레임
              // 겹치지 않아 작은 기기에서도 saveLayer 비용과 메모리 피크를 막는다.
              final state = defeatedBlend > .001
                  ? 'release'
                  : hitBlend > .001
                      ? 'hit'
                      : attackBlend > .001
                          ? 'attack'
                          : 'idle';
              return Transform.translate(
                offset: offset,
                child: Transform.scale(
                  scale: 1 + idle * .01 + attack * .045,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Align(
                        alignment: const Alignment(0, .83),
                        child: FractionallySizedBox(
                          widthFactor: .58,
                          child: Container(
                            height: 16,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: RadialGradient(
                                colors: [
                                  Colors.black.withAlpha(90),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _GuardianImage(
                        key: ValueKey('tangle-body-$state'),
                        asset: expeditionTangleAssetPath(enemyCode, state),
                        cacheWidth: imageCacheWidth,
                        mobileAssetWidth: expeditionMobileTangleWidth,
                      ),
                    ],
                  ),
                ),
              );
            }
            return Transform.translate(
              offset: offset,
              child: Transform.scale(
                scale: 1 + idle * .01 + attack * .045,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: const Alignment(0, .83),
                      child: FractionallySizedBox(
                        widthFactor: .68,
                        child: Container(
                          height: 18,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: RadialGradient(
                              colors: [
                                Colors.black.withAlpha(105),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: (1 -
                              math.max(
                                defeatedBlend,
                                math.max(hitBlend, attackBlend),
                              ))
                          .clamp(0.0, 1.0)
                          .toDouble(),
                      child: _GuardianImage(
                        key: const ValueKey('ledger-keeper-idle'),
                        asset: expeditionLedgerKeeperIdleAsset,
                        cacheWidth: imageCacheWidth,
                      ),
                    ),
                    if (hitBlend > .001)
                      Opacity(
                        opacity: hitBlend,
                        child: _GuardianImage(
                          key: const ValueKey('ledger-keeper-hit'),
                          asset: expeditionLedgerKeeperHitAsset,
                          cacheWidth: imageCacheWidth,
                        ),
                      ),
                    if (attackBlend > .001)
                      Opacity(
                        opacity: attackBlend,
                        child: _GuardianImage(
                          key: const ValueKey('ledger-keeper-attack'),
                          asset: expeditionLedgerKeeperAttackAsset,
                          cacheWidth: imageCacheWidth,
                        ),
                      ),
                    if (defeatedBlend > .001)
                      Opacity(
                        opacity: defeatedBlend,
                        child: _GuardianImage(
                          key: const ValueKey('ledger-keeper-defeated'),
                          asset: expeditionLedgerKeeperDefeatedAsset,
                          cacheWidth: imageCacheWidth,
                        ),
                      ),
                    if (!reduceMotion && guardianFlash > .02)
                      Opacity(
                        opacity: guardianFlash * .72,
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcATop,
                          ),
                          child: _GuardianImage(
                            asset: expeditionLedgerKeeperHitAsset,
                            cacheWidth: imageCacheWidth,
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

class _GuardianImage extends StatelessWidget {
  const _GuardianImage({
    super.key,
    required this.asset,
    required this.cacheWidth,
    this.mobileAssetWidth = expeditionMobileGuardianWidth,
  });

  final String asset;
  final int cacheWidth;
  final int mobileAssetWidth;

  @override
  Widget build(BuildContext context) => Image(
        image: expeditionRuntimeImageProvider(
          assetPath: asset,
          cacheWidth: cacheWidth,
          mobileAssetWidth: mobileAssetWidth,
        ),
        fit: BoxFit.contain,
        alignment: Alignment.bottomCenter,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      );
}

/// 캐릭터 원화는 child 슬롯에 고정하고 위치 변환만 매 프레임 갱신한다.
class _AnimatedCombatActor extends StatelessWidget {
  const _AnimatedCombatActor({
    required this.action,
    required this.cue,
    required this.actor,
    required this.stage,
    required this.scale,
    required this.width,
    required this.height,
    required this.reduceMotion,
  });

  final Animation<double> action;
  final ExpeditionActionCue? cue;
  final ExpeditionMember? actor;
  final int stage;
  final double scale;
  final double width;
  final double height;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final pose = cue == null
        ? PlantSpritePose.idle
        : cue!.playsEnemyAttack && !cue!.playsPartyAttack
            ? PlantSpritePose.diary
            : cue!.effectKey == 'safe_guard'
                ? PlantSpritePose.diary
                : PlantSpritePose.grow;
    final artwork = RepaintBoundary(
      key: const ValueKey('expedition-combat-actor-artwork'),
      child: PlantView(
        stage: stage,
        form: PlantGrowthForm.fromCode(cue?.form ?? actor!.form),
        speciesCode: cue?.speciesCode ?? actor!.speciesCode,
        speciesName: cue?.speciesName ?? actor!.speciesName,
        spritePose: pose,
        outfitKey: cue?.outfitKey ?? actor?.outfitKey,
        width: width,
        height: height,
      ),
    );
    return Transform.scale(
      key: const ValueKey('expedition-combat-actor'),
      scale: scale,
      alignment: Alignment.bottomLeft,
      child: AnimatedBuilder(
        animation: action,
        child: artwork,
        builder: (context, child) {
          final progress = cue == null ? 0.0 : action.value;
          final shake = cue?.isGuardianExchange == true && !reduceMotion
              ? cue?.playsEnemyAttack == true
                  ? ExpeditionCombatTimeline.impactShake(progress, cue) * .35
                  : cue?.dealsGuardianDamage == true
                      ? ExpeditionCombatTimeline.partyImpactShake(
                              progress, cue) *
                          .18
                      : Offset.zero
              : Offset.zero;
          final cast = cue?.playsPartyAttack == true
              ? math.sin(
                  ExpeditionCombatTimeline.segment(progress, .04, .46) *
                      math.pi,
                )
              : 0.0;
          final recoil = cue?.playsEnemyAttack == true
              ? math.sin(
                  ExpeditionCombatTimeline.segment(progress, .56, .82) *
                      math.pi,
                )
              : 0.0;
          return Transform.translate(
            offset: (reduceMotion
                    ? Offset.zero
                    : ExpeditionCombatTimeline.actorOffset(progress, cue)) +
                shake,
            child: Transform.rotate(
              angle: -cast * .035 + recoil * .045,
              alignment: Alignment.bottomCenter,
              child: Transform.scale(
                scaleX: 1 + cast * .055 - recoil * .025,
                scaleY: 1 - cast * .025 + recoil * .035,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 현재 행동 대원 뒤에서 나머지 탐험대가 실제 성장형과 의상을 유지한다.
/// 전투원 수가 늘어도 무대 밀도를 일정하게 유지하도록 후열은 최대 두 명만 보인다.
class _CombatPartyFormation extends StatelessWidget {
  const _CombatPartyFormation({
    required this.party,
    required this.battle,
    required this.activeMemberId,
  });

  final List<ExpeditionMember> party;
  final ExpeditionBattle? battle;
  final int? activeMemberId;

  @override
  Widget build(BuildContext context) {
    final members = party
        .where((member) => member.id != activeMemberId)
        .take(2)
        .toList(growable: false);
    if (members.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      key: const ValueKey('expedition-combat-party-lineup'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < members.length; index++)
            Positioned(
              left: 4 + index * 48,
              bottom: 20 + index * 9,
              width: 78,
              height: 112,
              child: _BacklineMember(
                member: members[index],
                status: battle?.party
                    .where((item) => item.memberId == members[index].id)
                    .firstOrNull,
              ),
            ),
        ],
      ),
    );
  }
}

class _BacklineMember extends StatelessWidget {
  const _BacklineMember({required this.member, required this.status});

  final ExpeditionMember member;
  final ExpeditionBattleMember? status;

  @override
  Widget build(BuildContext context) {
    final health = status == null || status!.maxHp <= 0
        ? 1.0
        : (status!.hp / status!.maxHp).clamp(0.0, 1.0);
    final formationScale = switch (member.stage) {
      <= 2 => 1.5,
      3 => 1.24,
      4 => 1.1,
      _ => 1.0,
    };
    return Opacity(
      opacity: status?.isAlive == false ? .42 : .76,
      child: Column(
        children: [
          Expanded(
            child: Transform.scale(
              scale: formationScale,
              alignment: Alignment.bottomCenter,
              child: PlantView(
                stage: member.stage,
                form: PlantGrowthForm.fromCode(member.form),
                speciesCode: member.speciesCode,
                speciesName: member.speciesName,
                spritePose: PlantSpritePose.idle,
                outfitKey: member.outfitKey,
                width: 78,
                height: 94,
              ),
            ),
          ),
          Container(
            width: 46,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(110),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: health,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: health > .35
                      ? const Color(0xFF8EE0A8)
                      : const Color(0xFFFF8D78),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardianIntentLayer extends StatelessWidget {
  const _GuardianIntentLayer({
    required this.ambient,
    required this.reduceMotion,
    required this.target,
  });

  final Animation<double> ambient;
  final bool reduceMotion;
  final String target;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: ambient,
          builder: (context, _) => CustomPaint(
            painter: ExpeditionGuardianIntentPainter(
              phase: ambient.value,
              reduceMotion: reduceMotion,
              target: target,
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
  });

  final Animation<double> action;
  final String enemyName;
  final int maxGuard;
  final int before;
  final int after;
  final bool animate;

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
          ),
        ),
      );
}

class _AnimatedCombatLabels extends StatelessWidget {
  const _AnimatedCombatLabels({
    required this.action,
    required this.cue,
    required this.combat,
  });

  final Animation<double> action;
  final ExpeditionActionCue cue;
  final ExpeditionCombatFeedback? combat;

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
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (progress < .86)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: ExpeditionActorBadge(
                      actorName: cue.actorName,
                      actionName: cue.title,
                    ),
                  ),
                if (progress >= partyContact && (combat?.guardDamage ?? 0) > 0)
                  Positioned(
                    right: 54,
                    top: 104 -
                        ExpeditionCombatTimeline.segment(
                              progress,
                              partyContact,
                              partyContact + .25,
                            ) *
                            18,
                    child: ExpeditionDamageNumber(
                      label: '-${combat!.guardDamage}',
                      caption: '수호 장벽 피해',
                      color: expeditionCombatEffectColor(cue.effectKey),
                      opacity: ExpeditionCombatTimeline.floatingOpacity(
                        progress,
                        partyContact,
                        partyContact + .40,
                      ),
                    ),
                  ),
                if (cue.playsEnemyAttack && progress >= .18)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 12,
                    child: Center(
                      child: ExpeditionAttackCallout(
                        attackName: combat!.attackName,
                        progress: progress,
                      ),
                    ),
                  ),
                if (cue.playsEnemyAttack && progress >= enemyContact)
                  Positioned(
                    left: 58,
                    bottom: 78 +
                        ExpeditionCombatTimeline.segment(
                              progress,
                              enemyContact,
                              enemyContact + .34,
                            ) *
                            12,
                    child: ExpeditionDamageNumber(
                      label: combat!.counterDamage > 0
                          ? '-${combat!.counterDamage}'
                          : combat!.counterResult == 'calmed'
                              ? '진정'
                              : '방어',
                      caption: combat!.counterDamage > 0
                          ? '${combat!.damageTarget} 피해'
                          : combat!.counterResult == 'calmed'
                              ? '교전 없이 이탈'
                              : '${combat!.attackName} 차단',
                      color: combat!.counterDamage > 0
                          ? const Color(0xFFFF8D78)
                          : const Color(0xFF9FE7D2),
                      opacity: ExpeditionCombatTimeline.floatingOpacity(
                        progress,
                        enemyContact,
                        enemyContact + .38,
                      ),
                    ),
                  ),
                if (progress >= .86)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
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
