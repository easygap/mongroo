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

/// 어두운 테마용 같은 색상의 밝은 변주.
///
/// 위 값들은 종이색 배경에 맞춰 고른 어두운 색이라 검은 배경 위에서는
/// 3:1 언저리까지 떨어진다(비텍스트 대비 하한). 색상은 그대로 두고 밝기만
/// 올려 어두운 테마에서 4.6:1 이상을 확보한다.
const Map<int, Color> moodLevelColorsDark = {
  1: Color(0xFF837B9B),
  2: Color(0xFF6D8488),
  3: Color(0xFF9F7A43),
  4: Color(0xFF5C896F),
  5: Color(0xFFC16555),
};

String moodLevelName(int level) => moodLevelNames[level] ?? '잔잔함';

Color moodLevelColor(int level, {Brightness brightness = Brightness.light}) {
  final palette =
      brightness == Brightness.dark ? moodLevelColorsDark : moodLevelColors;
  return palette[level] ?? palette[3]!;
}

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

/// 서버가 `mood_entries.ai_emotion`에 넣는 라벨을 여섯 갈래 코드로 모은다.
///
/// **분류기는 한국어 라벨을 낸다**(`EMOTION_LABELS = ("기쁨","슬픔","분노",
/// "불안","상처","당황")`). 영어 코드만 알던 시절의 매핑을 그대로 두면
/// 기쁨·슬픔·분노·불안이 전부 미분류로 떨어져서, 달력·기록 목록·기록 상세가
/// 라벨은 「기쁨」이라 적어 놓고 아이콘은 보라색 책을 그린다.
/// 서버 `app/services/plants.py`의 `_EMOTION_ALIASES`와 같은 표를 쓴다.
const Map<String, String> _diaryEmotionAliases = {
  'joy': 'joy',
  'happy': 'joy',
  'happiness': 'joy',
  '기쁨': 'joy',
  '행복': 'joy',
  '즐거움': 'joy',
  'sad': 'sadness',
  'sadness': 'sadness',
  'hurt': 'sadness',
  '슬픔': 'sadness',
  '상처': 'sadness',
  'anger': 'anger',
  'angry': 'anger',
  '분노': 'anger',
  '화남': 'anger',
  'anxiety': 'anxiety',
  'anxious': 'anxiety',
  'fear': 'anxiety',
  '불안': 'anxiety',
  'surprise': 'surprise',
  'surprised': 'surprise',
  'embarrassment': 'surprise',
  'flustered': 'surprise',
  '당황': 'surprise',
  '놀람': 'surprise',
  'mixed': 'mixed',
  'mosaic': 'mixed',
  'uncertain': 'mixed',
  'abstained': 'mixed',
  '혼합': 'mixed',
};

/// 표에 없는 값은 null. 이름은 원문을 살리고 아이콘·색만 중립으로 떨어진다.
String? diaryEmotionCode(String? value) =>
    _diaryEmotionAliases[value?.trim().toLowerCase() ?? ''];

String diaryEmotionName(String? value) {
  final named = switch (diaryEmotionCode(value)) {
    'joy' => '기쁨',
    'sadness' => '슬픔·상처',
    'anger' => '화남',
    'anxiety' => '불안',
    'surprise' => '놀람·당황',
    'mixed' => '여러 마음',
    _ => null,
  };
  if (named != null) return named;
  final raw = value?.trim() ?? '';
  return raw.isEmpty ? '아직 읽힌 마음 없음' : raw;
}

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

/// 마음별 표시 색. 어두운 테마에서는 같은 색상의 밝은 변주를 쓴다.
///
/// 종이색 배경에 맞춘 어두운 값들이라 검은 배경에서는 3.1~3.6:1까지
/// 떨어진다. 달력 칸·기록 카드의 아이콘과 테두리가 전부 이 색이라 어두운
/// 테마에서 마음이 구분되지 않았다.
Color diaryEmotionColor(
  String? emotion, {
  Brightness brightness = Brightness.light,
}) {
  final dark = brightness == Brightness.dark;
  return switch (diaryEmotionCode(emotion)) {
    'joy' => dark ? const Color(0xFFB47032) : const Color(0xFF9A602B),
    'sadness' => dark ? const Color(0xFF5C83A5) : const Color(0xFF4F718F),
    'anger' => dark ? const Color(0xFFC16561) : const Color(0xFFA84642),
    'anxiety' => dark ? const Color(0xFF827BA8) : const Color(0xFF655D8E),
    'surprise' => dark ? const Color(0xFFB4668E) : const Color(0xFF984A72),
    'mixed' => dark ? const Color(0xFF598974) : const Color(0xFF4D7664),
    _ => dark ? const Color(0xFF7D74D1) : const Color(0xFF6257C8),
  };
}

IconData diaryEmotionIcon(String? emotion) =>
    switch (diaryEmotionCode(emotion)) {
      'joy' => Icons.wb_sunny_outlined,
      'sadness' => Icons.water_drop_outlined,
      'anger' => Icons.local_fire_department_outlined,
      'anxiety' => Icons.nights_stay_outlined,
      'surprise' => Icons.auto_awesome_rounded,
      'mixed' => Icons.spa_outlined,
      _ => Icons.menu_book_outlined,
    };

/// 달력 범례가 실제로 찍히는 표시와 같은 순서·아이콘을 쓰도록 하나로 모은다.
const List<({String code, String label})> diaryEmotionLegend = [
  (code: 'joy', label: '기쁨'),
  (code: 'sadness', label: '슬픔·상처'),
  (code: 'anger', label: '화남'),
  (code: 'anxiety', label: '불안'),
  (code: 'surprise', label: '놀람·당황'),
  (code: 'mixed', label: '여러 마음'),
];
