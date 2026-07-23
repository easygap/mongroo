import 'package:flutter/material.dart';

/// 구 기록에 사용자가 명시한 기분 5단계 표기.
///
/// 좋고 나쁨으로 감정을 평가하지 않고, 사용자가 오늘 마음에 가까운 풍경을
/// 고를 수 있도록 날씨에 빗대어 표현한다. 숫자 값은 서버 호환용일 뿐 UI에서
/// 점수나 등급으로 노출하지 않는다.
const Map<int, String> moodLevelNames = {
  1: '비 내림',
  2: '구름 낌',
  3: '잔잔함',
  4: '햇살 남',
  5: '반짝임',
};

/// 캘린더 점·기록 카드에 함께 쓰는 기분 색.
const Map<int, Color> moodLevelColors = {
  1: Color(0xFF5F5874),
  2: Color(0xFF657A7E),
  3: Color(0xFF92703E),
  4: Color(0xFF4E745E),
  5: Color(0xFFAA4E3E),
};

String moodLevelName(int level) => moodLevelNames[level] ?? '잔잔함';

Color moodLevelColor(int level) =>
    moodLevelColors[level] ?? moodLevelColors[3]!;

/// 색을 구분하기 어려운 환경에서도 기분 풍경을 알아볼 수 있게 하는 보조 아이콘.
IconData moodLevelIcon(int level) => switch (level) {
      1 => Icons.water_drop_outlined,
      2 => Icons.cloud_outlined,
      3 => Icons.air_rounded,
      4 => Icons.wb_sunny_outlined,
      5 => Icons.auto_awesome_outlined,
      _ => Icons.air_rounded,
    };

/// 기본 감정 태그 후보. 직접 입력으로 추가할 수 있다.
const List<String> presetEmotionTags = [
  '기쁨',
  '설렘',
  '뿌듯함',
  '평온',
  '감사',
  '피곤함',
  '우울함',
  '불안',
  '짜증',
  '외로움',
];

/// analysis_status를 사용자 문구로 바꾼다.
String? analysisStatusLabel(String status) {
  switch (status) {
    case 'pending':
    case 'running':
    case 'waiting_dependency':
      return '일기에서 마음을 읽는 중';
    case 'failed':
      return '이 기록의 마음은 읽지 못했어요';
    default:
      return null; // not_requested, succeeded는 별도 표기 없음
  }
}

String diaryEmotionName(String? value) => switch (value?.toLowerCase()) {
      'joy' || 'happy' || 'happiness' => '기쁨',
      'sad' || 'sadness' || 'hurt' || '상처' => '슬픔·상처',
      'anger' || 'angry' => '화남',
      'anxiety' || 'anxious' || 'fear' => '불안',
      'surprise' ||
      'surprised' ||
      'embarrassment' ||
      'flustered' ||
      '당황' =>
        '놀람·당황',
      'mixed' || 'mosaic' || 'uncertain' || 'abstained' => '여러 마음',
      final label? when label.trim().isNotEmpty => label.trim(),
      _ => '아직 읽힌 마음 없음',
    };

String diaryAnalysisDisplayLabel({
  required String status,
  required String? emotion,
  bool hidden = false,
}) {
  if (hidden) return '읽힌 감정 숨김';
  return switch (status) {
    'pending' || 'running' || 'waiting_dependency' => '마음을 읽는 중',
    'succeeded' when emotion != null => diaryEmotionName(emotion),
    'failed' => '이 기록은 읽지 못함',
    _ => '일기 기록',
  };
}

IconData diaryAnalysisIcon(String status, {bool hidden = false}) {
  if (hidden) return Icons.visibility_off_outlined;
  return switch (status) {
    'pending' ||
    'running' ||
    'waiting_dependency' =>
      Icons.hourglass_top_rounded,
    'succeeded' => Icons.auto_awesome_rounded,
    'failed' => Icons.cloud_off_outlined,
    _ => Icons.menu_book_outlined,
  };
}

Color diaryEmotionColor(String? emotion) => switch (emotion?.toLowerCase()) {
      'joy' || 'happy' || 'happiness' => const Color(0xFF9A602B),
      'sad' || 'sadness' || 'hurt' || '상처' => const Color(0xFF4F718F),
      'anger' || 'angry' => const Color(0xFFA84642),
      'anxiety' || 'anxious' || 'fear' => const Color(0xFF655D8E),
      'surprise' ||
      'surprised' ||
      'embarrassment' ||
      'flustered' ||
      '당황' =>
        const Color(0xFF984A72),
      'mixed' ||
      'mosaic' ||
      'uncertain' ||
      'abstained' =>
        const Color(0xFF4D7664),
      _ => const Color(0xFF6257C8),
    };

IconData diaryEmotionIcon(String? emotion) => switch (emotion?.toLowerCase()) {
      'joy' || 'happy' || 'happiness' => Icons.wb_sunny_outlined,
      'sad' || 'sadness' || 'hurt' || '상처' => Icons.water_drop_outlined,
      'anger' || 'angry' => Icons.local_fire_department_outlined,
      'anxiety' || 'anxious' || 'fear' => Icons.nights_stay_outlined,
      'surprise' ||
      'surprised' ||
      'embarrassment' ||
      'flustered' ||
      '당황' =>
        Icons.auto_awesome_rounded,
      'mixed' || 'mosaic' || 'uncertain' || 'abstained' => Icons.spa_outlined,
      _ => Icons.menu_book_outlined,
    };
