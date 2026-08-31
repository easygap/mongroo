import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/mood/data/mood_repository.dart';
import 'package:mongroo/features/mood/domain/mood_entry.dart';
import 'package:mongroo/features/mood/presentation/mood_detail_screen.dart';

import 'tap_target.dart';

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

  testWidgets('날짜는 한국어로 적고 태그 칸은 값이 있을 때만 세운다', (tester) async {
    // `local_date`는 API 계약 문자열이다. 그대로 쓰면 이 화면만
    // `2026-07-13`으로 나온다. 태그 칸은 작성 화면에 고르는 자리가 없어서
    // 앱에서 쓴 기록에서는 늘 비어 있었다.
    final tagged = _entry(emotionTags: const ['기쁨']);
    await _pumpDetail(tester, tagged);

    expect(find.textContaining('2026년 7월 13일'), findsOneWidget);
    expect(find.textContaining('2026-07-13'), findsNothing);
    expect(find.text('내 태그'), findsOneWidget);
    expect(find.text('일기'), findsOneWidget);
    expect(find.text('메모'), findsNothing);

    await _pumpDetail(tester, _entry(emotionTags: const []));
    expect(find.text('내 태그'), findsNothing);
    expect(find.text('고른 태그가 없어요.'), findsNothing);
    expect(find.text('오늘의 기록'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 200% 글자에서도 기록과 조작이 넘치지 않는다', (tester) async {
    // 품질 점검표의 기준은 320px·글자 200%인데 이 화면만 그 조건으로 도는
    // 테스트가 없었다. 쓴 글을 다시 읽는 자리라 글자를 키워 보는 사람이
    // 가장 먼저 오는 화면이기도 하다.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moodRepositoryProvider.overrideWithValue(
            _DetailMoodRepository(_entry(emotionTags: const ['기쁨'])),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const MoodDetailScreen(moodId: 9),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘의 기록'), findsOneWidget);
    expectTapTargets(tester, screen: '기록 상세');
    expect(tester.takeException(), isNull);
  });
}

MoodEntry _entry({required List<String> emotionTags}) => MoodEntry(
      id: 9,
      localDate: '2026-07-13',
      recordedAt: DateTime.utc(2026, 7, 13, 3),
      moodLevel: 4,
      emotionTags: emotionTags,
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

Future<void> _pumpDetail(WidgetTester tester, MoodEntry entry) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        moodRepositoryProvider.overrideWithValue(_DetailMoodRepository(entry)),
      ],
      child: const MaterialApp(home: MoodDetailScreen(moodId: 9)),
    ),
  );
  await tester.pumpAndSettle();
}
