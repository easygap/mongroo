import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mongroo_ui.dart';
import '../domain/expedition_models.dart';
import 'expedition_controller.dart';
import 'moss_archive_scene.dart';

class ExpeditionScreen extends ConsumerWidget {
  const ExpeditionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(
      expeditionControllerProvider.select((state) => state.error),
      (previous, next) {
        if (next == null || next == previous) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        ref.read(expeditionControllerProvider.notifier).clearError();
      },
    );
    final state = ref.watch(expeditionControllerProvider);
    final expedition = state.expedition;
    final title = expedition?.region.name ?? '함께 떠나는 탐험';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (expedition?.run.mode == 'tutorial' &&
              expedition?.run.isActive == true)
            IconButton(
              onPressed: ref
                  .read(expeditionControllerProvider.notifier)
                  .replayTutorialHelp,
              tooltip: '현재 조작 도움말 다시 보기',
              icon: const Icon(Icons.help_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : expedition != null
                ? expedition.run.isActive
                    ? _ActiveExpedition(state: state, expedition: expedition)
                    : _ExpeditionSummary(expedition: expedition)
                : _ExpeditionPreparation(state: state),
      ),
    );
  }
}

class _ExpeditionPreparation extends ConsumerWidget {
  const _ExpeditionPreparation({required this.state});

  final ExpeditionUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = state.catalog;
    if (catalog == null) {
      return _CenteredMessage(
        icon: Icons.cloud_off_outlined,
        title: '탐험 준비를 불러오지 못했어요',
        description: state.error ?? '연결을 확인하고 다시 시도해 주세요.',
        actionLabel: '다시 불러오기',
        onAction: ref.read(expeditionControllerProvider.notifier).load,
      );
    }
    if (catalog.suspended) {
      return const _CenteredMessage(
        icon: Icons.health_and_safety_outlined,
        title: '오늘은 안전 지원을 먼저 살펴봐요',
        description: '마음이 급한 날에는 탐험을 쉬어도 성장 기록은 사라지지 않아요.',
      );
    }
    final region = catalog.regions.firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: ref.read(expeditionControllerProvider.notifier).load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth >= 720 ? 32 : 16,
            16,
            constraints.maxWidth >= 720 ? 32 : 16,
            40,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PreparationHero(catalog: catalog),
                    const SizedBox(height: 24),
                    Text('1. 목적지',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    if (region != null) _RegionCard(region: region),
                    const SizedBox(height: 24),
                    Text('2. 탐험대 편성',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      '최대 3명. 이번 길에서 활약시키고 싶은 캐릭터를 직접 골라요.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 10),
                    if (state.roster.isEmpty)
                      const MongrooPanel(
                        child: Text('새싹 단계 이상의 캐릭터가 생기면 함께 탐험할 수 있어요.'),
                      )
                    else
                      ...state.roster.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RosterTile(
                            item: item,
                            selected:
                                state.selectedPlantIds.contains(item.plantId),
                            enabled: state.busyAction == null,
                            onChanged: item.eligible
                                ? () => ref
                                    .read(expeditionControllerProvider.notifier)
                                    .togglePlant(item.plantId)
                                : null,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text('3. 출발 방식',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    if (!catalog.tutorialCompleted) ...[
                      _TutorialCoachCard(
                        step: 1,
                        onDismiss: null,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _StartActions(state: state),
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

class _PreparationHero extends StatelessWidget {
  const _PreparationHero({required this.catalog});

  final ExpeditionCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MongrooPanel(
      borderColor: scheme.primary.withAlpha(80),
      radius: 18,
      padding: EdgeInsets.zero,
      child: MossArchiveScene(
        borderRadius: BorderRadius.circular(18),
        semanticLabel: '갈림길과 오래된 서가가 보이는 이끼 기억서고 탐험지',
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                MongrooPalette.of(context).night.withAlpha(205),
                MongrooPalette.of(context).night.withAlpha(84),
                Colors.transparent,
              ],
              stops: const [0, .62, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MongrooTag(
                  label: '첫 지역 · 이끼 기억서고',
                  icon: Icons.map_outlined,
                  backgroundColor: scheme.surface.withAlpha(232),
                ),
                const SizedBox(height: 72),
                Text(
                  '내가 키운 캐릭터와\n직접 길을 골라요',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.onNight,
                      ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Text(
                    catalog.diaryReady
                        ? '오늘 마음 일기가 탐험의 공명을 열었어요. 이동과 선택, 스킬 판정을 직접 진행해요.'
                        : '자유 탐험은 언제든 가능해요. 오늘 마음 일기를 쓰면 성장과 씨앗이 있는 공명 탐험이 열려요.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onNightMuted,
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

class _RegionCard extends StatelessWidget {
  const _RegionCard({required this.region});

  final ExpeditionRegion region;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, color: palette.leaf),
              const SizedBox(width: 10),
              Expanded(
                child: Text(region.name,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              MongrooTag(
                label: '권장 ${region.recommendedStage}단계',
                icon: Icons.spa_outlined,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(region.description),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MongrooTag(
                  label: '성장 +${region.rewardExp}', icon: Icons.trending_up),
              MongrooTag(
                  label: '씨앗 +${region.rewardSeeds}',
                  icon: Icons.grass_outlined),
              const MongrooTag(label: '8개 노드', icon: Icons.route_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final ExpeditionRosterItem item;
  final bool selected;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MongrooPressable(
      onTap: enabled ? onChanged : null,
      semanticLabel: '${item.name}, ${selected ? '탐험대에서 제외' : '탐험대에 추가'}',
      borderRadius: BorderRadius.circular(16),
      child: MongrooPanel(
        shadowOffset: Offset.zero,
        borderColor: selected ? scheme.primary : scheme.outlineVariant,
        color: selected ? scheme.primaryContainer.withAlpha(125) : null,
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    '${item.speciesName} · ${item.stage}단계 · ${_formLabel(item.form)}'
                    '${item.isActive ? ' · 성장 중' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  if (!item.eligible) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.ineligibleReason ?? '아직 탐험할 수 없어요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            MongrooTag(
              label:
                  '최고 ${item.stats.values.fold<int>(0, (a, b) => a > b ? a : b)}',
              icon: Icons.auto_graph_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _StartActions extends ConsumerWidget {
  const _StartActions({required this.state});

  final ExpeditionUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(expeditionControllerProvider.notifier);
    final busy = state.busyAction != null;
    final hasParty = state.selectedPlantIds.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: !busy && hasParty && state.catalog!.heartResonanceAvailable
              ? () => controller.start('heart_resonance')
              : null,
          icon: busy && state.busyAction?.startsWith('start:heart') == true
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.favorite_outline),
          label: const Text('마음 공명 탐험 시작'),
        ),
        const SizedBox(height: 8),
        Text(
          state.catalog!.heartResonanceAvailable
              ? '오늘 1회, 목표를 확보하고 귀환하면 성장과 씨앗을 받아요.'
              : '마음 공명 보상은 오늘 50자 이상의 마음 일기를 쓴 뒤 열려요.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: !busy && hasParty && state.catalog!.freeExploreAvailable
              ? () => controller.start('free_explore')
              : null,
          icon: const Icon(Icons.route_outlined),
          label: const Text('보상 없이 자유 탐험'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed:
              !busy && hasParty ? () => controller.start('tutorial') : null,
          icon: const Icon(Icons.school_outlined),
          label: const Text('안내자와 조작 연습'),
        ),
      ],
    );
  }
}

class _ActiveExpedition extends ConsumerWidget {
  const _ActiveExpedition({required this.state, required this.expedition});

  final ExpeditionUiState state;
  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final content = [
      Expanded(
          flex: 6, child: _MapColumn(state: state, expedition: expedition)),
      if (width >= 820)
        const SizedBox(width: 16)
      else
        const SizedBox(height: 16),
      Expanded(
          flex: 4,
          child: _DecisionColumn(state: state, expedition: expedition)),
    ];
    return RefreshIndicator(
      onRefresh: ref.read(expeditionControllerProvider.notifier).load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            width >= 720 ? 24 : 12, 12, width >= 720 ? 24 : 12, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.tutorialCoachStep != null &&
                      state.tutorialCoachStep != 3 &&
                      state.tutorialCoachStep != 4) ...[
                    _TutorialCoachCard(
                      step: state.tutorialCoachStep!,
                      onDismiss: ref
                          .read(expeditionControllerProvider.notifier)
                          .dismissTutorialCoach,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _ExpeditionStatusBar(expedition: expedition),
                  const SizedBox(height: 12),
                  width >= 820
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: content,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MapColumn(state: state, expedition: expedition),
                            const SizedBox(height: 16),
                            _DecisionColumn(
                              state: state,
                              expedition: expedition,
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpeditionStatusBar extends StatelessWidget {
  const _ExpeditionStatusBar({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '길빛 ${expedition.run.trailLight}, 결의 ${expedition.run.resolve}',
      child: MongrooPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
            final trailLight = _ResourceMeter(
              icon: Icons.light_mode_outlined,
              label: '길빛',
              value: expedition.run.trailLight,
              max: 12,
              color: scheme.tertiary,
            );
            final resolve = _ResourceMeter(
              icon: Icons.shield_outlined,
              label: '결의',
              value: expedition.run.resolve,
              max: 6,
              color: scheme.secondary,
            );
            if (largeText || constraints.maxWidth < 280) {
              return Column(
                children: [
                  trailLight,
                  const SizedBox(height: 12),
                  resolve,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: trailLight),
                const SizedBox(width: 16),
                Expanded(child: resolve),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResourceMeter extends StatelessWidget {
  const _ResourceMeter({
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text('$label $value/$max',
                  style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
              value: value / max, color: color, minHeight: 6),
        ],
      );
}

class _MapColumn extends StatelessWidget {
  const _MapColumn({required this.state, required this.expedition});

  final ExpeditionUiState state;
  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context) {
    final threadText = expedition.runThread['current_text'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (threadText != null && threadText.isNotEmpty) ...[
          MongrooPanel(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            shadowOffset: Offset.zero,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_stories_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(threadText)),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        MongrooPanel(
          padding: const EdgeInsets.all(10),
          child: AspectRatio(
            aspectRatio: 1.55,
            child: _ExpeditionMap(state: state, expedition: expedition),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          expedition.run.phase == 'awaiting_event'
              ? '사건을 해결하면 다음 길이 열려요.'
              : '밝게 표시된 장소를 눌러 이동해요. 이동에는 길빛이 들어요.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ExpeditionMap extends ConsumerWidget {
  const _ExpeditionMap({required this.state, required this.expedition});

  final ExpeditionUiState state;
  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final nodes = expedition.nodes.where((node) => node.isPositioned).toList();
    return MossArchiveScene(
      semanticLabel: '${expedition.region.name}의 갈림길 탐험 지도',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const nodeWidth = 74.0;
          const nodeHeight = 68.0;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MapEdgePainter(
                    nodes: nodes,
                    edges: expedition.edges,
                    currentCode: expedition.run.currentNodeCode,
                    lineColor: AppTheme.onNight.withAlpha(125),
                    activeColor: scheme.primary,
                  ),
                ),
              ),
              for (final node in nodes)
                Positioned(
                  left: (node.x! * constraints.maxWidth - nodeWidth / 2)
                      .clamp(0.0, constraints.maxWidth - nodeWidth),
                  top: (node.y! * constraints.maxHeight - nodeHeight / 2)
                      .clamp(0.0, constraints.maxHeight - nodeHeight),
                  width: nodeWidth,
                  height: nodeHeight,
                  child: _MapNodeButton(
                    node: node,
                    current: node.code == expedition.run.currentNodeCode,
                    available:
                        expedition.availableMoveCodes.contains(node.code),
                    busy: state.busyAction != null,
                    onTap: () async {
                      final moved = await ref
                          .read(expeditionControllerProvider.notifier)
                          .move(node.code);
                      if (moved) HapticFeedback.selectionClick();
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MapNodeButton extends StatelessWidget {
  const _MapNodeButton({
    required this.node,
    required this.current,
    required this.available,
    required this.busy,
    required this.onTap,
  });

  final ExpeditionNode node;
  final bool current;
  final bool available;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = available && !busy;
    final background = current
        ? scheme.primary
        : available
            ? scheme.primaryContainer.withAlpha(238)
            : scheme.surface.withAlpha(205);
    final foreground = current
        ? scheme.onPrimary
        : available
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: current,
      label: current
          ? '${node.name}, 현재 위치'
          : available
              ? '${node.name}, 길빛 ${node.cost}를 사용해 이동'
              : '${node.name}, 현재 이동할 수 없음',
      child: Tooltip(
        message: node.name,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 48,
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : MongrooMotion.standard,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: background,
                  border: Border.all(
                    color: current || available
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: current ? 3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(current ? 95 : 58),
                      blurRadius: current ? 14 : 7,
                      offset: const Offset(0, 3),
                    ),
                    if (current)
                      BoxShadow(
                        color: scheme.primary.withAlpha(90),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: enabled ? onTap : null,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(_nodeIcon(node.type), color: foreground, size: 23),
                        if (available && node.cost > 0)
                          Positioned(
                            right: 1,
                            bottom: 1,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.inverseSurface,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '-${node.cost}',
                                textScaler: TextScaler.noScaling,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.onInverseSurface,
                                      fontSize: 10,
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
            const SizedBox(height: 2),
            if (current || available)
              Container(
                constraints: const BoxConstraints(maxWidth: 74),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: MongrooPalette.of(context).night.withAlpha(205),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  current ? '현재 · ${node.name}' : node.name,
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.onNight,
                        fontSize: 10,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapEdgePainter extends CustomPainter {
  _MapEdgePainter({
    required this.nodes,
    required this.edges,
    required this.currentCode,
    required this.lineColor,
    required this.activeColor,
  });

  final List<ExpeditionNode> nodes;
  final List<List<String>> edges;
  final String currentCode;
  final Color lineColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final byCode = {for (final node in nodes) node.code: node};
    for (final edge in edges) {
      final left = byCode[edge[0]];
      final right = byCode[edge[1]];
      if (left == null || right == null) continue;
      final start = Offset(left.x! * size.width, left.y! * size.height);
      final end = Offset(right.x! * size.width, right.y! * size.height);
      final active = left.code == currentCode || right.code == currentCode;
      final midpoint = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(midpoint, start.dy, midpoint, end.dy, end.dx, end.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withAlpha(95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 9 : 7
          ..strokeCap = StrokeCap.round,
      );
      if (active) {
        canvas.drawPath(
          path,
          Paint()
            ..color = activeColor.withAlpha(65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 12
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = active ? activeColor : lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 4 : 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapEdgePainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.edges != edges ||
      oldDelegate.currentCode != currentCode ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.activeColor != activeColor;
}

class _DecisionColumn extends ConsumerWidget {
  const _DecisionColumn({required this.state, required this.expedition});

  final ExpeditionUiState state;
  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = expedition.currentEvent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.tutorialCoachStep == 3 || state.tutorialCoachStep == 4) ...[
          _TutorialCoachCard(
            step: state.tutorialCoachStep!,
            onDismiss: ref
                .read(expeditionControllerProvider.notifier)
                .dismissTutorialCoach,
          ),
          const SizedBox(height: 10),
        ],
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : MongrooMotion.standard,
          switchInCurve: MongrooMotion.enter,
          child: event == null
              ? _TravelDecisionPanel(
                  key: const ValueKey('travel'),
                  state: state,
                  expedition: expedition)
              : _EventDecisionPanel(
                  key: ValueKey(event.code),
                  state: state,
                  expedition: expedition,
                  event: event,
                ),
        ),
      ],
    );
  }
}

class _TutorialCoachCard extends StatelessWidget {
  const _TutorialCoachCard({required this.step, required this.onDismiss});

  final int step;
  final VoidCallback? onDismiss;

  static const _titles = {
    1: '첫 탐험은 가볍게 연습해요',
    2: '연결된 방을 직접 골라요',
    3: '사건에 맞는 캐릭터를 골라요',
    4: '고유 스킬로 판정을 바꿔 보세요',
    5: '다른 길도 틀린 길은 아니에요',
    6: '목표를 확보했어요',
  };
  static const _descriptions = {
    1: '현재 자라는 캐릭터와 안내자가 함께해요. 보상과 관계없이 언제든 다시 연습할 수 있어요.',
    2: '밝게 표시된 방을 누르면 길빛 비용과 방 종류를 확인하고 이동해요.',
    3: '능력치 미리보기를 비교한 뒤 행동할 캐릭터와 선택지를 고르세요.',
    4: '강조된 고유 스킬은 이번 사건의 판정이나 손실을 즉시 바꿔요. 그냥 해결해도 괜찮아요.',
    5: '목표 방향과 발견 방향 중 원하는 길을 골라요. 이 연습에서는 되돌아가도 불이익이 없어요.',
    6: '지금 귀환하면 발견과 기록이 저장돼요. 더 살펴보고 싶다면 다른 길을 먼저 둘러봐도 돼요.',
  };

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: '튜토리얼 $step단계. ${_titles[step]}. ${_descriptions[step]}',
        child: MongrooPanel(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderColor: Theme.of(context).colorScheme.primary.withAlpha(90),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    child: Text('$step'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_titles[step] ?? '탐험 조작 안내',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(_descriptions[step] ?? ''),
                      ],
                    ),
                  ),
                ],
              ),
              if (onDismiss != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onDismiss,
                    child: Text(step == 3 ? '다음: 스킬 보기' : '알겠어요'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _TravelDecisionPanel extends ConsumerWidget {
  const _TravelDecisionPanel(
      {super.key, required this.state, required this.expedition});

  final ExpeditionUiState state;
  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = expedition.nodes.firstWhere(
      (node) => node.code == expedition.run.currentNodeCode,
    );
    final busy = state.busyAction != null;
    return MongrooPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(_nodeIcon(current.type),
              size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(current.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            expedition.run.objectiveSecured
                ? '기억 서랍을 확보했어요. 귀환 통로를 찾아 무사히 돌아가요.'
                : '지도에서 다음 장소를 직접 골라 주세요. 갈림길마다 다른 사건과 회복 지점이 있어요.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text('누가 길을 살펴볼까요?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _PartySelector(
            expedition: expedition,
            selectedMemberId:
                state.selectedMemberId ?? expedition.party.first.id,
            busy: busy,
          ),
          const SizedBox(height: 12),
          _MemberSkillActions(
            selected: expedition.party.firstWhere(
              (member) =>
                  member.id ==
                  (state.selectedMemberId ?? expedition.party.first.id),
            ),
            busy: busy,
          ),
          if (expedition.loot.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...expedition.loot.map(
              (loot) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(loot.name),
                subtitle: Text(
                  loot.disposition == 'candidate'
                      ? '귀환하면 수집함에 담겨요.'
                      : '이번 탐험의 발견 기록이에요.',
                ),
                trailing: Text('×${loot.quantity}'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (expedition.canExtract)
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () =>
                      ref.read(expeditionControllerProvider.notifier).extract(),
              icon: const Icon(Icons.home_outlined),
              label: const Text('목표를 안고 귀환'),
            ),
          if (expedition.canRetreat) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: busy ? null : () => _confirmRetreat(context, ref),
              icon: const Icon(Icons.keyboard_return_outlined),
              label: const Text('지금 안전하게 돌아가기'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRetreat(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지금 돌아갈까요?'),
        content: const Text('확보하지 못한 보상은 받지 않지만, 캐릭터와 남긴 선택 기록은 보존돼요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 탐험')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('안전 귀환'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(expeditionControllerProvider.notifier).retreat();
    }
  }
}

class _EventDecisionPanel extends ConsumerWidget {
  const _EventDecisionPanel({
    super.key,
    required this.state,
    required this.expedition,
    required this.event,
  });

  final ExpeditionUiState state;
  final ExpeditionSnapshot expedition;
  final ExpeditionEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberId = state.selectedMemberId ?? expedition.party.first.id;
    final selected =
        expedition.party.firstWhere((member) => member.id == memberId);
    final busy = state.busyAction != null;
    return MongrooPanel(
      borderColor: Theme.of(context).colorScheme.secondary.withAlpha(110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.question_mark_rounded,
                  color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(event.title,
                      style: Theme.of(context).textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 8),
          Text(event.text),
          const SizedBox(height: 16),
          Text('누가 나설까요?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _PartySelector(
            expedition: expedition,
            selectedMemberId: memberId,
            busy: busy,
            spotlightMemberId: event.spotlightMemberId,
          ),
          const SizedBox(height: 12),
          _MemberSkillActions(selected: selected, busy: busy),
          const SizedBox(height: 12),
          ...event.choices.map((choice) {
            final preview = choice.previewFor(memberId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final success = await ref
                            .read(expeditionControllerProvider.notifier)
                            .choose(choice.code);
                        if (success) HapticFeedback.mediumImpact();
                      },
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(choice.label),
                    if (preview != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${preview.label}${preview.forecast == null ? '' : ' · ${preview.forecast}'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PartySelector extends ConsumerWidget {
  const _PartySelector({
    required this.expedition,
    required this.selectedMemberId,
    required this.busy,
    this.spotlightMemberId,
  });

  final ExpeditionSnapshot expedition;
  final int selectedMemberId;
  final bool busy;
  final int? spotlightMemberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: expedition.party
            .map(
              (member) => ChoiceChip(
                avatar: Icon(
                  member.id == spotlightMemberId
                      ? Icons.star_outline_rounded
                      : member.isGuide
                          ? Icons.assistant_outlined
                          : Icons.person_outline,
                  size: 18,
                ),
                label: Text(member.name),
                selected: member.id == selectedMemberId,
                onSelected: busy
                    ? null
                    : (_) => ref
                        .read(expeditionControllerProvider.notifier)
                        .selectMember(member.id),
              ),
            )
            .toList(growable: false),
      );
}

class _MemberSkillActions extends ConsumerWidget {
  const _MemberSkillActions({required this.selected, required this.busy});

  final ExpeditionMember selected;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selected.isGuide) {
      return Text(
        '기록 안내자는 조작을 설명하지만 캐릭터 스킬은 사용하지 않아요.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    final actions = [
      _SkillActionData(
        type: 'signature',
        icon: Icons.bolt_outlined,
        skill: selected.signatureSkill,
      ),
      _SkillActionData(
        type: 'form',
        icon: Icons.auto_awesome_outlined,
        skill: selected.formSkill,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = actions
                .map(
                  (action) => _SkillButton(
                    data: action,
                    busy: busy,
                    onPressed: () => _activateSkill(context, ref, action),
                  ),
                )
                .toList(growable: false);
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buttons.first,
                  const SizedBox(height: 8),
                  buttons.last,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: buttons.first),
                const SizedBox(width: 8),
                Expanded(child: buttons.last),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          '${selected.signatureSkill.name}: ${selected.signatureSkill.description}\n'
          '${selected.formSkill.name}: ${selected.formSkill.description}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (selected.hasRegionAdjustment) ...[
          const SizedBox(height: 6),
          Text(
            '이 지역은 능력치를 ${selected.statCap}까지 보정해요. '
            '선택지에서 원래 수치와 탐험 수치를 함께 보여 줄게요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class _SkillActionData {
  const _SkillActionData({
    required this.type,
    required this.icon,
    required this.skill,
  });

  final String type;
  final IconData icon;
  final ExpeditionSkill skill;
}

class _SkillButton extends StatelessWidget {
  const _SkillButton({
    required this.data,
    required this.busy,
    required this.onPressed,
  });

  final _SkillActionData data;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skill = data.skill;
    final status = skill.used
        ? '사용함'
        : skill.available
            ? null
            : '지금은 사용 불가';
    return Semantics(
      button: true,
      enabled: !busy && skill.available,
      label:
          '${skill.name}. ${skill.description}${status == null ? '' : '. $status'}',
      child: Tooltip(
        message: skill.description,
        child: OutlinedButton.icon(
          onPressed: busy || !skill.available ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          icon: Icon(data.icon),
          label: Text(status == null ? skill.name : '${skill.name} · $status'),
        ),
      ),
    );
  }
}

Future<void> _activateSkill(
  BuildContext context,
  WidgetRef ref,
  _SkillActionData action,
) async {
  final modes = action.skill.modes;
  String? modeCode;
  if (modes.length == 1) {
    modeCode = modes.single.code;
  } else if (modes.length > 1) {
    modeCode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(action.skill.name,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(action.skill.description),
              const SizedBox(height: 16),
              ...modes.map(
                (mode) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, mode.code),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(mode.label),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (modeCode == null) return;
  }
  final success = await ref
      .read(expeditionControllerProvider.notifier)
      .useSkill(action.type, modeCode: modeCode);
  if (success) HapticFeedback.lightImpact();
}

class _ExpeditionSummary extends ConsumerWidget {
  const _ExpeditionSummary({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = expedition.run.status == 'completed';
    final summary = expedition.summary ?? const {};
    final reward = summary['reward'] is Map<String, dynamic>
        ? summary['reward'] as Map<String, dynamic>
        : null;
    final returnScene = summary['return_scene'] is Map<String, dynamic>
        ? summary['return_scene'] as Map<String, dynamic>
        : null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: MongrooPanel(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    completed
                        ? Icons.home_filled
                        : Icons.health_and_safety_outlined,
                    size: 52,
                    color: completed
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    summary['title'] as String? ?? '탐험에서 돌아왔어요',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    completed
                        ? '길에서 고른 선택과 캐릭터의 활약이 탐험 기록에 남았어요.'
                        : '무리하지 않고 돌아오는 것도 좋은 탐험 판단이에요.',
                    textAlign: TextAlign.center,
                  ),
                  if (returnScene != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withAlpha(130),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            returnScene['title'] as String? ?? '함께 돌아온 기록',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(returnScene['caption'] as String? ?? ''),
                          const SizedBox(height: 8),
                          for (final member
                              in (returnScene['members'] as List? ?? const []))
                            if (member is Map<String, dynamic>)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                leading: Icon(
                                  member['is_guide'] == true
                                      ? Icons.assistant_outlined
                                      : Icons.favorite_outline_rounded,
                                ),
                                title:
                                    Text(member['name'] as String? ?? '탐험대원'),
                                subtitle: Text(
                                  member['contribution'] as String? ??
                                      '함께 무사히 돌아왔어요.',
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                  if (reward != null) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final event
                            in (reward['events'] as List? ?? const []))
                          if (event is Map<String, dynamic>) ...[
                            MongrooTag(
                              label: '성장 +${event['exp_delta'] ?? 0}',
                              icon: Icons.trending_up,
                            ),
                            MongrooTag(
                              label: '씨앗 +${event['seed_delta'] ?? 0}',
                              icon: Icons.grass_outlined,
                            ),
                          ],
                      ],
                    ),
                  ],
                  if (expedition.loot.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    ...expedition.loot.map(
                      (loot) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(loot.name),
                        trailing: Text('×${loot.quantity}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await ref
                            .read(expeditionControllerProvider.notifier)
                            .leaveSummary();
                        if (expedition.run.mode == 'tutorial' &&
                            context.mounted) {
                          await Navigator.of(context).maybePop();
                        }
                      },
                      icon: Icon(
                        expedition.run.mode == 'tutorial'
                            ? Icons.home_outlined
                            : Icons.list_alt_outlined,
                      ),
                      label: Text(
                        expedition.run.mode == 'tutorial'
                            ? '홈으로 돌아가 쉬기'
                            : '탐험 목록으로',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(description, textAlign: TextAlign.center),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      );
}

IconData _nodeIcon(String type) => switch (type) {
      'entrance' => Icons.login_outlined,
      'event' => Icons.question_mark_rounded,
      'camp' => Icons.local_florist_outlined,
      'discovery' => Icons.search_outlined,
      'guardian' => Icons.shield_outlined,
      'objective' => Icons.inventory_2_outlined,
      'exit' => Icons.home_outlined,
      _ => Icons.circle_outlined,
    };

String _formLabel(String form) => switch (form) {
      'sunny' => '햇살',
      'rainy' => '빗결',
      'ember' => '불씨',
      'moonlit' => '달빛',
      'sparkling' => '반짝임',
      _ => '모자이크',
    };
