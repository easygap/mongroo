import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tap_target.dart';
import 'package:mongroo/core/text/korean_particles.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_controller.dart';
import 'package:mongroo/features/expedition/presentation/expedition_screen.dart';

Map<String, dynamic> _stage({
  required int no,
  required String kind,
  bool cleared = false,
  bool unlocked = false,
  bool storySeen = false,
  bool elite = false,
}) =>
    {
      'no': no,
      'kind': kind,
      'kind_label': switch (kind) {
        'event' => '사건',
        'camp' => '쉼터',
        'boss' => '수호전',
        _ => '전투',
      },
      'elite': elite,
      'label': '기억서고 $no',
      'title': '$no번째 자리',
      'summary': '$no번째 자리에서 벌어지는 일이에요.',
      'estimated_seconds': 75,
      'weakness': 'insight',
      'weakness_label': '관찰',
      'tangles': kind == 'battle'
          ? [
              {
                'code': 'tangled_ledger',
                'name': '엉킨 장부 뭉치',
                'description': '분류하다 만 장부들이 실처럼 서로 얽혔어요.',
              },
            ]
          : <Map<String, dynamic>>[],
      'cleared': cleared,
      'clear_count': cleared ? 1 : 0,
      'cleared_at': cleared ? '2026-08-08T00:00:00Z' : null,
      'story_seen': storySeen,
      'unlocked': unlocked,
      'lock_reason':
          unlocked ? null : '${koreanObject('기억서고 ${no - 1}')} 먼저 완주하면 열려요.',
    };

ExpeditionStageMap _stageMap({
  int clearedCount = 1,
  String regionCode = 'moss_archive',
  bool echoWellUnlocked = false,
}) =>
    ExpeditionStageMap.fromJson({
      'content_version': '2026.08.4',
      'region': regionCode == 'echo_well'
          ? {
              'code': 'echo_well',
              'name': '메아리 우물정원',
              'short_name': '우물정원',
              'description': '두 번째 탐험지',
              'recommended_stage': 3,
            }
          : {
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
      'regions': [
        {
          'code': 'moss_archive',
          'name': '이끼 기억서고',
          'short_name': '기억서고',
          'unlocked': true,
          'lock_reason': null,
          'cleared_count': regionCode == 'moss_archive' ? clearedCount : 8,
          'total': 8,
        },
        {
          'code': 'echo_well',
          'name': '메아리 우물정원',
          'short_name': '우물정원',
          'unlocked': echoWellUnlocked || regionCode == 'echo_well',
          'lock_reason': echoWellUnlocked || regionCode == 'echo_well'
              ? null
              : '앞 지역을 완주하면 열려요.',
          'cleared_count': regionCode == 'echo_well' ? clearedCount : 0,
          'total': 8,
        },
      ],
      'stages': [
        for (var no = 1; no <= 8; no++)
          _stage(
            no: no,
            kind: switch (no) {
              2 || 6 => 'event',
              5 => 'camp',
              8 => 'boss',
              _ => 'battle',
            },
            elite: no == 4,
            cleared: no <= clearedCount,
            unlocked: no <= clearedCount + 1,
            storySeen: false,
          ),
      ],
    });

ExpeditionCatalog _catalog({bool heartResonance = true, bool deep = false}) =>
    ExpeditionCatalog.fromJson({
      'content_version': '2026.08.4',
      'active_run_id': null,
      'entry': {
        'diary_ready': heartResonance,
        'heart_resonance_available': heartResonance,
        'free_explore_available': true,
        'deep_available': deep,
        'deep_locked_reason': deep ? null : '지역의 8스테이지를 모두 마치면 열려요',
        'suspended': false,
        'tutorial_completed': true,
      },
      'regions': [
        {
          'code': 'moss_archive',
          'name': '이끼 기억서고',
          'description': '첫 탐험지',
          'recommended_stage': 2,
          'reward': {'exp': 6, 'seeds': 2},
        },
      ],
    });

List<ExpeditionRosterItem> _roster() => [
      ExpeditionRosterItem.fromJson({
        'plant_id': 11,
        'name': '새싹몬',
        'species': {'code': 'baby-pot', 'name': '아기 화분'},
        'status': 'active',
        'stage': 3,
        'form': 'sunny',
        'outfit_key': null,
        'stats': {'care': 7, 'focus': 6, 'courage': 6, 'insight': 5},
        'eligible': true,
        'ineligible_reason': null,
      }),
    ];

class _FakeStageController extends ExpeditionController {
  _FakeStageController(this.initial);

  final ExpeditionUiState initial;
  int loadCalls = 0;
  final List<String> selectedRegions = [];

  @override
  ExpeditionUiState build() => initial;

  @override
  Future<void> load() async {
    loadCalls += 1;
  }

  @override
  Future<void> selectRegion(String regionCode) async {
    selectedRegions.add(regionCode);
    final map = state.stageMap;
    final target =
        map?.regions.where((region) => region.code == regionCode).firstOrNull;
    if (target != null && !target.unlocked) {
      state = state.copyWith(error: target.lockReason);
      return;
    }
    state = state.copyWith(stageMap: _stageMap(regionCode: regionCode));
  }
}

Future<_FakeStageController> _pumpShell(
  WidgetTester tester, {
  int clearedCount = 1,
  bool heartResonance = true,
  bool deep = false,
  bool echoWellUnlocked = false,
}) async {
  late _FakeStageController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expeditionControllerProvider.overrideWith(() {
          controller = _FakeStageController(
            ExpeditionUiState(
              loading: false,
              catalog: _catalog(heartResonance: heartResonance, deep: deep),
              roster: _roster(),
              stageMap: _stageMap(
                clearedCount: clearedCount,
                echoWellUnlocked: echoWellUnlocked,
              ),
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
    expectTapTargets(tester, screen: '스테이지 지도');
  return controller;
}

void main() {
  testWidgets('허브는 이어서 탐험할 스테이지 하나를 크게 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpShell(tester, clearedCount: 2);

    expect(find.byKey(const ValueKey('hub-continue-card')), findsOneWidget);
    expect(find.text('이어서 탐험하기'), findsOneWidget);
    expect(find.text('기억서고 3'), findsOneWidget);
    expect(find.text('오늘 일기를 써서 마음 공명이 준비됐어요.'), findsOneWidget);
    // 잠긴 하위 진입점은 숨기지 않고 조건을 그대로 읽어 준다.
    expect(find.text('깊은 조사'), findsOneWidget);
    expect(find.text('기억서고 8까지 완주하면 열려요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('일기 전에는 자유 탐험 안내로 바뀌고 재촉하지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpShell(tester, heartResonance: false);

    expect(
      find.text('마음 일기를 쓰면 오늘의 보상 탐험이 열려요. 그전에도 자유롭게 다녀올 수 있어요.'),
      findsOneWidget,
    );
    expect(find.byType(Badge), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('지도는 8개 점과 진행도를 보여 주고 잠긴 곳은 사유를 읽어 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpShell(tester, clearedCount: 2);
    await tester.tap(find.byKey(const ValueKey('hub-continue-card')));
    await tester.pump();

    for (var no = 1; no <= 8; no++) {
      expect(
        find.byKey(ValueKey('stage-point-$no')),
        findsOneWidget,
        reason: '$no번 스테이지 점',
      );
    }
    expect(find.text('2/8'), findsOneWidget);
    expect(find.text('기억서고 4를 먼저 완주하면 열려요.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('잠긴 곳의 글자는 흐려서 안 읽히지 않는다', (tester) async {
    // 잠김을 불투명도로 표시하면 이미 muted 색인 설명·사유가 한 번 더
    // 눌린다. 실측으로 4.62:1이던 `onSurfaceVariant`가 2.35:1까지 내려갔다.
    // 잠김은 아이콘과 사유 줄이 말하고, 글자는 색 그대로 둔다.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpShell(tester, clearedCount: 2);

    // 허브의 준비 중 항목
    final comingSoon = find.text('여섯이서 깊이 잠든 수호짐승을 깨워 줘요.');
    await tester.ensureVisible(comingSoon);
    await tester.pump();
    expect(
      find.ancestor(of: comingSoon, matching: find.byType(Opacity)),
      findsNothing,
      reason: '허브 잠김 항목 설명이 흐려집니다',
    );

    // 지도의 잠긴 스테이지
    await tester.tap(find.byKey(const ValueKey('hub-continue-card')));
    await tester.pump();
    final lockReason = find.text('기억서고 4를 먼저 완주하면 열려요.').first;
    await tester.ensureVisible(lockReason);
    await tester.pump();
    expect(
      find.ancestor(of: lockReason, matching: find.byType(Opacity)),
      findsNothing,
      reason: '잠긴 스테이지 사유가 흐려집니다',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('스테이지를 누르면 미리보기 시트가 열리고 출발까지 이어진다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpShell(tester, clearedCount: 2);
    await tester.tap(find.byKey(const ValueKey('hub-continue-card')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('stage-point-3')));
    await tester.pumpAndSettle();

    expect(find.text('기억서고 3 · 3번째 자리'), findsOneWidget);
    expect(find.text('약 1분 15초'), findsOneWidget);
    expect(find.text('약점 관찰'), findsOneWidget);
    expect(find.text('엉킨 장부 뭉치'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stage-sheet-start')));
    await tester.pumpAndSettle();

    expect(controller.state.shellView, ExpeditionShellView.preparation);
    expect(controller.state.selectedStageNo, 3);
    expect(
      find.byKey(const ValueKey('stage-preparation-header')),
      findsOneWidget,
    );
    expect(find.text('기억서고 3 · 전투'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('잠긴 스테이지는 시트에서 출발 버튼 대신 사유만 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpShell(tester, clearedCount: 1);
    await tester.tap(find.byKey(const ValueKey('hub-continue-card')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('stage-point-5')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stage-sheet-start')), findsNothing);
    expect(find.text('기억서고 4를 먼저 완주하면 열려요.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('지도와 편성 화면에서 뒤로 가면 한 단계씩 돌아온다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpShell(tester, clearedCount: 2);
    await tester.tap(find.byKey(const ValueKey('hub-continue-card')));
    await tester.pump();
    expect(controller.state.shellView, ExpeditionShellView.stageMap);

    await tester.tap(find.byKey(const ValueKey('stage-map-back')));
    await tester.pump();
    expect(controller.state.shellView, ExpeditionShellView.hub);
    expect(find.byKey(const ValueKey('hub-continue-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px과 200% 글자에서도 허브와 지도가 넘치지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late _FakeStageController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(() {
            controller = _FakeStageController(
              ExpeditionUiState(
                loading: false,
                catalog: _catalog(),
                roster: _roster(),
                stageMap: _stageMap(clearedCount: 2),
                selectedPlantIds: const {11},
              ),
            );
            return controller;
          }),
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

    expect(find.byKey(const ValueKey('hub-continue-card')), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.openStageMap();
    await tester.pump();

    expect(find.byKey(const ValueKey('stage-point-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('지역을 완주하면 지도에서 다음 지역으로 넘어갈 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpShell(
      tester,
      clearedCount: 8,
      echoWellUnlocked: true,
    );
    await tester.tap(find.byKey(const ValueKey('hub-continue-card')));
    await tester.pump();

    expect(find.byKey(const ValueKey('region-chip-moss_archive')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('region-chip-echo_well')));
    await tester.pump();

    expect(controller.selectedRegions, ['echo_well']);
    expect(controller.state.stageMap?.region.code, 'echo_well');
    expect(find.text('메아리 우물정원'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('아직 잠긴 지역을 누르면 이유를 말해 주고 지도는 그대로 둔다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpShell(tester, clearedCount: 3);
    await tester.tap(find.byKey(const ValueKey('hub-continue-card')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('region-chip-echo_well')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.selectedRegions, ['echo_well']);
    // 사유는 스낵바로 한 번 알리고 상태에서는 지워진다.
    expect(controller.state.stageMap?.region.code, 'moss_archive');
    expect(find.text('앞 지역을 완주하면 열려요.'), findsOneWidget);
    expect(find.text('이끼 기억서고'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('열린 깊은 조사는 눌러서 편성까지 들어간다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpShell(tester, clearedCount: 8, deep: true);

    expect(find.text('지도를 직접 읽으며 숨은 길과 원본 서고를 찾아요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hub-entry-깊은 조사')));
    // 편성 화면 캐릭터는 계속 흔들리므로 pumpAndSettle이 끝나지 않는다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.shellView, ExpeditionShellView.preparation);
    // 깊은 조사는 스테이지 투기장이 아니라 지역 자유 지도를 쓴다.
    expect(controller.state.selectedStageNo, isNull);
    expect(find.byKey(const ValueKey('prep-start-deep')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('스테이지를 골라 들어온 편성에는 깊은 조사 버튼을 두지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpShell(tester, clearedCount: 8, deep: true);
    controller.openStagePreparation(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.shellView, ExpeditionShellView.preparation);
    expect(find.byKey(const ValueKey('prep-start-deep')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('깊은 조사 편성에서 뒤로 가면 지도를 건너뛰고 허브로 돌아온다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = await _pumpShell(tester, clearedCount: 8, deep: true);
    controller.openDeepPreparation();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.state.shellView, ExpeditionShellView.preparation);

    expect(controller.goBackInShell(), isTrue);
    expect(controller.state.shellView, ExpeditionShellView.hub);
  });

  testWidgets('아직 만들지 않은 길은 자물쇠가 아니라 준비 중으로 알린다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpShell(tester, clearedCount: 8, deep: true);

    // 지역을 다 깨도 열리지 않는다. `조건을 채우면 열린다`고 약속하지 않는다.
    expect(find.text('합동 수호전'), findsOneWidget);
    expect(find.text('장거리 개척'), findsOneWidget);
    expect(find.text('아직 만들고 있어요.'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('hub-entry-합동 수호전')), findsNothing);
    expect(find.byKey(const ValueKey('hub-entry-장거리 개척')), findsNothing);

    // 순찰은 탐험 탭이 들고 있으므로 여기서는 진입만 열려 있다.
    expect(find.byKey(const ValueKey('hub-entry-자동 순찰')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
