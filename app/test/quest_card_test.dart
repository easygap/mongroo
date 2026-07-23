import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/quest/domain/daily_quest.dart';
import 'package:mongroo/features/quest/presentation/quest_widgets.dart';

void main() {
  const quest = DailyQuest(
    id: 7,
    questDate: '2026-07-14',
    status: DailyQuestStatus.assigned,
    quest: QuestDefinition(
      id: 4,
      code: 'QST_SOUNDTRACK',
      title: '오늘의 배경음 고르기',
      description: '오늘과 어울리는 노래나 소리 하나를 골라 보세요.',
      category: 'expression',
      burdenLevel: 1,
      estimatedMinutes: 3,
      rewardExp: 20,
      rewardSeeds: 5,
    ),
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
    VoidCallback? onComplete,
    VoidCallback? onSkip,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: QuestCard(
              userQuest: quest,
              busy: false,
              onComplete: onComplete ?? () {},
              onSkip: onSkip ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('좁은 화면에서도 임무와 두 선택을 모두 보여 준다', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var completed = 0;
    var skipped = 0;
    await pumpCard(
      tester,
      onComplete: () => completed++,
      onSkip: () => skipped++,
    );

    expect(find.text('오늘의 배경음 고르기'), findsOneWidget);
    expect(find.text('최대 +20 XP'), findsOneWidget);
    expect(find.text('+20 XP'), findsNothing);
    expect(find.text('+5 씨앗'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('완료했어요'));
    await tester.tap(find.text('오늘은 건너뛰기'));
    expect(completed, 1);
    expect(skipped, 1);
  });

  testWidgets('어두운 테마에서도 임무 카드가 그려진다', (tester) async {
    await pumpCard(tester, themeMode: ThemeMode.dark);

    expect(find.text('만들기'), findsOneWidget);
    expect(find.text('3분'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
