import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/plant_view.dart';
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
    final catalogItems = data.collectionCatalogItems.toList(growable: false);
    final fallbackItems = data.ownedCollectionItems.toList(growable: false);
    final allVisibleItems = catalogItems.isEmpty ? fallbackItems : catalogItems;
    final lineageItems = data.growthLineageItems;
    final standaloneSpecies = data.standaloneSpecies;
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
                  '성장 캐릭터 도감',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '모든 캐릭터는 씨앗에서 시작해 일기의 감정을 먹고 다섯 단계로 자라요.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ResponsiveCards(
                  count: standaloneSpecies.length + lineageItems.length,
                  extent: 244,
                  emptyMessage: '등록된 성장 캐릭터가 아직 없어요.',
                  builder: (index) {
                    if (index < standaloneSpecies.length) {
                      return _SpeciesCard(entry: standaloneSpecies[index]);
                    }
                    return _CharacterLineageCard(
                      item: lineageItems[index - standaloneSpecies.length],
                    );
                  },
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
    // 카드와 같은 목록으로 센다. `species`를 그대로 더하면 계보 항목과 겹친
    // 열다섯 캐릭터를 두 번 세어 `3/33`처럼 실제보다 큰 수가 나온다.
    final ownedCharacters =
        data.standaloneSpecies.where((entry) => entry.isUnlocked).length +
            data.growthLineageItems.where((entry) => entry.owned).length;
    final totalCharacters =
        data.standaloneSpecies.length + data.growthLineageItems.length;
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
            // 씨앗 배지는 정원 앱바가 이미 같은 값으로 들고 있다. 여기서 한 번
            // 더 놓으면 좁은 폭에서 부제목이 배지 옆으로 밀려 `전체 수집`이
            // `전체 수` + `집`으로 갈린다. 숫자를 두 곳에서 말할 이유가 없어
            // 배지를 내리고 폭을 부제목에 준다.
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
                    totalCharacters == 0
                        ? '수집 ${data.unlockedCount}/${data.totalCount} · 보유 아이템 ${data.ownedCollectionItems.length}개'
                        : '성장 캐릭터 $ownedCharacters/$totalCharacters\n'
                            '전체 수집 ${data.unlockedCount}/${data.totalCount}',
                  ),
                ],
              ),
            ),
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
    final growthLine = _GrowthLineagePreview(
      speciesCode: entry.code,
      speciesName: entry.name,
    );
    return Semantics(
      button: entry.isUnlocked,
      label: entry.isUnlocked
          ? '${entry.name}, 해금된 식물 캐릭터. 눌러서 감정별 성장 도감 보기'
          : '아직 만나지 못한 식물 캐릭터',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // 계보 카드와 같은 시트를 연다. 예전에는 품종 카드만 눌러도 아무
          // 일이 없어서, 같아 보이는 카드 둘 중 하나만 열리는 화면이었다.
          onTap: entry.isUnlocked
              ? () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => _CharacterGrowthAtlasSheet(
                      name: entry.name,
                      speciesCode: entry.code,
                    ),
                  )
              : null,
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
                    padding: const EdgeInsets.all(8),
                    child: entry.isUnlocked
                        ? growthLine
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              ColorFiltered(
                                colorFilter: kMongrooGreyscale,
                                child: Opacity(opacity: .32, child: growthLine),
                              ),
                              Icon(
                                Icons.lock_outline,
                                size: 36,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
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
                  entry.isUnlocked
                      ? '공통 씨앗에서 여섯 마음 루트로 성장'
                      : '해금하면 씨앗부터 함께 키울 수 있어요',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 씨앗 하나가 여섯 마음결로 갈라지는 계보 미리보기.
///
/// 예전에는 일곱 칸을 한 줄로 세웠다. 도감 카드는 세로로 긴데 가로 한 줄은
/// `scaleDown`에 눌려 카드 높이의 1/6만 쓰는 얇은 띠가 되고, 위아래가 텅 빈
/// 카드로 보였다. 씨앗을 위에 두고 여섯 결을 3×2로 접어 같은 정보로 칸을
/// 채운다.
class _GrowthLineagePreview extends StatelessWidget {
  const _GrowthLineagePreview({
    required this.speciesCode,
    required this.speciesName,
  });

  final String speciesCode;
  final String speciesName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const forms = PlantGrowthForm.values;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlantStagePreview(
            stage: 1,
            speciesCode: speciesCode,
            speciesName: speciesName,
            size: 54,
          ),
          Icon(
            Icons.call_split_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          for (var row = 0; row < 2; row++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final form in forms.skip(row * 3).take(3))
                  PlantStagePreview(
                    stage: 5,
                    form: form,
                    speciesCode: speciesCode,
                    speciesName: speciesName,
                    size: 46,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CharacterLineageCard extends StatelessWidget {
  const _CharacterLineageCard({required this.item});

  final ShopItem item;

  void _showGrowthAtlas(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CharacterGrowthAtlasSheet(
        name: item.name,
        speciesCode: item.growthSpeciesCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = !item.owned;
    final growthLine = _GrowthLineagePreview(
      speciesCode: item.growthSpeciesCode,
      speciesName: item.name,
    );
    return Semantics(
      label: locked
          ? '${item.name}, 아직 만나지 못한 성장 캐릭터'
          : '${item.name}, 씨앗에서 사람형 완전체까지 자라는 성장 캐릭터',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: locked ? null : () => _showGrowthAtlas(context),
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
                    padding: const EdgeInsets.all(8),
                    child: locked
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              ColorFiltered(
                                colorFilter: kMongrooGreyscale,
                                child: Opacity(opacity: .32, child: growthLine),
                              ),
                              Icon(
                                Icons.lock_outline,
                                size: 36,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          )
                        : growthLine,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  locked ? '아직 비밀이에요' : item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  locked ? '해금하면 씨앗부터 함께 키울 수 있어요' : '씨앗부터 여섯 감정의 성인 모습까지 성장',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterGrowthAtlasSheet extends StatelessWidget {
  const _CharacterGrowthAtlasSheet({
    required this.name,
    required this.speciesCode,
  });

  final String name;
  final String speciesCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: .9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name 감정별 성장 도감',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '씨앗 · 새싹 · 유아기 · 성장기 · 성인',
                        style: TextStyle(color: scheme.onSurfaceVariant),
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
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: PlantGrowthForm.values.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final form = PlantGrowthForm.values[index];
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${form.emotionLabel} · ${form.label} · ${form.personalityName}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            children: [
                              for (var stage = 1; stage <= 5; stage++)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: PlantStagePreview(
                                    stage: stage,
                                    form: stage >= 2 ? form : null,
                                    speciesCode: speciesCode,
                                    speciesName: name,
                                    size: 82,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogItemCard extends StatefulWidget {
  const _CatalogItemCard({required this.item});

  final ShopItem item;

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
    final canOpenStory = !locked &&
        !item.isGrowthCharacter &&
        (item.hasCollectionStory || item.isMoodResonance);
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
                  : item.isGrowthCharacter
                      ? '${item.name}, 성장 씨앗 해금'
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
                          padding: const EdgeInsets.all(10),
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
                        item.isGrowthCharacter
                            ? locked
                                ? '아직 만나지 못한 성장 씨앗'
                                : '일기로 키우는 다섯 단계 성장 캐릭터'
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
                    if (item.isGrowthCharacter) ...[
                      const SizedBox(height: 3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          locked
                              ? '상점과 작은 행동에서 씨앗을 해금할 수 있어요'
                              : '씨앗 · 새싹 · 줄기 · 개화 · 만개',
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
                  if (item.baseOutfitName case final outfit?)
                    _StoryTag(
                      label: item.includesBaseOutfit
                          ? '기본 재화 복장 · $outfit (구매 시 포함)'
                          : '기본 복장 · $outfit',
                      icon: Icons.checkroom_outlined,
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
