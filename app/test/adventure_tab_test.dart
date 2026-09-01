import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tap_target.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/adventure/data/adventure_repository.dart';
import 'package:mongroo/features/adventure/domain/adventure_models.dart';
import 'package:mongroo/features/adventure/presentation/adventure_controller.dart';
import 'package:mongroo/features/adventure/presentation/adventure_tab.dart';

class _AdventureRepository extends AdventureRepository {
  _AdventureRepository(this.value) : super(Dio());

  final AdventureState value;
  int donationCalls = 0;
  int claimCalls = 0;

  @override
  Future<AdventureState> getState() async => value;

  @override
  Future<AdventureActionResult> donateItem({
    required String itemCode,
    required String idempotencyKey,
  }) async {
    donationCalls += 1;
    return AdventureActionResult(state: value, seedBalance: 2);
  }

  @override
  Future<AdventureActionResult> claimPatrol({
    required int patrolId,
    required String idempotencyKey,
  }) async {
    claimCalls += 1;
    return AdventureActionResult(
      state: value,
      outcomeMessage: '첫 새소리의 자리: 수관 사이 쉼터를 찾았어요.\n'
          '모아: “서로 다른 흔적을 모으니 한 장면이 됐어.”',
    );
  }
}

AdventureState _adventureState({
  Map<String, dynamic>? patrol,
  List<Map<String, dynamic>> economy = const [],
}) =>
    AdventureState.fromJson({
      'suspended': false,
      'diary_ready': true,
      'diary_requirement': {'message': '오늘 탐험이 열렸어요.'},
      'economy': economy,
      'weekly_board': {
        'week_start': '2026-08-03',
        'week_end': '2026-08-09',
        'goals': [
          {
            'code': 'diary_3',
            'name': '마음 일기 3일',
            'description': '서로 다른 3일에 마음을 50자 이상 기록해요.',
            'progress': 3,
            'target': 3,
            'reward_exp': 0,
            'reward_seeds': 20,
            'completed': true,
            'claimed': true,
            'can_claim': false,
          },
          {
            'code': 'patrol_3',
            'name': '순찰 귀환 3회',
            'description': '돌아온 순찰 보상을 3번 받아요.',
            'progress': 1,
            'target': 3,
            'reward_exp': 0,
            'reward_seeds': 8,
            'completed': false,
            'claimed': false,
            'can_claim': false,
          },
          {
            'code': 'dungeon_2',
            'name': '던전 탐험 2회',
            'description': '발견한 던전을 2번 탐험해요.',
            'progress': 0,
            'target': 2,
            'reward_exp': 0,
            'reward_seeds': 6,
            'completed': false,
            'claimed': false,
            'can_claim': false,
          },
        ],
      },
      'milestones': {
        'current_title': '마음 기록가',
        'unlocked_count': 1,
        'total_count': 5,
        'items': [
          {
            'code': 'seven_day_diary',
            'name': '일곱 날의 마음',
            'description': '50자 이상 마음 일기를 서로 다른 7일에 남겨요.',
            'progress': 7,
            'target': 7,
            'unlocked': true,
            'title': '마음 기록가',
          },
          {
            'code': 'five_patrol_returns',
            'name': '익숙해진 산책길',
            'description': '캐릭터의 순찰 귀환을 5번 맞이해요.',
            'progress': 3,
            'target': 5,
            'unlocked': false,
            'title': '정원 길잡이',
          },
          {
            'code': 'five_dungeon_runs',
            'name': '문 너머의 기록',
            'description': '발견한 던전을 5번 차분히 탐험해요.',
            'progress': 2,
            'target': 5,
            'unlocked': false,
            'title': '고요한 탐험가',
          },
          {
            'code': 'three_research_projects',
            'name': '세 번째 표본함',
            'description': '서로 다른 표본 연구를 3개 완성해요.',
            'progress': 1,
            'target': 3,
            'unlocked': false,
            'title': '표본 연구가',
          },
          {
            'code': 'outside_greenhouse_atlas',
            'name': '온실 밖 탐험 1장',
            'description': '마음나무 관측실까지의 탐험 지도를 완성해요.',
            'progress': 0,
            'target': 1,
            'unlocked': false,
            'title': '온실 밖 지도지기',
          },
        ],
      },
      'donation': {
        'available_today': true,
        'used_today': false,
        'has_eligible_item': true,
        'required_quantity': 3,
        'reward_exp': 0,
        'reward_seeds': 2,
        'message': '연구에 필요한 수량을 남기고 여분 표본만 기증할 수 있어요.',
      },
      'routes': [
        {
          'code': 'dawn_canopy_walk',
          'name': '새벽 수관 회랑',
          'description': '만개한 온실 위 나무길을 따라가요.',
          'duration_minutes': 40,
          'base_duration_minutes': 40,
          'time_reduction_minutes': 0,
          'required_stage': 5,
          'available': true,
          'recommended_stats': ['돌봄', '용기'],
          'performance_score': 18,
          'projected_quantity': 2,
          'best_match': true,
          'reward': {
            'exp': 0,
            'seeds': 3,
            'item_code': 'dawn_bark_rubbing',
          },
        },
      ],
      'patrol': patrol,
      'dungeons': const <dynamic>[],
      'inventory': [
        {
          'code': 'pressed_leaf_map',
          'name': '눌러 말린 잎 지도',
          'description': '다음 길을 찾을 때 쓰는 얇은 지도 조각',
          'quantity': 6,
          'reserved_quantity': 3,
          'donatable_quantity': 3,
          'can_donate': true,
        },
        {
          'code': 'moon_dew',
          'name': '달빛 이슬',
          'description': '밤의 식물에서만 맺히는 맑은 이슬',
          'quantity': 6,
          'reserved_quantity': 4,
          'donatable_quantity': 2,
          'can_donate': false,
        },
      ],
      'research_projects': const <dynamic>[],
      'research_summary': {
        'completed_count': 1,
        'total_count': 5,
        'chapter_completed': true,
        'chapter_name': '온실 밖 탐험 1장',
      },
      'journal': {
        'discovered_count': 4,
        'total_dungeons': 4,
        'total_clear_count': 7,
        'recent_entries': [
          {
            'kind': 'dungeon',
            'title': '비어 있는 나이테',
            'description':
                '오래된 나이테 한 칸이 비어 있어 지금의 기록을 기다리고 있었어요. · 호흡을 고르고 집중하기 · 심재 씨앗 표본 2개',
            'occurred_at': '2026-08-04T03:00:00Z',
            'location_code': 'heartwood_observatory',
            'item_code': 'heartwood_seed_sample',
            'item_name': '심재 씨앗 표본',
            'quantity': 2,
            'outcome_code': 'resonant',
          },
          {
            'kind': 'patrol',
            'title': '첫 새소리의 자리',
            'description':
                '가장 먼저 울린 새소리를 따라 수관 사이 쉼터를 찾았어요. · 모아 “서로 다른 흔적을 모으니 한 장면이 됐어.” · 새벽 나무결 탁본 2개',
            'occurred_at': '2026-08-04T02:58:00Z',
            'location_code': 'dawn_canopy_walk',
            'item_code': 'dawn_bark_rubbing',
            'item_name': '새벽 나무결 탁본',
            'quantity': 2,
            'outcome_code': null,
          },
        ],
      },
      'story_collection': {
        'collected_count': 2,
        'total_count': 24,
        'completed': false,
        'chapters': [
          {
            'code': 'patrol_memories',
            'name': '순찰에서 주운 장면',
            'description': '온실 밖 네 길에서 발견한 이야기',
            'collected_count': 1,
            'total_count': 12,
            'items': [
              {
                'kind': 'patrol',
                'code': 'first_birdsong',
                'location_code': 'dawn_canopy_walk',
                'location_name': '새벽 수관 회랑',
                'discovered': true,
                'title': '첫 새소리의 자리',
                'text': '수관 사이의 작은 쉼터를 찾았어요.',
                'detail': '모아 “같이 기억하자.”',
                'discovered_at': '2026-08-04T02:58:00Z',
              },
              {
                'kind': 'patrol',
                'code': 'feather_marker',
                'location_code': 'dawn_canopy_walk',
                'location_name': '새벽 수관 회랑',
                'discovered': false,
                'title': null,
                'text': null,
                'detail': null,
                'discovered_at': null,
              },
            ],
          },
          {
            'code': 'dungeon_memories',
            'name': '문 너머에서 만난 장면',
            'description': '네 던전 안쪽에서 마주친 기록',
            'collected_count': 1,
            'total_count': 12,
            'items': [
              {
                'kind': 'dungeon',
                'code': 'blank_growth_ring',
                'location_code': 'heartwood_observatory',
                'location_name': '마음나무 관측실',
                'discovered': true,
                'title': '비어 있는 나이테',
                'text': '지금의 기록을 기다리고 있었어요.',
                'detail': '호흡을 고르고 집중하기 · 성장 공명',
                'discovered_at': '2026-08-04T03:00:00Z',
              },
              {
                'kind': 'dungeon',
                'code': 'root_archive',
                'location_code': 'heartwood_observatory',
                'location_name': '마음나무 관측실',
                'discovered': false,
                'title': null,
                'text': null,
                'detail': null,
                'discovered_at': null,
              },
            ],
          },
        ],
      },
    });

void main() {
  testWidgets('좁은 화면과 큰 글자에서도 최근 탐험 기록을 읽을 수 있다', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _AdventureRepository(_adventureState());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adventureRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const Scaffold(body: AdventureTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectTapTargets(tester, screen: '모험 탭');

    await tester.scrollUntilVisible(
      find.text('이번 주 탐험 약속'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('씨앗 +20'), findsOneWidget);
    expect(find.text('받기 완료'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('오늘 잘 맞는 길'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('수집 예상 ×2'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('탐험 기록장'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('장소 발견 4/4'), findsOneWidget);
    // 구버전 던전은 이름으로 직접 탐험과 갈라 둔다. 두 활동이 같은 화면에
    // 서 있어서 `던전`만으로는 어느 쪽인지 읽히지 않았다.
    expect(find.text('발견한 던전 7회'), findsOneWidget);
    expect(find.text('비어 있는 나이테'), findsOneWidget);
    expect(find.textContaining('오래된 나이테 한 칸이 비어 있어'), findsOneWidget);
    expect(find.text('성장 공명'), findsOneWidget);
    expect(find.text('첫 새소리의 자리'), findsOneWidget);
    expect(
      find.textContaining('가장 먼저 울린 새소리를 따라'),
      findsOneWidget,
    );
    expect(find.textContaining('모아 “서로 다른 흔적을 모으니'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('탐험 이야기 도감'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('이야기 2/24'), findsOneWidget);
    expect(find.text('순찰에서 주운 장면'), findsOneWidget);
    expect(find.text('문 너머에서 만난 장면'), findsOneWidget);
    await tester.tap(find.text('순찰에서 주운 장면'));
    await tester.pumpAndSettle();
    expect(find.text('첫 새소리의 자리'), findsWidgets);
    expect(find.text('새벽 수관 회랑의 미발견 장면'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('쌓여 가는 탐험 발자국'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('현재 칭호'), findsOneWidget);
    expect(find.text('마음 기록가'), findsWidgets);
    expect(find.text('칭호 1/5 · 씨앗과 XP는 따로 지급하지 않아요.'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('탐험 수집함'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('온실 표본 기증 · 3개 → 씨앗 2개'), findsOneWidget);
    expect(find.text('연구 보관 3'), findsOneWidget);
    expect(find.text('기증 가능 3'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('여분 표본 3개 기증'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('여분 표본 3개 기증'));
    await tester.pumpAndSettle();
    expect(find.text('눌러 말린 잎 지도 기증'), findsOneWidget);
    expect(find.text('여분만 기증'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repository.donationCalls, 0);

    await tester.tap(find.text('여분 표본 3개 기증'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('여분만 기증'));
    await tester.pumpAndSettle();
    expect(repository.donationCalls, 1);
    expect(find.text('눌러 말린 잎 지도 기증'), findsNothing);
  });

  testWidgets('순찰 귀환 때 발견 이야기와 성장 결 반응을 함께 보여 준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _AdventureRepository(
      _adventureState(
        patrol: {
          'id': 37,
          'route_name': '새벽 수관 회랑',
          'status': 'active',
          'returns_at': '2026-08-04T00:00:00Z',
          'ready_to_claim': true,
          'performance_score': 18,
        },
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adventureRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AdventureTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('돌아온 순찰 확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('돌아온 순찰 확인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(repository.claimCalls, 1);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdventureTab)),
    );
    expect(
      container.read(adventureControllerProvider).actionMessage,
      contains('첫 새소리의 자리:'),
    );
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('첫 새소리의 자리:'), findsOneWidget);
    expect(find.textContaining('모아: “서로 다른 흔적을 모으니'), findsOneWidget);
  });

  testWidgets('성장 효율 표가 직접 탐험과 발견한 던전을 갈라 보여 준다', (tester) async {
    // 두 활동이 같은 화면에 서 있는데 `던전` 한 줄만 있어서, 탐험을 권하는
    // 자리에서 다른 활동의 숫자를 읽게 되어 있었다.
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _AdventureRepository(
      _adventureState(
        economy: const [
          {'code': 'diary', 'label': '마음 일기', 'exp': 40, 'seeds': 15},
          {
            'code': 'expedition',
            'label': '직접 탐험',
            'exp': 6,
            'seeds': 2,
            'exp_max': 10,
            'seeds_max': 5,
          },
          {'code': 'dungeon', 'label': '발견한 던전', 'exp': 10, 'seeds': 4},
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adventureRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AdventureTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('직접 탐험'), findsOneWidget);
    // 지역마다 달라서 한 값으로 못 적는다. 폭으로 읽어 준다.
    expect(find.text('6~10 XP · 씨앗 2~5'), findsOneWidget);
    // 효율 표의 줄과 아래쪽 구역 제목이 **같은 이름**이다. 그 줄이 어느
    // 활동을 말하는지 화면 안에서 이어진다.
    expect(find.text('발견한 던전'), findsNWidgets(2));
    expect(find.text('10 XP · 씨앗 4'), findsOneWidget);
    // 어느 줄도 그냥 `던전`이라고 하지 않는다.
    expect(find.text('던전'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
