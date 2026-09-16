import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// 탐험·전투 화면이 함께 쓰는 도트 표현의 기본 요소.
///
/// 규칙은 셋뿐이다.
///
/// 1. **화소는 정수 배율로만 키운다.** 배경·캐릭터·적·이펙트가 같은 배율을
///    써야 한 화면이 한 그림으로 읽힌다. 배율이 제각각이면 캐릭터만 큼직한
///    도트, 배경만 잔도트가 되어 오려 붙인 것처럼 보인다.
/// 2. **보간하지 않는다.** [FilterQuality.none]과 `isAntiAlias = false`로만
///    그린다. 흐려진 도트는 도트가 아니라 저해상도 그림이다.
/// 3. **UI도 같은 문법이다.** 둥근 모서리·그림자 번짐·유리 효과 대신 1~2화소
///    테두리와 한 칸 어긋난 그림자만 쓴다.
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

  /// 도트 글자. 숫자와 한두 단어짜리 게임 라벨에만 쓴다(MASTER.md).
  static TextStyle text(
    double size, {
    Color color = AppTheme.onNight,
    Color shadow = const Color(0xFF15100C),
    double shadowOffset = 2,
    FontWeight weight = FontWeight.w700,
  }) =>
      TextStyle(
        fontFamily: AppTheme.pixelFont,
        fontSize: size,
        height: 1.15,
        color: color,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
        shadows: [
          Shadow(color: shadow, offset: Offset(shadowOffset, shadowOffset)),
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
        final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
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

/// 도트 UI 판.
///
/// 둥근 카드 대신 쓰는 것. 바깥 1칸 어두운 선, 안쪽 1칸 밝은 선, 그리고
/// 오른쪽 아래로 한 칸 밀린 단단한 그림자. 네 귀퉁이는 한 칸씩 잘라 낸다 —
/// 도트 시대의 창이 그렇게 생겼고, 지금의 도트 게임들도 그 문법을 지킨다.
class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.unit = 2,
    this.fill = const Color(0xF2201913),
    this.border = const Color(0xFF0E0B08),
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
    final u = unit;
    final body = Rect.fromLTWH(0, 0, size.width - u, size.height - u);
    Path frame(Rect r, double cut) {
      if (!chamfer || cut <= 0) return Path()..addRect(r);
      return Path()
        ..moveTo(r.left + cut, r.top)
        ..lineTo(r.right - cut, r.top)
        ..lineTo(r.right, r.top + cut)
        ..lineTo(r.right, r.bottom - cut)
        ..lineTo(r.right - cut, r.bottom)
        ..lineTo(r.left + cut, r.bottom)
        ..lineTo(r.left, r.bottom - cut)
        ..lineTo(r.left, r.top + cut)
        ..close();
    }

    final flat = Paint()..isAntiAlias = false;
    // 그림자: 한 칸 오른쪽 아래.
    canvas.drawPath(
      frame(body.shift(Offset(u, u)), u),
      flat..color = shadow,
    );
    // 테두리.
    canvas.drawPath(frame(body, u), flat..color = border);
    // 안쪽 면.
    final inner = body.deflate(u);
    canvas.drawPath(frame(inner, u), flat..color = fill);
    // 위·왼쪽 밝은 선. 유리 광택이 아니라 판의 두께를 말하는 선이다.
    canvas.drawRect(
      Rect.fromLTWH(inner.left + u, inner.top, inner.width - u * 2, u),
      flat..color = highlight,
    );
    canvas.drawRect(
      Rect.fromLTWH(inner.left, inner.top + u, u, inner.height - u * 2),
      flat..color = highlight,
    );
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

/// 도트 게이지. 체력·장벽·집중력이 같은 모양을 쓴다.
///
/// 채워진 만큼을 칸 단위로 끊고, 25%마다 눈금을 판다. 값이 색으로만
/// 말하지 않게 호출부가 숫자를 옆에 둔다.
class PixelBar extends StatelessWidget {
  const PixelBar({
    super.key,
    required this.value,
    this.unit = 2,
    this.height = 8,
    this.color = const Color(0xFF7ED67C),
    this.lowColor = const Color(0xFFF08A6B),
    this.lowThreshold = .35,
    this.track = const Color(0xFF2A211A),
    this.border = const Color(0xFF0E0B08),
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
