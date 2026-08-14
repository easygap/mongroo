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

/// 지역 전용 장면 원화가 **이미 있는** 것들.
///
/// `{지역}/{장면}` 조합만 적는다. 여기 없는 조합은 공용 원화로 떨어지므로,
/// 새 원화가 들어오면 이 표에 한 줄 더하는 것으로 끝난다. 파일이 없는데 표에
/// 적으면 그 장면만 검은 화면이 되므로 번들 테스트가 존재를 확인한다.
/// 첫 지역의 지형 지도. 전용 지도가 없는 지역이 기대는 자리다.
const mossArchiveMapAsset =
    'assets/adventure/expedition-moss-archive-terrain-v3.webp';

/// 지역 전용 지형 지도.
///
/// 걷는 내내 보는 화면이라 장면 배경보다 먼저 갈랐어야 했다. 네 지역이 기억서고
/// 지형 하나를 공유하던 동안에는 색 보정으로 덮어 두었지만, 그 그림에는 보물상자
/// 동굴·뿌리 둥지 같은 **기억서고의 물건**이 박혀 있어 색만으로는 다른 지역이
/// 되지 않았다.
///
/// 여덟 랜드마크가 노드 좌표에 맞춰 그려져 있다. 지도를 새로 그리면 노드 자리도
/// 함께 봐야 하고, 그 대조는 `expeditionRegionWalkAreas`가 맡는다.
const expeditionRegionTerrain = <String, String>{
  'echo_well': 'assets/adventure/expedition-echo-well-terrain-v1.webp',
  'starlight_seed_vault':
      'assets/adventure/expedition-starlight-seed-vault-terrain-v1.webp',
  'heartwood_observatory':
      'assets/adventure/expedition-heartwood-observatory-terrain-v1.webp',
};

/// 이 지역의 지형 지도. 전용이 없으면 첫 지역 것을 쓴다.
String expeditionTerrainAsset(String? regionCode) =>
    expeditionRegionTerrain[regionCode] ?? mossArchiveMapAsset;

const expeditionRegionSceneAssets = <String, String>{
  // 기억서고는 공용 원화가 곧 자기 원화다(먼저 만들어진 지역이라 그렇다).
  //
  // 아래 여덟은 재사용이 가장 거슬리던 자리다 — 수호자 소굴 셋(보스방은 가장
  // 오래 보는 화면), 지역 입구 셋(새 지역 첫 화면), 그리고 두 지역의 상징 공간.
  // 나머지 장면은 여전히 공용 원화 + 지역 색 보정으로 간다.
  'echo_well/monster_den':
      'assets/adventure/expedition-monster-den-echo-well-v1.webp',
  'starlight_seed_vault/monster_den':
      'assets/adventure/expedition-monster-den-starlight-seed-vault-v1.webp',
  'heartwood_observatory/monster_den':
      'assets/adventure/expedition-monster-den-heartwood-observatory-v1.webp',
  'echo_well/dungeon_gate':
      'assets/adventure/expedition-dungeon-gate-echo-well-v1.webp',
  'starlight_seed_vault/dungeon_gate':
      'assets/adventure/expedition-dungeon-gate-starlight-seed-vault-v1.webp',
  'heartwood_observatory/dungeon_gate':
      'assets/adventure/expedition-dungeon-gate-heartwood-observatory-v1.webp',
  'starlight_seed_vault/treasure_vault':
      'assets/adventure/expedition-treasure-vault-starlight-seed-vault-v1.webp',
  'heartwood_observatory/moon_tower':
      'assets/adventure/expedition-moon-tower-heartwood-observatory-v1.webp',
  // v2 — 글과 그림이 다른 말을 하던 세 자리. `메아리 없는 방`이 이 프로젝트에서
  // 가장 절제된 원화라 나머지 둘의 화풍 기준으로 썼다.
  'echo_well/treasure_vault':
      'assets/adventure/expedition-treasure-vault-echo-well-v1.webp',
  'echo_well/echo_well':
      'assets/adventure/expedition-echo-well-echo-well-v1.webp',
  'starlight_seed_vault/root_tunnel':
      'assets/adventure/expedition-root-tunnel-starlight-seed-vault-v1.webp',
};

/// 지역마다 다른 색 보정. 전용 원화가 오기 전까지 **같은 배경이 지역마다 다르게
/// 읽히게** 하는 최소 장치다.
///
/// 원화를 대신하지는 못한다. 다만 우물정원의 침수 동굴과 보관고의 침수 동굴이
/// 완전히 같은 그림으로 보이는 것보다는, 물빛과 성에빛으로 갈라 두는 편이 낫다.
/// 전용 원화가 들어오면 이 보정은 옅어져도 된다.
const expeditionRegionGrades = <String, Color>{
  'moss_archive': Color(0x00000000),
  // 물빛 — 푸르고 축축하게.
  'echo_well': Color(0x2247A0C8),
  // 성에빛 — 차고 마르게.
  'starlight_seed_vault': Color(0x268FA6D4),
  // 나무빛 — 따뜻하고 높게.
  'heartwood_observatory': Color(0x24C08A4E),
};

/// 지역별 강조색. 같은 장면이라도 지역이 다르면 테두리와 표시선이 달라진다.
const expeditionRegionAccents = <String, Color>{
  'echo_well': Color(0xFF6FC3D9),
  'starlight_seed_vault': Color(0xFFA9BCE4),
  'heartwood_observatory': Color(0xFFD6A46A),
};

/// 이 지역에서 이 장면을 그릴 때 덮는 색.
///
/// **전용 원화가 있으면 덮지 않는다.** 보정은 공용 원화를 지역별로 갈라 주려고
/// 있는 것이라, 이미 그 지역 색으로 그려진 그림에 또 얹으면 두 번 물든다.
/// 모르는 지역도 덮지 않는다.
Color expeditionRegionGrade(String? regionCode, {String? sceneKey}) {
  if (regionCode == null) return const Color(0x00000000);
  if (sceneKey != null &&
      expeditionRegionSceneAssets.containsKey('$regionCode/$sceneKey')) {
    return const Color(0x00000000);
  }
  return expeditionRegionGrades[regionCode] ?? const Color(0x00000000);
}

/// 장면 테마. 지역을 주면 전용 원화와 지역 강조색을 함께 반영한다.
///
/// 지역을 안 주면 지금까지와 똑같이 동작한다 — 준비 화면처럼 아직 지역이 정해지지
/// 않은 자리가 있기 때문이다.
ExpeditionSceneTheme expeditionSceneTheme(
  String sceneKey, {
  String? regionCode,
}) {
  final base = _sceneThemes[sceneKey] ?? _sceneThemes['dungeon_gate']!;
  if (regionCode == null) return base;
  final dedicated = expeditionRegionSceneAssets['$regionCode/$sceneKey'];
  final accent = expeditionRegionAccents[regionCode];
  if (dedicated == null && accent == null) return base;
  return ExpeditionSceneTheme(
    assetPath: dedicated ?? base.assetPath,
    icon: base.icon,
    accent: accent ?? base.accent,
  );
}

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
    this.regionCode,
    this.sceneKey,
  });

  final ExpeditionSceneTheme scene;

  /// 어느 지역에서 보는 장면인지. 전용 원화가 없는 장면만 색 보정으로
  /// 갈라 준다. 모르면 보정하지 않는다.
  final String? regionCode;

  /// 어떤 장면인지. 이 지역·이 장면의 전용 원화가 있으면 보정을 건너뛴다.
  final String? sceneKey;
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
              // 지역 색 보정. 원화 위, 가독성 그라디언트 아래에 둔다 — 글자
              // 대비를 만드는 층을 건드리면 안 되기 때문이다.
              if (expeditionRegionGrade(
                widget.regionCode,
                sceneKey: widget.sceneKey,
              ).a >
                  0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: expeditionRegionGrade(
                        widget.regionCode,
                        sceneKey: widget.sceneKey,
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
