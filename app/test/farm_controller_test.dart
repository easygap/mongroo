import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/error/api_exception.dart';
import 'package:mongroo/features/garden/data/garden_repository.dart';
import 'package:mongroo/features/garden/domain/garden_models.dart';
import 'package:mongroo/features/garden/presentation/garden_controller.dart';
import 'package:mongroo/features/garden/presentation/farm_tab.dart';

const _deco = ShopItem(
  id: 1,
  code: 'deco_cushion_leaf',
  type: 'deco',
  name: '쿠션',
  description: '',
  priceSeeds: 10,
  rarity: 1,
  assetManifest: {},
  owned: true,
);

const _purchased = UserGardenItem(
  id: 2,
  item: ShopItem(
    id: 2,
    code: 'character_ninja_pot',
    type: 'main_character',
    name: '그림싹',
    description: '',
    priceSeeds: 100,
    rarity: 3,
    assetManifest: {'asset_key': 'characters/ninja-pot'},
    owned: true,
  ),
);

const _moonLamp = UserGardenItem(
  id: 3,
  item: ShopItem(
    id: 3,
    code: 'deco_lamp_moon',
    type: 'deco',
    name: '달빛 조명',
    description: '',
    priceSeeds: 50,
    rarity: 2,
    assetManifest: {},
    owned: true,
  ),
);

const _cityNightWardrobe = UserGardenItem(
  id: 77,
  item: ShopItem(
    id: 77,
    code: 'wardrobe_city_night',
    type: 'wardrobe',
    name: '시티 나이트',
    description: '',
    priceSeeds: 180,
    rarity: 3,
    assetManifest: {
      'wardrobe_layer_key': 'city-night',
      'compatible_species': ['gumiho-pot'],
    },
    owned: true,
  ),
);

class _FarmRepository extends GardenRepository {
  _FarmRepository() : super(Dio());

  @override
  Future<FarmData> getFarm() async => const FarmData(
        layout: FarmLayout(
          version: 1,
          companionUserItemIds: [],
          decorations: [],
        ),
        ownedItems: [UserGardenItem(id: 1, item: _deco), _moonLamp],
      );
}

class _WardrobeFarmRepository extends GardenRepository {
  _WardrobeFarmRepository() : super(Dio());

  @override
  Future<FarmData> getFarm() async => const FarmData(
        layout: FarmLayout(
          version: 1,
          wardrobeUserItemId: 77,
          companionUserItemIds: [],
          decorations: [],
        ),
        ownedItems: [_cityNightWardrobe],
      );
}

class _ConflictFarmRepository extends GardenRepository {
  _ConflictFarmRepository() : super(Dio());

  int getFarmCalls = 0;
  final List<FarmLayout> updateRequests = [];

  static const initial = FarmData(
    layout: FarmLayout(
      version: 1,
      companionUserItemIds: [],
      decorations: [],
    ),
    ownedItems: [UserGardenItem(id: 1, item: _deco)],
  );

  static const latest = FarmData(
    layout: FarmLayout(
      version: 2,
      companionUserItemIds: [],
      decorations: [],
    ),
    ownedItems: [UserGardenItem(id: 1, item: _deco)],
  );

  @override
  Future<FarmData> getFarm() async => getFarmCalls++ == 0 ? initial : latest;

  @override
  Future<FarmLayout> updateFarm(FarmLayout layout) async {
    updateRequests.add(layout);
    if (updateRequests.length == 1) {
      throw const ApiException(
        code: 'FARM_LAYOUT_VERSION_CONFLICT',
        message: '다른 기기에서 방 배치가 변경되었습니다.',
        statusCode: 409,
        details: {'expected_version': 1, 'current_version': 2},
      );
    }
    return layout.copyWith(version: layout.version + 1);
  }
}

class _DelayedSaveFarmRepository extends _FarmRepository {
  final saveGate = Completer<FarmLayout>();
  final List<FarmLayout> updateRequests = [];

  @override
  Future<FarmLayout> updateFarm(FarmLayout layout) {
    updateRequests.add(layout);
    return saveGate.future;
  }
}

void main() {
  test('장착 의상 provider는 farm draft의 레이어 키를 화면에 제공한다', () async {
    final container = ProviderContainer(
      overrides: [
        gardenRepositoryProvider.overrideWithValue(_WardrobeFarmRepository()),
      ],
    );
    addTearDown(container.dispose);

    container.read(equippedWardrobeLayerKeyProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(equippedWardrobeLayerKeyProvider),
      'city-night',
    );

    container.read(farmControllerProvider.notifier).equipWardrobe(null);
    expect(container.read(equippedWardrobeLayerKeyProvider), isNull);
  });

  test('호환 의상이 없는 빈 상태는 보유 여부와 자동 해제를 구분해 안내한다', () {
    expect(
      farmWardrobeEmptyMessage(ownsWardrobe: false),
      '상점에서 캐릭터 의상을 모아 보세요.',
    );
    expect(
      farmWardrobeEmptyMessage(ownsWardrobe: true),
      allOf(contains('호환되지 않아요'), contains('장착이 해제')),
    );
    expect(farmWardrobeAutoUnequipHint, contains('자동으로 해제'));
  });

  test('선택한 의상을 편집 중인 방 배치에 반영한다', () async {
    final container = ProviderContainer(
      overrides: [
        gardenRepositoryProvider.overrideWithValue(_FarmRepository()),
      ],
    );
    addTearDown(container.dispose);

    container.read(farmControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(farmControllerProvider.notifier);
    controller.beginEditing();

    controller.equipWardrobe(77);
    expect(
      container.read(farmControllerProvider).draft?.wardrobeUserItemId,
      77,
    );

    controller.equipWardrobe(null);
    expect(
      container.read(farmControllerProvider).draft?.wardrobeUserItemId,
      isNull,
    );
  });

  test('편집 중 구매 아이템을 합쳐도 미저장 방 배치가 유지된다', () async {
    final container = ProviderContainer(
      overrides: [
        gardenRepositoryProvider.overrideWithValue(_FarmRepository()),
      ],
    );
    addTearDown(container.dispose);

    container.read(farmControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(farmControllerProvider.notifier);
    controller.beginEditing();
    controller.placeDecoration(1);
    controller.placeDecoration(3);
    final draftBefore = container.read(farmControllerProvider).draft;

    controller.mergePurchasedItem(_purchased);
    final state = container.read(farmControllerProvider);

    expect(state.editing, isTrue);
    expect(state.draft, same(draftBefore));
    expect(state.draft?.decorations, hasLength(2));
    expect(state.draft?.decorations[0].userItemId, 1);
    expect(state.draft?.decorations[0].x, 0.82);
    expect(state.draft?.decorations[0].y, 0.80);
    expect(state.draft?.decorations[1].userItemId, 3);
    expect(state.draft?.decorations[1].x, 0.82);
    expect(state.draft?.decorations[1].y, 0.14);
    expect(state.data.valueOrNull?.ownedItems, hasLength(3));
    expect(state.data.valueOrNull?.equippedMainCharacter, isNull);
  });

  testWidgets('저장 중에는 방 조작과 draft 변경을 모두 막는다', (tester) async {
    final repository = _DelayedSaveFarmRepository();
    final container = ProviderContainer(
      overrides: [gardenRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: FarmTab())),
      ),
    );
    await tester.pumpAndSettle();

    final controller = container.read(farmControllerProvider.notifier);
    controller.beginEditing();
    controller.placeDecoration(1);
    await tester.pump();
    final draftAtRequest = container.read(farmControllerProvider).draft!;

    final save = controller.save();
    await tester.pump();

    expect(repository.updateRequests, hasLength(1));
    expect(container.read(farmControllerProvider).saving, isTrue);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '달빛 조명'),
          )
          .onPressed,
      isNull,
    );

    controller.placeDecoration(3);
    controller.moveDecoration(1, x: 0.1, y: 0.2);
    controller.cancelEditing();

    final duringSave = container.read(farmControllerProvider);
    expect(duringSave.draft, same(draftAtRequest));
    expect(duringSave.editing, isTrue);
    expect(duringSave.draft?.decorations, hasLength(1));
    expect(duringSave.draft?.decorations.single.userItemId, 1);
    expect(duringSave.draft?.decorations.single.x, 0.82);
    expect(duringSave.draft?.decorations.single.y, 0.80);

    repository.saveGate.complete(
      repository.updateRequests.single.copyWith(version: 2),
    );
    expect(await save, isTrue);
    await tester.pump();

    final saved = container.read(farmControllerProvider);
    expect(saved.saving, isFalse);
    expect(saved.editing, isFalse);
    expect(saved.draft?.decorations, hasLength(1));
    expect(saved.draft?.decorations.single.userItemId, 1);
  });

  test('version 충돌 시 서버 최신본을 받아도 로컬 방 초안을 보존한다', () async {
    final repository = _ConflictFarmRepository();
    final container = ProviderContainer(
      overrides: [gardenRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    container.read(farmControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(farmControllerProvider.notifier);
    controller.placeDecoration(1);
    final localDraft = container.read(farmControllerProvider).draft;

    expect(await controller.save(), isFalse);
    final conflicted = container.read(farmControllerProvider);

    expect(conflicted.editing, isTrue);
    expect(conflicted.saving, isFalse);
    expect(conflicted.draft, same(localDraft));
    expect(conflicted.draft?.decorations.single.userItemId, 1);
    expect(conflicted.draft?.version, 1);
    expect(conflicted.data.valueOrNull?.layout.version, 2);
    expect(conflicted.conflict?.latestLayout.version, 2);

    controller.useLatestLayout();
    final latest = container.read(farmControllerProvider);
    expect(latest.conflict, isNull);
    expect(latest.editing, isFalse);
    expect(latest.draft?.version, 2);
    expect(latest.draft?.decorations, isEmpty);
  });

  test('충돌 후 내 배치 다시 저장은 최신 version 위에 보존 초안을 재시도한다', () async {
    final repository = _ConflictFarmRepository();
    final container = ProviderContainer(
      overrides: [gardenRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    container.read(farmControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final controller = container.read(farmControllerProvider.notifier);
    controller.placeDecoration(1);

    expect(await controller.save(), isFalse);
    expect(await controller.retryConflict(), isTrue);

    expect(repository.updateRequests, hasLength(2));
    expect(repository.updateRequests[0].version, 1);
    expect(repository.updateRequests[1].version, 2);
    expect(repository.updateRequests[1].decorations.single.userItemId, 1);

    final saved = container.read(farmControllerProvider);
    expect(saved.conflict, isNull);
    expect(saved.editing, isFalse);
    expect(saved.draft?.version, 3);
    expect(saved.draft?.decorations.single.userItemId, 1);
  });

  testWidgets('작은 화면에서도 충돌 원인과 두 복구 선택지를 함께 보여준다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _ConflictFarmRepository();
    final container = ProviderContainer(
      overrides: [gardenRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: FarmTab())),
      ),
    );
    await tester.pumpAndSettle();

    final controller = container.read(farmControllerProvider.notifier);
    controller.placeDecoration(1);
    expect(await controller.save(), isFalse);
    await tester.pumpAndSettle();

    expect(find.text('방이 다른 기기에서 바뀌었어요'), findsOneWidget);
    expect(find.textContaining('지금 꾸민 배치는 안전하게 보관했어요'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '최신 배치 불러오기'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '내 배치 다시 저장'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, '내 배치 다시 저장'));
    await tester.pumpAndSettle();

    expect(find.text('방이 다른 기기에서 바뀌었어요'), findsNothing);
    expect(container.read(farmControllerProvider).draft?.version, 3);
    expect(find.text('보관한 내 배치로 방을 저장했어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
