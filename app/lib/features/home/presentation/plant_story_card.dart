import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../domain/plant.dart';
import '../domain/plant_story.dart';
import 'plant_view.dart';

class PlantStoryCard extends StatelessWidget {
  const PlantStoryCard({
    super.key,
    required this.plant,
    required this.onMuseum,
  });

  final ActivePlant plant;
  final VoidCallback onMuseum;

  Future<void> _showStory(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 620),
        builder: (context) => _PlantStorySheet(
          plant: plant,
          onMuseum: () {
            Navigator.of(context).pop();
            onMuseum();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final current = plant.currentStoryChapter;
    final next = plant.nextStoryChapter;
    return MongrooPressable(
      onTap: () => _showStory(context),
      semanticLabel:
          '${plant.name}의 성장 이야기, ${current.stageLabel}, ${current.title}',
      child: MongrooPanel(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        shadowOffset: const Offset(3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MongrooTag(
                        label: '${plant.name}의 연재 일지',
                        icon: Icons.auto_stories_outlined,
                        maxWidth: (constraints.maxWidth - 54).clamp(80, 420),
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${plant.stage}/5장',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final chapter in plant.storyChapters) ...[
                  Expanded(
                    child: _ChapterNode(chapter: chapter, plant: plant),
                  ),
                  if (chapter.stage < 5)
                    Container(
                      width: 8,
                      height: 2,
                      color: chapter.stage < plant.stage
                          ? palette.leaf
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
            const SizedBox(height: 15),
            Text(
              current.title,
              style: const TextStyle(
                fontFamily: AppTheme.pixelFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              current.story,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.inkMuted, height: 1.45),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  next == null
                      ? Icons.account_balance_outlined
                      : Icons.lock_open_rounded,
                  size: 17,
                  color: palette.inkMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    next == null
                        ? '마지막 장면은 박물관에서 오래 남길 수 있어요.'
                        : '${next.stageLabel}에서 「${next.title}」이 열려요.',
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterNode extends StatelessWidget {
  const _ChapterNode({required this.chapter, required this.plant});

  final PlantStoryChapter chapter;
  final ActivePlant plant;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final color = chapter.current
        ? palette.butter
        : chapter.unlocked
            ? palette.leaf
            : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label:
          '${chapter.stageLabel}, ${chapter.unlocked ? chapter.title : '아직 잠김'}',
      child: ExcludeSemantics(
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withAlpha(chapter.unlocked ? 95 : 150),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: chapter.current ? palette.night : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: chapter.unlocked ? 1 : .32,
                child: FittedBox(
                  child: PlantStagePreview(
                    stage: chapter.stage,
                    form: _previewForm(plant, chapter.stage),
                    secondaryForm:
                        chapter.stage >= 4 ? plant.secondaryForm : null,
                    speciesCode: plant.species.code,
                    speciesName: plant.species.name,
                    growthVisual: plant.growthVisual,
                    size: 50,
                  ),
                ),
              ),
              if (!chapter.unlocked)
                Icon(Icons.lock_outline_rounded,
                    size: 17, color: palette.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantStorySheet extends StatelessWidget {
  const _PlantStorySheet({required this.plant, required this.onMuseum});

  final ActivePlant plant;
  final VoidCallback onMuseum;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      minChildSize: .45,
      maxChildSize: .92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text(
            '${plant.name}의 다섯 장 이야기',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            '일기가 쌓일수록 외형과 성격이 갈라지고, 한 장씩 새로운 장면이 열려요.',
            style: TextStyle(color: palette.inkMuted, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (plant.stage >= 3)
            _EmotionMixCard(profile: plant.emotionProfile)
          else if (plant.stage == 2)
            const _SproutStageEmotionCard()
          else
            const _SeedStageEmotionCard(),
          if (plant.stage >= 3 && plant.growthTraits.hasContent) ...[
            const SizedBox(height: 12),
            _CharacterGrowthCard(plant: plant),
          ],
          const SizedBox(height: 18),
          for (final chapter in plant.storyChapters) ...[
            _StoryChapterTile(chapter: chapter, plant: plant),
            const SizedBox(height: 10),
          ],
          // B1은 3단계(Lv9)에 열린다. 그 전에는 넣을 칸이 없어 보여 주지 않는다.
          if (plant.stage >= 3) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              key: const ValueKey('plant-detail-skill-books'),
              onPressed: () => context.push(
                '/skill-books/${plant.id}?name=${Uri.encodeComponent(plant.name)}',
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('마음결 기록서 정리하기'),
            ),
          ],
          if (plant.stage >= 5) ...[
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: onMuseum,
              icon: const Icon(Icons.account_balance_outlined),
              label: const Text('식물 박물관 둘러보기'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CharacterGrowthCard extends StatelessWidget {
  const _CharacterGrowthCard({required this.plant});

  final ActivePlant plant;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final traits = plant.growthTraits;
    final dominant = plant.dominantForm?.label ?? '관찰 중';
    final secondary = plant.secondaryForm?.label;
    final summary = [
      '주결 $dominant',
      if (secondary != null) '보조결 $secondary',
      if (plant.temperamentSummary.isNotEmpty) plant.temperamentSummary,
    ].join(', ');
    return Semantics(
      container: true,
      label: '${plant.personalityName}. $summary',
      child: MongrooPanel(
        color: palette.sky.withAlpha(92),
        shadowOffset: const Offset(2, 2),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.theater_comedy_outlined,
                    size: 18, color: palette.leaf),
                const SizedBox(width: 7),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      plant.personalityName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                Text(
                  '${plant.stage}단계 성격',
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  if (plant.dominantForm case final dominant?)
                    MongrooTag(
                      label: '주결 · ${dominant.label}',
                      icon: _emotionIcon(dominant),
                      maxWidth: constraints.maxWidth,
                    ),
                  if (plant.secondaryForm case final secondary?)
                    MongrooTag(
                      label: '보조결 · ${secondary.label}',
                      icon: _emotionIcon(secondary),
                      maxWidth: constraints.maxWidth,
                    ),
                  for (final trait in traits.traits.take(3))
                    MongrooTag(
                      label: trait,
                      maxWidth: constraints.maxWidth,
                    ),
                ],
              ),
            ),
            if (plant.temperamentSummary.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                plant.temperamentSummary,
                style: TextStyle(color: palette.inkMuted, height: 1.4),
              ),
            ],
            if (traits.nextReveal.trim().isNotEmpty && plant.stage < 5) ...[
              const SizedBox(height: 8),
              Text(
                traits.nextReveal,
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 15, color: palette.inkMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '일기에서 자란 식물 캐릭터의 설정이에요. 사용자의 성격을 진단하거나 성장 속도·보상을 바꾸지 않아요.',
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 10.5,
                      height: 1.4,
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
}

class _StoryChapterTile extends StatelessWidget {
  const _StoryChapterTile({required this.chapter, required this.plant});

  final PlantStoryChapter chapter;
  final ActivePlant plant;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      color: chapter.current ? palette.butter.withAlpha(105) : null,
      shadowOffset: const Offset(2, 2),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: chapter.unlocked
                  ? palette.leaf.withAlpha(75)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: chapter.unlocked ? 1 : .3,
                  child: PlantStagePreview(
                    stage: chapter.stage,
                    form: _previewForm(plant, chapter.stage),
                    secondaryForm:
                        chapter.stage >= 4 ? plant.secondaryForm : null,
                    speciesCode: plant.species.code,
                    speciesName: plant.species.name,
                    growthVisual: plant.growthVisual,
                    size: 58,
                  ),
                ),
                if (!chapter.unlocked)
                  const Icon(Icons.lock_outline_rounded, size: 18),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.stageLabel,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chapter.unlocked ? chapter.title : '아직 열리지 않은 장면',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  chapter.unlocked
                      ? chapter.story
                      : '${plantStageName(chapter.stage)} 단계가 되면 이야기를 읽을 수 있어요.',
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

PlantGrowthForm? _previewForm(ActivePlant plant, int stage) {
  if (stage <= 1) return null;
  if (stage == 2) {
    return plant.stage >= 2 ? plant.emotionProfile.leadingCue : null;
  }
  if (plant.stage < 3) return null;
  return plant.growthForm;
}

class _SeedStageEmotionCard extends StatelessWidget {
  const _SeedStageEmotionCard();

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      color: Theme.of(context).colorScheme.tertiaryContainer.withAlpha(120),
      shadowOffset: const Offset(2, 2),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.spa_outlined, size: 18, color: palette.leaf),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '씨앗 안에서는 아직 마음빛이 겉으로 드러나지 않아요. '
              '새싹이 돋으면 일기에서 읽은 첫 단서가 보이기 시작해요.',
              style: TextStyle(color: palette.inkMuted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _SproutStageEmotionCard extends StatelessWidget {
  const _SproutStageEmotionCard();

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      color: Theme.of(context).colorScheme.tertiaryContainer.withAlpha(120),
      shadowOffset: const Offset(2, 2),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.grass_rounded, size: 18, color: palette.leaf),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '새싹에 첫 마음빛이 번지고 있어요. 아직 한 가지 이름으로 정하지 않고, '
              '기록이 더 쌓이면 줄기와 성격으로 천천히 드러나요.',
              style: TextStyle(color: palette.inkMuted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmotionMixCard extends StatelessWidget {
  const _EmotionMixCard({required this.profile});

  final ActivePlantEmotionProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final cues = profile.topCues();
    return MongrooPanel(
      color: Theme.of(context).colorScheme.tertiaryContainer.withAlpha(120),
      shadowOffset: const Offset(2, 2),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.blur_circular_rounded, size: 18, color: palette.leaf),
              const SizedBox(width: 7),
              const Text(
                '마음빛 조합',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (cues.isEmpty)
            Text(
              '아직 읽힌 마음빛이 없어요. 일기가 쌓이면 이곳에 첫 단서가 나타나요.',
              style: TextStyle(color: palette.inkMuted, height: 1.45),
            )
          else
            for (final cue in cues) ...[
              _EmotionCueBar(cue: cue),
              if (cue != cues.last) const SizedBox(height: 10),
            ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.balance_rounded, size: 16, color: palette.inkMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '어떤 마음도 실패가 아니에요. 마음빛은 모습과 성격만 바꾸고 '
                  '성장 속도·보상에는 영향을 주지 않아요.',
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmotionCueBar extends StatelessWidget {
  const _EmotionCueBar({required this.cue});

  final PlantEmotionCue cue;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final ratio = cue.ratio.clamp(0.0, 1.0).toDouble();
    final percent = (ratio * 100).round();
    return Semantics(
      label: '${cue.form.emotionLabel} 마음빛 $percent퍼센트',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_emotionIcon(cue.form), size: 15, color: palette.ink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cue.form.emotionLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: ratio,
                        child:
                            ColoredBox(color: _emotionColor(cue.form, palette)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _emotionIcon(PlantGrowthForm form) => switch (form) {
      PlantGrowthForm.sunny => Icons.wb_sunny_outlined,
      PlantGrowthForm.rainy => Icons.water_drop_outlined,
      PlantGrowthForm.ember => Icons.local_fire_department_outlined,
      PlantGrowthForm.moonlit => Icons.dark_mode_outlined,
      PlantGrowthForm.sparkling => Icons.auto_awesome_outlined,
      PlantGrowthForm.mosaic => Icons.interests_outlined,
    };

Color _emotionColor(PlantGrowthForm form, MongrooPalette palette) =>
    switch (form) {
      PlantGrowthForm.sunny => palette.butter,
      PlantGrowthForm.rainy =>
        ThemeData.estimateBrightnessForColor(palette.paper) == Brightness.dark
            ? const Color(0xFF8FC7E6)
            : const Color(0xFF5C8BA7),
      PlantGrowthForm.ember => palette.coral,
      PlantGrowthForm.moonlit =>
        ThemeData.estimateBrightnessForColor(palette.paper) == Brightness.dark
            ? const Color(0xFFC2B5E8)
            : const Color(0xFF76699D),
      PlantGrowthForm.sparkling => palette.wood,
      PlantGrowthForm.mosaic => palette.leaf,
    };
