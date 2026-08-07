part of 'expedition_screen.dart';

// 통합 지형 위의 경로, 랜드마크, 파티 위치만 담당하는 지도 레이어.
class _ExpeditionMap extends ConsumerStatefulWidget {
  const _ExpeditionMap({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  ConsumerState<_ExpeditionMap> createState() => _ExpeditionMapState();
}

class _ExpeditionMapState extends ConsumerState<_ExpeditionMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel;
  late Offset _from;
  late Offset _to;
  late String _toCode;
  late List<Offset> _route;

  @override
  void initState() {
    super.initState();
    _toCode = widget.expedition.run.currentNodeCode;
    _to = _currentPosition(widget.expedition);
    _from = _to;
    _route = [_to];
    _travel = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _ExpeditionMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextCode = widget.expedition.run.currentNodeCode;
    final next = _currentPosition(widget.expedition);
    if (nextCode == _toCode && next == _to) return;
    _from = mossArchiveRoutePosition(_route, _travel.value);
    final nextRoute = mossArchiveRouteBetween(
      _toCode,
      nextCode,
      fallbackFrom: _to,
      fallbackTo: next,
    );
    _route = [_from, ...nextRoute.skip(1)];
    _to = next;
    _toCode = nextCode;
    _travel.duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 1)
        : const Duration(milliseconds: 940);
    _travel.forward(from: 0);
  }

  Offset _currentPosition(ExpeditionSnapshot expedition) {
    for (final node in expedition.nodes) {
      if (node.code == expedition.run.currentNodeCode && node.isPositioned) {
        return Offset(node.x!, node.y!);
      }
    }
    return const Offset(.08, .5);
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expedition = widget.expedition;
    final nodes = expedition.nodes.where((node) => node.isPositioned).toList();
    final current = nodes.firstWhere(
      (node) => node.code == expedition.run.currentNodeCode,
    );
    final explored = nodes
        .where((node) => node.status == 'visited' || node.status == 'resolved')
        .length;
    return MossArchiveScene(
      semanticLabel:
          '${expedition.region.name}의 통합 지형. 동굴과 땅굴, 소굴, 보물고와 탑이 길로 이어져 있어요.',
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      fit: BoxFit.fill,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MapTrailPainter(
                    nodes: nodes,
                    edges: expedition.edges,
                    currentCode: expedition.run.currentNodeCode,
                    availableCodes: expedition.availableMoveCodes,
                    activeColor: scheme.primary,
                  ),
                ),
              ),
              for (final node in nodes)
                Positioned(
                  left: (node.x! * constraints.maxWidth - 22)
                      .clamp(0.0, constraints.maxWidth - 44),
                  top: (node.y! * constraints.maxHeight - 22)
                      .clamp(0.0, constraints.maxHeight - 44),
                  width: 44,
                  height: 44,
                  child: _InteractiveLandmarkBeacon(
                    node: node,
                    current: node.code == expedition.run.currentNodeCode,
                    available:
                        expedition.availableMoveCodes.contains(node.code),
                  ),
                ),
              for (final node in nodes.where(
                (node) => expedition.availableMoveCodes.contains(node.code),
              ))
                Positioned(
                  left: (node.x! * constraints.maxWidth - 58)
                      .clamp(4.0, constraints.maxWidth - 120),
                  top: (node.y! * constraints.maxHeight +
                          (node.y! > .63 ? -61 : 20))
                      .clamp(40.0, constraints.maxHeight - 42),
                  width: 116,
                  child: _DestinationBeaconLabel(node: node),
                ),
              AnimatedBuilder(
                animation: _travel,
                builder: (context, _) {
                  final position = mossArchiveRoutePosition(
                    _route,
                    Curves.easeInOutCubic.transform(_travel.value),
                  );
                  return Positioned(
                    left: (position.dx * constraints.maxWidth - 32)
                        .clamp(0.0, constraints.maxWidth - 64),
                    top: (position.dy * constraints.maxHeight - 58)
                        .clamp(0.0, constraints.maxHeight - 64),
                    width: 64,
                    height: 64,
                    child: _PartyTrailMarker(
                      moving: _travel.isAnimating,
                      label: '현재 위치 ${current.name}',
                      party: expedition.party,
                    ),
                  );
                },
              ),
              Positioned(
                left: 9,
                top: 9,
                child: _SceneHudTag(
                  icon: Icons.directions_walk_rounded,
                  label: '현재 · ${current.name}',
                  color: const Color(0xFFFFE19A),
                ),
              ),
              Positioned(
                right: 9,
                top: 9,
                child: _SceneHudTag(
                  icon: Icons.travel_explore_rounded,
                  label: constraints.maxWidth < 360
                      ? '$explored/${expedition.nodes.length}'
                      : '$explored/${expedition.nodes.length} 발견',
                  color: const Color(0xFFB5E6D1),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 조작 잠금만 구독해 지도 원화·경로·캐릭터 마커는 다시 만들지 않는다.
class _InteractiveLandmarkBeacon extends ConsumerWidget {
  const _InteractiveLandmarkBeacon({
    required this.node,
    required this.current,
    required this.available,
  });

  final ExpeditionNode node;
  final bool current;
  final bool available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(
      expeditionControllerProvider.select(
        (state) => state.interactionLocked,
      ),
    );
    return _LandmarkBeacon(
      node: node,
      current: current,
      available: available,
      busy: busy,
      onTap: () async {
        final moved = await ref
            .read(expeditionControllerProvider.notifier)
            .move(node.code);
        if (moved) HapticFeedback.selectionClick();
      },
    );
  }
}

class _LandmarkBeacon extends StatelessWidget {
  const _LandmarkBeacon({
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
    final enabled = available && !busy;
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
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: enabled ? onTap : null,
            radius: 22,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            child: Center(
              child: AnimatedScale(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : MongrooMotion.standard,
                scale: available ? 1 : .72,
                child: SizedBox(
                  width: 30,
                  height: 22,
                  child: CustomPaint(
                    painter: _LandmarkGlowPainter(
                      current: current,
                      available: available,
                      resolved: node.status == 'resolved',
                    ),
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

class _LandmarkGlowPainter extends CustomPainter {
  const _LandmarkGlowPainter({
    required this.current,
    required this.available,
    required this.resolved,
  });

  final bool current;
  final bool available;
  final bool resolved;

  @override
  void paint(Canvas canvas, Size size) {
    if (!current && !available && !resolved) return;
    final center = Offset(size.width / 2, size.height * .66);
    final rect = Rect.fromCenter(
      center: center,
      width: available ? 26 : 15,
      height: available ? 11 : 6,
    );
    final color = available
        ? const Color(0xFFFFD98A)
        : resolved
            ? const Color(0xFF9CD7B8)
            : AppTheme.onNight;
    if (available) {
      canvas.drawOval(
        rect.inflate(4),
        Paint()
          ..color = color.withAlpha(65)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withAlpha(available ? 35 : 22)
        ..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withAlpha(available ? 220 : 105)
        ..style = PaintingStyle.stroke
        ..strokeWidth = available ? 1.5 : 1,
    );
  }

  @override
  bool shouldRepaint(covariant _LandmarkGlowPainter oldDelegate) =>
      oldDelegate.current != current ||
      oldDelegate.available != available ||
      oldDelegate.resolved != resolved;
}

class _DestinationBeaconLabel extends StatelessWidget {
  const _DestinationBeaconLabel({required this.node});

  final ExpeditionNode node;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MongrooPalette.of(context).night.withAlpha(218),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFFFD98A).withAlpha(100)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(90),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.onNight,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (node.cost > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '-${node.cost}',
                    textScaler: TextScaler.noScaling,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFFFFD98A),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _PartyTrailMarker extends StatelessWidget {
  const _PartyTrailMarker({
    required this.moving,
    required this.label,
    required this.party,
  });

  final bool moving;
  final String label;
  final List<ExpeditionMember> party;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: RepaintBoundary(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PartyMarkerPainter(
                    color: const Color(0xFFFFE3A0),
                    moving: moving,
                  ),
                ),
              ),
              for (var index = 0; index < party.length && index < 3; index++)
                Positioned(
                  left: 4 + index * 12,
                  bottom: 5 + (index == 1 ? 3 : 0),
                  width: 38,
                  height: 56,
                  child: PlantView(
                    stage: party[index].stage,
                    form: PlantGrowthForm.fromCode(party[index].form),
                    speciesCode: party[index].speciesCode,
                    speciesName: party[index].speciesName,
                    spritePose: PlantSpritePose.idle,
                    outfitKey: party[index].outfitKey,
                    width: 38,
                    height: 56,
                  ),
                ),
            ],
          ),
        ),
      );
}

class _PartyMarkerPainter extends CustomPainter {
  const _PartyMarkerPainter({required this.color, required this.moving});

  final Color color;
  final bool moving;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 8);
    canvas.drawCircle(
      center,
      moving ? 16 : 13,
      Paint()
        ..color = color.withAlpha(moving ? 72 : 48)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 38, height: 10),
      Paint()..color = Colors.black.withAlpha(115),
    );
    canvas.drawArc(
      Rect.fromCenter(center: center, width: 34, height: 14),
      0,
      3.14,
      false,
      Paint()
        ..color = color.withAlpha(190)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _PartyMarkerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.moving != moving;
}

class _MapTrailPainter extends CustomPainter {
  _MapTrailPainter({
    required this.nodes,
    required this.edges,
    required this.currentCode,
    required this.availableCodes,
    required this.activeColor,
  });

  final List<ExpeditionNode> nodes;
  final List<List<String>> edges;
  final String currentCode;
  final Set<String> availableCodes;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final byCode = {for (final node in nodes) node.code: node};
    for (final edge in edges) {
      final left = byCode[edge[0]];
      final right = byCode[edge[1]];
      if (left == null || right == null) continue;
      final active =
          (left.code == currentCode && availableCodes.contains(right.code)) ||
              (right.code == currentCode && availableCodes.contains(left.code));
      final walked = _walked(left) && _walked(right);
      if (!active && !walked) continue;
      final route = mossArchiveRouteBetween(
        left.code,
        right.code,
        fallbackFrom: Offset(left.x!, left.y!),
        fallbackTo: Offset(right.x!, right.y!),
      );
      final path = Path()
        ..moveTo(route.first.dx * size.width, route.first.dy * size.height);
      for (final point in route.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      for (final metric in path.computeMetrics()) {
        final step = active ? 18.0 : 22.0;
        for (var distance = 8.0;
            distance < metric.length - 6;
            distance += step) {
          final tangent = metric.getTangentForOffset(distance);
          if (tangent == null) continue;
          canvas.save();
          canvas.translate(tangent.position.dx, tangent.position.dy);
          canvas.rotate(tangent.angle);
          final paint = Paint()
            ..color = active
                ? activeColor.withAlpha(185)
                : AppTheme.onNight.withAlpha(48);
          canvas.drawOval(
            Rect.fromCenter(
              center: const Offset(-2.5, -2.3),
              width: active ? 4 : 3,
              height: active ? 7 : 5,
            ),
            paint,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: const Offset(3.5, 2.5),
              width: active ? 4 : 3,
              height: active ? 7 : 5,
            ),
            paint,
          );
          canvas.restore();
        }
      }
    }
  }

  bool _walked(ExpeditionNode node) =>
      node.status == 'visited' || node.status == 'resolved';

  @override
  bool shouldRepaint(covariant _MapTrailPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.edges != edges ||
      oldDelegate.currentCode != currentCode ||
      oldDelegate.availableCodes != availableCodes ||
      oldDelegate.activeColor != activeColor;
}
