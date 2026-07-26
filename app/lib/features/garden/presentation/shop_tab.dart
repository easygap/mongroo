import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/text/korean_particles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../domain/garden_models.dart';
import 'garden_controller.dart';
import 'garden_item_visual.dart';

enum _ShopFilter { all, resonance, growth, room, decoration }

class ShopTab extends ConsumerStatefulWidget {
  const ShopTab({super.key, this.initialSpeciesCode});

  final String? initialSpeciesCode;

  @override
  ConsumerState<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends ConsumerState<ShopTab> {
  _ShopFilter _filter = _ShopFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.initialSpeciesCode != null) {
      _filter = _ShopFilter.growth;
    }
  }

  @override
  void didUpdateWidget(covariant ShopTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSpeciesCode != oldWidget.initialSpeciesCode &&
        widget.initialSpeciesCode != null) {
      _filter = _ShopFilter.growth;
    }
  }

  bool _isFocusedSpecies(ShopItem item) =>
      widget.initialSpeciesCode != null &&
      item.assetManifest['species_code'] == widget.initialSpeciesCode;

  bool _canUseInRoom(ShopItem item) => item.isCompanion || item.type == 'deco';

  void _openRoom(WidgetRef ref) {
    DefaultTabController.maybeOf(context)?.animateTo(0);
    ref.read(farmControllerProvider.notifier).beginEditing();
  }

  Future<void> _purchase(
    BuildContext context,
    WidgetRef ref,
    ShopItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 구매'),
        content: Text('씨앗 ${item.priceSeeds}개를 사용해 이 아이템을 구매할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('구매하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result =
        await ref.read(shopControllerProvider.notifier).purchase(item.id);
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('${koreanObject(item.name)} 모음에 추가했어요.'),
          action: _canUseInRoom(item)
              ? SnackBarAction(
                  label: '방에서 사용',
                  onPressed: () => _openRoom(ref),
                )
              : null,
        ),
      );
  }

  Future<void> _claim(
    BuildContext context,
    WidgetRef ref,
    ShopItem item,
  ) async {
    final result =
        await ref.read(shopControllerProvider.notifier).claim(item.id);
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('${koreanObject(item.name)} 해금했어요.'),
          action: _canUseInRoom(item)
              ? SnackBarAction(
                  label: '방에 놓기',
                  onPressed: () => _openRoom(ref),
                )
              : null,
        ),
      );
  }

  void _openRoomThemePreview(BuildContext context, ShopItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => RoomThemePreviewSheet(itemId: item.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shopControllerProvider);
    ref.listen(
      shopControllerProvider.select((value) => value.actionError),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next)));
        ref.read(shopControllerProvider.notifier).clearActionError();
      },
    );

    return state.catalog.when(
      loading: () => const _ShopLoading(),
      error: (error, _) => _ShopError(
        message: ApiException.from(error).message,
        onRetry: () => ref.read(shopControllerProvider.notifier).load(),
      ),
      data: (catalog) => RefreshIndicator(
        onRefresh: () => ref.read(shopControllerProvider.notifier).load(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final items = catalog.items.where((item) {
              return switch (_filter) {
                _ShopFilter.all => true,
                _ShopFilter.resonance => item.isMoodResonance,
                _ShopFilter.growth => item.isGrowthCharacter,
                _ShopFilter.room => item.isRoomTheme,
                _ShopFilter.decoration => item.type == 'deco',
              };
            }).toList()
              ..sort((left, right) {
                final leftFocused = _isFocusedSpecies(left);
                final rightFocused = _isFocusedSpecies(right);
                if (leftFocused != rightFocused) return leftFocused ? -1 : 1;
                if (left.canClaim != right.canClaim) {
                  return left.canClaim ? -1 : 1;
                }
                if (left.owned != right.owned) {
                  return left.owned ? 1 : -1;
                }
                if (left.isGrowthCharacter != right.isGrowthCharacter) {
                  return left.isGrowthCharacter ? -1 : 1;
                }
                if (left.isGrowthCharacter && right.isGrowthCharacter) {
                  final leftIsRoster =
                      left.assetKey?.startsWith('characters/') ?? false;
                  final rightIsRoster =
                      right.assetKey?.startsWith('characters/') ?? false;
                  if (leftIsRoster != rightIsRoster) {
                    return leftIsRoster ? -1 : 1;
                  }
                  final rarity = right.rarity.compareTo(left.rarity);
                  if (rarity != 0) return rarity;
                }
                return left.id.compareTo(right.id);
              });
            final columns = textScale > 1.55 && constraints.maxWidth < 760
                ? 1
                : switch (constraints.maxWidth) {
                    < 360 => 1,
                    < 760 => 2,
                    < 1080 => 3,
                    _ => 4,
                  };
            final extraTextHeight =
                ((textScale - 1).clamp(0.0, 1.0) * 64).toDouble();
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (widget.initialSpeciesCode == null)
                  SliverToBoxAdapter(
                    child: _ShopFeatureRail(
                      catalog: catalog,
                      onResonanceTap: () => setState(
                        () => _filter = _ShopFilter.resonance,
                      ),
                      onPressedTap: () => setState(
                        () => _filter = _ShopFilter.decoration,
                      ),
                    ),
                  )
                else
                  const SliverToBoxAdapter(
                    child: _SpeciesShopNotice(),
                  ),
                SliverToBoxAdapter(
                  child: _ShopFilterBar(
                    selected: _filter,
                    onSelected: (filter) => setState(() => _filter = filter),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: (constraints.maxWidth < 460 ? 322 : 360) +
                          extraTextHeight,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (items.isEmpty) return const _EmptyShopCard();
                        final item = items[index];
                        return _ShopItemCard(
                          item: item,
                          focused: _isFocusedSpecies(item),
                          balance: catalog.seedBalance,
                          busy: state.purchasingItemIds.isNotEmpty,
                          onAction: () => item.requiresClaim
                              ? _claim(context, ref, item)
                              : _purchase(context, ref, item),
                          onPreview: () => _openRoomThemePreview(context, item),
                        );
                      },
                      childCount: items.isEmpty ? 1 : items.length,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SpeciesShopNotice extends StatelessWidget {
  const _SpeciesShopNotice();

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.sky.withAlpha(145),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.ink.withAlpha(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.travel_explore_rounded, color: palette.leaf),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '아까 골랐던 씨앗을 맨 앞에 놓았어요.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PressedCollectionBanner extends StatelessWidget {
  const _PressedCollectionBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: MongrooPressable(
        onTap: onTap,
        semanticLabel: '새 압화 작업실 소품 6종 보기',
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 122,
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            color: palette.blush,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.ink.withAlpha(32)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '새 진열 · 압화 작업실',
                      style: TextStyle(
                        color: palette.coral,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '손때 묻은 소품 6종',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '네 종류를 모으면 압화 편지 작업실이 열려요.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: ExcludeSemantics(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: const [
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: _BannerAsset(
                          path: 'assets/decorations/pressed-flower-books.webp',
                          size: 72,
                          angle: -0.08,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: -2,
                        child: _BannerAsset(
                          path: 'assets/decorations/mushroom-reading-lamp.webp',
                          size: 78,
                          angle: 0.07,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopFeatureRail extends StatelessWidget {
  const _ShopFeatureRail({
    required this.catalog,
    required this.onResonanceTap,
    required this.onPressedTap,
  });

  final ShopCatalog catalog;
  final VoidCallback onResonanceTap;
  final VoidCallback onPressedTap;

  @override
  Widget build(BuildContext context) {
    final resonance = catalog.items.where((item) => item.isMoodResonance);
    final claimed = resonance.where((item) => item.owned).length;
    final claimable = resonance.where((item) => item.canClaim).length;
    return SizedBox(
      height: 138,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth =
              (constraints.maxWidth * 0.86).clamp(300.0, 520.0).toDouble();
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 8),
            children: [
              SizedBox(
                width: cardWidth,
                child: _MoodResonanceBanner(
                  claimed: claimed,
                  total: resonance.length,
                  claimable: claimable,
                  onTap: onResonanceTap,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _PressedCollectionBanner(onTap: onPressedTap),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MoodResonanceBanner extends StatelessWidget {
  const _MoodResonanceBanner({
    required this.claimed,
    required this.total,
    required this.claimable,
    required this.onTap,
  });

  final int claimed;
  final int total;
  final int claimable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final status = claimable > 0
        ? '지금 $claimable개 받을 수 있어요'
        : total > 0
            ? '$claimed/$total 모음'
            : '여섯 마음꽃을 기다리는 중';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 2),
      child: MongrooPressable(
        onTap: onTap,
        semanticLabel: '마음결 기념품 보기, $status',
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 122,
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            color: palette.sky.withAlpha(154),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.ink.withAlpha(32)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '첫 수확의 기억',
                      style: TextStyle(
                        color: palette.leaf,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '마음결 기념품',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$status · 감정마다 다른 반응을 방에 남겨요.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                flex: 3,
                child: ExcludeSemantics(
                  child: _BannerAsset(
                    path: 'assets/decorations/many-heart-mobile-mosaic.webp',
                    size: 92,
                    angle: 0.03,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerAsset extends StatelessWidget {
  const _BannerAsset({required this.path, required this.size, this.angle = 0});

  final String path;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle,
        child: Image.asset(
          path,
          width: size,
          height: size,
          fit: BoxFit.contain,
          cacheWidth: 180,
          filterQuality: FilterQuality.medium,
        ),
      );
}

class _ShopFilterBar extends StatelessWidget {
  const _ShopFilterBar({required this.selected, required this.onSelected});

  final _ShopFilter selected;
  final ValueChanged<_ShopFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _ShopFilter.all: ('전체', Icons.apps_rounded),
      _ShopFilter.resonance: ('마음결', Icons.blur_circular_rounded),
      _ShopFilter.growth: ('성장 씨앗', Icons.local_florist_outlined),
      _ShopFilter.room: ('방', Icons.cottage_outlined),
      _ShopFilter.decoration: ('소품', Icons.chair_outlined),
    };
    return SizedBox(
      height: 68,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        children: [
          for (final entry in labels.entries) ...[
            FilterChip(
              avatar: Icon(entry.value.$2, size: 17),
              label: Text(entry.value.$1),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ShopItemCard extends StatefulWidget {
  const _ShopItemCard({
    required this.item,
    required this.focused,
    required this.balance,
    required this.busy,
    required this.onAction,
    required this.onPreview,
  });

  final ShopItem item;
  final bool focused;
  final int balance;
  final bool busy;
  final VoidCallback onAction;
  final VoidCallback onPreview;

  @override
  State<_ShopItemCard> createState() => _ShopItemCardState();
}

class _ShopItemCardState extends State<_ShopItemCard> {
  bool _hovered = false;
  bool _pressed = false;

  String _cardActionLabel(ShopItem item, {required bool affordable}) {
    if (item.owned) return item.isRoomTheme ? '보유 중 · 적용하기' : '보유 중';
    if (item.requiresClaim) {
      if (item.canClaim) return item.isRoomTheme ? '해금 가능 · 자세히' : '해금받기';
      final progress = item.acquisition?.progressLabel;
      return progress == null ? '획득 조건 확인' : '진행 $progress';
    }
    if (item.isRoomTheme) return '씨앗 ${item.priceSeeds}개 · 자세히';
    return affordable ? '씨앗 ${item.priceSeeds}개' : '씨앗이 부족해요';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final affordable = widget.balance >= item.priceSeeds;
    final rule = item.acquisition;
    final canPurchase = !item.owned &&
        !item.requiresClaim &&
        affordable &&
        (rule?.eligible ?? true);
    final canClaim = item.canClaim;
    final actionable = !widget.busy && (canPurchase || canClaim);
    final opensPreview = item.isRoomTheme && !widget.busy;
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = gardenRarityColor(
      scheme,
      item.rarity,
      palette: MongrooPalette.of(context),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed
            ? 0.985
            : _hovered
                ? 1.005
                : 1,
        duration: animationsDisabled
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: Semantics(
          excludeSemantics: true,
          button: opensPreview || actionable,
          label: item.isMoodResonance
              ? '${item.name}, ${item.affinityLabel} 기념품, ${item.acquisitionHint}'
              : '${item.name}, ${item.rarityLabel}, ${item.acquisitionHint}',
          hint: opensPreview
              ? '두 번 탭하여 방 미리보기와 획득 조건 열기'
              : actionable
                  ? item.requiresClaim
                      ? '두 번 탭하여 해금받기'
                      : '두 번 탭하여 구매하기'
                  : null,
          child: Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: widget.focused
                    ? MongrooPalette.of(context).leaf
                    : scheme.outlineVariant,
                width: widget.focused ? 2 : 1,
              ),
            ),
            child: InkWell(
              onTap: opensPreview
                  ? widget.onPreview
                  : actionable
                      ? widget.onAction
                      : null,
              onHighlightChanged: (value) {
                if (_pressed != value) setState(() => _pressed = value);
              },
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GardenRarityFrame(
                              item: item,
                              child: GardenItemVisual(
                                item: item,
                                fit: item.isRoomTheme
                                    ? BoxFit.cover
                                    : BoxFit.contain,
                                animateIdle: false,
                                cacheWidth: 512,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: _CatalogPill(
                              label: item.isMoodResonance
                                  ? item.affinityLabel
                                  : item.typeLabel,
                              foreground: scheme.onSurface,
                              background: scheme.surface,
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: _CatalogPill(
                              label: item.rarityLabel,
                              foreground: accent,
                              background: scheme.surface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.isGrowthCharacter
                          ? '일기를 쓰며 감정을 먹고 다섯 단계로 자라요.'
                          : item.isCompanion
                              ? item.personality
                              : item.isMoodResonance &&
                                      item.reactionCopy != null
                                  ? item.reactionCopy!
                                  : item.description.isEmpty
                                      ? item.typeLabel
                                      : item.description,
                      maxLines: item.isCharacter ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    if (item.isGrowthCharacter) ...[
                      const SizedBox(height: 4),
                      Text(
                        '씨앗 · 새싹 · 줄기 · 개화 · 만개',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (item.isCompanion) ...[
                      const SizedBox(height: 4),
                      Text(
                        '“${item.catchphrase}”',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: opensPreview || actionable
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: widget.busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  item.owned
                                      ? Icons.check
                                      : item.isRoomTheme
                                          ? Icons.visibility_outlined
                                          : item.requiresClaim
                                              ? Icons.lock_open_outlined
                                              : Icons.toll_outlined,
                                  size: 19,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    _cardActionLabel(
                                      item,
                                      affordable: affordable,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 방 테마의 분위기와 획득 조건을 한 화면에서 확인하고 바로 적용하는 시트.
class RoomThemePreviewSheet extends ConsumerStatefulWidget {
  const RoomThemePreviewSheet({super.key, required this.itemId});

  final int itemId;

  @override
  ConsumerState<RoomThemePreviewSheet> createState() =>
      _RoomThemePreviewSheetState();
}

class _RoomThemePreviewSheetState extends ConsumerState<RoomThemePreviewSheet> {
  bool _applying = false;

  ShopItem? _findItem(ShopCatalog? catalog) {
    if (catalog == null) return null;
    for (final item in catalog.items) {
      if (item.id == widget.itemId) return item;
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _purchase(ShopItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 구매'),
        content: Text('씨앗 ${item.priceSeeds}개를 사용해 이 방 테마를 구매할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('구매하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result =
        await ref.read(shopControllerProvider.notifier).purchase(item.id);
    if (result == null || !mounted) return;
    _showMessage('${koreanObject(item.name)} 모음에 추가했어요. 이제 바로 적용할 수 있어요.');
  }

  Future<void> _claim(ShopItem item) async {
    final result =
        await ref.read(shopControllerProvider.notifier).claim(item.id);
    if (result == null || !mounted) return;
    _showMessage('${koreanObject(item.name)} 해금했어요. 이제 바로 적용할 수 있어요.');
  }

  Future<void> _applyTheme(ShopItem item) async {
    if (_applying) return;
    setState(() => _applying = true);
    final controller = ref.read(farmControllerProvider.notifier);
    var farmState = ref.read(farmControllerProvider);
    if (farmState.data.valueOrNull == null) {
      await controller.load();
      farmState = ref.read(farmControllerProvider);
    }
    UserGardenItem? ownedTheme;
    for (final entry in farmState.data.valueOrNull?.ownedItems ?? const []) {
      if (entry.item.id == item.id) {
        ownedTheme = entry;
        break;
      }
    }
    if (ownedTheme == null && !farmState.editing) {
      await controller.load();
      farmState = ref.read(farmControllerProvider);
      for (final entry in farmState.data.valueOrNull?.ownedItems ?? const []) {
        if (entry.item.id == item.id) {
          ownedTheme = entry;
          break;
        }
      }
    }
    if (!mounted) return;
    if (ownedTheme == null) {
      setState(() => _applying = false);
      _showMessage('보유한 방 테마 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
      return;
    }

    final wasEditing = farmState.editing;
    controller.equipRoomTheme(ownedTheme.id);
    if (wasEditing) {
      setState(() => _applying = false);
      _showMessage('편집 중인 방에 적용했어요. 마이룸에서 저장하면 완료돼요.');
      return;
    }

    final saved = await controller.save();
    if (!mounted) return;
    setState(() => _applying = false);
    if (saved) {
      _showMessage('${item.name} 테마를 마이룸에 적용했어요.');
    } else {
      final message = ref.read(farmControllerProvider).actionError;
      _showMessage(message ?? '테마는 편집 화면에 보관했어요. 마이룸에서 저장 상태를 확인해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopState = ref.watch(shopControllerProvider);
    final catalog = shopState.catalog.valueOrNull;
    final item = _findItem(catalog);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final desiredHeight = screenHeight * 0.9;
    final sheetHeight = desiredHeight > 860 ? 860.0 : desiredHeight;
    if (item == null) {
      return SizedBox(
        height: sheetHeight,
        child: const Center(child: Text('방 테마 정보를 불러오지 못했어요.')),
      );
    }
    final busy = shopState.purchasingItemIds.contains(item.id) || _applying;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: sheetHeight,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '방 테마 미리보기',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SeedBalanceBadge(balance: catalog?.seedBalance ?? 0),
                          IconButton(
                            tooltip: '미리보기 닫기',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GardenRarityFrame(
                        item: item,
                        padding: const EdgeInsets.all(6),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: GardenItemVisual(
                              item: item,
                              fit: BoxFit.cover,
                              animateIdle: false,
                              cacheWidth: 1024,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CatalogPill(
                            label: item.typeLabel,
                            foreground: scheme.onSurface,
                            background: scheme.surfaceContainerHighest,
                          ),
                          _CatalogPill(
                            label: item.rarityLabel,
                            foreground: gardenRarityColor(
                              scheme,
                              item.rarity,
                              palette: MongrooPalette.of(context),
                            ),
                            background: scheme.surfaceContainerHighest,
                          ),
                        ],
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          item.description,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.45,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      ShopAcquisitionPanel(
                        item: item,
                        balance: catalog?.seedBalance ?? 0,
                      ),
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: _RoomThemeActionButton(
                    item: item,
                    balance: catalog?.seedBalance ?? 0,
                    busy: busy,
                    applying: _applying,
                    onPurchase: () => _purchase(item),
                    onClaim: () => _claim(item),
                    onApply: () => _applyTheme(item),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopAcquisitionPanel extends StatelessWidget {
  const ShopAcquisitionPanel({
    super.key,
    required this.item,
    required this.balance,
  });

  final ShopItem item;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rule = item.acquisition;
    final current = rule?.current ?? balance;
    final target = rule?.target ?? item.priceSeeds;
    final eligible =
        item.owned || (rule?.eligible ?? balance >= item.priceSeeds);
    final progress = item.owned
        ? 1.0
        : target <= 0
            ? eligible
                ? 1.0
                : 0.0
            : (current / target).clamp(0.0, 1.0).toDouble();
    final status = item.owned
        ? '보유 완료'
        : eligible
            ? '달성 완료'
            : '진행 중';
    final progressText = item.owned
        ? '완료'
        : target > 0
            ? '$current/$target'
            : status;
    final label = rule?.label ?? '씨앗으로 구매';

    return Semantics(
      container: true,
      label: '획득 조건, $label, $progressText',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: eligible
                ? scheme.primaryContainer.withAlpha(86)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: eligible
                  ? scheme.primary.withAlpha(92)
                  : scheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      eligible ? Icons.task_alt : Icons.flag_outlined,
                      color:
                          eligible ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        '획득 조건',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        color:
                            eligible ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      progressText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomThemeActionButton extends StatelessWidget {
  const _RoomThemeActionButton({
    required this.item,
    required this.balance,
    required this.busy,
    required this.applying,
    required this.onPurchase,
    required this.onClaim,
    required this.onApply,
  });

  final ShopItem item;
  final int balance;
  final bool busy;
  final bool applying;
  final VoidCallback onPurchase;
  final VoidCallback onClaim;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final rule = item.acquisition;
    final canPurchase = balance >= item.priceSeeds && (rule?.eligible ?? true);
    final enabled = item.owned
        ? !busy
        : item.requiresClaim
            ? item.canClaim && !busy
            : canPurchase && !busy;
    final label = busy
        ? applying
            ? '마이룸에 적용하는 중'
            : '처리하는 중'
        : item.owned
            ? '마이룸에 바로 적용'
            : item.requiresClaim
                ? item.canClaim
                    ? '조건 달성 · 해금받기'
                    : '조건을 더 채워 주세요'
                : canPurchase
                    ? '씨앗 ${item.priceSeeds}개로 구매하기'
                    : '씨앗 ${item.priceSeeds}개가 필요해요';
    final icon = item.owned
        ? Icons.wallpaper_outlined
        : item.requiresClaim
            ? Icons.lock_open_outlined
            : Icons.toll_outlined;

    return Semantics(
      excludeSemantics: true,
      liveRegion: busy,
      label: label,
      button: true,
      enabled: enabled,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          onPressed: enabled
              ? item.owned
                  ? onApply
                  : item.requiresClaim
                      ? onClaim
                      : onPurchase
              : null,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon),
          label: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _CatalogPill extends StatelessWidget {
  const _CatalogPill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
}

class _EmptyShopCard extends StatelessWidget {
  const _EmptyShopCard();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.storefront_outlined, size: 42),
              SizedBox(height: 12),
              Text('새 아이템을 준비하고 있어요.'),
            ],
          ),
        ),
      );
}

class _ShopLoading extends StatelessWidget {
  const _ShopLoading();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('상점 진열대를 채우고 있어요.'),
          ],
        ),
      );
}

class _ShopError extends StatelessWidget {
  const _ShopError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined, size: 42),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(144, 48),
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
}
