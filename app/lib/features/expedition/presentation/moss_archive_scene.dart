import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'expedition_scene.dart';

const mossArchiveMapAsset =
    'assets/adventure/expedition-moss-archive-terrain-v3.webp';

/// 통합 지형 원화에 실제로 그려진 길의 중심선이다.
/// 캐릭터 이동과 발자국이 같은 좌표를 써서 수풀이나 건물을 가로지르지 않게 한다.
const _mossArchiveRoutes = <String, List<Offset>>{
  'entrance>wet_labels': [
    Offset(.08, .50),
    Offset(.14, .48),
    Offset(.19, .42),
    Offset(.24, .34),
    Offset(.28, .27),
  ],
  'entrance>root_catalogue': [
    Offset(.08, .50),
    Offset(.14, .55),
    Offset(.20, .63),
    Offset(.29, .72),
  ],
  'wet_labels>quiet_camp': [
    Offset(.28, .27),
    Offset(.34, .32),
    Offset(.41, .30),
    Offset(.46, .23),
    Offset(.49, .19),
  ],
  'root_catalogue>pressed_gallery': [
    Offset(.29, .72),
    Offset(.35, .73),
    Offset(.42, .78),
    Offset(.50, .81),
  ],
  'quiet_camp>ledger_keeper': [
    Offset(.49, .19),
    Offset(.54, .27),
    Offset(.59, .34),
    Offset(.64, .43),
    Offset(.69, .50),
  ],
  'pressed_gallery>ledger_keeper': [
    Offset(.50, .81),
    Offset(.55, .73),
    Offset(.59, .64),
    Offset(.64, .56),
    Offset(.69, .50),
  ],
  'ledger_keeper>memory_drawer': [
    Offset(.69, .50),
    Offset(.74, .46),
    Offset(.79, .40),
    Offset(.84, .34),
  ],
  'memory_drawer>exit': [
    Offset(.84, .34),
    Offset(.86, .42),
    Offset(.89, .51),
    Offset(.91, .60),
    Offset(.93, .67),
  ],
  'wet_labels>pressed_gallery': [
    Offset(.28, .27),
    Offset(.35, .38),
    Offset(.42, .49),
    Offset(.47, .64),
    Offset(.50, .81),
  ],
  'root_catalogue>quiet_camp': [
    Offset(.29, .72),
    Offset(.35, .62),
    Offset(.42, .48),
    Offset(.47, .33),
    Offset(.49, .19),
  ],
  'quiet_camp>pressed_gallery': [
    Offset(.49, .19),
    Offset(.45, .34),
    Offset(.44, .50),
    Offset(.46, .66),
    Offset(.50, .81),
  ],
};

List<Offset> mossArchiveRouteBetween(
  String from,
  String to, {
  required Offset fallbackFrom,
  required Offset fallbackTo,
}) {
  final direct = _mossArchiveRoutes['$from>$to'];
  if (direct != null) return direct;
  final reverse = _mossArchiveRoutes['$to>$from'];
  if (reverse != null) return reverse.reversed.toList(growable: false);
  return [fallbackFrom, fallbackTo];
}

Offset mossArchiveRoutePosition(List<Offset> route, double progress) {
  if (route.isEmpty) return Offset.zero;
  if (route.length == 1) return route.first;
  if (progress <= 0) return route.first;
  if (progress >= 1) return route.last;
  final lengths = <double>[];
  var total = 0.0;
  for (var index = 1; index < route.length; index++) {
    final length = (route[index] - route[index - 1]).distance;
    lengths.add(length);
    total += length;
  }
  if (total == 0) return route.last;
  var remaining = progress.clamp(0.0, 1.0) * total;
  for (var index = 0; index < lengths.length; index++) {
    if (remaining <= lengths[index]) {
      return Offset.lerp(
            route[index],
            route[index + 1],
            remaining / lengths[index],
          ) ??
          route[index + 1];
    }
    remaining -= lengths[index];
  }
  return route.last;
}

/// 실시간 3D 엔진 없이 배경·안개·광점을 분리해 깊이를 만드는 탐험 무대다.
/// 지형과 상호작용 좌표가 어긋나지 않도록 배경 자체에는 이동 변환을 주지 않는다.
class MossArchiveScene extends StatefulWidget {
  const MossArchiveScene({
    super.key,
    required this.child,
    this.semanticLabel = '이끼와 오래된 서가가 이어진 기억서고 탐험길',
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.fit = BoxFit.cover,
  });

  final Widget child;
  final String semanticLabel;
  final BorderRadius borderRadius;
  final BoxFit fit;

  @override
  State<MossArchiveScene> createState() => _MossArchiveSceneState();
}

class _MossArchiveSceneState extends State<MossArchiveScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient;
  String? _precacheSignature;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cacheWidth = expeditionSceneDecodeWidth(context);
    final signature = '$mossArchiveMapAsset@$cacheWidth';
    if (_precacheSignature != signature) {
      _precacheSignature = signature;
      precacheImage(
        expeditionSceneImageProvider(context, mossArchiveMapAsset),
        context,
      ).ignore();
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _ambient
        ..stop()
        ..value = .35;
    } else if (!_ambient.isAnimating) {
      _ambient.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Semantics(
      container: true,
      image: true,
      label: widget.semanticLabel,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: Image(
                  image: expeditionSceneImageProvider(
                    context,
                    mossArchiveMapAsset,
                  ),
                  fit: widget.fit,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stackTrace) =>
                      ColoredBox(color: palette.night),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          palette.night.withAlpha(34),
                          palette.night.withAlpha(8),
                          palette.night.withAlpha(112),
                        ],
                        stops: const [0, .52, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _ambient,
                    builder: (context, _) => CustomPaint(
                      painter: _ArchiveLightPainter(
                        phase: _ambient.value,
                        light: palette.butter,
                      ),
                    ),
                  ),
                ),
              ),
              widget.child,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withAlpha(26)),
                      borderRadius: widget.borderRadius,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchiveLightPainter extends CustomPainter {
  const _ArchiveLightPainter({required this.phase, required this.light});

  final double phase;
  final Color light;

  static const _points = [
    Offset(.08, .50),
    Offset(.28, .27),
    Offset(.49, .19),
    Offset(.69, .50),
    Offset(.84, .34),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < _points.length; index++) {
      final point = _points[index];
      final wave = math.sin((phase * math.pi * 2) + index * 1.37);
      final center = Offset(
        point.dx * size.width + wave * 3,
        point.dy * size.height + math.cos(index + phase * math.pi) * 2,
      );
      final radius = 1.5 + (wave + 1) * .65;
      canvas.drawCircle(
        center,
        radius * 3.2,
        Paint()
          ..color = light.withAlpha(18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = light.withAlpha(135),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArchiveLightPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.light != light;
}
