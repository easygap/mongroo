import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../../expedition/presentation/expedition_battle_dock.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/adventure_models.dart';
import 'adventure_controller.dart';
import 'adventure_cue_audio.dart';

class AdventureTab extends ConsumerStatefulWidget {
  const AdventureTab({super.key});

  @override
  ConsumerState<AdventureTab> createState() => _AdventureTabState();
}

class _AdventureTabState extends ConsumerState<AdventureTab> {
  Timer? _clock;
  DateTime _now = DateTime.now();
  late final AdventureCueAudio _cues;

  @override
  void initState() {
    super.initState();
    _cues = AdventureCueAudio();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_cues.dispose());
    super.dispose();
  }

  /// 확정 순간의 소리. 사용자가 효과음을 끄면 문구와 촉각만 남는다.
  Future<void> _playCue(AdventureCue cue) => _cues.play(
        cue,
        enabled: ref.read(expeditionBattleSettingsProvider).sfxEnabled,
      );

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
                      const SizedBox(height: 12),
                      const _InteractiveExpeditionCallout(),
                      const SizedBox(height: 22),
                      _SectionTitle(
                        icon: Icons.auto_graph_rounded,
                        title: '오늘의 성장 효율',
                        description: '마음 일기가 탐험보다 가장 큰 성장과 씨앗을 줘요.',
                      ),
                      const SizedBox(height: 10),
                      _EconomyStrip(entries: data.economy),
                      if (data.weeklyBoard.goals.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          icon: Icons.calendar_view_week_outlined,
                          title: '이번 주 탐험 약속',
                          description: '일기 기록을 중심으로 천천히 채우는 주간 씨앗 목표예요.',
                        ),
                        const SizedBox(height: 10),
                        _WeeklyGoalBoard(
                          board: data.weeklyBoard,
                          busyAction: ui.busyAction,
                          onClaim: _claimWeeklyGoal,
                        ),
                      ],
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
                        icon: Icons.auto_stories_outlined,
                        title: '탐험 기록장',
                        description: '순찰과 던전에서 남긴 최근 발자국을 모아 봐요.',
                      ),
                      const SizedBox(height: 10),
                      _AdventureJournalCard(journal: data.journal),
                      if (data.storyCollection.chapters.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          icon: Icons.collections_bookmark_outlined,
                          title: '탐험 이야기 도감',
                          description: '만난 장면은 다시 읽고, 남은 이야기는 장소별로 찾아가요.',
                        ),
                        const SizedBox(height: 10),
                        _StoryCollectionCard(collection: data.storyCollection),
                      ],
                      if (data.milestones.items.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          icon: Icons.military_tech_outlined,
                          title: '쌓여 가는 탐험 발자국',
                          description: '보상 경쟁 없이 오래 이어 온 기록을 칭호로 남겨요.',
                        ),
                        const SizedBox(height: 10),
                        _MilestoneBoard(milestones: data.milestones),
                      ],
                      const SizedBox(height: 24),
                      const _SectionTitle(
                        icon: Icons.inventory_2_outlined,
                        title: '탐험 수집함',
                        description: '연구분을 남겨 두고 여분 표본만 하루 한 번 기증할 수 있어요.',
                      ),
                      const SizedBox(height: 10),
                      _Inventory(
                        items: data.inventory,
                        donation: data.donation,
                        busyAction: ui.busyAction,
                        onDonate: _donateItem,
                      ),
                      const SizedBox(height: 24),
                      const _SectionTitle(
                        icon: Icons.science_outlined,
                        title: '표본 연구대',
                        description: '재료를 정리해 수집 효율을 높여요. 성장 보상은 마음 일기가 가장 커요.',
                      ),
                      const SizedBox(height: 10),
                      _ResearchProgress(summary: data.researchSummary),
                      const SizedBox(height: 12),
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
    unawaited(_playCue(AdventureCue.patrolDepart));
    _showSuccess('순찰을 보냈어요. 돌아올 때까지 일상을 이어가도 좋아요.');
  }

  Future<void> _claimPatrol(int patrolId) async {
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .claimPatrol(patrolId);
    if (!mounted || !success) return;
    final encounter = ref.read(adventureControllerProvider).actionMessage;
    _showSuccess(encounter ?? '순찰 보상과 새 발견을 수집함에 담았어요.');
    await HapticFeedback.lightImpact();
    unawaited(_playCue(AdventureCue.patrolReturn));
  }

  Future<void> _runDungeon(AdventureDungeon dungeon) async {
    if (dungeon.approaches.isEmpty) {
      _showSuccess('탐험 방식을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
      return;
    }
    final approachCode = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _DungeonApproachSheet(dungeon: dungeon),
    );
    if (!mounted || approachCode == null) return;
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .runDungeon(dungeon.code, approachCode);
    if (!mounted || !success) return;
    final outcome = ref.read(adventureControllerProvider).actionMessage;
    _showSuccess(outcome ?? '던전 탐험을 마치고 성장 보상을 받았어요.');
    await HapticFeedback.lightImpact();
    unawaited(_playCue(AdventureCue.dungeonClear));
  }

  Future<void> _completeResearch(String projectCode) async {
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .completeResearch(projectCode);
    if (!mounted || !success) return;
    final suspended =
        ref.read(adventureControllerProvider).data.valueOrNull?.suspended ??
            false;
    if (!suspended) {
      await HapticFeedback.mediumImpact();
      unawaited(_playCue(AdventureCue.researchComplete));
    }
    _showSuccess('표본 연구를 완성했어요. 다음 탐험부터 효과가 적용돼요.');
  }

  Future<void> _claimWeeklyGoal(String goalCode) async {
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .claimWeeklyGoal(goalCode);
    if (!mounted || !success) return;
    await HapticFeedback.lightImpact();
    unawaited(_playCue(AdventureCue.patrolReturn));
    _showSuccess('주간 탐험 약속을 지켜 씨앗 보상을 받았어요.');
  }

  Future<void> _donateItem(AdventureInventoryItem item) async {
    final donation =
        ref.read(adventureControllerProvider).data.valueOrNull?.donation;
    if (donation == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} 기증'),
        content: Text(
          '${item.name} ${donation.requiredQuantity}개를 기증하고 '
          '씨앗 ${donation.rewardSeeds}개를 받아요.\n\n'
          '미완성 연구에 필요한 ${item.reservedQuantity}개는 이미 제외했어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('여분만 기증'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final success = await ref
        .read(adventureControllerProvider.notifier)
        .donateItem(item.code);
    if (!mounted || !success) return;
    await HapticFeedback.lightImpact();
    _showSuccess('여분 표본을 기증하고 씨앗 ${donation.rewardSeeds}개를 받았어요.');
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
    if (largeText) {
      return Semantics(
        container: true,
        label: '온실 밖 순찰길. 마음 일기를 쓴 뒤 캐릭터와 탐험을 떠나는 공간',
        child: MongrooPanel(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 136,
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
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              palette.night.withAlpha(72),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MongrooTag(
                        label: data.diaryReady ? '오늘 탐험 가능' : '일기 후 개방',
                        icon: data.diaryReady
                            ? Icons.check_circle_outline
                            : Icons.edit_note_outlined,
                        backgroundColor:
                            data.diaryReady ? palette.leaf : palette.paperDeep,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '온실 밖으로 한 걸음',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '기록으로 자란 캐릭터가 길과 물건을 찾아와요.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
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

class _InteractiveExpeditionCallout extends StatelessWidget {
  const _InteractiveExpeditionCallout();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MongrooPressable(
      onTap: () => context.push('/expedition'),
      semanticLabel: '직접 탐험 화면 열기',
      borderRadius: BorderRadius.circular(16),
      child: MongrooPanel(
        shadowOffset: Offset.zero,
        color: scheme.tertiaryContainer,
        borderColor: scheme.tertiary.withAlpha(90),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surface.withAlpha(210),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.explore_outlined, color: scheme.tertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '캐릭터와 직접 탐험하기',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '탐험대를 꾸리고 지도에서 길과 사건의 답을 직접 골라요.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
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

class _WeeklyGoalBoard extends StatelessWidget {
  const _WeeklyGoalBoard({
    required this.board,
    required this.busyAction,
    required this.onClaim,
  });

  final AdventureWeeklyBoard board;
  final String? busyAction;
  final ValueChanged<String> onClaim;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final range = board.weekStart == null || board.weekEnd == null
        ? '이번 주'
        : '${formatKoreanMonthDay(board.weekStart!)}–${formatKoreanMonthDay(board.weekEnd!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MongrooPanel(
          shadowOffset: Offset.zero,
          color: palette.butter.withAlpha(76),
          borderColor: palette.wood.withAlpha(64),
          child: Wrap(
            spacing: 10,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                range,
                style: TextStyle(
                  color: palette.night,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                '마음 일기 목표의 보상이 가장 커요. 주간 보상은 성장 XP 없이 씨앗만 지급해요.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final goal in board.goals)
                SizedBox(
                  width: constraints.maxWidth >= 680
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth,
                  child: _WeeklyGoalCard(
                    goal: goal,
                    busy: busyAction == 'weekly:${goal.code}',
                    anyBusy: busyAction != null,
                    onClaim: () => onClaim(goal.code),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeeklyGoalCard extends StatelessWidget {
  const _WeeklyGoalCard({
    required this.goal,
    required this.busy,
    required this.anyBusy,
    required this.onClaim,
  });

  final AdventureWeeklyGoal goal;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final icon = switch (goal.code) {
      'diary_3' => Icons.menu_book_outlined,
      'patrol_3' => Icons.route_outlined,
      'dungeon_2' => Icons.door_sliding_outlined,
      _ => Icons.flag_outlined,
    };
    final statusLabel = goal.claimed
        ? '받기 완료'
        : goal.canClaim
            ? '보상 받기'
            : goal.completed
                ? '마음 돌봄 후 받기'
                : '진행 중';
    return Semantics(
      container: true,
      label:
          '${goal.name}. ${goal.progress}/${goal.target}. 씨앗 ${goal.rewardSeeds}개. $statusLabel',
      child: MongrooPanel(
        color: goal.isDiary ? palette.leaf.withAlpha(22) : null,
        borderColor: goal.isDiary ? palette.leaf.withAlpha(100) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  goal.claimed ? Icons.task_alt_rounded : icon,
                  color: goal.claimed || goal.isDiary
                      ? palette.leaf
                      : palette.wood,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    goal.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MongrooTag(
                label: '씨앗 +${goal.rewardSeeds}',
                icon: Icons.spa_outlined,
                backgroundColor: goal.isDiary
                    ? palette.leaf.withAlpha(34)
                    : palette.paperDeep,
                foregroundColor: palette.night,
              ),
            ),
            const SizedBox(height: 8),
            Text(goal.description, style: TextStyle(color: palette.inkMuted)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    goal.completed ? '이번 주 목표 달성' : '이번 주 진행도',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${goal.progress}/${goal.target}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: goal.progressRatio,
                minHeight: 8,
                color: goal.isDiary ? palette.leaf : palette.wood,
                backgroundColor: palette.paperDeep,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: goal.canClaim && !anyBusy ? onClaim : null,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(goal.claimed
                      ? Icons.check_rounded
                      : Icons.redeem_outlined),
              label: Text(statusLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneBoard extends StatelessWidget {
  const _MilestoneBoard({required this.milestones});

  final AdventureMilestones milestones;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MongrooPanel(
          shadowOffset: Offset.zero,
          color: palette.leaf.withAlpha(20),
          borderColor: palette.leaf.withAlpha(90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '현재 칭호',
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                milestones.currentTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: palette.leaf,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '칭호 ${milestones.unlockedCount}/${milestones.totalCount} · 씨앗과 XP는 따로 지급하지 않아요.',
                style: TextStyle(color: palette.inkMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final milestone in milestones.items)
                SizedBox(
                  width: constraints.maxWidth >= 680
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth,
                  child: _MilestoneCard(milestone: milestone),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({required this.milestone});

  final AdventureMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final icon = switch (milestone.code) {
      'seven_day_diary' => Icons.auto_stories_outlined,
      'five_patrol_returns' => Icons.signpost_outlined,
      'five_dungeon_runs' => Icons.door_sliding_outlined,
      'three_research_projects' => Icons.biotech_outlined,
      'outside_greenhouse_atlas' => Icons.map_outlined,
      _ => Icons.explore_outlined,
    };
    final status = milestone.unlocked ? '칭호 획득' : '기록 중';
    return Semantics(
      container: true,
      label:
          '${milestone.name}. ${milestone.progress}/${milestone.target}. $status. ${milestone.title}',
      child: MongrooPanel(
        shadowOffset: Offset.zero,
        color: milestone.unlocked ? palette.butter.withAlpha(58) : null,
        borderColor: milestone.unlocked ? palette.wood.withAlpha(90) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  milestone.unlocked ? Icons.workspace_premium_outlined : icon,
                  color: milestone.unlocked ? palette.wood : palette.inkMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    milestone.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              milestone.description,
              style: TextStyle(color: palette.inkMuted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    milestone.unlocked ? '달성 완료' : '달성 진행도',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${milestone.progress}/${milestone.target}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: milestone.progressRatio,
                minHeight: 8,
                color: milestone.unlocked ? palette.wood : palette.leaf,
                backgroundColor: palette.paperDeep,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  milestone.unlocked
                      ? Icons.check_circle_outline_rounded
                      : Icons.lock_outline_rounded,
                  size: 17,
                  color: milestone.unlocked ? palette.leaf : palette.inkMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    milestone.unlocked
                        ? '칭호 · ${milestone.title}'
                        : '달성 칭호 · ${milestone.title}',
                    style: TextStyle(
                      color:
                          milestone.unlocked ? palette.night : palette.inkMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
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
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Semantics(
      container: true,
      label: route.available
          ? '${route.name}. 수집 예상 ${route.projectedQuantity}개. ${route.bestMatch ? '오늘 잘 맞는 길.' : ''}'
          : '${route.name}. ${route.requiredStage}단계에 개방.',
      child: MongrooPanel(
        borderColor: route.available && route.bestMatch
            ? palette.leaf.withAlpha(125)
            : null,
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
            if (route.available) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  if (route.bestMatch)
                    MongrooTag(
                      label: '오늘 잘 맞는 길',
                      icon: Icons.recommend_outlined,
                      backgroundColor: palette.leaf.withAlpha(38),
                      foregroundColor: palette.night,
                    ),
                  MongrooTag(
                    label: '수집 예상 ×${route.projectedQuantity}',
                    icon: Icons.inventory_2_outlined,
                    backgroundColor: route.projectedQuantity >= 2
                        ? palette.butter.withAlpha(90)
                        : palette.paperDeep,
                    foregroundColor: palette.night,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 7),
            Text(route.description,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text(
                '추천 ${route.recommendedStats.join(' · ')} · 씨앗 ${route.reward.seeds}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (route.timeReductionMinutes > 0) ...[
              const SizedBox(height: 5),
              Text(
                '표본 연구로 기본 ${route.baseDurationMinutes}분보다 ${route.timeReductionMinutes}분 빨라졌어요.',
                style: TextStyle(
                  color: MongrooPalette.of(context).leaf,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
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
      ),
    );
  }
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
  final ValueChanged<AdventureDungeon> onRun;

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
                  busy: busyAction?.startsWith('dungeon:${dungeon.code}:') ==
                      true,
                  anyBusy: busyAction != null,
                  onRun: () => onRun(dungeon),
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
                      fit: BoxFit.cover, semanticLabel: '${dungeon.name} 탐험 장소')
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
                              ? '탐험 방식 고르기'
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

class _DungeonApproachSheet extends StatelessWidget {
  const _DungeonApproachSheet({required this.dungeon});

  final AdventureDungeon dungeon;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          20 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '${dungeon.name}, 어떻게 살펴볼까요?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 7),
                Text(
                  '캐릭터의 감정 성장과 잘 맞는 방식을 고르면 수집품을 더 꼼꼼히 찾을 수 있어요. XP와 씨앗 보상은 어떤 방식이든 같아요.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (final approach in dungeon.approaches) ...[
                  MongrooPressable(
                    onTap: () => Navigator.of(context).pop(approach.code),
                    semanticLabel:
                        '${approach.name}. ${approach.statLabel} ${approach.statValue}. ${approach.resonant ? '성장 공명 예상.' : ''} 수집 예상 ${approach.projectedQuantity}개',
                    child: MongrooPanel(
                      shadowOffset: Offset.zero,
                      borderColor: approach.resonant
                          ? palette.leaf.withAlpha(125)
                          : null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: (approach.resonant
                                      ? palette.leaf
                                      : palette.paperDeep)
                                  .withAlpha(approach.resonant ? 38 : 255),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _approachIcon(approach.statCode),
                              color: palette.night,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  approach.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  approach.description,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: [
                                    MongrooTag(
                                      label:
                                          '${approach.statLabel} ${approach.statValue}',
                                      icon: _approachIcon(approach.statCode),
                                    ),
                                    if (approach.recommended)
                                      const MongrooTag(
                                        label: '장소 추천',
                                        icon: Icons.route_outlined,
                                      ),
                                    MongrooTag(
                                      label: approach.resonant
                                          ? '성장 공명 · 수집 ×${approach.projectedQuantity}'
                                          : '수집 예상 ×${approach.projectedQuantity}',
                                      icon: approach.resonant
                                          ? Icons.auto_awesome_rounded
                                          : Icons.inventory_2_outlined,
                                      backgroundColor: approach.resonant
                                          ? palette.leaf.withAlpha(38)
                                          : palette.paperDeep,
                                      foregroundColor: palette.night,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                  if (approach != dungeon.approaches.last)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdventureJournalCard extends StatelessWidget {
  const _AdventureJournalCard({required this.journal});

  final AdventureJournal journal;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MongrooTag(
                label:
                    '장소 발견 ${journal.discoveredCount}/${journal.totalDungeons}',
                icon: Icons.map_outlined,
                backgroundColor: palette.leaf.withAlpha(34),
                foregroundColor: palette.night,
              ),
              MongrooTag(
                label: '던전 탐험 ${journal.totalClearCount}회',
                icon: Icons.door_sliding_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (journal.recentEntries.isEmpty)
            Row(
              children: [
                Icon(Icons.history_rounded, color: palette.inkMuted),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('아직 남겨진 발자국이 없어요. 첫 순찰을 다녀오면 기록돼요.'),
                ),
              ],
            )
          else
            for (final entry in journal.recentEntries) ...[
              _JournalEntryRow(entry: entry),
              if (entry != journal.recentEntries.last)
                Divider(height: 22, color: palette.ink.withAlpha(24)),
            ],
        ],
      ),
    );
  }
}

class _JournalEntryRow extends StatelessWidget {
  const _JournalEntryRow({required this.entry});

  final AdventureJournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final timeLabel = _journalTimeLabel(entry.occurredAt, DateTime.now());
    return Semantics(
      container: true,
      label: '${entry.title}. $timeLabel. ${entry.description}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: entry.isDungeon
                  ? palette.sky.withAlpha(90)
                  : palette.leaf.withAlpha(38),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              entry.isDungeon
                  ? Icons.door_sliding_outlined
                  : Icons.route_outlined,
              color: palette.night,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  timeLabel,
                  style: TextStyle(fontSize: 12, color: palette.inkMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.description,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.resonant) ...[
                  const SizedBox(height: 7),
                  MongrooTag(
                    label: '성장 공명',
                    icon: Icons.auto_awesome_rounded,
                    backgroundColor: palette.leaf.withAlpha(38),
                    foregroundColor: palette.night,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryCollectionCard extends StatelessWidget {
  const _StoryCollectionCard({required this.collection});

  final AdventureStoryCollection collection;

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
              MongrooTag(
                label:
                    '이야기 ${collection.collectedCount}/${collection.totalCount}',
                icon: collection.completed
                    ? Icons.auto_awesome_rounded
                    : Icons.menu_book_outlined,
                backgroundColor: palette.leaf.withAlpha(34),
                foregroundColor: palette.night,
              ),
              Text(
                collection.completed
                    ? '모든 장면을 다시 읽을 수 있어요.'
                    : '보상 없이 천천히 채우는 기록이에요.',
                style: TextStyle(color: palette.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label:
                '탐험 이야기 ${collection.collectedCount}/${collection.totalCount} 수집',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: collection.progress,
                minHeight: 8,
                backgroundColor: palette.ink.withAlpha(18),
                color: palette.leaf,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final chapter in collection.chapters)
            _StoryChapterTile(chapter: chapter),
        ],
      ),
    );
  }
}

class _StoryChapterTile extends StatelessWidget {
  const _StoryChapterTile({required this.chapter});

  final AdventureStoryChapter chapter;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('story-chapter-${chapter.code}'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Icon(
            chapter.code == 'dungeon_memories'
                ? Icons.door_sliding_outlined
                : Icons.route_outlined,
            color: palette.night,
          ),
          title: Text(
            chapter.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${chapter.collectedCount}/${chapter.totalCount} · ${chapter.description}',
            style: TextStyle(color: palette.inkMuted),
          ),
          children: [
            for (var index = 0; index < chapter.items.length; index++) ...[
              _StoryCollectionRow(item: chapter.items[index]),
              if (index < chapter.items.length - 1)
                Divider(height: 1, color: palette.ink.withAlpha(20)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoryCollectionRow extends StatelessWidget {
  const _StoryCollectionRow({required this.item});

  final AdventureStoryItem item;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final title = item.discovered
        ? (item.title ?? '이름 없는 장면')
        : '${item.locationName}의 미발견 장면';
    final description = item.discovered
        ? [
            item.locationName,
            if ((item.text ?? '').isNotEmpty) item.text!,
            if ((item.detail ?? '').isNotEmpty) item.detail!,
          ].join('\n')
        : '${item.locationName}에서 아직 만나지 못했어요.';
    return Semantics(
      container: true,
      label: item.discovered ? '$title. $description' : '$title. 아직 잠김',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: item.discovered
                    ? palette.leaf.withAlpha(34)
                    : palette.ink.withAlpha(12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                item.discovered
                    ? item.isDungeon
                        ? Icons.auto_stories_outlined
                        : Icons.bookmark_added_outlined
                    : Icons.lock_outline_rounded,
                size: 20,
                color: item.discovered ? palette.night : palette.inkMuted,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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

class _Inventory extends StatelessWidget {
  const _Inventory({
    required this.items,
    required this.donation,
    required this.busyAction,
    required this.onDonate,
  });

  final List<AdventureInventoryItem> items;
  final AdventureDonationStatus donation;
  final String? busyAction;
  final ValueChanged<AdventureInventoryItem> onDonate;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MongrooPanel(
          shadowOffset: Offset.zero,
          color: donation.hasEligibleItem && donation.availableToday
              ? palette.butter.withAlpha(68)
              : palette.paper,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                donation.usedToday
                    ? Icons.volunteer_activism_rounded
                    : Icons.recycling_outlined,
                color: donation.hasEligibleItem && donation.availableToday
                    ? palette.wood
                    : palette.inkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '온실 표본 기증 · ${donation.requiredQuantity}개 → 씨앗 ${donation.rewardSeeds}개',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      donation.message,
                      style: TextStyle(color: palette.inkMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          MongrooPanel(
            shadowOffset: Offset.zero,
            child: Row(
              children: [
                Icon(Icons.inbox_outlined, color: palette.inkMuted),
                const SizedBox(width: 10),
                const Expanded(child: Text('아직 수집품이 없어요. 첫 순찰을 보내 보세요.')),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in items)
                  SizedBox(
                    width: constraints.maxWidth >= 680
                        ? (constraints.maxWidth - 10) / 2
                        : constraints.maxWidth,
                    child: _InventoryItemCard(
                      item: item,
                      donation: donation,
                      busy: busyAction == 'donation:${item.code}',
                      anyBusy: busyAction != null,
                      onDonate: () => onDonate(item),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InventoryItemCard extends StatelessWidget {
  const _InventoryItemCard({
    required this.item,
    required this.donation,
    required this.busy,
    required this.anyBusy,
    required this.onDonate,
  });

  final AdventureInventoryItem item;
  final AdventureDonationStatus donation;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onDonate;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final buttonLabel = donation.usedToday
        ? '오늘 기증 완료'
        : !donation.availableToday
            ? '오늘 기증 불가'
            : item.canDonate
                ? '여분 표본 ${donation.requiredQuantity}개 기증'
                : item.reservedQuantity > 0
                    ? '연구 재료 보관 중'
                    : '여분 ${donation.requiredQuantity}개 필요';
    return Semantics(
      container: true,
      label:
          '${item.name} ${item.quantity}개. 연구 보관 ${item.reservedQuantity}개. 기증 가능 ${item.donatableQuantity}개.',
      child: MongrooPanel(
        shadowOffset: Offset.zero,
        borderColor: item.canDonate ? palette.wood.withAlpha(90) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_itemIcon(item.code), color: palette.leaf),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '×${item.quantity}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(item.description, style: TextStyle(color: palette.inkMuted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (item.reservedQuantity > 0)
                  MongrooTag(
                    label: '연구 보관 ${item.reservedQuantity}',
                    icon: Icons.science_outlined,
                    backgroundColor: palette.paperDeep,
                    foregroundColor: palette.night,
                  ),
                MongrooTag(
                  label: '기증 가능 ${item.donatableQuantity}',
                  icon: Icons.recycling_outlined,
                  backgroundColor: item.canDonate
                      ? palette.butter.withAlpha(100)
                      : palette.paperDeep,
                  foregroundColor: palette.night,
                ),
              ],
            ),
            const SizedBox(height: 11),
            FilledButton.tonal(
              onPressed: item.canDonate && !anyBusy ? onDonate : null,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonLabel, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResearchProgress extends StatelessWidget {
  const _ResearchProgress({required this.summary});

  final AdventureResearchSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final title = summary.chapterCompleted
        ? '${summary.chapterName} 완성'
        : summary.chapterName;
    final description = summary.chapterCompleted
        ? '마음나무 관측실까지의 기록을 한 장으로 묶었어요. 남은 선택 연구도 이어갈 수 있어요.'
        : '마지막 관측 기록을 모아 첫 탐험 장을 완성해 보세요.';
    return Semantics(
      container: true,
      label: '$title. $description',
      child: MongrooPanel(
        shadowOffset: Offset.zero,
        color: summary.chapterCompleted
            ? palette.leaf.withAlpha(24)
            : palette.paper,
        borderColor:
            summary.chapterCompleted ? palette.leaf.withAlpha(105) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  summary.chapterCompleted
                      ? Icons.task_alt_rounded
                      : Icons.menu_book_outlined,
                  color: summary.chapterCompleted ? palette.leaf : palette.wood,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                MongrooTag(
                  label: '연구 ${summary.completedCount}/${summary.totalCount}',
                  icon: Icons.science_outlined,
                  backgroundColor: summary.chapterCompleted
                      ? palette.leaf.withAlpha(34)
                      : palette.paperDeep,
                  foregroundColor: palette.night,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(color: palette.inkMuted),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: summary.progress,
                minHeight: 8,
                color: palette.leaf,
                backgroundColor: palette.paperDeep,
              ),
            ),
          ],
        ),
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

String _journalTimeLabel(DateTime? occurredAt, DateTime now) {
  if (occurredAt == null) return '시간 기록 없음';
  final local = occurredAt.toLocal();
  final localDay = dateOnly(local);
  final today = dateOnly(now);
  final dayLabel = localDay == today
      ? '오늘'
      : localDay == today.subtract(const Duration(days: 1))
          ? '어제'
          : formatKoreanMonthDay(local);
  return '$dayLabel ${formatLocalTime(occurredAt)}';
}

IconData _itemIcon(String code) => switch (code) {
      'pressed_leaf_map' => Icons.map_outlined,
      'moon_dew' => Icons.water_drop_outlined,
      'moss_key' => Icons.key_outlined,
      'echo_seed' => Icons.spa_outlined,
      'glass_leaf_vein' => Icons.filter_vintage_outlined,
      'starlight_pollen' => Icons.grain_outlined,
      'dawn_bark_rubbing' => Icons.texture_outlined,
      'heartwood_seed_sample' => Icons.nature_outlined,
      _ => Icons.eco_outlined,
    };

IconData _approachIcon(String statCode) => switch (statCode) {
      'care' => Icons.volunteer_activism_outlined,
      'focus' => Icons.center_focus_strong_outlined,
      'courage' => Icons.shield_outlined,
      'insight' => Icons.visibility_outlined,
      _ => Icons.explore_outlined,
    };
