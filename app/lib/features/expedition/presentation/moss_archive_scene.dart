import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const mossArchiveMapAsset = 'assets/adventure/expedition-moss-archive-map.webp';

/// 실시간 3D 엔진 없이 배경·안개·광점을 분리해 깊이를 만드는 탐험 무대다.
/// 지도 조작은 위 레이어에 그대로 남아 작은 기기와 웹에서도 가볍게 동작한다.
class MossArchiveScene extends StatefulWidget {
  const MossArchiveScene({
    super.key,
    required this.child,
    this.semanticLabel = '이끼와 오래된 서가가 이어진 기억서고 탐험길',
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final Widget child;
  final String semanticLabel;
  final BorderRadius borderRadius;

  @override
  State<MossArchiveScene> createState() => _MossArchiveSceneState();
}

class _MossArchiveSceneState extends State<MossArchiveScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient;
  bool _preloaded = false;

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
    if (!_preloaded) {
      _preloaded = true;
      precacheImage(const AssetImage(mossArchiveMapAsset), context);
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
                child: AnimatedBuilder(
                  animation: _ambient,
                  builder: (context, _) {
                    final drift = (_ambient.value - .5) * 5;
                    return Transform.translate(
                      offset: Offset(drift, -drift * .35),
                      child: Transform.scale(
                        scale: 1.025,
                        child: Image.asset(
                          mossArchiveMapAsset,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.medium,
                          excludeFromSemantics: true,
                          errorBuilder: (context, error, stackTrace) =>
                              ColoredBox(color: palette.night),
                        ),
                      ),
                    );
                  },
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
    Offset(.17, .38),
    Offset(.38, .25),
    Offset(.57, .67),
    Offset(.76, .34),
    Offset(.88, .57),
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
