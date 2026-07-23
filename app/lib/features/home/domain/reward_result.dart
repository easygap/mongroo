import 'plant.dart';

/// 보상이 발생한 쓰기 응답에 포함되는 reward(api.md RewardResult).
class RewardEvent {
  const RewardEvent({
    required this.eventType,
    required this.expDelta,
    required this.seedDelta,
  });

  final String eventType;
  final int expDelta;
  final int seedDelta;

  factory RewardEvent.fromJson(Map<String, dynamic> json) => RewardEvent(
        eventType: (json['event_type'] as String?) ?? '',
        expDelta: (json['exp_delta'] as int?) ?? 0,
        seedDelta: (json['seed_delta'] as int?) ?? 0,
      );
}

class RewardPlantState {
  const RewardPlantState({
    required this.id,
    required this.exp,
    required this.stage,
    required this.stageChanged,
    required this.harvestable,
    this.growthForm,
  });

  final int id;
  final int exp;
  final int stage;
  final bool stageChanged;
  final bool harvestable;
  final PlantGrowthForm? growthForm;

  factory RewardPlantState.fromJson(Map<String, dynamic> json) =>
      RewardPlantState(
        id: (json['id'] as int?) ?? 0,
        exp: (json['exp'] as int?) ?? 0,
        stage: (json['stage'] as int?) ?? 1,
        stageChanged: (json['stage_changed'] as bool?) ?? false,
        harvestable: (json['harvestable'] as bool?) ?? false,
        growthForm: PlantGrowthForm.fromCode(
          json['growth_form'] ?? json['growth_branch'],
        ),
      );
}

class RewardResult {
  const RewardResult({
    required this.events,
    required this.plant,
    required this.dailyExpGranted,
    required this.dailyExpCap,
    required this.seedBalance,
  });

  final List<RewardEvent> events;
  final RewardPlantState? plant;
  final int dailyExpGranted;
  final int dailyExpCap;
  final int seedBalance;

  int get totalExp => events.fold(0, (sum, e) => sum + e.expDelta);
  int get totalSeeds => events.fold(0, (sum, e) => sum + e.seedDelta);
  bool get stageChanged => plant?.stageChanged ?? false;

  factory RewardResult.fromJson(Map<String, dynamic> json) => RewardResult(
        events: ((json['events'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RewardEvent.fromJson)
            .toList(),
        plant: json['plant'] is Map<String, dynamic>
            ? RewardPlantState.fromJson(json['plant'] as Map<String, dynamic>)
            : null,
        dailyExpGranted: (json['daily_exp_granted'] as int?) ?? 0,
        dailyExpCap: (json['daily_exp_cap'] as int?) ?? 30,
        seedBalance: (json['seed_balance'] as int?) ?? 0,
      );

  static RewardResult? fromJsonOrNull(Object? json) {
    if (json is Map<String, dynamic>) return RewardResult.fromJson(json);
    return null;
  }
}
