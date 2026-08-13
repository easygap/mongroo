import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const expeditionDungeonGateAsset =
    'assets/adventure/expedition-dungeon-gate-v3.webp';
const expeditionFloodedCaveAsset =
    'assets/adventure/expedition-flooded-cave-v3.webp';
const expeditionRootTunnelAsset =
    'assets/adventure/expedition-root-tunnel-v3.webp';
const expeditionMonsterDenAsset =
    'assets/adventure/expedition-monster-den-v3.webp';
const expeditionMonsterDenBattleAsset =
    'assets/adventure/expedition-monster-den-battle-v1.webp';
const expeditionLedgerKeeperIdleAsset =
    'assets/adventure/ledger-keeper-idle-v1.webp';
const expeditionLedgerKeeperAttackAsset =
    'assets/adventure/ledger-keeper-attack-v1.webp';
const expeditionLedgerKeeperHitAsset =
    'assets/adventure/ledger-keeper-hit-v1.webp';
const expeditionLedgerKeeperDefeatedAsset =
    'assets/adventure/ledger-keeper-defeated-v1.webp';
const expeditionTreasureVaultAsset =
    'assets/adventure/expedition-treasure-vault-v3.webp';
const expeditionMoonTowerAsset =
    'assets/adventure/expedition-moon-tower-v3.webp';
const expeditionEchoWellAsset = 'assets/adventure/expedition-echo-well-v3.webp';

const expeditionEnvironmentAssets = <String>{
  expeditionDungeonGateAsset,
  expeditionFloodedCaveAsset,
  expeditionRootTunnelAsset,
  expeditionMonsterDenAsset,
  expeditionMonsterDenBattleAsset,
  expeditionTreasureVaultAsset,
  expeditionMoonTowerAsset,
  expeditionEchoWellAsset,
};

const expeditionCombatAssets = <String>{
  expeditionLedgerKeeperIdleAsset,
  expeditionLedgerKeeperAttackAsset,
  expeditionLedgerKeeperHitAsset,
  expeditionLedgerKeeperDefeatedAsset,
};

const expeditionTangleCodes = <String>{
  'tangled_ledger',
  'drifting_pressings',
  'shelf_snarl',
};

const expeditionTangleStates = <String>{
  'idle',
  'attack',
  'hit',
  'release',
};

String expeditionTangleAssetPath(String code, String state) {
  final safeCode = expeditionTangleCodes.contains(code)
      ? code.replaceAll('_', '-')
      : 'tangled-ledger';
  final safeState = expeditionTangleStates.contains(state) ? state : 'idle';
  return 'assets/adventure/tangles/tangle-$safeCode-$safeState-v1.webp';
}

final expeditionTangleCombatAssets = <String>{
  for (final code in expeditionTangleCodes)
    for (final state in expeditionTangleStates)
      expeditionTangleAssetPath(code, state),
};

const expeditionMobileSceneWidth = 960;
const expeditionMobileGuardianWidth = 768;
const expeditionMobileTangleWidth = 576;

const expeditionSceneKeys = <String>{
  'dungeon_gate',
  'flooded_cave',
  'root_tunnel',
  'echo_well',
  'treasure_vault',
  'monster_den',
  'moon_tower',
};

/// 장면 원화를 현재 화면의 물리 픽셀 너비에 맞춰 디코드한다.
///
/// 같은 함수를 현장 배경과 이동 카드가 함께 사용해야 [ImageCache] 키가 일치해
/// 장면 전환 직후 원본 이미지를 다시 디코드하지 않는다.
int expeditionSceneDecodeWidth(BuildContext context) {
  final media = MediaQuery.of(context);
  return (media.size.width * media.devicePixelRatio * 1.15)
      .round()
      .clamp(480, 1600);
}

/// 원본 이름과 1:1로 생성되는 모바일 런타임 파생본 경로를 반환한다.
///
/// 원본을 덮어쓰지 않으므로 데스크톱과 고밀도 화면의 화질을 유지하면서 작은 화면의
/// WebP 해제 비용만 줄일 수 있다. 파생본은 build_expedition_runtime_assets.py가 만든다.
String expeditionMobileAssetPath(String assetPath) {
  final extensionIndex = assetPath.lastIndexOf('.');
  if (extensionIndex < 0) return '$assetPath-mobile';
  return '${assetPath.substring(0, extensionIndex)}-mobile'
      '${assetPath.substring(extensionIndex)}';
}

ImageProvider<Object> expeditionRuntimeImageProvider({
  required String assetPath,
  required int cacheWidth,
  required int mobileAssetWidth,
}) {
  final resolvedPath = cacheWidth <= mobileAssetWidth
      ? expeditionMobileAssetPath(assetPath)
      : assetPath;
  return ResizeImage.resizeIfNeeded(
    cacheWidth,
    null,
    AssetImage(resolvedPath),
  );
}

ImageProvider<Object> expeditionSceneImageProvider(
  BuildContext context,
  String assetPath,
) {
  final cacheWidth = expeditionSceneDecodeWidth(context);
  return expeditionRuntimeImageProvider(
    assetPath: assetPath,
    cacheWidth: cacheWidth,
    mobileAssetWidth: expeditionMobileSceneWidth,
  );
}

class ExpeditionSceneTheme {
  const ExpeditionSceneTheme({
    required this.assetPath,
    required this.icon,
    required this.accent,
  });

  final String assetPath;
  final IconData icon;
  final Color accent;
}

const _sceneThemes = <String, ExpeditionSceneTheme>{
  'dungeon_gate': ExpeditionSceneTheme(
    assetPath: expeditionDungeonGateAsset,
    icon: Icons.fort_outlined,
    accent: Color(0xFFE8B86B),
  ),
  'flooded_cave': ExpeditionSceneTheme(
    assetPath: expeditionFloodedCaveAsset,
    icon: Icons.water_outlined,
    accent: Color(0xFF72D6DD),
  ),
  'root_tunnel': ExpeditionSceneTheme(
    assetPath: expeditionRootTunnelAsset,
    icon: Icons.alt_route_rounded,
    accent: Color(0xFFD3A15F),
  ),
  'echo_well': ExpeditionSceneTheme(
    assetPath: expeditionEchoWellAsset,
    icon: Icons.local_fire_department_outlined,
    accent: Color(0xFFF0C674),
  ),
  'treasure_vault': ExpeditionSceneTheme(
    assetPath: expeditionTreasureVaultAsset,
    icon: Icons.inventory_2_outlined,
    accent: Color(0xFFFFD166),
  ),
  'monster_den': ExpeditionSceneTheme(
    assetPath: expeditionMonsterDenAsset,
    icon: Icons.pets_outlined,
    accent: Color(0xFFE67B68),
  ),
  'moon_tower': ExpeditionSceneTheme(
    assetPath: expeditionMoonTowerAsset,
    icon: Icons.stairs_outlined,
    accent: Color(0xFFB8C5FF),
  ),
};

ExpeditionSceneTheme expeditionSceneTheme(String sceneKey) =>
    _sceneThemes[sceneKey] ?? _sceneThemes['dungeon_gate']!;

const expeditionGuardianBattleScene = ExpeditionSceneTheme(
  assetPath: expeditionMonsterDenBattleAsset,
  icon: Icons.shield_outlined,
  accent: Color(0xFFE67B68),
);

class ExpeditionSceneBackdrop extends StatefulWidget {
  const ExpeditionSceneBackdrop({
    super.key,
    required this.scene,
    required this.semanticLabel,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.preloadScenes = const [],
    this.preloadDelay = Duration.zero,
  });

  final ExpeditionSceneTheme scene;
  final String semanticLabel;
  final Widget child;
  final BorderRadius borderRadius;
  final List<ExpeditionSceneTheme> preloadScenes;
  final Duration preloadDelay;

  @override
  State<ExpeditionSceneBackdrop> createState() =>
      _ExpeditionSceneBackdropState();
}

class _ExpeditionSceneBackdropState extends State<ExpeditionSceneBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient;
  String? _currentPrecacheSignature;
  String? _nextPrecacheSignature;
  Timer? _nextPrecacheTimer;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheVisibleScenes();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ambient
        ..stop()
        ..value = .35;
    } else if (!_ambient.isAnimating) {
      _ambient.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ExpeditionSceneBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _precacheVisibleScenes();
  }

  void _precacheVisibleScenes() {
    final cacheWidth = expeditionSceneDecodeWidth(context);
    final currentSignature = '${widget.scene.assetPath}@$cacheWidth';
    if (_currentPrecacheSignature != currentSignature) {
      _currentPrecacheSignature = currentSignature;
      precacheImage(
        expeditionSceneImageProvider(context, widget.scene.assetPath),
        context,
      ).ignore();
    }

    final nextAssets = widget.preloadScenes
        .map((scene) => scene.assetPath)
        .where((asset) => asset != widget.scene.assetPath)
        .toSet()
        .take(2)
        .toList(growable: false);
    final nextSignature = '${nextAssets.join('|')}@$cacheWidth';
    if (_nextPrecacheSignature == nextSignature) return;
    _nextPrecacheSignature = nextSignature;
    _nextPrecacheTimer?.cancel();
    if (nextAssets.isEmpty) return;

    void preloadNextScenes() {
      if (!mounted || _nextPrecacheSignature != nextSignature) return;
      // 전체 지역을 올리지 않고 실제로 열린 다음 길만 준비한다.
      for (final asset in nextAssets) {
        precacheImage(
          expeditionSceneImageProvider(context, asset),
          context,
        ).ignore();
      }
    }

    if (widget.preloadDelay == Duration.zero) {
      preloadNextScenes();
    } else {
      // 서버 응답 직후의 첫 전투 프레임과 이미지 디코드를 겹치지 않는다.
      _nextPrecacheTimer = Timer(widget.preloadDelay, preloadNextScenes);
    }
  }

  @override
  void dispose() {
    _nextPrecacheTimer?.cancel();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
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
                  builder: (context, child) {
                    final drift =
                        reduceMotion ? 0.0 : (_ambient.value - .5) * 7;
                    return Transform.translate(
                      offset: Offset(drift, -drift * .28),
                      child: Transform.scale(scale: 1.035, child: child),
                    );
                  },
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 360),
                    switchInCurve: MongrooMotion.enter,
                    switchOutCurve: Curves.easeIn,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      fit: StackFit.expand,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: .985, end: 1).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: MongrooMotion.enter,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                    child: Image(
                      image: expeditionSceneImageProvider(
                        context,
                        widget.scene.assetPath,
                      ),
                      key: ValueKey(widget.scene.assetPath),
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stackTrace) =>
                          ColoredBox(color: palette.night),
                    ),
                  ),
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
                          palette.night.withAlpha(48),
                          Colors.transparent,
                          palette.night.withAlpha(228),
                        ],
                        stops: const [0, .48, 1],
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
                      painter: _ExpeditionMotePainter(
                        phase: _ambient.value,
                        color: widget.scene.accent,
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
                      border: Border.all(color: Colors.white.withAlpha(28)),
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

class _ExpeditionMotePainter extends CustomPainter {
  const _ExpeditionMotePainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  static const _points = <Offset>[
    Offset(.12, .32),
    Offset(.26, .62),
    Offset(.44, .23),
    Offset(.61, .53),
    Offset(.78, .31),
    Offset(.88, .69),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < _points.length; index++) {
      final point = _points[index];
      final wave = math.sin(phase * math.pi * 2 + index * 1.63);
      final center = Offset(
        point.dx * size.width + wave * 4,
        point.dy * size.height - wave * 5,
      );
      canvas.drawCircle(
        center,
        2.2,
        Paint()
          ..color = color.withAlpha(75)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        center,
        .85,
        Paint()..color = AppTheme.onNight.withAlpha(155),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExpeditionMotePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
