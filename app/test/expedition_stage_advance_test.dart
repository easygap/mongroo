import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/data/expedition_repository.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_controller.dart';
import 'package:mongroo/features/expedition/presentation/expedition_screen.dart';

/// 걸음 하나를 마친 판. 목표를 확보하고 서버가 판을 닫은 상태다.
Map<String, dynamic> _finishedRunJson({
  int stageNo = 4,
  String status = 'completed',
  bool withStory = true,
}) =>
    {
      'run': {
        'id': 21,
        'mode': 'free_explore',
        'stage_no': stageNo,
        'status': status,
        'phase': 'finished',
        'revision': 9,
        'current_node_code': 'stage_den',
        'trail_light': 6,
        'resolve': 4,
        'objective_secured': true,
        'reward_eligible': true,
      },
      'region': {
        'code': 'moss_archive',
        'name': '이끼 기억서고',
        'description': '첫 탐험지',
        'recommended_stage': 2,
        'reward': {'exp': 6, 'seeds': 2},
      },
      'party': [
        {
          'id': 11,
          'name': '새싹몬',
          'species': {'code': 'baby-pot', 'name': '아기 화분'},
          'stage': 3,
          'form': 'sunny',
          'outfit_key': null,
          'stats': {'care': 7, 'focus': 6, 'courage': 6, 'insight': 5},
          'is_guide': false,
          'skills': {
            'signature': {
              'code': 'baby-pot.sprout-cheer',
              'name': '새싹 응원',
              'description': '이번 우회의 결의 손실을 한 번 막아요.',
              'phases': <String>[],
              'modes': <Map<String, dynamic>>[],
              'used': true,
              'available': false,
            },
            'form': {
              'code': 'sunny.share-warmth',
              'name': '온기 나누기',
              'description': '돌봄 판정에 +3을 더해요.',
              'phases': <String>[],
              'modes': <Map<String, dynamic>>[],
              'used': true,
              'available': false,
            },
          },
        },
      ],
      'map': {
        'nodes': [
          {
            'code': 'stage_den',
            'name': '번진 이름들',
            'type': 'event',
            'status': 'resolved',
            'x': .5,
            'y': .55,
            'cost': 0,
            'scene_key': 'flooded_cave',
            'scene_label': '침수 동굴',
            'scene_description': '젖은 표찰의 글자를 되살리는 자리예요.',
            'depth_label': '기억서고 $stageNo',
            'threat_level': 1,
          },
        ],
        'edges': <List<String>>[],
      },
      'current_event': null,
      'last_resolution': null,
      'available_actions': <Map<String, dynamic>>[],
      'run_thread': {'code': 'archive_breathing_ledger', 'current_text': ''},
      'memory': {'discoveries': [], 'outcomes': []},
      'loot': [
        {
          'item_code': 'pressed_leaf_map',
          'name': '눌러 말린 잎 지도',
          'quantity': 1,
          'disposition': 'granted',
        },
      ],
      'summary': {
        'reward': {
          'events': [
            {'exp_delta': 6, 'seed_delta': 2},
          ],
        },
        if (withStory)
          'story_cue': {
            'stage_no': stageNo,
            'code': 'archive_$stageNo',
            'title': '되살아난 표찰',
            'body': '글자가 다시 읽히자 서고가 조금 조용해졌어요.',
          },
      },
    };

/// 진행 중인 다음 걸음. `계속`이 부른 출발이 돌려주는 판이다.
Map<String, dynamic> _nextRunJson() {
  final json = _finishedRunJson(stageNo: 5);
  final run = json['run'] as Map<String, dynamic>;
  run['id'] = 22;
  run['status'] = 'active';
  run['phase'] = 'exploring';
  run['objective_secured'] = false;
  json['summary'] = null;
  json['available_actions'] = [
    {'type': 'move', 'node_code': 'stage_den', 'cost': 0},
  ];
  return json;
}

Map<String, dynamic> _stageMapJson({int clearedCount = 3}) => {
      'content_version': '2026.08.4',
      'region': {
        'code': 'moss_archive',
        'name': '이끼 기억서고',
        'short_name': '기억서고',
        'description': '첫 탐험지',
        'recommended_stage': 2,
      },
      'progress': {
        'cleared_count': clearedCount,
        'total': 8,
        'next_stage_no': clearedCount >= 8 ? null : clearedCount + 1,
        'region_cleared': clearedCount >= 8,
      },
      'active_run': null,
      'regions': <Map<String, dynamic>>[],
      'stages': [
        for (var no = 1; no <= 8; no++)
          {
            'no': no,
            'kind': no == 8 ? 'boss' : 'battle',
            'kind_label': no == 8 ? '수호전' : '전투',
            'label': '기억서고 $no',
            'title': '$no번째 자리',
            'summary': '$no번째 자리에서 벌어지는 일이에요.',
            'estimated_seconds': 75,
            'tangles': <Map<String, dynamic>>[],
            'cleared': no <= clearedCount,
            'clear_count': no <= clearedCount ? 1 : 0,
            'story_seen': false,
            'unlocked': no <= clearedCount + 1,
            'lock_reason': no <= clearedCount + 1 ? null : '앞 걸음을 먼저 마쳐요.',
          },
      ],
    };

ExpeditionCatalog _catalog({bool heartResonance = false}) =>
    ExpeditionCatalog.fromJson({
      'content_version': '2026.08.4',
      'active_run_id': null,
      'entry': {
        'diary_ready': heartResonance,
        'heart_resonance_available': heartResonance,
        'free_explore_available': true,
        'deep_available': false,
        'deep_locked_reason': '기억서고 8까지 완주하면 열려요.',
        'suspended': false,
        'tutorial_completed': true,
      },
      'regions': <Map<String, dynamic>>[],
    });

/// 다음 걸음을 여는 데 필요한 것만 답한다.
class _FakeRepository implements ExpeditionRepository {
  _FakeRepository({this.heartResonance = false});

  final bool heartResonance;
  final List<String?> stageMapCalls = [];
  final List<(String, int?)> starts = [];
  int storySeen = 0;

  @override
  Future<ExpeditionStageMap> getStageMap({String? regionCode}) async {
    stageMapCalls.add(regionCode);
    // 방금 마친 4장이 완주로 잡힌 지도.
    return ExpeditionStageMap.fromJson(_stageMapJson(clearedCount: 4));
  }

  @override
  Future<ExpeditionCatalog> getCatalog() async =>
      _catalog(heartResonance: heartResonance);

  @override
  Future<ExpeditionSnapshot> start({
    required String mode,
    required String regionCode,
    required List<int> plantIds,
    required int guideCount,
    required String idempotencyKey,
    int? stageNo,
  }) async {
    starts.add((mode, stageNo));
    return ExpeditionSnapshot.fromJson(_nextRunJson());
  }

  @override
  Future<bool> markStageStorySeen({
    required String regionCode,
    required int stageNo,
  }) async {
    storySeen += 1;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// 화면 검사용 - 서버를 부르지 않고 이어 가기 호출만 센다.
class _FakeAdvanceController extends ExpeditionController {
  _FakeAdvanceController(this.initial);

  final ExpeditionUiState initial;
  int advanceCalls = 0;
  int leaveCalls = 0;

  @override
  ExpeditionUiState build() => initial;

  @override
  Future<bool> advanceToNextStage() async {
    advanceCalls += 1;
    return true;
  }

  @override
  Future<void> leaveSummary() async {
    leaveCalls += 1;
  }

  @override
  Future<void> markStageStorySeen(int stageNo) async {}
}

Future<_FakeAdvanceController> _pumpScene(
  WidgetTester tester, {
  int stageNo = 4,
  String status = 'completed',
  bool withStageMap = true,
  int clearedCount = 3,
}) async {
  late _FakeAdvanceController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expeditionControllerProvider.overrideWith(() {
          controller = _FakeAdvanceController(
            ExpeditionUiState(
              loading: false,
              expedition: ExpeditionSnapshot.fromJson(
                _finishedRunJson(stageNo: stageNo, status: status),
              ),
              stageMap: withStageMap
                  ? ExpeditionStageMap.fromJson(
                      _stageMapJson(clearedCount: clearedCount),
                    )
                  : null,
              selectedMemberId: 11,
              selectedPlantIds: const {11},
            ),
          );
          return controller;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ExpeditionScreen(),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

/// 컨트롤러만 세운다 - 화면 없이 이어 가기 절차를 본다.
({ProviderContainer container, _FakeRepository repository}) _controller({
  bool heartResonance = false,
  int stageNo = 4,
}) {
  final repository = _FakeRepository(heartResonance: heartResonance);
  final container = ProviderContainer(
    overrides: [
      expeditionRepositoryProvider.overrideWithValue(repository),
      expeditionControllerProvider.overrideWith(
        () => _StubbedController(
          ExpeditionUiState(
            loading: false,
            catalog: _catalog(),
            expedition: ExpeditionSnapshot.fromJson(
              _finishedRunJson(stageNo: stageNo),
            ),
            stageMap: ExpeditionStageMap.fromJson(_stageMapJson()),
            selectedPlantIds: const {11},
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, repository: repository);
}

/// 초기 상태만 갈아 끼우고 나머지는 진짜 컨트롤러 그대로 쓴다.
class _StubbedController extends ExpeditionController {
  _StubbedController(this.initial);

  final ExpeditionUiState initial;

  @override
  ExpeditionUiState build() => initial;
}

void main() {
  testWidgets('걸음을 마치면 결과 페이지 대신 무대 위에 결과가 얹힌다', (tester) async {
    // 설계서 3.6: `스테이지 사이에는 불투명 로딩 카드나 흰 결과 페이지를
    // 끼우지 않는다.`
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpScene(tester);

    // 걸었던 무대가 그대로 남는다.
    expect(find.byKey(const ValueKey('stage-scene-stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-advance-panel')), findsOneWidget);
    expect(find.text('계속 · 5장으로'), findsOneWidget);
    expect(find.text('경로'), findsOneWidget);
    expect(find.text('나가기'), findsOneWidget);
    // 결과 페이지의 `탐험 목록으로`는 서지 않는다.
    expect(find.text('탐험 목록으로'), findsNothing);
    // 이 걸음이 남긴 것도 같은 자리에서 읽힌다.
    expect(find.text('성장 +6'), findsOneWidget);
    expect(find.text('씨앗 +2'), findsOneWidget);
    expect(find.textContaining('되살아난 표찰'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('계속을 누르면 다음 걸음을 연다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpScene(tester);
    await tester.tap(find.byKey(const ValueKey('stage-advance-continue')));
    await tester.pump();

    expect(controller.advanceCalls, 1);
    expect(controller.leaveCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('나가기를 누르면 허브로 돌아간다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpScene(tester);
    await tester.tap(find.byKey(const ValueKey('stage-advance-leave')));
    await tester.pump();

    expect(controller.leaveCalls, 1);
    expect(controller.advanceCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('경로를 누르면 같은 오버레이가 무대 위에 열린다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpScene(tester);
    await tester.tap(find.byKey(const ValueKey('stage-advance-route')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('stage-route-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-scene-stage')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('지역의 마지막 걸음은 기존 결과 화면으로 간다', (tester) async {
    // 지역을 마친 순간에는 다음 지역이 열렸다는 소식과 전환기가 있는 결과
    // 화면이 할 말이 더 많다.
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpScene(tester, stageNo: 8);

    expect(find.byKey(const ValueKey('stage-advance-panel')), findsNothing);
    expect(find.text('탐험 목록으로'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('후퇴한 판은 이어 가기를 권하지 않는다', (tester) async {
    // 물러난 사람은 돌아가려던 것이지 이어 걸으려던 것이 아니다.
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpScene(tester, status: 'retreated');

    expect(find.byKey(const ValueKey('stage-advance-panel')), findsNothing);
    expect(find.text('탐험 목록으로'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('지도를 아직 못 읽었으면 기존 결과 화면으로 간다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpScene(tester, withStageMap: false);

    expect(find.byKey(const ValueKey('stage-advance-panel')), findsNothing);
    expect(find.text('탐험 목록으로'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('이어 가기는 판을 한 번도 비우지 않는다', () async {
    // 이것이 이 기능의 전부다. 중간에 판이 비면 화면이 허브로 한 번 돌아갔다
    // 오고, 그 순간 무대도 음악도 끊긴다.
    final harness = _controller();
    final notifier =
        harness.container.read(expeditionControllerProvider.notifier);

    final sawEmpty = <bool>[];
    harness.container.listen(
      expeditionControllerProvider,
      (previous, next) => sawEmpty.add(next.expedition == null),
      fireImmediately: true,
    );

    expect(await notifier.advanceToNextStage(), isTrue);

    expect(sawEmpty.contains(true), isFalse);
    expect(harness.repository.starts, [('free_explore', 5)]);
    expect(harness.repository.stageMapCalls, ['moss_archive']);
    final state = harness.container.read(expeditionControllerProvider);
    expect(state.expedition?.run.id, 22);
    expect(state.expedition?.run.stageNo, 5);
    expect(state.advancing, isFalse);
    // 허브를 거치지 않는다.
    expect(state.shellView, ExpeditionShellView.hub);
  });

  test('오늘 일기를 썼으면 다음 걸음도 마음 공명으로 떠난다', () async {
    // 카탈로그를 다시 읽는 이유다. 이 걸음에 공명을 이미 썼다면 다음은
    // 자유 탐험이어야 하고, 안 썼다면 남은 공명을 버리면 안 된다.
    final harness = _controller(heartResonance: true);
    await harness.container
        .read(expeditionControllerProvider.notifier)
        .advanceToNextStage();

    expect(harness.repository.starts, [('heart_resonance', 5)]);
  });

  test('걷는 중이면 이어 가기가 아무 일도 하지 않는다', () async {
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        expeditionRepositoryProvider.overrideWithValue(repository),
        expeditionControllerProvider.overrideWith(
          () => _StubbedController(
            ExpeditionUiState(
              loading: false,
              catalog: _catalog(),
              expedition: ExpeditionSnapshot.fromJson(_nextRunJson()),
              stageMap: ExpeditionStageMap.fromJson(_stageMapJson()),
              selectedPlantIds: const {11},
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final advanced = await container
        .read(expeditionControllerProvider.notifier)
        .advanceToNextStage();

    expect(advanced, isFalse);
    expect(repository.starts, isEmpty);
  });

  testWidgets('재도전을 마치면 이미 걸은 번호가 아니라 아직 안 걸은 곳을 가리킨다', (tester) async {
    // 6까지 걸어 둔 사람이 3을 다시 걸고 나면 다음은 4가 아니라 7이다.
    // `마친 번호 + 1`로 두면 여기서 틀린다.
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpScene(tester, stageNo: 3, clearedCount: 6);

    expect(find.text('계속 · 7장으로'), findsOneWidget);
    expect(find.text('계속 · 4장으로'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('다음 번호는 방금 마친 걸음까지 셈에 넣는다', () {
    final map = ExpeditionStageMap.fromJson(_stageMapJson(clearedCount: 3));
    // 캐시된 지도는 4를 아직 안 걸은 것으로 알고 있다. 방금 그 4를 마쳤다.
    expect(map.nextStageNo, 4);
    expect(stageAdvanceNextNo(map, 4), 5);
    // 재도전은 이미 지나온 번호로 되돌리지 않는다.
    expect(stageAdvanceNextNo(map, 2), 4);
  });
}
