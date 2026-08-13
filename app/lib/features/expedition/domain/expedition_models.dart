import 'expedition_combat_models.dart';
export 'expedition_combat_models.dart';
export 'expedition_stage_models.dart';

int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

class ExpeditionCatalog {
  const ExpeditionCatalog({
    required this.contentVersion,
    required this.activeRunId,
    required this.diaryReady,
    required this.heartResonanceAvailable,
    required this.freeExploreAvailable,
    required this.suspended,
    required this.tutorialCompleted,
    required this.regions,
  });

  final String contentVersion;
  final int? activeRunId;
  final bool diaryReady;
  final bool heartResonanceAvailable;
  final bool freeExploreAvailable;
  final bool suspended;
  final bool tutorialCompleted;
  final List<ExpeditionRegion> regions;

  factory ExpeditionCatalog.fromJson(Map<String, dynamic> json) {
    final entry = _map(json['entry']);
    return ExpeditionCatalog(
      contentVersion: json['content_version'] as String? ?? '',
      activeRunId: json['active_run_id'] is num
          ? (json['active_run_id'] as num).toInt()
          : null,
      diaryReady: entry['diary_ready'] == true,
      heartResonanceAvailable: entry['heart_resonance_available'] == true,
      freeExploreAvailable: entry['free_explore_available'] == true,
      suspended: entry['suspended'] == true,
      tutorialCompleted: entry['tutorial_completed'] == true,
      regions: _maps(json['regions'])
          .map(ExpeditionRegion.fromJson)
          .toList(growable: false),
    );
  }
}

class ExpeditionRegion {
  const ExpeditionRegion({
    required this.code,
    required this.name,
    required this.description,
    required this.recommendedStage,
    required this.rewardExp,
    required this.rewardSeeds,
  });

  final String code;
  final String name;
  final String description;
  final int recommendedStage;
  final int rewardExp;
  final int rewardSeeds;

  factory ExpeditionRegion.fromJson(Map<String, dynamic> json) {
    final reward = _map(json['reward']);
    return ExpeditionRegion(
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      recommendedStage: _asInt(json['recommended_stage'], 1),
      rewardExp: _asInt(reward['exp']),
      rewardSeeds: _asInt(reward['seeds']),
    );
  }
}

class ExpeditionRosterItem {
  const ExpeditionRosterItem({
    required this.plantId,
    required this.name,
    required this.speciesName,
    required this.speciesCode,
    required this.isActive,
    required this.stage,
    required this.form,
    required this.outfitKey,
    required this.stats,
    required this.eligible,
    required this.ineligibleReason,
  });

  final int plantId;
  final String name;
  final String speciesName;
  final String speciesCode;
  final bool isActive;
  final int stage;
  final String form;
  final String? outfitKey;
  final Map<String, int> stats;
  final bool eligible;
  final String? ineligibleReason;

  factory ExpeditionRosterItem.fromJson(Map<String, dynamic> json) {
    final stats = _map(json['stats']);
    return ExpeditionRosterItem(
      plantId: _asInt(json['plant_id']),
      name: json['name'] as String? ?? '',
      speciesName: _map(json['species'])['name'] as String? ?? '',
      speciesCode: _map(json['species'])['code'] as String? ?? '',
      isActive: json['status'] == 'active',
      stage: _asInt(json['stage'], 1),
      form: json['form'] as String? ?? 'mosaic',
      outfitKey: json['outfit_key'] as String?,
      stats: stats.map(
        (key, value) => MapEntry(key, _asInt(value)),
      ),
      eligible: json['eligible'] == true,
      ineligibleReason: json['ineligible_reason'] as String?,
    );
  }
}

class ExpeditionSnapshot {
  const ExpeditionSnapshot({
    required this.run,
    required this.region,
    required this.party,
    required this.nodes,
    required this.edges,
    required this.currentEvent,
    required this.lastResolution,
    this.lastCombatExchange = const [],
    required this.availableActions,
    required this.runThread,
    required this.memory,
    required this.loot,
    required this.summary,
    this.unlockedSkillBooks = const [],
  });

  final ExpeditionRun run;
  final ExpeditionRegion region;
  final List<ExpeditionMember> party;
  final List<ExpeditionNode> nodes;
  final List<List<String>> edges;
  final ExpeditionEvent? currentEvent;
  final ExpeditionResolution? lastResolution;
  final List<ExpeditionBattleEvent> lastCombatExchange;
  final List<Map<String, dynamic>> availableActions;
  final Map<String, dynamic> runThread;
  final Map<String, dynamic> memory;
  final List<ExpeditionLootItem> loot;
  final Map<String, dynamic>? summary;

  /// 이번 행동으로 조건을 채워 새로 서고에 들어온 기록서.
  ///
  /// 조건을 채운 순간에 알려 주지 않으면 사용자는 서고를 따로 열어 보기 전까지
  /// 모른다. 확률이 아니라 결정적으로 얻는 보상이라 더더욱 즉시 알려야 한다.
  final List<ExpeditionUnlockedSkillBook> unlockedSkillBooks;

  Set<String> get availableMoveCodes => availableActions
      .where((action) => action['type'] == 'move')
      .map((action) => action['node_code'] as String? ?? '')
      .where((code) => code.isNotEmpty)
      .toSet();

  bool get canExtract =>
      availableActions.any((action) => action['type'] == 'extract');

  bool get canRetreat =>
      availableActions.any((action) => action['type'] == 'retreat');

  int? get rewardedSeedBalance {
    final reward = summary?['reward'];
    return reward is Map<String, dynamic> && reward['seed_balance'] is num
        ? (reward['seed_balance'] as num).toInt()
        : null;
  }

  factory ExpeditionSnapshot.fromJson(Map<String, dynamic> json) {
    final map = _map(json['map']);
    final unlocked = json['unlocked_skill_books'];
    final rawSummary = json['summary'];
    return ExpeditionSnapshot(
      run: ExpeditionRun.fromJson(_map(json['run'])),
      region: ExpeditionRegion.fromJson(_map(json['region'])),
      party: _maps(json['party'])
          .map(ExpeditionMember.fromJson)
          .toList(growable: false),
      nodes: _maps(map['nodes'])
          .map(ExpeditionNode.fromJson)
          .toList(growable: false),
      edges: map['edges'] is List
          ? (map['edges'] as List)
              .whereType<List>()
              .where((edge) => edge.length == 2)
              .map((edge) => [edge[0].toString(), edge[1].toString()])
              .toList(growable: false)
          : const [],
      currentEvent: json['current_event'] is Map<String, dynamic>
          ? ExpeditionEvent.fromJson(
              json['current_event'] as Map<String, dynamic>,
            )
          : null,
      lastResolution: json['last_resolution'] is Map<String, dynamic>
          ? ExpeditionResolution.fromJson(
              json['last_resolution'] as Map<String, dynamic>,
            )
          : null,
      lastCombatExchange: _maps(json['last_combat_exchange'])
          .map(ExpeditionBattleEvent.fromJson)
          .toList(growable: false),
      availableActions: _maps(json['available_actions']),
      runThread: _map(json['run_thread']),
      memory: _map(json['memory']),
      loot: _maps(json['loot'])
          .map(ExpeditionLootItem.fromJson)
          .toList(growable: false),
      summary: rawSummary is Map<String, dynamic> ? rawSummary : null,
      unlockedSkillBooks: unlocked is List
          ? unlocked
              .whereType<Map<String, dynamic>>()
              .map(ExpeditionUnlockedSkillBook.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

/// 조건을 채워 방금 열린 기록서 한 권.
class ExpeditionUnlockedSkillBook {
  const ExpeditionUnlockedSkillBook({
    required this.code,
    required this.source,
    required this.name,
    required this.effectSummary,
  });

  final String code;

  /// `unlock`(조건 달성) 또는 `challenge`(도전 고정 달성).
  final String source;

  /// 서버가 함께 보내 준 이름. 앱이 카탈로그 사본을 들고 있지 않아도 된다.
  final String name;
  final String effectSummary;

  String get sourceLabel => source == 'challenge' ? '도전 달성' : '조건 달성';

  /// 안내 한 줄. 보유해도 자동 장착되지 않으므로 다음 행동까지 알려 준다.
  String get notice => '$name을(를) 서고에 담았어요. 기록서 화면에서 장착할 수 있어요.';

  factory ExpeditionUnlockedSkillBook.fromJson(Map<String, dynamic> json) {
    final code = json['code'] as String? ?? '';
    return ExpeditionUnlockedSkillBook(
      code: code,
      source: json['source'] as String? ?? 'unlock',
      name: json['name'] as String? ?? code,
      effectSummary: json['effect_summary'] as String? ?? '',
    );
  }
}

class ExpeditionRun {
  const ExpeditionRun({
    required this.id,
    required this.mode,
    required this.stageNo,
    required this.status,
    required this.phase,
    required this.revision,
    required this.currentNodeCode,
    required this.trailLight,
    required this.resolve,
    required this.objectiveSecured,
    required this.rewardEligible,
  });

  final int id;
  final String mode;

  /// 스테이지 지도에서 출발한 run만 값을 가진다.
  final int? stageNo;
  final String status;
  final String phase;
  final int revision;
  final String currentNodeCode;
  final int trailLight;
  final int resolve;
  final bool objectiveSecured;
  final bool rewardEligible;

  bool get isActive => status == 'active';

  factory ExpeditionRun.fromJson(Map<String, dynamic> json) => ExpeditionRun(
        id: _asInt(json['id']),
        mode: json['mode'] as String? ?? '',
        stageNo:
            json['stage_no'] is num ? (json['stage_no'] as num).toInt() : null,
        status: json['status'] as String? ?? '',
        phase: json['phase'] as String? ?? '',
        revision: _asInt(json['revision']),
        currentNodeCode: json['current_node_code'] as String? ?? '',
        trailLight: _asInt(json['trail_light']),
        resolve: _asInt(json['resolve']),
        objectiveSecured: json['objective_secured'] == true,
        rewardEligible: json['reward_eligible'] == true,
      );
}

class ExpeditionMember {
  const ExpeditionMember({
    required this.id,
    required this.name,
    required this.speciesName,
    required this.speciesCode,
    required this.stage,
    required this.form,
    this.outfitKey,
    required this.stats,
    required this.rawStats,
    required this.effectiveStats,
    required this.statCap,
    required this.isGuide,
    required this.signatureSkill,
    required this.formSkill,
  });

  final int id;
  final String name;
  final String speciesName;
  final String speciesCode;
  final int stage;
  final String form;
  final String? outfitKey;
  final Map<String, int> stats;
  final Map<String, int> rawStats;
  final Map<String, int> effectiveStats;
  final int? statCap;
  final bool isGuide;
  final ExpeditionSkill signatureSkill;
  final ExpeditionSkill formSkill;

  bool get signatureUsed => signatureSkill.used;
  bool get formUsed => formSkill.used;
  bool get hasRegionAdjustment => rawStats.entries.any(
        (entry) => effectiveStats[entry.key] != entry.value,
      );

  factory ExpeditionMember.fromJson(Map<String, dynamic> json) {
    final skills = _map(json['skills']);
    final stats = _map(json['stats']).map(
      (key, value) => MapEntry(key, _asInt(value)),
    );
    final rawStats = _map(json['raw_stats']).map(
      (key, value) => MapEntry(key, _asInt(value)),
    );
    final effectiveStats = _map(json['effective_stats']).map(
      (key, value) => MapEntry(key, _asInt(value)),
    );
    return ExpeditionMember(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '',
      speciesName: _map(json['species'])['name'] as String? ?? '',
      speciesCode: _map(json['species'])['code'] as String? ?? '',
      stage: _asInt(json['stage'], 1),
      form: json['form'] as String? ?? 'mosaic',
      outfitKey: json['outfit_key'] as String?,
      stats: stats,
      rawStats: rawStats.isEmpty ? stats : rawStats,
      effectiveStats: effectiveStats.isEmpty ? stats : effectiveStats,
      statCap:
          json['stat_cap'] is num ? (json['stat_cap'] as num).toInt() : null,
      isGuide: json['is_guide'] == true,
      signatureSkill: ExpeditionSkill.fromJson(
        _map(skills['signature']),
        fallbackName: '고유 스킬',
      ),
      formSkill: ExpeditionSkill.fromJson(
        _map(skills['form']),
        fallbackName: '성장형 스킬',
      ),
    );
  }
}

class ExpeditionSkillMode {
  const ExpeditionSkillMode({required this.code, required this.label});

  final String code;
  final String label;

  factory ExpeditionSkillMode.fromJson(Map<String, dynamic> json) =>
      ExpeditionSkillMode(
        code: json['code'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );
}

class ExpeditionSkill {
  const ExpeditionSkill({
    required this.code,
    required this.name,
    required this.description,
    required this.phases,
    required this.modes,
    required this.used,
    required this.available,
  });

  final String code;
  final String name;
  final String description;
  final List<String> phases;
  final List<ExpeditionSkillMode> modes;
  final bool used;
  final bool available;

  factory ExpeditionSkill.fromJson(
    Map<String, dynamic> json, {
    required String fallbackName,
  }) =>
      ExpeditionSkill(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? fallbackName,
        description: json['description'] as String? ?? '',
        phases: json['phases'] is List
            ? (json['phases'] as List)
                .whereType<String>()
                .toList(growable: false)
            : const [],
        modes: _maps(json['modes'])
            .map(ExpeditionSkillMode.fromJson)
            .where((mode) => mode.code.isNotEmpty)
            .toList(growable: false),
        used: json['used'] == true,
        available: json['available'] == true,
      );
}

class ExpeditionNode {
  const ExpeditionNode({
    required this.code,
    required this.name,
    required this.type,
    required this.status,
    required this.x,
    required this.y,
    required this.cost,
    required this.sceneKey,
    required this.sceneLabel,
    required this.sceneDescription,
    required this.depthLabel,
    required this.threatLevel,
  });

  final String code;
  final String name;
  final String type;
  final String status;
  final double? x;
  final double? y;
  final int cost;
  final String sceneKey;
  final String sceneLabel;
  final String sceneDescription;
  final String depthLabel;
  final int threatLevel;

  bool get isPositioned => x != null && y != null;

  factory ExpeditionNode.fromJson(Map<String, dynamic> json) => ExpeditionNode(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '아직 보이지 않는 길',
        type: json['type'] as String? ?? 'unknown',
        status: json['status'] as String? ?? 'hidden',
        x: json['x'] is num ? (json['x'] as num).toDouble() : null,
        y: json['y'] is num ? (json['y'] as num).toDouble() : null,
        cost: _asInt(json['cost']),
        sceneKey: json['scene_key'] as String? ?? 'dungeon_gate',
        sceneLabel: json['scene_label'] as String? ?? '미확인 구역',
        sceneDescription: json['scene_description'] as String? ??
            '아직 이 장소의 모습을 자세히 확인하지 못했어요.',
        depthLabel: json['depth_label'] as String? ?? '깊이 미확인',
        threatLevel: _asInt(json['threat_level']).clamp(0, 3),
      );
}

class ExpeditionEvent {
  const ExpeditionEvent({
    required this.code,
    required this.title,
    required this.text,
    required this.spotlightMemberId,
    required this.encounter,
    this.battle,
    required this.choices,
  });

  final String code;
  final String title;
  final String text;
  final int? spotlightMemberId;
  final ExpeditionEncounter? encounter;
  final ExpeditionBattle? battle;
  final List<ExpeditionChoice> choices;

  factory ExpeditionEvent.fromJson(Map<String, dynamic> json) =>
      ExpeditionEvent(
        code: json['code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        spotlightMemberId: json['spotlight_member_id'] is num
            ? (json['spotlight_member_id'] as num).toInt()
            : null,
        encounter: json['encounter'] is Map<String, dynamic>
            ? ExpeditionEncounter.fromJson(
                json['encounter'] as Map<String, dynamic>,
              )
            : null,
        battle: json['battle'] is Map<String, dynamic>
            ? ExpeditionBattle.fromJson(
                json['battle'] as Map<String, dynamic>,
              )
            : null,
        choices: _maps(json['choices'])
            .map(ExpeditionChoice.fromJson)
            .toList(growable: false),
      );
}

class ExpeditionChoice {
  const ExpeditionChoice({
    required this.code,
    required this.label,
    required this.safe,
    required this.stat,
    required this.resolveCost,
    required this.effectKey,
    required this.guardDamage,
    required this.previews,
  });

  final String code;
  final String label;
  final bool safe;

  /// 판정에 어울리는 힘(공명). 안전 선택은 null이다.
  final String? stat;
  final int resolveCost;
  final String? effectKey;
  final int guardDamage;
  final List<ExpeditionChoicePreview> previews;

  ExpeditionChoicePreview? previewFor(int memberId) {
    for (final preview in previews) {
      if (preview.memberId == memberId) return preview;
    }
    return null;
  }

  factory ExpeditionChoice.fromJson(Map<String, dynamic> json) =>
      ExpeditionChoice(
        code: json['code'] as String? ?? '',
        label: json['label'] as String? ?? '',
        safe: json['safe'] == true,
        stat: json['stat'] as String?,
        resolveCost: _asInt(json['resolve_cost']),
        effectKey: json['effect_key'] as String?,
        guardDamage: _asInt(json['guard_damage']),
        previews: _maps(json['previews'])
            .map(ExpeditionChoicePreview.fromJson)
            .toList(growable: false),
      );
}

class ExpeditionEncounter {
  const ExpeditionEncounter({
    required this.kind,
    required this.enemyName,
    required this.enemyMaxGuard,
    required this.attackName,
    required this.telegraph,
    required this.damageTarget,
  });

  final String kind;
  final String enemyName;
  final int enemyMaxGuard;
  final String attackName;
  final String telegraph;
  final String damageTarget;

  factory ExpeditionEncounter.fromJson(Map<String, dynamic> json) =>
      ExpeditionEncounter(
        kind: json['kind'] as String? ?? '',
        enemyName: json['enemy_name'] as String? ?? '수호자',
        enemyMaxGuard: _asInt(json['enemy_max_guard'], 100),
        attackName: json['attack_name'] as String? ?? '수호자의 공격',
        telegraph: json['telegraph'] as String? ?? '',
        damageTarget: json['damage_target'] as String? ?? '결의',
      );
}

class ExpeditionResolution {
  const ExpeditionResolution({
    required this.eventCode,
    required this.title,
    required this.choice,
    required this.outcome,
    required this.score,
    required this.actorName,
    required this.skillCode,
    required this.combat,
  });

  final String eventCode;
  final String title;
  final String choice;
  final String outcome;
  final int score;
  final String actorName;
  final String? skillCode;
  final ExpeditionCombatFeedback? combat;

  factory ExpeditionResolution.fromJson(Map<String, dynamic> json) =>
      ExpeditionResolution(
        eventCode: json['event_code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        choice: json['choice'] as String? ?? '',
        outcome: json['outcome'] as String? ?? '',
        score: _asInt(json['score']),
        actorName: json['actor_name'] as String? ?? '탐험대원',
        skillCode: json['skill_code'] as String?,
        combat: json['combat_feedback'] is Map<String, dynamic>
            ? ExpeditionCombatFeedback.fromJson(
                json['combat_feedback'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ExpeditionCombatFeedback {
  const ExpeditionCombatFeedback({
    required this.kind,
    required this.enemyName,
    required this.enemyMaxGuard,
    required this.enemyGuardBefore,
    required this.enemyGuardAfter,
    required this.guardDamage,
    required this.attackName,
    required this.telegraph,
    required this.damageTarget,
    required this.counterDamage,
    required this.counterResult,
    required this.effectKey,
  });

  final String kind;
  final String enemyName;
  final int enemyMaxGuard;
  final int enemyGuardBefore;
  final int enemyGuardAfter;
  final int guardDamage;
  final String attackName;
  final String telegraph;
  final String damageTarget;
  final int counterDamage;
  final String counterResult;
  final String effectKey;

  factory ExpeditionCombatFeedback.fromJson(Map<String, dynamic> json) =>
      ExpeditionCombatFeedback(
        kind: json['kind'] as String? ?? '',
        enemyName: json['enemy_name'] as String? ?? '수호자',
        enemyMaxGuard: _asInt(json['enemy_max_guard'], 100),
        enemyGuardBefore: _asInt(json['enemy_guard_before'], 100),
        enemyGuardAfter: _asInt(json['enemy_guard_after']),
        guardDamage: _asInt(json['guard_damage']),
        attackName: json['attack_name'] as String? ?? '수호자의 공격',
        telegraph: json['telegraph'] as String? ?? '',
        damageTarget: json['damage_target'] as String? ?? '결의',
        counterDamage: _asInt(json['counter_damage']),
        counterResult: json['counter_result'] as String? ?? 'guarded',
        effectKey: json['effect_key'] as String? ?? 'safe_guard',
      );
}

class ExpeditionChoicePreview {
  const ExpeditionChoicePreview({
    required this.memberId,
    required this.label,
    required this.forecast,
    required this.safe,
    required this.statLabel,
    required this.value,
    required this.difficulty,
  });

  final int memberId;
  final String label;
  final String? forecast;
  final bool safe;
  final String? statLabel;
  final int value;
  final int difficulty;

  /// 성공 예상 3단 표현. 정확한 수치는 길게 누르기 상세에서 보여 준다.
  String get outlook {
    if (safe) return '안전하게 진행돼요';
    final margin = value - difficulty;
    if (margin >= 0) return '확실해요';
    if (margin >= -2) return '해 볼 만해요';
    return '어려워 보여요';
  }

  factory ExpeditionChoicePreview.fromJson(Map<String, dynamic> json) =>
      ExpeditionChoicePreview(
        memberId: _asInt(json['member_id']),
        label: json['label'] as String? ?? '',
        forecast: json['forecast'] as String?,
        safe: json['safe'] == true,
        statLabel: json['stat_label'] as String?,
        value: _asInt(json['value']),
        difficulty: _asInt(json['difficulty']),
      );
}

class ExpeditionLootItem {
  const ExpeditionLootItem({
    required this.itemCode,
    required this.name,
    required this.quantity,
    required this.disposition,
  });

  final String itemCode;
  final String name;
  final int quantity;
  final String disposition;

  factory ExpeditionLootItem.fromJson(Map<String, dynamic> json) =>
      ExpeditionLootItem(
        itemCode: json['item_code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        quantity: _asInt(json['quantity']),
        disposition: json['disposition'] as String? ?? '',
      );
}
