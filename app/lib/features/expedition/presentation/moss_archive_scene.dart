import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'expedition_scene.dart';

/// 실시간 3D 엔진 없이 배경·안개·광점을 분리해 깊이를 만드는 탐험 무대다.
/// 지형과 상호작용 좌표가 어긋나지 않도록 배경 자체에는 이동 변환을 주지 않는다.
class MossArchiveScene extends StatefulWidget {
  const MossArchiveScene({
    super.key,
    required this.child,
    this.semanticLabel = '이끼와 오래된 서가가 이어진 기억서고 탐험길',
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.fit = BoxFit.cover,
    this.regionCode,
  });

  final Widget child;
  final String semanticLabel;
  final BorderRadius borderRadius;
  final BoxFit fit;

  /// 어느 지역의 지형인지.
  ///
  /// 지형 원화는 아직 기억서고 것 하나뿐이라 **네 지역이 같은 그림을 쓴다.**
  /// 지역 전용 지형이 들어오기 전까지는 장면 배경과 같은 방식으로 색을 갈라
  /// 둔다 — 우물정원과 보관고 지도가 완전히 같은 그림으로 보이는 것보다는 낫다.
  final String? regionCode;

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
    final signature = '$expeditionTerrainAsset(widget.regionCode)@$cacheWidth';
    if (_precacheSignature != signature) {
      _precacheSignature = signature;
      precacheImage(
        expeditionSceneImageProvider(
          context,
          expeditionTerrainAsset(widget.regionCode),
        ),
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
                    expeditionTerrainAsset(widget.regionCode),
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
              // 지역 색 보정. 지형 그림 위, 노드·토큰 아래다 — 노드와 캐릭터가
              // 함께 물들면 지도에서 읽기 어려워진다.
              if (expeditionRegionGrade(widget.regionCode).a > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: expeditionRegionGrade(widget.regionCode),
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
