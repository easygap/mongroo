import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/core/theme/mongroo_ui.dart';
import 'package:mongroo/features/auth/domain/user.dart';
import 'package:mongroo/features/auth/presentation/auth_controller.dart';
import 'package:mongroo/features/garden/presentation/garden_controller.dart';
import 'package:mongroo/features/home/data/plant_repository.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/home/presentation/home_controller.dart';
import 'package:mongroo/features/home/presentation/home_screen.dart';

class _SignedInAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.signedIn,
        user: User(
          id: 1,
          email: 'harvest@example.com',
          nickname: '하루',
          timezone: 'Asia/Seoul',
          seedBalance: 20,
          streakDays: 3,
        ),
      );
}

class _IdleFarmController extends FarmController {
  @override
  FarmUiState build() => const FarmUiState();
}

class _DelayedHarvestRepository extends PlantRepository {
  _DelayedHarvestRepository(this.plant) : super(Dio());

  final ActivePlant plant;
  final Completer<void> harvestGate = Completer<void>();
  int harvestCalls = 0;
  int speciesCalls = 0;
  bool harvested = false;

  @override
  Future<ActivePlant?> getActivePlant() async => harvested ? null : plant;

  @override
  Future<void> harvest({
    required int plantId,
    required String idempotencyKey,
  }) async {
    harvestCalls++;
    await harvestGate.future;
    harvested = true;
  }

  @override
  Future<List<PlantSpecies>> getSpecies() async {
    speciesCalls++;
    return const [PlantSpecies(id: 1, code: 'mood_seed', name: '마음씨앗')];
  }
}

class _DelayedCreateRepository extends PlantRepository {
  _DelayedCreateRepository(this.plant) : super(Dio());

  final ActivePlant plant;
  final Completer<void> createGate = Completer<void>();
  int createCalls = 0;
  bool created = false;

  @override
  Future<ActivePlant?> getActivePlant() async => created ? plant : null;

  @override
  Future<ActivePlant> createPlant({int? speciesId, String? name}) async {
    createCalls++;
    await createGate.future;
    created = true;
    return plant;
  }
}

ActivePlant _harvestablePlant() => ActivePlant(
      id: 7,
      name: '햇살이',
      species: const PlantSpecies(
        id: 1,
        code: 'mood_seed',
        name: '마음씨앗',
      ),
      exp: 1000,
      stage: 5,
      stageThresholds: const [0, 100, 300, 600, 1000],
      nextStageExp: null,
      harvestable: true,
      plantedAt: DateTime.utc(2026, 7, 1),
      growthForm: PlantGrowthForm.sunny,
      branchStatus: PlantBranchStatus.stable,
      branchPhase: PlantBranchPhase.branched,
      growthPhase: PlantGrowthPhase.fullBloom,
      profileState: PlantProfileState.ready,
      emotionProfile: const ActivePlantEmotionProfile(
        total: 3,
        counts: {'joy': 3},
        ratios: {'joy': 1},
      ),
      visualKey: 'stage_5_sunny',
    );

void main() {
  test('새 식물 심기 연속 호출은 진행 중인 한 요청을 함께 기다린다', () async {
    final repository = _DelayedCreateRepository(_harvestablePlant());
    final container = ProviderContainer(
      overrides: [plantRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(homeControllerProvider.future);

    final controller = container.read(homeControllerProvider.notifier);
    final first = controller.plantNew(speciesId: 1, name: '햇살이');
    final second = controller.plantNew(speciesId: 1, name: '햇살이');
    await Future<void>.delayed(Duration.zero);

    expect(repository.createCalls, 1);
    repository.createGate.complete();
    expect(await first, isNull);
    expect(await second, isNull);
    expect(repository.createCalls, 1);
  });

  testWidgets('지연된 수확 중 연속 탭은 요청과 완료 흐름을 한 번만 실행한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _DelayedHarvestRepository(_harvestablePlant());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plantRepositoryProvider.overrideWithValue(repository),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          farmControllerProvider.overrideWith(_IdleFarmController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 화분이 있을 때와 비었을 때의 인사 부제가 달라야 한다.
    expect(find.text('한 줄만 남겨도 지금 키우는 식물이 반응해요.'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('박물관으로 보내기'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, '박물관으로 보내기'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '수확하기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.harvestCalls, 1);
    expect(find.text('박물관으로 보내는 중'), findsOneWidget);

    await tester.tap(find.text('박물관으로 보내는 중'));
    await tester.tap(find.text('박물관으로 보내는 중'));
    await tester.pump();

    expect(repository.harvestCalls, 1);
    expect(find.widgetWithText(FilledButton, '수확하기'), findsNothing);

    repository.harvestGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.harvestCalls, 1);
    expect(repository.speciesCalls, 0);
    expect(find.text('햇살이의 이야기를 보관했어요'), findsOneWidget);
    expect(find.text('박물관에 식물이 도착했어요.'), findsOneWidget);
    // 수확한 뒤에는 화분이 비어 있다. 없는 식물을 가리키면 안 된다.
    expect(find.text('한 줄만 남겨도 지금 키우는 식물이 반응해요.'), findsNothing);
    expect(
      find.text('새 씨앗을 심으면 오늘 적은 한 줄부터 함께 자라요.'),
      findsOneWidget,
    );

    await tester.tap(find.text('다음 식물 심기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.speciesCalls, 1);
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '이 씨앗 심기'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(TextButton, '나중에'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.harvestCalls, 1);
    expect(repository.speciesCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '새 식물 심기'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('레일이 서는 폭에서는 앱바에 브랜드를 또 그리지 않는다', (tester) async {
    // 데스크톱에서는 왼쪽 레일 머리에 이미 몽그루가 있다. 홈 앱바의
    // 워드마크까지 그리면 한 화면에 브랜드가 두 번 나온다.
    final repository = _DelayedHarvestRepository(_harvestablePlant());
    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plantRepositoryProvider.overrideWithValue(repository),
            authControllerProvider.overrideWith(_SignedInAuthController.new),
            farmControllerProvider.overrideWith(_IdleFarmController.new),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    addTearDown(tester.view.reset);

    await pumpAt(const Size(390, 844));
    expect(find.text('몽그루'), findsOneWidget);
    expect(find.text('오늘'), findsNothing);

    await pumpAt(const Size(1280, 900));
    expect(find.text('몽그루'), findsNothing);
    expect(find.text('오늘'), findsOneWidget);
  });

  testWidgets('빈 화분 카드는 다른 카드와 같은 너비로 선다', (tester) async {
    // 패널 안 Column이 폭을 안 잡아서 가장 넓은 자식(버튼)만큼만 커졌다.
    // 같은 화면의 다른 카드는 전부 전체 너비라 이 카드만 반쪽으로 보인다.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plantRepositoryProvider
              .overrideWithValue(_DelayedCreateRepository(_harvestablePlant())),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          farmControllerProvider.overrideWith(_IdleFarmController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final card = find.ancestor(
      of: find.text('화분이 비어 있어요.'),
      matching: find.byType(MongrooPanel),
    );
    expect(card, findsWidgets);
    final cardWidth = tester.getSize(card.first).width;
    // 390px 화면에서 좌우 여백을 빼도 300은 넘어야 한다. 고치기 전에는
    // 버튼 폭을 따라 170 언저리였다.
    expect(cardWidth, greaterThan(300), reason: '카드가 반쪽으로 섰습니다');
  });
}
