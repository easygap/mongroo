import 'package:flutter/material.dart';

import '../../../core/branding/mongroo_brand.dart';
import '../../../core/theme/app_theme.dart';
import 'auth_scene.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    const foreground = MongrooBrandColors.soil;
    return Scaffold(
      // Web·Android의 native launch frame과 같은 색으로 첫 frame flash를 막습니다.
      backgroundColor: MongrooBrandColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Semantics(
                container: true,
                liveRegion: true,
                label: '몽그루를 시작하는 중입니다',
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const MongrooPocketMark(size: 156),
                      const SizedBox(height: 26),
                      Text(
                        '몽그루',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  color: foreground,
                                  fontFamily: AppTheme.pixelFont,
                                  letterSpacing: 0,
                                ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '마음을 기록하고 식물을 키워요.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: foreground.withAlpha(205),
                            ),
                      ),
                      const SizedBox(height: 28),
                      _PixelLoadingStatus(
                        foreground: foreground,
                        coral: palette.coral,
                        butter: palette.butter,
                        leaf: palette.leaf,
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

class _PixelLoadingStatus extends StatelessWidget {
  const _PixelLoadingStatus({
    required this.foreground,
    required this.coral,
    required this.butter,
    required this.leaf,
  });

  final Color foreground;
  final Color coral;
  final Color butter;
  final Color leaf;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 7, height: 7, color: coral),
              const SizedBox(width: 6),
              Container(width: 7, height: 7, color: butter),
              const SizedBox(width: 6),
              Container(width: 7, height: 7, color: leaf),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '불러오는 중…',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontFamily: AppTheme.pixelFont,
                ),
          ),
        ],
      );
}
