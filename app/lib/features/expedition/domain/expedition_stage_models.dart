/// 스테이지 지도와 모험 허브가 읽는 진행 상태.
///
/// 개편 설계서(stage-battle-v2.0) 3.1·5.1·5.2의 화면 계약을 그대로 옮긴다.
/// 지역 하나는 8개 스테이지로 나뉘고 `기억서고 3`처럼 지역명과 번호로 부른다.
library;

int _stageInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Map<String, dynamic> _stageMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _stageMaps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

enum ExpeditionStageKind {
  battle,
  event,
  camp,
  boss;

  static ExpeditionStageKind fromCode(String? code) => switch (code) {
        'event' => ExpeditionStageKind.event,
        'camp' => ExpeditionStageKind.camp,
        'boss' => ExpeditionStageKind.boss,
        _ => ExpeditionStageKind.battle,
      };
}

class ExpeditionStageMap {
  const ExpeditionStageMap({
    required this.contentVersion,
    required this.region,
    required this.clearedCount,
    required this.total,
    required this.nextStageNo,
    required this.regionCleared,
    required this.activeRunId,
    required this.activeStageNo,
    required this.stages,
  });

  final String contentVersion;
  final ExpeditionStageRegion region;
  final int clearedCount;
  final int total;

  /// 허브의 `이어서 모험하기`가 가리키는 스테이지. 모두 완주했으면 null이다.
  final int? nextStageNo;
  final bool regionCleared;
  final int? activeRunId;
  final int? activeStageNo;
  final List<ExpeditionStage> stages;

  bool get hasActiveRun => activeRunId != null;

  ExpeditionStage? get nextStage {
    final no = nextStageNo;
    if (no == null) return null;
    return stages.where((stage) => stage.no == no).firstOrNull;
  }

  ExpeditionStage? stageOf(int? no) =>
      no == null ? null : stages.where((stage) => stage.no == no).firstOrNull;

  factory ExpeditionStageMap.fromJson(Map<String, dynamic> json) {
    final progress = _stageMap(json['progress']);
    final active = json['active_run'];
    return ExpeditionStageMap(
      contentVersion: json['content_version'] as String? ?? '',
      region: ExpeditionStageRegion.fromJson(_stageMap(json['region'])),
      clearedCount: _stageInt(progress['cleared_count']),
      total: _stageInt(progress['total'], 8),
      nextStageNo: progress['next_stage_no'] is num
          ? (progress['next_stage_no'] as num).toInt()
          : null,
      regionCleared: progress['region_cleared'] == true,
      activeRunId: active is Map<String, dynamic> && active['run_id'] is num
          ? (active['run_id'] as num).toInt()
          : null,
      activeStageNo: active is Map<String, dynamic> && active['stage_no'] is num
          ? (active['stage_no'] as num).toInt()
          : null,
      stages: _stageMaps(json['stages'])
          .map(ExpeditionStage.fromJson)
          .toList(growable: false),
    );
  }
}

class ExpeditionStageRegion {
  const ExpeditionStageRegion({
    required this.code,
    required this.name,
    required this.shortName,
    required this.description,
    required this.recommendedStage,
  });

  final String code;
  final String name;
  final String shortName;
  final String description;
  final int recommendedStage;

  factory ExpeditionStageRegion.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    return ExpeditionStageRegion(
      code: json['code'] as String? ?? '',
      name: name,
      shortName: json['short_name'] as String? ?? name,
      description: json['description'] as String? ?? '',
      recommendedStage: _stageInt(json['recommended_stage'], 1),
    );
  }
}

class ExpeditionStage {
  const ExpeditionStage({
    required this.no,
    required this.kind,
    required this.kindLabel,
    required this.elite,
    required this.label,
    required this.title,
    required this.summary,
    required this.estimatedSeconds,
    required this.weakness,
    required this.weaknessLabel,
    required this.tangles,
    required this.cleared,
    required this.clearCount,
    required this.storySeen,
    required this.story,
    required this.unlocked,
    required this.lockReason,
  });

  final int no;
  final ExpeditionStageKind kind;
  final String kindLabel;

  /// 큰 엉킴(중간 보스). 같은 전투 아이콘을 쓰고 표식만 더 붙인다.
  final bool elite;
  final String label;
  final String title;
  final String summary;
  final int estimatedSeconds;
  final String? weakness;
  final String? weaknessLabel;
  final List<ExpeditionTangle> tangles;
  final bool cleared;
  final int clearCount;
  final bool storySeen;
  final ExpeditionStageStory? story;
  final bool unlocked;
  final String? lockReason;

  /// 클리어했지만 이야기 컷을 아직 안 봤을 때 지도에 남는 책갈피 표시.
  bool get hasUnreadStory => cleared && !storySeen;

  String get estimatedLabel {
    final minutes = estimatedSeconds ~/ 60;
    final seconds = estimatedSeconds % 60;
    if (minutes == 0) return '약 $seconds초';
    if (seconds == 0) return '약 $minutes분';
    return '약 $minutes분 $seconds초';
  }

  factory ExpeditionStage.fromJson(Map<String, dynamic> json) =>
      ExpeditionStage(
        no: _stageInt(json['no'], 1),
        kind: ExpeditionStageKind.fromCode(json['kind'] as String?),
        kindLabel: json['kind_label'] as String? ?? '',
        elite: json['elite'] == true,
        label: json['label'] as String? ?? '',
        title: json['title'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        estimatedSeconds: _stageInt(json['estimated_seconds'], 60),
        weakness: json['weakness'] as String?,
        weaknessLabel: json['weakness_label'] as String?,
        tangles: _stageMaps(json['tangles'])
            .map(ExpeditionTangle.fromJson)
            .toList(growable: false),
        cleared: json['cleared'] == true,
        clearCount: _stageInt(json['clear_count']),
        storySeen: json['story_seen'] == true,
        story: json['story'] is Map<String, dynamic>
            ? ExpeditionStageStory.fromJson(_stageMap(json['story']))
            : null,
        unlocked: json['unlocked'] == true,
        lockReason: json['lock_reason'] as String?,
      );
}

class ExpeditionTangle {
  const ExpeditionTangle({
    required this.code,
    required this.name,
    required this.description,
    required this.knowledgeLevel,
    required this.skills,
  });

  final String code;
  final String name;
  final String description;
  final String knowledgeLevel;
  final List<String> skills;

  bool get catalogued => knowledgeLevel == 'catalogued';

  factory ExpeditionTangle.fromJson(Map<String, dynamic> json) =>
      ExpeditionTangle(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        knowledgeLevel: json['knowledge_level'] as String? ?? 'silhouette',
        skills: (json['skills'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );
}

/// 최초 클리어 뒤에만 공개되는 짧은 캠페인 장면.
///
/// 전투 중에는 전달하지 않고 귀환 결과와 도서관 다시보기에서만 사용한다.
/// 일기 텍스트나 감정 점수를 입력값으로 받지 않는 사전 제작 콘텐츠다.
class ExpeditionStageStory {
  const ExpeditionStageStory({
    required this.code,
    required this.chapter,
    required this.phase,
    required this.title,
    required this.caption,
    required this.sceneKey,
    required this.visualAsset,
    required this.audioCue,
    required this.codexEntry,
  });

  final String code;
  final int chapter;
  final String phase;
  final String title;
  final String caption;
  final String sceneKey;
  final String? visualAsset;
  final String? audioCue;
  final String codexEntry;

  factory ExpeditionStageStory.fromJson(Map<String, dynamic> json) =>
      ExpeditionStageStory(
        code: json['code'] as String? ?? '',
        chapter: _stageInt(json['chapter']),
        phase: json['phase'] as String? ?? '',
        title: json['title'] as String? ?? '',
        caption: json['caption'] as String? ?? '',
        sceneKey: json['scene_key'] as String? ?? 'dungeon_gate',
        visualAsset: json['visual_asset'] as String?,
        audioCue: json['audio_cue'] as String?,
        codexEntry: json['codex_entry'] as String? ?? '',
      );
}
