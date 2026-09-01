part of 'expedition_screen.dart';

/// 무대 위에 겹치는 8점 진행 rail과 경로 오버레이.
///
/// 개편 설계서 3.6·5.2가 정한 것: `8점 지도는 삭제하지 않지만 필수 중간
/// 화면이 아닌 경로 오버레이다. 상단 progress rail을 탭하면 현재 무대 위에
/// 열리고, 닫으면 같은 카메라 위치로 돌아간다.`
///
/// 그래서 지도를 새 화면으로 밀어 올리지 않는다. push하면 걷던 장면이
/// 화면에서 내려가고, 돌아왔을 때 카메라도 걸음도 처음부터 다시 선다.
/// 불투명하지 않은 대화상자로 겹쳐야 아래의 무대와 그 상태가 그대로 남는다.

/// rail 점 하나의 지름. 8개가 320px에서도 한 줄에 남는 크기다.
const double _railDotSize = 13;

/// 경로 오버레이의 점 하나.
const double _routeDotSize = 44;

/// 상단 8점 진행 rail.
///
/// 지금 몇 번째 걸음인지만 말하고, 누르면 경로를 편다. 지역명은 옆의
/// 태그가 이미 말하므로 여기서 되풀이하지 않는다.
class _StageProgressRail extends ConsumerWidget {
  const _StageProgressRail({required this.stageNo});

  /// 지금 걷고 있는 스테이지 번호.
  final int stageNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stageMap = ref.watch(
      expeditionControllerProvider.select((state) => state.stageMap),
    );
    final stages = stageMap?.stages ?? const <ExpeditionStage>[];
    if (stageMap == null || stages.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final total = stages.length;
    final here = stageNo.clamp(1, total);
    return MongrooPressable(
      key: const ValueKey('stage-progress-rail'),
      borderRadius: BorderRadius.circular(999),
      semanticLabel:
          '${stageMap.region.shortName} $total걸음 중 $here번째. 눌러서 경로를 봐요.',
      onTap: () {
        HapticFeedback.selectionClick();
        _openStageRouteOverlay(context, stageNo: here);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final stage in stages) ...[
                    if (stage.no != stages.first.no)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: stage.no <= here
                              ? scheme.primary.withAlpha(150)
                              : scheme.outlineVariant.withAlpha(140),
                        ),
                      ),
                    _RailDot(stage: stage, here: stage.no == here),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 9),
            // 설계서 5.3의 `작은 고정폭 숫자 묶음`. 걸음이 넘어갈 때 숫자가
            // 흔들리지 않도록 자릿수 폭을 고정한다.
            Text(
              '$here/$total',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more_rounded,
              size: 17,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RailDot extends StatelessWidget {
  const _RailDot({required this.stage, required this.here});

  final ExpeditionStage stage;
  final bool here;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = here
        ? scheme.primary
        : stage.cleared
            ? scheme.primary.withAlpha(120)
            : scheme.surfaceContainerHighest;
    return Container(
      width: here ? _railDotSize + 4 : _railDotSize,
      height: here ? _railDotSize + 4 : _railDotSize,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: here
              ? scheme.onPrimaryContainer.withAlpha(190)
              : scheme.outlineVariant.withAlpha(stage.cleared ? 90 : 190),
          width: here ? 2 : 1,
        ),
      ),
      // 보스 자리만 rail에서도 표식을 남긴다. 여덟 걸음의 끝이 어디인지
      // 오버레이를 열지 않고도 보이게 하려는 것이다.
      child: stage.kind == ExpeditionStageKind.boss && !here
          ? Icon(
              Icons.pets_rounded,
              size: _railDotSize - 5,
              color: stage.cleared ? scheme.onPrimary : scheme.onSurfaceVariant,
            )
          : null,
    );
  }
}

/// 경로 오버레이를 현재 무대 위에 편다.
///
/// [showGeneralDialog]가 만드는 경로는 불투명하지 않아서, 아래에 깔린 탐험
/// 화면이 계속 그려지고 위젯 상태도 살아 있다. 닫았을 때 걷던 카메라가
/// 그대로 남는 것은 이 성질에 기댄 것이다.
Future<void> _openStageRouteOverlay(
  BuildContext context, {
  required int stageNo,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '경로 닫기',
    barrierColor: Colors.black.withAlpha(110),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _StageRouteOverlay(stageNo: stageNo),
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: MongrooMotion.enter,
      );
      return FadeTransition(
        opacity: curved,
        child: reduceMotion
            ? child
            : SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
      );
    },
  );
}

/// 무대 위에 겹치는 경로 — 8개의 점이 완만한 굽잇길로 이어진다.
///
/// 여기서 다른 스테이지로 출발할 수는 없다. 이미 한 걸음 안에 들어와 있고,
/// 이 오버레이는 설계서 5.2의 `진행 확인`용이다. 걷던 판을 버리게 만드는
/// 버튼을 지도 모양 위에 올려 두지 않는다.
class _StageRouteOverlay extends ConsumerWidget {
  const _StageRouteOverlay({required this.stageNo});

  final int stageNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stageMap = ref.watch(
      expeditionControllerProvider.select((state) => state.stageMap),
    );
    final stages = stageMap?.stages ?? const <ExpeditionStage>[];
    if (stageMap == null || stages.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final here = stageNo.clamp(1, stages.length);
    final leader = ref
        .watch(expeditionControllerProvider.select((state) => state.expedition))
        ?.party
        .firstOrNull;

    return Semantics(
      container: true,
      label: '${stageMap.region.name} 경로. ${stages.length}걸음 중 $here번째예요.',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                child: MongrooPanel(
                  key: const ValueKey('stage-route-overlay'),
                  // 판 자체는 불투명하게 둔다. 반투명으로 뒀더니 아래
                  // 이야기 글이 점과 겹쳐 읽혀 둘 다 못 읽었다. `무대 위`는
                  // 판 바깥으로 비치는 장면과 어두운 막이 이미 말한다.
                  color: palette.paper,
                  borderColor: scheme.primary.withAlpha(80),
                  radius: 22,
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${stageMap.region.shortName} 경로',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '${stages.length}걸음 중 $here번째 · 완주 '
                                  '${stageMap.clearedCount}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('stage-route-close'),
                            onPressed: () => Navigator.of(context).maybePop(),
                            tooltip: '경로 닫고 하던 곳으로',
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      AspectRatio(
                        aspectRatio: 1.85,
                        child: _RouteTrail(
                          stages: stages,
                          here: here,
                          leaderName: leader?.name,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '걷던 자리는 그대로예요. 닫으면 바로 이어서 걸어요.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
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

/// 여덟 점이 두 줄의 굽잇길로 이어진 경로.
class _RouteTrail extends StatelessWidget {
  const _RouteTrail({
    required this.stages,
    required this.here,
    this.leaderName,
  });

  final List<ExpeditionStage> stages;
  final int here;
  final String? leaderName;

  /// [index]번째 점이 놓이는 자리(0~1). 위 줄은 왼쪽에서, 아래 줄은
  /// 오른쪽에서 시작해 한 번 꺾이는 굽잇길이 된다.
  static Offset slotOf(int index, int total) {
    final perRow = (total / 2).ceil();
    final row = index ~/ perRow;
    final within = index % perRow;
    final column = row.isEven ? within : perRow - 1 - within;
    return Offset(
      (column + .5) / perRow,
      total <= perRow ? .5 : (row == 0 ? .3 : .72),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slots = [
      for (var index = 0; index < stages.length; index++)
        slotOf(index, stages.length),
    ];
    final hereIndex = stages.indexWhere((stage) => stage.no == here);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _RoutePathPainter(
              slots: slots,
              walked: hereIndex,
              walkedColor: scheme.primary.withAlpha(170),
              restColor: scheme.outlineVariant.withAlpha(170),
            ),
          ),
        ),
        for (var index = 0; index < stages.length; index++)
          Align(
            alignment: Alignment(
              slots[index].dx * 2 - 1,
              slots[index].dy * 2 - 1,
            ),
            child: _RouteStagePoint(
              stage: stages[index],
              here: stages[index].no == here,
            ),
          ),
        if (leaderName != null && hereIndex >= 0)
          Align(
            alignment: Alignment(
              slots[hereIndex].dx * 2 - 1,
              // 점 지름의 3분의 2쯤 위. 더 띄우면 판 머리에 붙어
              // 어느 점의 것인지 읽히지 않는다.
              slots[hereIndex].dy * 2 - 1 - .3,
            ),
            child: _RouteLeaderToken(name: leaderName!),
          ),
      ],
    );
  }
}

/// 지나온 길은 진하게, 남은 길은 흐리게 잇는다.
class _RoutePathPainter extends CustomPainter {
  const _RoutePathPainter({
    required this.slots,
    required this.walked,
    required this.walkedColor,
    required this.restColor,
  });

  final List<Offset> slots;

  /// 지금 서 있는 점의 차례. 여기까지가 지나온 길이다.
  final int walked;

  final Color walkedColor;
  final Color restColor;

  Path _through(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final middle = Offset.lerp(points[index], points[index + 1], .5)!;
      if (index == 0) {
        path.lineTo(middle.dx, middle.dy);
      } else {
        path.quadraticBezierTo(
          points[index].dx,
          points[index].dy,
          middle.dx,
          middle.dy,
        );
      }
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.length < 2) return;
    final pixels = [
      for (final slot in slots)
        Offset(slot.dx * size.width, slot.dy * size.height),
    ];
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_through(pixels), stroke..color = restColor);
    final done = walked.clamp(0, pixels.length - 1);
    if (done >= 1) {
      canvas.drawPath(
        _through(pixels.sublist(0, done + 1)),
        stroke..color = walkedColor,
      );
    }
  }

  @override
  bool shouldRepaint(_RoutePathPainter old) =>
      old.walked != walked ||
      old.slots != slots ||
      old.walkedColor != walkedColor ||
      old.restColor != restColor;
}

/// 경로 위의 점 하나 — 종류 glyph와 번호, 완주·미열람 표식.
class _RouteStagePoint extends StatelessWidget {
  const _RouteStagePoint({required this.stage, required this.here});

  final ExpeditionStage stage;
  final bool here;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = !stage.unlocked;
    final background = here
        ? scheme.primaryContainer
        : stage.cleared
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest;
    final foreground = here
        ? scheme.onPrimaryContainer
        : stage.cleared
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant;
    return Semantics(
      key: ValueKey('route-point-${stage.no}'),
      label: [
        stage.label,
        stage.kindLabel,
        if (stage.cleared) '완주',
        if (stage.hasUnreadStory) '이야기 미열람',
        if (here) '지금 여기',
        if (locked) stage.lockReason ?? '아직 잠김',
      ].join('. '),
      child: SizedBox(
        width: _routeDotSize + 10,
        height: _routeDotSize + 10,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: _routeDotSize,
              height: _routeDotSize,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: here
                      ? scheme.primary
                      : scheme.outlineVariant.withAlpha(200),
                  width: here ? 2.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    // 잠긴 점도 무엇인지는 보여 준다(5.2). 자물쇠로 덮으면
                    // 지도 화면과 다른 말을 하게 된다 — 거기서도 잠긴 점은
                    // 종류 아이콘을 그대로 쓰고 배지로만 잠김을 말한다.
                    _stageIcon(stage),
                    size: 15,
                    color: locked ? foreground.withAlpha(150) : foreground,
                  ),
                  Text(
                    '${stage.no}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: locked ? foreground.withAlpha(150) : foreground,
                          height: 1.05,
                        ),
                  ),
                ],
              ),
            ),
            // 완주와 잠김은 같이 오지 않으므로 같은 자리를 나눠 쓴다.
            if (stage.cleared)
              Align(
                alignment: Alignment.bottomRight,
                child: _RouteBadge(
                  icon: Icons.check_rounded,
                  background: scheme.primary,
                  foreground: scheme.onPrimary,
                ),
              )
            else if (locked)
              Align(
                alignment: Alignment.bottomRight,
                child: _RouteBadge(
                  icon: Icons.lock_rounded,
                  background: scheme.surfaceContainerHighest,
                  foreground: scheme.onSurfaceVariant,
                ),
              ),
            if (stage.hasUnreadStory)
              Align(
                alignment: Alignment.topRight,
                child: _RouteBadge(
                  icon: Icons.bookmark_rounded,
                  background: scheme.tertiary,
                  foreground: scheme.onTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  const _RouteBadge({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 11, color: foreground),
      );
}

/// 지금 서 있는 점 위에 서는 선두 캐릭터 토큰.
class _RouteLeaderToken extends StatelessWidget {
  const _RouteLeaderToken({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          name.characters.take(5).toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onInverseSurface,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
