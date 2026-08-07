import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../home/domain/plant.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/expedition_models.dart';
import 'expedition_action_cue.dart';
import 'expedition_combat_audio.dart';
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
    required this.actor,
    this.party = const [],
    required this.cue,
    required this.onCueCompleted,
  });

  final ExpeditionEncounter? encounter;
  final ExpeditionBattle? battle;
  final ExpeditionMember? actor;
  final List<ExpeditionMember> party;
  final ExpeditionActionCue? cue;
  final VoidCallback onCueCompleted;

  @override
  State<ExpeditionEncounterStage> createState() =>
      _ExpeditionEncounterStageState();
}

class _ExpeditionEncounterStageState extends State<ExpeditionEncounterStage>
    with TickerProviderStateMixin {
  late final AnimationController _actionController;
  late final AnimationController _ambientController;
  late final ExpeditionCombatAudio _audio;
  Timer? _holdTimer;
  int? _playingCueId;
  double _previousProgress = 0;
  String? _precacheSignature;
  bool _effectStartsPrecached = false;

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
    _audio = ExpeditionCombatAudio();
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
                ? ExpeditionCombatTimeline.terminalOutcomeHoldDuration
                : cue.playsEnemyAttack
                    ? ExpeditionCombatTimeline.enemyHoldDuration
                    : ExpeditionCombatTimeline.commandHoldDuration
            : ExpeditionCombatTimeline.resultHoldDuration;
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
    _precacheGuardianImages();
    _precacheEffectStarts();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ambientController
        ..stop()
        ..value = .5;
    } else if (!_ambientController.isAnimating) {
      _ambientController.repeat();
    }
    _playCueIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ExpeditionEncounterStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cue?.id != widget.cue?.id) {
      _playCueIfNeeded();
    }
  }

  int _guardianCacheWidth(BuildContext context) {
    final media = MediaQuery.of(context);
    return (media.size.width * .55 * media.devicePixelRatio * 1.15)
        .round()
        .clamp(256, 1024);
  }

  void _precacheGuardianImages() {
    final cacheWidth = _guardianCacheWidth(context);
    final signature = '$cacheWidth:${expeditionCombatAssets.join('|')}';
    if (_precacheSignature == signature) return;
    _precacheSignature = signature;
    for (final asset in expeditionCombatAssets) {
      final provider = expeditionRuntimeImageProvider(
        assetPath: asset,
        cacheWidth: cacheWidth,
        mobileAssetWidth: expeditionMobileGuardianWidth,
      );
      // 디코드는 첫 공격보다 먼저 시작하되 화면 진입은 기다리지 않는다.
      precacheImage(provider, context).ignore();
    }
  }

  void _precacheEffectStarts() {
    if (_effectStartsPrecached) return;
    _effectStartsPrecached = true;
    final fullSequences = <String>{
      if (widget.battle != null || widget.encounter?.kind == 'guardian')
        'enemy_wave',
      if (widget.battle != null)
        for (final member in widget.battle!.party) ...{
          if (member.kit.basic.effectKey != null) member.kit.basic.effectKey!,
          if (member.kit.skill.effectKey != null) member.kit.skill.effectKey!,
          'safe_guard',
        },
    };
    for (final asset in <String>{
      ...expeditionCombatEffectFirstFrames,
      for (final effectKey in fullSequences)
        ...expeditionCombatEffectAssets(effectKey),
    }) {
      precacheImage(AssetImage(asset), context).ignore();
    }
  }

  Future<void> _precacheCueEffects(ExpeditionActionCue cue) async {
    final effectKeys = <String>{
      if (cue.playsPartyAttack) cue.effectKey,
      if (cue.playsEnemyAttack) 'enemy_wave',
    };
    await Future.wait<void>([
      for (final effectKey in effectKeys)
        for (final asset in expeditionCombatEffectAssets(effectKey))
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
    _actionController.duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 1)
        : cue.isCombatRound
            ? cue.playsEnemyAttack
                ? ExpeditionCombatTimeline.enemyCommandDuration
                : ExpeditionCombatTimeline.partyCommandDuration
            : cue.isGuardianExchange
                ? ExpeditionCombatTimeline.guardianDuration
                : ExpeditionCombatTimeline.skillDuration;
    _actionController.forward(from: 0);
    if (cue.isCombatRound) {
      unawaited(
        _audio.play(
          cue.effectKey == 'safe_guard'
              ? ExpeditionCombatSound.guard
              : cue.playsEnemyAttack
                  ? ExpeditionCombatSound.enemy
                  : ExpeditionCombatSound.command,
          volume: cue.playsEnemyAttack ? .64 : .48,
        ),
      );
    }
  }

  void _handleTimelineFeedback() {
    final cue = widget.cue;
    if (cue?.isGuardianExchange != true) {
      _previousProgress = _actionController.value;
      return;
    }
    final progress = _actionController.value;
    if (cue!.dealsGuardianDamage &&
        _previousProgress < .34 &&
        progress >= .34) {
      HapticFeedback.lightImpact();
      unawaited(
        _audio.play(
          cue.weaknessHit
              ? ExpeditionCombatSound.weakness
              : ExpeditionCombatSound.hit,
          volume: cue.weaknessHit ? .78 : .66,
        ),
      );
    }
    if (cue.isTerminalCombatOutcome &&
        _previousProgress < .86 &&
        progress >= .86) {
      if (cue.combatResult == 'victory') {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.heavyImpact();
      }
      unawaited(
        _audio.play(
          cue.combatResult == 'victory'
              ? ExpeditionCombatSound.victory
              : ExpeditionCombatSound.defeat,
          volume: .82,
        ),
      );
    }
    if (cue.playsEnemyAttack && _previousProgress < .62 && progress >= .62) {
      if ((cue.combat?.counterDamage ?? 0) > 0) {
        HapticFeedback.mediumImpact();
        unawaited(_audio.play(ExpeditionCombatSound.hit, volume: .76));
      } else {
        HapticFeedback.selectionClick();
        unawaited(_audio.play(ExpeditionCombatSound.guard, volume: .58));
      }
    }
    _previousProgress = progress;
  }

  @override
  void dispose() {
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
    final semantics = cue == null
        ? '$enemyName 조우. $currentTelegraph'
        : cue.isTerminalCombatOutcome
            ? cue.outcome ?? '수호전이 끝났어요.'
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
              final actorWidth = math.min(152.0, size.width * .40);
              final actorHeight = size.height * .82;
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
                      bottom: 1,
                      width: size.width * .39,
                      height: size.height * .52,
                      child: _CombatPartyFormation(
                        party: widget.party,
                        battle: battle,
                        activeMemberId: cue?.actorId ?? widget.actor?.id,
                      ),
                    ),
                  if (guardianActive)
                    Positioned(
                      right: -size.width * .035,
                      top: size.height * .035,
                      width: size.width * .62,
                      height: size.height * .84,
                      child: _AnimatedGuardian(
                        action: _actionController,
                        ambient: _ambientController,
                        cue: cue,
                        combat: combat,
                        reduceMotion: reduceMotion,
                        imageCacheWidth: _guardianCacheWidth(context),
                      ),
                    ),
                  if (cue != null || widget.actor != null)
                    Positioned(
                      left: size.width * .035,
                      bottom: actorBottom,
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
                  if (enemyName != null)
                    Positioned(
                      top: 47,
                      left: 10,
                      width: math.min(200.0, size.width * .53),
                      child: _AnimatedGuardHud(
                        action: _actionController,
                        enemyName: enemyName,
                        maxGuard: maxGuard,
                        before: combat?.enemyGuardBefore ?? currentGuard,
                        after: combat?.enemyGuardAfter ?? currentGuard,
                        animate: cue != null,
                      ),
                    ),
                  if (cue == null && (encounter != null || battle != null))
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: ExpeditionTelegraphChip(
                        attackName: battle?.enemy.intent.name ??
                            encounter?.attackName ??
                            '수호자의 공격',
                        text: currentTelegraph,
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
  });

  final Animation<double> action;
  final Animation<double> ambient;
  final ExpeditionActionCue? cue;
  final ExpeditionCombatFeedback? combat;
  final bool reduceMotion;
  final int imageCacheWidth;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([action, ambient]),
          builder: (context, _) {
            final progress = cue == null ? 0.0 : action.value;
            final defeatedBlend = cue?.combatResult == 'victory'
                ? ExpeditionCombatTimeline.segment(progress, .68, .78)
                : 0.0;
            final hitExit = cue?.combatResult == 'victory'
                ? ExpeditionCombatTimeline.segment(progress, .68, .78)
                : ExpeditionCombatTimeline.segment(progress, .52, .61);
            final hitBlend = cue?.dealsGuardianDamage == true
                ? math.min(
                    ExpeditionCombatTimeline.segment(progress, .27, .34),
                    1 - hitExit,
                  )
                : 0.0;
            final attackBlend = cue?.playsEnemyAttack == true &&
                    combat?.counterResult != 'calmed'
                ? math.min(
                      ExpeditionCombatTimeline.segment(progress, .54, .61),
                      1 - ExpeditionCombatTimeline.segment(progress, .84, .88),
                    ) *
                    (1 - defeatedBlend) *
                    (1 - hitBlend)
                : 0.0;
            final guardianHit = cue?.dealsGuardianDamage == true
                ? ExpeditionCombatTimeline.segment(progress, .31, .56)
                : 0.0;
            final guardianFlash = cue?.dealsGuardianDamage == true
                ? math.sin(
                    ExpeditionCombatTimeline.segment(progress, .32, .48) *
                        math.pi,
                  )
                : 0.0;
            final idle =
                reduceMotion ? 0.0 : math.sin(ambient.value * math.pi * 2);
            final attack = cue?.playsEnemyAttack == true &&
                    combat?.counterResult != 'calmed'
                ? math.sin(
                    ExpeditionCombatTimeline.segment(progress, .49, .80) *
                        math.pi,
                  )
                : 0.0;
            final shake = cue?.isGuardianExchange == true && !reduceMotion
                ? cue?.playsEnemyAttack == true
                    ? ExpeditionCombatTimeline.impactShake(progress)
                    : cue?.dealsGuardianDamage == true
                        ? ExpeditionCombatTimeline.partyImpactShake(progress)
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
  });

  final String asset;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) => Image(
        image: expeditionRuntimeImageProvider(
          assetPath: asset,
          cacheWidth: cacheWidth,
          mobileAssetWidth: expeditionMobileGuardianWidth,
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
                  ? ExpeditionCombatTimeline.impactShake(progress) * .35
                  : cue?.dealsGuardianDamage == true
                      ? ExpeditionCombatTimeline.partyImpactShake(progress) *
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
            offset: ExpeditionCombatTimeline.actorOffset(progress, cue) + shake,
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
  });

  final Animation<double> ambient;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: ambient,
          builder: (context, _) => CustomPaint(
            painter: ExpeditionGuardianIntentPainter(
              phase: ambient.value,
              reduceMotion: reduceMotion,
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
                if (progress >= .32 && (combat?.guardDamage ?? 0) > 0)
                  Positioned(
                    right: 54,
                    top: 104 -
                        ExpeditionCombatTimeline.segment(
                              progress,
                              .32,
                              .57,
                            ) *
                            18,
                    child: ExpeditionDamageNumber(
                      label: '-${combat!.guardDamage}',
                      caption: '수호 장벽 피해',
                      color: expeditionCombatEffectColor(cue.effectKey),
                      opacity: ExpeditionCombatTimeline.floatingOpacity(
                        progress,
                        .32,
                        .72,
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
                if (cue.playsEnemyAttack && progress >= .56)
                  Positioned(
                    left: 58,
                    bottom: 78 +
                        ExpeditionCombatTimeline.segment(progress, .56, .9) *
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
                        .56,
                        .94,
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
