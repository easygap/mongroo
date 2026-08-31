int _combatInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Map<String, dynamic> _combatMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _combatMaps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

Map<String, int> _combatIntMap(Object? value) {
  final source = _combatMap(value);
  return {
    for (final entry in source.entries)
      if (entry.value is num) entry.key: (entry.value as num).toInt(),
  };
}

Map<String, String> _combatStringMap(Object? value) {
  final source = _combatMap(value);
  return {
    for (final entry in source.entries)
      if (entry.value is String) entry.key: entry.value as String,
  };
}

class ExpeditionCombatCommand {
  const ExpeditionCombatCommand({
    required this.memberId,
    required this.action,
    this.choice,
  });

  final int memberId;
  final String action;

  /// 일부 기록서는 무엇으로 바꿀지 함께 고른다. 허용값 판정은 서버가 한다.
  final String? choice;

  Map<String, dynamic> toJson() => {
        'member_id': memberId,
        'action': action,
        // 고르지 않은 명령까지 null을 실어 보내지 않는다. 구버전 서버가
        // 모르는 키를 받고 400을 내는 일을 막는다.
        if (choice != null) 'choice': choice,
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
    this.bossPhase,
    this.regionCode,
    this.threat,
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

  /// 3페이즈 보스의 현재 봉인 상태. 일반 수호전과 엉킴에는 없다.
  final ExpeditionBattleBossPhase? bossPhase;

  /// 이 전투가 벌어지는 지역. 지역마다 다른 BGM을 고르는 값이며 웨이브가 없는
  /// 구버전 수호전 응답에는 없다.
  final String? regionCode;

  /// 스테이지 시작 시 고정된 위협 프로필. 캐릭터 레벨을 읽어 공격력을 올리는
  /// 동적 스케일이 아니라 스테이지 번호에 귀속된 공개 규칙이다.
  final ExpeditionBattleThreat? threat;

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
        regionCode: json['region_code'] as String?,
        wave: json['wave'] is Map<String, dynamic>
            ? ExpeditionBattleWave.fromJson(
                json['wave'] as Map<String, dynamic>,
              )
            : null,
        bossPhase: json['boss_phase'] is Map<String, dynamic>
            ? ExpeditionBattleBossPhase.fromJson(
                json['boss_phase'] as Map<String, dynamic>,
              )
            : null,
        threat: json['threat'] is Map<String, dynamic>
            ? ExpeditionBattleThreat.fromJson(
                json['threat'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ExpeditionBattleThreat {
  const ExpeditionBattleThreat({
    required this.code,
    required this.name,
    required this.tier,
    required this.rank,
    required this.recommendedLevel,
    required this.mechanicLevel,
    required this.patternDepth,
  });

  final String code;
  final String name;
  final int tier;
  final String rank;
  final int recommendedLevel;
  final int mechanicLevel;
  final int patternDepth;

  factory ExpeditionBattleThreat.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleThreat(
        code: json['code'] as String? ?? 'legacy',
        name: json['name'] as String? ?? '기본 탐험',
        tier: _combatInt(json['tier']),
        rank: json['rank'] as String? ?? 'legacy',
        recommendedLevel: _combatInt(json['recommended_level'], 1),
        mechanicLevel: _combatInt(json['mechanic_level']),
        patternDepth: _combatInt(json['pattern_depth'], 1),
      );
}

class ExpeditionBattleWave {
  const ExpeditionBattleWave({
    required this.index,
    required this.count,
    required this.code,
    required this.name,
  });

  final int index;
  final int count;
  final String code;
  final String name;

  factory ExpeditionBattleWave.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleWave(
        index: _combatInt(json['index'], 1),
        count: _combatInt(json['count'], 1),
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class ExpeditionBattleBossPhase {
  const ExpeditionBattleBossPhase({
    required this.index,
    required this.count,
    required this.code,
    required this.name,
    required this.tone,
    required this.intentPowerBonus,
    this.nextThresholdGuard,
    this.ruleName,
    this.ruleSummary,
    this.phaseGate,
    this.phaseGateReady = false,
  });

  final int index;
  final int count;
  final String code;
  final String name;
  final String tone;
  final int intentPowerBonus;
  final int? nextThresholdGuard;
  final String? ruleName;
  final String? ruleSummary;
  final String? phaseGate;
  final bool phaseGateReady;

  bool get isFinal => index >= count;

  factory ExpeditionBattleBossPhase.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleBossPhase(
        index: _combatInt(json['index'], 1),
        count: _combatInt(json['count'], 1),
        code: json['code'] as String? ?? 'phase_1',
        name: json['name'] as String? ?? '수호 페이즈',
        tone: json['tone'] as String? ?? 'mosaic',
        intentPowerBonus: _combatInt(json['intent_power_bonus']),
        nextThresholdGuard: json['next_threshold_guard'] is num
            ? (json['next_threshold_guard'] as num).toInt()
            : null,
        ruleName: json['rule_name'] as String?,
        ruleSummary: json['rule_summary'] as String?,
        phaseGate: json['phase_gate'] as String?,
        phaseGateReady: json['phase_gate_ready'] == true,
      );
}

class ExpeditionBattlePendingRound {
  const ExpeditionBattlePendingRound({
    required this.acted,
    required this.awaiting,
    this.weaknessHit = false,
    this.guardActions = 0,
  });

  final List<int> acted;
  final List<int> awaiting;
  final bool weaknessHit;
  final int guardActions;

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
        weaknessHit: json['weakness_hit'] == true,
        guardActions: _combatInt(json['guard_actions']),
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
    this.extraIntents = const [],
    this.nextIntent,
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

  /// 같은 라운드에 함께 오는 예고들. 합동 수호전의 잠꼬대와 여운이 여기
  /// 들어오고, 예고가 하나뿐인 전투에서는 비어 있다.
  final List<ExpeditionBattleIntent> extraIntents;

  /// 다음 라운드 예고. `잔향 읽기`를 쓴 전투에서만 서버가 열어 준다.
  ///
  /// 책을 안 썼으면 `null`이라 화면에 아무것도 안 나온다 — 늘 보이면 그 책이
  /// 파는 것이 사라진다.
  final ExpeditionBattleIntent? nextIntent;
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
        extraIntents: (json['extra_intents'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ExpeditionBattleIntent.fromJson)
            .toList(growable: false),
        nextIntent: json['next_intent'] is Map<String, dynamic>
            ? ExpeditionBattleIntent.fromJson(
                json['next_intent'] as Map<String, dynamic>,
              )
            : null,
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
    this.contactMaterial,
    this.mechanic,
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

  /// 이 예고가 날려 보내는 물건의 재질. 예고 preview 소리를 고르는 값이며
  /// 실제로 닿는 순간의 접촉음과 같은 재질이라 귀로 예상이 맞는지 확인된다.
  final String? contactMaterial;
  final ExpeditionEnemyMechanic? mechanic;

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
        contactMaterial: json['contact_material'] as String?,
        mechanic: json['mechanic'] is Map<String, dynamic>
            ? ExpeditionEnemyMechanic.fromJson(
                json['mechanic'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ExpeditionEnemyMechanic {
  const ExpeditionEnemyMechanic({
    required this.code,
    required this.name,
    required this.trigger,
    required this.effect,
    required this.value,
    required this.counter,
  });

  final String code;
  final String name;
  final String trigger;
  final String effect;
  final int value;
  final String counter;

  factory ExpeditionEnemyMechanic.fromJson(Map<String, dynamic> json) =>
      ExpeditionEnemyMechanic(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        trigger: json['trigger'] as String? ?? '',
        effect: json['effect'] as String? ?? '',
        value: _combatInt(json['value']),
        counter: json['counter'] as String? ?? '',
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
    this.statuses = const {},
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
  final Map<String, int> statuses;

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
        statuses: _combatIntMap(json['statuses']),
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
    this.role = '',
    this.roleLabel = '',
    this.combatStats = const {},
    this.combatStatLabels = const {},
    this.emotionVfxPalette = const {},
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
  final String role;
  final String roleLabel;
  final Map<String, int> combatStats;
  final Map<String, String> combatStatLabels;
  final Map<String, String> emotionVfxPalette;
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
      role: json['role'] as String? ?? '',
      roleLabel: json['role_label'] as String? ?? '',
      combatStats: _combatIntMap(json['combat_stats']),
      combatStatLabels: _combatStringMap(json['combat_stat_labels']),
      emotionVfxPalette: _combatStringMap(json['emotion_vfx_palette']),
      primaryElement: json['primary_element'] as String?,
      primaryElementLabel: json['primary_element_label'] as String?,
      secondaryElement: json['secondary_element'] as String?,
      secondaryElementLabel: json['secondary_element_label'] as String?,
    );
  }
}

/// 명령형 기록서가 함께 묻는 선택지 하나.
///
/// 값과 이름표를 서버가 짝지어 내려보낸다. 앱이 코드→한글 표를 따로 들고 있으면
/// 결이 늘어날 때마다 두 곳을 고쳐야 하고, 한쪽만 고치면 빈 이름이 나온다.
class ExpeditionBattleChoiceOption {
  const ExpeditionBattleChoiceOption({required this.value, required this.label});

  factory ExpeditionBattleChoiceOption.fromJson(Map<String, dynamic> json) =>
      ExpeditionBattleChoiceOption(
        value: json['value'] as String? ?? '',
        label: json['label'] as String? ?? json['value'] as String? ?? '',
      );

  final String value;
  final String label;
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
    this.effectValues = const {},
    this.mechanicSummary = '',
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
    this.presentationTier = 1,
    this.vfxIntensity = .86,
    this.audioLayer = 'light',
    this.cameraProfile = 'steady',
    this.emotionVfxPrimary,
    this.emotionVfxSecondary,
    this.choiceKind,
    this.choiceCurrent,
    this.choiceOptions = const [],
    this.lockReason,
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
  final Map<String, int> effectValues;
  final String mechanicSummary;
  final int cooldownTurns;
  final int cooldownRemaining;
  final String? element;
  final String? elementLabel;
  final List<String> elements;
  final String? damageType;
  final String? damageTypeLabel;

  /// 이 행동이 무엇을 함께 고르는지(`kel` 등). null이면 고를 것이 없다.
  ///
  /// 후보와 판정은 모두 서버가 쥐고 있다. 앱은 목록을 만들지도, 규칙을 다시
  /// 계산하지도 않는다 — 두 곳이 어긋나면 사용자가 영문 없이 막히기 때문이다.
  final String? choiceKind;

  /// 지금 무엇으로 되어 있는지. 선택지에서 `현재`를 표시하는 용도다.
  final String? choiceCurrent;
  final List<ExpeditionBattleChoiceOption> choiceOptions;

  /// 눌렀을 때 고르는 단계를 거쳐야 하는가.
  bool get needsChoice => choiceKind != null && choiceOptions.isNotEmpty;

  /// 왜 못 누르는지에 대한 서버의 문장. 레벨 해금 말고도 이유가 여럿이라
  /// (넘길 대원이 없다, 바꿔 낄 책이 없다) 앱이 추측하지 않고 그대로 쓴다.
  final String? lockReason;
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
  final int presentationTier;
  final double vfxIntensity;
  final String audioLayer;
  final String cameraProfile;
  final String? emotionVfxPrimary;
  final String? emotionVfxSecondary;

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
        effectValues: _combatIntMap(json['effect_values']),
        mechanicSummary: json['mechanic_summary'] as String? ?? '',
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
        presentationTier: _combatInt(
          json['presentation_tier'],
          _combatInt(json['tier'], 1),
        ),
        vfxIntensity: (json['vfx_intensity'] as num?)?.toDouble() ?? .86,
        audioLayer: json['audio_layer'] as String? ?? 'light',
        cameraProfile: json['camera_profile'] as String? ?? 'steady',
        emotionVfxPrimary: json['emotion_vfx_primary'] as String?,
        emotionVfxSecondary: json['emotion_vfx_secondary'] as String?,
        lockReason: json['lock_reason'] as String?,
        choiceKind: json['choice_kind'] as String?,
        choiceCurrent: json['choice_current'] as String?,
        choiceOptions: List.unmodifiable(
          _combatMaps(json['choice_options'])
              .map(ExpeditionBattleChoiceOption.fromJson)
              .where((option) => option.value.isNotEmpty),
        ),
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
    this.skillCode,
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
    this.effectValues = const {},
    this.mechanicSummary = '',
    this.presentationTier = 1,
    this.vfxIntensity = .86,
    this.audioLayer = 'light',
    this.cameraProfile = 'steady',
    this.emotionVfxPrimary,
    this.emotionVfxSecondary,
    this.phaseIndex = 0,
    this.phaseCount = 0,
    this.phaseName,
    this.contactMaterial,
    this.regionCode,
  });

  final int sequence;
  final String type;
  final int? memberId;
  final String? actorName;
  final String? action;
  final String? actionName;
  final String? effectKey;
  final bool weaknessHit;

  /// 이 행동이 실제로 쓴 스킬 코드. 슬롯(`action`)은 자리를, 이 값은 무엇을
  /// 썼는지를 알려 준다. 같은 `selected_1`에 여섯 성장결 스킬이 번갈아 들어오기
  /// 때문에 고유한 소리를 고르려면 슬롯이 아니라 이 코드가 필요하다.
  /// 구버전 응답에는 없어 `null`이면 tier 대체음으로 떨어진다.
  final String? skillCode;
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
  final Map<String, int> effectValues;
  final String mechanicSummary;
  final int presentationTier;
  final double vfxIntensity;
  final String audioLayer;
  final String cameraProfile;
  final String? emotionVfxPrimary;
  final String? emotionVfxSecondary;
  final int phaseIndex;
  final int phaseCount;
  final String? phaseName;

  /// 접촉 프레임에서 어떤 재질 소리를 낼지 — 서버가 판정한 값이다.
  /// `leaf|paper|water|wood|stone|guard` 중 하나이며, 구버전 응답에는 없다.
  final String? contactMaterial;

  /// 풀려남 cadence를 고를 지역. 엉킴이 풀린 이벤트에만 실려 온다.
  final String? regionCode;

  bool get isPartyAction => type == 'party_action';
  bool get isEnemyAction => type == 'enemy_action';
  bool get isBossPhase => type == 'boss_phase';

  /// 엉킴 하나가 제자리로 돌아간 순간. 다음 엉킴 등장 전 한 번만 울린다.
  bool get isWaveCleared => type == 'wave_cleared';

  /// 마지막 엉킴까지 풀려 전투가 끝난 순간.
  bool get isVictoryOutcome => type == 'outcome' && outcome == 'victory';

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
        skillCode: json['skill_code'] as String?,
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
        effectValues: _combatIntMap(json['effect_values']),
        mechanicSummary: json['mechanic_summary'] as String? ?? '',
        presentationTier: _combatInt(json['presentation_tier'], 1),
        vfxIntensity: (json['vfx_intensity'] as num?)?.toDouble() ?? .86,
        audioLayer: json['audio_layer'] as String? ?? 'light',
        cameraProfile: json['camera_profile'] as String? ?? 'steady',
        emotionVfxPrimary: json['emotion_vfx_primary'] as String?,
        emotionVfxSecondary: json['emotion_vfx_secondary'] as String?,
        phaseIndex: _combatInt(json['phase_index']),
        phaseCount: _combatInt(json['phase_count']),
        phaseName: json['phase_name'] as String?,
        contactMaterial: json['contact_material'] as String?,
        regionCode: json['region_code'] as String?,
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
