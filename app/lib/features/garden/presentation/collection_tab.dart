import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/garden_models.dart';
import 'garden_controller.dart';
import 'garden_item_visual.dart';

class CollectionTab extends ConsumerWidget {
  const CollectionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(collectionControllerProvider);
    return collection.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('도감을 펼치고 있어요.'),
          ],
        ),
      ),
      error: (error, _) => _CollectionError(
        message: ApiException.from(error).message,
        onRetry: () => ref.invalidate(collectionControllerProvider),
      ),
      data: (data) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(collectionControllerProvider),
        child: CollectionCatalogView(data: data),
      ),
    );
  }
}

/// 도감의 분류와 카드 목록.
class CollectionCatalogView extends StatelessWidget {
  const CollectionCatalogView({super.key, required this.data});

  final GardenCollection data;

  @override
  Widget build(BuildContext context) {
    final catalogCharacters = data.collectionCatalogItems
        .where((item) => item.isCharacter)
        .toList(growable: false);
    final ownedCharacters = data.ownedCollectionItems
        .where((item) => item.isCharacter)
        .toList(growable: false);
    final characters = [
      ...(catalogCharacters.isEmpty ? ownedCharacters : catalogCharacters),
    ]..sort((left, right) {
        if (left.owned != right.owned) return left.owned ? -1 : 1;
        final leftIsRoster = left.assetKey?.startsWith('characters/') ?? false;
        final rightIsRoster =
            right.assetKey?.startsWith('characters/') ?? false;
        if (leftIsRoster != rightIsRoster) return leftIsRoster ? -1 : 1;
        final rarity = right.rarity.compareTo(left.rarity);
        return rarity != 0 ? rarity : left.id.compareTo(right.id);
      });
    final catalogItems = data.collectionCatalogItems
        .where((item) => !item.isCharacter)
        .toList(growable: false);
    final fallbackItems = data.ownedCollectionItems
        .where((item) => !item.isCharacter)
        .toList(growable: false);
    final allVisibleItems = catalogItems.isEmpty ? fallbackItems : catalogItems;
    final resonanceItems = allVisibleItems
        .where((item) => item.isMoodResonance)
        .toList(growable: false);
    final visibleItems = allVisibleItems
        .where((item) => !item.isMoodResonance)
        .toList(growable: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CollectionHeader(data: data),
                const SizedBox(height: 20),
                const Text(
                  '정원 가이드 도감',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '식물의 성장을 돕는 가이드와 동행 친구를 만나 보세요.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ResponsiveCards(
                  count: characters.length,
                  extent: 288,
                  emptyMessage: '새로운 캐릭터 친구들이 곧 도착해요.',
                  builder: (index) => _CatalogItemCard(
                    item: characters[index],
                    characterFirst: true,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '식물 품종',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '돌봄을 이어 가며 새로운 식물을 도감에 등록해요.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ResponsiveCards(
                  count: data.species.length,
                  emptyMessage: '등록된 식물 품종이 아직 없어요.',
                  builder: (index) => _SpeciesCard(entry: data.species[index]),
                ),
                if (resonanceItems.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    '마음결 기념품',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '각 마음꽃의 첫 수확을 기억하는 여섯 소품이에요. 감정마다 가치와 획득 난이도는 같아요.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ResponsiveCards(
                    count: resonanceItems.length,
                    extent: 244,
                    emptyMessage: '첫 마음꽃을 수확하면 기념품이 열려요.',
                    builder: (index) => _CatalogItemCard(
                      item: resonanceItems[index],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  '아이템 도감',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '방 테마와 꾸미기 아이템의 수집 현황이에요.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ResponsiveCards(
                  count: visibleItems.length,
                  emptyMessage: '상점에서 첫 꾸미기 아이템을 만나 보세요.',
                  builder: (index) =>
                      _CatalogItemCard(item: visibleItems[index]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({required this.data});

  final GardenCollection data;

  @override
  Widget build(BuildContext context) {
    final characters = data.catalogItems.where((item) => item.isCharacter);
    final ownedCharacters = characters.where((item) => item.owned).length;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer.withAlpha(78),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.auto_stories_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '나의 무드 도감',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    characters.isEmpty
                        ? '수집 ${data.unlockedCount}/${data.totalCount} · 보유 아이템 ${data.ownedCollectionItems.length}개'
                        : '캐릭터 $ownedCharacters/${characters.length} · 전체 수집 ${data.unlockedCount}/${data.totalCount}',
                  ),
                ],
              ),
            ),
            SeedBalanceBadge(balance: data.seedBalance),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveCards extends StatelessWidget {
  const _ResponsiveCards({
    required this.count,
    required this.builder,
    required this.emptyMessage,
    this.extent = 220,
  });

  final int count;
  final Widget Function(int index) builder;
  final String emptyMessage;
  final double extent;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Text(emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          < 480 => 2,
          < 760 => 3,
          _ => 4,
        };
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: extent,
          ),
          itemCount: count,
          itemBuilder: (context, index) => builder(index),
        );
      },
    );
  }
}

class _SpeciesCard extends StatelessWidget {
  const _SpeciesCard({required this.entry});

  final SpeciesCollectionEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          entry.isUnlocked ? '${entry.name}, 해금된 식물 캐릭터' : '아직 만나지 못한 식물 캐릭터',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    entry.isUnlocked
                        ? Icons.local_florist_outlined
                        : Icons.lock_outline,
                    size: 54,
                    color: entry.isUnlocked
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                entry.isUnlocked ? entry.name : '아직 비밀이에요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                entry.isUnlocked ? '도감에 등록됨' : '계속 돌보며 만나 보세요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogItemCard extends StatefulWidget {
  const _CatalogItemCard({
    required this.item,
    this.characterFirst = false,
  });

  final ShopItem item;
  final bool characterFirst;

  @override
  State<_CatalogItemCard> createState() => _CatalogItemCardState();
}

class _CatalogItemCardState extends State<_CatalogItemCard> {
  bool _hovered = false;

  void _showCollectionStory(BuildContext context, ShopItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CollectionStorySheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scheme = Theme.of(context).colorScheme;
    final locked = !item.owned;
    final canOpenStory =
        !locked && (item.hasCollectionStory || item.isMoodResonance);
    final accent = gardenRarityColor(
      scheme,
      item.rarity,
      palette: MongrooPalette.of(context),
    );
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && !locked ? 1.015 : 1,
        duration: animationsDisabled
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: Semantics(
          button: canOpenStory,
          label: locked
              ? '${item.name}, 아직 수집하지 못함'
              : item.isMoodResonance
                  ? '${item.name}, 수집 완료, ${item.affinityLabel} 기념품'
                  : '${item.name}, 수집 완료, ${item.personality}',
          hint: canOpenStory
              ? item.isMoodResonance
                  ? '두 번 탭하여 기념품 반응 보기'
                  : '두 번 탭하여 캐릭터 이야기 보기'
              : locked && (item.isRoomTheme || item.isMoodResonance)
                  ? item.acquisitionHint
                  : null,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: canOpenStory
                  ? () => _showCollectionStory(context, item)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: GardenRarityFrame(
                          item: item,
                          locked: locked,
                          padding: EdgeInsets.all(
                            widget.characterFirst ? 6 : 10,
                          ),
                          child: GardenItemVisual(
                            item: item,
                            locked: locked,
                            animateIdle: false,
                            cacheWidth: 512,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          locked ? Icons.lock_outline : Icons.check_circle,
                          size: 16,
                          color: locked ? scheme.onSurfaceVariant : accent,
                        ),
                        if (canOpenStory) ...[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.menu_book_outlined,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.characterFirst
                            ? locked
                                ? '아직 알려지지 않은 친구'
                                : item.personality
                            : locked && item.isRoomTheme
                                ? item.acquisitionHint
                                : item.isMoodResonance
                                    ? locked
                                        ? item.acquisitionHint
                                        : '${item.affinityLabel} · ${item.reactionCopy ?? '첫 수확의 기억'}'
                                    : '${item.typeLabel} · ${item.rarityLabel}',
                        maxLines:
                            locked && (item.isRoomTheme || item.isMoodResonance)
                                ? 2
                                : item.isMoodResonance
                                    ? 2
                                    : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (widget.characterFirst) ...[
                      const SizedBox(height: 3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          locked ? '퀘스트와 상점에서 만날 수 있어요' : item.catchphrase,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: locked ? scheme.onSurfaceVariant : accent,
                          ),
                        ),
                      ),
                    ],
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

class _CollectionStorySheet extends StatelessWidget {
  const _CollectionStorySheet({required this.item});

  final ShopItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = gardenRarityColor(
      scheme,
      item.rarity,
      palette: MongrooPalette.of(context),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: '${item.name} 캐릭터 그림',
                image: true,
                excludeSemantics: true,
                child: SizedBox(
                  height: 184,
                  child: GardenRarityFrame(
                    item: item,
                    padding: const EdgeInsets.all(10),
                    child: GardenItemVisual(
                      item: item,
                      cacheWidth: 512,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                item.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StoryTag(label: item.typeLabel),
                  _StoryTag(label: item.rarityLabel, color: accent),
                  if (item.isMoodResonance)
                    _StoryTag(
                      label: item.affinityLabel,
                      icon: Icons.blur_circular_rounded,
                    ),
                  if (item.storyRole case final role?)
                    _StoryTag(
                      label: '정원에서의 역할 · $role',
                      icon: Icons.theater_comedy_outlined,
                    ),
                ],
              ),
              if (item.isMoodResonance) ...[
                const SizedBox(height: 20),
                Text(
                  '식물의 기억',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 7),
                Text(
                  item.reactionCopy ?? '이 소품은 첫 수확의 마음결을 기억하고 조용히 반응해요.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '모든 마음결 기념품은 같은 조건으로 열리며 성장 속도나 보상에는 영향을 주지 않아요.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (item.loreHook case final lore?) ...[
                const SizedBox(height: 20),
                Text(
                  '정원 이야기',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 7),
                Text(
                  lore,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (item.collectionQuote case final quote?) ...[
                const SizedBox(height: 18),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withAlpha(105),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '“$quote”',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryTag extends StatelessWidget {
  const _StoryTag({required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = color ?? scheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withAlpha(92)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final icon?) ...[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionError extends StatelessWidget {
  const _CollectionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_outlined, size: 42),
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
