import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_controller.dart';
import 'package:mongroo/features/expedition/presentation/expedition_screen.dart';

Map<String, dynamic> _member() => {
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
          'phases': ['awaiting_event'],
          'modes': <Map<String, dynamic>>[],
          'used': false,
          'available': true,
        },
        'form': {
          'code': 'sunny.share-warmth',
          'name': '온기 나누기',
          'description': '돌봄 판정에 +3을 더해요.',
          'phases': ['awaiting_event'],
          'modes': <Map<String, dynamic>>[],
          'used': false,
          'available': true,
        },
      },
    };

Map<String, dynamic> _stageDen({
  String type = 'event',
  String sceneKey = 'flooded_cave',
  String status = 'visited',
}) =>
    {
      'code': 'stage_den',
      'name': '번진 이름들',
      'type': type,
      'status': status,
      'x': .5,
      'y': .55,
      'cost': 0,
      'scene_key': sceneKey,
      'scene_label': '침수 동굴',
      'scene_description': '젖은 표찰의 글자를 되살리는 자리예요.',
      'depth_label': '기억서고 2',
      'threat_level': 1,
    };

Map<String, dynamic> _snapshotBase({
  required Map<String, dynamic> den,
  Map<String, dynamic>? currentEvent,
  bool objectiveSecured = false,
  List<Map<String, dynamic>> availableActions = const [],
  List<Map<String, dynamic>> loot = const [],
}) =>
    {
      'run': {
        'id': 7,
        'mode': 'free_explore',
        'stage_no': 2,
        'status': 'active',
        'phase': currentEvent != null ? 'awaiting_event' : 'exploring',
        'revision': 3,
        'current_node_code': 'stage_den',
        'trail_light': 10,
        'resolve': 6,
        'objective_secured': objectiveSecured,
        'reward_eligible': false,
      },
      'region': {
        'code': 'moss_archive',
        'name': '이끼 기억서고',
        'description': '첫 탐험지',
        'recommended_stage': 2,
        'reward': {'exp': 6, 'seeds': 2},
      },
      'party': [_member()],
      'map': {
        'nodes': [den],
        'edges': <List<String>>[],
      },
      'current_event': currentEvent,
      'last_resolution': null,
      'available_actions': availableActions,
      'run_thread': {'code': 'archive_breathing_ledger', 'current_text': ''},
      'memory': {'discoveries': [], 'outcomes': []},
      'loot': loot,
      'summary': null,
    };

Map<String, dynamic> _eventSnapshotJson() => _snapshotBase(
      den: _stageDen(),
      currentEvent: {
        'code': 'wet_label_order',
        'node_code': 'stage_den',
        'title': '번진 이름들',
        'text': '비에 젖은 표찰들이 바닥에 붙어 있어요. 흐릿한 글자를 어떤 방식으로 되살릴까요?',
        'spotlight_member_id': 11,
        'encounter': null,
        'battle': null,
        'choices': [
          {
            'code': 'trace_ink',
            'label': '번진 잉크의 결을 따라간다',
            'stat': 'insight',
            'difficulty': 8,
            'resolve_cost': 1,
            'previews': [
              {
                'member_id': 11,
                'stat': 'insight',
                'stat_label': '관찰',
                'value': 7,
                'difficulty': 8,
                'forecast': '도전',
                'label': '관찰 7 · 기준 8',
              },
            ],
          },
          {
            'code': 'sort_slowly',
            'label': '숨을 맞추며 한 장씩 분류한다',
            'stat': 'focus',
            'difficulty': 8,
            'resolve_cost': 1,
            'previews': [
              {
                'member_id': 11,
                'stat': 'focus',
                'stat_label': '집중',
                'value': 4,
                'difficulty': 8,
                'forecast': '도전',
                'label': '집중 4 · 기준 8',
              },
            ],
          },
          {
            'code': 'mark_return',
            'label': '안전한 표식만 남기고 돌아선다',
            'stat': null,
            'difficulty': 0,
            'resolve_cost': 0,
            'safe': true,
            'previews': [
              {
                'member_id': 11,
                'safe': true,
                'label': '판정 없이 안전하게 진행',
              },
            ],
          },
        ],
      },
      availableActions: [
        {'type': 'choice'},
        {'type': 'skill'},
      ],
    );

Map<String, dynamic> _finishedSnapshotJson() => _snapshotBase(
      den: _stageDen(status: 'resolved'),
      objectiveSecured: true,
      availableActions: [
        {'type': 'extract'},
        {'type': 'retreat'},
      ],
      loot: [
        {
          'item_code': 'moss_key',
          'name': '이끼 열쇠',
          'quantity': 1,
          'disposition': 'recorded',
        },
      ],
    );

Map<String, dynamic> _campSnapshotJson() => _snapshotBase(
      den: _stageDen(type: 'camp', sceneKey: 'echo_well', status: 'resolved'),
      objectiveSecured: true,
      availableActions: [
        {'type': 'extract'},
      ],
    );

Map<String, dynamic> _walkingSnapshotJson() {
  final den = _stageDen(status: 'revealed');
  final raw = _snapshotBase(
    den: den,
    availableActions: [
      {'type': 'move', 'node_code': 'stage_den', 'cost': 0},
      {'type': 'retreat'},
    ],
  );
  final run = raw['run'] as Map<String, dynamic>;
  run['current_node_code'] = 'stage_entry';
  final map = raw['map'] as Map<String, dynamic>;
  map['nodes'] = [
    {
      'code': 'stage_entry',
      'name': '기억서고 들머리',
      'type': 'entrance',
      'status': 'visited',
      'x': .08,
      'y': .50,
      'cost': 0,
      'scene_key': 'dungeon_gate',
      'scene_label': '직접 걷는 들머리',
      'scene_description': '등불 아래의 길이 모습을 드러내요.',
      'depth_label': '기억서고 2 · 입구',
      'threat_level': 0,
    },
    den,
  ];
  map['edges'] = [
    ['stage_entry', 'stage_den'],
  ];
  raw['memory'] = {
    'discoveries': [],
    'outcomes': [],
    'stage_field': {
      'stage_no': 2,
      'chapter': 2,
      'title': '번진 이름들',
      'approach': '등불이 젖은 종이 냄새를 따라 하나씩 켜져요.',
      'objective': '젖은 표찰의 글자를 어떤 방식으로 되살릴지 골라요.',
      'destination_name': '침수 표찰 동굴',
      'destination_hint': '현장의 흔적은 가까이서 살펴봐야 읽혀요.',
    },
  };
  return raw;
}

class _FakeSceneController extends ExpeditionController {
  _FakeSceneController(this.initial);

  final ExpeditionUiState initial;
  final List<String> chosen = [];
  final List<String> moved = [];
  int extractCalls = 0;

  @override
  ExpeditionUiState build() => initial;

  @override
  Future<bool> choose(String choiceCode) async {
    chosen.add(choiceCode);
    return true;
  }

  @override
  Future<bool> move(String nodeCode) async {
    moved.add(nodeCode);
    return true;
  }

  @override
  Future<bool> extract() async {
    extractCalls += 1;
    return true;
  }
}

/// 진행 rail이 읽는 8점 지도. 걷는 판 밖의 상태라 장면 스냅숏과 따로 온다.
ExpeditionStageMap _railStageMap({int clearedCount = 1}) =>
    ExpeditionStageMap.fromJson({
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
        'next_stage_no': clearedCount + 1,
        'region_cleared': false,
      },
      'active_run': null,
      'regions': <Map<String, dynamic>>[],
      'stages': [
        for (var no = 1; no <= 8; no++)
          {
            'no': no,
            'kind': switch (no) {
              2 || 6 => 'event',
              5 => 'camp',
              8 => 'boss',
              _ => 'battle',
            },
            'kind_label': '전투',
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
    });

Future<_FakeSceneController> _pump(
  WidgetTester tester,
  Map<String, dynamic> json, {
  ExpeditionStageMap? stageMap,
}) async {
  final snapshot = ExpeditionSnapshot.fromJson(json);
  late _FakeSceneController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expeditionControllerProvider.overrideWith(() {
          controller = _FakeSceneController(
            ExpeditionUiState(
              loading: false,
              expedition: snapshot,
              stageMap: stageMap,
              selectedMemberId: 11,
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

void main() {
  testWidgets('스테이지는 지역 지형 위를 직접 걷고 목적 표식으로 사건에 진입한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pump(tester, _walkingSnapshotJson());

    expect(find.byKey(const ValueKey('stage-field-story')), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-field-map')), findsOneWidget);
    expect(find.text('번진 이름들'), findsWidgets);
    expect(find.textContaining('누른 채 원하는 방향'), findsOneWidget);
    expect(find.textContaining('가까이서 살펴봐야'), findsOneWidget);

    // 빈 길을 끌면 파티가 월드 좌표 안에서 실제로 이동한다. 카메라 추적형이라
    // 캐릭터는 화면 중앙에 머물 수 있으므로 스크린 픽셀이 아니라 좌표를 본다.
    final mapRect = tester.getRect(
      find.byKey(const ValueKey('expedition-walk-surface')),
    );
    String playerPosition() => tester
        .widget<Semantics>(
          find.byKey(const ValueKey('tile-world-player-position')),
        )
        .properties
        .value!;
    final beforeY = double.parse(playerPosition().split(',').last);
    final gesture = await tester.startGesture(
      Offset(mapRect.left + mapRect.width * .34,
          mapRect.top + mapRect.height * .78),
    );
    // 기억서고 들머리의 첫 통로는 아래쪽으로 열린다. 실제 보행 마스크의
    // 통로를 따라 한 걸음 내려간다.
    await gesture.moveBy(const Offset(0, 52));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final afterY = double.parse(playerPosition().split(',').last);
    expect(afterY, greaterThan(beforeY));
    await gesture.up();
    await tester.pump();

    // 전체 72×52 맵 이미지를 한 번에 그리지 않고 가시 타일만 그리며,
    // 위치 파악용 미니맵은 별도 저비용 데이터 레이어다.
    expect(find.textContaining('/3744'), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-world-minimap')), findsOneWidget);

    // 표식 탭은 아래의 가상 스틱 레이어에 막히지 않고 같은 move로 모인다.
    final landmark = find.byTooltip('번진 이름들');
    expect(tester.getSize(landmark).width, greaterThanOrEqualTo(48));
    await tester.tap(landmark);
    await tester.pump();
    expect(controller.moved, ['stage_den']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('칸 단위로 걷고 경계에서 멈추며 늘 칸 한가운데에 선다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, _walkingSnapshotJson());

    String position() => tester
        .widget<Semantics>(
          find.byKey(const ValueKey('tile-world-player-position')),
        )
        .properties
        .value!;
    double x() => double.parse(position().split(',').first);
    final map = tester.getRect(
      find.byKey(const ValueKey('expedition-walk-surface')),
    );
    final before = x();
    final gesture = await tester.startGesture(map.center);
    await gesture.moveBy(const Offset(-70, 0));
    for (var frame = 0; frame < 75; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(x(), lessThan(before));
    // 캐릭터 반지름과 바깥 테두리를 포함한 서쪽 충돌 경계.
    expect(x(), greaterThanOrEqualTo(1.35));
    // 칸 단위 이동이므로 걸음이 끝나면 늘 칸 한가운데(x.5)에 선다. 아날로그로
    // 미끄러지면 이 값이 아무 소수점이나 된다.
    expect((x() - x().floor()), closeTo(.5, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('사건 스테이지는 말풍선과 성공 예상이 붙은 선택 카드를 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pump(tester, _eventSnapshotJson());

    // 필드 장면 위 말풍선 하나로 사건을 말한다.
    expect(find.byKey(const ValueKey('stage-scene-stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-scene-bubble')), findsOneWidget);
    expect(find.textContaining('흐릿한 글자를 어떤 방식으로'), findsOneWidget);
    expect(find.text('새싹몬은 어떻게 할까요?'), findsOneWidget);

    // 선택 카드는 어울리는 힘과 성공 예상 세 단어만 크게 보여 준다.
    expect(find.text('어울리는 힘 · 관찰'), findsOneWidget);
    expect(find.text('해 볼 만해요'), findsOneWidget);
    expect(find.text('어려워 보여요'), findsOneWidget);
    expect(find.text('안전하게 진행돼요'), findsOneWidget);
    // 정확한 수치는 기본 화면에 노출하지 않는다.
    expect(find.textContaining('기준 8'), findsNothing);

    // 길게 누르면 수치 상세가 열린다.
    await tester
        .longPress(find.byKey(const ValueKey('stage-choice-trace_ink')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('관찰 7 · 기준 8'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(milliseconds: 300));

    // 카드 탭 한 번이 곧 선택이다.
    await tester.tap(find.byKey(const ValueKey('stage-choice-mark_return')));
    await tester.pump();
    expect(controller.chosen, ['mark_return']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('사건을 매듭지으면 그 자리에서 귀환 버튼이 열린다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pump(tester, _finishedSnapshotJson());

    // 말풍선이 28자로 줄면서 `기록을 안고`가 빠졌다. 돌아갈 수 있다는 것은
    // 그대로 말한다 - 그게 이 검사가 지키려던 것이다.
    expect(find.textContaining('돌아갈 수 있어요'), findsOneWidget);
    expect(find.textContaining('이끼 열쇠'), findsOneWidget);
    final extract = find.byKey(const ValueKey('stage-scene-extract'));
    expect(extract, findsOneWidget);
    await tester.tap(extract);
    await tester.pump();
    expect(controller.extractCalls, 1);
    // 걸음이 끝났으니 돌아가기 아이콘은 더 보여 주지 않는다.
    expect(find.byKey(const ValueKey('stage-scene-retreat')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('쉼터 스테이지는 휴식 문구와 함께 바로 귀환할 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, _campSnapshotJson());

    // 5.4의 28자 계약에 맞춰 줄인 문구다. 회복했다는 사실은 그대로 말한다.
    expect(find.textContaining('길빛과 결의가 차올라요'), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-scene-extract')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('320px과 200% 글자에서도 사건 장면이 넘치지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final snapshot = ExpeditionSnapshot.fromJson(_eventSnapshotJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeSceneController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                // 진행 rail도 같이 세워 둔다. 8개 점과 숫자가 320px에서
                // 넘치는지가 이 검사의 몫이다.
                stageMap: _railStageMap(clearedCount: 3),
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('stage-scene-stage')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px과 200% 글자에서도 직접 걷기 지도가 깨지지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final snapshot = ExpeditionSnapshot.fromJson(_walkingSnapshotJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeSceneController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                // 진행 rail도 같이 세워 둔다. 8개 점과 숫자가 320px에서
                // 넘치는지가 이 검사의 몫이다.
                stageMap: _railStageMap(clearedCount: 3),
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('stage-field-story')), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-field-map')), findsOneWidget);
    final mapSize =
        tester.getSize(find.byKey(const ValueKey('expedition-walk-surface')));
    expect(mapSize.width, closeTo(296, .01));
    expect(mapSize.width / mapSize.height, closeTo(1.45, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('걷는 중에도 상단 rail이 몇 번째 걸음인지 말한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(
      tester,
      _walkingSnapshotJson(),
      stageMap: _railStageMap(clearedCount: 1),
    );

    final rail = find.byKey(const ValueKey('stage-progress-rail'));
    expect(rail, findsOneWidget);
    expect(find.text('2/8'), findsOneWidget);
    // 손끝이 닿는 크기여야 rail이 실제로 눌린다.
    expect(tester.getSize(rail).height, greaterThanOrEqualTo(24));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rail을 누르면 무대 위에 경로가 열리고 닫으면 걷던 자리 그대로다', (tester) async {
    // 설계서 3.6: `상단 progress rail을 탭하면 현재 무대 위에 열리고,
    // 닫으면 같은 카메라 위치로 돌아간다.`
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pump(
      tester,
      _walkingSnapshotJson(),
      stageMap: _railStageMap(clearedCount: 3),
    );

    String playerPosition() => tester
        .widget<Semantics>(
          find.byKey(const ValueKey('tile-world-player-position')),
        )
        .properties
        .value!;
    final field = find.byKey(const ValueKey('stage-field-map'));
    final before = playerPosition();
    final fieldElement = tester.element(field);

    await tester.tap(find.byKey(const ValueKey('stage-progress-rail')));
    // 무대의 숨·잎은 계속 움직이므로 pumpAndSettle은 멈추지 않는다.
    // 오버레이가 열리는 190ms만 넘긴다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('stage-route-overlay')), findsOneWidget);
    // 무대 위에 겹친다 — 다른 화면으로 밀려나면 아래 판은 offstage가 되어
    // 기본 finder에 잡히지 않는다. 잡힌다는 것이 곧 겹쳤다는 뜻이다.
    expect(field, findsOneWidget);
    // 걷던 판을 두고 지도 화면으로 넘어가지 않는다.
    expect(controller.state.shellView, ExpeditionShellView.hub);
    expect(find.byKey(const ValueKey('stage-point-1')), findsNothing);

    // 여덟 점이 모두 서고, 지금 자리와 완주한 자리를 읽어 준다.
    for (var no = 1; no <= 8; no++) {
      expect(find.byKey(ValueKey('route-point-$no')), findsOneWidget);
    }
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('route-point-2')))
          .properties
          .label,
      contains('지금 여기'),
    );
    // 지나온 걸음에는 완주 표식이 남는다.
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('route-point-1')))
          .properties
          .label,
      contains('완주'),
    );

    await tester.tap(find.byKey(const ValueKey('stage-route-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('stage-route-overlay')), findsNothing);
    // 같은 요소가 그대로 살아 있으니 카메라도 걸음도 처음부터 다시 서지 않는다.
    expect(identical(tester.element(field), fieldElement), isTrue);
    expect(playerPosition(), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('8점 지도를 아직 못 읽었으면 rail 자리를 비워 둔다', (tester) async {
    // 이어하기로 곧장 들어오면 판이 지도보다 먼저 선다. 그때 빈 rail을
    // 그려 두면 걸음 수를 0/0으로 말하게 된다.
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, _walkingSnapshotJson());

    expect(find.byKey(const ValueKey('stage-progress-rail')), findsNothing);
    expect(find.byKey(const ValueKey('stage-field-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
