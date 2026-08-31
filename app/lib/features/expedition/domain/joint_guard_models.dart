import 'expedition_models.dart';

int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

/// 합동 수호전 입구가 읽는 목록 — 어떤 짐승이 열려 있고 어떤 난이도가 있는지.
class JointGuardEntry {
  const JointGuardEntry({
    required this.beasts,
    required this.difficulties,
    this.activeRunId,
  });

  final List<JointGuardBeast> beasts;
  final List<JointGuardDifficulty> difficulties;
  final int? activeRunId;

  bool get hasAnyOpen => beasts.any((beast) => beast.unlocked);

  factory JointGuardEntry.fromJson(Map<String, dynamic> json) => JointGuardEntry(
        beasts: (json['beasts'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(JointGuardBeast.fromJson)
            .toList(growable: false),
        difficulties: (json['difficulties'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(JointGuardDifficulty.fromJson)
            .toList(growable: false),
        activeRunId:
            json['active_run_id'] is num ? _asInt(json['active_run_id']) : null,
      );
}

class JointGuardBeast {
  const JointGuardBeast({
    required this.code,
    required this.name,
    required this.regionCode,
    required this.dreamScene,
    required this.holding,
    required this.unlocked,
    this.lockedReason,
  });

  final String code;
  final String name;
  final String regionCode;

  /// 그 짐승의 꿈이 어떤 곳인지. 입구 카드가 한 줄로 읽어 준다.
  final String dreamScene;

  /// 짐승이 품에 안고 있는 것. 이야기의 축이라 카드에 반드시 적는다.
  final String holding;

  final bool unlocked;
  final String? lockedReason;

  factory JointGuardBeast.fromJson(Map<String, dynamic> json) => JointGuardBeast(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        regionCode: json['region_code'] as String? ?? '',
        dreamScene: json['dream_scene'] as String? ?? '',
        holding: json['holding'] as String? ?? '',
        unlocked: json['unlocked'] == true,
        lockedReason: json['locked_reason'] as String?,
      );
}

class JointGuardDifficulty {
  const JointGuardDifficulty({
    required this.code,
    required this.name,
    required this.summary,
    required this.layers,
    required this.tutorial,
  });

  final String code;
  final String name;
  final String summary;
  final int layers;

  /// 연습을 겸하는 난이도. 처음 여는 사람에게 먼저 권한다.
  final bool tutorial;

  factory JointGuardDifficulty.fromJson(Map<String, dynamic> json) =>
      JointGuardDifficulty(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        layers: _asInt(json['layers'], 1),
        tutorial: json['tutorial'] == true,
      );
}

/// 진행 중인 한 판.
class JointGuardRun {
  const JointGuardRun({
    required this.runId,
    required this.revision,
    required this.state,
  });

  final int runId;
  final int revision;
  final JointGuardState state;

  factory JointGuardRun.fromJson(Map<String, dynamic> json) => JointGuardRun(
        runId: _asInt(_map(json['run'])['id']),
        revision: _asInt(_map(json['run'])['revision']),
        state: JointGuardState.fromJson(_map(json['joint_guard'])),
      );
}

class JointGuardState {
  const JointGuardState({
    required this.status,
    required this.beast,
    required this.difficulty,
    required this.layer,
    required this.front,
    required this.reserves,
    required this.swapsLeft,
    required this.battle,
    required this.log,
  });

  final String status;
  final JointGuardBeast beast;
  final JointGuardDifficulty difficulty;
  final JointGuardLayer layer;

  /// 지금 무대에 선 셋. 화면 동시 표시는 늘 셋을 넘지 않는다.
  final List<JointGuardMember> front;

  /// 뒤에서 기다리는 셋.
  final List<JointGuardMember> reserves;

  final int swapsLeft;
  final ExpeditionBattle battle;
  final List<String> log;

  bool get isActive => status == 'active';
  bool get isAwake => status == 'awake';
  bool get canSwap => isActive && swapsLeft > 0;

  /// 마지막 한 줄. 화면 위쪽에서 지금 무슨 일이 일어났는지 읽어 준다.
  String get latestLine => log.isEmpty ? '' : log.last;

  factory JointGuardState.fromJson(Map<String, dynamic> json) => JointGuardState(
        status: json['status'] as String? ?? 'active',
        beast: JointGuardBeast.fromJson(_map(json['beast'])),
        difficulty: JointGuardDifficulty.fromJson(_map(json['difficulty'])),
        layer: JointGuardLayer.fromJson(_map(json['layer'])),
        front: (json['front'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(JointGuardMember.fromJson)
            .toList(growable: false),
        reserves: (json['reserves'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(JointGuardMember.fromJson)
            .toList(growable: false),
        swapsLeft: _asInt(json['swaps_left']),
        battle: ExpeditionBattle.fromJson(_map(json['battle'])),
        log: (json['log'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );
}

class JointGuardLayer {
  const JointGuardLayer({
    required this.index,
    required this.name,
    required this.count,
    required this.weakKelLabel,
    required this.resistKelLabel,
    this.warning,
  });

  final int index;
  final String name;
  final int count;

  /// 이 겹에서 잘 통하는 결과 잘 안 통하는 결. 겹에 들어설 때 함께 공개된다.
  final String weakKelLabel;
  final String resistKelLabel;

  /// 라운드 안에 예고할 자리가 없는 결정적 순간. 겹 입장에서 미리 알린다.
  final JointGuardMomentWarning? warning;

  /// 사람이 읽는 진행도 — `2겹째 / 3겹`.
  String get progressLabel => '${index + 1}겹째 · 전체 $count겹';

  factory JointGuardLayer.fromJson(Map<String, dynamic> json) => JointGuardLayer(
        index: _asInt(json['index']),
        name: json['name'] as String? ?? '',
        count: _asInt(json['count'], 1),
        weakKelLabel: json['weak_kel_label'] as String? ?? '',
        resistKelLabel: json['resist_kel_label'] as String? ?? '',
        warning: json['warning'] is Map<String, dynamic>
            ? JointGuardMomentWarning.fromJson(_map(json['warning']))
            : null,
      );
}

class JointGuardMomentWarning {
  const JointGuardMomentWarning({
    required this.code,
    required this.name,
    required this.inRounds,
    required this.text,
    required this.bypass,
  });

  final String code;
  final String name;
  final int inRounds;
  final String text;

  /// 역할이 없어도 넘는 길. 예고와 반드시 함께 읽어 준다.
  final String bypass;

  factory JointGuardMomentWarning.fromJson(Map<String, dynamic> json) =>
      JointGuardMomentWarning(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        inRounds: _asInt(json['in_rounds'], 1),
        text: json['text'] as String? ?? '',
        bypass: json['bypass'] as String? ?? '',
      );
}

/// 명단 한 명. 대원 모델을 그대로 품고 있어 기존 스프라이트·슬롯이 읽는다.
class JointGuardMember {
  const JointGuardMember({
    required this.memberId,
    required this.hp,
    required this.maxHp,
    required this.formation,
    required this.member,
    this.canSwapIn = false,
  });

  final int memberId;
  final int hp;
  final int maxHp;
  final String formation;

  /// 기존 탐험 대원 모델. 슬롯과 무대가 이 값으로 스프라이트를 그린다.
  final ExpeditionMember member;

  /// 지금 무대에 설 수 있는가. 지쳐서 물러난 대원은 아직 설 수 없다.
  final bool canSwapIn;

  String get name => member.name;
  bool get isDown => hp <= 0;
  double get hpRatio => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0, 1).toDouble();

  factory JointGuardMember.fromJson(Map<String, dynamic> json) =>
      JointGuardMember(
        memberId: _asInt(json['member_id']),
        hp: _asInt(json['hp']),
        maxHp: _asInt(json['max_hp'], 1),
        formation: json['formation'] as String? ?? 'front',
        canSwapIn: json['can_swap_in'] == true,
        member: ExpeditionMember.fromJson(json),
      );
}
