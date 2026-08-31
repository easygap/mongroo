import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tap_target.dart';
import 'package:go_router/go_router.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/mood/presentation/mood_entries_by_ids_screen.dart';
import 'package:mongroo/features/report/data/report_repository.dart';
import 'package:mongroo/features/report/domain/report.dart';
import 'package:mongroo/features/report/presentation/report_screen.dart';

class _ReportRepository extends ReportRepository {
  _ReportRepository(this.report) : super(Dio());

  final Report report;

  @override
  Future<Report> create({
    required String periodType,
    required String periodStart,
    required String idempotencyKey,
  }) async =>
      report;

  @override
  Future<Report> getById(int id) async => report;
}

const _report = Report(
  id: 7,
  periodType: 'weekly',
  periodStart: '2026-07-13',
  periodEnd: '2026-07-19',
  status: 'succeeded',
  stats: ReportStats(
    totalEntries: 4,
    entriesWithText: 3,
    analyzedEntries: 2,
    moodDaily: [
      MoodDailyPoint(
        date: '2026-07-13',
        avgMood: 4,
        count: 2,
        entryIds: [11, 12],
      ),
      MoodDailyPoint(
        date: '2026-07-14',
        avgMood: 3,
        count: 2,
        entryIds: [13, 14],
      ),
    ],
    tagDistribution: [
      TagCount(tag: '기쁨', count: 3, entryIds: [11, 12, 13]),
    ],
    aiEmotionDistribution: [
      AiEmotionCount(emotion: 'joy', count: 2, entryIds: [11, 13]),
    ],
    timeOfDay: [
      TimeOfDayCount(bucket: 'morning', count: 2, entryIds: [11, 12]),
      TimeOfDayCount(bucket: 'night', count: 2, entryIds: [13, 14]),
    ],
    streak: StreakStat(current: 3, longestInPeriod: 3),
    keywords: [
      KeywordStat(keyword: '산책', score: .8, entryIds: [11, 13]),
    ],
  ),
  analysisCoverage: 2 / 3,
  summary: ReportSummary(
    overview: '아침 기록이 두 번 있었습니다.',
    patterns: ['주 초반의 기분 점수가 높았습니다.'],
    reflectionQuestions: ['산책한 날과 다른 날은 무엇이 달랐나요?'],
  ),
  summaryModelVersion: 'test-model',
  errorCode: null,
);

void main() {
  Future<ValueNotifier<MoodEntriesByIdsArgs?>> pumpReport(
    WidgetTester tester, {
    Size size = const Size(900, 1800),
    double textScale = 1,
  }) async {
    final openedArgs = ValueNotifier<MoodEntriesByIdsArgs?>(null);
    addTearDown(openedArgs.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ReportScreen(),
        ),
        GoRoute(
          path: '/moods/entries',
          builder: (context, state) {
            openedArgs.value = state.extra! as MoodEntriesByIdsArgs;
            return const Scaffold(body: Text('기록 상세 목록'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportRepositoryProvider
              .overrideWithValue(_ReportRepository(_report)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
    expectTapTargets(tester, screen: '회고');
    await tester.pumpAndSettle();
    return openedArgs;
  }

  testWidgets('직접 고른 예전 감정과 일기에서 읽은 감정을 구분한다', (tester) async {
    await pumpReport(tester);
    final semantics = tester.ensureSemantics();

    expect(find.text('마음 회고'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-user-ledger')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-ai-ledger')), findsOneWidget);
    expect(find.text('마음 이야기'), findsOneWidget);
    expect(find.text('예전 기록에서 직접 고른 감정'), findsOneWidget);
    expect(find.text('일기에서 자주 읽힌 마음'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-user-emotions')),
        matching: find.text('기쁨'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-ai-emotions')),
        matching: find.text('기쁨'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('의료 진단이나 치료 권고가 아닙니다.'),
      findsOneWidget,
    );
    expect(find.textContaining('생성 모델 · test-model'), findsOneWidget);
    expect(
      find.bySemanticsLabel('직접 선택한 감정, 기쁨, 기록 3건, 기록 보기'),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('감정 분포 선택은 기존 제목과 기록 ID로 드릴다운한다', (tester) async {
    final openedArgs = await pumpReport(tester);
    final semantics = tester.ensureSemantics();

    await tester.tap(
      find.bySemanticsLabel('직접 선택한 감정, 기쁨, 기록 3건, 기록 보기'),
    );
    await tester.pumpAndSettle();
    expect(find.text('기록 상세 목록'), findsOneWidget);
    expect(openedArgs.value?.title, '태그: 기쁨');
    expect(openedArgs.value?.entryIds, [11, 12, 13]);

    semantics.dispose();
  });

  testWidgets('320px과 200% 글자에서도 기록표를 끝까지 읽을 수 있다', (tester) async {
    await pumpReport(
      tester,
      size: const Size(320, 640),
      textScale: 2,
    );

    expect(find.text('마음 회고'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('이번 기간 한 문장 회고'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('이번 기간 한 문장 회고'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('기간 기록표'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('기간 기록표'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
