import 'package:flutter/material.dart';

/// 몽그루 BI에만 사용하는 기준 색입니다.
abstract final class MongrooBrandColors {
  static const sprout = Color(0xFFB9EE84);
  static const soil = Color(0xFF3B1F06);
  static const paper = Color(0xFFEFEFEF);
}

/// 확정한 입체 `m` 심볼을 앱 안에서 일관되게 표시합니다.
class MongrooBrandMark extends StatelessWidget {
  const MongrooBrandMark({
    super.key,
    this.size = 48,
    this.withPlate = false,
    this.semanticLabel = '몽그루, 오늘의 마음이 한 그루 자라나요',
  });

  static const assetPath = 'assets/brand/mongroo-symbol.webp';

  final double size;
  final bool withPlate;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      assetPath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );

    return Semantics(
      image: true,
      label: semanticLabel,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: withPlate
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: MongrooBrandColors.paper,
                    borderRadius: BorderRadius.circular(size * 0.24),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.08),
                    child: mark,
                  ),
                )
              : mark,
        ),
      ),
    );
  }
}
