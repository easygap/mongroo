import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/data/expedition_repository.dart';
import 'package:mongroo/features/expedition/data/journey_repository.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/domain/journey_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_controller.dart';
import 'package:mongroo/features/expedition/presentation/journey_screen.dart';

import 'tap_target.dart';

Map<String, dynamic> _direction({
  String code = 'beyond_the_well',
  String name = '우물 너머 답사',
  bool locked = false,
  int maxLegs = 2,
}) =>
    {
      'code': code,
      'name': name,
      'summary': '두 구간을 서로 다른 조가 맡아요.',
      'max_legs': maxLegs,
      'party_size': 2,
      'max_own_members': maxLegs * 2,
      'minutes': [16, 24],
      'region_name': '메아리 우물정원',
      'locked': locked,
      'lock_reason': locked ? '메아리 우물정원을 완주하면 열려요.' : null,
    };

Map<String, dynamic> _entry({Map<String, dynamic>? active}) => {
      'content_version': 'journey-v1',
      'unlocked': true,
      'directions': [
        _direction(),
        _direction(
          code: 'starlight_crossing',
          name: '별빛 종단',
          locked: true,
          maxLegs: 3,
        ),
      ],
      'active': active,
    };

Map<String, dynamic> _leg({
  int index = 0,
  String route = '우물 아가리',
  bool secured = true,
  String status = 'completed',
}) =>
    {
      'leg_index': index,
      'run_id': 40 + index,
      'route_code': 'well_mouth',
      'route_name': route,
      'region_code': 'echo_well',
      'region_name': '메아리 우물정원',
      'status': status,
      'objective_secured': secured,
      'party': [
        {'name': '새싹몬', 'is_guide': false, 'plant_id': 11},
        {'name': '기록 안내자', 'is_guide': true, 'plant_id': null},
      ],
      'started_at': null,
      'finished_at': null,
    };

Map<String, dynamic> _journey({
  int currentLegIndex = 0,
  List<Map<String, dynamic>> legs = const [],
  bool atCamp = true,
  bool canContinue = true,
  int? activeRunId,
  String status = 'active',
  List<int> usedPlantIds = const [],
  Map<String, dynamic>? summary,
}) =>
    {
      'id': 3,
      'direction_code': 'beyond_the_well',
      'direction_name': '우물 너머 답사',
      'status': status,
      'mode': 'free_explore',
      'max_legs': 2,
      'current_leg_index': currentLegIndex,
      'revision': 1,
      'reward_eligible': true,
      'deepest_secured_region': legs.isEmpty ? null : 'echo_well',
      'deepest_secured_region_name': legs.isEmpty ? null : '메아리 우물정원',
      'reward_band': legs.isEmpty ? null : {'exp': 7, 'seeds': 2},
      'legs': legs,
      'used_plant_ids': usedPlantIds,
      'max_own_members': 4,
      'party_size': 2,
      'active_run_id': activeRunId,
      'at_camp': atCamp,
      'can_continue': canContinue,
      'next_routes': canContinue
          ? [
              {
                'code': 'well_mouth',
                'name': '우물 아가리',
                'region_code': 'echo_well',
                'hint': '물소리가 제일 크게 도는 쪽이에요.',
              },
              {
                'code': 'mossy_stair',
                'name': '이끼 낀 계단',
                'region_code': 'moss_archive',
                'hint': '서고 뒤편으로 돌아 내려가는 길이에요.',
              },
            ]
          : const [],
      'summary': summary,
    };

class _FakeJourneyRepository implements JourneyRepository {
  _FakeJourneyRepository({required this.entry, this.active});

  Map<String, dynamic> entry;
  Map<String, dynamic>? active;

  String? lastRouteCode;
  List<int>? lastPlantIds;
  int? lastGuideCount;
  int returnCalls = 0;

  @override
  Future<JourneyEntry> getEntry() async => JourneyEntry.fromJson({
        ...entry,
        'active': active,
      });

  @override
  Future<Journey?> getActive() async =>
      active == null ? null : Journey.fromJson(active!);

  @override
  Future<Journey> start({
    required String directionCode,
    required String mode,
    required String idempotencyKey,
  }) async {
    active = _journey();
    return Journey.fromJson(active!);
  }

  @override
  Future<Journey> createLeg({
    required int journeyId,
    required String routeCode,
    required List<int> plantIds,
    required int guideCount,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    lastRouteCode = routeCode;
    lastPlantIds = plantIds;
    lastGuideCount = guideCount;
    active = _journey(activeRunId: 40, canContinue: false);
    return Journey.fromJson(active!);
  }

  @override
  Future<Journey> returnHome({
    required int journeyId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    returnCalls++;
    active = _journey(
      status: 'completed',
      atCamp: false,
      canContinue: false,
      legs: [_leg()],
      summary: {
        'title': '원정 기록을 안고 돌아왔어요',
        'leg_count': 1,
        'secured_count': 1,
        'deepest_region_name': '메아리 우물정원',
        'legs': [_leg()],
        'reward': {
          'events': [
            {'exp_delta': 7, 'seed_delta': 2},
          ],
        },
      },
    );
    return Journey.fromJson(active!);
  }
}

/// 탐험 컨트롤러는 구간을 열고 나서 한 번 다시 읽는다. 여기서는 그 호출이
/// 일어났다는 것만 세고 실제 요청은 하지 않는다 — 개척 화면의 검사가 탐험
/// 카탈로그까지 통째로 흉내 내기 시작하면 무엇을 재는 검사인지 흐려진다.
class _FakeExpeditionController extends ExpeditionController {
  int loadCalls = 0;

  @override
  ExpeditionUiState build() => const ExpeditionUiState(loading: false);

  @override
  Future<void> load() async {
    loadCalls += 1;
  }
}

class _FakeExpeditionRepository implements ExpeditionRepository {
  @override
  Future<List<ExpeditionRosterItem>> getRoster() async => [
        ExpeditionRosterItem.fromJson({
          'plant_id': 11,
          'name': '새싹몬',
          'species': {'code': 'baby-pot', 'name': '아기 화분'},
          'status': 'active',
          'stage': 3,
          'form': 'mosaic',
          'stats': {'care': 5, 'focus': 5, 'courage': 5, 'insight': 5},
          'eligible': true,
        }),
        ExpeditionRosterItem.fromJson({
          'plant_id': 12,
          'name': '둘째',
          'species': {'code': 'ninja-pot', 'name': '닌자 화분'},
          'status': 'harvested',
          'stage': 4,
          'form': 'sunny',
          'stats': {'care': 5, 'focus': 5, 'courage': 5, 'insight': 5},
          'eligible': true,
        }),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<_FakeJourneyRepository> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? active,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = _FakeJourneyRepository(entry: _entry(), active: active);
  final expedition = _FakeExpeditionController();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const JourneyScreen()),
      GoRoute(
        path: '/expedition',
        builder: (context, state) => const Scaffold(body: Text('걷는 화면')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        journeyRepositoryProvider.overrideWithValue(repository),
        expeditionRepositoryProvider.overrideWithValue(
          _FakeExpeditionRepository(),
        ),
        expeditionControllerProvider.overrideWith(() => expedition),
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
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('입구는 잠긴 방향도 이유와 함께 보여 준다', (tester) async {
    await _pump(tester);

    expect(find.text('우물 너머 답사'), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-start-beyond_the_well')),
        findsOneWidget);

    // 잠긴 방향은 숨기지 않는다. 무엇이 기다리는지 알아야 열어 볼 마음이 생긴다.
    expect(find.text('별빛 종단'), findsOneWidget);
    expect(find.text('메아리 우물정원을 완주하면 열려요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-start-starlight_crossing')),
        findsNothing);

    expectTapTargets(tester, screen: '장거리 개척 입구');
    expect(tester.takeException(), isNull);
  });

  testWidgets('출발하면 갈림길 둘과 원정 띠가 있는 편성 화면이 열린다', (tester) async {
    await _pump(tester);

    await tester.tap(
      find.byKey(const ValueKey('journey-start-beyond_the_well')),
    );
    await tester.pumpAndSettle();

    expect(find.text('1구간 · 어느 길로 갈까요'), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-route-well_mouth')), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-route-mossy_stair')), findsOneWidget);
    // 아직 가지 않은 구간은 이름을 보여 주지 않는다.
    expect(find.text('미지의 구간'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('길잡이만으로도 떠날 수 있고 남은 자리는 자동으로 채워진다', (tester) async {
    final repository = await _pump(tester, active: _journey());

    await tester.tap(find.byKey(const ValueKey('journey-route-mossy_stair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journey-depart')));
    await tester.pumpAndSettle();

    expect(repository.lastRouteCode, 'mossy_stair');
    expect(repository.lastPlantIds, isEmpty);
    expect(repository.lastGuideCount, 2);
    // 걷는 화면으로 밀어 넣기 전에 탐험 상태를 다시 읽어야 한다. 이게 없으면
    // 방금 연 구간 대신 낡은 허브가 뜬다.
    expect(find.text('걷는 화면'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('이미 다녀온 캐릭터는 남겨 두되 고를 수 없다', (tester) async {
    await _pump(
      tester,
      active: _journey(
        currentLegIndex: 1,
        legs: [_leg()],
        usedPlantIds: const [11],
      ),
    );

    expect(find.text('이번 개척에서 이미 한 구간을 걸었어요'), findsOneWidget);
    final walked = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('journey-roster-11')),
    );
    expect(walked.onChanged, isNull);
    final free = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('journey-roster-12')),
    );
    expect(free.onChanged, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('마지막 야영지에서는 가장 먼 곳 기준 보상을 알리고 귀환만 남는다', (tester) async {
    final repository = await _pump(
      tester,
      active: _journey(currentLegIndex: 2, legs: [_leg()], canContinue: false),
    );

    expect(find.text('마지막 야영지예요'), findsOneWidget);
    expect(find.text('가장 먼 곳 · 메아리 우물정원'), findsOneWidget);
    expect(find.text('7 XP · 씨앗 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-depart')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('journey-return')));
    await tester.pumpAndSettle();

    expect(repository.returnCalls, 1);
    expect(find.text('원정 기록을 안고 돌아왔어요'), findsOneWidget);
    expect(find.text('1구간 · 우물 아가리'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('걷던 구간이 있으면 탐험 화면으로 돌려보낸다', (tester) async {
    await _pump(
      tester,
      active: _journey(activeRunId: 40, canContinue: false),
    );

    expect(find.text('걷던 구간이 있어요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journey-resume')));
    await tester.pumpAndSettle();
    expect(find.text('걷는 화면'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 200% 글자에서도 편성 화면이 오버플로우하지 않는다', (tester) async {
    await _pump(
      tester,
      active: _journey(),
      size: const Size(320, 640),
      textScale: 2,
    );

    expect(find.byKey(const ValueKey('journey-depart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
