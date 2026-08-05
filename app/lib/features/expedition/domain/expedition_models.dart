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
    required this.isActive,
    required this.stage,
    required this.form,
    required this.stats,
    required this.eligible,
    required this.ineligibleReason,
  });

  final int plantId;
  final String name;
  final String speciesName;
  final bool isActive;
  final int stage;
  final String form;
  final Map<String, int> stats;
  final bool eligible;
  final String? ineligibleReason;

  factory ExpeditionRosterItem.fromJson(Map<String, dynamic> json) {
    final stats = _map(json['stats']);
    return ExpeditionRosterItem(
      plantId: _asInt(json['plant_id']),
      name: json['name'] as String? ?? '',
      speciesName: _map(json['species'])['name'] as String? ?? '',
      isActive: json['status'] == 'active',
      stage: _asInt(json['stage'], 1),
      form: json['form'] as String? ?? 'mosaic',
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
    required this.availableActions,
    required this.runThread,
    required this.memory,
    required this.loot,
    required this.summary,
  });

  final ExpeditionRun run;
  final ExpeditionRegion region;
  final List<ExpeditionMember> party;
  final List<ExpeditionNode> nodes;
  final List<List<String>> edges;
  final ExpeditionEvent? currentEvent;
  final List<Map<String, dynamic>> availableActions;
  final Map<String, dynamic> runThread;
  final Map<String, dynamic> memory;
  final List<ExpeditionLootItem> loot;
  final Map<String, dynamic>? summary;

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
      availableActions: _maps(json['available_actions']),
      runThread: _map(json['run_thread']),
      memory: _map(json['memory']),
      loot: _maps(json['loot'])
          .map(ExpeditionLootItem.fromJson)
          .toList(growable: false),
      summary: rawSummary is Map<String, dynamic> ? rawSummary : null,
    );
  }
}

class ExpeditionRun {
  const ExpeditionRun({
    required this.id,
    required this.mode,
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
    required this.stage,
    required this.form,
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
  final int stage;
  final String form;
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
      stage: _asInt(json['stage'], 1),
      form: json['form'] as String? ?? 'mosaic',
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
  });

  final String code;
  final String name;
  final String type;
  final String status;
  final double? x;
  final double? y;
  final int cost;

  bool get isPositioned => x != null && y != null;

  factory ExpeditionNode.fromJson(Map<String, dynamic> json) => ExpeditionNode(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '아직 보이지 않는 길',
        type: json['type'] as String? ?? 'unknown',
        status: json['status'] as String? ?? 'hidden',
        x: json['x'] is num ? (json['x'] as num).toDouble() : null,
        y: json['y'] is num ? (json['y'] as num).toDouble() : null,
        cost: _asInt(json['cost']),
      );
}

class ExpeditionEvent {
  const ExpeditionEvent({
    required this.code,
    required this.title,
    required this.text,
    required this.spotlightMemberId,
    required this.choices,
  });

  final String code;
  final String title;
  final String text;
  final int? spotlightMemberId;
  final List<ExpeditionChoice> choices;

  factory ExpeditionEvent.fromJson(Map<String, dynamic> json) =>
      ExpeditionEvent(
        code: json['code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        spotlightMemberId: json['spotlight_member_id'] is num
            ? (json['spotlight_member_id'] as num).toInt()
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
    required this.previews,
  });

  final String code;
  final String label;
  final bool safe;
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
        previews: _maps(json['previews'])
            .map(ExpeditionChoicePreview.fromJson)
            .toList(growable: false),
      );
}

class ExpeditionChoicePreview {
  const ExpeditionChoicePreview({
    required this.memberId,
    required this.label,
    required this.forecast,
    required this.safe,
  });

  final int memberId;
  final String label;
  final String? forecast;
  final bool safe;

  factory ExpeditionChoicePreview.fromJson(Map<String, dynamic> json) =>
      ExpeditionChoicePreview(
        memberId: _asInt(json['member_id']),
        label: json['label'] as String? ?? '',
        forecast: json['forecast'] as String?,
        safe: json['safe'] == true,
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
