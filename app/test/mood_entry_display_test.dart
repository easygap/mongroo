import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/mood/domain/mood_entry.dart';
import 'package:mongroo/features/mood/presentation/mood_entry_tile.dart';
import 'package:mongroo/features/mood/presentation/mood_style.dart';

MoodEntry _entry({
  String status = 'succeeded',
  String? emotion = 'joy',
  bool hidden = false,
}) =>
    MoodEntry(
      id: 1,
      localDate: '2026-07-14',
      recordedAt: DateTime.utc(2026, 7, 14, 3),
      moodLevel: 3,
      moodLevelExplicit: false,
      emotionTags: const [],
      content: '오늘의 일기',
      analysisStatus: status,
      aiEmotion: emotion,
      aiScores: const {},
      aiEmotionOverride: null,
      aiLabelHidden: hidden,
      analysisModelVersion: null,
      analyzedAt: null,
      createdAt: null,
      updatedAt: null,
    );

void main() {
  testWidgets('content-only 일기는 중립 mood level 대신 글에서 읽은 감정을 보여 준다',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: MoodEntryTile(entry: _entry())),
      ),
    );

    expect(find.textContaining('기쁨'), findsOneWidget);
    expect(find.textContaining('잔잔함'), findsNothing);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
  });

  testWidgets('분석 중·숨김 상태는 감정 아이콘으로 오해하지 않게 별도 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              MoodEntryTile(entry: _entry(status: 'pending', emotion: null)),
              MoodEntryTile(entry: _entry(hidden: true)),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('마음을 읽는 중'), findsOneWidget);
    expect(find.textContaining('읽힌 감정 숨김'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.textContaining('잔잔함'), findsNothing);
  });

  test('calendar content-only 계약과 classifier abstention을 사용자 문구로 읽는다', () {
    final day = CalendarDay.fromJson({
      'date': '2026-07-14',
      'entry_count': 2,
      'last_mood_level': null,
      'last_mood_level_explicit': false,
      'last_ai_emotion': 'uncertain',
      'last_analysis_status': 'succeeded',
      'pending_count': 0,
    });

    expect(day.lastMoodLevel, isNull);
    expect(day.lastMoodLevelExplicit, isFalse);
    expect(day.lastAiEmotion, 'uncertain');
    expect(diaryEmotionName(day.lastAiEmotion), '여러 마음');
    expect(diaryEmotionName('hurt'), '슬픔·상처');
    expect(diaryEmotionName('embarrassment'), '놀람·당황');
  });

  test('분류기가 내는 한글 라벨도 여섯 갈래 표시로 이어진다', () {
    // 서버 `EMOTION_LABELS`는 한국어다. 영어 코드만 알던 매핑에서는
    // 기쁨·슬픔·분노·불안이 전부 미분류 아이콘(책)과 보라색으로 떨어져서
    // 라벨은 「기쁨」인데 그림은 아무 뜻도 없는 상태가 됐다.
    const pairs = {
      '기쁨': 'joy',
      '슬픔': 'sadness',
      '상처': 'sadness',
      '분노': 'anger',
      '불안': 'anxiety',
      '당황': 'surprise',
    };
    for (final entry in pairs.entries) {
      expect(diaryEmotionCode(entry.key), entry.value, reason: entry.key);
      expect(
        diaryEmotionIcon(entry.key),
        diaryEmotionIcon(entry.value),
        reason: entry.key,
      );
      expect(
        diaryEmotionColor(entry.key),
        diaryEmotionColor(entry.value),
        reason: entry.key,
      );
      expect(
        diaryEmotionIcon(entry.key),
        isNot(Icons.menu_book_outlined),
        reason: entry.key,
      );
    }

    // 모르는 라벨은 원문을 살리고 표시만 중립으로 남긴다.
    expect(diaryEmotionCode('무엇'), isNull);
    expect(diaryEmotionName('무엇'), '무엇');
    expect(diaryEmotionIcon('무엇'), Icons.menu_book_outlined);
  });

  test('어두운 테마에서도 마음 표시가 배경과 충분히 갈린다', () {
    // 종이색 배경용으로 고른 어두운 값들이라 검은 배경에서는 3:1 언저리까지
    // 떨어졌다. 달력 칸·기록 카드의 아이콘과 테두리가 전부 이 색이다.
    const darkSurface = Color(0xFF17130F);
    double relativeLuminance(Color color) {
      double channel(double value) => value <= 0.03928
          ? value / 12.92
          : math.pow((value + .055) / 1.055, 2.4).toDouble();
      return .2126 * channel(color.r) +
          .7152 * channel(color.g) +
          .0722 * channel(color.b);
    }

    double contrast(Color a, Color b) {
      final first = relativeLuminance(a);
      final second = relativeLuminance(b);
      final high = math.max(first, second);
      final low = math.min(first, second);
      return (high + .05) / (low + .05);
    }

    for (final emotion in diaryEmotionLegend) {
      final dark = diaryEmotionColor(
        emotion.code,
        brightness: Brightness.dark,
      );
      expect(
        contrast(dark, darkSurface),
        greaterThanOrEqualTo(4.5),
        reason: '${emotion.label}이 어두운 배경에서 묻힙니다',
      );
    }
    for (var level = 1; level <= 5; level++) {
      expect(
        contrast(moodLevelColor(level, brightness: Brightness.dark),
            darkSurface),
        greaterThanOrEqualTo(4.5),
        reason: '$level단계 기분 색이 어두운 배경에서 묻힙니다',
      );
    }

    // 밝은 테마 값은 그대로 둔다.
    expect(
      diaryEmotionColor('기쁨'),
      diaryEmotionColor('joy'),
    );
    expect(
      diaryEmotionColor('기쁨', brightness: Brightness.dark),
      isNot(diaryEmotionColor('기쁨')),
    );
  });

  test('달력 범례의 아이콘과 색이 칸 표시와 같다', () {
    for (final emotion in diaryEmotionLegend) {
      expect(diaryEmotionCode(emotion.code), emotion.code);
      expect(diaryEmotionName(emotion.code), emotion.label);
    }
    // 여섯 갈래가 서로 다른 아이콘을 쓴다 — 범례가 구분에 쓸모 있으려면 필요하다.
    expect(
      diaryEmotionLegend.map((e) => diaryEmotionIcon(e.code)).toSet(),
      hasLength(diaryEmotionLegend.length),
    );
  });
}
