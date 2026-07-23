import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../data/plant_repository.dart';
import '../domain/plant.dart';
import 'plant_view.dart';

sealed class SpeciesPickResult {
  const SpeciesPickResult._();

  const factory SpeciesPickResult.plant({
    required int speciesId,
    String? name,
  }) = _PlantSpeciesPickResult;

  const factory SpeciesPickResult.openShop(String speciesCode) =
      _SpeciesShopPickResult;

  int? get speciesId;
  String? get speciesCode;
  String? get name;
  bool get openShop;
}

final class _PlantSpeciesPickResult extends SpeciesPickResult {
  const _PlantSpeciesPickResult({required this.speciesId, this.name})
      : super._();

  @override
  final int speciesId;
  @override
  final String? name;
  @override
  String? get speciesCode => null;
  @override
  bool get openShop => false;
}

final class _SpeciesShopPickResult extends SpeciesPickResult {
  const _SpeciesShopPickResult(this.speciesCode) : super._();

  @override
  final String speciesCode;
  @override
  int? get speciesId => null;
  @override
  String? get name => null;
  @override
  bool get openShop => true;
}

/// 수확 후 새 식물을 심을 때 품종과 이름을 고르는 다이얼로그.
Future<SpeciesPickResult?> showSpeciesPickerDialog(BuildContext context) {
  return showDialog<SpeciesPickResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _SpeciesPickerDialog(),
  );
}

class _SpeciesPickerDialog extends ConsumerStatefulWidget {
  const _SpeciesPickerDialog();

  @override
  ConsumerState<_SpeciesPickerDialog> createState() =>
      _SpeciesPickerDialogState();
}

class _SpeciesPickerDialogState extends ConsumerState<_SpeciesPickerDialog> {
  final _nameController = TextEditingController();
  late Future<List<PlantSpecies>> _speciesFuture;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _speciesFuture = _loadSpecies();
  }

  Future<List<PlantSpecies>> _loadSpecies() async {
    final species = await ref.read(plantRepositoryProvider).getSpecies();
    final initialId = species.where((item) => item.isUnlocked).firstOrNull?.id;
    if (mounted && _selectedId == null && initialId != null) {
      setState(() => _selectedId = initialId);
    }
    return species;
  }

  void _retry() {
    setState(() {
      _selectedId = null;
      _speciesFuture = _loadSpecies();
    });
  }

  void _submit() {
    final selectedId = _selectedId;
    if (selectedId == null) return;
    final name = _nameController.text.trim();
    Navigator.of(context).pop(
      SpeciesPickResult.plant(
        speciesId: selectedId,
        name: name.isEmpty ? null : name,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: viewport.height - 40,
        ),
        child: MongrooPanel(
          padding: EdgeInsets.zero,
          radius: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                MongrooTag(
                                  label: '새 이야기',
                                  icon: Icons.auto_stories_outlined,
                                  backgroundColor: palette.butter,
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  tooltip: '나중에 심기',
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '어떤 씨앗으로 시작할까요?',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '모든 품종은 일기 속 마음에 따라 다른 모습으로 자라요.',
                              style: TextStyle(
                                color: palette.inkMuted,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: palette.paperDeep),
                      FutureBuilder<List<PlantSpecies>>(
                        future: _speciesFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const _PickerLoading();
                          }
                          if (snapshot.hasError) {
                            return _PickerError(
                              message:
                                  ApiException.from(snapshot.error!).message,
                              onRetry: _retry,
                            );
                          }
                          final species =
                              snapshot.data ?? const <PlantSpecies>[];
                          if (species.isEmpty) return const _PickerEmpty();
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 15, 16, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final item in species) ...[
                                  _SpeciesChoiceCard(
                                    key: ValueKey('species-${item.id}'),
                                    species: item,
                                    selected: _selectedId == item.id,
                                    onSelected: item.isUnlocked
                                        ? () => setState(
                                              () => _selectedId = item.id,
                                            )
                                        : () => Navigator.of(context).pop(
                                              SpeciesPickResult.openShop(
                                                item.code,
                                              ),
                                            ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  '식물 이름',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _nameController,
                                  maxLength: 20,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                  decoration: const InputDecoration(
                                    hintText: '비워 두면 기본 이름이 붙어요',
                                    prefixIcon: Icon(Icons.edit_outlined),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Divider(color: palette.paperDeep),
              _PickerActions(
                canSubmit: _selectedId != null,
                onCancel: () => Navigator.of(context).pop(),
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeciesChoiceCard extends StatelessWidget {
  const _SpeciesChoiceCard({
    super.key,
    required this.species,
    required this.selected,
    required this.onSelected,
  });

  final PlantSpecies species;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final visual = PlantGrowthVisual.fromSources(species: species);
    final status = species.isUnlocked
        ? (selected ? '이 씨앗으로 시작' : '보유 중 · 지금 심기')
        : species.unlockPrice == null
            ? '정원 상점에서 해금'
            : '정원 상점 · 씨앗 ${species.unlockPrice}개';
    final semanticLabel = '${species.name}, ${_rarityLabel(species.rarity)}, '
        '${visual.seedLabel}, ${visual.vesselLabel}, $status';

    return MongrooPressable(
      onTap: onSelected,
      semanticLabel: semanticLabel,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : MongrooMotion.standard,
        curve: MongrooMotion.enter,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withAlpha(135)
              : species.isUnlocked
                  ? palette.paper
                  : palette.paperDeep.withAlpha(150),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? palette.night : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: palette.night.withAlpha(24),
                    offset: const Offset(0, 3),
                    blurRadius: 10,
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SeedPreview(
              species: species,
              visual: visual,
              selected: selected,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    species.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: species.isUnlocked
                              ? palette.ink
                              : palette.inkMuted,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _rarityLabel(species.rarity),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: visual.isSpecial ? palette.wood : palette.inkMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${visual.seedLabel} · ${visual.vesselLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        species.isUnlocked
                            ? selected
                                ? Icons.check_circle_rounded
                                : Icons.eco_outlined
                            : Icons.lock_outline_rounded,
                        size: 15,
                        color: species.isUnlocked
                            ? palette.leaf
                            : palette.inkMuted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: species.isUnlocked
                                ? palette.ink
                                : palette.inkMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _SeedPreview extends StatelessWidget {
  const _SeedPreview({
    required this.species,
    required this.visual,
    required this.selected,
  });

  final PlantSpecies species;
  final PlantGrowthVisual visual;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 82,
          height: 92,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.paperDeep,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Opacity(
            opacity: species.isUnlocked ? 1 : .52,
            child: PlantStagePreview(
              stage: 1,
              speciesCode: species.code,
              growthVisual: visual,
              size: 78,
            ),
          ),
        ),
        if (!species.isUnlocked)
          Positioned(
            right: 5,
            top: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.night,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(
                dimension: 27,
                child: Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: AppTheme.onNight,
                ),
              ),
            ),
          ),
        if (selected)
          Positioned(
            left: -3,
            bottom: -3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.leaf,
                shape: BoxShape.circle,
                border: Border.all(color: palette.paper, width: 2),
              ),
              child: const SizedBox.square(
                dimension: 27,
                child: Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppTheme.onNight,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PickerActions extends StatelessWidget {
  const _PickerActions({
    required this.canSubmit,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool canSubmit;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaledLabel = MediaQuery.textScalerOf(context).scale(16);
          final shouldStack = constraints.maxWidth < 300 || scaledLabel > 20;
          final cancel = TextButton(
            onPressed: onCancel,
            child: const Text('나중에'),
          );
          final submit = FilledButton.icon(
            onPressed: canSubmit ? onSubmit : null,
            icon: const Icon(Icons.spa_rounded),
            label: const Text('이 씨앗 심기'),
          );
          if (shouldStack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                submit,
                const SizedBox(height: 4),
                cancel,
              ],
            );
          }
          return Row(
            children: [
              cancel,
              const Spacer(),
              submit,
            ],
          );
        },
      ),
    );
  }
}

class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 46),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('씨앗 서랍을 여는 중…', style: TextStyle(color: palette.inkMuted)),
        ],
      ),
    );
  }
}

class _PickerError extends StatelessWidget {
  const _PickerError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 32, color: palette.inkMuted),
          const SizedBox(height: 12),
          Text(
            '품종을 불러오지 못했어요.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(color: palette.inkMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('다시 불러오기'),
          ),
        ],
      ),
    );
  }
}

class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty();

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Text(
        '지금 심을 수 있는 씨앗이 없어요.\n잠시 후 다시 확인해 주세요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.inkMuted, height: 1.5),
      ),
    );
  }
}

String _rarityLabel(int? rarity) => switch (rarity ?? 1) {
      >= 5 => '신화 품종 · ★★★★★',
      4 => '아주 희귀 · ★★★★',
      3 => '희귀 품종 · ★★★',
      2 => '특별 품종 · ★★',
      _ => '기본 품종 · ★',
    };

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
