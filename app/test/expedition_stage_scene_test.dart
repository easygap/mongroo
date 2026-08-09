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

class _FakeSceneController extends ExpeditionController {
  _FakeSceneController(this.initial);

  final ExpeditionUiState initial;
  final List<String> chosen = [];
  int extractCalls = 0;

  @override
  ExpeditionUiState build() => initial;

  @override
  Future<bool> choose(String choiceCode) async {
    chosen.add(choiceCode);
    return true;
  }

  @override
  Future<bool> extract() async {
    extractCalls += 1;
    return true;
  }
}

Future<_FakeSceneController> _pump(
  WidgetTester tester,
  Map<String, dynamic> json,
) async {
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
    await tester.longPress(find.byKey(const ValueKey('stage-choice-trace_ink')));
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

    expect(find.textContaining('기록을 안고 돌아갈 수 있어요'), findsOneWidget);
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

    expect(find.textContaining('숨을 골랐어요'), findsOneWidget);
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
}
