import '../domain/expedition_models.dart';
import 'expedition_combat_effect_catalog.dart';

enum ExpeditionActionCueKind {
  skill,
  resolution,
  combatParty,
  combatEnemy,
  bossPhase,
}

class ExpeditionActionCue {
  const ExpeditionActionCue({
    required this.id,
    required this.kind,
    required this.actorName,
    required this.actorId,
    required this.speciesCode,
    required this.speciesName,
    required this.stage,
    required this.form,
    this.outfitKey,
    required this.title,
    required this.effectKey,
    required this.outcome,
    required this.combat,
    this.weaknessHit = false,
    this.combatResult,
    this.motionProfile,
    this.motion,
    this.vfxFamily,
    this.kelFallbackFamily,
    this.fusionVfxFamily,
    this.presentationTier = 1,
    this.vfxIntensity = .86,
    this.audioLayer = 'light',
    this.cameraProfile = 'steady',
    this.emotionVfxPrimary,
    this.emotionVfxSecondary,
    this.contactMaterial,
    this.releaseRegionCode,
    this.skillCode,
  });

  final int id;
  final ExpeditionActionCueKind kind;
  final String actorName;
  final int actorId;
  final String speciesCode;
  final String speciesName;
  final int stage;
  final String form;
  final String? outfitKey;
  final String title;
  final String effectKey;
  final String? outcome;
  final ExpeditionCombatFeedback? combat;
  final bool weaknessHit;
  final String? combatResult;
  final String? motionProfile;
  final ExpeditionCombatMotion? motion;
  final String? vfxFamily;
  final String? kelFallbackFamily;
  final String? fusionVfxFamily;
  final int presentationTier;
  final double vfxIntensity;
  final String audioLayer;
  final String cameraProfile;
  final String? emotionVfxPrimary;
  final String? emotionVfxSecondary;

  /// 접촉 프레임에서 어떤 재질이 부딪히는지. 서버가 판정한 값이며 구버전
  /// 응답에서는 `null`이라 기존 공용 타격음으로 떨어진다.
  final String? contactMaterial;

  /// 이 행동으로 엉킴 하나가 풀려 제자리로 돌아갔다면 그 지역 코드다.
  /// 연출이 끝난 뒤 지역별 두 음 풀려남 cadence를 한 번 재생한다.
  final String? releaseRegionCode;

  /// 지금 쓰인 스킬(또는 적 공격)의 코드. 이 값으로 그 행동만의 소리를 고른다.
  /// 서버가 알려 주지 않는 구버전 응답에서는 `null`이고 공용음으로 떨어진다.
  final String? skillCode;

  bool get isGuardianExchange => combat?.kind == 'guardian';
  bool get isCombatRound =>
      kind == ExpeditionActionCueKind.combatParty ||
      kind == ExpeditionActionCueKind.combatEnemy ||
      kind == ExpeditionActionCueKind.bossPhase;
  bool get isBossPhase => kind == ExpeditionActionCueKind.bossPhase;
  bool get playsPartyAttack =>
      kind != ExpeditionActionCueKind.combatEnemy &&
      kind != ExpeditionActionCueKind.bossPhase &&
      combat?.counterResult != 'calmed';
  bool get playsPartyEffect => playsPartyAttack || isBossPhase;
  bool get playsEnemyAttack =>
      kind == ExpeditionActionCueKind.combatEnemy ||
      (kind == ExpeditionActionCueKind.resolution && isGuardianExchange);
  ExpeditionCombatEffectSpec get partyEffect => resolveExpeditionCombatEffect(
        vfxFamily: vfxFamily,
        kelFallbackFamily: kelFallbackFamily,
        legacyEffectKey: effectKey,
      );
  ExpeditionCombatEffectSpec? get fusionEffect => fusionVfxFamily == null
      ? null
      : resolveExpeditionCombatEffect(vfxFamily: fusionVfxFamily);
  ExpeditionCombatEffectSpec get enemyEffect =>
      kind == ExpeditionActionCueKind.combatEnemy
          ? resolveExpeditionCombatEffect(
              vfxFamily: vfxFamily,
              kelFallbackFamily: kelFallbackFamily,
              legacyEffectKey: effectKey,
            )
          : resolveExpeditionCombatEffect(
              vfxFamily: 'guardian.enemy-wave',
              legacyEffectKey: 'enemy_wave',
            );
  String get enemyEffectKey =>
      enemyEffect.effectKeys.firstOrNull ?? 'enemy_wave';

  /// 적 공격이 대원에게 닿는 순간의 재질.
  ///
  /// 받아 냈다면 날아온 물건이 아니라 우리 방어가 내는 소리라 `guard`다. 눈을
  /// 떼고 있어도 `맞았다`와 `막았다`가 서로 다른 소리로 구분돼야 한다.
  String? get enemyContactMaterial =>
      (combat?.counterDamage ?? 0) > 0 ? contactMaterial : 'guard';

  bool get dealsGuardianDamage =>
      playsPartyAttack && (combat?.guardDamage ?? 0) > 0;
  bool get isTerminalCombatOutcome => combatResult != null;

  factory ExpeditionActionCue.skill({
    required int id,
    required ExpeditionMember member,
    required ExpeditionSkill skill,
  }) =>
      ExpeditionActionCue(
        id: id,
        kind: ExpeditionActionCueKind.skill,
        actorName: member.name,
        actorId: member.id,
        speciesCode: member.speciesCode,
        speciesName: member.speciesName,
        stage: member.stage,
        form: member.form,
        outfitKey: member.outfitKey,
        title: skill.name,
        effectKey: _skillEffectKey(member, skill),
        outcome: null,
        combat: null,
        skillCode: skill.code,
      );

  factory ExpeditionActionCue.resolution({
    required int id,
    required ExpeditionResolution resolution,
    required ExpeditionMember member,
  }) =>
      ExpeditionActionCue(
        id: id,
        kind: ExpeditionActionCueKind.resolution,
        actorName: resolution.actorName,
        actorId: member.id,
        speciesCode: member.speciesCode,
        speciesName: member.speciesName,
        stage: member.stage,
        form: member.form,
        outfitKey: member.outfitKey,
        title: resolution.choice,
        effectKey: resolution.combat?.effectKey ?? 'echo_wave',
        outcome: resolution.outcome,
        combat: resolution.combat,
      );

  factory ExpeditionActionCue.combatRound({
    required int id,
    required ExpeditionBattleEvent event,
    required ExpeditionMember member,
    required ExpeditionBattleEnemy enemy,
    String? terminalResult,
    String? terminalCaption,
    String? releaseRegionCode,
  }) {
    final enemyAction = event.isEnemyAction;
    final target = event.targets.firstOrNull;
    return ExpeditionActionCue(
      id: id,
      kind: enemyAction
          ? ExpeditionActionCueKind.combatEnemy
          : ExpeditionActionCueKind.combatParty,
      actorName: enemyAction ? enemy.name : event.actorName ?? member.name,
      actorId: member.id,
      speciesCode: member.speciesCode,
      speciesName: member.speciesName,
      stage: member.stage,
      form: member.form,
      outfitKey: member.outfitKey,
      title: event.actionName ?? (enemyAction ? enemy.intent.name : '공명 공격'),
      effectKey: event.effectKey ?? (enemyAction ? 'enemy_wave' : 'echo_wave'),
      outcome: terminalCaption ?? event.caption,
      weaknessHit: event.weaknessHit,
      combatResult: terminalResult,
      combat: ExpeditionCombatFeedback(
        kind: 'guardian',
        enemyName: enemy.name,
        enemyMaxGuard: enemy.maxGuard,
        enemyGuardBefore: event.enemyGuardBefore ?? enemy.guard,
        enemyGuardAfter: event.enemyGuardAfter ?? enemy.guard,
        guardDamage: enemyAction ? 0 : event.damage,
        attackName: event.actionName ?? enemy.intent.name,
        telegraph: event.caption,
        damageTarget: target?.name ?? member.name,
        counterDamage: target?.damage ?? 0,
        counterResult: enemyAction
            ? (target?.damage ?? 0) > 0
                ? 'hit'
                : 'guarded'
            : 'none',
        effectKey:
            event.effectKey ?? (enemyAction ? 'enemy_wave' : 'echo_wave'),
      ),
      motionProfile: event.motionProfile,
      motion: event.motion,
      vfxFamily: event.vfxFamily,
      kelFallbackFamily: event.kelFallbackFamily,
      fusionVfxFamily: event.fusionVfxFamily,
      presentationTier: event.presentationTier,
      vfxIntensity: event.vfxIntensity,
      audioLayer: event.audioLayer,
      cameraProfile: event.cameraProfile,
      emotionVfxPrimary: event.emotionVfxPrimary,
      emotionVfxSecondary: event.emotionVfxSecondary,
      contactMaterial: event.contactMaterial,
      releaseRegionCode: releaseRegionCode,
      skillCode: event.skillCode,
    );
  }

  factory ExpeditionActionCue.bossPhase({
    required int id,
    required ExpeditionBattleEvent event,
    required ExpeditionMember member,
    required ExpeditionBattleEnemy enemy,
  }) =>
      ExpeditionActionCue(
        id: id,
        kind: ExpeditionActionCueKind.bossPhase,
        actorName: enemy.name,
        actorId: member.id,
        speciesCode: member.speciesCode,
        speciesName: member.speciesName,
        stage: member.stage,
        form: member.form,
        outfitKey: member.outfitKey,
        title: event.phaseName ?? '봉인 자세 전환',
        effectKey: event.effectKey ?? 'boss_phase_break',
        outcome: event.caption,
        combat: ExpeditionCombatFeedback(
          kind: 'guardian',
          enemyName: enemy.name,
          enemyMaxGuard: enemy.maxGuard,
          enemyGuardBefore: enemy.guard,
          enemyGuardAfter: enemy.guard,
          guardDamage: 0,
          attackName: event.phaseName ?? '봉인 자세 전환',
          telegraph: event.caption,
          damageTarget: '',
          counterDamage: 0,
          counterResult: 'phase',
          effectKey: event.effectKey ?? 'boss_phase_break',
        ),
        motionProfile: event.motionProfile,
        motion: event.motion,
        vfxFamily: event.vfxFamily,
        kelFallbackFamily: event.kelFallbackFamily,
        presentationTier: event.presentationTier,
        vfxIntensity: event.vfxIntensity,
        audioLayer: event.audioLayer,
        cameraProfile: 'ultimate',
      );
}

String _skillEffectKey(ExpeditionMember member, ExpeditionSkill skill) {
  final code = skill.code;
  if (code.contains('gumiho') || code.contains('ember')) return 'ember_arc';
  if (code.contains('magical') || code.contains('sparkling')) {
    return 'prism_burst';
  }
  if (code.contains('venom') || code.contains('ninja')) return 'venom_seam';
  if (code.contains('rainy')) return 'mist_dash';
  if (code.contains('moonlit') || code.contains('aloof')) {
    return 'insight_arc';
  }
  if (code.contains('sunny') || code.contains('baby')) return 'care_vines';
  return switch (member.form) {
    'ember' => 'ember_arc',
    'sparkling' => 'prism_burst',
    'rainy' => 'mist_dash',
    'moonlit' => 'insight_arc',
    'sunny' => 'care_vines',
    _ => 'echo_wave',
  };
}
