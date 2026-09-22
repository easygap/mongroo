import 'dart:ui' as ui;

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

ExpeditionCatalog _catalog({
  bool heartResonance = true,
  bool deep = false,
  bool? diaryReady,
}) =>
    ExpeditionCatalog.fromJson({
      'content_version': '2026.08.4',
      'active_run_id': null,
      'entry': {
        'diary_ready': diaryReady ?? heartResonance,
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
  final List<int> seenStories = [];

  @override
  Future<void> markStageStorySeen(int stageNo) async {
    seenStories.add(stageNo);
  }

  /// 실제로 떠난 모드. 허브에서 한 번에 들어가는 길이 생기면서, 어디로 갔는지가
  /// 아니라 **떠났는지**가 검사의 관심사가 됐다.
  final List<String> startedModes = [];

  @override
  Future<bool> start(String mode) async {
    startedModes.add(mode);
    return true;
  }

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
  String regionCode = 'moss_archive',
  bool? diaryReady,
  ExpeditionShellView shellView = ExpeditionShellView.hub,
  int? selectedStageNo,
}) async {
  late _FakeStageController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expeditionControllerProvider.overrideWith(() {
          controller = _FakeStageController(
            ExpeditionUiState(
              loading: false,
              catalog: _catalog(
                heartResonance: heartResonance,
                deep: deep,
                diaryReady: diaryReady,
              ),
              shellView: shellView,
              selectedStageNo: selectedStageNo,
              roster: _roster(),
              stageMap: _stageMap(
                clearedCount: clearedCount,
                regionCode: regionCode,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const ExpeditionScreen(),
      ),
    ),
  );
  await tester.pump();
  expectTapTargets(
    tester,
    screen: shellView == ExpeditionShellView.preparation ? '탐험대 편성' : '스테이지 지도',
  );
  return controller;
}

void main() {
  testWidgets('현장 수첩은 완료한 탐험의 이야기만 표시하고 펼친 기록을 저장한다', (tester) async {
    final map = ExpeditionStageMap.fromJson({
      'region': {'code': 'moss_archive', 'name': '이끼 기억서고'},
      'progress': {'total': 8, 'cleared_count': 2},
      'stages': [
        for (var no = 1; no <= 3; no++)
          {
            ..._stage(no: no, kind: 'event', cleared: no < 3),
            'story': {
              'code': 'story-$no',
              'title': no == 2 ? '지워진 주소' : '$no번째 기록',
              'caption': no == 2 ? '남은 세 글자는 온실 앞.' : '$no번째에서 찾은 이야기',
            },
          },
      ],
    });
    final controller =
        _FakeStageController(ExpeditionUiState(loading: false, stageMap: map));
    await tester.pumpWidget(ProviderScope(
      overrides: [expeditionControllerProvider.overrideWith(() => controller)],
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
              body: SingleChildScrollView(child: ExpeditionStoryJournal()))),
    ));
    expect(find.text('8곳 중 2곳 조사 완료'), findsOneWidget);
    expect(find.text('3. 3번째 기록'), findsNothing);
    await tester.tap(find.text('2. 지워진 주소'));
    await tester.pumpAndSettle();
    expect(find.text('남은 세 글자는 온실 앞.'), findsOneWidget);
    expect(controller.seenStories, [2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('탐험에 들어오면 여덟 장소와 대원이 있는 지도가 먼저 보인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpShell(tester, clearedCount: 2);
    final world = find.byKey(const ValueKey('expedition-world-map'));
    expect(tester.getSize(world).height, greaterThan(650));
    for (var no = 1; no <= 8; no++) {
      expect(find.byKey(ValueKey('stage-point-$no')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('atlas-party-leader')), findsOneWidget);
    expect(
        tester.getSize(find.byKey(const ValueKey('atlas-party-leader'))).height,
        greaterThanOrEqualTo(80));
    expect(find.text('3번째 자리'), findsOneWidget);
    expect(find.text('3번째 자리에서 벌어지는 일이에요.'), findsNothing);
    expect(find.text('깊은 조사'), findsNothing);
    expect(find.text('오늘의 탐험 보상을 받을 수 있습니다.'), findsNothing);
    expect(find.text('탐험하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('첫 탐험 장소는 아래 출발 메뉴에 가리지 않고 누를 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpShell(tester, clearedCount: 0);
    await tester.pumpAndSettle();
    final firstPlace = find.byKey(const ValueKey('stage-point-1'));
    final dock = find.byKey(const ValueKey('atlas-departure-dock'));
    expect(
        tester.getRect(firstPlace).bottom, lessThan(tester.getRect(dock).top));
    expect(firstPlace.hitTestable(), findsOneWidget);
    await tester.tap(firstPlace);
    await tester.pump();
    expect(find.text('1번째 자리'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('보상과 잠긴 탐험의 조건은 다른 탐험을 열었을 때 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpShell(tester, heartResonance: false);
    await tester.tap(find.byKey(const ValueKey('atlas-routes')));
    await tester.pumpAndSettle();
    expect(
        find.text('지금 바로 탐험할 수 있습니다. 일기를 쓴 날에는 추가 보상을 받습니다.'), findsOneWidget);
    expect(find.text('기억서고 8까지 완주하면 열려요.'), findsOneWidget);
    expect(find.byType(Badge), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 편성 화면은 오래 `마음 공명 = 일기 안 씀`으로만 읽었다. 서버는 `diary_ready`를
  // 따로 주는데 화면이 둘을 하나로 묶어, 오늘 일기를 쓰고 한 번 다녀온 사람에게
  // 일기를 쓰라고 다시 시켰다. 두 사유를 갈라 놓는다.
  for (final ready in [false, true]) {
    testWidgets('일일 보상 여부 $ready: 하나의 출발 버튼이 알맞은 탐험을 시작한다', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _pumpShell(
        tester,
        heartResonance: ready,
        diaryReady: ready,
        shellView: ExpeditionShellView.preparation,
        selectedStageNo: 2,
      );
      final start = find.byKey(const ValueKey('prep-start-expedition'));
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pump();
      expect(controller.startedModes,
          [ready ? 'heart_resonance' : 'free_explore']);
      expect(find.text('보상 없이 자유 탐험'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('오늘 몫을 받았어도 출발할 수 있고 보상 안내에서 상태를 확인한다', (tester) async {
    final controller = await _pumpShell(tester,
        heartResonance: false,
        diaryReady: true,
        shellView: ExpeditionShellView.preparation,
        selectedStageNo: 2);
    await tester.tap(find.byKey(const ValueKey('prep-start-expedition')));
    await tester.pump();
    expect(controller.startedModes, ['free_explore']);
    await tester.ensureVisible(find.text('보상 안내'));
    await tester.tap(find.text('보상 안내'));
    await tester.pumpAndSettle();
    expect(find.textContaining('오늘의 일일 보상은 받았습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('지도 표식을 누르면 해당 장소를 살펴보고 편성으로 출발한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _pumpShell(tester, clearedCount: 2);
    await tester.tap(find.byKey(const ValueKey('stage-point-3')));
    await tester.pumpAndSettle();
    expect(find.text('3번째 자리'), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-sheet-start')), findsNothing);
    await tester.tap(find.text('살펴보기'));
    await tester.pumpAndSettle();
    expect(find.text('기억서고 3 · 3번째 자리'), findsOneWidget);
    expect(find.text('약 1분 15초'), findsOneWidget);
    expect(find.text('약점 관찰'), findsOneWidget);
    expect(find.text('엉킨 장부 뭉치'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('stage-sheet-start')));
    await tester.tap(find.byKey(const ValueKey('stage-sheet-start')));
    await tester.pumpAndSettle();
    expect(controller.state.shellView, ExpeditionShellView.preparation);
    expect(controller.state.selectedStageNo, 3);
    expect(
        find.byKey(const ValueKey('stage-preparation-header')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('잠긴 장소도 지도에서 살펴볼 수 있지만 출발할 수 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _pumpShell(tester, clearedCount: 1);
    final destination = find.byKey(const ValueKey('stage-point-5'));
    await Scrollable.ensureVisible(tester.element(destination), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(destination);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stage-sheet-start')), findsNothing);
    expect(find.text('기억서고 4를 먼저 완주하면 열려요.'), findsOneWidget);
    expect(controller.startedModes, isEmpty);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('hub-continue-card')))
            .onPressed,
        isNull);
    expect(
        find.ancestor(
            of: find.text('기억서고 4를 먼저 완주하면 열려요.'),
            matching: find.byType(Opacity)),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('지도를 확대해도 선택 장소와 출발 버튼을 누를 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpShell(tester, clearedCount: 3);
    await tester.tap(find.byKey(const ValueKey('atlas-zoom')));
    await tester.pumpAndSettle();
    final selected = find.byKey(const ValueKey('stage-point-4'));
    expect(selected.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('hub-continue-card')).hitTestable(),
        findsOneWidget);
    final horizontal = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('atlas-horizontal-view')));
    expect(horizontal.controller!.position.maxScrollExtent, greaterThan(100));
    await tester.tap(selected);
    await tester.pump();
    expect(find.text('4번째 자리'), findsOneWidget);
    final beforePan = horizontal.controller!.offset;
    final gesture = await tester.startGesture(const Offset(100, 380),
        kind: ui.PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(126, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(horizontal.controller!.offset, lessThan(beforePan));
    expect(find.text('4번째 자리'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('대원 버튼에서 편성하고 돌아오면 같은 지도를 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _pumpShell(tester, clearedCount: 2);
    await tester.tap(find.byKey(const ValueKey('hub-choose-stage')));
    await tester.pumpAndSettle();
    expect(controller.state.shellView, ExpeditionShellView.preparation);
    expect(controller.state.selectedStageNo, 3);
    await tester.tap(find.byKey(const ValueKey('stage-preparation-back')));
    await tester.pumpAndSettle();
    expect(controller.state.shellView, ExpeditionShellView.stageMap);
    expect(find.byKey(const ValueKey('expedition-world-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('stage-point-3')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 720),
    const Size(390, 844),
    const Size(1280, 900)
  ]) {
    testWidgets('지도는 ${size.width}px와 200% 글자에서도 동작한다', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _FakeStageController(ExpeditionUiState(
          loading: false,
          catalog: _catalog(),
          roster: _roster(),
          stageMap: _stageMap(clearedCount: 2),
          selectedPlantIds: const {11}));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            expeditionControllerProvider.overrideWith(() => controller)
          ],
          child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!),
              home: const ExpeditionScreen())));
      await tester.pump();
      expect(find.byKey(const ValueKey('hub-continue-card')), findsOneWidget);
      expectTapTargets(tester, screen: '그림 지도');
      expect(tester.takeException(), isNull);
      controller.openStageMap();
      await tester.pump();
      expect(find.byKey(const ValueKey('stage-point-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('지역을 완주하면 지도에서 다음 지역의 그림으로 이동한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller =
        await _pumpShell(tester, clearedCount: 8, echoWellUnlocked: true);
    await tester.tap(find.byKey(const ValueKey('atlas-regions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('region-chip-echo_well')));
    await tester.pumpAndSettle();
    expect(controller.selectedRegions, ['echo_well']);
    expect(controller.state.stageMap?.region.code, 'echo_well');
    expect(find.text('우물정원'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('잠긴 지역의 조건을 읽을 수 있고 눌러도 현재 지도를 바꾸지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _pumpShell(tester, clearedCount: 3);
    await tester.tap(find.byKey(const ValueKey('atlas-regions')));
    await tester.pumpAndSettle();
    expect(find.text('앞 지역을 완주하면 열려요.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('region-chip-echo_well')));
    await tester.pump();
    expect(controller.selectedRegions, isEmpty);
    expect(controller.state.stageMap?.region.code, 'moss_archive');
    expect(tester.takeException(), isNull);
  });

  testWidgets('다른 탐험에서 깊은 조사를 누르면 편성까지 이어진다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _pumpShell(tester, clearedCount: 8, deep: true);
    await tester.tap(find.byKey(const ValueKey('atlas-routes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hub-entry-깊은 조사')));
    await tester.pumpAndSettle();
    expect(controller.state.shellView, ExpeditionShellView.preparation);
    expect(controller.state.selectedStageNo, isNull);
    expect(find.byKey(const ValueKey('prep-start-deep')), findsOneWidget);
    expect(controller.goBackInShell(), isTrue);
    expect(controller.state.shellView, ExpeditionShellView.hub);
    expect(tester.takeException(), isNull);
  });

  testWidgets('일반 스테이지 편성에는 깊은 조사 버튼이 없다', (tester) async {
    final controller = await _pumpShell(tester, clearedCount: 8, deep: true);
    controller.openStagePreparation(3);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prep-start-deep')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final cleared in [2, 8]) {
    testWidgets('합동 수호전과 개척의 실제 해금 조건을 유지한다: $cleared', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester, clearedCount: cleared, deep: cleared == 8);
      await tester.tap(find.byKey(const ValueKey('atlas-routes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hub-entry-합동 수호전')),
          cleared == 8 ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('hub-entry-장거리 개척')), findsNothing);
      expect(find.text('우물정원을 완주하면 온실 밖으로 나가는 길이 열려요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('hub-entry-자동 순찰')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('우물정원을 완주한 뒤에는 개척 입구가 열린다', (tester) async {
    await _pumpShell(tester,
        clearedCount: 8, deep: true, regionCode: 'echo_well');
    await tester.tap(find.byKey(const ValueKey('atlas-routes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hub-entry-장거리 개척')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final cleared in [0, 2]) {
    testWidgets('지도 출발은 첫 방문이면 편성, 재방문이면 바로 탐험: $cleared', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _pumpShell(tester, clearedCount: cleared);
      await tester.tap(find.byKey(const ValueKey('hub-continue-card')));
      await tester.pump();
      expect(controller.startedModes,
          cleared == 0 ? isEmpty : ['heart_resonance']);
      expect(controller.state.selectedStageNo, cleared + 1);
      expect(
          controller.state.shellView,
          cleared == 0
              ? ExpeditionShellView.preparation
              : ExpeditionShellView.hub);
      expect(tester.takeException(), isNull);
    });
  }
}
