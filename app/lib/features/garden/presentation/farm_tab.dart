import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/domain/plant.dart';
import '../../home/presentation/home_controller.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/garden_models.dart';
import 'garden_controller.dart';
import 'garden_item_visual.dart';

/// 바닥 장식과 0 이하 z 장식은 캐릭터 뒤 레이어에 그린다.
///
/// 구름 러그는 배치 순서상 z값이 높아도 발 아래에 깔리는 바닥 소품이므로
/// 캐릭터를 가리지 않도록 항상 뒤로 보낸다.
@visibleForTesting
bool gardenDecorationRendersBehindCharacters(ShopItem item, int zIndex) =>
    zIndex <= 0 ||
    item.code == 'deco_rug_cloud' ||
    item.assetKey == 'deco/rug_cloud';

class FarmTab extends ConsumerStatefulWidget {
  const FarmTab({super.key});

  @override
  ConsumerState<FarmTab> createState() => _FarmTabState();
}

class _FarmTabState extends ConsumerState<FarmTab> {
  int? _selectedDecorationId;

  Future<void> _save() async {
    final saved = await ref.read(farmControllerProvider.notifier).save();
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('나만의 방 배치를 저장했어요.')),
    );
    setState(() => _selectedDecorationId = null);
  }

  Future<void> _retryConflict() async {
    final saved =
        await ref.read(farmControllerProvider.notifier).retryConflict();
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('보관한 내 배치로 방을 저장했어요.')),
      );
    setState(() => _selectedDecorationId = null);
  }

  void _useLatestLayout() {
    ref.read(farmControllerProvider.notifier).useLatestLayout();
    setState(() => _selectedDecorationId = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('다른 기기에서 저장한 최신 배치를 불러왔어요.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(farmControllerProvider);
    final activePlant = ref.watch(homeControllerProvider).valueOrNull;
    ref.listen(
      farmControllerProvider.select((value) => value.actionError),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next)));
        ref.read(farmControllerProvider.notifier).clearActionError();
      },
    );

    return state.data.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('나만의 방을 준비하고 있어요.'),
          ],
        ),
      ),
      error: (error, _) => _FarmError(
        message: ApiException.from(error).message,
        onRetry: () => ref.read(farmControllerProvider.notifier).load(),
      ),
      data: (data) {
        final draft = state.draft ?? data.layout;
        final editingEnabled = state.editing && !state.saving;
        return RefreshIndicator(
          onRefresh: state.editing
              ? () async {}
              : () => ref.read(farmControllerProvider.notifier).load(),
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FarmToolbar(
                          editing: state.editing,
                          saving: state.saving,
                          hasConflict: state.conflict != null,
                          onEdit: () => ref
                              .read(farmControllerProvider.notifier)
                              .beginEditing(),
                          onCancel: () {
                            ref
                                .read(farmControllerProvider.notifier)
                                .cancelEditing();
                            setState(() => _selectedDecorationId = null);
                          },
                          onSave: _save,
                        ),
                        if (state.conflict != null) ...[
                          const SizedBox(height: 12),
                          _FarmConflictNotice(
                            saving: state.saving,
                            onUseLatest: _useLatestLayout,
                            onRetryLocal: _retryConflict,
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (constraints.maxWidth >= 900)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _RoomCanvas(
                                  data: data,
                                  layout: draft,
                                  activePlant: activePlant,
                                  editing: editingEnabled,
                                  selectedDecorationId: _selectedDecorationId,
                                  onSelectDecoration: (id) => setState(
                                      () => _selectedDecorationId = id),
                                  onMoveDecoration: (id, x, y) => ref
                                      .read(farmControllerProvider.notifier)
                                      .moveDecoration(id, x: x, y: y),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: _FarmControls(
                                  data: data,
                                  layout: draft,
                                  activePlant: activePlant,
                                  editing: editingEnabled,
                                  selectedDecorationId: _selectedDecorationId,
                                  onSelectDecoration: (id) => setState(
                                      () => _selectedDecorationId = id),
                                ),
                              ),
                            ],
                          )
                        else ...[
                          _RoomCanvas(
                            data: data,
                            layout: draft,
                            activePlant: activePlant,
                            editing: editingEnabled,
                            selectedDecorationId: _selectedDecorationId,
                            onSelectDecoration: (id) =>
                                setState(() => _selectedDecorationId = id),
                            onMoveDecoration: (id, x, y) => ref
                                .read(farmControllerProvider.notifier)
                                .moveDecoration(id, x: x, y: y),
                          ),
                          const SizedBox(height: 16),
                          _FarmControls(
                            data: data,
                            layout: draft,
                            activePlant: activePlant,
                            editing: editingEnabled,
                            selectedDecorationId: _selectedDecorationId,
                            onSelectDecoration: (id) =>
                                setState(() => _selectedDecorationId = id),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FarmToolbar extends StatelessWidget {
  const _FarmToolbar({
    required this.editing,
    required this.saving,
    required this.hasConflict,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  final bool editing;
  final bool saving;
  final bool hasConflict;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (hasConflict)
          const SizedBox.shrink()
        else if (!editing)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 48),
              backgroundColor: palette.butter,
              foregroundColor: palette.night,
            ),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('꾸미기'),
          )
        else ...[
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(72, 48),
              foregroundColor: palette.ink,
            ),
            onPressed: saving ? null : onCancel,
            child: const Text('취소'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(104, 48),
              backgroundColor: palette.leaf,
              foregroundColor: scheme.onPrimary,
            ),
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saving ? '저장 중…' : '저장'),
          ),
        ],
      ],
    );
    const title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '나만의 마음 정원',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 2),
        Text('모은 캐릭터와 아이템으로 편안한 공간을 꾸며 보세요.'),
      ],
    );

    return MongrooPanel(
      color: palette.paper,
      borderColor: palette.night.withAlpha(82),
      radius: 12,
      shadowOffset: const Offset(3, 3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520 || textScale > 1.4) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                if (!hasConflict) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              if (!hasConflict) ...[
                const SizedBox(width: 12),
                actions,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FarmConflictNotice extends StatelessWidget {
  const _FarmConflictNotice({
    required this.saving,
    required this.onUseLatest,
    required this.onRetryLocal,
  });

  final bool saving;
  final VoidCallback onUseLatest;
  final VoidCallback onRetryLocal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: MongrooPanel(
        color: Color.alphaBlend(scheme.error.withAlpha(28), palette.paper),
        borderColor: scheme.error.withAlpha(150),
        radius: 12,
        shadowOffset: const Offset(3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sync_problem_outlined, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '방이 다른 기기에서 바뀌었어요',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '지금 꾸민 배치는 안전하게 보관했어요. 최신 배치를 불러오면 이 초안은 '
                        '사라지고, 내 배치를 다시 저장하면 다른 기기의 최신 배치를 교체해요.',
                        style: TextStyle(color: palette.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(164, 48),
                    foregroundColor: palette.ink,
                    backgroundColor: Color.alphaBlend(
                      palette.leaf.withAlpha(54),
                      palette.paper,
                    ),
                    side: BorderSide(color: palette.ink.withAlpha(150)),
                  ),
                  onPressed: saving ? null : onUseLatest,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('최신 배치 불러오기'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(172, 48),
                    backgroundColor: palette.coral,
                    foregroundColor: scheme.onTertiary,
                  ),
                  onPressed: saving ? null : onRetryLocal,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_as_outlined),
                  label: Text(saving ? '다시 저장 중…' : '내 배치 다시 저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCanvas extends StatelessWidget {
  const _RoomCanvas({
    required this.data,
    required this.layout,
    required this.activePlant,
    required this.editing,
    required this.selectedDecorationId,
    required this.onSelectDecoration,
    required this.onMoveDecoration,
  });

  final FarmData data;
  final FarmLayout layout;
  final ActivePlant? activePlant;
  final bool editing;
  final int? selectedDecorationId;
  final ValueChanged<int> onSelectDecoration;
  final void Function(int id, double x, double y) onMoveDecoration;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final roomAspectRatio =
        MediaQuery.sizeOf(context).width < 600 ? 4 / 3 : 16 / 9;
    final theme = data.itemByUserItemId(layout.roomThemeUserItemId);
    final companions = layout.companionUserItemIds
        .map(data.itemByUserItemId)
        .whereType<UserGardenItem>()
        .toList();
    final decorations = [...layout.decorations]..sort((left, right) {
        final byZ = left.zIndex.compareTo(right.zIndex);
        return byZ != 0 ? byZ : left.userItemId.compareTo(right.userItemId);
      });
    final lowDecorations = decorations.where((decoration) {
      final entry = data.itemByUserItemId(decoration.userItemId);
      return entry != null &&
          gardenDecorationRendersBehindCharacters(
            entry.item,
            decoration.zIndex,
          );
    }).toList(growable: false);
    final highDecorations = decorations
        .where((decoration) => !lowDecorations.contains(decoration))
        .toList(growable: false);

    return MongrooPanel(
      padding: EdgeInsets.zero,
      color: palette.paper,
      borderColor: palette.night.withAlpha(96),
      radius: 12,
      shadowOffset: const Offset(3, 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: roomAspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              Widget decorationWidget(FarmDecoration decoration) =>
                  _PositionedDecoration(
                    key: ValueKey(
                      'farm-decoration-${decoration.userItemId}',
                    ),
                    decoration: decoration,
                    entry: data.itemByUserItemId(decoration.userItemId),
                    canvasWidth: width,
                    canvasHeight: height,
                    editing: editing,
                    selected: selectedDecorationId == decoration.userItemId,
                    onSelect: () => onSelectDecoration(decoration.userItemId),
                    onMove: (x, y) =>
                        onMoveDecoration(decoration.userItemId, x, y),
                  );
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: theme == null
                        ? Image.asset(
                            gardenDefaultRoomAssetPath,
                            key: const ValueKey('farm-default-room'),
                            fit: BoxFit.cover,
                            semanticLabel: '따뜻한 햇살이 드는 기본 온실 방',
                          )
                        : GardenItemVisual(
                            key: const ValueKey('farm-equipped-room'),
                            item: theme.item,
                            fit: BoxFit.cover,
                          ),
                  ),
                  for (final decoration in lowDecorations)
                    decorationWidget(decoration),
                  if (activePlant != null)
                    Positioned(
                      width: math.min(width * 0.3, 144.0),
                      height: math.min(height * 0.48, 174.0),
                      left: width * 0.35,
                      bottom: height * 0.06,
                      child: PlantView(
                        key: ValueKey(
                          'farm-growth-character-${activePlant!.visualKey}',
                        ),
                        stage: activePlant!.stage,
                        form: activePlant!.visualForm,
                        secondaryForm: activePlant!.secondaryForm,
                        speciesCode: activePlant!.species.code,
                        speciesName: activePlant!.species.name,
                        growthVisual: activePlant!.growthVisual,
                        width: math.min(width * 0.3, 144.0),
                        height: math.min(height * 0.48, 174.0),
                      ),
                    ),
                  for (var index = 0; index < companions.length; index++)
                    Positioned(
                      width: math.min(width * 0.17, 86.0),
                      height: math.min(height * 0.25, 92.0),
                      left: index.isEven
                          ? width * (0.12 + (index ~/ 2) * 0.12)
                          : null,
                      right: index.isOdd
                          ? width * (0.12 + (index ~/ 2) * 0.12)
                          : null,
                      bottom: height * 0.1,
                      child: GardenItemVisual(
                        key: ValueKey('farm-companion-$index'),
                        item: companions[index].item,
                        animateIdle: false,
                      ),
                    ),
                  for (final decoration in highDecorations)
                    decorationWidget(decoration),
                  if (editing)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: MongrooTag(
                        label: '드래그해서 위치 조절',
                        icon: Icons.open_with_rounded,
                        backgroundColor: palette.night,
                        foregroundColor: palette.paper,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PositionedDecoration extends StatelessWidget {
  const _PositionedDecoration({
    super.key,
    required this.decoration,
    required this.entry,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.editing,
    required this.selected,
    required this.onSelect,
    required this.onMove,
  });

  final FarmDecoration decoration;
  final UserGardenItem? entry;
  final double canvasWidth;
  final double canvasHeight;
  final bool editing;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double x, double y) onMove;

  @override
  Widget build(BuildContext context) {
    if (entry == null) return const SizedBox.shrink();
    final palette = MongrooPalette.of(context);
    final size = (72 * decoration.scale).clamp(48.0, 144.0).toDouble();
    final availableWidth = math.max(1.0, canvasWidth - size);
    final availableHeight = math.max(1.0, canvasHeight - size);
    return Positioned(
      left: decoration.x * availableWidth,
      top: decoration.y * availableHeight,
      width: size,
      height: size,
      child: Semantics(
        button: editing,
        selected: selected,
        label: '${entry!.item.name} 꾸미기 아이템',
        hint: editing ? '끌어서 위치를 옮길 수 있어요.' : null,
        child: GestureDetector(
          onTap: editing ? onSelect : null,
          onPanStart: editing ? (_) => onSelect() : null,
          onPanUpdate: editing
              ? (details) {
                  final x = (decoration.x + details.delta.dx / availableWidth)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  final y = (decoration.y + details.delta.dy / availableHeight)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  onMove(x, y);
                }
              : null,
          child: Transform.rotate(
            angle: decoration.rotation,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: selected
                    ? Border.all(color: palette.coral, width: 3)
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: GardenItemVisual(item: entry!.item),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FarmControls extends ConsumerWidget {
  const _FarmControls({
    required this.data,
    required this.layout,
    required this.activePlant,
    required this.editing,
    required this.selectedDecorationId,
    required this.onSelectDecoration,
  });

  final FarmData data;
  final FarmLayout layout;
  final ActivePlant? activePlant;
  final bool editing;
  final int? selectedDecorationId;
  final ValueChanged<int?> onSelectDecoration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(farmControllerProvider.notifier);
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final themes = data.itemsOfType('room_theme');
    final companions = data.itemsOfType('companion');
    final decorations = data.itemsOfType('deco');
    FarmDecoration? selected;
    for (final item in layout.decorations) {
      if (item.userItemId == selectedDecorationId) selected = item;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ControlSection(
          title: '방 테마',
          child: FarmRoomThemePicker(
            themes: themes,
            selectedUserItemId: layout.roomThemeUserItemId,
            enabled: editing,
            onSelected: controller.equipRoomTheme,
          ),
        ),
        const SizedBox(height: 12),
        _ControlSection(
          title: '성장 캐릭터',
          child: Text(
            activePlant == null
                ? '홈에서 씨앗을 심으면 이 방에도 같은 캐릭터가 찾아와요.'
                : '${activePlant!.name} · ${plantStageName(activePlant!.stage)} 단계\n'
                    '홈과 대화에서 키우는 바로 그 캐릭터가 방에도 함께 있어요.',
          ),
        ),
        const SizedBox(height: 12),
        _ControlSection(
          title: '동행 친구',
          child: companions.isEmpty
              ? const Text('보유한 동행 친구가 없어요.')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in companions)
                      FilterChip(
                        label: Text(entry.item.name),
                        selected:
                            layout.companionUserItemIds.contains(entry.id),
                        selectedColor: palette.butter.withAlpha(92),
                        checkmarkColor: palette.leaf,
                        side: BorderSide(
                          color: layout.companionUserItemIds.contains(entry.id)
                              ? palette.leaf
                              : scheme.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: editing
                            ? (_) => controller.toggleCompanion(entry.id)
                            : null,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _ControlSection(
          title: '꾸미기 아이템',
          child: decorations.isEmpty
              ? const Text('상점에서 꾸미기 아이템을 모아 보세요.')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in decorations)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(112, 48),
                          foregroundColor: palette.ink,
                          backgroundColor: Color.alphaBlend(
                            palette.leaf.withAlpha(54),
                            palette.paper,
                          ),
                          side: BorderSide(color: palette.ink.withAlpha(150)),
                        ),
                        onPressed: editing
                            ? () {
                                controller.placeDecoration(entry.id);
                                onSelectDecoration(entry.id);
                              }
                            : null,
                        icon: Icon(
                          layout.decorations
                                  .any((item) => item.userItemId == entry.id)
                              ? Icons.check
                              : Icons.add,
                        ),
                        label: Text(entry.item.name),
                      ),
                  ],
                ),
        ),
        if (editing && selected != null) ...[
          const SizedBox(height: 12),
          _DecorationEditor(
            decoration: selected,
            name: data.itemByUserItemId(selected.userItemId)?.item.name ??
                '꾸미기 아이템',
            onMove: (x, y) => controller.moveDecoration(
              selected!.userItemId,
              x: x,
              y: y,
            ),
            onScale: (value) =>
                controller.scaleDecoration(selected!.userItemId, value),
            onRotate: (value) =>
                controller.rotateDecoration(selected!.userItemId, value),
            onRemove: () {
              controller.removeDecoration(selected!.userItemId);
              onSelectDecoration(null);
            },
          ),
        ],
      ],
    );
  }
}

/// 보유한 방 테마를 썸네일로 고른다.
class FarmRoomThemePicker extends StatelessWidget {
  const FarmRoomThemePicker({
    super.key,
    required this.themes,
    required this.selectedUserItemId,
    required this.enabled,
    required this.onSelected,
  });

  final List<UserGardenItem> themes;
  final int? selectedUserItemId;
  final bool enabled;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final oneColumn = constraints.maxWidth < 280 || textScale > 1.55;
        final cardWidth =
            oneColumn ? constraints.maxWidth : (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: cardWidth,
              child: _RoomThemeThumbnail(
                name: '기본 방',
                selected: selectedUserItemId == null,
                enabled: enabled,
                onTap: () => onSelected(null),
              ),
            ),
            for (final entry in themes)
              SizedBox(
                width: cardWidth,
                child: _RoomThemeThumbnail(
                  name: entry.item.name,
                  item: entry.item,
                  selected: selectedUserItemId == entry.id,
                  enabled: enabled,
                  onTap: () => onSelected(entry.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RoomThemeThumbnail extends StatelessWidget {
  const _RoomThemeThumbnail({
    required this.name,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.item,
  });

  final String name;
  final ShopItem? item;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final borderColor = selected ? palette.leaf : palette.night.withAlpha(72);
    return Semantics(
      button: enabled,
      selected: selected,
      label: '$name 방 테마',
      hint: enabled
          ? selected
              ? '현재 선택됨'
              : '두 번 탭하여 이 테마 선택'
          : '편집을 시작하면 선택할 수 있어요.',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : .58,
          child: MongrooPanel(
            padding: EdgeInsets.zero,
            color: selected
                ? Color.alphaBlend(
                    palette.butter.withAlpha(46),
                    palette.paper,
                  )
                : palette.paper,
            borderColor: borderColor,
            radius: 12,
            shadowOffset: selected ? const Offset(3, 3) : const Offset(2, 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onTap : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (item == null)
                                Image.asset(
                                  gardenDefaultRoomAssetPath,
                                  key: const ValueKey(
                                    'farm-theme-default-preview',
                                  ),
                                  fit: BoxFit.cover,
                                  cacheWidth: 512,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, __, ___) => ColoredBox(
                                    color: scheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.weekend_outlined,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              else
                                GardenItemVisual(
                                  item: item!,
                                  fit: BoxFit.cover,
                                  animateIdle: false,
                                  cacheWidth: 512,
                                ),
                              if (selected)
                                Positioned(
                                  right: 6,
                                  top: 6,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: palette.leaf,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.check,
                                        size: 15,
                                        color: scheme.onTertiary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w700,
                          color: enabled ? palette.ink : palette.inkMuted,
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

class _ControlSection extends StatelessWidget {
  const _ControlSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      color: palette.paper,
      borderColor: palette.night.withAlpha(72),
      radius: 12,
      shadowOffset: const Offset(3, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MongrooTag(
            label: title,
            backgroundColor: palette.butter,
            foregroundColor: palette.night,
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DecorationEditor extends StatelessWidget {
  const _DecorationEditor({
    required this.decoration,
    required this.name,
    required this.onMove,
    required this.onScale,
    required this.onRotate,
    required this.onRemove,
  });

  final FarmDecoration decoration;
  final String name;
  final void Function(double x, double y) onMove;
  final ValueChanged<double> onScale;
  final ValueChanged<double> onRotate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    const step = 0.05;
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      color: Color.alphaBlend(palette.butter.withAlpha(28), palette.paper),
      borderColor: palette.coral.withAlpha(120),
      radius: 12,
      shadowOffset: const Offset(3, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MongrooTag(
            label: '$name 조절',
            icon: Icons.tune_rounded,
            backgroundColor: palette.coral,
            foregroundColor: Theme.of(context).colorScheme.onTertiary,
          ),
          const SizedBox(height: 10),
          const Text('끌기 대신 방향 버튼으로도 정확하게 움직일 수 있어요.'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ControlIconButton(
                tooltip: '왼쪽으로 이동',
                icon: Icons.arrow_left,
                onPressed: decoration.x <= 0
                    ? null
                    : () => onMove(decoration.x - step, decoration.y),
              ),
              _ControlIconButton(
                tooltip: '오른쪽으로 이동',
                icon: Icons.arrow_right,
                onPressed: decoration.x >= 1
                    ? null
                    : () => onMove(decoration.x + step, decoration.y),
              ),
              _ControlIconButton(
                tooltip: '위로 이동',
                icon: Icons.arrow_upward,
                onPressed: decoration.y <= 0
                    ? null
                    : () => onMove(decoration.x, decoration.y - step),
              ),
              _ControlIconButton(
                tooltip: '아래로 이동',
                icon: Icons.arrow_downward,
                onPressed: decoration.y >= 1
                    ? null
                    : () => onMove(decoration.x, decoration.y + step),
              ),
              _ControlIconButton(
                tooltip: '작게',
                icon: Icons.zoom_out,
                onPressed: decoration.scale <= 0.5
                    ? null
                    : () => onScale(decoration.scale - 0.1),
              ),
              _ControlIconButton(
                tooltip: '크게',
                icon: Icons.zoom_in,
                onPressed: decoration.scale >= 2
                    ? null
                    : () => onScale(decoration.scale + 0.1),
              ),
              _ControlIconButton(
                tooltip: '왼쪽으로 회전',
                icon: Icons.rotate_left,
                onPressed: decoration.rotation <= -math.pi
                    ? null
                    : () => onRotate(decoration.rotation - 0.15),
              ),
              _ControlIconButton(
                tooltip: '오른쪽으로 회전',
                icon: Icons.rotate_right,
                onPressed: decoration.rotation >= math.pi
                    ? null
                    : () => onRotate(decoration.rotation + 0.15),
              ),
              _ControlIconButton(
                tooltip: '방에서 치우기',
                icon: Icons.delete_outline,
                onPressed: onRemove,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlIconButton extends StatelessWidget {
  const _ControlIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final foreground = destructive ? scheme.error : palette.ink;
    return SizedBox.square(
      dimension: 48,
      child: IconButton.outlined(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          foregroundColor: foreground,
          disabledForegroundColor: palette.inkMuted.withAlpha(90),
          side: BorderSide(color: foreground.withAlpha(150)),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _FarmError extends StatelessWidget {
  const _FarmError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.home_work_outlined, size: 44),
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
