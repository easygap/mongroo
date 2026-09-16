import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'expedition_pixel_art.dart';
import 'expedition_pixel_assets.g.dart';

/// 지역별 도트 전장 배경.
///
/// 세로 무대(폰)와 가로 무대(넓은 화면)가 다른 원화를 쓴다. 한 장을 비율에
/// 맞춰 늘이면 도트가 찌그러지고, 자르면 세로 무대에서 하늘만 남거나 가로
/// 무대에서 바닥만 남는다. 두 장을 그려 두는 편이 정직하다.
abstract final class ExpeditionPixelBackdrops {
  static const regions = <String>{
    'moss_archive',
    'echo_well',
    'starlight_seed_vault',
    'heartwood_observatory',
  };

  static String asset(String? regionCode, {required bool portrait}) {
    final region = regions.contains(regionCode) ? regionCode! : 'moss_archive';
    return 'assets/adventure/pixel/backdrops/$region-'
        '${portrait ? 'portrait' : 'landscape'}.png';
  }

  static Size nativeSize(String asset) =>
      expeditionPixelAssetSizes[asset] ?? const Size(192, 288);

  /// 지역 도트 배경 전부. 번들 테스트가 존재를 확인한다.
  static List<String> get all => [
        for (final region in regions)
          for (final portrait in const [true, false])
            asset(region, portrait: portrait),
      ];
}

/// 도트 배경 위에 전장을 얹는 틀.
///
/// [child]는 `Positioned.fill`을 쓰는 [ExpeditionEncounterStage]처럼 Stack
/// 안에서 자리를 잡는 위젯이어도 된다 — 여기가 그 Stack이다.
class PixelBattleBackdrop extends StatelessWidget {
  const PixelBattleBackdrop({
    super.key,
    required this.regionCode,
    required this.semanticLabel,
    required this.child,
    this.tint,
    this.borderRadius = BorderRadius.zero,
  });

  final String? regionCode;
  final String semanticLabel;
  final Widget child;

  /// 꿈 같은 특별한 전장에 얹는 색. 알파가 세기다. 없으면 원화 그대로.
  final Color? tint;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        image: true,
        label: semanticLabel,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stage = constraints.biggest;
              // 확실히 세로인 무대(폰)에서만 세로 원화를 쓴다. 넓은 화면의 무대는
              // 정사각형에 가까운데, 거기에 세로 원화를 아래 맞춤으로 덮으면
              // 위쪽 장면이 잘려 바닥만 남는다. 가로 원화는 양옆이 잘릴 뿐
              // 장면은 남는다.
              final portrait = stage.height >= stage.width * 1.2;
              final asset = ExpeditionPixelBackdrops.asset(
                regionCode,
                portrait: portrait,
              );
              final native = ExpeditionPixelBackdrops.nativeSize(asset);
              // 배경이 무대를 덮는 배율이 곧 무대의 배율이다. 캐릭터와 적도
              // 같은 값을 읽어 도트 한 칸의 크기를 맞춘다.
              final scale = math.max(
                2,
                ExpeditionPixelArt.scaleFor(stage, native),
              );
              return PixelStageScale(
                scale: scale,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: PixelCoverImage(
                          asset: asset,
                          imageKey: ValueKey('pixel-backdrop-$asset'),
                          native: native,
                          scale: scale,
                        ),
                      ),
                    ),
                    if (tint case final tint? when tint.a > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(color: tint),
                        ),
                      ),
                    child,
                  ],
                ),
              );
            },
          ),
        ),
      );
}
