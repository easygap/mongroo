import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_formats.dart';
import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/plant_view.dart';
import '../data/gallery_repository.dart';
import '../domain/harvested_plant.dart';
import 'emotion_plant_view.dart';

const _unset = Object();
const _museumWideBreakpoint = 760.0;

class GalleryState {
  const GalleryState({
    this.mode = MuseumMode.recent,
    this.items = const [],
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
    this.maxFeatured = 10,
    this.togglingIds = const {},
    this.featuredCount,
    this.actionError,
  });

  final MuseumMode mode;
  final List<HarvestedPlant> items;
  final String? nextCursor;
  final bool loadingMore;
  final String? loadMoreError;
  final int maxFeatured;
  final Set<int> togglingIds;
  final int? featuredCount;
  final String? actionError;

  GalleryState copyWith({
    MuseumMode? mode,
    List<HarvestedPlant>? items,
    Object? nextCursor = _unset,
    bool? loadingMore,
    Object? loadMoreError = _unset,
    int? maxFeatured,
    Set<int>? togglingIds,
    int? featuredCount,
    Object? actionError = _unset,
  }) =>
      GalleryState(
        mode: mode ?? this.mode,
        items: items ?? this.items,
        nextCursor:
            nextCursor == _unset ? this.nextCursor : nextCursor as String?,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: loadMoreError == _unset
            ? this.loadMoreError
            : loadMoreError as String?,
        maxFeatured: maxFeatured ?? this.maxFeatured,
        togglingIds: togglingIds ?? this.togglingIds,
        featuredCount: featuredCount ?? this.featuredCount,
        actionError:
            actionError == _unset ? this.actionError : actionError as String?,
      );
}

class GalleryController extends AsyncNotifier<GalleryState> {
  MuseumMode _requestedMode = MuseumMode.recent;

  @override
  Future<GalleryState> build() => _fetch(MuseumMode.recent);

  Future<GalleryState> _fetch(MuseumMode mode) async {
    final repository = ref.read(galleryRepositoryProvider);
    if (mode == MuseumMode.archive) {
      final page = await repository.getHarvested();
      return GalleryState(
        mode: MuseumMode.archive,
        items: page.items,
        nextCursor: page.nextCursor,
      );
    }
    final page = await repository.getMuseum(mode: mode);
    return GalleryState(
      mode: page.mode,
      items: page.items,
      maxFeatured: page.maxFeatured,
      featuredCount:
          page.mode == MuseumMode.featured ? page.items.length : null,
    );
  }

  Future<void> selectMode(MuseumMode mode) async {
    final current = state.valueOrNull;
    if (current?.mode == mode ||
        current?.togglingIds.isNotEmpty == true ||
        state.isLoading) {
      return;
    }
    _requestedMode = mode;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(mode));
  }

  Future<void> refresh() async {
    if (state.valueOrNull?.togglingIds.isNotEmpty == true) return;
    final mode = state.valueOrNull?.mode ?? _requestedMode;
    state = await AsyncValue.guard(() => _fetch(mode));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        current.mode != MuseumMode.archive ||
        current.nextCursor == null ||
        current.loadingMore ||
        current.togglingIds.isNotEmpty) {
      return;
    }

    state = AsyncData(
      current.copyWith(loadingMore: true, loadMoreError: null),
    );
    try {
      final page = await ref
          .read(galleryRepositoryProvider)
          .getHarvested(cursor: current.nextCursor);
      final knownIds = current.items.map((plant) => plant.id).toSet();
      final appended = page.items
          .where((plant) => knownIds.add(plant.id))
          .toList(growable: false);
      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          items: [...current.items, ...appended],
          nextCursor: page.nextCursor,
          loadingMore: false,
          loadMoreError: null,
        ),
      );
    } catch (error) {
      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          loadingMore: false,
          loadMoreError: ApiException.from(error).message,
        ),
      );
    }
  }

  Future<bool> toggleFeatured(int plantId) async {
    final current = state.valueOrNull;
    if (current == null || current.togglingIds.contains(plantId)) return false;
    final index = current.items.indexWhere((item) => item.id == plantId);
    if (index < 0) return false;

    final original = current.items[index];
    final nextFeatured = !original.museumFeatured;
    final optimistic = original.copyWith(museumFeatured: nextFeatured);
    final optimisticItems = [...current.items]..[index] = optimistic;
    state = AsyncData(
      current.copyWith(
        items: optimisticItems,
        togglingIds: {...current.togglingIds, plantId},
        actionError: null,
      ),
    );

    try {
      final result = await ref.read(galleryRepositoryProvider).setFeatured(
            plantId: plantId,
            isFeatured: nextFeatured,
          );
      final latest = state.valueOrNull;
      if (latest == null) return true;
      final saved = result.plant ?? optimistic;
      final savedItems = latest.mode == MuseumMode.featured && !nextFeatured
          ? latest.items.where((item) => item.id != plantId).toList()
          : [
              for (final item in latest.items)
                if (item.id == plantId) saved else item,
            ];
      state = AsyncData(
        latest.copyWith(
          items: savedItems,
          maxFeatured: result.maxFeatured,
          featuredCount: result.featuredCount ??
              (latest.mode == MuseumMode.featured ? savedItems.length : null),
          togglingIds: {...latest.togglingIds}..remove(plantId),
          actionError: null,
        ),
      );
      return true;
    } on ApiException catch (error) {
      final latest = state.valueOrNull ?? current;
      final message = error.code == 'MUSEUM_FEATURED_LIMIT'
          ? '대표 전시는 최대 ${current.maxFeatured}그루까지 선택할 수 있어요.'
          : error.message;
      state = AsyncData(
        latest.copyWith(
          items: current.items,
          togglingIds: {...latest.togglingIds}..remove(plantId),
          actionError: message,
        ),
      );
      return false;
    }
  }
}

final galleryControllerProvider =
    AsyncNotifierProvider<GalleryController, GalleryState>(
  GalleryController.new,
);

/// 감정 기록으로 다 자란 식물을 다시 만나는 전시 공간.
class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final museum = ref.watch(galleryControllerProvider);
    final palette = _MuseumPalette.of(context);
    return Scaffold(
      backgroundColor: palette.paper,
      appBar: AppBar(
        backgroundColor: palette.paper,
        title: const Text('마음 식물 박물관'),
        actions: [
          IconButton(
            tooltip: '박물관 이용 안내',
            onPressed: () => _showMuseumGuide(context),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _MuseumPaperPainter(
                    color: palette.ink.withAlpha(
                      Theme.of(context).brightness == Brightness.dark ? 9 : 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: museum.when(
              loading: () => const _MuseumLoadingView(),
              error: (error, _) => _MuseumErrorView(
                message: ApiException.from(error).message,
                onRetry: () =>
                    ref.read(galleryControllerProvider.notifier).refresh(),
              ),
              data: (state) => _MuseumContent(state: state),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMuseumGuide(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.local_florist_rounded),
          title: const Text('마음 식물 박물관'),
          content: const Text(
            '식물은 함께 자란 감정 기록에 따라 저마다 다른 모습으로 만개해요. '
            '밝은 마음도, 무거운 마음도 모두 같은 가치로 전시됩니다.\n\n'
            '최근 식물은 최대 10그루를 보여 주며, 오래 보고 싶은 식물은 대표 전시에 '
            '최대 10그루까지 직접 골라 둘 수 있어요. 전체 식물에서는 오래전에 '
            '수확한 기록까지 차례로 꺼내 볼 수 있습니다. 식물이나 카드를 누르면 '
            '씨앗부터 만개까지의 성장 계보를 볼 수 있어요.\n\n'
            '마음결과 기질은 식물 캐릭터의 연출 설정이며, 사용자 성격 진단이나 '
            '성장 속도·보상 차등에는 사용되지 않습니다.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('알겠어요'),
            ),
          ],
        ),
      );
}

class _MuseumContent extends ConsumerWidget {
  const _MuseumContent({required this.state});

  final GalleryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = _MuseumPalette.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final plants = state.mode == MuseumMode.archive
        ? state.items
        : state.items.take(10).toList(growable: false);
    return RefreshIndicator(
      onRefresh: () => ref.read(galleryControllerProvider.notifier).refresh(),
      color: palette.coral,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _MuseumIntro(
              mode: state.mode,
              count: plants.length,
              maxFeatured: state.maxFeatured,
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
                  child: MuseumModeSelector(
                    selected: state.mode,
                    enabled: state.togglingIds.isEmpty,
                    onSelected: (mode) => ref
                        .read(galleryControllerProvider.notifier)
                        .selectMode(mode),
                  ),
                ),
              ),
            ),
          ),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              if (state.mode == MuseumMode.archive ||
                  constraints.crossAxisExtent < _museumWideBreakpoint) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              return SliverToBoxAdapter(
                child: _MuseumRoomStage(
                  plants: plants,
                  onOpen: (plant) => _showPlantDetails(context, ref, plant),
                ),
              );
            },
          ),
          if (plants.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _MuseumEmptyView(
                mode: state.mode,
                onShowRecent: () => ref
                    .read(galleryControllerProvider.notifier)
                    .selectMode(MuseumMode.recent),
                onGrowPlant: () => context.go('/home'),
              ),
            )
          else
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                if (width < _museumWideBreakpoint) {
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 44),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final plant = plants[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == plants.length - 1 ? 0 : 14,
                            ),
                            child: _MobileMuseumShelfCard(
                              key: ValueKey('museum-mobile-card-${plant.id}'),
                              plant: plant,
                              busy: state.togglingIds.contains(plant.id),
                              onOpen: () =>
                                  _showPlantDetails(context, ref, plant),
                              onToggleFeatured: () =>
                                  _toggleFeatured(context, ref, plant),
                            ),
                          );
                        },
                        childCount: plants.length,
                      ),
                    ),
                  );
                }
                final maxExtent = textScale > 1.35 ? 360.0 : 258.0;
                final rowHeight = textScale > 1.35 ? 416.0 : 350.0;
                final side = width > 1160 ? (width - 1120) / 2 : 20.0;
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, 48),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: maxExtent,
                      mainAxisExtent: rowHeight,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final plant = plants[index];
                        return _MuseumSpecimenCard(
                          plant: plant,
                          busy: state.togglingIds.contains(plant.id),
                          onOpen: () => _showPlantDetails(context, ref, plant),
                          onToggleFeatured: () =>
                              _toggleFeatured(context, ref, plant),
                        );
                      },
                      childCount: plants.length,
                    ),
                  ),
                );
              },
            ),
          if (state.mode == MuseumMode.archive)
            SliverToBoxAdapter(
              child: _MuseumArchiveFooter(
                hasMore: state.nextCursor != null,
                loading: state.loadingMore,
                error: state.loadMoreError,
                onLoadMore: () =>
                    ref.read(galleryControllerProvider.notifier).loadMore(),
              ),
            ),
          const SliverToBoxAdapter(
            child: SafeArea(
              top: false,
              child: SizedBox(height: 8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFeatured(
    BuildContext context,
    WidgetRef ref,
    HarvestedPlant plant,
  ) async {
    final success = await ref
        .read(galleryControllerProvider.notifier)
        .toggleFeatured(plant.id);
    if (!context.mounted) return;
    final latest = ref.read(galleryControllerProvider).valueOrNull;
    final message = success
        ? (plant.museumFeatured ? '대표 전시에서 내렸어요.' : '대표 전시에 놓았어요.')
        : latest?.actionError ?? '전시 설정을 바꾸지 못했어요.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showPlantDetails(
    BuildContext context,
    WidgetRef ref,
    HarvestedPlant plant,
  ) async {
    final desired = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (context) => _PlantDetailSheet(plant: plant),
    );
    if (desired == null || !context.mounted) return;
    await _toggleFeatured(context, ref, plant);
  }
}

class _MuseumArchiveFooter extends StatelessWidget {
  const _MuseumArchiveFooter({
    required this.hasMore,
    required this.loading,
    required this.error,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool loading;
  final String? error;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!hasMore && !loading && error == null) {
      return const SizedBox.shrink();
    }
    final palette = _MuseumPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
          child: error != null
              ? MongrooPanel(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  color: palette.sheet,
                  radius: 14,
                  shadowOffset: const Offset(2, 2),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_rounded, color: palette.coral),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(color: palette.inkMuted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: onLoadMore,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : loading
                  ? Semantics(
                      label: '식물을 더 불러오는 중',
                      liveRegion: true,
                      child: const Center(
                        child: SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      key: const ValueKey('museum-load-more'),
                      onPressed: onLoadMore,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      label: const Text('식물 더 보기'),
                    ),
        ),
      ),
    );
  }
}

class MuseumModeSelector extends StatelessWidget {
  const MuseumModeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final MuseumMode selected;
  final ValueChanged<MuseumMode> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.ink.withAlpha(18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final mode in MuseumMode.values)
              Expanded(
                child: _MuseumModeButton(
                  mode: mode,
                  selected: selected == mode,
                  onPressed: enabled ? () => onSelected(mode) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MuseumModeButton extends StatelessWidget {
  const _MuseumModeButton({
    required this.mode,
    required this.selected,
    required this.onPressed,
  });

  final MuseumMode mode;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final (label, icon) = switch (mode) {
      MuseumMode.recent => ('최근 식물', Icons.schedule_rounded),
      MuseumMode.featured => ('대표 전시', Icons.bookmark_rounded),
      MuseumMode.archive => ('전체 식물', Icons.inventory_2_rounded),
    };
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? palette.sheet : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border:
                  selected ? Border.all(color: palette.ink, width: 1.4) : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: palette.ink.withAlpha(24),
                        offset: const Offset(0, 2),
                        blurRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 19,
                    color: selected ? palette.coral : palette.inkMuted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? palette.ink : palette.inkMuted,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
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

class _MuseumIntro extends StatelessWidget {
  const _MuseumIntro({
    required this.mode,
    required this.count,
    required this.maxFeatured,
  });

  final MuseumMode mode;
  final int count;
  final int maxFeatured;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final (title, description, countLabel, icon, tagColor) = switch (mode) {
      MuseumMode.recent => (
          '최근 수확한 식물',
          '최근 수확 순으로 최대 10그루를 표시합니다.',
          '최근 $count/10',
          Icons.spa_rounded,
          palette.paper,
        ),
      MuseumMode.featured => (
          '대표 전시 식물',
          '직접 고른 식물을 한그루씩 천천히 다시 만나 보세요.',
          '대표 $count/$maxFeatured',
          Icons.bookmark_rounded,
          palette.butter,
        ),
      MuseumMode.archive => (
          '모든 수확 기록',
          '오래된 식물까지 차례로 불러와 천천히 둘러볼 수 있어요.',
          '현재 $count그루',
          Icons.inventory_2_rounded,
          palette.paper,
        ),
    };
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.inkMuted,
                height: 1.45,
              ),
        ),
      ],
    );
    final countTag = MongrooTag(
      label: countLabel,
      icon: icon,
      backgroundColor: tagColor,
      foregroundColor: palette.ink,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: MongrooPanel(
            padding: const EdgeInsets.all(16),
            color: palette.sheet,
            radius: 16,
            shadowOffset: const Offset(2, 2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackContent = constraints.maxWidth < 420 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                if (stackContent) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      countTag,
                      const SizedBox(height: 10),
                      copy,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 16),
                    countTag,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MuseumRoomStage extends StatelessWidget {
  const _MuseumRoomStage({required this.plants, required this.onOpen});

  final List<HarvestedPlant> plants;
  final ValueChanged<HarvestedPlant> onOpen;

  /// 16:9 밤 전시실의 진열대와 맞춘 좌표 비율.
  /// 안쪽에서 밖쪽으로 좌우를 한 쌍씩 채워 적은 수도 균형을 유지한다.
  static const _slots = <_MuseumSlot>[
    _MuseumSlot(.184, .255),
    _MuseumSlot(.739, .255),
    _MuseumSlot(.104, .255),
    _MuseumSlot(.812, .255),
    _MuseumSlot(.018, .255),
    _MuseumSlot(.902, .255),
    _MuseumSlot(.184, .505),
    _MuseumSlot(.739, .505),
    _MuseumSlot(.105, .565),
    _MuseumSlot(.812, .565),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 10),
                child: Row(
                  children: [
                    MongrooTag(
                      label: '밤 전시실',
                      icon: Icons.museum_outlined,
                      backgroundColor: palette.butter,
                      foregroundColor: palette.ink,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '현재 목록의 식물을 최대 10그루까지 진열합니다.',
                        style: TextStyle(
                          color: palette.inkMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              MongrooPanel(
                padding: const EdgeInsets.all(8),
                color: palette.sheet,
                radius: 20,
                shadowOffset: const Offset(3, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      label: '마음 식물 박물관 전시실, 식물 ${plants.length}그루 전시 중',
                      child: LayoutBuilder(
                        builder: (context, stageConstraints) {
                          final plantSize = stageConstraints.maxWidth * .085;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                'assets/rooms/night-museum-ink.webp',
                                key: const ValueKey(
                                  'museum-room-background',
                                ),
                                fit: BoxFit.cover,
                                cacheWidth: 1280,
                                filterQuality: FilterQuality.medium,
                                excludeFromSemantics: true,
                                errorBuilder: (context, error, stack) =>
                                    ColoredBox(
                                  color: palette.sheet,
                                  child: Icon(
                                    Icons.museum_outlined,
                                    size: 64,
                                    color: palette.inkMuted,
                                  ),
                                ),
                              ),
                              for (var index = 0;
                                  index < plants.length &&
                                      index < _slots.length;
                                  index++)
                                Positioned(
                                  left: stageConstraints.maxWidth *
                                      _slots[index].x,
                                  top: stageConstraints.maxHeight *
                                      _slots[index].y,
                                  width: plantSize,
                                  height: plantSize,
                                  child: _MuseumRoomPlantButton(
                                    plant: plants[index],
                                    size: plantSize,
                                    onPressed: () => onOpen(plants[index]),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
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

class _MuseumRoomPlantButton extends StatelessWidget {
  const _MuseumRoomPlantButton({
    required this.plant,
    required this.size,
    required this.onPressed,
  });

  final HarvestedPlant plant;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    return Semantics(
      button: true,
      label: '${plant.name}, ${plant.finalForm.label}, 실제 전시 식물',
      hint: '두 번 탭해 성장 계보 열기',
      child: Tooltip(
        message: '${plant.name} 성장 계보 보기',
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            key: ValueKey('museum-room-plant-${plant.id}'),
            onTap: onPressed,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            radius: size / 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: ExcludeSemantics(
                    child: EmotionPlantView(
                      form: plant.finalForm,
                      speciesCode: plant.species.code,
                      speciesName: plant.species.name,
                      size: size,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.sheet.withAlpha(235),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: palette.ink.withAlpha(45),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.open_in_full_rounded,
                          size: 12,
                          color: palette.coral,
                        ),
                      ),
                    ),
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

class _MuseumSlot {
  const _MuseumSlot(this.x, this.y);

  final double x;
  final double y;
}

class _MobileMuseumShelfCard extends StatelessWidget {
  const _MobileMuseumShelfCard({
    super.key,
    required this.plant,
    required this.busy,
    required this.onOpen,
    required this.onToggleFeatured,
  });

  final HarvestedPlant plant;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onToggleFeatured;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final formColors = palette.form(plant.finalForm);
    final harvested = plant.harvestedAt?.toLocal();
    final date =
        harvested == null ? '수확 날짜 기록 없음' : '${formatDotDate(harvested)} 수확';
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final vertical = textScale > 1.25 || MediaQuery.sizeOf(context).width < 350;
    final semanticLabel = '${plant.name}, ${plant.species.name}, '
        '${plant.finalForm.label}, $date'
        '${plant.museumFeatured ? ', 대표 전시 중' : ''}, 상세 보기';
    final plantShelf = _MobilePlantShelf(
      plant: plant,
      backgroundColor: palette.paper,
    );
    final information = _MobileMuseumPlantInformation(
      plant: plant,
      date: date,
      busy: busy,
      expanded: vertical,
      onToggleFeatured: onToggleFeatured,
    );

    return Semantics(
      button: true,
      label: semanticLabel,
      hint: '두 번 탭해 성장 계보와 마음결 정보 열기',
      child: MongrooPanel(
        padding: const EdgeInsets.all(6),
        color: palette.sheet,
        radius: 18,
        shadowOffset: const Offset(2, 3),
        child: Material(
          color: formColors.background,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: vertical
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: 158, child: plantShelf),
                        const SizedBox(height: 10),
                        information,
                      ],
                    )
                  : SizedBox(
                      height: 166,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 112, child: plantShelf),
                          const SizedBox(width: 10),
                          Expanded(child: information),
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

class _MobilePlantShelf extends StatelessWidget {
  const _MobilePlantShelf({
    required this.plant,
    required this.backgroundColor,
  });

  final HarvestedPlant plant;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final wood = MongrooPalette.of(context).wood;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor.withAlpha(185),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plantSize =
              (constraints.maxWidth - 8).clamp(92, 118).toDouble();
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 4,
                right: 4,
                bottom: 9,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: wood,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: palette.ink.withAlpha(35),
                        offset: const Offset(0, 3),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                child: RepaintBoundary(
                  child: ExcludeSemantics(
                    child: EmotionPlantView(
                      form: plant.finalForm,
                      speciesCode: plant.species.code,
                      speciesName: plant.species.name,
                      size: plantSize,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MobileMuseumPlantInformation extends StatelessWidget {
  const _MobileMuseumPlantInformation({
    required this.plant,
    required this.date,
    required this.busy,
    required this.expanded,
    required this.onToggleFeatured,
  });

  final HarvestedPlant plant;
  final String date;
  final bool busy;
  final bool expanded;
  final VoidCallback onToggleFeatured;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final formColors = palette.form(plant.finalForm);
    return Column(
      mainAxisSize: expanded ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: MongrooTag(
                  label: '${plant.finalForm.emotionLabel}의 식물',
                  icon: Icons.auto_awesome_rounded,
                  backgroundColor: palette.sheet,
                  foregroundColor: formColors.foreground,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: plant.museumFeatured ? '대표 전시에서 내리기' : '대표 전시에 놓기',
              child: Semantics(
                button: true,
                label: plant.museumFeatured
                    ? '${plant.name} 대표 전시에서 내리기'
                    : '${plant.name} 대표 전시에 놓기',
                child: IconButton.filledTonal(
                  onPressed: busy ? null : onToggleFeatured,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                    backgroundColor: palette.sheet,
                    foregroundColor:
                        plant.museumFeatured ? palette.coral : palette.inkMuted,
                  ),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          plant.museumFeatured
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          plant.name,
          maxLines: expanded ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${plant.finalForm.label} · ${plant.personalityName} · ${plant.species.name}',
          maxLines: expanded ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: formColors.foreground,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          date,
          maxLines: expanded ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.inkMuted,
            fontSize: 11,
            height: 1.35,
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 10),
          Text(
            plant.finalForm.description,
            style: TextStyle(color: palette.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 10),
        ] else
          const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '상세 기록 보기',
              style: TextStyle(
                color: palette.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_forward_rounded, size: 16, color: palette.coral),
          ],
        ),
      ],
    );
  }
}

class _MuseumSpecimenCard extends StatefulWidget {
  const _MuseumSpecimenCard({
    required this.plant,
    required this.busy,
    required this.onOpen,
    required this.onToggleFeatured,
  });

  final HarvestedPlant plant;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onToggleFeatured;

  @override
  State<_MuseumSpecimenCard> createState() => _MuseumSpecimenCardState();
}

class _MuseumSpecimenCardState extends State<_MuseumSpecimenCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final formColors = palette.form(widget.plant.finalForm);
    final harvested = widget.plant.harvestedAt?.toLocal();
    final date =
        harvested == null ? '수확 날짜 기록 없음' : '${formatDotDate(harvested)} 수확';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final semanticsLabel =
        '${widget.plant.name}, ${widget.plant.species.name}, '
        '${widget.plant.finalForm.label}, $date'
        '${widget.plant.museumFeatured ? ', 대표 전시 중' : ''}, 상세 성장 계보 보기';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, (1 - value) * 12), child: child),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered && !reduceMotion ? 1.015 : 1,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Semantics(
            button: true,
            label: semanticsLabel,
            hint: '두 번 탭해 성장 계보와 마음결 정보 열기',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onOpen,
                customBorder: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(110),
                    bottom: Radius.circular(18),
                  ),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    color: formColors.background,
                    border: Border.all(
                        color: palette.ink.withAlpha(175), width: 1.35),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(110),
                      bottom: Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: palette.ink.withAlpha(_hovered ? 38 : 22),
                        offset: Offset(0, _hovered ? 6 : 4),
                        blurRadius: _hovered ? 14 : 0,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(13, 20, 13, 13),
                        child: Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: RepaintBoundary(
                                  child: EmotionPlantView(
                                    form: widget.plant.finalForm,
                                    speciesCode: widget.plant.species.code,
                                    speciesName: widget.plant.species.name,
                                    size: 164,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.fromLTRB(12, 11, 12, 10),
                              decoration: BoxDecoration(
                                color: palette.sheet.withAlpha(235),
                                border: Border.all(
                                    color: palette.ink.withAlpha(120)),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    widget.plant.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.ink,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${widget.plant.finalForm.label} · ${widget.plant.personalityName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: formColors.foreground,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    date,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: palette.inkMuted, fontSize: 11),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '성장 계보 보기',
                                        style: TextStyle(
                                          color: palette.ink,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 14,
                                        color: palette.coral,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 7,
                        top: 56,
                        child: Tooltip(
                          message: widget.plant.museumFeatured
                              ? '대표 전시에서 내리기'
                              : '대표 전시에 놓기',
                          child: Semantics(
                            button: true,
                            label: widget.plant.museumFeatured
                                ? '${widget.plant.name} 대표 전시에서 내리기'
                                : '${widget.plant.name} 대표 전시에 놓기',
                            child: IconButton.filledTonal(
                              onPressed:
                                  widget.busy ? null : widget.onToggleFeatured,
                              style: IconButton.styleFrom(
                                minimumSize: const Size.square(48),
                                backgroundColor: palette.sheet.withAlpha(230),
                                foregroundColor: widget.plant.museumFeatured
                                    ? palette.coral
                                    : palette.inkMuted,
                                side: BorderSide(
                                    color: palette.ink.withAlpha(100)),
                              ),
                              icon: widget.busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Icon(
                                      widget.plant.museumFeatured
                                          ? Icons.bookmark_rounded
                                          : Icons.bookmark_border_rounded,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlantDetailSheet extends StatelessWidget {
  const _PlantDetailSheet({required this.plant});

  final HarvestedPlant plant;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final harvested = plant.harvestedAt?.toLocal();
    final planted = plant.plantedAt?.toLocal();
    final dateLabel = harvested == null
        ? '수확 날짜 기록 없음'
        : planted == null
            ? '${formatDotDate(harvested)} 수확'
            : '${formatDotDate(planted)} 심음 · ${formatDotDate(harvested)} 수확';
    return Material(
      color: palette.sheet,
      // 손잡이는 테마가 이미 그린다(`bottomSheetTheme.showDragHandle`).
      // 여기서 또 그리면 시트 머리에 회색 막대가 두 개 겹쳐 뜬다.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
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
                        plant.finalForm.label,
                        style: TextStyle(
                          color: palette.form(plant.finalForm).foreground,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        plant.name,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${plant.species.name} · $dateLabel',
                        style: TextStyle(color: palette.inkMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(minHeight: 220),
              decoration: BoxDecoration(
                color: palette.form(plant.finalForm).background,
                border: Border.all(color: palette.ink.withAlpha(120)),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(100),
                  topRight: Radius.circular(100),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Center(
                child: EmotionPlantView(
                  form: plant.finalForm,
                  speciesCode: plant.species.code,
                  speciesName: plant.species.name,
                  size: 210,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _PlantGrowthLineage(plant: plant),
            const SizedBox(height: 20),
            _PlantIdentityPanel(plant: plant),
            const SizedBox(height: 22),
            Text(
              '만개 관찰 기록',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              plant.finalForm.description,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            Text(
              '감정 기록 구성',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            if (!plant.emotionProfile.hasData)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '예전에 수확한 식물이라 세부 감정 기록이 남아 있지 않아요. 식물의 모습은 그대로 소중히 보관됩니다.',
                  style: TextStyle(color: palette.inkMuted),
                ),
              )
            else
              for (final emotion in PlantEmotion.values)
                _EmotionProfileRow(
                  emotion: emotion,
                  count: plant.emotionProfile.counts[emotion.code] ?? 0,
                  ratio: plant.emotionProfile.ratioFor(emotion),
                  color: palette.emotion(emotion),
                ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(!plant.museumFeatured),
              icon: Icon(
                plant.museumFeatured
                    ? Icons.bookmark_remove_rounded
                    : Icons.bookmark_add_rounded,
              ),
              label: Text(
                plant.museumFeatured ? '대표 전시에서 내리기' : '대표 전시에 놓기',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlantGrowthLineage extends StatelessWidget {
  const _PlantGrowthLineage({required this.plant});

  final HarvestedPlant plant;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final dominant = plant.dominantForm;
    final secondary = plant.secondaryForm;
    final steps = <_GrowthLineageStep>[
      const _GrowthLineageStep(
        stage: 1,
        title: '씨앗',
        detail: '모든 마음결이 같은 자리에서 시작',
      ),
      const _GrowthLineageStep(
        stage: 2,
        title: '새싹',
        detail: '일기 기록을 만나 첫잎을 펼침',
      ),
      _GrowthLineageStep(
        stage: 3,
        title: '주결 분기',
        detail: '${dominant.personalityName}이 줄기와 말투의 중심이 됨',
        form: dominant,
      ),
      _GrowthLineageStep(
        stage: 4,
        title: '보조결 · 기질',
        detail: secondary == null
            ? '주결의 캐릭터 기질과 말걸음이 또렷해짐'
            : '${secondary.personalityName}이 색과 반응에 한 겹을 보탬',
        form: dominant,
        secondaryForm: secondary,
      ),
      _GrowthLineageStep(
        stage: 5,
        title: '만개',
        detail: '${plant.finalForm.label} 모습으로 수확되어 박물관에 도착',
        form: dominant,
        secondaryForm: secondary,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '이 식물이 자란 다섯 장면',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          '씨앗에서 시작해 기록이 쌓일수록 외형과 식물 캐릭터의 말걸음이 갈라졌어요.',
          style: TextStyle(color: palette.inkMuted, height: 1.45),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final wide = constraints.maxWidth >= 570 && textScale <= 1.25;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < steps.length; index++) ...[
                    Expanded(
                      child: _GrowthLineageTile(
                        step: steps[index],
                        plant: plant,
                        compact: true,
                      ),
                    ),
                    if (index != steps.length - 1) const SizedBox(width: 8),
                  ],
                ],
              );
            }
            final singleColumn = constraints.maxWidth < 300 || textScale > 1.35;
            final tileWidth = singleColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final step in steps)
                  SizedBox(
                    width: tileWidth,
                    child: _GrowthLineageTile(step: step, plant: plant),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GrowthLineageStep {
  const _GrowthLineageStep({
    required this.stage,
    required this.title,
    required this.detail,
    this.form,
    this.secondaryForm,
  });

  final int stage;
  final String title;
  final String detail;
  final PlantGrowthForm? form;
  final PlantGrowthForm? secondaryForm;
}

class _GrowthLineageTile extends StatelessWidget {
  const _GrowthLineageTile({
    required this.step,
    required this.plant,
    this.compact = false,
  });

  final _GrowthLineageStep step;
  final HarvestedPlant plant;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final formColors = palette.form(plant.finalForm);
    return Semantics(
      container: true,
      label: '${step.stage}단계 ${step.title}. ${step.detail}',
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('museum-growth-stage-${step.stage}'),
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 11,
            9,
            compact ? 8 : 11,
            11,
          ),
          decoration: BoxDecoration(
            color: palette.paper,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: palette.ink.withAlpha(24),
                spreadRadius: 1,
              ),
              BoxShadow(
                color: palette.ink.withAlpha(18),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  step.stage.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: formColors.foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              PlantStagePreview(
                stage: step.stage,
                form: step.form,
                secondaryForm: step.stage >= 4 ? step.secondaryForm : null,
                speciesCode: plant.species.code,
                speciesName: plant.species.name,
                growthVisual: plant.growthVisual,
                size: compact ? 54 : 64,
              ),
              const SizedBox(height: 5),
              Text(
                step.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                step.detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantIdentityPanel extends StatelessWidget {
  const _PlantIdentityPanel({required this.plant});

  final HarvestedPlant plant;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final formColors = palette.form(plant.finalForm);
    final dominant = plant.dominantForm;
    final secondary = plant.secondaryForm;
    final temperament = _temperamentCopy(plant);
    final conversation = _conversationCopy(plant);
    return Semantics(
      container: true,
      label: '${plant.name}의 주결, 보조결, 식물 캐릭터 기질과 말걸음',
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: palette.paper,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: palette.ink.withAlpha(22),
              spreadRadius: 1,
            ),
            BoxShadow(
              color: palette.ink.withAlpha(16),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '이 식물의 마음결',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            _IdentityRow(
              icon: Icons.filter_vintage_rounded,
              label: '주결',
              value:
                  '${dominant.personalityName} · ${dominant.emotionLabel} 기록이 가장 오래 머문 중심 결',
              accent: formColors.foreground,
            ),
            _IdentityRow(
              icon: Icons.auto_awesome_rounded,
              label: '보조결',
              value: secondary == null
                  ? '별도 보조결 없이 주결 하나가 또렷하게 이어졌어요.'
                  : '${secondary.personalityName} · ${secondary.emotionLabel}의 결이 색과 반응에 한 겹 보탰어요.',
              accent: formColors.foreground,
            ),
            _IdentityRow(
              icon: Icons.psychology_alt_rounded,
              label: '식물 캐릭터 기질',
              value: temperament,
              accent: formColors.foreground,
            ),
            _IdentityRow(
              icon: Icons.record_voice_over_rounded,
              label: '말걸음',
              value: conversation,
              accent: formColors.foreground,
              last: true,
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: formColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '“${plant.voiceLine}”',
                style: TextStyle(
                  color: formColors.foreground,
                  fontWeight: FontWeight.w800,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: palette.inkMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '식물 캐릭터의 연출 설정이며, 사용자 성격 진단·성장 속도·보상 차등과 관계없어요.',
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _temperamentCopy(HarvestedPlant plant) {
    final summary = plant.temperamentSummary.trim();
    if (summary.isNotEmpty) return summary;
    if (plant.growthTraits.traits.isNotEmpty) {
      return plant.growthTraits.traits.take(3).join(' · ');
    }
    return plant.personalityDescription;
  }

  String _conversationCopy(HarvestedPlant plant) {
    final profile = plant.conversationProfile;
    final values = [
      profile.cadence,
      profile.focus,
      profile.questionStyle,
      profile.secondaryModifier,
      profile.stageExpression,
    ];
    final unique = <String>[];
    for (final value in values) {
      final copy = value.trim();
      if (copy.isNotEmpty && !unique.contains(copy)) unique.add(copy);
      if (unique.length == 3) break;
    }
    if (unique.isNotEmpty) return unique.join(' · ');
    return '대표 대사에 남은 말투로 천천히 이야기를 이어 가요.';
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 8 : 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withAlpha(18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox.square(
              dimension: 34,
              child: Icon(icon, size: 19, color: accent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: palette.inkMuted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmotionProfileRow extends StatelessWidget {
  const _EmotionProfileRow({
    required this.emotion,
    required this.count,
    required this.ratio,
    required this.color,
  });

  final PlantEmotion emotion;
  final int count;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final percent = (ratio * 100).round();
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.35;
    return Semantics(
      label: '${emotion.label} $count회, $percent퍼센트',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: largeText ? 88 : 64,
              child: Text(
                emotion.label,
                style:
                    TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 9,
                  color: color,
                  backgroundColor: palette.ink.withAlpha(20),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: largeText ? 80 : 58,
              child: Text(
                '$count · $percent%',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MuseumEmptyView extends StatelessWidget {
  const _MuseumEmptyView({
    required this.mode,
    required this.onShowRecent,
    required this.onGrowPlant,
  });

  final MuseumMode mode;
  final VoidCallback onShowRecent;
  final VoidCallback onGrowPlant;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    final featured = mode == MuseumMode.featured;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.butter.withAlpha(90),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child:
                      EmotionPlantView(form: PlantFinalForm.mosaic, size: 130),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                featured ? '대표 전시장이 비어 있어요' : '아직 전시할 식물이 없어요',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                featured
                    ? '최근 식물에서 오래 보고 싶은 친구의 책갈피를 눌러 보세요. 최대 10그루를 고를 수 있어요.'
                    : '감정을 기록하며 식물을 만개시키고 수확하면 이곳에 저마다 다른 모습으로 전시돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.inkMuted, height: 1.55),
              ),
              if (featured) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onShowRecent,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('최근 식물 보러 가기'),
                ),
              ] else ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onGrowPlant,
                  icon: const Icon(Icons.spa_outlined),
                  label: const Text('현재 식물 키우러 가기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MuseumLoadingView extends StatelessWidget {
  const _MuseumLoadingView();

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    return Semantics(
      label: '박물관을 불러오는 중',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text(
                  '전시실 문을 여는 중이에요…',
                  style: TextStyle(
                      color: palette.ink, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MuseumErrorView extends StatelessWidget {
  const _MuseumErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = _MuseumPalette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_florist_outlined,
                  size: 56, color: palette.coral),
              const SizedBox(height: 14),
              Text(
                '전시실을 열지 못했어요',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.inkMuted)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('다시 열어 보기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MuseumPalette {
  const _MuseumPalette({
    required this.paper,
    required this.sheet,
    required this.ink,
    required this.inkMuted,
    required this.coral,
    required this.butter,
    required this.dark,
  });

  final Color paper;
  final Color sheet;
  final Color ink;
  final Color inkMuted;
  final Color coral;
  final Color butter;
  final bool dark;

  static _MuseumPalette of(BuildContext context) {
    final brand = MongrooPalette.of(context);
    return _MuseumPalette(
      paper: brand.paperDeep,
      sheet: brand.paper,
      ink: brand.ink,
      inkMuted: brand.inkMuted,
      coral: brand.coral,
      butter: brand.butter,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
  }

  _FormColors form(PlantFinalForm form) {
    final colors = switch (form) {
      PlantFinalForm.sunny =>
        const _FormColors(Color(0xFFFFF3C9), Color(0xFF84571B)),
      PlantFinalForm.rainy =>
        const _FormColors(Color(0xFFDCECF0), Color(0xFF315F76)),
      PlantFinalForm.ember =>
        const _FormColors(Color(0xFFF7DED3), Color(0xFF9A3E35)),
      PlantFinalForm.moonlit =>
        const _FormColors(Color(0xFFE6E0ED), Color(0xFF5D527B)),
      PlantFinalForm.sparkling =>
        const _FormColors(Color(0xFFF9E0DD), Color(0xFF9D454F)),
      PlantFinalForm.mosaic =>
        const _FormColors(Color(0xFFE8E8D6), Color(0xFF536548)),
    };
    if (!dark) return colors;
    return _FormColors(
      Color.alphaBlend(colors.background.withAlpha(34), sheet),
      ink,
    );
  }

  Color emotion(PlantEmotion emotion) => switch (emotion) {
        PlantEmotion.joy => const Color(0xFFE0A638),
        PlantEmotion.sadness => const Color(0xFF6697B2),
        PlantEmotion.anger => const Color(0xFFD85E4B),
        PlantEmotion.anxiety => const Color(0xFF8176A4),
        PlantEmotion.surprise => const Color(0xFFE47B79),
        PlantEmotion.mixed => const Color(0xFF74866D),
      };
}

class _FormColors {
  const _FormColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

class _MuseumPaperPainter extends CustomPainter {
  const _MuseumPaperPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 5.0; y < size.height; y += 22) {
      final offset = ((y / 22).floor().isEven ? 7.0 : 17.0);
      for (var x = offset; x < size.width; x += 38) {
        canvas.drawCircle(Offset(x, y), .65, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MuseumPaperPainter oldDelegate) =>
      oldDelegate.color != color;
}
