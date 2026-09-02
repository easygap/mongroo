import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 아직 만나지 못한 것을 흑백으로 눕히는 필터.
///
/// `ColorFilter.mode(..., BlendMode.saturation)`은 자식의 **사각 경계 전체**에
/// 색을 올려서, 투명한 여백까지 회색 판으로 칠해 버린다. 도감 카드처럼 칸을
/// 꽉 채우면 그 판이 그대로 보인다. 채도 행렬은 알파를 그대로 두므로 그림만
/// 흑백이 된다.
const ColorFilter kMongrooGreyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

class MongrooPanel extends StatelessWidget {
  const MongrooPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.radius = 16,
    this.shadowOffset = const Offset(0, 4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? palette.paper,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? scheme.outlineVariant.withAlpha(210),
        ),
        boxShadow: shadowOffset == Offset.zero
            ? null
            : [
                BoxShadow(
                  color: palette.night.withAlpha(18),
                  offset: shadowOffset,
                  blurRadius: 14,
                  spreadRadius: -4,
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class MongrooTag extends StatelessWidget {
  const MongrooTag({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.backgroundColor,
    this.foregroundColor,
    this.maxWidth,
  });

  final String label;
  final IconData? icon;

  /// 글자 앞에 그릴 것. 주면 `icon` 대신 이걸 쓴다.
  ///
  /// 성장결처럼 **글리프가 아니라 그린 마크**를 앞에 둬야 하는 자리가 있다.
  /// 예전에는 여섯 성장결이 `Icons.hub_outlined` 하나를 나눠 써서, 색과 글자를
  /// 못 읽으면 구분이 되지 않았다.
  final Widget? leading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final background = backgroundColor ?? palette.paperDeep;
    final foreground = foregroundColor ??
        _contrastingForeground(
          background,
          dark: palette.night,
          light: AppTheme.onNight,
        );
    Widget buildTag(double? resolvedMaxWidth) {
      final labelText = Text(
        label,
        maxLines: 1,
        // 항상 말줄임이다. 예전에는 `maxWidth`를 준 태그만 줄였는데, 폭을
        // 안 준 태그는 글자가 커지면 줄지 못하고 부모를 넘겼다.
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      );
      final constrainedLabel = resolvedMaxWidth == null
          ? labelText
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    (resolvedMaxWidth - 16 - (icon == null && leading == null ? 0 : 19))
                    .clamp(
                  24,
                  double.infinity,
                ),
              ),
              child: labelText,
            );
      return DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withAlpha(35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 5),
              ] else if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 5),
              ],
              // 받은 폭 안에서 줄어든다. `maxWidth`를 안 넘긴 태그는 글자가
              // 커질 때 제 자연 크기를 고집하다 320px·200%에서 부모 Row를
              // 30px 넘겼다 - 기록 상세의 `읽힌 감정` 태그가 그랬다.
              // Flexible이면 남은 자리에 맞춰 말줄임으로 접힌다.
              Flexible(child: constrainedLabel),
            ],
          ),
        ),
      );
    }

    if (maxWidth == null) return buildTag(null);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: LayoutBuilder(
        builder: (context, constraints) => buildTag(
          constraints.hasBoundedWidth
              ? constraints.maxWidth.clamp(40, maxWidth!)
              : maxWidth,
        ),
      ),
    );
  }
}

Color _contrastingForeground(
  Color background, {
  required Color dark,
  required Color light,
}) {
  final backgroundLuminance = background.computeLuminance();

  double contrast(Color candidate) {
    final candidateLuminance = candidate.computeLuminance();
    final lighter = backgroundLuminance > candidateLuminance
        ? backgroundLuminance
        : candidateLuminance;
    final darker = backgroundLuminance < candidateLuminance
        ? backgroundLuminance
        : candidateLuminance;
    return (lighter + .05) / (darker + .05);
  }

  return contrast(dark) >= contrast(light) ? dark : light;
}

class MongrooPressable extends StatefulWidget {
  const MongrooPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;
  final BorderRadius borderRadius;

  @override
  State<MongrooPressable> createState() => _MongrooPressableState();
}

class _MongrooPressableState extends State<MongrooPressable> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final content = AnimatedScale(
      scale: _pressed && !reduceMotion ? .985 : 1,
      duration: MongrooMotion.quick,
      curve: MongrooMotion.enter,
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (pressed) {
            if (_pressed != pressed) setState(() => _pressed = pressed);
          },
          child: widget.child,
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.semanticLabel,
      onTap: widget.semanticLabel == null ? null : widget.onTap,
      child: widget.semanticLabel == null
          ? content
          : ExcludeSemantics(child: content),
    );
  }
}


/// 보유 씨앗을 보여 주는 공용 배지.
///
/// 씨앗은 앱의 유일한 재화인데 홈은 잎사귀 도트 칩, 정원·상점은 동전
/// 아이콘의 분홍 배지를 써서 같은 값이 다른 물건처럼 보였다. 화폐 표기는
/// 한 곳에서만 만든다.
class MongrooSeedToken extends StatelessWidget {
  const MongrooSeedToken({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Semantics(
      label: '보유 씨앗 $value개',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.night,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.eco_rounded, size: 16, color: palette.butter),
              const SizedBox(width: 4),
              ExcludeSemantics(
                child: Text(
                  '$value',
                  style: const TextStyle(
                    color: AppTheme.onNight,
                    fontFamily: AppTheme.pixelFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
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
