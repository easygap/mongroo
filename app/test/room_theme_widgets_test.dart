import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/auth/domain/user.dart';
import 'package:mongroo/features/auth/presentation/auth_controller.dart';
import 'package:mongroo/features/garden/data/garden_repository.dart';
import 'package:mongroo/features/garden/domain/garden_models.dart';
import 'package:mongroo/features/garden/presentation/farm_tab.dart';
import 'package:mongroo/features/garden/presentation/garden_item_visual.dart';
import 'package:mongroo/features/garden/presentation/shop_tab.dart';

const _sunnyTheme = ShopItem(
  id: 10,
  code: 'room_sunny',
  type: 'room_theme',
  name: '햇살 온실',
  description: '따뜻한 오후 햇살이 머무는 온실',
  priceSeeds: 100,
  rarity: 2,
  assetManifest: {'asset_key': 'room/sunny_greenhouse'},
  owned: true,
);

const _layerMain = UserGardenItem(
  id: 201,
  item: ShopItem(
    id: 201,
    code: 'character_baby_pot',
    type: 'main_character',
    name: '아기 화분',
    description: '',
    priceSeeds: 0,
    rarity: 2,
    assetManifest: {'asset_key': 'characters/baby-pot'},
    owned: true,
  ),
);

const _layerCompanion = UserGardenItem(
  id: 202,
  item: ShopItem(
    id: 202,
    code: 'companion_dewdrop',
    type: 'companion',
    name: '이슬이',
    description: '',
    priceSeeds: 0,
    rarity: 2,
    assetManifest: {'asset_key': 'companion/dewdrop'},
    owned: true,
  ),
);

const _layerCushion = UserGardenItem(
  id: 203,
  item: ShopItem(
    id: 203,
    code: 'deco_cushion_leaf',
    type: 'deco',
    name: '잎새 쿠션',
    description: '',
    priceSeeds: 0,
    rarity: 1,
    assetManifest: {'asset_key': 'deco/cushion_leaf'},
    owned: true,
  ),
);

const _layerRug = UserGardenItem(
  id: 204,
  item: ShopItem(
    id: 204,
    code: 'deco_rug_cloud',
    type: 'deco',
    name: '구름 러그',
    description: '',
    priceSeeds: 0,
    rarity: 2,
    assetManifest: {'asset_key': 'deco/rug_cloud'},
    owned: true,
  ),
);

const _layerLamp = UserGardenItem(
  id: 205,
  item: ShopItem(
    id: 205,
    code: 'deco_lamp_moon',
    type: 'deco',
    name: '달빛 조명',
    description: '',
    priceSeeds: 0,
    rarity: 2,
    assetManifest: {'asset_key': 'deco/lamp_moon'},
    owned: true,
  ),
);

class _LayerFarmRepository extends GardenRepository {
  _LayerFarmRepository() : super(Dio());

  @override
  Future<FarmData> getFarm() async => const FarmData(
        layout: FarmLayout(
          version: 1,
          mainCharacterUserItemId: 201,
          companionUserItemIds: [202],
          decorations: [
            FarmDecoration(
              userItemId: 203,
              x: .12,
              y: .2,
              scale: 1,
              rotation: 0,
              zIndex: 0,
            ),
            FarmDecoration(
              userItemId: 205,
              x: .8,
              y: .18,
              scale: 1,
              rotation: 0,
              zIndex: 2,
            ),
            FarmDecoration(
              userItemId: 204,
              x: .42,
              y: .75,
              scale: 1.4,
              rotation: 0,
              zIndex: 9,
            ),
          ],
        ),
        ownedItems: [
          _layerMain,
          _layerCompanion,
          _layerCushion,
          _layerRug,
          _layerLamp,
        ],
      );
}

class _PreviewRepository extends GardenRepository {
  _PreviewRepository() : super(Dio());

  @override
  Future<ShopCatalog> getShopItems() async => ShopCatalog(
        seedBalance: 20,
        items: [
          ShopItem(
            id: 71,
            code: 'room_magic_atelier',
            type: 'room_theme',
            name: '마법 공방',
            description: '마음의 색을 섞는 비밀 공방',
            priceSeeds: 0,
            rarity: 4,
            assetManifest: const {'asset_key': 'room/magic_atelier'},
            owned: false,
            acquisition: const ShopItemAcquisition(
              type: 'quest_count',
              label: '작은 행동 5회 완료',
              current: 2,
              target: 5,
              eligible: false,
            ),
          ),
        ],
      );
}

class _PreviewAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.signedIn,
        user: User(
          id: 1,
          email: 'preview@example.com',
          nickname: '미리보기',
          timezone: 'Asia/Seoul',
          seedBalance: 20,
          streakDays: 2,
        ),
      );
}

void main() {
  void useSmallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('획득 조건 패널은 큰 글자와 작은 화면에서도 진행률을 읽어 준다', (tester) async {
    useSmallScreen(tester);
    final semantics = tester.ensureSemantics();
    final item = ShopItem(
      id: 71,
      code: 'room_magic_atelier',
      type: 'room_theme',
      name: '마법 공방',
      description: '마음의 색을 섞는 비밀 공방',
      priceSeeds: 0,
      rarity: 4,
      assetManifest: const {'asset_key': 'room/magic_atelier'},
      owned: false,
      acquisition: const ShopItemAcquisition(
        type: 'quest_count',
        label: '작은 행동 5회 완료',
        current: 2,
        target: 5,
        eligible: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ShopAcquisitionPanel(item: item, balance: 20),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('작은 행동 5회 완료'), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);
    expect(
      find.bySemanticsLabel('획득 조건, 작은 행동 5회 완료, 2/5'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('마이룸 테마 선택기는 큰 글자에서 한 열로 바뀌고 썸네일로 선택한다', (tester) async {
    useSmallScreen(tester);
    final semantics = tester.ensureSemantics();
    int? selected = -1;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: FarmRoomThemePicker(
                themes: const [UserGardenItem(id: 110, item: _sunnyTheme)],
                selectedUserItemId: null,
                enabled: true,
                onSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final defaultNode = tester.getSemantics(
      find.bySemanticsLabel('기본 방 방 테마'),
    );
    expect(defaultNode.flagsCollection.isSelected, Tristate.isTrue);
    expect(find.byType(Image), findsWidgets);
    final defaultPreview = tester.widget<Image>(
      find.byKey(const ValueKey('farm-theme-default-preview')),
    );
    expect(
      (defaultPreview.image as ResizeImage).imageProvider,
      const AssetImage(gardenDefaultRoomAssetPath),
    );

    await tester.tap(find.text('햇살 온실'));
    await tester.pump();

    expect(selected, 110);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('바닥 장식과 낮은 z 장식을 캐릭터 뒤에 그린다', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gardenRepositoryProvider.overrideWithValue(_LayerFarmRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: FarmTab()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final codes = tester
        .widgetList<GardenItemVisual>(find.byType(GardenItemVisual))
        .map((visual) => visual.item.code)
        .toList();
    expect(
      codes.take(4),
      [
        'deco_cushion_leaf',
        'deco_rug_cloud',
        'companion_dewdrop',
        'deco_lamp_moon',
      ],
    );
    expect(codes, isNot(contains('character_baby_pot')));
    expect(
      gardenDecorationRendersBehindCharacters(_layerRug.item, 99),
      isTrue,
    );
    expect(
      gardenDecorationRendersBehindCharacters(_layerLamp.item, 2),
      isFalse,
    );
    final background = tester.widget<Image>(
      find.byKey(const ValueKey('farm-default-room')),
    );
    expect(
      (background.image as AssetImage).assetName,
      gardenDefaultRoomAssetPath,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('방 테마 프리뷰는 작은 화면·큰 글자에서도 16:9 전체 이미지를 유지한다', (tester) async {
    useSmallScreen(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gardenRepositoryProvider.overrideWithValue(_PreviewRepository()),
          authControllerProvider.overrideWith(_PreviewAuthController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: const Scaffold(body: RoomThemePreviewSheet(itemId: 71)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('마법 공방'), findsOneWidget);
    expect(find.text('작은 행동 5회 완료'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, '조건을 더 채워 주세요'),
      findsOneWidget,
    );
    final previewRatio = tester.widget<AspectRatio>(
      find.descendant(
        of: find.byType(RoomThemePreviewSheet),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(previewRatio.aspectRatio, 16 / 9);
    expect(tester.takeException(), isNull);
  });
}
