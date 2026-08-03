import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/adventure_models.dart';
import 'adventure_controller.dart';

class AdventureTab extends ConsumerStatefulWidget {
  const AdventureTab({super.key});

  @override
  ConsumerState<AdventureTab> createState() => _AdventureTabState();
}

class _AdventureTabState extends ConsumerState<AdventureTab> {
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      adventureControllerProvider.select((state) => state.actionError),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        ref.read(adventureControllerProvider.notifier).clearActionError();
      },
    );
    final ui = ref.watch(adventureControllerProvider);
    return ui.data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _LoadError(
        onRetry: ref.read(adventureControllerProvider.notifier).load,
      ),
      data: (data) => RefreshIndicator(
        onRefresh: ref.read(adventureControllerProvider.notifier).load,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            key: const PageStorageKey('adventure-tab-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth >= 760 ? 24 : 14,
              18,
              constraints.maxWidth >= 760 ? 24 : 14,
              48,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AdventureHero(data: data),
                      const SizedBox(height: 14),
                      _DiaryGate(data: data),
                      const SizedBox(height: 22),
                      _SectionTitle(
                        icon: Icons.auto_graph_rounded,
                        title: '오늘의 성장 효율',
                        description: '마음 일기가 탐험보다 가장 큰 성장과 씨앗을 줘요.',
                      ),
                      const SizedBox(height: 10),
                      _EconomyStrip(entries: data.economy),
                      if (data.character != null) ...[
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          icon: Icons.badge_outlined,
                          title: '캐릭터 스테이터스',
                          description: '감정은 능력의 방향만 바꾸고 총합은 같아요.',
                        ),
                        const SizedBox(height: 10),
                        _CharacterStats(character: data.character!),
                      ],
                      const SizedBox(height: 24),
                      const _SectionTitle(
                        icon: Icons.route_outlined,
                        title: '오늘의 순찰',
                        description: '하루 한 번 길을 살펴보고 새 장소와 재료를 발견해요.',
                      ),
                      const SizedBox(height: 10),
                      _PatrolSection(
                        data: data,
                        now: _now,
                        busyAction: ui.busyAction,
                        onStart: _startPatrol,
                        onClaim: _claimPatrol,
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle(
                        icon: Icons.door_sliding_outlined,
                        title: '발견한 던전',
                        description: '순찰에서 찾은 장소는 하루 한 번 차분히 탐험할 수 있어요.',
                      ),
                      const SizedBox(height: 10),
                      _DungeonGrid(
                        dungeons: data.dungeons,
                        enabled: data.diaryReady && !data.suspended,
                        busyAction: ui.busyAction,
                        onRun: _runDungeon,
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle(
                        icon: Icons.inventory_2_outlined,
                        title: '탐험 수집함',
                        description: '발견한 재료를 모아 표본 연구를 완성할 수 있어요.',
                      ),
                      const SizedBox(height: 10),
                      _Inventory(items: data.inventory),
                      const SizedBox(height: 24),
                      const _SectionTitle(
                        icon: Icons.science_outlined,
                        title: '표본 연구대',
                        description: '재료를 정리해 수집 효율을 높여요. 성장 보상은 마음 일기가 가장 커요.',
                      ),
                      const SizedBox(height: 10),
                      _ResearchGrid(
                        projects: data.researchProjects,
                        busyAction: ui.busyAction,
                        onComplete: _completeResearch,
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

  Future<void> _startPatrol(String routeCode) async {
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .startPatrol(routeCode);
    if (!mounted || !success) return;
    await HapticFeedback.selectionClick();
    _showSuccess('순찰을 보냈어요. 돌아올 때까지 일상을 이어가도 좋아요.');
  }

  Future<void> _claimPatrol(int patrolId) async {
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .claimPatrol(patrolId);
    if (!mounted || !success) return;
    await HapticFeedback.lightImpact();
    _showSuccess('순찰 보상과 새 발견을 수집함에 담았어요.');
  }

  Future<void> _runDungeon(String dungeonCode) async {
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .runDungeon(dungeonCode);
    if (!mounted || !success) return;
    await HapticFeedback.lightImpact();
    _showSuccess('던전 탐험을 마치고 성장 보상을 받았어요.');
  }

  Future<void> _completeResearch(String projectCode) async {
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .completeResearch(projectCode);
    if (!mounted || !success) return;
    final suspended =
        ref.read(adventureControllerProvider).data.valueOrNull?.suspended ??
            false;
    if (!suspended) await HapticFeedback.mediumImpact();
    _showSuccess('표본 연구를 완성했어요. 다음 탐험부터 효과가 적용돼요.');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AdventureHero extends StatelessWidget {
  const _AdventureHero({required this.data});

  final AdventureState data;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final character = data.character;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compact = MediaQuery.sizeOf(context).width < 520;
    final largeText = textScale > 1.35;
    return Semantics(
      container: true,
      label: '온실 밖 순찰길. 마음 일기를 쓴 뒤 캐릭터와 탐험을 떠나는 공간',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: (226 + ((textScale - 1).clamp(0, 1) * 84)).toDouble(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/adventure/patrol-garden-path.webp',
                fit: BoxFit.cover,
                semanticLabel: '새벽빛이 비치는 온실 바깥의 조용한 정원 순찰길',
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.night.withAlpha(210),
                      palette.night.withAlpha(104),
                      Colors.transparent,
                    ],
                    stops: const [0, .58, 1],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                top: 22,
                bottom: 20,
                width: compact && !largeText ? 184 : 230,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MongrooTag(
                      label: data.diaryReady ? '오늘 탐험 가능' : '일기 후 개방',
                      icon: data.diaryReady
                          ? Icons.check_circle_outline
                          : Icons.edit_note_outlined,
                      backgroundColor:
                          data.diaryReady ? palette.leaf : palette.paper,
                    ),
                    const Spacer(),
                    Text(
                      '온실 밖으로\n한 걸음',
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: AppTheme.onNight,
                                fontFamily: AppTheme.pixelFont,
                                height: 1.15,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '기록으로 자란 캐릭터가 길과 물건을 찾아와요.',
                      style: TextStyle(
                        color: AppTheme.onNightMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (character != null && !largeText)
                Positioned(
                  right: 8,
                  bottom: -4,
                  width: compact ? 118 : 142,
                  height: compact ? 172 : 190,
                  child: PlantView(
                    stage: character.stage,
                    form: character.form,
                    speciesCode: character.speciesCode,
                    speciesName: character.speciesName,
                    outfitKey: character.outfit?.layerKey,
                    width: compact ? 118 : 142,
                    height: compact ? 172 : 190,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiaryGate extends StatelessWidget {
  const _DiaryGate({required this.data});

  final AdventureState data;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final ready = data.diaryReady && !data.suspended;
    return MongrooPanel(
      color: ready ? palette.paper : palette.blush,
      shadowOffset: Offset.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.35;
          final message = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                data.suspended
                    ? Icons.favorite_border_rounded
                    : ready
                        ? Icons.menu_book_rounded
                        : Icons.edit_note_rounded,
                color: ready ? palette.leaf : palette.coral,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.suspended
                          ? '오늘은 탐험보다 마음 돌봄을 먼저 해요'
                          : ready
                              ? '오늘의 마음 일기로 탐험이 열렸어요'
                              : data.diaryMessage,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ready
                          ? '일기 보상 40 XP · 씨앗 15개가 오늘 활동 중 가장 커요.'
                          : '감정의 종류와 관계없이 같은 성장 보상을 받아요.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (ready || data.suspended) return message;
          final button = FilledButton.tonalIcon(
            onPressed: () => context.push('/record'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('일기 쓰기'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [message, const SizedBox(height: 12), button],
            );
          }
          return Row(
            children: [
              Expanded(child: message),
              const SizedBox(width: 10),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: MongrooPalette.of(context).leaf),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _EconomyStrip extends StatelessWidget {
  const _EconomyStrip({required this.entries});
  final List<AdventureEconomyEntry> entries;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 680
              ? (constraints.maxWidth - 30) / 4
              : (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in entries)
                SizedBox(
                  width: width,
                  child: MongrooPanel(
                    padding: const EdgeInsets.all(12),
                    color: entry.code == 'diary'
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    shadowOffset: Offset.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 7),
                        Text('${entry.exp} XP · 씨앗 ${entry.seeds}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class _CharacterStats extends StatelessWidget {
  const _CharacterStats({required this.character});
  final AdventureCharacter character;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${character.name} · ${character.stage}단계',
                  style: Theme.of(context).textTheme.titleMedium),
              if (character.outfit?.bonusLabel != null)
                MongrooTag(
                  label: character.outfit!.bonusLabel!,
                  icon: Icons.checkroom_outlined,
                  backgroundColor: palette.butter,
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (final stat in character.stats) ...[
            Semantics(
              label: '${stat.label} 능력치 ${stat.value}',
              child: Row(
                children: [
                  SizedBox(
                      width: 42,
                      child: Text(stat.label,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (stat.value / 12).clamp(0, 1).toDouble(),
                        minHeight: 8,
                        color: palette.leaf,
                        backgroundColor: palette.paperDeep,
                      ),
                    ),
                  ),
                  SizedBox(
                      width: 32,
                      child: Text('${stat.value}', textAlign: TextAlign.end)),
                ],
              ),
            ),
            if (stat != character.stats.last) const SizedBox(height: 10),
          ],
          if (character.outfit == null) ...[
            const SizedBox(height: 14),
            Text('의상을 장착하면 특정 탐험의 수집 성능이 올라가요.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _PatrolSection extends StatelessWidget {
  const _PatrolSection({
    required this.data,
    required this.now,
    required this.busyAction,
    required this.onStart,
    required this.onClaim,
  });

  final AdventureState data;
  final DateTime now;
  final String? busyAction;
  final ValueChanged<String> onStart;
  final ValueChanged<int> onClaim;

  @override
  Widget build(BuildContext context) {
    final patrol = data.patrol;
    if (patrol != null) {
      final ready = patrol.readyToClaim ||
          (patrol.returnsAt != null && !patrol.returnsAt!.isAfter(now));
      final remaining = patrol.returnsAt?.difference(now) ?? Duration.zero;
      return MongrooPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  patrol.claimed
                      ? Icons.task_alt_rounded
                      : ready
                          ? Icons.notifications_active_outlined
                          : Icons.directions_walk_rounded,
                  size: 32,
                  color: MongrooPalette.of(context).leaf,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patrol.routeName,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        patrol.claimed
                            ? '오늘 순찰을 마쳤어요.'
                            : ready
                                ? '순찰에서 돌아왔어요. 발견물을 확인해 보세요.'
                                : '돌아오기까지 ${_durationLabel(remaining)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (ready && !patrol.claimed) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busyAction == null ? () => onClaim(patrol.id) : null,
                child: busyAction == 'claim:${patrol.id}'
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('돌아온 순찰 확인'),
              ),
            ],
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final route in data.routes)
            SizedBox(
              width: constraints.maxWidth >= 680
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth,
              child: _RouteCard(
                route: route,
                enabled: data.diaryReady && !data.suspended,
                busy: busyAction == 'patrol:${route.code}',
                anyBusy: busyAction != null,
                onStart: () => onStart(route.code),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.enabled,
    required this.busy,
    required this.anyBusy,
    required this.onStart,
  });
  final PatrolRoute route;
  final bool enabled;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => MongrooPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(route.name,
                        style: Theme.of(context).textTheme.titleMedium)),
                MongrooTag(
                    label: '${route.durationMinutes}분',
                    icon: Icons.schedule_outlined),
              ],
            ),
            const SizedBox(height: 7),
            Text(route.description,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text(
                '추천 ${route.recommendedStats.join(' · ')} · 씨앗 ${route.reward.seeds}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed:
                  enabled && route.available && !anyBusy ? onStart : null,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(route.available
                      ? '순찰 보내기'
                      : '${route.requiredStage}단계에 개방'),
            ),
          ],
        ),
      );
}

class _DungeonGrid extends StatelessWidget {
  const _DungeonGrid({
    required this.dungeons,
    required this.enabled,
    required this.busyAction,
    required this.onRun,
  });
  final List<AdventureDungeon> dungeons;
  final bool enabled;
  final String? busyAction;
  final ValueChanged<String> onRun;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final dungeon in dungeons)
              SizedBox(
                width: constraints.maxWidth >= 680
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                child: _DungeonCard(
                  dungeon: dungeon,
                  enabled: enabled,
                  busy: busyAction == 'dungeon:${dungeon.code}',
                  anyBusy: busyAction != null,
                  onRun: () => onRun(dungeon.code),
                ),
              ),
          ],
        ),
      );
}

class _DungeonCard extends StatelessWidget {
  const _DungeonCard({
    required this.dungeon,
    required this.enabled,
    required this.busy,
    required this.anyBusy,
    required this.onRun,
  });
  final AdventureDungeon dungeon;
  final bool enabled;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: SizedBox(
              height: 126,
              child: dungeon.discovered
                  ? Image.asset(dungeon.assetPath,
                      fit: BoxFit.cover,
                      semanticLabel: '${dungeon.name}의 식물 표본 보관실')
                  : ColoredBox(
                      color: palette.night,
                      child: Center(
                          child: Icon(Icons.lock_outline,
                              color: AppTheme.onNightMuted, size: 34)),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(dungeon.discovered ? dungeon.name : '아직 발견하지 못한 장소',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(
                  dungeon.discovered
                      ? dungeon.description
                      : '순찰을 보내면 새로운 장소의 단서를 찾을 수 있어요.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Text(
                  dungeon.discovered
                      ? '추천 ${dungeon.recommendedStats.join(' · ')} · ${dungeon.reward.exp} XP · 씨앗 ${dungeon.reward.seeds}'
                      : '필요 단계 ${dungeon.requiredStage}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed:
                      enabled && dungeon.available && !anyBusy ? onRun : null,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(dungeon.discovered
                          ? dungeon.available
                              ? '던전 탐험하기'
                              : '오늘 탐험 완료'
                          : '순찰에서 발견하기'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Inventory extends StatelessWidget {
  const _Inventory({required this.items});
  final List<AdventureInventoryItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return MongrooPanel(
        shadowOffset: Offset.zero,
        child: Row(
          children: [
            Icon(Icons.inbox_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            const Expanded(child: Text('아직 수집품이 없어요. 첫 순찰을 보내 보세요.')),
          ],
        ),
      );
    }
    return MongrooPanel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items)
            Semantics(
              label: '${item.name} ${item.quantity}개. ${item.description}',
              child: MongrooTag(
                label: '${item.name} ×${item.quantity}',
                icon: _itemIcon(item.code),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResearchGrid extends StatelessWidget {
  const _ResearchGrid({
    required this.projects,
    required this.busyAction,
    required this.onComplete,
  });

  final List<AdventureResearchProject> projects;
  final String? busyAction;
  final ValueChanged<String> onComplete;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return const MongrooPanel(
        shadowOffset: Offset.zero,
        child: Text('준비 중인 표본 연구가 없어요.'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final project in projects)
            SizedBox(
              width: constraints.maxWidth >= 680
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth,
              child: _ResearchCard(
                project: project,
                busy: busyAction == 'research:${project.code}',
                anyBusy: busyAction != null,
                onComplete: () => onComplete(project.code),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResearchCard extends StatelessWidget {
  const _ResearchCard({
    required this.project,
    required this.busy,
    required this.anyBusy,
    required this.onComplete,
  });

  final AdventureResearchProject project;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final status = project.completed
        ? '완료'
        : project.canComplete
            ? '완성 가능'
            : '재료 수집 중';
    return Semantics(
      container: true,
      label: '${project.name}. $status. 효과 ${project.effectLabel}',
      child: MongrooPanel(
        borderColor: project.completed ? palette.leaf.withAlpha(110) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  project.completed
                      ? Icons.task_alt_rounded
                      : Icons.biotech_outlined,
                  color: project.completed ? palette.leaf : palette.wood,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    project.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                MongrooTag(
                  label: status,
                  backgroundColor: project.completed || project.canComplete
                      ? palette.leaf.withAlpha(34)
                      : palette.paperDeep,
                  foregroundColor: palette.night,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              project.description,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final requirement in project.requirements)
                  MongrooTag(
                    label: project.completed
                        ? '${requirement.name} 사용 완료'
                        : '${requirement.name} ${requirement.current}/${requirement.required}',
                    icon: requirement.fulfilled || project.completed
                        ? Icons.check_rounded
                        : _itemIcon(requirement.code),
                    backgroundColor: requirement.fulfilled || project.completed
                        ? palette.leaf.withAlpha(34)
                        : palette.paperDeep,
                    foregroundColor: palette.night,
                  ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              project.effectLabel,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: !project.completed && project.canComplete && !anyBusy
                  ? onComplete
                  : null,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(project.completed
                      ? Icons.check_rounded
                      : Icons.auto_awesome_outlined),
              label: Text(project.completed
                  ? '연구 완료'
                  : project.canComplete
                      ? '재료 정리해 완성'
                      : '재료가 더 필요해요'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 36),
              const SizedBox(height: 12),
              const Text('탐험 정보를 불러오지 못했어요.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 불러오기'),
              ),
            ],
          ),
        ),
      );
}

String _durationLabel(Duration duration) {
  if (duration.isNegative) return '곧 도착';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

IconData _itemIcon(String code) => switch (code) {
      'pressed_leaf_map' => Icons.map_outlined,
      'moon_dew' => Icons.water_drop_outlined,
      'moss_key' => Icons.key_outlined,
      'echo_seed' => Icons.spa_outlined,
      _ => Icons.eco_outlined,
    };
