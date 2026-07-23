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
}
