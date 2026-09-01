import '../../home/domain/plant.dart';

int _int(Object? value) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text) ?? 0,
      _ => 0,
    };

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

class AdventureEconomyEntry {
  const AdventureEconomyEntry({
    required this.code,
    required this.label,
    required this.exp,
    required this.seeds,
    this.expMax,
    this.seedsMax,
  });

  final String code;
  final String label;
  final int exp;
  final int seeds;

  /// 값이 하나로 정해지지 않는 활동의 위쪽 끝. 직접 탐험은 지역마다 달라서
  /// `6~10 XP`처럼 폭으로 읽어 준다. 폭이 없으면 둘 다 null이다.
  final int? expMax;
  final int? seedsMax;

  bool get hasRange =>
      (expMax != null && expMax != exp) || (seedsMax != null && seedsMax != seeds);

  String _span(int low, int? high) =>
      high == null || high == low ? '$low' : '$low~$high';

  /// `6~10 XP · 씨앗 2~5`처럼 한 줄로.
  String get amountLabel =>
      '${_span(exp, expMax)} XP · 씨앗 ${_span(seeds, seedsMax)}';

  factory AdventureEconomyEntry.fromJson(Map<String, dynamic> json) =>
      AdventureEconomyEntry(
        code: json['code']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        exp: _int(json['exp']),
        seeds: _int(json['seeds']),
        expMax: json['exp_max'] == null ? null : _int(json['exp_max']),
        seedsMax: json['seeds_max'] == null ? null : _int(json['seeds_max']),
      );
}

class AdventureStat {
  const AdventureStat({
    required this.code,
    required this.label,
    required this.value,
  });

  final String code;
  final String label;
  final int value;

  factory AdventureStat.fromJson(Map<String, dynamic> json) => AdventureStat(
        code: json['code']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        value: _int(json['value']),
      );
}

class AdventureOutfit {
  const AdventureOutfit({
    required this.name,
    required this.layerKey,
    required this.bonusLabel,
    required this.bonusAmount,
  });

  final String name;
  final String? layerKey;
  final String? bonusLabel;
  final int bonusAmount;

  factory AdventureOutfit.fromJson(Map<String, dynamic> json) {
    final bonus = _map(json['bonus']);
    return AdventureOutfit(
      name: json['name']?.toString() ?? '장착 의상',
      layerKey: json['layer_key']?.toString(),
      bonusLabel: bonus['label']?.toString(),
      bonusAmount: _int(bonus['amount']),
    );
  }
}

class AdventureCharacter {
  const AdventureCharacter({
    required this.plantId,
    required this.name,
    required this.stage,
    required this.form,
    required this.speciesCode,
    required this.speciesName,
    required this.stats,
    this.outfit,
  });

  final int plantId;
  final String name;
  final int stage;
  final PlantGrowthForm? form;
  final String speciesCode;
  final String speciesName;
  final List<AdventureStat> stats;
  final AdventureOutfit? outfit;

  factory AdventureCharacter.fromJson(Map<String, dynamic> json) =>
      AdventureCharacter(
        plantId: _int(json['plant_id']),
        name: json['name']?.toString() ?? '마음꽃',
        stage: _int(json['stage']).clamp(1, 5).toInt(),
        form: PlantGrowthForm.fromCode(json['form']),
        speciesCode: json['species_code']?.toString() ?? 'basic_sprout',
        speciesName: json['species_name']?.toString() ?? '마음꽃',
        stats: ((json['stats'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdventureStat.fromJson)
            .toList(growable: false),
        outfit: json['outfit'] is Map<String, dynamic>
            ? AdventureOutfit.fromJson(_map(json['outfit']))
            : null,
      );
}

class AdventureRewardPreview {
  const AdventureRewardPreview({
    required this.exp,
    required this.seeds,
    required this.itemCode,
  });

  final int exp;
  final int seeds;
  final String itemCode;

  factory AdventureRewardPreview.fromJson(Map<String, dynamic> json) =>
      AdventureRewardPreview(
        exp: _int(json['exp']),
        seeds: _int(json['seeds']),
        itemCode: json['item_code']?.toString() ?? '',
      );
}

class PatrolRoute {
  const PatrolRoute({
    required this.code,
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.baseDurationMinutes,
    required this.timeReductionMinutes,
    required this.requiredStage,
    required this.available,
    required this.recommendedStats,
    required this.performanceScore,
    required this.projectedQuantity,
    required this.bestMatch,
    required this.reward,
  });

  final String code;
  final String name;
  final String description;
  final int durationMinutes;
  final int baseDurationMinutes;
  final int timeReductionMinutes;
  final int requiredStage;
  final bool available;
  final List<String> recommendedStats;
  final int performanceScore;
  final int projectedQuantity;
  final bool bestMatch;
  final AdventureRewardPreview reward;

  factory PatrolRoute.fromJson(Map<String, dynamic> json) => PatrolRoute(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        durationMinutes: _int(json['duration_minutes']),
        baseDurationMinutes: _int(json['base_duration_minutes']) == 0
            ? _int(json['duration_minutes'])
            : _int(json['base_duration_minutes']),
        timeReductionMinutes: _int(json['time_reduction_minutes']),
        requiredStage: _int(json['required_stage']),
        available: json['available'] == true,
        recommendedStats:
            ((json['recommended_stats'] as List<dynamic>?) ?? const [])
                .map((value) => value.toString())
                .toList(growable: false),
        performanceScore: _int(json['performance_score']),
        projectedQuantity: _int(json['projected_quantity']),
        bestMatch: json['best_match'] == true,
        reward: AdventureRewardPreview.fromJson(_map(json['reward'])),
      );
}

class ActivePatrol {
  const ActivePatrol({
    required this.id,
    required this.routeName,
    required this.status,
    required this.returnsAt,
    required this.readyToClaim,
    required this.performanceScore,
  });

  final int id;
  final String routeName;
  final String status;
  final DateTime? returnsAt;
  final bool readyToClaim;
  final int performanceScore;

  bool get claimed => status == 'claimed';

  factory ActivePatrol.fromJson(Map<String, dynamic> json) => ActivePatrol(
        id: _int(json['id']),
        routeName: json['route_name']?.toString() ?? '순찰',
        status: json['status']?.toString() ?? 'active',
        returnsAt: DateTime.tryParse(json['returns_at']?.toString() ?? ''),
        readyToClaim: json['ready_to_claim'] == true,
        performanceScore: _int(json['performance_score']),
      );
}

class DungeonApproach {
  const DungeonApproach({
    required this.code,
    required this.name,
    required this.description,
    required this.statCode,
    required this.statLabel,
    required this.statValue,
    required this.recommended,
    required this.performanceScore,
    required this.projectedQuantity,
    required this.projectedOutcome,
  });

  final String code;
  final String name;
  final String description;
  final String statCode;
  final String statLabel;
  final int statValue;
  final bool recommended;
  final int performanceScore;
  final int projectedQuantity;
  final String projectedOutcome;

  bool get resonant => projectedOutcome == 'resonant';

  factory DungeonApproach.fromJson(Map<String, dynamic> json) =>
      DungeonApproach(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        statCode: json['stat_code']?.toString() ?? '',
        statLabel: json['stat_label']?.toString() ?? '',
        statValue: _int(json['stat_value']),
        recommended: json['recommended'] == true,
        performanceScore: _int(json['performance_score']),
        projectedQuantity: _int(json['projected_quantity']),
        projectedOutcome: json['projected_outcome']?.toString() ?? 'steady',
      );
}

class AdventureDungeon {
  const AdventureDungeon({
    required this.code,
    required this.name,
    required this.description,
    required this.requiredStage,
    required this.discovered,
    required this.available,
    required this.clearCount,
    required this.recommendedStats,
    required this.assetPath,
    required this.reward,
    required this.approaches,
  });

  final String code;
  final String name;
  final String description;
  final int requiredStage;
  final bool discovered;
  final bool available;
  final int clearCount;
  final List<String> recommendedStats;
  final String assetPath;
  final AdventureRewardPreview reward;
  final List<DungeonApproach> approaches;

  factory AdventureDungeon.fromJson(Map<String, dynamic> json) =>
      AdventureDungeon(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        requiredStage: _int(json['required_stage']),
        discovered: json['discovered'] == true,
        available: json['available'] == true,
        clearCount: _int(json['clear_count']),
        recommendedStats:
            ((json['recommended_stats'] as List<dynamic>?) ?? const [])
                .map((value) => value.toString())
                .toList(growable: false),
        assetPath: json['asset_path']?.toString() ?? '',
        reward: AdventureRewardPreview.fromJson(_map(json['reward'])),
        approaches: ((json['approaches'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DungeonApproach.fromJson)
            .toList(growable: false),
      );
}

class AdventureInventoryItem {
  const AdventureInventoryItem({
    required this.code,
    required this.name,
    required this.description,
    required this.quantity,
    required this.reservedQuantity,
    required this.donatableQuantity,
    required this.canDonate,
  });

  final String code;
  final String name;
  final String description;
  final int quantity;
  final int reservedQuantity;
  final int donatableQuantity;
  final bool canDonate;

  factory AdventureInventoryItem.fromJson(Map<String, dynamic> json) =>
      AdventureInventoryItem(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        quantity: _int(json['quantity']),
        reservedQuantity: _int(json['reserved_quantity']),
        donatableQuantity: _int(json['donatable_quantity']),
        canDonate: json['can_donate'] == true,
      );
}

class AdventureDonationStatus {
  const AdventureDonationStatus({
    required this.availableToday,
    required this.usedToday,
    required this.hasEligibleItem,
    required this.requiredQuantity,
    required this.rewardExp,
    required this.rewardSeeds,
    required this.message,
  });

  final bool availableToday;
  final bool usedToday;
  final bool hasEligibleItem;
  final int requiredQuantity;
  final int rewardExp;
  final int rewardSeeds;
  final String message;

  factory AdventureDonationStatus.fromJson(Map<String, dynamic> json) =>
      AdventureDonationStatus(
        availableToday: json['available_today'] == true,
        usedToday: json['used_today'] == true,
        hasEligibleItem: json['has_eligible_item'] == true,
        requiredQuantity: _int(json['required_quantity']) == 0
            ? 3
            : _int(json['required_quantity']),
        rewardExp: _int(json['reward_exp']),
        rewardSeeds:
            _int(json['reward_seeds']) == 0 ? 2 : _int(json['reward_seeds']),
        message: json['message']?.toString() ?? '표본 기증 정보를 불러오는 중이에요.',
      );
}

class AdventureResearchRequirement {
  const AdventureResearchRequirement({
    required this.code,
    required this.name,
    required this.current,
    required this.required,
  });

  final String code;
  final String name;
  final int current;
  final int required;

  bool get fulfilled => current >= required;

  factory AdventureResearchRequirement.fromJson(Map<String, dynamic> json) =>
      AdventureResearchRequirement(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        current: _int(json['current']),
        required: _int(json['required']),
      );
}

class AdventureResearchProject {
  const AdventureResearchProject({
    required this.code,
    required this.name,
    required this.description,
    required this.completed,
    required this.canComplete,
    required this.requirements,
    required this.effectLabel,
  });

  final String code;
  final String name;
  final String description;
  final bool completed;
  final bool canComplete;
  final List<AdventureResearchRequirement> requirements;
  final String effectLabel;

  factory AdventureResearchProject.fromJson(Map<String, dynamic> json) {
    final effect = _map(json['effect']);
    return AdventureResearchProject(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      completed: json['completed'] == true,
      canComplete: json['can_complete'] == true,
      requirements: ((json['requirements'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdventureResearchRequirement.fromJson)
          .toList(growable: false),
      effectLabel: effect['label']?.toString() ?? '',
    );
  }
}

class AdventureResearchSummary {
  const AdventureResearchSummary({
    required this.completedCount,
    required this.totalCount,
    required this.chapterCompleted,
    required this.chapterName,
  });

  final int completedCount;
  final int totalCount;
  final bool chapterCompleted;
  final String chapterName;

  double get progress =>
      totalCount == 0 ? 0 : (completedCount / totalCount).clamp(0, 1);

  factory AdventureResearchSummary.fromJson(
    Map<String, dynamic> json, {
    required int fallbackTotal,
  }) =>
      AdventureResearchSummary(
        completedCount: _int(json['completed_count']),
        totalCount: _int(json['total_count']) == 0
            ? fallbackTotal
            : _int(json['total_count']),
        chapterCompleted: json['chapter_completed'] == true,
        chapterName: json['chapter_name']?.toString() ?? '온실 밖 탐험 1장',
      );
}

class AdventureJournalEntry {
  const AdventureJournalEntry({
    required this.kind,
    required this.title,
    required this.description,
    required this.occurredAt,
    required this.locationCode,
    required this.itemCode,
    required this.itemName,
    required this.quantity,
    this.outcomeCode,
  });

  final String kind;
  final String title;
  final String description;
  final DateTime? occurredAt;
  final String locationCode;
  final String itemCode;
  final String itemName;
  final int quantity;
  final String? outcomeCode;

  bool get isDungeon => kind == 'dungeon';
  bool get resonant => outcomeCode == 'resonant';

  factory AdventureJournalEntry.fromJson(Map<String, dynamic> json) =>
      AdventureJournalEntry(
        kind: json['kind']?.toString() ?? 'patrol',
        title: json['title']?.toString() ?? '탐험 기록',
        description: json['description']?.toString() ?? '',
        occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? ''),
        locationCode: json['location_code']?.toString() ?? '',
        itemCode: json['item_code']?.toString() ?? '',
        itemName: json['item_name']?.toString() ?? '',
        quantity: _int(json['quantity']),
        outcomeCode: json['outcome_code']?.toString(),
      );
}

class AdventureJournal {
  const AdventureJournal({
    required this.discoveredCount,
    required this.totalDungeons,
    required this.totalClearCount,
    required this.recentEntries,
  });

  final int discoveredCount;
  final int totalDungeons;
  final int totalClearCount;
  final List<AdventureJournalEntry> recentEntries;

  factory AdventureJournal.fromJson(
    Map<String, dynamic> json, {
    required int fallbackTotalDungeons,
  }) =>
      AdventureJournal(
        discoveredCount: _int(json['discovered_count']),
        totalDungeons: _int(json['total_dungeons']) == 0
            ? fallbackTotalDungeons
            : _int(json['total_dungeons']),
        totalClearCount: _int(json['total_clear_count']),
        recentEntries: ((json['recent_entries'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdventureJournalEntry.fromJson)
            .toList(growable: false),
      );
}

class AdventureStoryItem {
  const AdventureStoryItem({
    required this.kind,
    required this.code,
    required this.locationCode,
    required this.locationName,
    required this.discovered,
    required this.title,
    required this.text,
    required this.detail,
    required this.discoveredAt,
  });

  final String kind;
  final String code;
  final String locationCode;
  final String locationName;
  final bool discovered;
  final String? title;
  final String? text;
  final String? detail;
  final DateTime? discoveredAt;

  bool get isDungeon => kind == 'dungeon';

  factory AdventureStoryItem.fromJson(Map<String, dynamic> json) =>
      AdventureStoryItem(
        kind: json['kind']?.toString() ?? 'patrol',
        code: json['code']?.toString() ?? '',
        locationCode: json['location_code']?.toString() ?? '',
        locationName: json['location_name']?.toString() ?? '알 수 없는 장소',
        discovered: json['discovered'] == true,
        title: json['title']?.toString(),
        text: json['text']?.toString(),
        detail: json['detail']?.toString(),
        discoveredAt: DateTime.tryParse(
          json['discovered_at']?.toString() ?? '',
        ),
      );
}

class AdventureStoryChapter {
  const AdventureStoryChapter({
    required this.code,
    required this.name,
    required this.description,
    required this.collectedCount,
    required this.totalCount,
    required this.items,
  });

  final String code;
  final String name;
  final String description;
  final int collectedCount;
  final int totalCount;
  final List<AdventureStoryItem> items;

  double get progress => totalCount == 0
      ? 0
      : (collectedCount / totalCount).clamp(0, 1).toDouble();

  factory AdventureStoryChapter.fromJson(Map<String, dynamic> json) =>
      AdventureStoryChapter(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '탐험 이야기',
        description: json['description']?.toString() ?? '',
        collectedCount: _int(json['collected_count']),
        totalCount: _int(json['total_count']),
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdventureStoryItem.fromJson)
            .toList(growable: false),
      );
}

class AdventureStoryCollection {
  const AdventureStoryCollection({
    required this.collectedCount,
    required this.totalCount,
    required this.completed,
    required this.chapters,
  });

  final int collectedCount;
  final int totalCount;
  final bool completed;
  final List<AdventureStoryChapter> chapters;

  double get progress => totalCount == 0
      ? 0
      : (collectedCount / totalCount).clamp(0, 1).toDouble();

  factory AdventureStoryCollection.fromJson(Map<String, dynamic> json) =>
      AdventureStoryCollection(
        collectedCount: _int(json['collected_count']),
        totalCount: _int(json['total_count']),
        completed: json['completed'] == true,
        chapters: ((json['chapters'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdventureStoryChapter.fromJson)
            .toList(growable: false),
      );
}

class AdventureWeeklyGoal {
  const AdventureWeeklyGoal({
    required this.code,
    required this.name,
    required this.description,
    required this.progress,
    required this.target,
    required this.rewardExp,
    required this.rewardSeeds,
    required this.completed,
    required this.claimed,
    required this.canClaim,
  });

  final String code;
  final String name;
  final String description;
  final int progress;
  final int target;
  final int rewardExp;
  final int rewardSeeds;
  final bool completed;
  final bool claimed;
  final bool canClaim;

  bool get isDiary => code == 'diary_3';
  double get progressRatio =>
      target == 0 ? 0 : (progress / target).clamp(0, 1).toDouble();

  factory AdventureWeeklyGoal.fromJson(Map<String, dynamic> json) =>
      AdventureWeeklyGoal(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '주간 목표',
        description: json['description']?.toString() ?? '',
        progress: _int(json['progress']),
        target: _int(json['target']),
        rewardExp: _int(json['reward_exp']),
        rewardSeeds: _int(json['reward_seeds']),
        completed: json['completed'] == true,
        claimed: json['claimed'] == true,
        canClaim: json['can_claim'] == true,
      );
}

class AdventureWeeklyBoard {
  const AdventureWeeklyBoard({
    required this.weekStart,
    required this.weekEnd,
    required this.goals,
  });

  final DateTime? weekStart;
  final DateTime? weekEnd;
  final List<AdventureWeeklyGoal> goals;

  factory AdventureWeeklyBoard.fromJson(Map<String, dynamic> json) =>
      AdventureWeeklyBoard(
        weekStart: DateTime.tryParse(json['week_start']?.toString() ?? ''),
        weekEnd: DateTime.tryParse(json['week_end']?.toString() ?? ''),
        goals: ((json['goals'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdventureWeeklyGoal.fromJson)
            .toList(growable: false),
      );
}

class AdventureMilestone {
  const AdventureMilestone({
    required this.code,
    required this.name,
    required this.description,
    required this.progress,
    required this.target,
    required this.unlocked,
    required this.title,
  });

  final String code;
  final String name;
  final String description;
  final int progress;
  final int target;
  final bool unlocked;
  final String title;

  double get progressRatio =>
      target == 0 ? 0 : (progress / target).clamp(0, 1).toDouble();

  factory AdventureMilestone.fromJson(Map<String, dynamic> json) =>
      AdventureMilestone(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '탐험 발자국',
        description: json['description']?.toString() ?? '',
        progress: _int(json['progress']),
        target: _int(json['target']),
        unlocked: json['unlocked'] == true,
        title: json['title']?.toString() ?? '탐험가',
      );
}

class AdventureMilestones {
  const AdventureMilestones({
    required this.currentTitle,
    required this.unlockedCount,
    required this.totalCount,
    required this.items,
  });

  final String currentTitle;
  final int unlockedCount;
  final int totalCount;
  final List<AdventureMilestone> items;

  factory AdventureMilestones.fromJson(Map<String, dynamic> json) {
    final items = ((json['items'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AdventureMilestone.fromJson)
        .toList(growable: false);
    return AdventureMilestones(
      currentTitle: json['current_title']?.toString() ?? '첫 발자국',
      unlockedCount: _int(json['unlocked_count']),
      totalCount: _int(json['total_count']) == 0
          ? items.length
          : _int(json['total_count']),
      items: items,
    );
  }
}

class AdventureState {
  const AdventureState({
    required this.suspended,
    required this.diaryReady,
    required this.diaryMessage,
    required this.economy,
    required this.weeklyBoard,
    required this.milestones,
    required this.routes,
    required this.dungeons,
    required this.inventory,
    required this.donation,
    required this.researchProjects,
    required this.researchSummary,
    required this.journal,
    required this.storyCollection,
    required this.dungeonRunAvailable,
    this.character,
    this.patrol,
  });

  final bool suspended;
  final bool diaryReady;
  final String diaryMessage;
  final List<AdventureEconomyEntry> economy;
  final AdventureWeeklyBoard weeklyBoard;
  final AdventureMilestones milestones;
  final AdventureCharacter? character;
  final List<PatrolRoute> routes;
  final ActivePatrol? patrol;
  final bool dungeonRunAvailable;
  final List<AdventureDungeon> dungeons;
  final List<AdventureInventoryItem> inventory;
  final AdventureDonationStatus donation;
  final List<AdventureResearchProject> researchProjects;
  final AdventureResearchSummary researchSummary;
  final AdventureJournal journal;
  final AdventureStoryCollection storyCollection;

  factory AdventureState.fromJson(Map<String, dynamic> json) {
    final requirement = _map(json['diary_requirement']);
    final dungeons = ((json['dungeons'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AdventureDungeon.fromJson)
        .toList(growable: false);
    final researchProjects =
        ((json['research_projects'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdventureResearchProject.fromJson)
            .toList(growable: false);
    return AdventureState(
      suspended: json['suspended'] == true,
      diaryReady: json['diary_ready'] == true,
      diaryMessage:
          requirement['message']?.toString() ?? '오늘 마음 일기를 쓰면 탐험이 열려요.',
      economy: ((json['economy'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdventureEconomyEntry.fromJson)
          .toList(growable: false),
      weeklyBoard: AdventureWeeklyBoard.fromJson(_map(json['weekly_board'])),
      milestones: AdventureMilestones.fromJson(_map(json['milestones'])),
      character: json['character'] is Map<String, dynamic>
          ? AdventureCharacter.fromJson(_map(json['character']))
          : null,
      routes: ((json['routes'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PatrolRoute.fromJson)
          .toList(growable: false),
      patrol: json['patrol'] is Map<String, dynamic>
          ? ActivePatrol.fromJson(_map(json['patrol']))
          : null,
      dungeonRunAvailable: json['dungeon_run_available'] == true,
      dungeons: dungeons,
      inventory: ((json['inventory'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdventureInventoryItem.fromJson)
          .toList(growable: false),
      donation: AdventureDonationStatus.fromJson(_map(json['donation'])),
      researchProjects: researchProjects,
      researchSummary: AdventureResearchSummary.fromJson(
        _map(json['research_summary']),
        fallbackTotal: researchProjects.length,
      ),
      journal: AdventureJournal.fromJson(
        _map(json['journal']),
        fallbackTotalDungeons: dungeons.length,
      ),
      storyCollection: AdventureStoryCollection.fromJson(
        _map(json['story_collection']),
      ),
    );
  }
}

class AdventureActionResult {
  const AdventureActionResult({
    required this.state,
    this.seedBalance,
    this.outcomeMessage,
  });

  final AdventureState state;
  final int? seedBalance;
  final String? outcomeMessage;

  factory AdventureActionResult.fromJson(Map<String, dynamic> json) {
    final reward = _map(json['reward']);
    final run = _map(json['run']);
    return AdventureActionResult(
      state: AdventureState.fromJson(_map(json['state'])),
      seedBalance: reward.containsKey('seed_balance')
          ? _int(reward['seed_balance'])
          : null,
      outcomeMessage: json['outcome_message']?.toString() ??
          run['outcome_message']?.toString(),
    );
  }
}
