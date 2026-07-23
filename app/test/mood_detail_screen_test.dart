import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/mood/data/mood_repository.dart';
import 'package:mongroo/features/mood/domain/mood_entry.dart';
import 'package:mongroo/features/mood/presentation/mood_detail_screen.dart';

class _DetailMoodRepository implements MoodRepository {
  _DetailMoodRepository(this.entry);

  final MoodEntry entry;
  Map<String, dynamic>? lastPatch;

  @override
  Future<MoodEntry> getById(int id) async => entry;

  @override
  Future<MoodSaveResult> patch(int id, Map<String, dynamic> changes) async {
    lastPatch = Map<String, dynamic>.from(changes);
    return MoodSaveResult(mood: entry, reward: null, safetyAction: null);
  }

  @override
  Future<MoodCalendar> getCalendar({required int year, required int month}) =>
      throw UnimplementedError();

  @override
  Future<List<MoodEntry>> getByDate(String date) => throw UnimplementedError();

  @override
  Future<List<MoodEntry>> getByIds(List<int> ids) => throw UnimplementedError();

  @override
  Future<MoodSaveResult> create({
    required int moodLevel,
    required List<String> emotionTags,
    required String? content,
    required String idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) => throw UnimplementedError();
}

void main() {
  testWidgets('AI 라벨 변경도 현재 편집 버전을 함께 보낸다', (tester) async {
    final entry = MoodEntry(
      id: 9,
      localDate: '2026-07-13',
      recordedAt: DateTime.utc(2026, 7, 13, 3),
      moodLevel: 4,
      emotionTags: const ['기쁨'],
      content: '오늘의 기록',
      analysisStatus: 'succeeded',
      aiEmotion: '기쁨',
      aiScores: const {'기쁨': 0.9},
      aiEmotionOverride: null,
      aiLabelHidden: false,
      analysisModelVersion: 'fake-v1',
      analyzedAt: DateTime.utc(2026, 7, 13, 3, 1),
      createdAt: DateTime.utc(2026, 7, 13, 3),
      updatedAt: DateTime.utc(2026, 7, 13, 3),
      editVersion: 44,
    );
    final repository = _DetailMoodRepository(entry);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [moodRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: MoodDetailScreen(moodId: 9)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('숨기기'));
    await tester.pumpAndSettle();

    expect(repository.lastPatch?['expected_version'], 44);
    expect(repository.lastPatch?['ai_label_hidden'], isTrue);
  });
}
