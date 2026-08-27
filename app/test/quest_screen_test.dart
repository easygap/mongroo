import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/quest/data/quest_repository.dart';
import 'package:mongroo/features/quest/domain/daily_quest.dart';
import 'package:mongroo/features/quest/presentation/quest_screen.dart';

const _assigned = DailyQuest(
  id: 7,
  questDate: '2026-07-16',
  status: DailyQuestStatus.assigned,
  quest: QuestDefinition(
    id: 3,
    code: 'QST_WINDOW_LIGHT',
    title: '창가의 빛 3분 보기',
    description: '편한 곳에서 빛과 그림자의 모양을 잠깐 바라봐요.',
    category: 'senses',
    burdenLevel: 1,
    estimatedMinutes: 3,
    rewardExp: 20,
    rewardSeeds: 5,
  ),
);

class _QuestRepository extends QuestRepository {
  _QuestRepository() : super(Dio());

  int completeCalls = 0;
  int skipCalls = 0;

  @override
  Future<DailyQuestFeed> getToday() async => const DailyQuestFeed(
        date: '2026-07-16',
        suspended: false,
        contextStatus: 'record_optional',
        items: [_assigned],
      );

  @override
  Future<QuestCompletionResult> complete({
    required int userQuestId,
    required String idempotencyKey,
  }) async {
    completeCalls++;
    return QuestCompletionResult(
      userQuest: _assigned.copyWith(status: DailyQuestStatus.completed),
    );
  }

  @override
  Future<DailyQuest> skip(int userQuestId) async {
    skipCalls++;
    return _assigned.copyWith(status: DailyQuestStatus.skipped);
  }
}

Future<(_QuestRepository, GoRouter)> _pumpScreen(
  WidgetTester tester,
) async {
  final repository = _QuestRepository();
  final router = GoRouter(
    initialLocation: '/quests',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('홈 화면')),
      ),
      GoRoute(
        path: '/record',
        builder: (_, __) => const Scaffold(body: Text('기록 화면')),
      ),
      GoRoute(
        path: '/quests',
        builder: (_, __) => const QuestScreen(),
      ),
      GoRoute(
        path: '/garden',
        builder: (_, __) => const Scaffold(body: Text('정원 화면')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        questRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, router);
}

void main() {
  testWidgets('기록이 없으면 작은 행동 문맥에서 기록 화면으로 바로 이어진다', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('오늘 이야기 남기기'), findsOneWidget);
    await tester.tap(find.text('오늘 이야기 남기기'));
    await tester.pumpAndSettle();

    expect(find.text('기록 화면'), findsOneWidget);
  });

  testWidgets('완료는 중복 확인 없이 보상 결과로 바로 이어진다', (tester) async {
    final (repository, _) = await _pumpScreen(tester);

    await tester.tap(find.text('완료했어요'));
    await tester.pumpAndSettle();

    expect(repository.completeCalls, 1);
    expect(find.text('작은 행동을 마쳤나요?'), findsNothing);
    expect(find.text('작은 행동 완료!'), findsOneWidget);
  });

  testWidgets('건너뛰기는 불이익을 설명하고 쉼 상태를 구분한다', (tester) async {
    final (repository, _) = await _pumpScreen(tester);

    await tester.tap(find.text('오늘은 건너뛰기'));
    await tester.pumpAndSettle();
    expect(find.text('건너뛰어도 기록, 성장, 연속 일수에는 불이익이 없어요.'), findsOneWidget);

    await tester.tap(find.text('오늘은 쉬기'));
    await tester.pumpAndSettle();
    expect(repository.skipCalls, 1);
    expect(find.textContaining('오늘은 쉬어 가기로 했어요.'), findsOneWidget);
  });

  testWidgets('직접 주소로 열어도 뒤로가기가 홈으로 복귀한다', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('홈 화면'), findsOneWidget);
  });
}
