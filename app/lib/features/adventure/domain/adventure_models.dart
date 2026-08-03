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
  });

  final String code;
  final String label;
  final int exp;
  final int seeds;

  factory AdventureEconomyEntry.fromJson(Map<String, dynamic> json) =>
      AdventureEconomyEntry(
        code: json['code']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        exp: _int(json['exp']),
        seeds: _int(json['seeds']),
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
    required this.requiredStage,
    required this.available,
    required this.recommendedStats,
    required this.reward,
  });

  final String code;
  final String name;
  final String description;
  final int durationMinutes;
  final int requiredStage;
  final bool available;
  final List<String> recommendedStats;
  final AdventureRewardPreview reward;

  factory PatrolRoute.fromJson(Map<String, dynamic> json) => PatrolRoute(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        durationMinutes: _int(json['duration_minutes']),
        requiredStage: _int(json['required_stage']),
        available: json['available'] == true,
        recommendedStats:
            ((json['recommended_stats'] as List<dynamic>?) ?? const [])
                .map((value) => value.toString())
                .toList(growable: false),
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
      );
}

class AdventureInventoryItem {
  const AdventureInventoryItem({
    required this.code,
    required this.name,
    required this.description,
    required this.quantity,
  });

  final String code;
  final String name;
  final String description;
  final int quantity;

  factory AdventureInventoryItem.fromJson(Map<String, dynamic> json) =>
      AdventureInventoryItem(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        quantity: _int(json['quantity']),
      );
}

class AdventureState {
  const AdventureState({
    required this.suspended,
    required this.diaryReady,
    required this.diaryMessage,
    required this.economy,
    required this.routes,
    required this.dungeons,
    required this.inventory,
    required this.dungeonRunAvailable,
    this.character,
    this.patrol,
  });

  final bool suspended;
  final bool diaryReady;
  final String diaryMessage;
  final List<AdventureEconomyEntry> economy;
  final AdventureCharacter? character;
  final List<PatrolRoute> routes;
  final ActivePatrol? patrol;
  final bool dungeonRunAvailable;
  final List<AdventureDungeon> dungeons;
  final List<AdventureInventoryItem> inventory;

  factory AdventureState.fromJson(Map<String, dynamic> json) {
    final requirement = _map(json['diary_requirement']);
    return AdventureState(
      suspended: json['suspended'] == true,
      diaryReady: json['diary_ready'] == true,
      diaryMessage:
          requirement['message']?.toString() ?? '오늘 마음 일기를 쓰면 탐험이 열려요.',
      economy: ((json['economy'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdventureEconomyEntry.fromJson)
          .toList(growable: false),
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
      dungeons: ((json['dungeons'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdventureDungeon.fromJson)
          .toList(growable: false),
      inventory: ((json['inventory'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AdventureInventoryItem.fromJson)
          .toList(growable: false),
    );
  }
}

class AdventureActionResult {
  const AdventureActionResult({required this.state, this.seedBalance});

  final AdventureState state;
  final int? seedBalance;

  factory AdventureActionResult.fromJson(Map<String, dynamic> json) {
    final reward = _map(json['reward']);
    return AdventureActionResult(
      state: AdventureState.fromJson(_map(json['state'])),
      seedBalance: reward.containsKey('seed_balance')
          ? _int(reward['seed_balance'])
          : null,
    );
  }
}
