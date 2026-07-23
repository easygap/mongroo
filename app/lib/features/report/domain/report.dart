/// api.md Report DTO와 하위 통계 구조.
/// 모든 bucket이 entry_ids를 들고 있어 차트에서 원 기록으로 내려갈 수 있다.
class MoodDailyPoint {
  const MoodDailyPoint({
    required this.date,
    required this.avgMood,
    required this.count,
    required this.entryIds,
  });

  final String date;
  final double avgMood;
  final int count;
  final List<int> entryIds;

  factory MoodDailyPoint.fromJson(Map<String, dynamic> json) => MoodDailyPoint(
        date: (json['date'] as String?) ?? '',
        avgMood: ((json['avg_mood'] as num?) ?? 0).toDouble(),
        count: (json['count'] as int?) ?? 0,
        entryIds: _ids(json['entry_ids']),
      );
}

class TagCount {
  const TagCount(
      {required this.tag, required this.count, required this.entryIds});

  final String tag;
  final int count;
  final List<int> entryIds;

  factory TagCount.fromJson(Map<String, dynamic> json) => TagCount(
        tag: (json['tag'] as String?) ?? '',
        count: (json['count'] as int?) ?? 0,
        entryIds: _ids(json['entry_ids']),
      );
}

class AiEmotionCount {
  const AiEmotionCount(
      {required this.emotion, required this.count, required this.entryIds});

  final String emotion;
  final int count;
  final List<int> entryIds;

  factory AiEmotionCount.fromJson(Map<String, dynamic> json) => AiEmotionCount(
        emotion: (json['emotion'] as String?) ?? '',
        count: (json['count'] as int?) ?? 0,
        entryIds: _ids(json['entry_ids']),
      );
}

class TimeOfDayCount {
  const TimeOfDayCount(
      {required this.bucket, required this.count, required this.entryIds});

  final String bucket; // morning | afternoon | evening | night
  final int count;
  final List<int> entryIds;

  static const bucketLabels = {
    'morning': '아침',
    'afternoon': '오후',
    'evening': '저녁',
    'night': '밤',
  };

  String get label => bucketLabels[bucket] ?? bucket;

  factory TimeOfDayCount.fromJson(Map<String, dynamic> json) => TimeOfDayCount(
        bucket: (json['bucket'] as String?) ?? '',
        count: (json['count'] as int?) ?? 0,
        entryIds: _ids(json['entry_ids']),
      );
}

class StreakStat {
  const StreakStat({required this.current, required this.longestInPeriod});

  final int current;
  final int longestInPeriod;

  factory StreakStat.fromJson(Map<String, dynamic> json) => StreakStat(
        current: (json['current'] as int?) ?? 0,
        longestInPeriod: (json['longest_in_period'] as int?) ?? 0,
      );
}

class KeywordStat {
  const KeywordStat(
      {required this.keyword, required this.score, required this.entryIds});

  final String keyword;
  final double score;
  final List<int> entryIds;

  factory KeywordStat.fromJson(Map<String, dynamic> json) => KeywordStat(
        keyword: (json['keyword'] as String?) ?? '',
        score: ((json['score'] as num?) ?? 0).toDouble(),
        entryIds: _ids(json['entry_ids']),
      );
}

class ReportStats {
  const ReportStats({
    required this.totalEntries,
    required this.entriesWithText,
    required this.analyzedEntries,
    required this.moodDaily,
    required this.tagDistribution,
    required this.aiEmotionDistribution,
    required this.timeOfDay,
    required this.streak,
    required this.keywords,
    this.explicitMoodEntries = -1,
  });

  final int totalEntries;
  final int entriesWithText;
  final int analyzedEntries;
  final List<MoodDailyPoint> moodDaily;
  final List<TagCount> tagDistribution;
  final List<AiEmotionCount> aiEmotionDistribution;
  final List<TimeOfDayCount> timeOfDay;
  final StreakStat streak;
  final List<KeywordStat> keywords;
  final int explicitMoodEntries;

  bool get hasExplicitMoodEntries =>
      explicitMoodEntries > 0 ||
      (explicitMoodEntries < 0 && moodDaily.isNotEmpty);

  factory ReportStats.fromJson(Map<String, dynamic> json) => ReportStats(
        totalEntries: (json['total_entries'] as int?) ?? 0,
        entriesWithText: (json['entries_with_text'] as int?) ?? 0,
        analyzedEntries: (json['analyzed_entries'] as int?) ?? 0,
        explicitMoodEntries:
            (json['explicit_mood_entries'] as num?)?.toInt() ?? -1,
        moodDaily: _list(json['mood_daily'], MoodDailyPoint.fromJson),
        tagDistribution: _list(json['tag_distribution'], TagCount.fromJson),
        aiEmotionDistribution:
            _list(json['ai_emotion_distribution'], AiEmotionCount.fromJson),
        timeOfDay: _list(json['time_of_day'], TimeOfDayCount.fromJson),
        streak: json['streak'] is Map<String, dynamic>
            ? StreakStat.fromJson(json['streak'] as Map<String, dynamic>)
            : const StreakStat(current: 0, longestInPeriod: 0),
        keywords: _list(json['keywords'], KeywordStat.fromJson),
      );
}

class ReportSummary {
  const ReportSummary({
    required this.overview,
    required this.patterns,
    required this.reflectionQuestions,
  });

  final String overview;
  final List<String> patterns;
  final List<String> reflectionQuestions;

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
        overview: (json['overview'] as String?) ?? '',
        patterns: ((json['patterns'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .toList(),
        reflectionQuestions:
            ((json['reflection_questions'] as List<dynamic>?) ?? const [])
                .whereType<String>()
                .toList(),
      );
}

class Report {
  const Report({
    required this.id,
    required this.periodType,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.stats,
    required this.analysisCoverage,
    required this.summary,
    required this.summaryModelVersion,
    required this.errorCode,
  });

  final int id;
  final String periodType; // weekly | monthly
  final String periodStart;
  final String periodEnd;
  final String status; // pending | succeeded | failed
  final ReportStats? stats;
  final double? analysisCoverage;
  final ReportSummary? summary;
  final String? summaryModelVersion;
  final String? errorCode;

  bool get summaryPending => status == 'pending';
  bool get summaryFailed => status == 'failed';

  factory Report.fromJson(Map<String, dynamic> json) => Report(
        id: json['id'] as int,
        periodType: (json['period_type'] as String?) ?? 'weekly',
        periodStart: (json['period_start'] as String?) ?? '',
        periodEnd: (json['period_end'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'pending',
        stats: json['stats'] is Map<String, dynamic>
            ? ReportStats.fromJson(json['stats'] as Map<String, dynamic>)
            : null,
        analysisCoverage: (json['analysis_coverage'] as num?)?.toDouble(),
        summary: json['summary'] is Map<String, dynamic>
            ? ReportSummary.fromJson(json['summary'] as Map<String, dynamic>)
            : null,
        summaryModelVersion: json['summary_model_version'] as String?,
        errorCode: json['error_code'] as String?,
      );
}

List<int> _ids(Object? raw) =>
    ((raw as List<dynamic>?) ?? const []).whereType<int>().toList();

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) fromJson) =>
    ((raw as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
