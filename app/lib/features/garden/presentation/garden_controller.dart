import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../quest/presentation/quest_controller.dart';
import '../data/garden_repository.dart';
import '../domain/garden_models.dart';

const _stateUnset = Object();

class ShopUiState {
  const ShopUiState({
    this.catalog = const AsyncLoading(),
    this.purchasingItemIds = const {},
    this.actionError,
  });

  final AsyncValue<ShopCatalog> catalog;
  final Set<int> purchasingItemIds;
  final String? actionError;

  ShopUiState copyWith({
    AsyncValue<ShopCatalog>? catalog,
    Set<int>? purchasingItemIds,
    Object? actionError = _stateUnset,
  }) =>
      ShopUiState(
        catalog: catalog ?? this.catalog,
        purchasingItemIds: purchasingItemIds ?? this.purchasingItemIds,
        actionError: actionError == _stateUnset
            ? this.actionError
            : actionError as String?,
      );
}

class ShopController extends Notifier<ShopUiState> {
  static const _uuid = Uuid();
  final Map<int, String> _purchaseKeys = {};
  final Map<int, String> _claimKeys = {};
  int _catalogRefreshRevision = 0;

  @override
  ShopUiState build() {
    Future.microtask(load);
    return const ShopUiState();
  }

  Future<void> load() async {
    final revision = ++_catalogRefreshRevision;
    state = state.copyWith(catalog: const AsyncLoading(), actionError: null);
    try {
      final catalog = await ref.read(gardenRepositoryProvider).getShopItems();
      if (revision != _catalogRefreshRevision) return;
      ref
          .read(authControllerProvider.notifier)
          .updateSeedBalance(catalog.seedBalance);
      state = state.copyWith(catalog: AsyncData(catalog));
    } on ApiException catch (error, stack) {
      if (revision != _catalogRefreshRevision) return;
      state = state.copyWith(catalog: AsyncError(error, stack));
    }
  }

  Future<ShopPurchaseResult?> purchase(int itemId) async {
    if (state.purchasingItemIds.isNotEmpty) return null;
    final catalog = state.catalog.valueOrNull;
    final item =
        catalog?.items.where((entry) => entry.id == itemId).firstOrNull;
    if (item == null || item.owned || item.requiresClaim) return null;
    if (catalog == null || catalog.seedBalance < item.priceSeeds) {
      state = state.copyWith(
        actionError: '씨앗이 부족해요. 오늘의 기록과 퀘스트로 모아 보세요.',
      );
      return null;
    }

    _setPurchasing(itemId, true);
    try {
      final key = _purchaseKeys.putIfAbsent(itemId, () => _uuid.v4());
      final result = await ref.read(gardenRepositoryProvider).purchase(
            itemId: itemId,
            idempotencyKey: key,
          );
      _purchaseKeys.remove(itemId);
      _completeAcquisition(itemId, result);
      return result;
    } on ApiException catch (error) {
      _setPurchasing(itemId, false, error: error.message);
      return null;
    }
  }

  /// 구매가 아닌 퀘스트·연속 기록·수집 조건 보상을 수령한다.
  Future<ShopPurchaseResult?> claim(int itemId) async {
    if (state.purchasingItemIds.isNotEmpty) return null;
    final catalog = state.catalog.valueOrNull;
    final item =
        catalog?.items.where((entry) => entry.id == itemId).firstOrNull;
    if (item == null || item.owned || !item.canClaim) return null;

    _setPurchasing(itemId, true);
    try {
      final key = _claimKeys.putIfAbsent(itemId, () => _uuid.v4());
      final result = await ref.read(gardenRepositoryProvider).claim(
            itemId: itemId,
            idempotencyKey: key,
          );
      _claimKeys.remove(itemId);
      _completeAcquisition(itemId, result);
      return result;
    } on ApiException catch (error) {
      _setPurchasing(itemId, false, error: error.message);
      return null;
    }
  }

  void _completeAcquisition(int itemId, ShopPurchaseResult result) {
    final current = state.catalog.valueOrNull;
    if (current != null) {
      state = state.copyWith(
        catalog: AsyncData(
          current.markOwned(
            itemId,
            result.seedBalance,
            acquisition: result.acquisition,
          ),
        ),
      );
    }
    ref
        .read(authControllerProvider.notifier)
        .updateSeedBalance(result.seedBalance);
    ref.invalidate(collectionControllerProvider);
    // 상점 획득 후 열려 있는 여정 요약만 즉시 갱신한다.
    // 미사용 provider를 새로 깨우면 화면 이탈 후 load가 실행될 수 있다.
    if (ref.exists(questControllerProvider)) {
      ref.invalidate(questControllerProvider);
    }
    ref
        .read(farmControllerProvider.notifier)
        .mergeAcquiredItem(result.userItem);
    _setPurchasing(itemId, false);
    // 한 아이템 획득은 own_item/collection_count 조건의 다른 상품도 즉시
    // 활성화할 수 있다. 성공 UI는 먼저 유지하고 카탈로그만 조용히 재계산한다.
    final revision = ++_catalogRefreshRevision;
    Future<void>.microtask(
      () => _refreshCatalogAfterAcquisition(revision),
    );
  }

  Future<void> _refreshCatalogAfterAcquisition(int revision) async {
    try {
      final refreshed = await ref.read(gardenRepositoryProvider).getShopItems();
      if (revision != _catalogRefreshRevision) return;
      final local = state.catalog.valueOrNull;
      if (local == null) return;
      final locallyOwnedIds = local.items
          .where((item) => item.owned)
          .map((item) => item.id)
          .toSet();
      final refreshedIds = refreshed.items.map((item) => item.id).toSet();
      final merged = ShopCatalog(
        items: [
          for (final item in refreshed.items)
            locallyOwnedIds.contains(item.id)
                ? item.copyWith(owned: true)
                : item,
          // 재조회가 일시적으로 오래된 응답을 주더라도 방금 얻은 아이템은
          // 화면과 보유 목록에서 사라지지 않는다.
          for (final item in local.items)
            if (item.owned && !refreshedIds.contains(item.id)) item,
        ],
        seedBalance: refreshed.seedBalance,
      );
      state = state.copyWith(catalog: AsyncData(merged));
      ref
          .read(authControllerProvider.notifier)
          .updateSeedBalance(refreshed.seedBalance);
    } catch (_) {
      // 획득 자체는 이미 성공했다. 의존 조건 갱신 실패를 성공 상태 위에
      // 덮어쓰지 않고 다음 pull-to-refresh에서 자연스럽게 재시도한다.
    }
  }

  void clearActionError() => state = state.copyWith(actionError: null);

  void _setPurchasing(int id, bool busy, {String? error}) {
    final ids = {...state.purchasingItemIds};
    busy ? ids.add(id) : ids.remove(id);
    state = state.copyWith(purchasingItemIds: ids, actionError: error);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

final shopControllerProvider =
    NotifierProvider<ShopController, ShopUiState>(ShopController.new);

class CollectionController extends AsyncNotifier<GardenCollection> {
  @override
  Future<GardenCollection> build() async {
    final collection =
        await ref.watch(gardenRepositoryProvider).getCollection();
    ref
        .read(authControllerProvider.notifier)
        .updateSeedBalance(collection.seedBalance);
    return collection;
  }
}

final collectionControllerProvider =
    AsyncNotifierProvider<CollectionController, GardenCollection>(
  CollectionController.new,
);

/// 다른 기기에서 먼저 저장된 배치와 로컬 초안을 사용자가 직접 조정하기 위한 상태.
class FarmLayoutConflict {
  const FarmLayoutConflict({required this.latestLayout});

  final FarmLayout latestLayout;
}

class FarmUiState {
  const FarmUiState({
    this.data = const AsyncLoading(),
    this.draft,
    this.conflict,
    this.editing = false,
    this.saving = false,
    this.actionError,
  });

  final AsyncValue<FarmData> data;
  final FarmLayout? draft;
  final FarmLayoutConflict? conflict;
  final bool editing;
  final bool saving;
  final String? actionError;

  FarmUiState copyWith({
    AsyncValue<FarmData>? data,
    Object? draft = _stateUnset,
    Object? conflict = _stateUnset,
    bool? editing,
    bool? saving,
    Object? actionError = _stateUnset,
  }) =>
      FarmUiState(
        data: data ?? this.data,
        draft: draft == _stateUnset ? this.draft : draft as FarmLayout?,
        conflict: conflict == _stateUnset
            ? this.conflict
            : conflict as FarmLayoutConflict?,
        editing: editing ?? this.editing,
        saving: saving ?? this.saving,
        actionError: actionError == _stateUnset
            ? this.actionError
            : actionError as String?,
      );
}

class FarmController extends Notifier<FarmUiState> {
  Future<void>? _loadFuture;

  @override
  FarmUiState build() {
    final authStatus = ref.watch(
      authControllerProvider.select((state) => state.status),
    );
    // 계정 삭제·로그아웃 뒤 세션 캐시를 비울 때 provider가 다시 생성되더라도
    // 폐기된 토큰으로 방 배치를 재조회하지 않는다.
    if (authStatus != AuthStatus.signedOut) {
      Future.microtask(load);
    }
    return const FarmUiState();
  }

  Future<void> load() {
    final active = _loadFuture;
    if (active != null) return active;
    late final Future<void> tracked;
    tracked = _performLoad().whenComplete(() {
      if (identical(_loadFuture, tracked)) _loadFuture = null;
    });
    _loadFuture = tracked;
    return tracked;
  }

  Future<void> _performLoad() async {
    state = state.copyWith(data: const AsyncLoading(), actionError: null);
    try {
      final data = await ref.read(gardenRepositoryProvider).getFarm();
      state = FarmUiState(data: AsyncData(data), draft: data.layout);
    } on ApiException catch (error, stack) {
      state = state.copyWith(data: AsyncError(error, stack));
    }
  }

  void beginEditing() {
    if (state.saving) return;
    state = state.copyWith(editing: true, actionError: null);
  }

  void cancelEditing() {
    if (state.saving) return;
    final serverLayout = state.data.valueOrNull?.layout;
    state = state.copyWith(
      draft: serverLayout,
      conflict: null,
      editing: false,
      actionError: null,
    );
  }

  void equipRoomTheme(int? userItemId) => _updateDraft(
        (draft) => draft.copyWith(roomThemeUserItemId: userItemId),
      );

  void equipMainCharacter(int? userItemId) => _updateDraft(
        (draft) => draft.copyWith(mainCharacterUserItemId: userItemId),
      );

  void equipWardrobe(int? userItemId) => _updateDraft(
        (draft) => draft.copyWith(wardrobeUserItemId: userItemId),
      );

  void toggleCompanion(int userItemId) {
    if (state.saving) return;
    final draft = state.draft;
    if (draft == null) return;
    if (!draft.companionUserItemIds.contains(userItemId) &&
        draft.companionUserItemIds.length >= 3) {
      state = state.copyWith(actionError: '동행 친구는 세 명까지 함께할 수 있어요.');
      return;
    }
    _updateDraft((draft) {
      final ids = [...draft.companionUserItemIds];
      ids.contains(userItemId) ? ids.remove(userItemId) : ids.add(userItemId);
      return draft.copyWith(companionUserItemIds: ids);
    });
  }

  void placeDecoration(int userItemId) {
    if (state.saving) return;
    final draft = state.draft;
    if (draft == null) return;
    final itemCode =
        state.data.valueOrNull?.itemByUserItemId(userItemId)?.item.code;
    if (!draft.decorations.any((item) => item.userItemId == userItemId) &&
        draft.decorations.length >= 30) {
      state = state.copyWith(actionError: '꾸미기 아이템은 서른 개까지 놓을 수 있어요.');
      return;
    }
    _updateDraft((draft) {
      if (draft.decorations.any((item) => item.userItemId == userItemId)) {
        return draft;
      }
      final highest = draft.decorations.fold<int>(
        0,
        (value, item) => item.zIndex > value ? item.zIndex : value,
      );
      final position = _decorationStartPosition(
        draft.decorations.length,
        itemCode,
      );
      return draft.copyWith(decorations: [
        ...draft.decorations,
        FarmDecoration(
          userItemId: userItemId,
          x: position.$1,
          y: position.$2,
          scale: 1,
          rotation: 0,
          zIndex: highest + 1,
        ),
      ]);
    });
  }

  /// 용도에 맞는 첫 위치를 주고, 알 수 없는 아이템은 빈 가장자리에 놓는다.
  /// 캐릭터 중앙을 피하면서 조명은 벽, 패브릭은 바닥에서 시작하게 한다.
  (double, double) _decorationStartPosition(int index, String? code) {
    return switch (code) {
      'deco_lamp_moon' => (0.82, 0.14),
      'deco_cushion_leaf' => (0.82, 0.80),
      'deco_rug_cloud' => (0.50, 0.88),
      'deco_lamp_mushroom' => (0.78, 0.72),
      'deco_radio_strawberry' => (0.24, 0.72),
      'deco_stool_frog' => (0.76, 0.82),
      'deco_books_pressed' => (0.22, 0.82),
      'deco_mobile_moon_seed' => (0.72, 0.18),
      'deco_planter_teacup' => (0.20, 0.58),
      _ => switch (index % 6) {
          0 => (0.78, 0.78),
          1 => (0.22, 0.18),
          2 => (0.82, 0.42),
          3 => (0.18, 0.42),
          4 => (0.68, 0.18),
          _ => (0.32, 0.18),
        },
    };
  }

  void moveDecoration(int userItemId, {required double x, required double y}) =>
      _replaceDecoration(
        userItemId,
        (item) => item.copyWith(x: x, y: y),
      );

  void scaleDecoration(int userItemId, double scale) => _replaceDecoration(
        userItemId,
        (item) => item.copyWith(scale: scale),
      );

  void rotateDecoration(int userItemId, double rotation) => _replaceDecoration(
        userItemId,
        (item) => item.copyWith(rotation: rotation),
      );

  void removeDecoration(int userItemId) => _updateDraft(
        (draft) => draft.copyWith(
          decorations: draft.decorations
              .where((item) => item.userItemId != userItemId)
              .toList(),
        ),
      );

  Future<bool> save() async {
    final draft = state.draft;
    final farm = state.data.valueOrNull;
    if (draft == null || farm == null || state.saving) return false;
    if (state.conflict != null) {
      state = state.copyWith(actionError: '아래에서 저장할 배치를 먼저 선택해 주세요.');
      return false;
    }
    state = state.copyWith(saving: true, actionError: null);
    try {
      final saved = await ref.read(gardenRepositoryProvider).updateFarm(draft);
      state = FarmUiState(
        data: AsyncData(farm.copyWith(layout: saved)),
        draft: saved,
      );
      return true;
    } on ApiException catch (error) {
      if (error.code == 'FARM_LAYOUT_VERSION_CONFLICT') {
        try {
          final latest = await ref.read(gardenRepositoryProvider).getFarm();
          state = FarmUiState(
            data: AsyncData(latest),
            // 최신 서버본은 기준 데이터로만 갱신하고, 사용자가 꾸민 초안은
            // 명시적으로 선택하기 전까지 절대 덮어쓰지 않는다.
            draft: draft,
            conflict: FarmLayoutConflict(latestLayout: latest.layout),
            editing: true,
          );
        } on ApiException catch (refreshError) {
          state = state.copyWith(
            saving: false,
            editing: true,
            actionError: '${refreshError.message} 지금 꾸민 배치는 이 화면에 보관되어 있어요.',
          );
        }
      } else {
        state = state.copyWith(saving: false, actionError: error.message);
      }
      return false;
    }
  }

  /// 충돌 시 받아 둔 서버 최신본으로 로컬 초안을 교체한다.
  void useLatestLayout() {
    final latest = state.conflict?.latestLayout;
    if (latest == null || state.saving) return;
    state = state.copyWith(
      draft: latest,
      conflict: null,
      editing: false,
      actionError: null,
    );
  }

  /// 로컬 초안을 최신 서버 version 위에 다시 저장한다.
  ///
  /// 배치 문서는 전체 교체 계약이므로 이 동작은 사용자가 충돌 안내에서
  /// 명시적으로 선택했을 때만 호출한다. 재충돌하면 같은 초안을 다시 보존한다.
  Future<bool> retryConflict() async {
    final draft = state.draft;
    final latest = state.conflict?.latestLayout;
    if (draft == null || latest == null || state.saving) return false;
    state = state.copyWith(
      draft: draft.copyWith(version: latest.version),
      conflict: null,
      actionError: null,
    );
    return save();
  }

  void clearActionError() => state = state.copyWith(actionError: null);

  /// 구매/조건 해금 결과의 보유 목록만 합친다. 서버 재조회로 저장 전 draft를 덮지 않는다.
  void mergeAcquiredItem(UserGardenItem acquired) {
    final farm = state.data.valueOrNull;
    if (farm == null) {
      load();
      return;
    }
    final items = [
      for (final item in farm.ownedItems)
        if (item.id != acquired.id) item,
      acquired,
    ];
    state = state.copyWith(
      data: AsyncData(farm.copyWith(ownedItems: items)),
    );
  }

  /// 이전 호출부와 테스트를 위한 호환 별칭.
  void mergePurchasedItem(UserGardenItem purchased) =>
      mergeAcquiredItem(purchased);

  void _replaceDecoration(
    int userItemId,
    FarmDecoration Function(FarmDecoration) update,
  ) =>
      _updateDraft((draft) => draft.copyWith(
            decorations: [
              for (final item in draft.decorations)
                item.userItemId == userItemId ? update(item) : item,
            ],
          ));

  void _updateDraft(FarmLayout Function(FarmLayout) update) {
    final draft = state.draft;
    if (draft == null || state.saving) return;
    state = state.copyWith(
      draft: update(draft),
      editing: true,
      actionError: null,
    );
  }
}

final farmControllerProvider =
    NotifierProvider<FarmController, FarmUiState>(FarmController.new);

/// 현재 방 배치에 장착된 의상의 렌더 레이어 키.
///
/// 방 편집 중에는 미리보기와 다른 화면의 캐릭터가 같은 의상을 보여 주도록
/// draft를 우선하고, 저장된 보유 아이템에서 실제 레이어 키를 찾는다.
final equippedWardrobeLayerKeyProvider = Provider<String?>((ref) {
  final state = ref.watch(farmControllerProvider);
  final farm = state.data.valueOrNull;
  final layout = state.draft ?? farm?.layout;
  final wardrobe = farm?.itemByUserItemId(layout?.wardrobeUserItemId);
  return wardrobe?.item.wardrobeLayerKey;
});
