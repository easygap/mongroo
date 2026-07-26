import '../../home/domain/reward_result.dart';

enum DailyQuestStatus { assigned, completed, skipped }

DailyQuestStatus dailyQuestStatusFromJson(Object? value) {
  switch (value) {
    case 'completed':
      return DailyQuestStatus.completed;
    case 'skipped':
      return DailyQuestStatus.skipped;
    default:
      return DailyQuestStatus.assigned;
  }
}

int _asInt(Object? value, [int fallback = 0]) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text) ?? fallback,
      _ => fallback,
    };

/// 서버에서 검수한 실생활 행동 카탈로그 항목.
class QuestDefinition {
  const QuestDefinition({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.category,
    required this.burdenLevel,
    required this.estimatedMinutes,
    required this.rewardExp,
    required this.rewardSeeds,
  });

  final int id;
  final String code;
  final String title;
  final String description;
  final String category;
  final int burdenLevel;
  final int estimatedMinutes;
  final int rewardExp;
  final int rewardSeeds;

  String get categoryLabel => switch (category) {
        'grounding' || 'senses' => '관찰',
        'reflection' => '기록',
        'body' => '몸풀기',
        'movement' => '움직임',
        'environment' || 'space' => '정리',
        'connection' => '안부',
        'expression' || 'creativity' => '만들기',
        'planning' => '준비',
        'self_kindness' => '내 선택',
        'rest' => '휴식',
        _ => '일상',
      };

  String get burdenLabel => switch (burdenLevel) {
        <= 1 => '준비 거의 없음',
        2 => '준비 조금',
        _ => '준비 필요',
      };

  factory QuestDefinition.fromJson(Map<String, dynamic> json) =>
      QuestDefinition(
        id: _asInt(json['id']),
        code: (json['code'] as String?) ?? '',
        title: (json['title'] as String?) ?? '오늘의 마음 퀘스트',
        description: (json['description'] as String?) ?? '',
        category: (json['category'] as String?) ?? 'grounding',
        burdenLevel: _asInt(json['burden_level'], 1),
        estimatedMinutes: _asInt(json['estimated_minutes'], 3),
        rewardExp: _asInt(json['reward_exp'], 20),
        rewardSeeds: _asInt(json['reward_seeds'], 5),
      );
}

/// 특정 사용자에게 오늘 배정된 퀘스트.
class DailyQuest {
  const DailyQuest({
    required this.id,
    required this.questDate,
    required this.status,
    required this.quest,
    this.completedAt,
  });

  final int id;
  final String questDate;
  final DailyQuestStatus status;
  final DateTime? completedAt;
  final QuestDefinition quest;

  bool get canComplete => status == DailyQuestStatus.assigned;

  DailyQuest copyWith({
    DailyQuestStatus? status,
    DateTime? completedAt,
  }) =>
      DailyQuest(
        id: id,
        questDate: questDate,
        status: status ?? this.status,
        completedAt: completedAt ?? this.completedAt,
        quest: quest,
      );

  factory DailyQuest.fromJson(Map<String, dynamic> json) {
    final questJson = json['quest'];
    return DailyQuest(
      id: _asInt(json['id']),
      questDate: (json['quest_date'] as String?) ?? '',
      status: dailyQuestStatusFromJson(json['status']),
      completedAt: json['completed_at'] is String
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
      quest: QuestDefinition.fromJson(
        questJson is Map<String, dynamic> ? questJson : json,
      ),
    );
  }
}

/// 오늘의 행동이 장기 수집 목표에 어디까지 이어졌는지 보여 주는 다음 해금.
class JourneyUnlock {
  const JourneyUnlock({
    required this.itemId,
    required this.code,
    required this.name,
    required this.itemType,
    required this.acquisitionType,
    required this.label,
    required this.current,
    required this.target,
    required this.eligible,
  });

  final int itemId;
  final String code;
  final String name;
  final String itemType;
  final String acquisitionType;
  final String label;
  final int current;
  final int target;
  final bool eligible;

  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0, 1).toDouble();

  String get progressLabel => eligible ? '지금 해금 가능' : '$current / $target';

  String get typeLabel => switch (itemType) {
        'room_theme' => '방 테마',
        'main_character' => '성장 씨앗',
        'companion' => '동행 친구',
        'deco' => '꾸미기',
        'species_unlock' => '성장 씨앗',
        _ => '컬렉션',
      };

  factory JourneyUnlock.fromJson(Map<String, dynamic> json) => JourneyUnlock(
        itemId: _asInt(json['item_id']),
        code: (json['code'] as String?) ?? '',
        name: (json['name'] as String?) ?? '다음 컬렉션',
        itemType: (json['item_type'] as String?) ?? '',
        acquisitionType: (json['acquisition_type'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        current: _asInt(json['current']),
        target: _asInt(json['target']),
        eligible: (json['eligible'] as bool?) ?? false,
      );
}

/// 하루·이번 주·전체 누적을 같은 문맥에서 보여 주는 가벼운 진행 요약.
class JourneyProgress {
  const JourneyProgress({
    this.recordedDayCount = 0,
    this.completedQuestCount = 0,
    this.weeklyRecordedDays = 0,
    this.weeklyCompletedQuests = 0,
    this.nextUnlock,
  });

  final int recordedDayCount;
  final int completedQuestCount;
  final int weeklyRecordedDays;
  final int weeklyCompletedQuests;
  final JourneyUnlock? nextUnlock;

  factory JourneyProgress.fromJson(Object? value) {
    final json =
        value is Map<String, dynamic> ? value : const <String, dynamic>{};
    final unlock = json['next_unlock'];
    return JourneyProgress(
      recordedDayCount: _asInt(json['recorded_day_count']),
      completedQuestCount: _asInt(json['completed_quest_count']),
      weeklyRecordedDays: _asInt(json['weekly_recorded_days']),
      weeklyCompletedQuests: _asInt(json['weekly_completed_quests']),
      nextUnlock: unlock is Map<String, dynamic>
          ? JourneyUnlock.fromJson(unlock)
          : null,
    );
  }
}

class DailyQuestFeed {
  const DailyQuestFeed({
    required this.date,
    required this.suspended,
    required this.items,
    this.suspensionReason,
    this.contextStatus = 'neutral',
    this.contextEmotion,
    this.journey = const JourneyProgress(),
  });

  final String date;
  final bool suspended;
  final String? suspensionReason;
  final String contextStatus;
  final String? contextEmotion;
  final List<DailyQuest> items;
  final JourneyProgress journey;

  String? get contextEmotionLabel {
    final emotion = contextEmotion?.trim();
    if (emotion == null || emotion.isEmpty) return null;
    return switch (emotion) {
      'joy' => '기쁨',
      'sadness' => '슬픔',
      'anger' => '분노',
      'anxiety' => '불안',
      'surprise' => '놀람',
      'mixed' => '복합적인 마음',
      _ => emotion,
    };
  }

  String get contextTitle => switch (contextStatus) {
        'diary_matched' when contextEmotionLabel != null =>
          '오늘 일기에서 읽힌 ${contextEmotionLabel!}',
        'analyzing' => '식물이 오늘 마음을 읽는 중',
        'record_optional' => '이야기 뒤에 이어지는 선택',
        _ => '오늘의 작은 행동',
      };

  String get contextDescription => switch (contextStatus) {
        'diary_matched' => '이 마음을 평가하지 않고, 부담 적은 행동과 연결했어요.',
        'analyzing' => '분석이 끝나면 완료 전 퀘스트를 오늘의 마음과 다시 연결해요.',
        'record_optional' => '먼저 이야기를 남기면 오늘의 마음과 어울리는 행동을 골라요.',
        _ => '완료해도, 건너뛰어도 연속 기록에는 영향이 없어요.',
      };

  DailyQuest? get nextAssigned {
    for (final item in items) {
      if (item.status == DailyQuestStatus.assigned) return item;
    }
    return null;
  }

  bool get allFinished => items.isNotEmpty && nextAssigned == null;

  DailyQuestFeed replace(
    DailyQuest updated, {
    JourneyProgress? journey,
  }) =>
      DailyQuestFeed(
        date: date,
        suspended: suspended,
        suspensionReason: suspensionReason,
        contextStatus: contextStatus,
        contextEmotion: contextEmotion,
        journey: journey ?? this.journey,
        items: [
          for (final item in items) item.id == updated.id ? updated : item,
        ],
      );

  factory DailyQuestFeed.fromJson(Map<String, dynamic> json) => DailyQuestFeed(
        date: (json['date'] as String?) ?? '',
        suspended: (json['suspended'] as bool?) ?? false,
        suspensionReason: json['suspension_reason'] as String?,
        contextStatus: (json['context_status'] as String?) ?? 'neutral',
        contextEmotion: json['context_emotion'] as String?,
        journey: JourneyProgress.fromJson(json['journey']),
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DailyQuest.fromJson)
            .toList(),
      );
}

class QuestCompletionResult {
  const QuestCompletionResult({
    required this.userQuest,
    this.reward,
    this.journey = const JourneyProgress(),
  });

  final DailyQuest userQuest;
  final RewardResult? reward;
  final JourneyProgress journey;

  factory QuestCompletionResult.fromJson(Map<String, dynamic> json) =>
      QuestCompletionResult(
        userQuest: DailyQuest.fromJson(
          (json['user_quest'] as Map<String, dynamic>?) ?? const {},
        ),
        reward: RewardResult.fromJsonOrNull(json['reward']),
        journey: JourneyProgress.fromJson(json['journey']),
      );
}
