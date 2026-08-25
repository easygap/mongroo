import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/branding/mongroo_brand.dart';
import '../../../core/error/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../../core/text/korean_particles.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../gallery/presentation/gallery_screen.dart';
import '../../garden/presentation/garden_controller.dart';
import '../../quest/presentation/quest_controller.dart';
import '../domain/plant.dart';
import 'home_controller.dart';
import 'plant_story_card.dart';
import 'plant_view.dart';
import 'species_picker_dialog.dart';
import 'today_journey_board.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _harvestInFlight = false;
  bool _plantingInFlight = false;

  Future<void> _onHarvest(ActivePlant plant) async {
    if (_harvestInFlight) return;
    setState(() => _harvestInFlight = true);

    try {
      var confirmationHandled = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          void closeOnce(bool result) {
            if (confirmationHandled) return;
            confirmationHandled = true;
            Navigator.of(dialogContext).pop(result);
          }

          return AlertDialog(
            title: const Text('수확하기'),
            content: Text(
              '${koreanSubject(plant.name)} 다 자랐어요. 박물관에 보내고 새 식물을 심을까요?',
            ),
            actions: [
              TextButton(
                onPressed: () => closeOnce(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => closeOnce(true),
                child: const Text('수확하기'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;

      final error =
          await ref.read(homeControllerProvider.notifier).harvest(plant.id);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('박물관에 식물이 도착했어요.')),
      );
      ref.invalidate(galleryControllerProvider);
      final destination = await showModalBottomSheet<_HarvestDestination>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (context) => _HarvestEndingSheet(plant: plant),
      );
      if (!mounted) return;
      if (destination == _HarvestDestination.museum) {
        context.go('/museum');
      } else if (destination == _HarvestDestination.shop) {
        context.go('/garden?tab=1');
      } else if (destination == _HarvestDestination.plantNew) {
        await _plantNew();
      }
    } finally {
      if (mounted) setState(() => _harvestInFlight = false);
    }
  }

  Future<void> _plantNew() async {
    if (_plantingInFlight) return;
    setState(() => _plantingInFlight = true);
    try {
      final pick = await showSpeciesPickerDialog(context);
      if (pick == null || !mounted) return;
      if (pick.openShop) {
        final speciesCode = pick.speciesCode;
        context.go(
          speciesCode == null
              ? '/garden?tab=1'
              : '/garden?tab=1&species=${Uri.encodeQueryComponent(speciesCode)}',
        );
        return;
      }
      final speciesId = pick.speciesId;
      if (speciesId == null) return;
      final previousOutfitKey = ref.read(equippedWardrobeLayerKeyProvider);
      final error = await ref
          .read(homeControllerProvider.notifier)
          .plantNew(speciesId: speciesId, name: pick.name);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      await ref.read(farmControllerProvider.notifier).load();
      if (!mounted) return;
      if (previousOutfitKey != null &&
          ref.read(equippedWardrobeLayerKeyProvider) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('새 품종과 맞지 않는 의상은 자동으로 해제됐어요.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _plantingInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plantAsync = ref.watch(homeControllerProvider);
    ref.listen<AsyncValue<ActivePlant?>>(homeControllerProvider,
        (previous, next) {
      final pendingBefore =
          previous?.valueOrNull?.emotionProfile.pendingCount ?? 0;
      final pendingAfter = next.valueOrNull?.emotionProfile.pendingCount ?? 0;
      if (pendingBefore > 0 && pendingAfter == 0) {
        ref.invalidate(questControllerProvider);
      }
    });
    final nickname =
        ref.watch(authControllerProvider.select((s) => s.user?.nickname ?? ''));
    final seedBalance = ref
        .watch(authControllerProvider.select((s) => s.user?.seedBalance ?? 0));
    final analysisAcknowledged = ref.watch(plantReactionProvider);
    final questFeed = ref.watch(questControllerProvider).feed.valueOrNull;
    final outfitKey = ref.watch(equippedWardrobeLayerKeyProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
        titleSpacing: 20,
        title: const _HomeWordmark(),
        actions: [
          _SeedToken(value: seedBalance),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '마음 식물 박물관',
            onPressed: () => context.go('/museum'),
            icon: const Icon(Icons.account_balance_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '메뉴',
            onSelected: (value) {
              if (value == 'account') {
                context.push('/account');
              } else if (value == 'logout') {
                ref.read(authControllerProvider.notifier).logout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'account', child: Text('계정과 데이터')),
              PopupMenuItem(value: 'logout', child: Text('로그아웃')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(homeControllerProvider.notifier).refresh(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final plantCard = plantAsync.when(
              loading: () => const SizedBox(
                height: 420,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _ErrorCard(
                message: ApiException.from(error).message,
                onRetry: () =>
                    ref.read(homeControllerProvider.notifier).refresh(),
              ),
              data: (plant) => plant == null
                  ? _EmptyPlantCard(
                      onPlant: _harvestInFlight || _plantingInFlight
                          ? null
                          : _plantNew,
                    )
                  : _PlantCard(
                      plant: plant,
                      outfitKey: outfitKey,
                      expression: analysisAcknowledged
                          ? PlantExpression.acknowledged
                          : PlantExpression.neutral,
                      harvesting: _harvestInFlight,
                      onChat: () => context.push('/chat'),
                      onHarvest:
                          _harvestInFlight ? null : () => _onHarvest(plant),
                    ),
            );
            final journeyBoard = TodayJourneyBoard(
              onRecord: () => context.push('/record'),
              onQuest: () => context.push('/quests'),
              onChat: () => context.push('/chat'),
              onSafety: () => context.push('/safety'),
            );
            final currentPlant = plantAsync.valueOrNull;
            final storyCard = currentPlant == null
                ? null
                : PlantStoryCard(
                    plant: currentPlant,
                    onMuseum: () => context.go('/museum'),
                  );
            final unlockCard = questFeed?.journey.nextUnlock == null
                ? null
                : NextUnlockCard(
                    progress: questFeed!.journey,
                    onOpen: () => context.go('/garden?tab=1'),
                  );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                wide ? 32 : 20,
                12,
                wide ? 32 : 20,
                32,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HomeGreeting(
                          nickname: nickname,
                          recordedToday: questFeed == null
                              ? null
                              : questFeed.contextStatus != 'record_optional',
                        ),
                        const SizedBox(height: 20),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  children: [
                                    plantCard,
                                    if (storyCard != null) ...[
                                      const SizedBox(height: 16),
                                      storyCard,
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    journeyBoard,
                                    if (unlockCard != null) ...[
                                      const SizedBox(height: 16),
                                      unlockCard,
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          )
                        else ...[
                          plantCard,
                          const SizedBox(height: 14),
                          journeyBoard,
                          if (storyCard != null) ...[
                            const SizedBox(height: 14),
                            storyCard,
                          ],
                          if (unlockCard != null) ...[
                            const SizedBox(height: 14),
                            unlockCard,
                          ],
                        ],
                      ],
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

enum _HarvestDestination { museum, shop, plantNew, stay }

class _HarvestEndingSheet extends StatelessWidget {
  const _HarvestEndingSheet({required this.plant});

  final ActivePlant plant;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final formName = plant.growthForm?.label ?? '마음꽃';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: MongrooTag(
              label: '제5장 · 이야기 완성',
              icon: Icons.auto_stories_outlined,
              backgroundColor: palette.butter,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${plant.name}의 이야기를 보관했어요',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${plant.species.name} · $formName\n함께 쌓은 마음빛과 마지막 모습이 박물관 표본으로 오래 남아요. 첫 수확이라면 같은 조건의 마음결 기념품도 열려요.',
            style: TextStyle(color: palette.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(
              _HarvestDestination.museum,
            ),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('박물관에서 첫 전시 보기'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(
              _HarvestDestination.shop,
            ),
            icon: const Icon(Icons.redeem_outlined),
            label: const Text('마음결 기념품 확인하기'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(
              _HarvestDestination.plantNew,
            ),
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('다음 식물 심기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              _HarvestDestination.stay,
            ),
            child: const Text('잠시 여운 남기기'),
          ),
        ],
      ),
    );
  }
}

class _HomeWordmark extends StatelessWidget {
  const _HomeWordmark();

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Semantics(
      header: true,
      label: '몽그루',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MongrooBrandMark(size: 34, withPlate: true),
            const SizedBox(width: 9),
            Text(
              '몽그루',
              style: TextStyle(
                color: palette.ink,
                fontFamily: AppTheme.pixelFont,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeedToken extends StatelessWidget {
  const _SeedToken({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Semantics(
        label: '보유 씨앗 $value개',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.night,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.eco_rounded, size: 16, color: palette.butter),
                const SizedBox(width: 4),
                ExcludeSemantics(
                  child: Text(
                    '$value',
                    style: TextStyle(
                      color: AppTheme.onNight,
                      fontFamily: AppTheme.pixelFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
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

class _HomeGreeting extends StatelessWidget {
  const _HomeGreeting({required this.nickname, required this.recordedToday});

  final String nickname;
  final bool? recordedToday;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final today = DateTime.now();
    const weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    final name = nickname.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MongrooTag(
          label: '${today.month}월 ${today.day}일 ${weekdays[today.weekday - 1]}',
          backgroundColor: palette.sky,
        ),
        const SizedBox(height: 12),
        Text(
          recordedToday == true
              ? (name.isEmpty ? '마음빛 도착!' : '$name님, 마음빛 도착!')
              : (name.isEmpty ? '오늘 마음은?' : '$name님, 오늘 마음은?'),
          maxLines: 2,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 6),
        Text(
          recordedToday == true
              ? '이야기가 식물의 다음 모습과 작은 행동으로 이어져요.'
              : '한 줄만 남겨도 지금 키우는 식물이 반응해요.',
          style: TextStyle(color: palette.inkMuted),
        ),
      ],
    );
  }
}

class _PlantCard extends StatelessWidget {
  const _PlantCard({
    required this.plant,
    required this.outfitKey,
    required this.expression,
    required this.harvesting,
    required this.onChat,
    required this.onHarvest,
  });

  final ActivePlant plant;
  final String? outfitKey;
  final PlantExpression expression;
  final bool harvesting;
  final VoidCallback onChat;
  final VoidCallback? onHarvest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = plant.nextStageExp;
    final plantLine = plant.voiceLine;
    return MongrooPanel(
      padding: EdgeInsets.zero,
      shadowOffset: const Offset(4, 4),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: _PlantStageScene(
              plant: plant,
              outfitKey: outfitKey,
              expression: expression,
              plantLine: plantLine,
              onChat: onChat,
            ),
          ),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : MongrooMotion.standard,
            child: expression == PlantExpression.acknowledged
                ? Container(
                    key: const ValueKey('plant-diary-reaction'),
                    width: double.infinity,
                    color: scheme.secondaryContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: scheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '새 일기를 맡았어요 · 식물이 마음을 읽는 중',
                            style: TextStyle(
                              color: scheme.onSecondaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('plant-diary-reaction-empty'),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Semantics(
              label: '경험치 진행도',
              value: next == null
                  ? '경험치 ${plant.exp}, 최고 단계'
                  : '경험치 ${plant.exp}, 다음 단계까지 ${next - plant.exp}',
              child: Column(
                children: [
                  Row(
                    children: [
                      MongrooTag(
                        label: plantStageName(plant.stage),
                        icon: Icons.spa_rounded,
                        backgroundColor: scheme.tertiaryContainer,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              plant.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            // 장면 안 이름표가 들고 있던 종과 성격을 여기로
                            // 옮겼다. 단계는 왼쪽 칩이 이미 말한다.
                            Text(
                              '${plant.species.name} · '
                              '${plant.stage >= 3 && plant.growthForm != null ? plant.personalityName : '관찰 중'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      next == null
                          ? '${plant.exp} XP · 만개'
                          : '${plant.exp} / $next XP',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: plant.stageProgress,
                      minHeight: 8,
                      backgroundColor: scheme.primaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 17,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          plant.nextMilestoneLabel,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          plant.stage >= 3 && plant.growthForm != null
                              ? Icons.theater_comedy_outlined
                              : Icons.manage_search_rounded,
                          size: 20,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plant.personalityName,
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                plant.growthSummary,
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                              if (plant.stage >= 3 &&
                                  plant.growthForm != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  plant.personalityDescription,
                                  style: TextStyle(
                                    color: scheme.onPrimaryContainer
                                        .withAlpha(205),
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (plant.analysisNotice case final notice?) ...[
                    const SizedBox(height: 9),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          size: 17,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            notice,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onChat,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('지금 식물과 대화하기'),
                    ),
                  ),
                  if (plant.harvestable) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onHarvest,
                        icon: harvesting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.agriculture_outlined),
                        label: Text(
                          harvesting ? '박물관으로 보내는 중' : '박물관으로 보내기',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlantStageScene extends StatelessWidget {
  const _PlantStageScene({
    required this.plant,
    required this.outfitKey,
    required this.expression,
    required this.plantLine,
    required this.onChat,
  });

  final ActivePlant plant;
  final String? outfitKey;
  final PlantExpression expression;
  final String plantLine;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: compact
          ? (textScale > 1.3 ? 380 : 330)
          : (textScale > 1.3 ? 430 : 390),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final backgroundCacheWidth = (width * dpr).round().clamp(720, 2200);
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/rooms/day-greenhouse-ink.webp',
                  fit: BoxFit.cover,
                  cacheWidth: backgroundCacheWidth,
                  errorBuilder: (_, __, ___) =>
                      ColoredBox(color: palette.paperDeep),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                    child: MongrooPressable(
                      onTap: onChat,
                      semanticLabel:
                          '${koreanWith(plant.name)} 대화하기, $plantLine',
                      child: _GuideSpeechBubble(
                        speaker: plant.name,
                        text: plantLine,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, sceneConstraints) {
                        final maxSceneHeight = sceneConstraints.maxHeight;
                        final desiredPlantWidth =
                            width < 380 ? 196.0 : (width < 520 ? 232.0 : 270.0);
                        final desiredPlantHeight = desiredPlantWidth * 1.5;
                        final plantHeight = (maxSceneHeight + 12)
                            .clamp(138.0, desiredPlantHeight)
                            .toDouble();
                        final plantWidth = (plantHeight / 1.5)
                            .clamp(92.0, desiredPlantWidth)
                            .toDouble();
                        return Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned(
                              left: (width - plantWidth) / 2,
                              bottom: 2,
                              width: plantWidth,
                              height: plantHeight,
                              child: RepaintBoundary(
                                child: AnimatedSwitcher(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                          ? Duration.zero
                                          : const Duration(milliseconds: 320),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween(begin: .96, end: 1.0)
                                          .animate(animation),
                                      alignment: Alignment.bottomCenter,
                                      child: child,
                                    ),
                                  ),
                                  child: PlantView(
                                    key: ValueKey(
                                      plant.visualKey.isEmpty
                                          ? 'stage_${plant.stage}_${plant.visualForm?.code ?? 'base'}_${plant.secondaryForm?.code ?? 'solo'}_${plant.growthVisual?.secondaryAssetKey ?? 'vector'}'
                                          : '${plant.visualKey}_${plant.growthVisual?.secondaryAssetKey ?? 'vector'}',
                                    ),
                                    stage: plant.stage,
                                    expression: expression,
                                    form: plant.visualForm,
                                    secondaryForm: plant.secondaryForm,
                                    speciesCode: plant.species.code,
                                    speciesName: plant.species.name,
                                    growthVisual: plant.growthVisual,
                                    outfitKey: outfitKey,
                                    width: plantWidth,
                                    height: plantHeight,
                                  ),
                                ),
                              ),
                            ),
                            // 이름표는 장면 안에 두지 않는다. 캐릭터는 늘 가운데
                            // 아래에 서고 이름표는 왼쪽 아래에 붙어 있어서,
                            // 390폭에서 캐릭터가 x 79~311을 쓰고 이름표가 240px를
                            // 쓰니 겹치지 않을 자리가 없었다. 화분이나 발이 통째로
                            // 가려져 캐릭터가 잘려 보였다. 이름은 바로 아래 줄이
                            // 이미 보여 주고 있어 여기 있을 이유도 없었다.
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GuideSpeechBubble extends StatelessWidget {
  const _GuideSpeechBubble({required this.speaker, required this.text});

  final String speaker;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Semantics(
      label: '$speaker의 말, $text',
      child: Transform.rotate(
        angle: -0.018,
        alignment: Alignment.topLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.paper.withAlpha(246),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.ink.withAlpha(46)),
                boxShadow: [
                  BoxShadow(
                    color: palette.ink.withAlpha(42),
                    blurRadius: 16,
                    spreadRadius: -6,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.eco_rounded, size: 13, color: palette.leaf),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '$speaker의 쪽지',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.inkMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        height: 1.35,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 18,
              top: -5,
              child: Transform.rotate(
                angle: 0.04,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.sky.withAlpha(210),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const SizedBox(width: 36, height: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlantCard extends StatelessWidget {
  const _EmptyPlantCard({required this.onPlant});

  final VoidCallback? onPlant;

  @override
  Widget build(BuildContext context) {
    return MongrooPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Icon(Icons.add_circle_outline_rounded, size: 36),
            const SizedBox(height: 10),
            const Text('화분이 비어 있어요.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPlant,
              child: const Text('새 식물 심기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MongrooPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
