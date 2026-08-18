part of 'expedition_screen.dart';

// 통합 지형 위의 경로, 랜드마크, 파티 위치만 담당하는 지도 레이어.
class _ExpeditionMap extends ConsumerStatefulWidget {
  const _ExpeditionMap({required this.expedition});

  final ExpeditionSnapshot expedition;

  @override
  ConsumerState<_ExpeditionMap> createState() => _ExpeditionMapState();
}

class _ExpeditionMapState extends ConsumerState<_ExpeditionMap>
    with TickerProviderStateMixin {
  late final AnimationController _travel;
  late Offset _from;
  late Offset _to;
  late String _toCode;
  late List<Offset> _route;

  /// 마지막으로 발소리를 낸 진행도. 걷는 동안 일정 간격으로만 울린다.
  double _lastStepAt = 0;

  /// 가상 스틱이 눌린 자리와 지금 손가락 자리. 끌지 않을 때는 null이라
  /// 스틱이 화면에 나타나지 않는다 — 늘 떠 있으면 지도를 가린다.
  Offset? _stickCenter;
  Offset? _stickTouch;

  /// 직접 걸을 때의 자리. 노드를 눌러 이동할 때는 경로 애니메이션이 쓰이고
  /// 이 값은 도착 자리로 다시 맞춰진다.
  Offset? _freePosition;

  /// 직접 걷기의 보폭 위상. 서버 경로 애니메이션과 별개로 캐릭터의 들썩임,
  /// 그림자와 발소리가 실제 이동 거리를 따라가게 한다.
  double _freeStride = 0;

  /// 프레임마다 걸음을 옮기는 시계.
  Ticker? _walkTicker;
  Duration _lastTick = Duration.zero;

  /// 이동 요청을 보내는 중인가. 한 노드에 여러 번 보내지 않기 위한 빗장이다.
  bool _movePending = false;

  /// 발소리만 내는 가벼운 재생기.
  ///
  /// 전투 오버레이의 것을 빌려 오지 않는다 — 그건 전투 화면과 함께
  /// 만들어지고 사라지는데 걸음은 전투 밖에서 난다. 음악은 켜지 않아
  /// 배경 재생과 겹치지 않는다(효과음 전용).
  ExpeditionCombatAudio? _steps;

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
    _from = expeditionPathPosition(_route, _travel.value);
    _route = _routeBetween(_from, next);
    _to = next;
    _toCode = nextCode;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _travel.duration = reduceMotion
        ? const Duration(milliseconds: 1)
        : const Duration(milliseconds: 940);
    _lastStepAt = 0;
    _travel.forward(from: 0);
    // 움직임을 줄인 설정에서는 걸음이 한순간에 끝나므로 발소리도 내지
    // 않는다. 소리만 남으면 무슨 일이 일어났는지 알 수 없는 잡음이 된다.
    if (!reduceMotion) {
      _stepSound(widget.expedition);
    }
  }

  /// 지금 밟고 있는 바닥의 소리를 한 번 낸다.
  ///
  /// 재질은 **떠나온 자리**가 아니라 향하는 자리로 정한다 — 걸음의 대부분이
  /// 목적지 쪽 바닥이고, 도착하면 그 장면이 화면을 채우기 때문이다.
  void _stepSound(ExpeditionSnapshot expedition) {
    // 효과음을 끈 사용자에게는 아무것도 만들지 않는다.
    if (!ref.read(expeditionBattleSettingsProvider).sfxEnabled) return;
    _steps ??= ExpeditionCombatAudio(musicEnabled: false, sfxEnabled: true);
    ExpeditionNode? node;
    for (final item in expedition.nodes) {
      if (item.code == _toCode) {
        node = item;
        break;
      }
    }
    unawaited(
      _steps!.play(
        ExpeditionCombatAudio.stepSoundFor(node?.sceneKey),
        // 배경보다 조용하다. 걸음은 계속 나는 소리라 앞에 나서면 지친다.
        volume: .34,
      ),
    );
  }

  /// 걷는 동안 일정 간격으로 발소리를 낸다.
  ///
  /// 프레임마다 내면 소리가 뭉개지고 한 번만 내면 걷는 느낌이 안 난다. 길이와
  /// 무관하게 **같은 보폭**으로 울리도록 진행도 간격으로 센다.
  void _tickSteps(ExpeditionSnapshot expedition) {
    if (!_travel.isAnimating) return;
    const stride = .28;
    if (_travel.value - _lastStepAt < stride) return;
    _lastStepAt = _travel.value;
    _stepSound(expedition);
  }

  void _stickDown(Offset local, Size size) {
    setState(() {
      _stickCenter = local;
      _stickTouch = local;
      // 지금 서 있는 자리에서 출발한다. 노드를 눌러 이동한 직후라면 그 도착
      // 자리다.
      _freePosition ??= _currentPosition(widget.expedition);
    });
    _walkTicker ??= createTicker(_onWalkTick)..start();
    _lastTick = Duration.zero;
  }

  void _stickMove(Offset local) {
    if (_stickCenter == null) return;
    setState(() => _stickTouch = local);
  }

  void _stickUp() {
    _walkTicker?.stop();
    setState(() {
      _stickCenter = null;
      _stickTouch = null;
    });
  }

  /// 한 프레임 걷는다.
  ///
  /// 걸음은 **자리만 옮긴다.** 서버에 무엇을 보낼지는 노드에 닿았을 때만
  /// 정하므로, 지도를 헤매는 동안에는 아무 요청도 나가지 않는다.
  void _onWalkTick(Duration elapsed) {
    final center = _stickCenter;
    final touch = _stickTouch;
    final size = _mapSize;
    if (center == null || touch == null || size == null) return;

    final raw = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (raw <= 0) return;
    // 프레임이 길게 끊긴 만큼을 그대로 걸으면 지도를 가로질러 튄다. 그렇다고
    // **버리면 안 된다** — 느린 기기에서는 모든 프레임이 길어서 걸음이 통째로
    // 멈춘다(실제로 캡처 환경에서 캐릭터가 한 발도 못 움직였다). 잘라서 쓴다.
    final seconds = math.min(raw, .12);

    final direction = expeditionStickVector(center, touch);
    if (direction == Offset.zero) return;

    final area = expeditionWalkAreaFor(widget.expedition.region.code);
    final previous = _freePosition ?? _currentPosition(widget.expedition);
    final aspect = size.height <= 0 ? 1.0 : size.width / size.height;
    final next = expeditionWalkStep(
      area: area,
      from: previous,
      direction: direction,
      seconds: seconds,
      aspect: aspect,
    );
    if (next == previous) return;
    final delta = next - previous;
    final distance = math.sqrt(
      math.pow(delta.dx * aspect, 2) + math.pow(delta.dy, 2),
    );
    setState(() {
      _freePosition = next;
      _freeStride = (_freeStride + distance * 9) % 2;
    });
    _tickFreeSteps(distance);
    _enterNodeIfReached(next);
  }

  /// 직접 걸을 때의 발소리. 지나온 거리로 세어 스틱을 살살 밀어도 보폭이 같다.
  double _freeStepMark = 0;

  void _tickFreeSteps(double distance) {
    _freeStepMark += distance;
    if (_freeStepMark < .06) return;
    _freeStepMark = 0;
    _stepSound(widget.expedition);
  }

  /// 걸어서 노드에 닿으면 그 자리로 들어간다.
  ///
  /// 갈 수 있는 곳일 때만 보낸다 — 간선 판정은 서버가 쥐고 있고, 앱이 규칙을
  /// 다시 계산하지 않는다. 지금 서 있는 노드에는 다시 들어가지 않는다.
  Future<void> _enterNodeIfReached(Offset position) async {
    if (_movePending) return;
    final expedition = widget.expedition;
    final positions = <String, Offset>{
      for (final node in expedition.nodes)
        if (node.isPositioned &&
            expedition.availableMoveCodes.contains(node.code))
          node.code: _standAt(node),
    };
    final code = expeditionNodeAt(positions, position);
    if (code == null || code == expedition.run.currentNodeCode) return;

    _movePending = true;
    try {
      final moved =
          await ref.read(expeditionControllerProvider.notifier).move(code);
      if (moved && mounted) {
        HapticFeedback.selectionClick();
        // 이동이 받아들여지면 경로 애니메이션이 이어받는다. 자유 걸음 자리는
        // 비워 두어 도착 자리에서 다시 시작한다.
        setState(() => _freePosition = null);
        _stickUp();
      }
    } finally {
      _movePending = false;
    }
  }

  /// 스틱이 가리키는 좌우. 잡고 있지 않거나 위아래로만 밀면 null이라
  /// 경로 애니메이션의 방향을 그대로 쓴다.
  double? _stickFacing() {
    final center = _stickCenter;
    final touch = _stickTouch;
    if (center == null || touch == null) return null;
    final direction = expeditionStickVector(center, touch);
    if (direction.dx.abs() < .12) return null;
    return direction.dx >= 0 ? 1 : -1;
  }

  /// 마지막으로 그린 지도 크기. 가로세로 비율 보정에 쓴다.
  Size? _mapSize;

  /// 지금 서 있는 자리.
  ///
  /// 노드 표식이 아니라 **그 곁의 설 자리**다. 표식은 랜드마크 위에 찍히는데
  /// 아치 안이나 나무 그루터기 한가운데인 경우가 있어, 표식 자리에 세우면
  /// 캐릭터가 벽이나 그루터기 위에 올라선다.
  Offset _currentPosition(ExpeditionSnapshot expedition) {
    for (final node in expedition.nodes) {
      if (node.code == expedition.run.currentNodeCode && node.isPositioned) {
        return _standAt(node);
      }
    }
    return expeditionStandPoint(_area, const Offset(.08, .5));
  }

  ExpeditionWalkArea get _area =>
      expeditionWalkAreaFor(widget.expedition.region.code);

  Offset _standAt(ExpeditionNode node) =>
      expeditionStandPoint(_area, Offset(node.x!, node.y!));

  /// 두 자리를 잇는 걸어갈 길. 마스크에서 못 찾으면 곧은 선으로 떨어진다.
  ///
  /// 못 찾는 일은 마스크가 원화와 어긋났을 때뿐이고 생성기가 그걸 막지만,
  /// 여기서 빈 목록을 돌려주면 캐릭터가 아예 움직이지 못한다.
  List<Offset> _routeBetween(Offset from, Offset to) {
    final path = expeditionWalkPath(_area, from, to);
    return path.isEmpty ? [from, to] : path;
  }

  @override
  void dispose() {
    _walkTicker?.dispose();
    _steps?.dispose();
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expedition = widget.expedition;
    final movementEnabled = expedition.run.phase == 'exploring' &&
        !ref.watch(
          expeditionControllerProvider.select(
            (state) => state.interactionLocked,
          ),
        );
    final nodes = expedition.nodes.where((node) => node.isPositioned).toList();
    final current = nodes.firstWhere(
      (node) => node.code == expedition.run.currentNodeCode,
    );
    final explored = nodes
        .where((node) => node.status == 'visited' || node.status == 'resolved')
        .length;
    return MossArchiveScene(
      regionCode: expedition.region.code,
      semanticLabel:
          '${expedition.region.name}의 통합 지형. 동굴과 땅굴, 소굴, 보물고와 탑이 길로 이어져 있어요.',
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      fit: BoxFit.fill,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _mapSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MapTrailPainter(
                    area: _area,
                    nodes: nodes,
                    edges: expedition.edges,
                    currentCode: expedition.run.currentNodeCode,
                    availableCodes: expedition.availableMoveCodes,
                    activeColor: scheme.primary,
                  ),
                ),
              ),
              // 직접 걷는 조작은 노드와 HUD보다 먼저 둔다. Stack은 뒤에 그린
              // 자식을 먼저 hit-test하므로 이 순서여야 랜드마크 탭을 가로막지
              // 않으면서 빈 땅을 끌어 가상 스틱을 쓸 수 있다.
              Positioned.fill(
                child: Semantics(
                  excludeSemantics: true,
                  child: Listener(
                    key: const ValueKey('expedition-walk-surface'),
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: movementEnabled
                        ? (event) => _stickDown(
                              event.localPosition,
                              Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                            )
                        : null,
                    onPointerMove: movementEnabled
                        ? (event) => _stickMove(event.localPosition)
                        : null,
                    onPointerUp: movementEnabled ? (_) => _stickUp() : null,
                    onPointerCancel: movementEnabled ? (_) => _stickUp() : null,
                  ),
                ),
              ),
              for (final node in nodes)
                Positioned(
                  left: (node.x! * constraints.maxWidth - 24)
                      .clamp(0.0, constraints.maxWidth - 48),
                  top: (node.y! * constraints.maxHeight - 24)
                      .clamp(0.0, constraints.maxHeight - 48),
                  width: 48,
                  height: 48,
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
                  final progress =
                      Curves.easeInOutCubic.transform(_travel.value);
                  // 스틱을 잡고 있으면 그 자리가 우선이다. 놓으면 경로
                  // 애니메이션이 다시 토큰을 끈다.
                  final position =
                      _freePosition ?? expeditionPathPosition(_route, progress);
                  if (_freePosition == null) _tickSteps(expedition);
                  // 제작 규격의 지도 토큰 크기는 72~112px다. 좁은 화면에서
                  // 지도를 덮지 않도록 아래쪽을 쓴다.
                  const tokenSize = 88.0;
                  return Positioned(
                    left: (position.dx * constraints.maxWidth - tokenSize / 2)
                        .clamp(0.0, constraints.maxWidth - tokenSize),
                    top: (position.dy * constraints.maxHeight - tokenSize * .82)
                        .clamp(0.0, constraints.maxHeight - tokenSize),
                    width: tokenSize,
                    height: tokenSize,
                    child: IgnorePointer(
                      child: _PartyTrailMarker(
                        moving: _freePosition != null
                            ? expeditionStickVector(
                                  _stickCenter ?? Offset.zero,
                                  _stickTouch ?? Offset.zero,
                                ) !=
                                Offset.zero
                            : _travel.isAnimating,
                        ambient: expeditionRegionGrade(
                          expedition.region.code,
                        ),
                        facing: _stickFacing() ??
                            expeditionPathFacing(_route, progress),
                        stride: _freePosition != null ? _freeStride : progress,
                        label: '현재 위치 ${current.name}',
                        party: expedition.party,
                      ),
                    ),
                  );
                },
              ),
              if (_stickCenter != null && _stickTouch != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _WalkStickPainter(
                        center: _stickCenter!,
                        knob: expeditionStickKnob(
                          _stickCenter!,
                          _stickTouch!,
                        ),
                        color: scheme.primary,
                      ),
                    ),
                  ),
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
            radius: 24,
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
    this.facing = 1,
    this.stride = 0,
    this.ambient = const Color(0x00000000),
  });

  final bool moving;
  final String label;
  final List<ExpeditionMember> party;

  /// 걷는 방향. 1은 오른쪽, -1은 왼쪽이다.
  ///
  /// 좌우 스프라이트를 따로 만들지 않고 뒤집어 쓴다. 제작 규격이 지도
  /// 토큰을 `stage 2~4 transform`으로 두었기 때문이고, 뒤로 걷는 것처럼
  /// 보이지 않게 하는 데는 이것으로 충분하다.
  final double facing;

  /// 길 위의 진행도. 걸음의 들썩임과 그림자 크기를 만드는 데 쓴다.
  final double stride;

  /// 이 지역의 빛 색. 캐릭터에도 같은 색을 얹어 배경에서 떠 보이지 않게 한다.
  ///
  /// 그림자와 명암을 **스프라이트에 굽지 않는 이유**가 여기 있다. 장면마다
  /// 광원이 달라서(우물정원은 위에서 푸른 달빛, 보관고는 서랍 하나의 따뜻한
  /// 빛) 구워 넣으면 어느 장면에서는 반드시 틀린다. 코드로 얹으면 그 지역이
  /// 이미 아는 색을 그대로 쓴다.
  final Color ambient;

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
              // 발밑 그림자. 캐릭터보다 먼저 그려야 아래에 깔린다. 걸을 때
              // 들썩임과 반대로 줄어 바닥에 닿았다 떨어지는 느낌이 난다.
              for (var index = 0; index < party.length && index < 3; index++)
                Positioned(
                  left: 12 + index * 17 + 6,
                  bottom: 4,
                  width: 40,
                  height: 12,
                  child: IgnorePointer(
                    child: Transform.scale(
                      scale: expeditionShadowScale(moving, stride),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF11202A).withValues(alpha: .38),
                              const Color(0x0011202A),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (var index = 0; index < party.length && index < 3; index++)
                Positioned(
                  left: 12 + index * 17,
                  // 걸을 때 살짝 들썩인다. 대원마다 반 박자 어긋내 셋이
                  // 한 덩어리로 튀지 않게 한다.
                  bottom: 7 +
                      (index == 1 ? 3 : 0) +
                      (moving
                          ? 2.2 *
                              math
                                  .sin(
                                    (stride * 9 + index * .7) * math.pi,
                                  )
                                  .abs()
                          : 0),
                  width: 52,
                  height: 76,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..scaleByDouble(facing, 1, 1, 1),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        ambient,
                        BlendMode.srcATop,
                      ),
                      child: PlantView(
                        stage: party[index].stage,
                        form: PlantGrowthForm.fromCode(party[index].form),
                        speciesCode: party[index].speciesCode,
                        speciesName: party[index].speciesName,
                        spritePose: PlantSpritePose.idle,
                        outfitKey: party[index].outfitKey,
                        width: 52,
                        height: 76,
                      ),
                    ),
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
    required this.area,
  });

  final List<ExpeditionNode> nodes;
  final List<List<String>> edges;
  final String currentCode;
  final Set<String> availableCodes;
  final Color activeColor;

  /// 걸을 수 있는 땅. 발자국도 캐릭터와 **같은 길**을 밟아야 한다.
  final ExpeditionWalkArea area;

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
      final route = expeditionWalkPath(
        area,
        expeditionStandPoint(area, Offset(left.x!, left.y!)),
        expeditionStandPoint(area, Offset(right.x!, right.y!)),
      );
      if (route.length < 2) continue;
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
      oldDelegate.activeColor != activeColor ||
      oldDelegate.area != area;
}

/// 손가락이 닿은 자리에 뜨는 가상 스틱.
///
/// 늘 떠 있지 않고 **끄는 동안만** 보인다. 지도가 좁아서 고정 스틱을 두면
/// 지형을 가리고, 한 손으로 쥐었을 때 엄지가 닿는 자리도 사람마다 다르다.
class _WalkStickPainter extends CustomPainter {
  const _WalkStickPainter({
    required this.center,
    required this.knob,
    required this.color,
  });

  final Offset center;
  final Offset knob;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: .42);
    canvas.drawCircle(center, expeditionStickRadius, ring);

    // 죽은 구역을 옅게 표시한다. 여기서는 움직이지 않는다는 것이 보인다.
    canvas.drawCircle(
      center,
      expeditionStickDeadZone,
      Paint()..color = color.withValues(alpha: .16),
    );

    canvas.drawCircle(
      knob,
      15,
      Paint()..color = color.withValues(alpha: .58),
    );
    canvas.drawCircle(
      knob,
      15,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFF4DC).withValues(alpha: .82),
    );
  }

  @override
  bool shouldRepaint(covariant _WalkStickPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.knob != knob ||
      oldDelegate.color != color;
}
