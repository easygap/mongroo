int _combatInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Map<String, dynamic> _combatMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _combatMaps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

class ExpeditionCombatCommand {
  const ExpeditionCombatCommand({
    required this.memberId,
    required this.action,
  });

  final int memberId;
  final String action;

  Map<String, dynamic> toJson() => {
        'member_id': memberId,
        'action': action,
      };
}

class ExpeditionBattle {
  const ExpeditionBattle({
    required this.status,
    required this.round,
    required this.maxRounds,
    required this.focus,
    required this.maxFocus,
    required this.enemy,
    required this.party,
    required this.lastExchange,
    required this.battleLog,
    this.pendingRound,
  });

  final String status;
  final int round;
  final int maxRounds;
  final int focus;
  final int maxFocus;
  final ExpeditionBattleEnemy enemy;
  final List<ExpeditionBattleMember> party;
  final List<ExpeditionBattleEvent> lastExchange;
  final List<String> battleLog;

  /// 순차 명령 진행 상태. 구버전 서버 응답에는 없을 수 있다.
  final ExpeditionBattlePendingRound? pendingRound;

  bool get isActive => status == 'active';
  List<ExpeditionBattleMember> get livingParty =>
      party.where((member) => member.isAlive).toList(growable: false);

  /// 이번 라운드에 아직 행동하지 않은 대원. 서버가 진행 상태를 주지 않으면
  /// 라운드 시작으로 간주해 살아 있는 전원을 돌려준다.
  List<ExpeditionBattleMember> get awaitingParty {
    final pending = pendingRound;
    if (pending == null) return livingParty;
    return party
        .where((member) => pending.awaiting.contains(member.memberId))
        .toList(growable: false);
  }

  bool hasActed(int memberId) =>
      pendingRound?.acted.contains(memberId) ?? false;

  factory ExpeditionBattle.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattle(
        status: json['status'] as String? ?? 'active',
        round: _combatInt(json['round'], 1),
        maxRounds: _combatInt(json['max_rounds'], 6),
        focus: _combatInt(json['focus']),
        maxFocus: _combatInt(json['max_focus'], 5),
        enemy: ExpeditionBattleEnemy.fromJson(_combatMap(json['enemy'])),
        party: _combatMaps(json['party'])
            .map(ExpeditionBattleMember.fromJson)
            .toList(growable: false),
        lastExchange: _combatMaps(json['last_exchange'])
            .map(ExpeditionBattleEvent.fromJson)
            .toList(growable: false),
        battleLog: json['battle_log'] is List
            ? (json['battle_log'] as List)
                .whereType<String>()
                .toList(growable: false)
            : const [],
        pendingRound: json['pending_round'] is Map<String, dynamic>
            ? ExpeditionBattlePendingRound.fromJson(
                json['pending_round'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ExpeditionBattlePendingRound {
  const ExpeditionBattlePendingRound({
    required this.acted,
    required this.awaiting,
  });

  final List<int> acted;
  final List<int> awaiting;

  factory ExpeditionBattlePendingRound.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattlePendingRound(
        acted: json['acted'] is List
            ? (json['acted'] as List)
                .whereType<num>()
                .map((value) => value.toInt())
                .toList(growable: false)
            : const [],
        awaiting: json['awaiting'] is List
            ? (json['awaiting'] as List)
                .whereType<num>()
                .map((value) => value.toInt())
                .toList(growable: false)
            : const [],
      );
}

class ExpeditionBattleEnemy {
  const ExpeditionBattleEnemy({
    required this.name,
    required this.guard,
    required this.maxGuard,
    required this.weakness,
    required this.weaknessLabel,
    required this.intent,
  });

  final String name;
  final int guard;
  final int maxGuard;
  final String weakness;
  final String weaknessLabel;
  final ExpeditionBattleIntent intent;

  factory ExpeditionBattleEnemy.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleEnemy(
        name: json['name'] as String? ?? '수호자',
        guard: _combatInt(json['guard']),
        maxGuard: _combatInt(json['max_guard'], 100),
        weakness: json['weakness'] as String? ?? 'insight',
        weaknessLabel: json['weakness_label'] as String? ?? '관찰',
        intent: ExpeditionBattleIntent.fromJson(_combatMap(json['intent'])),
      );
}

class ExpeditionBattleIntent {
  const ExpeditionBattleIntent({
    required this.code,
    required this.name,
    required this.telegraph,
    required this.target,
    required this.power,
  });

  final String code;
  final String name;
  final String telegraph;
  final String target;
  final int power;

  String get targetLabel => switch (target) {
        'all' => '탐험대 전체',
        'lowest' => '체력이 가장 낮은 대원',
        _ => '행동 순서 맨 앞 대원',
      };

  factory ExpeditionBattleIntent.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleIntent(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '수호자의 공격',
        telegraph: json['telegraph'] as String? ?? '',
        target: json['target'] as String? ?? 'front',
        power: _combatInt(json['power'], 1),
      );
}

class ExpeditionBattleMember {
  const ExpeditionBattleMember({
    required this.memberId,
    required this.name,
    required this.position,
    required this.isGuide,
    required this.speciesCode,
    required this.form,
    required this.hp,
    required this.maxHp,
    required this.guard,
    required this.kit,
  });

  final int memberId;
  final String name;
  final int position;
  final bool isGuide;
  final String speciesCode;
  final String form;
  final int hp;
  final int maxHp;
  final int guard;
  final ExpeditionBattleKit kit;

  bool get isAlive => hp > 0;

  factory ExpeditionBattleMember.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleMember(
        memberId: _combatInt(json['member_id']),
        name: json['name'] as String? ?? '탐험대원',
        position: _combatInt(json['position']),
        isGuide: json['is_guide'] == true,
        speciesCode: json['species_code'] as String? ?? '',
        form: json['form'] as String? ?? 'mosaic',
        hp: _combatInt(json['hp']),
        maxHp: _combatInt(json['max_hp'], 3),
        guard: _combatInt(json['guard']),
        kit: ExpeditionBattleKit.fromJson(_combatMap(json['kit'])),
      );
}

class ExpeditionBattleKit {
  const ExpeditionBattleKit({
    required this.affinity,
    required this.affinityLabel,
    required this.basic,
    required this.skill,
    required this.guard,
  });

  final String affinity;
  final String affinityLabel;
  final ExpeditionBattleAction basic;
  final ExpeditionBattleAction skill;
  final ExpeditionBattleAction guard;

  factory ExpeditionBattleKit.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleKit(
        affinity: json['affinity'] as String? ?? 'insight',
        affinityLabel: json['affinity_label'] as String? ?? '관찰',
        basic: ExpeditionBattleAction.fromJson(_combatMap(json['basic'])),
        skill: ExpeditionBattleAction.fromJson(_combatMap(json['skill'])),
        guard: ExpeditionBattleAction.fromJson(_combatMap(json['guard'])),
      );
}

class ExpeditionBattleAction {
  const ExpeditionBattleAction({
    required this.code,
    required this.name,
    required this.description,
    required this.power,
    required this.focusCost,
    required this.focusDelta,
    required this.affinity,
    required this.affinityLabel,
    required this.effectKey,
    required this.effect,
    required this.guard,
  });

  final String code;
  final String name;
  final String description;
  final int power;
  final int focusCost;
  final int focusDelta;
  final String? affinity;
  final String? affinityLabel;
  final String? effectKey;
  final String? effect;
  final int guard;

  factory ExpeditionBattleAction.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleAction(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        power: _combatInt(json['power']),
        focusCost: _combatInt(json['focus_cost']),
        focusDelta: _combatInt(json['focus_delta']),
        affinity: json['affinity'] as String?,
        affinityLabel: json['affinity_label'] as String?,
        effectKey: json['effect_key'] as String?,
        effect: json['effect'] as String?,
        guard: _combatInt(json['guard']),
      );
}

class ExpeditionBattleEvent {
  const ExpeditionBattleEvent({
    required this.sequence,
    required this.type,
    required this.memberId,
    required this.actorName,
    required this.action,
    required this.actionName,
    required this.effectKey,
    required this.weaknessHit,
    required this.damage,
    required this.enemyGuardBefore,
    required this.enemyGuardAfter,
    required this.focusAfter,
    required this.caption,
    required this.outcome,
    required this.targets,
  });

  final int sequence;
  final String type;
  final int? memberId;
  final String? actorName;
  final String? action;
  final String? actionName;
  final String? effectKey;
  final bool weaknessHit;
  final int damage;
  final int? enemyGuardBefore;
  final int? enemyGuardAfter;
  final int focusAfter;
  final String caption;
  final String? outcome;
  final List<ExpeditionBattleTarget> targets;

  bool get isPartyAction => type == 'party_action';
  bool get isEnemyAction => type == 'enemy_action';

  factory ExpeditionBattleEvent.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleEvent(
        sequence: _combatInt(json['sequence']),
        type: json['type'] as String? ?? '',
        memberId: json['member_id'] is num
            ? (json['member_id'] as num).toInt()
            : null,
        actorName: json['actor_name'] as String?,
        action: json['action'] as String?,
        actionName: json['action_name'] as String?,
        effectKey: json['effect_key'] as String?,
        weaknessHit: json['weakness_hit'] == true,
        damage: _combatInt(json['damage']),
        enemyGuardBefore: json['enemy_guard_before'] is num
            ? (json['enemy_guard_before'] as num).toInt()
            : null,
        enemyGuardAfter: json['enemy_guard_after'] is num
            ? (json['enemy_guard_after'] as num).toInt()
            : null,
        focusAfter: _combatInt(json['focus_after']),
        caption: json['caption'] as String? ?? '',
        outcome: json['outcome'] as String?,
        targets: _combatMaps(json['targets'])
            .map(ExpeditionBattleTarget.fromJson)
            .toList(growable: false),
      );
}

class ExpeditionBattleTarget {
  const ExpeditionBattleTarget({
    required this.memberId,
    required this.name,
    required this.damage,
    required this.blocked,
    required this.hpAfter,
  });

  final int memberId;
  final String name;
  final int damage;
  final int blocked;
  final int hpAfter;

  factory ExpeditionBattleTarget.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleTarget(
        memberId: _combatInt(json['member_id']),
        name: json['name'] as String? ?? '탐험대원',
        damage: _combatInt(json['damage']),
        blocked: _combatInt(json['blocked']),
        hpAfter: _combatInt(json['hp_after']),
      );
}
