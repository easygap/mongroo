import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Sprite sampling remains discrete; interface typography and panels use the app design system.
abstract final class ExpeditionPixelArt {
  /// 화면 크기와 원화 native 크기로 정수 배율을 정한다.
  ///
  /// 원화가 무대를 **덮는** 가장 작은 정수다. 폰 세로 무대(390×600)에
  /// 160×240 원화면 3배, 넓은 화면에 320×200 원화면 3~4배가 된다.
  static int scaleFor(Size stage, Size native) {
    if (native.width <= 0 || native.height <= 0) return 3;
    final needed = math.max(
      stage.width / native.width,
      stage.height / native.height,
    );
    return needed.ceil().clamp(2, 6);
  }

  /// Compact, readable game labels; no decorative text shadow by default.
  static TextStyle text(
    double size, {
    Color color = AppTheme.onNight,
    Color shadow = const Color(0xFF15100C),
    double shadowOffset = 0,
    FontWeight weight = FontWeight.w700,
  }) =>
      TextStyle(
        fontFamily: AppTheme.bodyFont,
        fontSize: size,
        height: 1.15,
        color: color,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
        shadows: shadowOffset == 0
            ? null
            : [
                Shadow(
                    color: shadow, offset: Offset(shadowOffset, shadowOffset)),
              ],
      );
}

/// 무대의 도트 배율을 아래 위젯들에 알린다.
///
/// 배경이 무대를 덮는 배율을 정하면, 그 위에 서는 캐릭터·적·HUD가 같은 값을
/// 읽어 한 그림처럼 맞춘다. 없으면 폰 기준값 2다.
class PixelStageScale extends InheritedWidget {
  const PixelStageScale({
    super.key,
    required this.scale,
    required super.child,
  });

  final int scale;

  static int of(BuildContext context, {int fallback = 2}) =>
      context.dependOnInheritedWidgetOfExactType<PixelStageScale>()?.scale ??
      fallback;

  @override
  bool updateShouldNotify(covariant PixelStageScale oldWidget) =>
      oldWidget.scale != scale;
}

/// 도트 원화를 메모리에 올려 두는 캐시.
///
/// 시트에서 한 칸만 잘라 그리려면 [ui.Image]가 필요하다. 같은 시트를 화면마다
/// 다시 디코드하지 않도록 경로별로 한 번만 든다.
abstract final class ExpeditionPixelImages {
  static final Map<String, Future<ui.Image?>> _pending = {};
  static final Map<String, ui.Image> _ready = {};

  static ui.Image? ready(String asset) => _ready[asset];

  static Future<ui.Image?> load(String asset) {
    final cached = _ready[asset];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(asset, () async {
      try {
        final bytes = await rootBundle.load(asset);
        final codec =
            await ui.instantiateImageCodec(bytes.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        codec.dispose();
        _ready[asset] = frame.image;
        return frame.image;
      } catch (_) {
        // 번들에 없는 품종 시트 같은 것. 호출부가 폴백을 고른다.
        return null;
      }
    });
  }

  @visibleForTesting
  static void reset() {
    _pending.clear();
    for (final image in _ready.values) {
      image.dispose();
    }
    _ready.clear();
  }
}

/// 도트 시트의 한 칸을 정수 배율로 그린다.
///
/// [source]가 시트 안의 칸이고, 칸의 발밑선이 [Rect]의 아래 가운데에 닿는다.
class PixelSheetCell extends StatefulWidget {
  const PixelSheetCell({
    super.key,
    required this.asset,
    required this.source,
    required this.scale,
    this.flipX = false,
    this.flash = 0,
    this.opacity = 1,
    this.alignment = Alignment.bottomCenter,
    this.placeholder,
  });

  final String asset;
  final Rect source;

  /// 원화 한 화소가 차지할 논리 픽셀 수. 시트가 이미 4배 도트라면 `.75`처럼
  /// 소수도 되지만, 그때도 결과 화소가 정수가 되게 호출부가 맞춘다.
  final double scale;
  final bool flipX;

  /// 0~1. 맞는 순간 하얗게 번쩍이는 정도.
  final double flash;
  final double opacity;
  final Alignment alignment;

  /// 시트를 아직 못 읽었을 때 그릴 것. 없으면 빈 자리다.
  final Widget? placeholder;

  @override
  State<PixelSheetCell> createState() => _PixelSheetCellState();
}

class _PixelSheetCellState extends State<PixelSheetCell> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PixelSheetCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _image = ExpeditionPixelImages.ready(widget.asset);
      _load();
    }
  }

  void _load() {
    final ready = ExpeditionPixelImages.ready(widget.asset);
    if (ready != null) {
      _image = ready;
      return;
    }
    unawaited(
      ExpeditionPixelImages.load(widget.asset).then((image) {
        if (!mounted || image == null) return;
        setState(() => _image = image);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return widget.placeholder ?? const SizedBox.shrink();
    return CustomPaint(
      painter: _PixelSheetCellPainter(
        image: image,
        source: widget.source,
        scale: widget.scale,
        flipX: widget.flipX,
        flash: widget.flash,
        opacity: widget.opacity,
        alignment: widget.alignment,
      ),
    );
  }
}

class _PixelSheetCellPainter extends CustomPainter {
  const _PixelSheetCellPainter({
    required this.image,
    required this.source,
    required this.scale,
    required this.flipX,
    required this.flash,
    required this.opacity,
    required this.alignment,
  });

  final ui.Image image;
  final Rect source;
  final double scale;
  final bool flipX;
  final double flash;
  final double opacity;
  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    final width = (source.width * scale).roundToDouble();
    final height = (source.height * scale).roundToDouble();
    final left = ((size.width - width) * (alignment.x + 1) / 2).roundToDouble();
    final top =
        ((size.height - height) * (alignment.y + 1) / 2).roundToDouble();
    final target = Rect.fromLTWH(left, top, width, height);
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    canvas.save();
    if (flipX) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(image, source, target, paint);
    if (flash > 0) {
      // 몸의 모양대로만 하얗게. 사각형째 번쩍이면 종이가 씌워진 것처럼 보인다.
      canvas.saveLayer(target, Paint());
      canvas.drawImageRect(image, source, target, paint);
      canvas.drawRect(
        target,
        Paint()
          ..color = Colors.white.withValues(alpha: flash.clamp(0.0, 1.0))
          ..blendMode = BlendMode.srcATop,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PixelSheetCellPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.source != source ||
      oldDelegate.scale != scale ||
      oldDelegate.flipX != flipX ||
      oldDelegate.flash != flash ||
      oldDelegate.opacity != opacity ||
      oldDelegate.alignment != alignment;
}

/// Shared game panel. Legacy parameters remain compatible with existing screens.
class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.unit = 2,
    this.fill = const Color(0xFF202530),
    this.border = const Color(0xFF202530),
    this.highlight = const Color(0x40FFFFFF),
    this.shadow = const Color(0x8A000000),
    this.padding = const EdgeInsets.fromLTRB(8, 6, 8, 6),
    this.chamfer = true,
  });

  final Widget child;

  /// 한 칸의 논리 픽셀 수. 무대의 도트 배율과 맞춘다.
  final double unit;
  final Color fill;
  final Color border;
  final Color highlight;
  final Color shadow;
  final EdgeInsetsGeometry padding;
  final bool chamfer;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: PixelPanelPainter(
          unit: unit,
          fill: fill,
          border: border,
          highlight: highlight,
          shadow: shadow,
          chamfer: chamfer,
        ),
        child: Padding(
          padding: padding.add(EdgeInsets.all(unit * 2)),
          child: child,
        ),
      );
}

class PixelPanelPainter extends CustomPainter {
  const PixelPanelPainter({
    required this.unit,
    required this.fill,
    required this.border,
    required this.highlight,
    required this.shadow,
    this.chamfer = true,
  });

  final double unit;
  final Color fill;
  final Color border;
  final Color highlight;
  final Color shadow;
  final bool chamfer;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(.75), const Radius.circular(8));
    canvas.drawRRect(body, Paint()..color = fill);
    canvas.drawRRect(
        body,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant PixelPanelPainter oldDelegate) =>
      oldDelegate.unit != unit ||
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.highlight != highlight ||
      oldDelegate.shadow != shadow ||
      oldDelegate.chamfer != chamfer;
}

/// 도트 게이지. 체력·장벽·기력이 같은 모양을 쓴다.
///
/// 채워진 만큼을 칸 단위로 끊고, 25%마다 눈금을 판다. 값이 색으로만
/// 말하지 않게 호출부가 숫자를 옆에 둔다.
class PixelBar extends StatelessWidget {
  const PixelBar({
    super.key,
    required this.value,
    this.unit = 2,
    this.height = 8,
    this.color = const Color(0xFFA7BCFF),
    this.lowColor = const Color(0xFFFF91A6),
    this.lowThreshold = .35,
    this.track = const Color(0xFF303744),
    this.border = const Color(0xFF101216),
    this.ticks = 4,
  });

  final double value;
  final double unit;
  final double height;
  final Color color;
  final Color lowColor;
  final double lowThreshold;
  final Color track;
  final Color border;
  final int ticks;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: CustomPaint(
          painter: _PixelBarPainter(
            value: value.clamp(0.0, 1.0),
            unit: unit,
            color: value <= lowThreshold ? lowColor : color,
            track: track,
            border: border,
            ticks: ticks,
          ),
        ),
      );
}

class _PixelBarPainter extends CustomPainter {
  const _PixelBarPainter({
    required this.value,
    required this.unit,
    required this.color,
    required this.track,
    required this.border,
    required this.ticks,
  });

  final double value;
  final double unit;
  final Color color;
  final Color track;
  final Color border;
  final int ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final flat = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, flat..color = border);
    final inner = Rect.fromLTWH(
      unit,
      unit,
      size.width - unit * 2,
      size.height - unit * 2,
    );
    canvas.drawRect(inner, flat..color = track);
    // 채움은 칸 단위로 끊는다. 소수점 폭은 도트가 아니다.
    final filled = (inner.width * value / unit).round() * unit;
    if (filled > 0) {
      canvas.drawRect(
        Rect.fromLTWH(inner.left, inner.top, filled, inner.height),
        flat..color = color,
      );
      // 위쪽 한 줄은 밝게 — 게이지가 튜브가 아니라 판이라는 뜻.
      canvas.drawRect(
        Rect.fromLTWH(inner.left, inner.top, filled, unit),
        flat..color = Colors.white.withValues(alpha: .28),
      );
    }
    for (var tick = 1; tick < ticks; tick++) {
      final x = inner.left + (inner.width * tick / ticks / unit).round() * unit;
      canvas.drawRect(
        Rect.fromLTWH(x - unit, inner.top, unit, inner.height),
        flat..color = border.withValues(alpha: .55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PixelBarPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.unit != unit ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.border != border ||
      oldDelegate.ticks != ticks;
}

/// 정수 배율로 덮는 도트 그림.
///
/// [BoxFit.cover]는 비율을 맞추느라 소수 배율을 만든다. 여기서는 배율을
/// 정수로 올림한 뒤 넘치는 부분을 [alignment]에 맞춰 자른다. 아래를 맞추면
/// 바닥선이 늘 같은 자리에 있어 그 위에 선 배우가 뜨지 않는다.
class PixelCoverImage extends StatelessWidget {
  const PixelCoverImage({
    super.key,
    required this.asset,
    required this.native,
    this.alignment = Alignment.bottomCenter,
    this.minScale = 2,
    this.scale,
    this.imageKey,
    this.errorColor = const Color(0xFF15110E),
  });

  final String asset;
  final Size native;
  final Alignment alignment;
  final int minScale;

  /// 배율을 밖에서 정해 주면 그대로 쓴다. 없으면 무대를 덮는 배율을 고른다.
  final int? scale;
  final Key? imageKey;
  final Color errorColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final stage = constraints.biggest;
          final scale = this.scale ??
              math.max(
                minScale,
                ExpeditionPixelArt.scaleFor(stage, native),
              );
          final width = native.width * scale;
          final height = native.height * scale;
          return ClipRect(
            child: OverflowBox(
              alignment: alignment,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox(
                width: width,
                height: height,
                child: Image.asset(
                  asset,
                  key: imageKey,
                  width: width,
                  height: height,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                  isAntiAlias: false,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stackTrace) =>
                      ColoredBox(color: errorColor),
                ),
              ),
            ),
          );
        },
      );
}

/// 화소 단위로 흩어지는 조각들.
///
/// 엉킴이 풀려 제자리로 돌아갈 때 몸이 작은 네모들로 갈라져 흩날린다.
/// 파티클 텍스처 없이 네모만으로 그린다 — 도트 세계에서 조각은 네모다.
class PixelScatterPainter extends CustomPainter {
  PixelScatterPainter({
    required this.progress,
    required this.origin,
    required this.color,
    required this.unit,
    this.count = 14,
    this.seed = 7,
  });

  /// 0~1. 시작이 0, 다 흩어진 것이 1.
  final double progress;
  final Offset origin;
  final Color color;
  final double unit;
  final int count;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final random = math.Random(seed);
    final flat = Paint()..isAntiAlias = false;
    for (var index = 0; index < count; index++) {
      final angle = random.nextDouble() * math.pi * 2;
      final speed = 18 + random.nextDouble() * 34;
      final gravity = 28 * progress * progress;
      final dx = math.cos(angle) * speed * progress;
      final dy = math.sin(angle) * speed * progress * .55 + gravity;
      final side = unit * (1 + random.nextInt(2));
      final alpha = (1 - progress).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(
          ((origin.dx + dx) / unit).round() * unit,
          ((origin.dy + dy) / unit).round() * unit,
          side,
          side,
        ),
        flat..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PixelScatterPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.origin != origin ||
      oldDelegate.color != color ||
      oldDelegate.unit != unit;
}
