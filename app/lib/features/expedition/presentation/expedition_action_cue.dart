import '../domain/expedition_models.dart';

enum ExpeditionActionCueKind {
  skill,
  resolution,
  combatParty,
  combatEnemy,
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

  bool get isGuardianExchange => combat?.kind == 'guardian';
  bool get isCombatRound =>
      kind == ExpeditionActionCueKind.combatParty ||
      kind == ExpeditionActionCueKind.combatEnemy;
  bool get playsPartyAttack =>
      kind != ExpeditionActionCueKind.combatEnemy &&
      combat?.counterResult != 'calmed';
  bool get playsEnemyAttack =>
      kind == ExpeditionActionCueKind.combatEnemy ||
      (kind == ExpeditionActionCueKind.resolution && isGuardianExchange);
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
    );
  }
}

String _skillEffectKey(ExpeditionMember member, ExpeditionSkill skill) {
  final code = skill.code;
  if (code.contains('gumiho') || code.contains('ember')) return 'ember_arc';
  if (code.contains('magical') || code.contains('sparkling')) {
    return 'prism_burst';
  }
  if (code.contains('ninja') || code.contains('rainy')) return 'mist_dash';
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
