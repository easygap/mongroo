import 'dart:ui' show SemanticsAction;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/report/domain/report.dart';
import 'package:mongroo/features/report/presentation/report_charts.dart';

void main() {
  Future<void> pumpChart(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('감정 분포 행은 48px 조작 영역과 기록 이동 의미를 제공한다', (tester) async {
    var tapped = false;
    final semantics = tester.ensureSemantics();

    await pumpChart(
      tester,
      DistributionBarRow(
        label: '기쁨',
        count: 3,
        maxCount: 4,
        color: AppTheme.seed,
        onTap: () => tapped = true,
      ),
    );

    final row = find.bySemanticsLabel('기쁨, 기록 3건, 기록 보기');
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));

    await tester.tap(row);
    await tester.pump();
    expect(tapped, isTrue);

    semantics.dispose();
  });

  testWidgets('기분 추세는 날짜별 접근 버튼으로 같은 원본 항목을 전달한다', (tester) async {
    const first = MoodDailyPoint(
      date: '2026-07-13',
      avgMood: 4.0,
      count: 2,
      entryIds: [11, 12],
    );
    const second = MoodDailyPoint(
      date: '2026-07-14',
      avgMood: 3.5,
      count: 1,
      entryIds: [13],
    );
    MoodDailyPoint? selected;
    final semantics = tester.ensureSemantics();

    await pumpChart(
      tester,
      MoodTrendChart(
        points: const [first, second],
        onPointTap: (point) => selected = point,
      ),
    );

    expect(tester.widget<LineChart>(find.byType(LineChart)).duration,
        Duration.zero);
    final day = find.bySemanticsLabel(
      '7월 14일, 평균 기분 3.5, 기록 1건, 기록 보기',
    );
    expect(day, findsOneWidget);

    await tester.tap(day);
    await tester.pump();
    expect(selected, same(second));

    semantics.dispose();
  });

  testWidgets('시간대 스탬프는 빈 구간을 비활성화하고 기록 구간만 연다', (tester) async {
    const morning = TimeOfDayCount(
      bucket: 'morning',
      count: 2,
      entryIds: [21, 22],
    );
    TimeOfDayCount? selected;
    final semantics = tester.ensureSemantics();

    await pumpChart(
      tester,
      TimeOfDayChart(
        buckets: const [morning],
        onBucketTap: (bucket) => selected = bucket,
      ),
    );

    expect(
      tester.widget<BarChart>(find.byType(BarChart)).duration,
      Duration.zero,
    );
    final emptyNight = find.bySemanticsLabel('밤, 기록 없음');
    expect(emptyNight, findsOneWidget);
    expect(
      tester
          .getSemantics(emptyNight)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );

    await tester.tap(find.bySemanticsLabel('아침, 기록 2건, 기록 보기'));
    await tester.pump();
    expect(selected, same(morning));

    semantics.dispose();
  });
}
