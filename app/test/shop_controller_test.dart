import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/auth/domain/user.dart';
import 'package:mongroo/features/auth/presentation/auth_controller.dart';
import 'package:mongroo/features/garden/data/garden_repository.dart';
import 'package:mongroo/features/garden/domain/garden_models.dart';
import 'package:mongroo/features/garden/presentation/garden_controller.dart';

ShopItem _theme({required bool eligible}) => ShopItem(
      id: 70,
      code: 'room_fox_shrine',
      type: 'room_theme',
      name: '별여우 신사',
      description: '별빛이 머무는 여우 신사',
      priceSeeds: 0,
      rarity: 4,
      assetManifest: const {'asset_key': 'room/fox_star_shrine'},
      owned: false,
      acquisition: ShopItemAcquisition(
        type: 'own_item',
        label: '구미호 화분 보유',
        current: eligible ? 1 : 0,
        target: 1,
        eligible: eligible,
      ),
    );

class _ClaimRepository extends GardenRepository {
  _ClaimRepository({required this.eligible}) : super(Dio());

  final bool eligible;
  int claimCalls = 0;
  int purchaseCalls = 0;
  String? claimKey;

  @override
  Future<ShopCatalog> getShopItems() async => ShopCatalog(
        items: [_theme(eligible: eligible)],
        seedBalance: 15,
      );

  @override
  Future<ShopPurchaseResult> purchase({
    required int itemId,
    required String idempotencyKey,
  }) async {
    purchaseCalls++;
    throw StateError('조건형 상품은 purchase를 호출하면 안 됩니다.');
  }

  @override
  Future<ShopPurchaseResult> claim({
    required int itemId,
    required String idempotencyKey,
  }) async {
    claimCalls++;
    claimKey = idempotencyKey;
    final item = _theme(eligible: true).copyWith(owned: true);
    return ShopPurchaseResult(
      userItem: UserGardenItem(id: 170, item: item),
      seedBalance: 15,
      acquisition: const ShopItemAcquisition(
        type: 'own_item',
        label: '구미호 화분 보유',
        current: 1,
        target: 1,
        eligible: false,
      ),
    );
  }

  @override
  Future<FarmData> getFarm() async => const FarmData(
        layout: FarmLayout(
          version: 1,
          companionUserItemIds: [],
          decorations: [],
        ),
        ownedItems: [],
      );
}

class _DependencyRepository extends GardenRepository {
  _DependencyRepository() : super(Dio());

  bool gumihoOwned = false;
  int getShopCalls = 0;

  ShopItem get _gumiho => ShopItem(
        id: 60,
        code: 'character_gumiho_pot',
        type: 'main_character',
        name: '여우비',
        description: '비밀 이야기를 좋아하는 장난꾸러기',
        priceSeeds: 240,
        rarity: 4,
        assetManifest: const {'asset_key': 'characters/gumiho-pot'},
        owned: gumihoOwned,
        acquisition: ShopItemAcquisition(
          type: 'purchase',
          label: '씨앗으로 구매',
          current: 300,
          target: 240,
          eligible: !gumihoOwned,
        ),
      );

  ShopItem get _dependentTheme => ShopItem(
        id: 70,
        code: 'room_fox_shrine',
        type: 'room_theme',
        name: '별여우 신사',
        description: '별빛이 머무는 여우 신사',
        priceSeeds: 0,
        rarity: 4,
        assetManifest: const {'asset_key': 'room/fox_star_shrine'},
        owned: false,
        acquisition: ShopItemAcquisition(
          type: 'own_item',
          label: '구미호 화분 보유',
          current: gumihoOwned ? 1 : 0,
          target: 1,
          eligible: gumihoOwned,
        ),
      );

  @override
  Future<ShopCatalog> getShopItems() async {
    getShopCalls++;
    return ShopCatalog(
      items: [_gumiho, _dependentTheme],
      seedBalance: gumihoOwned ? 60 : 300,
    );
  }

  @override
  Future<ShopPurchaseResult> purchase({
    required int itemId,
    required String idempotencyKey,
  }) async {
    gumihoOwned = true;
    return ShopPurchaseResult(
      userItem: UserGardenItem(id: 160, item: _gumiho),
      seedBalance: 60,
    );
  }

  @override
  Future<FarmData> getFarm() async => const FarmData(
        layout: FarmLayout(
          version: 1,
          companionUserItemIds: [],
          decorations: [],
        ),
        ownedItems: [],
      );
}

class _SignedInAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.signedIn,
        user: User(
          id: 1,
          email: 'tester@example.com',
          nickname: '테스터',
          timezone: 'Asia/Seoul',
          seedBalance: 99,
          streakDays: 3,
        ),
      );
}

Future<ProviderContainer> _container(GardenRepository repository) async {
  final container = ProviderContainer(
    overrides: [
      gardenRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(_SignedInAuthController.new),
    ],
  );
  container.read(shopControllerProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await container.read(farmControllerProvider.notifier).load();
  return container;
}

void main() {
  test('조건을 달성한 상품은 claim하고 보유 목록과 카탈로그를 함께 갱신한다', () async {
    final repository = _ClaimRepository(eligible: true);
    final container = await _container(repository);
    addTearDown(container.dispose);

    final controller = container.read(shopControllerProvider.notifier);
    expect(await controller.purchase(70), isNull);
    final result = await controller.claim(70);

    expect(result, isNotNull);
    expect(repository.purchaseCalls, 0);
    expect(repository.claimCalls, 1);
    expect(repository.claimKey, isNotEmpty);
    expect(
      container
          .read(shopControllerProvider)
          .catalog
          .valueOrNull
          ?.items
          .single
          .owned,
      isTrue,
    );
    expect(
      container
          .read(farmControllerProvider)
          .data
          .valueOrNull
          ?.ownedItems
          .single
          .id,
      170,
    );
    expect(
      container.read(authControllerProvider).user?.seedBalance,
      15,
    );
  });

  test('획득 조건을 채우지 못한 상품은 claim 요청을 보내지 않는다', () async {
    final repository = _ClaimRepository(eligible: false);
    final container = await _container(repository);
    addTearDown(container.dispose);

    final result =
        await container.read(shopControllerProvider.notifier).claim(70);

    expect(result, isNull);
    expect(repository.claimCalls, 0);
    expect(
      container
          .read(shopControllerProvider)
          .catalog
          .valueOrNull
          ?.items
          .single
          .owned,
      isFalse,
    );
  });

  test('아이템 획득 뒤 의존하는 다른 테마의 조건을 로딩 깜빡임 없이 갱신한다', () async {
    final repository = _DependencyRepository();
    final container = await _container(repository);
    addTearDown(container.dispose);

    final before = container.read(shopControllerProvider).catalog.valueOrNull!;
    expect(before.items.last.canClaim, isFalse);

    final result =
        await container.read(shopControllerProvider.notifier).purchase(60);
    expect(result, isNotNull);
    expect(container.read(shopControllerProvider).catalog,
        isA<AsyncData<ShopCatalog>>());

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final refreshed =
        container.read(shopControllerProvider).catalog.valueOrNull!;
    expect(repository.getShopCalls, greaterThanOrEqualTo(2));
    expect(refreshed.items.first.owned, isTrue);
    expect(refreshed.items.last.canClaim, isTrue);
    expect(refreshed.items.last.acquisition?.progressLabel, '1/1');
  });
}
