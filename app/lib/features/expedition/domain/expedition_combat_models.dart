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
    this.version = 1,
    this.kelMapVersion = 1,
    this.pendingRound,
    this.enemyKind = 'guardian',
    this.wave,
  });

  final int version;
  final int kelMapVersion;
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

  /// 상대의 종류. 스테이지 전투의 엉킴은 'tangle', 수호짐승은 'guardian'.
  final String enemyKind;

  /// 웨이브 진행. 엉킴 웨이브 전투에만 있다.
  final ExpeditionBattleWave? wave;

  bool get isTangle => enemyKind == 'tangle';

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
        version: _combatInt(json['version'], 1),
        kelMapVersion: _combatInt(json['kel_map_version'], 1),
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
        enemyKind: json['enemy_kind'] as String? ?? 'guardian',
        wave: json['wave'] is Map<String, dynamic>
            ? ExpeditionBattleWave.fromJson(
                json['wave'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ExpeditionBattleWave {
  const ExpeditionBattleWave({
    required this.index,
    required this.count,
    required this.name,
  });

  final int index;
  final int count;
  final String name;

  factory ExpeditionBattleWave.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleWave(
        index: _combatInt(json['index'], 1),
        count: _combatInt(json['count'], 1),
        name: json['name'] as String? ?? '',
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
    this.elite = false,
    this.weakElement,
    this.weakElementLabel,
    this.resistElement,
    this.resistElementLabel,
    this.weakKel,
    this.weakKelLabel,
    this.resistKel,
    this.resistKelLabel,
  });

  final String name;
  final int guard;
  final int maxGuard;
  final String weakness;
  final String weaknessLabel;
  final ExpeditionBattleIntent intent;
  final String? weakElement;
  final String? weakElementLabel;
  final String? resistElement;
  final String? resistElementLabel;
  final String? weakKel;
  final String? weakKelLabel;
  final String? resistKel;
  final String? resistKelLabel;

  /// 큰 엉킴(중간 보스) 표식. 수호짐승에는 쓰지 않는다.
  final bool elite;

  factory ExpeditionBattleEnemy.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleEnemy(
        name: json['name'] as String? ?? '수호자',
        guard: _combatInt(json['guard']),
        maxGuard: _combatInt(json['max_guard'], 100),
        weakness: json['weakness'] as String? ?? 'insight',
        weaknessLabel: json['weakness_label'] as String? ?? '관찰',
        intent: ExpeditionBattleIntent.fromJson(_combatMap(json['intent'])),
        elite: json['elite'] == true,
        weakElement: json['weak_element'] as String?,
        weakElementLabel: json['weak_element_label'] as String?,
        resistElement: json['resist_element'] as String?,
        resistElementLabel: json['resist_element_label'] as String?,
        weakKel: json['weak_kel'] as String?,
        weakKelLabel: json['weak_kel_label'] as String?,
        resistKel: json['resist_kel'] as String?,
        resistKelLabel: json['resist_kel_label'] as String?,
      );
}

class ExpeditionBattleIntent {
  const ExpeditionBattleIntent({
    required this.code,
    required this.name,
    required this.telegraph,
    required this.target,
    required this.power,
    this.effectKey,
    this.vfxFamily,
    this.kelFallbackFamily,
    this.motionProfile,
    this.motion,
    this.kel,
  });

  final String code;
  final String name;
  final String telegraph;
  final String target;
  final int power;
  final String? effectKey;
  final String? vfxFamily;
  final String? kelFallbackFamily;
  final String? motionProfile;
  final ExpeditionCombatMotion? motion;
  final String? kel;

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
        effectKey: json['effect_key'] as String?,
        vfxFamily: json['vfx_family'] as String?,
        kelFallbackFamily: json['kel_fallback_family'] as String?,
        motionProfile: json['motion_profile'] as String?,
        motion: ExpeditionCombatMotion.fromNullableJson(json['motion']),
        kel: json['kel'] as String?,
      );
}

class ExpeditionCombatMotionPhase {
  const ExpeditionCombatMotionPhase({required this.name, required this.ms});

  final String name;
  final int ms;

  factory ExpeditionCombatMotionPhase.fromJson(Map<String, dynamic> json) =>
      ExpeditionCombatMotionPhase(
        name: json['name'] as String? ?? '',
        ms: _combatInt(json['ms']),
      );
}

class ExpeditionCombatMotion {
  const ExpeditionCombatMotion({
    required this.profile,
    required this.archetype,
    required this.facing,
    required this.travelRatio,
    required this.impactShakePx,
    required this.phases,
    required this.totalMs,
  });

  static const supportedArchetypes = {
    'dash',
    'draw',
    'cast',
    'brace',
    'channel',
    'leap',
  };

  final String profile;
  final String archetype;
  final String facing;
  final double travelRatio;
  final double impactShakePx;
  final List<ExpeditionCombatMotionPhase> phases;
  final int totalMs;

  double phaseStart(String name) {
    if (totalMs <= 0) return 0;
    var elapsed = 0;
    for (final phase in phases) {
      if (phase.name == name) return elapsed / totalMs;
      elapsed += phase.ms;
    }
    return 0;
  }

  double phaseEnd(String name) {
    if (totalMs <= 0) return 1;
    var elapsed = 0;
    for (final phase in phases) {
      elapsed += phase.ms;
      if (phase.name == name) return elapsed / totalMs;
    }
    return 1;
  }

  factory ExpeditionCombatMotion.fromJson(Map<String, dynamic> json) {
    final phases = _combatMaps(json['phases'])
        .map(ExpeditionCombatMotionPhase.fromJson)
        .where((phase) => phase.name.isNotEmpty && phase.ms > 0)
        .toList(growable: false);
    final rawArchetype = json['archetype'] as String? ?? 'cast';
    final phaseTotal = phases.fold<int>(0, (total, phase) => total + phase.ms);
    return ExpeditionCombatMotion(
      profile: json['profile'] as String? ?? '',
      archetype:
          supportedArchetypes.contains(rawArchetype) ? rawArchetype : 'cast',
      facing: json['facing'] == 'left' ? 'left' : 'right',
      travelRatio: (json['travel_ratio'] as num?)?.toDouble() ?? .18,
      impactShakePx: (json['impact_shake_px'] as num?)?.toDouble() ?? 2.5,
      phases: phases,
      totalMs: _combatInt(json['total_ms'], phaseTotal),
    );
  }

  static ExpeditionCombatMotion? fromNullableJson(Object? raw) {
    final json = _combatMap(raw);
    return json.isEmpty ? null : ExpeditionCombatMotion.fromJson(json);
  }
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
    required this.version,
    required this.affinity,
    required this.affinityLabel,
    required this.basic,
    required this.uniqueSkills,
    required this.selectedSkills,
    required this.guard,
    this.kelMapVersion = 1,
    this.level = 1,
    this.rarity = 1,
    this.signatureTier = 1,
    this.signatureScaleBp = 10000,
    this.basicScaleBp = 10000,
    this.emotionDiscipline = '',
    this.primaryElement,
    this.primaryElementLabel,
    this.secondaryElement,
    this.secondaryElementLabel,
  });

  final int version;
  final int kelMapVersion;
  final String affinity;
  final String affinityLabel;
  final ExpeditionBattleAction basic;
  final List<ExpeditionBattleAction> uniqueSkills;
  final List<ExpeditionBattleAction> selectedSkills;
  final ExpeditionBattleAction guard;
  final int level;
  final int rarity;
  final int signatureTier;
  final int signatureScaleBp;
  final int basicScaleBp;
  final String emotionDiscipline;
  final String? primaryElement;
  final String? primaryElementLabel;
  final String? secondaryElement;
  final String? secondaryElementLabel;

  /// 구버전 호출부가 읽던 단일 고유 스킬. 전송 action은 unique_1을 쓴다.
  ExpeditionBattleAction get skill => uniqueSkills.first;

  List<ExpeditionBattleAction> get combatSkills => [
        ...uniqueSkills,
        ...selectedSkills,
      ];

  ExpeditionBattleAction actionFor(String actionCode) => switch (actionCode) {
        'unique_1' => uniqueSkills[0],
        'unique_2' => uniqueSkills[1],
        'selected_1' => selectedSkills[0],
        'selected_2' => selectedSkills[1],
        'guard' => guard,
        _ => basic,
      };

  factory ExpeditionBattleKit.fromJson(Map<String, dynamic> json) {
    final uniqueSkills = _combatMaps(json['unique_skills'])
        .map(ExpeditionBattleAction.fromJson)
        .toList(growable: true);
    final legacySkill = _combatMap(json['skill']);
    if (uniqueSkills.isEmpty && legacySkill.isNotEmpty) {
      uniqueSkills.add(
        ExpeditionBattleAction.fromJson(
          legacySkill,
          fallbackSlot: 'unique_1',
        ),
      );
    }
    while (uniqueSkills.length < 2) {
      uniqueSkills.add(
        ExpeditionBattleAction.unavailable(
          slot: 'unique_${uniqueSkills.length + 1}',
          name: '고유 스킬 ${uniqueSkills.length + 1}',
        ),
      );
    }

    final selectedSkills = _combatMaps(json['selected_skills'])
        .map(ExpeditionBattleAction.fromJson)
        .toList(growable: true);
    while (selectedSkills.length < 2) {
      selectedSkills.add(
        ExpeditionBattleAction.unavailable(
          slot: 'selected_${selectedSkills.length + 1}',
          name: '선택 스킬 ${selectedSkills.length + 1}',
        ),
      );
    }

    return ExpeditionBattleKit(
      version: _combatInt(json['version'], legacySkill.isEmpty ? 4 : 1),
      kelMapVersion: _combatInt(json['kel_map_version'], 1),
      affinity: json['affinity'] as String? ?? 'insight',
      affinityLabel: json['affinity_label'] as String? ?? '관찰',
      basic: ExpeditionBattleAction.fromJson(
        _combatMap(json['basic']),
        fallbackSlot: 'attack',
      ),
      uniqueSkills: List.unmodifiable(uniqueSkills.take(2)),
      selectedSkills: List.unmodifiable(selectedSkills.take(2)),
      guard: ExpeditionBattleAction.fromJson(
        _combatMap(json['guard']),
        fallbackSlot: 'guard',
      ),
      level: _combatInt(json['level'], 1),
      rarity: _combatInt(json['rarity'], 1),
      signatureTier: _combatInt(json['signature_tier'], 1),
      signatureScaleBp: _combatInt(json['signature_scale_bp'], 10000),
      basicScaleBp: _combatInt(json['basic_scale_bp'], 10000),
      emotionDiscipline: json['emotion_discipline'] as String? ?? '',
      primaryElement: json['primary_element'] as String?,
      primaryElementLabel: json['primary_element_label'] as String?,
      secondaryElement: json['secondary_element'] as String?,
      secondaryElementLabel: json['secondary_element_label'] as String?,
    );
  }
}

class ExpeditionBattleAction {
  const ExpeditionBattleAction({
    required this.slot,
    required this.source,
    required this.available,
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
    this.unlockLevel = 1,
    this.tier = 1,
    this.tierLabel = '',
    this.level = 1,
    this.rarity = 1,
    this.rawPower = 0,
    this.powerScaleBp = 10000,
    this.tierPowerBp = 10000,
    this.powerNeutral = 0,
    this.matchup = 'neutral',
    this.matchupBp = 10000,
    this.effectPowerBp = 10000,
    this.cooldownTurns = 0,
    this.cooldownRemaining = 0,
    this.element,
    this.elementLabel,
    this.elements = const [],
    this.damageType,
    this.damageTypeLabel,
    this.motionProfile,
    this.vfxFamily,
    this.kelFallbackFamily,
    this.motion,
    this.kel,
    this.kelLabel,
    this.kels = const [],
    this.kelLabels = const [],
    this.readyRound = 0,
    this.fusionVariant,
    this.fusionVfxFamily,
  });

  final String slot;
  final String? source;
  final bool available;
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
  final int unlockLevel;
  final int tier;
  final String tierLabel;
  final int level;
  final int rarity;
  final int rawPower;
  final int powerScaleBp;
  final int tierPowerBp;
  final int powerNeutral;
  final String matchup;
  final int matchupBp;
  final int effectPowerBp;
  final int cooldownTurns;
  final int cooldownRemaining;
  final String? element;
  final String? elementLabel;
  final List<String> elements;
  final String? damageType;
  final String? damageTypeLabel;
  final String? motionProfile;
  final String? vfxFamily;
  final String? kelFallbackFamily;
  final ExpeditionCombatMotion? motion;
  final String? kel;
  final String? kelLabel;
  final List<String> kels;
  final List<String> kelLabels;
  final int readyRound;
  final String? fusionVariant;
  final String? fusionVfxFamily;

  factory ExpeditionBattleAction.fromJson(
    Map<String, dynamic> json, {
    String? fallbackSlot,
  }) =>
      ExpeditionBattleAction(
        slot: json['slot'] as String? ?? fallbackSlot ?? '',
        source: json['source'] as String?,
        available: json.isNotEmpty && json['available'] != false,
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
        unlockLevel: _combatInt(json['unlock_level'], 1),
        tier: _combatInt(json['tier'], 1),
        tierLabel: json['tier_label'] as String? ?? '',
        level: _combatInt(json['level'], 1),
        rarity: _combatInt(json['rarity'], 1),
        rawPower: _combatInt(json['raw_power'], _combatInt(json['power'])),
        powerScaleBp: _combatInt(json['power_scale_bp'], 10000),
        tierPowerBp: _combatInt(json['tier_power_bp'], 10000),
        powerNeutral: _combatInt(
          json['power_neutral'],
          _combatInt(json['power']),
        ),
        matchup: json['matchup'] as String? ?? 'neutral',
        matchupBp: _combatInt(json['matchup_bp'], 10000),
        effectPowerBp: _combatInt(json['effect_power_bp'], 10000),
        cooldownTurns: _combatInt(json['cooldown_turns']),
        cooldownRemaining: _combatInt(json['cooldown_remaining']),
        element: json['element'] as String?,
        elementLabel: json['element_label'] as String?,
        elements: json['elements'] is List
            ? (json['elements'] as List)
                .whereType<String>()
                .toList(growable: false)
            : const [],
        damageType: json['damage_type'] as String?,
        damageTypeLabel: json['damage_type_label'] as String?,
        motionProfile: json['motion_profile'] as String?,
        vfxFamily: json['vfx_family'] as String?,
        kelFallbackFamily: json['kel_fallback_family'] as String?,
        motion: ExpeditionCombatMotion.fromNullableJson(json['motion']),
        kel: json['kel'] as String?,
        kelLabel: json['kel_label'] as String?,
        kels: json['kels'] is List
            ? (json['kels'] as List).whereType<String>().toList(growable: false)
            : const [],
        kelLabels: json['kel_labels'] is List
            ? (json['kel_labels'] as List)
                .whereType<String>()
                .toList(growable: false)
            : json['kel_label'] is String
                ? [json['kel_label'] as String]
                : const [],
        readyRound: _combatInt(
          json['ready_round'],
          _combatInt(json['cooldown_until_round']),
        ),
        fusionVariant: json['fusion_variant'] as String?,
        fusionVfxFamily: json['fusion_vfx_family'] as String?,
      );

  factory ExpeditionBattleAction.unavailable({
    required String slot,
    required String name,
  }) =>
      ExpeditionBattleAction(
        slot: slot,
        source: null,
        available: false,
        code: '',
        name: name,
        description: '새 전투 스킬 구성이 필요한 슬롯이에요.',
        power: 0,
        focusCost: 0,
        focusDelta: 0,
        affinity: null,
        affinityLabel: null,
        effectKey: null,
        effect: null,
        guard: 0,
        unlockLevel: 1,
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
    this.resistanceHit = false,
    this.matchup = 'neutral',
    this.element,
    this.elements = const [],
    this.motionProfile,
    this.motion,
    this.vfxFamily,
    this.kelFallbackFamily,
    this.kel,
    this.kels = const [],
    this.powerNeutral = 0,
    this.matchupBp = 10000,
    this.cooldownTurns = 0,
    this.cooldownUntilRound = 0,
    this.readyRound = 0,
    this.fusionVariant,
    this.fusionVfxFamily,
    this.kelMapVersion = 1,
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
  final bool resistanceHit;
  final String matchup;
  final String? element;
  final List<String> elements;
  final String? motionProfile;
  final ExpeditionCombatMotion? motion;
  final String? vfxFamily;
  final String? kelFallbackFamily;
  final String? kel;
  final List<String> kels;
  final int powerNeutral;
  final int matchupBp;
  final int cooldownTurns;
  final int cooldownUntilRound;
  final int readyRound;
  final String? fusionVariant;
  final String? fusionVfxFamily;
  final int kelMapVersion;

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
        resistanceHit: json['resistance_hit'] == true,
        matchup: json['matchup'] as String? ?? 'neutral',
        element: json['element'] as String?,
        elements: json['elements'] is List
            ? (json['elements'] as List)
                .whereType<String>()
                .toList(growable: false)
            : const [],
        motionProfile: json['motion_profile'] as String?,
        motion: ExpeditionCombatMotion.fromNullableJson(json['motion']),
        vfxFamily: json['vfx_family'] as String?,
        kelFallbackFamily: json['kel_fallback_family'] as String?,
        kel: json['kel'] as String?,
        kels: json['kels'] is List
            ? (json['kels'] as List).whereType<String>().toList(growable: false)
            : const [],
        powerNeutral: _combatInt(json['power_neutral']),
        matchupBp: _combatInt(json['matchup_bp'], 10000),
        cooldownTurns: _combatInt(json['cooldown_turns']),
        cooldownUntilRound: _combatInt(json['cooldown_until_round']),
        readyRound: _combatInt(
          json['ready_round'],
          _combatInt(json['cooldown_until_round']),
        ),
        fusionVariant: json['fusion_variant'] as String?,
        fusionVfxFamily: json['fusion_vfx_family'] as String?,
        kelMapVersion: _combatInt(json['kel_map_version'], 1),
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
