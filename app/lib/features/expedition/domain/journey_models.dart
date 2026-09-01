int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _list(Object? value) =>
    (value as List? ?? const []).whereType<Map<String, dynamic>>().toList();

/// 장거리 개척 입구 — 어떤 방향이 열려 있는지와 진행 중인 개척.
class JourneyEntry {
  const JourneyEntry({
    required this.unlocked,
    required this.directions,
    this.active,
  });

  final bool unlocked;
  final List<JourneyDirection> directions;
  final Journey? active;

  factory JourneyEntry.fromJson(Map<String, dynamic> json) => JourneyEntry(
        unlocked: json['unlocked'] == true,
        directions: _list(json['directions'])
            .map(JourneyDirection.fromJson)
            .toList(growable: false),
        active: json['active'] == null
            ? null
            : Journey.fromJson(_map(json['active'])),
      );
}

/// 떠날 수 있는 방향 하나.
class JourneyDirection {
  const JourneyDirection({
    required this.code,
    required this.name,
    required this.summary,
    required this.maxLegs,
    required this.partySize,
    required this.maxOwnMembers,
    required this.minMinutes,
    required this.maxMinutes,
    required this.locked,
    this.lockReason,
  });

  final String code;
  final String name;
  final String summary;
  final int maxLegs;

  /// 한 구간에 서는 사람 수. 캐릭터든 길잡이든 합쳐서 이 수다.
  final int partySize;

  /// 이 방향에서 쓸 수 있는 내 캐릭터의 최대 수(= 구간 수 × 자리 수).
  final int maxOwnMembers;

  final int minMinutes;
  final int maxMinutes;
  final bool locked;
  final String? lockReason;

  factory JourneyDirection.fromJson(Map<String, dynamic> json) {
    final minutes = (json['minutes'] as List? ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(growable: false);
    return JourneyDirection(
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      maxLegs: _asInt(json['max_legs'], 2),
      partySize: _asInt(json['party_size'], 2),
      maxOwnMembers: _asInt(json['max_own_members'], 4),
      minMinutes: minutes.isEmpty ? 0 : minutes.first,
      maxMinutes: minutes.length < 2 ? 0 : minutes[1],
      locked: json['locked'] == true,
      lockReason: json['lock_reason'] as String?,
    );
  }
}

/// 야영지에서 고르는 갈림길.
class JourneyRoute {
  const JourneyRoute({
    required this.code,
    required this.name,
    required this.regionCode,
    required this.hint,
  });

  final String code;
  final String name;
  final String regionCode;
  final String hint;

  factory JourneyRoute.fromJson(Map<String, dynamic> json) => JourneyRoute(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        regionCode: json['region_code'] as String? ?? '',
        hint: json['hint'] as String? ?? '',
      );
}

/// 이미 걸은(또는 걷고 있는) 구간 하나.
class JourneyLeg {
  const JourneyLeg({
    required this.legIndex,
    required this.runId,
    required this.routeName,
    required this.regionName,
    required this.status,
    required this.objectiveSecured,
    required this.party,
  });

  final int legIndex;
  final int runId;
  final String routeName;
  final String regionName;
  final String status;
  final bool objectiveSecured;

  /// 그 구간에 선 두 사람. 길잡이도 이름으로 남는다.
  final List<JourneyMember> party;

  bool get walking => status == 'active';

  factory JourneyLeg.fromJson(Map<String, dynamic> json) => JourneyLeg(
        legIndex: _asInt(json['leg_index']),
        runId: _asInt(json['run_id']),
        routeName: json['route_name'] as String? ?? '',
        regionName: json['region_name'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        objectiveSecured: json['objective_secured'] == true,
        party: _list(json['party'])
            .map(JourneyMember.fromJson)
            .toList(growable: false),
      );
}

class JourneyMember {
  const JourneyMember({
    required this.name,
    required this.isGuide,
    this.plantId,
  });

  final String name;
  final bool isGuide;
  final int? plantId;

  factory JourneyMember.fromJson(Map<String, dynamic> json) => JourneyMember(
        name: json['name'] as String? ?? '',
        isGuide: json['is_guide'] == true,
        plantId: json['plant_id'] is num ? _asInt(json['plant_id']) : null,
      );
}

/// 진행 중이거나 막 끝난 개척 하나.
class Journey {
  const Journey({
    required this.id,
    required this.directionName,
    required this.status,
    required this.maxLegs,
    required this.currentLegIndex,
    required this.revision,
    required this.legs,
    required this.usedPlantIds,
    required this.partySize,
    required this.atCamp,
    required this.canContinue,
    required this.nextRoutes,
    this.activeRunId,
    this.deepestRegionName,
    this.rewardExp,
    this.rewardSeeds,
    this.summary,
  });

  final int id;
  final String directionName;
  final String status;
  final int maxLegs;

  /// 다음에 만들 구간의 번호. 곧 `지금까지 마친 구간 수`이기도 하다.
  final int currentLegIndex;

  final int revision;
  final List<JourneyLeg> legs;
  final List<int> usedPlantIds;
  final int partySize;

  /// 야영지에 있다 — 걷는 구간이 없고 개척은 아직 살아 있다.
  final bool atCamp;

  /// 야영지이고 갈 구간이 남았다.
  final bool canContinue;

  final List<JourneyRoute> nextRoutes;
  final int? activeRunId;
  final String? deepestRegionName;
  final int? rewardExp;
  final int? rewardSeeds;
  final JourneySummary? summary;

  bool get finished => status != 'active';

  factory Journey.fromJson(Map<String, dynamic> json) {
    final band = _map(json['reward_band']);
    return Journey(
      id: _asInt(json['id']),
      directionName: json['direction_name'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      maxLegs: _asInt(json['max_legs'], 2),
      currentLegIndex: _asInt(json['current_leg_index']),
      revision: _asInt(json['revision']),
      legs: _list(json['legs']).map(JourneyLeg.fromJson).toList(growable: false),
      usedPlantIds: (json['used_plant_ids'] as List? ?? const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(growable: false),
      partySize: _asInt(json['party_size'], 2),
      atCamp: json['at_camp'] == true,
      canContinue: json['can_continue'] == true,
      nextRoutes: _list(json['next_routes'])
          .map(JourneyRoute.fromJson)
          .toList(growable: false),
      activeRunId:
          json['active_run_id'] is num ? _asInt(json['active_run_id']) : null,
      deepestRegionName: json['deepest_secured_region_name'] as String?,
      rewardExp: band['exp'] is num ? _asInt(band['exp']) : null,
      rewardSeeds: band['seeds'] is num ? _asInt(band['seeds']) : null,
      summary: json['summary'] == null
          ? null
          : JourneySummary.fromJson(_map(json['summary'])),
    );
  }
}

/// 귀환 뒤에 남는 원정 기록.
class JourneySummary {
  const JourneySummary({
    required this.title,
    required this.legCount,
    required this.securedCount,
    required this.legs,
    this.deepestRegionName,
    this.rewardExp,
    this.rewardSeeds,
  });

  final String title;
  final int legCount;
  final int securedCount;
  final List<JourneyLeg> legs;
  final String? deepestRegionName;
  final int? rewardExp;
  final int? rewardSeeds;

  bool get rewarded => rewardExp != null || rewardSeeds != null;

  factory JourneySummary.fromJson(Map<String, dynamic> json) {
    // 보상은 원장 이벤트 안에 들어 있다. 지급이 없으면 통째로 null이다.
    final events = _list(_map(json['reward'])['events']);
    final first = events.isEmpty ? const <String, dynamic>{} : events.first;
    return JourneySummary(
      title: json['title'] as String? ?? '',
      legCount: _asInt(json['leg_count']),
      securedCount: _asInt(json['secured_count']),
      legs: _list(json['legs']).map(JourneyLeg.fromJson).toList(growable: false),
      deepestRegionName: json['deepest_region_name'] as String?,
      rewardExp: first['exp_delta'] is num ? _asInt(first['exp_delta']) : null,
      rewardSeeds:
          first['seed_delta'] is num ? _asInt(first['seed_delta']) : null,
    );
  }
}
