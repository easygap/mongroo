import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/presentation/expedition_battle_dock.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/data/expedition_repository.dart';
import 'package:mongroo/features/expedition/data/joint_guard_repository.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/domain/joint_guard_models.dart';
import 'package:mongroo/features/expedition/presentation/joint_guard_screen.dart';

import 'tap_target.dart';

Map<String, dynamic> _member(int id, String name, {int hp = 12}) => {
      'id': id,
      'member_id': id,
      'name': name,
      'species': {'code': 'ninja-pot', 'name': '닌자 화분'},
      'stage': 5,
      'form': 'mosaic',
      'stats': {'care': 5, 'focus': 5, 'courage': 5, 'insight': 5},
      'is_guide': false,
      'formation': 'front',
      'hp': hp,
      'max_hp': 12,
    };

Map<String, dynamic> _battle() => {
      'status': 'active',
      'round': 1,
      'max_rounds': 4,
      'focus': 3,
      'max_focus': 5,
      'enemy': {
        'name': '돌비늘 장부지기',
        'guard': 70,
        'max_guard': 70,
        'weakness': 'insight',
        'weakness_label': '관찰',
        'weak_kel': 'sunny',
        'weak_kel_label': '햇살결',
        'resist_kel': 'rainy',
        'resist_kel_label': '빗물결',
        'intent': {
          'code': 'page_snow',
          'name': '페이지 눈보라',
          'telegraph': '잠결에 페이지가 눈처럼 쏟아져요.',
          'target': 'all',
          'power': 2,
        },
        'extra_intents': [
          {
            'code': 'margin_murmur',
            'name': '여백의 잠꼬대',
            'telegraph': '여백에 적힌 말이 작게 새어 나와요.',
            'target': 'lowest',
            'power': 1,
          },
        ],
      },
      'party': [
        {'member_id': 1, 'name': '앞선이', 'hp': 12, 'max_hp': 12},
        {'member_id': 2, 'name': '가운데', 'hp': 12, 'max_hp': 12},
        {'member_id': 3, 'name': '뒷선이', 'hp': 12, 'max_hp': 12},
      ],
      'last_exchange': const [],
      'battle_log': const [],
    };

Map<String, dynamic> _run({int swapsLeft = 1, String status = 'active'}) => {
      'run': {'id': 7, 'revision': 3, 'status': 'active'},
      'joint_guard': {
        'status': status,
        'beast': {
          'code': 'ledger_keeper',
          'name': '돌비늘 장부지기',
          'region_code': 'moss_archive',
          'dream_scene': '페이지가 눈처럼 내리는 서고의 꿈',
          'holding': '분류 못 한 기억 장부',
          'unlocked': true,
        },
        'difficulty': {
          'code': 'three_layers',
          'name': '세 겹의 꿈',
          'summary': '세 겹을 모두 얕게 만들어요.',
          'layers': 3,
          'tutorial': false,
        },
        'layer': {
          'index': 0,
          'name': '겉꿈',
          'count': 3,
          'weak_kel': 'sunny',
          'weak_kel_label': '햇살결',
          'resist_kel': 'rainy',
          'resist_kel_label': '빗물결',
          'warning': null,
        },
        'swaps_left': swapsLeft,
        'front': [
          _member(1, '앞선이'),
          _member(2, '가운데'),
          _member(3, '뒷선이'),
        ],
        'reserves': [
          {..._member(4, '기다림'), 'formation': 'back', 'can_swap_in': true},
          {
            ..._member(5, '지친이', hp: 0),
            'formation': 'back',
            'can_swap_in': false,
          },
          {..._member(6, '막내'), 'formation': 'back', 'can_swap_in': true},
        ],
        'battle': _battle(),
        'log': const ['겉꿈에 들어섰어요.'],
      },
    };

Map<String, dynamic> _entry({bool unlocked = true}) => {
      'beasts': [
        {
          'code': 'ledger_keeper',
          'name': '돌비늘 장부지기',
          'region_code': 'moss_archive',
          'dream_scene': '페이지가 눈처럼 내리는 서고의 꿈',
          'holding': '분류 못 한 기억 장부',
          'unlocked': unlocked,
          'locked_reason':
              unlocked ? null : '그 지역의 수호짐승을 한 번 만나고 나면 열려요.',
        },
        {
          'code': 'echo_keeper',
          'name': '물거울 메아리지기',
          'region_code': 'echo_well',
          'dream_scene': '소리가 물결로 보이는 우물의 꿈',
          'holding': '주인 못 찾은 메아리',
          'unlocked': false,
          'locked_reason': '그 지역의 수호짐승을 한 번 만나고 나면 열려요.',
        },
      ],
      'difficulties': [
        {
          'code': 'outer_walk',
          'name': '겉꿈 산책',
          'summary': '한 겹만 걸어요.',
          'layers': 1,
          'tutorial': true,
        },
        {
          'code': 'three_layers',
          'name': '세 겹의 꿈',
          'summary': '세 겹을 모두 얕게 만들어요.',
          'layers': 3,
          'tutorial': false,
        },
      ],
      'active_run_id': null,
    };

class _FakeJointGuardRepository implements JointGuardRepository {
  _FakeJointGuardRepository({required this.entry, this.active});

  final Map<String, dynamic> entry;
  Map<String, dynamic>? active;
  int swapCalls = 0;

  @override
  Future<JointGuardEntry> getEntry() async => JointGuardEntry.fromJson(entry);

  @override
  Future<JointGuardRun?> getActive() async =>
      active == null ? null : JointGuardRun.fromJson(active!);

  @override
  Future<JointGuardRun> start({
    required String beastCode,
    required String difficulty,
    required List<Map<String, Object?>> formation,
    required String idempotencyKey,
  }) async {
    active = _run();
    return JointGuardRun.fromJson(active!);
  }

  @override
  Future<JointGuardRun> submitTurn({
    required int runId,
    required ExpeditionCombatCommand command,
    required int expectedRevision,
    required String clientActionId,
  }) async =>
      JointGuardRun.fromJson(active!);

  @override
  Future<JointGuardRun> swap({
    required int runId,
    required int outMemberId,
    required int inMemberId,
    required int expectedRevision,
    required String clientActionId,
  }) async {
    swapCalls += 1;
    active = _run(swapsLeft: 0);
    return JointGuardRun.fromJson(active!);
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
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<_FakeJointGuardRepository> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? entry,
  Map<String, dynamic>? active,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = _FakeJointGuardRepository(
    entry: entry ?? _entry(),
    active: active,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jointGuardRepositoryProvider.overrideWithValue(repository),
        expeditionRepositoryProvider.overrideWithValue(
          _FakeExpeditionRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const JointGuardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('입구는 잠긴 짐승도 이유와 함께 보여 준다', (tester) async {
    // 잠긴 것을 숨기면 무엇이 기다리는지 알 수 없다. 배지가 아니라 문장으로
    // 이유를 읽어 준다.
    await _pump(tester);

    expect(find.text('돌비늘 장부지기'), findsOneWidget);
    expect(find.text('물거울 메아리지기'), findsOneWidget);
    expect(
      find.text('그 지역의 수호짐승을 한 번 만나고 나면 열려요.'),
      findsOneWidget,
    );
    expect(find.text('겉꿈 산책 · 1겹'), findsOneWidget);
    expect(find.text('세 겹의 꿈 · 3겹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('끌어안은 것을 조사에 맞춰 읽어 준다', (tester) async {
    // `기억 장부를`이지 `기억 장부을`이 아니다. 짐승마다 받침이 다르다.
    await _pump(tester);
    expect(find.text('분류 못 한 기억 장부를 꼭 끌어안고 있어요.'), findsOneWidget);
  });

  testWidgets('난이도를 고르면 편성으로 이어지고 빈자리는 길잡이가 채운다',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('joint-guard-start-outer_walk')));
    await tester.pumpAndSettle();

    expect(find.text('탐험대 편성'), findsOneWidget);
    // 여섯 자리가 모두 서 있고, 아무도 안 골랐으면 전부 길잡이다.
    expect(find.text('길잡이'), findsNWidgets(6));
    expect(
      find.text('길잡이 여섯으로 들어가요. 그래도 끝까지 갈 수 있어요.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('캐릭터를 고르면 앞자리부터 채워진다', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('joint-guard-start-outer_walk')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('joint-guard-roster-11')));
    await tester.pumpAndSettle();

    expect(find.text('새싹몬'), findsWidgets);
    expect(find.text('길잡이'), findsNWidgets(5));
    expect(find.text('1명이 함께 가고 나머지는 길잡이가 채워요.'), findsOneWidget);
  });

  testWidgets('판에 들어가면 겹과 상성을 이름으로 읽어 준다', (tester) async {
    await _pump(tester, active: _run());

    expect(find.byKey(const ValueKey('joint-guard-layer')), findsOneWidget);
    expect(find.text('겉꿈 · 1겹째 · 전체 3겹'), findsOneWidget);
    // 색만으로 구분하지 않는다.
    expect(find.text('잘 통해요 햇살결'), findsOneWidget);
    expect(find.text('잘 안 통해요 빗물결'), findsOneWidget);

    // 글자도 못 읽는 경우까지 본다. 화살표는 통하고 안 통하고만 말했지
    // **어느 성장결인지**는 이름으로만 있었다. 성장결마다 다른 마크가 붙는다.
    final marks = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((asset) => asset.assetName)
        .where((name) => name.contains('/skill-icons/kel/'))
        .toList();
    expect(marks, contains(expeditionKelIconAsset('sunny')));
    expect(marks, contains(expeditionKelIconAsset('rainy')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('예고는 주 의도와 잠꼬대 두 줄로 나란히 선다', (tester) async {
    // 설계서 8장의 UI 계약이다. 잠꼬대가 안 보이면 다음 라운드를 판단할 수 없다.
    await _pump(tester, active: _run());

    // 주 예고는 기존 독이 그리고, 잠꼬대는 그 바로 아래에 이어 붙는다.
    // 사본을 만들면 같은 예고가 두 번 나온다 - 실제로 한 번 그랬다.
    expect(
      find.byKey(const ValueKey('seq-dock-extra-margin_murmur')),
      findsOneWidget,
    );
    expect(find.textContaining('페이지 눈보라'), findsOneWidget);
    expect(find.textContaining('여백의 잠꼬대'), findsOneWidget);
  });

  testWidgets('기다리는 대원은 체력과 함께 서고 지친 대원은 설 수 없다',
      (tester) async {
    await _pump(tester, active: _run());

    expect(find.text('기다리는 대원'), findsOneWidget);
    expect(find.text('이번 라운드 교대 1번'), findsOneWidget);
    expect(find.text('지쳐서 물러남'), findsOneWidget);

    final downed = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('joint-guard-reserve-5')),
    );
    expect(downed.onPressed, isNull);
    final ready = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('joint-guard-reserve-4')),
    );
    expect(ready.onPressed, isNotNull);
  });

  testWidgets('교대를 다 쓰면 남은 횟수를 그대로 말한다', (tester) async {
    await _pump(tester, active: _run(swapsLeft: 0));

    expect(find.text('이번 라운드 교대를 썼어요'), findsOneWidget);
    final ready = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('joint-guard-reserve-4')),
    );
    expect(ready.onPressed, isNull);
  });

  testWidgets('교대는 누구와 바꿀지 묻고 나서 보낸다', (tester) async {
    final repository = await _pump(tester, active: _run());

    await tester.tap(find.byKey(const ValueKey('joint-guard-reserve-4')));
    await tester.pumpAndSettle();

    expect(find.text('누구와 바꿀까요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('joint-guard-swap-out-1')));
    await tester.pumpAndSettle();

    expect(repository.swapCalls, 1);
  });

  testWidgets('깨어나면 반복 보상이 없다는 것을 숨기지 않는다', (tester) async {
    await _pump(tester, active: _run(status: 'awake'));

    expect(find.byKey(const ValueKey('joint-guard-outcome')), findsOneWidget);
    expect(find.text('돌비늘 장부지기가 깨어났어요'), findsOneWidget);
    expect(
      find.textContaining('씨앗과 성장은 오가지 않아요'),
      findsOneWidget,
    );
  });

  testWidgets('꿈이 다시 깊어져도 잃은 것이 없다고 말한다', (tester) async {
    await _pump(tester, active: _run(status: 'withdrawn'));

    expect(find.text('꿈이 다시 깊어졌어요'), findsOneWidget);
    expect(find.textContaining('아무도 다치지 않았어요'), findsOneWidget);
  });

  testWidgets('320px 200% 글자에서도 입구가 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(320, 720), textScale: 2);

    expect(find.text('깊은 꿈'), findsOneWidget);
    expectTapTargets(tester, screen: '합동 수호전 입구');
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 200% 글자에서도 편성이 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(320, 720), textScale: 2);
    final start = find.byKey(const ValueKey('joint-guard-start-outer_walk'));
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(find.text('탐험대 편성'), findsOneWidget);
    expectTapTargets(tester, screen: '합동 수호전 편성');
    expect(tester.takeException(), isNull);
  });
}
