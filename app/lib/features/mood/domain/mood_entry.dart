import '../../home/domain/reward_result.dart';
import '../../safety/domain/safety_action.dart';

/// api.md MoodEntry DTO. 사용자 태그(emotion_tags)가 원본이고
/// ai_emotion은 수정·숨김 가능한 보조 라벨이다.
class MoodEntry {
  const MoodEntry({
    required this.id,
    required this.localDate,
    required this.recordedAt,
    required this.moodLevel,
    this.moodLevelExplicit = true,
    required this.emotionTags,
    required this.content,
    required this.analysisStatus,
    required this.aiEmotion,
    required this.aiScores,
    required this.aiEmotionOverride,
    required this.aiLabelHidden,
    required this.analysisModelVersion,
    required this.analyzedAt,
    required this.createdAt,
    required this.updatedAt,
    this.editVersion,
  });

  final int id;
  final String localDate;
  final DateTime recordedAt;
  final int moodLevel;
  final bool moodLevelExplicit;
  final List<String> emotionTags;
  final String? content;
  final String analysisStatus;
  final String? aiEmotion;
  final Map<String, double> aiScores;
  final String? aiEmotionOverride;
  final bool aiLabelHidden;
  final String? analysisModelVersion;
  final DateTime? analyzedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 서버의 낙관적 편집 토큰. 이전 서버와의 호환을 위해 nullable로 둔다.
  final int? editVersion;

  /// 화면에 보여줄 AI 라벨. 사용자 수정값이 있으면 그것을 우선한다.
  String? get effectiveAiLabel => aiEmotionOverride ?? aiEmotion;

  bool get analysisInProgress =>
      analysisStatus == 'pending' ||
      analysisStatus == 'running' ||
      analysisStatus == 'waiting_dependency';

  factory MoodEntry.fromJson(Map<String, dynamic> json) => MoodEntry(
        id: json['id'] as int,
        localDate: (json['local_date'] as String?) ?? '',
        recordedAt: DateTime.tryParse((json['recorded_at'] as String?) ?? '') ??
            DateTime.now().toUtc(),
        moodLevel: (json['mood_level'] as int?) ?? 3,
        moodLevelExplicit: (json['mood_level_explicit'] as bool?) ?? true,
        emotionTags: ((json['emotion_tags'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .toList(),
        content: json['content'] as String?,
        analysisStatus: (json['analysis_status'] as String?) ?? 'not_requested',
        aiEmotion: json['ai_emotion'] as String?,
        aiScores: ((json['ai_scores'] as Map<String, dynamic>?) ?? const {})
            .map((k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0)),
        aiEmotionOverride: json['ai_emotion_override'] as String?,
        aiLabelHidden: (json['ai_label_hidden'] as bool?) ?? false,
        analysisModelVersion: json['analysis_model_version'] as String?,
        analyzedAt: json['analyzed_at'] == null
            ? null
            : DateTime.tryParse(json['analyzed_at'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.tryParse(json['updated_at'] as String),
        editVersion: (json['edit_version'] as num?)?.toInt(),
      );
}

/// POST/PATCH /moods 응답 {mood, reward, safety_action}.
class MoodSaveResult {
  const MoodSaveResult({
    required this.mood,
    required this.reward,
    required this.safetyAction,
  });

  final MoodEntry mood;
  final RewardResult? reward;
  final SafetyAction? safetyAction;

  factory MoodSaveResult.fromJson(Map<String, dynamic> json) => MoodSaveResult(
        mood: MoodEntry.fromJson(json['mood'] as Map<String, dynamic>),
        reward: RewardResult.fromJsonOrNull(json['reward']),
        safetyAction: SafetyAction.fromJsonOrNull(json['safety_action']),
      );
}

/// GET /moods/calendar 응답의 일자 집계.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.entryCount,
    this.lastMoodLevel,
    this.lastMoodLevelExplicit = true,
    this.lastAiEmotion,
    this.lastAnalysisStatus = 'not_requested',
    required this.pendingCount,
  });

  final String date;
  final int entryCount;
  final int? lastMoodLevel;
  final bool lastMoodLevelExplicit;
  final String? lastAiEmotion;
  final String lastAnalysisStatus;
  final int pendingCount;

  factory CalendarDay.fromJson(Map<String, dynamic> json) => CalendarDay(
        date: (json['date'] as String?) ?? '',
        entryCount: (json['entry_count'] as int?) ?? 0,
        lastMoodLevel: (json['last_mood_level'] as num?)?.toInt(),
        lastMoodLevelExplicit: (json['last_mood_level_explicit'] as bool?) ??
            json['last_mood_level'] != null,
        lastAiEmotion: json['last_ai_emotion'] as String?,
        lastAnalysisStatus:
            (json['last_analysis_status'] as String?) ?? 'not_requested',
        pendingCount: (json['pending_count'] as int?) ?? 0,
      );
}

class MoodCalendar {
  const MoodCalendar({
    required this.year,
    required this.month,
    required this.days,
  });

  final int year;
  final int month;
  final Map<String, CalendarDay> days;

  factory MoodCalendar.fromJson(Map<String, dynamic> json) {
    final days = <String, CalendarDay>{};
    for (final raw in (json['days'] as List<dynamic>?) ?? const []) {
      if (raw is Map<String, dynamic>) {
        final day = CalendarDay.fromJson(raw);
        days[day.date] = day;
      }
    }
    return MoodCalendar(
      year: (json['year'] as int?) ?? 0,
      month: (json['month'] as int?) ?? 0,
      days: days,
    );
  }
}
