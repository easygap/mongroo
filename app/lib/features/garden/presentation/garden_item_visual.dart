import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../home/presentation/plant_view.dart';
import '../domain/garden_models.dart';

const gardenDefaultRoomAssetPath = 'assets/rooms/day-greenhouse-ink.webp';

/// 서버 `asset_key`를 앱 번들 파일에 연결한다.
///
/// 새 방 테마/아이템 자산이 들어오면 이 표에 한 줄을 추가하면 상점·도감·
/// 마이룸이 동시에 같은 이미지를 사용한다. 검수한 번들 자산은 서버의 임시
/// 미리보기 URL보다 우선해 앱 전체의 잉크 일러스트 방향을 유지한다.
const Map<String, String> gardenBundledAssetKeyPaths = {
  'deco/cushion_leaf': 'assets/decorations/leaf-cushion.webp',
  'deco/lamp_moon': 'assets/decorations/moon-lamp.webp',
  'deco/rug_cloud': 'assets/decorations/cloud-rug.webp',
  'deco/mushroom_reading_lamp': 'assets/decorations/mushroom-reading-lamp.webp',
  'deco/strawberry_radio': 'assets/decorations/strawberry-radio.webp',
  'deco/frog_stool': 'assets/decorations/frog-stool.webp',
  'deco/pressed_flower_books': 'assets/decorations/pressed-flower-books.webp',
  'deco/moon_seed_mobile': 'assets/decorations/moon-seed-mobile.webp',
  'deco/teacup_planter': 'assets/decorations/teacup-planter.webp',
  'deco/resonance_sunny': 'assets/decorations/mood-lamp-sunny.webp',
  'deco/resonance_rainy': 'assets/decorations/listening-chime-rainy.webp',
  'deco/resonance_ember': 'assets/decorations/courage-lantern-ember.webp',
  'deco/resonance_moonlit': 'assets/decorations/preparation-lamp-moonlit.webp',
  'deco/resonance_sparkling': 'assets/decorations/prism-bud-sparkling.webp',
  'deco/resonance_mosaic': 'assets/decorations/many-heart-mobile-mosaic.webp',
  'room/sunny_greenhouse': 'assets/rooms/sunny-greenhouse.webp',
  'room/moonlit_dream': 'assets/rooms/moonlit-dream.webp',
  'room/sakura_loft': 'assets/rooms/sakura-loft.webp',
  'room/fox_star_shrine': 'assets/rooms/fox-star-shrine.webp',
  'room/magic_atelier': 'assets/rooms/magic-atelier.webp',
  'room/cloud_cafe': 'assets/rooms/cloud-cafe.webp',
  'room/pressed_flower_studio': 'assets/rooms/pressed-flower-studio.webp',
  'character/mongle': 'assets/characters/mongle.webp',
  'companion/dewdrop': 'assets/companions/dewdrop.webp',
  'companion/star': 'assets/companions/star-bean.webp',
  'companion/bunny': 'assets/companions/fluffy-bunny.webp',
  'species/cactus': 'assets/species/cactus-seed.webp',
  'species/sunflower': 'assets/species/sunflower-seed.webp',
  'characters/baby-pot': 'assets/characters/baby-pot-v2.webp',
  'characters/handsome-pot': 'assets/characters/handsome-pot-v2.webp',
  'characters/pretty-pot': 'assets/characters/pretty-pot-v2.webp',
  'characters/tsundere-pot': 'assets/characters/tsundere-pot-v3.webp',
  'characters/zombie-pot': 'assets/characters/zombie-pot-v2.webp',
  'characters/gumiho-pot': 'assets/characters/gumiho-pot-v3.webp',
  'characters/ninja-pot': 'assets/characters/ninja-pot-v2.webp',
  'characters/magical-pot': 'assets/characters/magical-pot-v2.webp',
  'characters/aloof-pot': 'assets/characters/aloof-pot-v2.webp',
  'characters/student-pot': 'assets/characters/student-pot-v2.webp',
  'characters/nurse-pot': 'assets/characters/nurse-pot-v6.webp',
  'characters/maestro-pot': 'assets/characters/maestro-pot-v6.webp',
};

/// `asset_key`가 없는 응답은 상품 코드로 찾는다.
const Map<String, String> gardenBundledItemCodePaths = {
  'deco_cushion_leaf': 'assets/decorations/leaf-cushion.webp',
  'deco_lamp_moon': 'assets/decorations/moon-lamp.webp',
  'deco_rug_cloud': 'assets/decorations/cloud-rug.webp',
  'deco_lamp_mushroom': 'assets/decorations/mushroom-reading-lamp.webp',
  'deco_radio_strawberry': 'assets/decorations/strawberry-radio.webp',
  'deco_stool_frog': 'assets/decorations/frog-stool.webp',
  'deco_books_pressed': 'assets/decorations/pressed-flower-books.webp',
  'deco_mobile_moon_seed': 'assets/decorations/moon-seed-mobile.webp',
  'deco_planter_teacup': 'assets/decorations/teacup-planter.webp',
  'deco_resonance_sunny': 'assets/decorations/mood-lamp-sunny.webp',
  'deco_resonance_rainy': 'assets/decorations/listening-chime-rainy.webp',
  'deco_resonance_ember': 'assets/decorations/courage-lantern-ember.webp',
  'deco_resonance_moonlit': 'assets/decorations/preparation-lamp-moonlit.webp',
  'deco_resonance_sparkling': 'assets/decorations/prism-bud-sparkling.webp',
  'deco_resonance_mosaic': 'assets/decorations/many-heart-mobile-mosaic.webp',
  'room_sunny': 'assets/rooms/sunny-greenhouse.webp',
  'room_moonlit': 'assets/rooms/moonlit-dream.webp',
  'room_sakura': 'assets/rooms/sakura-loft.webp',
  'room_fox_shrine': 'assets/rooms/fox-star-shrine.webp',
  'room_magic_atelier': 'assets/rooms/magic-atelier.webp',
  'room_cloud_cafe': 'assets/rooms/cloud-cafe.webp',
  'room_pressed_studio': 'assets/rooms/pressed-flower-studio.webp',
  'character_mongle': 'assets/characters/mongle.webp',
  'companion_dewdrop': 'assets/companions/dewdrop.webp',
  'companion_star': 'assets/companions/star-bean.webp',
  'companion_bunny': 'assets/companions/fluffy-bunny.webp',
  'species_cactus': 'assets/species/cactus-seed.webp',
  'species_sunflower': 'assets/species/sunflower-seed.webp',
  'character_nurse_pot': 'assets/characters/nurse-pot-v6.webp',
  'character_maestro_pot': 'assets/characters/maestro-pot-v6.webp',
};

String? gardenVisualAssetPath(ShopItem item) {
  final keyPath = gardenBundledAssetKeyPaths[item.assetKey];
  if (keyPath != null) return keyPath;
  final codePath = gardenBundledItemCodePaths[item.code];
  if (codePath != null) return codePath;
  final remoteOrManifestPath = item.assetPath;
  if (remoteOrManifestPath != null) return remoteOrManifestPath;
  return item.isCharacter
      ? item.bundledCharacterAssetPath
      : item.bundledAssetPath;
}

class GardenItemVisual extends StatelessWidget {
  const GardenItemVisual({
    super.key,
    required this.item,
    this.fit = BoxFit.contain,
    this.locked = false,
    this.animateIdle = true,
    this.cacheWidth = 768,
  });

  final ShopItem item;
  final BoxFit fit;
  final bool locked;
  final bool animateIdle;

  /// 래스터 decode 폭. 목록은 512, 큰 방/홈은 768을 사용해 캐시 메모리를 제한한다.
  final int cacheWidth;

  IconData get _fallbackIcon => switch (item.type) {
        'room_theme' => Icons.wallpaper_outlined,
        'main_character' => Icons.local_florist_outlined,
        'companion' => Icons.pets_outlined,
        'species_unlock' => Icons.eco_outlined,
        _ => Icons.chair_outlined,
      };

  @override
  Widget build(BuildContext context) {
    if (item.isGrowthCharacter) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final preview = PlantStagePreview(
        stage: 1,
        speciesCode: item.growthSpeciesCode,
        speciesName: item.name,
        size: item.hasFinalCharacterPreview
            ? 126
            : (cacheWidth / dpr).clamp(96, 512).toDouble(),
      );
      final finalAssetPath =
          item.hasFinalCharacterPreview ? item.bundledCharacterAssetPath : null;
      final growthPreview = finalAssetPath == null
          ? preview
          : SizedBox(
              width: 360,
              height: 300,
              child: Row(
                children: [
                  SizedBox(width: 126, height: 190, child: preview),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 24),
                  ),
                  Expanded(
                    child: AnimatedGardenCharacter(
                      item: item,
                      fit: BoxFit.contain,
                      locked: locked,
                      animateIdle: animateIdle,
                      cacheWidth: cacheWidth,
                    ),
                  ),
                ],
              ),
            );
      return Semantics(
        image: true,
        label: locked
            ? '${item.name}, 아직 해금하지 않은 성장 씨앗'
            : item.hasFinalCharacterPreview
                ? '${item.name}, 씨앗에서 사람형 완전체까지 자라는 성장 캐릭터'
                : '${item.name}, 씨앗부터 만개까지 자라는 성장 캐릭터',
        child: ExcludeSemantics(
          child: FittedBox(
            fit: fit,
            child: locked
                ? ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF807A72),
                      BlendMode.saturation,
                    ),
                    child: Opacity(opacity: .52, child: growthPreview),
                  )
                : growthPreview,
          ),
        ),
      );
    }

    if (item.isCompanion) {
      return AnimatedGardenCharacter(
        item: item,
        fit: fit,
        locked: locked,
        animateIdle: animateIdle,
        cacheWidth: cacheWidth,
      );
    }

    final path = gardenVisualAssetPath(item);
    final bundledFallback = switch (item.type) {
      'room_theme' => gardenDefaultRoomAssetPath,
      'species_unlock' => 'assets/species/sunflower-seed.webp',
      _ => null,
    };
    Widget fallback() => _GardenInkFallback(
          icon: locked ? Icons.lock_outline : _fallbackIcon,
        );

    final visual = _gardenImage(
      path: path ?? bundledFallback,
      fit: fit,
      cacheWidth: cacheWidth,
      fallback: fallback,
    );

    final treatedVisual = item.isRoomTheme
        ? visual
        : ColorFiltered(
            key: ValueKey('garden-ink-tone-${item.code}'),
            colorFilter: _inkToneFilter,
            child: visual,
          );
    return Semantics(
      image: true,
      label: locked ? '${item.name}, 잠긴 아이템' : item.name,
      child: ExcludeSemantics(
        child: Opacity(opacity: locked ? 0.42 : 1, child: treatedVisual),
      ),
    );
  }
}

/// 상점, 도감, 방에서 함께 쓰는 캐릭터 렌더러.
class AnimatedGardenCharacter extends StatefulWidget {
  const AnimatedGardenCharacter({
    super.key,
    required this.item,
    this.fit = BoxFit.contain,
    this.locked = false,
    this.animateIdle = true,
    this.cacheWidth = 768,
  });

  final ShopItem item;
  final BoxFit fit;
  final bool locked;
  final bool animateIdle;

  /// 원본 크기 대신 실제 표시 크기에 가까운 래스터를 decode한다.
  final int cacheWidth;

  @override
  State<AnimatedGardenCharacter> createState() =>
      _AnimatedGardenCharacterState();
}

class _AnimatedGardenCharacterState extends State<AnimatedGardenCharacter>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _tapController;
  late final Listenable _motion;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _motionDuration(widget.item.motionKey),
    );
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    _motion = Listenable.merge([_controller, _tapController]);
  }

  @override
  void didUpdateWidget(covariant AnimatedGardenCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.motionKey != widget.item.motionKey ||
        oldWidget.locked != widget.locked ||
        oldWidget.animateIdle != widget.animateIdle) {
      _controller.duration = _motionDuration(widget.item.motionKey);
      _tapController
        ..stop()
        ..value = 0;
      _syncMotion();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disabled != _animationsDisabled) {
      _animationsDisabled = disabled;
      _syncMotion();
    } else if (!_controller.isAnimating && !_animationsDisabled) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    if (_animationsDisabled || widget.locked) {
      _controller.stop();
      _controller.value = 0;
      _tapController.stop();
      _tapController.value = 0;
    } else if (widget.animateIdle) {
      _controller.repeat();
    } else {
      // 상점·도감 그리드는 수십 개 ticker를 계속 돌리지 않는다. 포인터로
      // 직접 반응할 때의 짧은 탭 모션은 별도 controller로 그대로 제공한다.
      _controller.stop();
      _controller.value = 0;
    }
  }

  void _playTapMotion() {
    if (_animationsDisabled ||
        widget.locked ||
        !_supportsTapMotion(widget.item.motionKey)) {
      return;
    }
    _tapController.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _tapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = gardenVisualAssetPath(widget.item);
    Widget fallback() => _GardenInkFallback(
          icon:
              widget.locked ? Icons.lock_outline : Icons.local_florist_outlined,
        );
    final image = _gardenImage(
      path: path ?? 'assets/characters/mongle.webp',
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      fallback: fallback,
    );

    return Semantics(
      image: true,
      label: widget.locked
          ? '${widget.item.name}, 아직 만나지 못한 캐릭터'
          : '${widget.item.name}, ${widget.item.personality}',
      hint: widget.locked ? '퀘스트와 상점에서 만날 수 있어요.' : widget.item.catchphrase,
      child: ExcludeSemantics(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _playTapMotion(),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _motion,
              child: image,
              builder: (context, child) {
                final motionEnabled = !_animationsDisabled && !widget.locked;
                final idlePose = _characterPose(
                  widget.item.motionKey,
                  motionEnabled ? _controller.value : 0,
                );
                final pose = idlePose.combinedWith(
                  _tapPose(
                    widget.item.motionKey,
                    motionEnabled ? _tapController.value : 0,
                  ),
                );
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (_showsSparkles(widget.item.motionKey) && !widget.locked)
                      ..._sparkles(
                        context,
                        progress: _animationsDisabled ? 0 : _controller.value,
                      ),
                    Opacity(
                      opacity: widget.locked ? 0.38 : pose.opacity,
                      child: Transform.translate(
                        key: ValueKey('character-pose-${widget.item.code}'),
                        offset: Offset(pose.x, pose.y),
                        child: Transform.rotate(
                          angle: pose.rotation,
                          alignment: Alignment.bottomCenter,
                          child: Transform.scale(
                            scaleX: pose.scaleX,
                            scaleY: pose.scaleY,
                            alignment: Alignment.bottomCenter,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                    if (widget.locked)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surface.withAlpha(224),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sparkles(BuildContext context, {required double progress}) {
    final color = Theme.of(context).colorScheme.tertiary;
    final wave = (math.sin(progress * math.pi * 2) + 1) / 2;
    return [
      Positioned(
        top: 8,
        right: 10,
        child: Opacity(
          opacity: 0.28 + wave * 0.72,
          child: Transform.scale(
            scale: 0.65 + wave * 0.35,
            child: Icon(Icons.auto_awesome, size: 18, color: color),
          ),
        ),
      ),
      Positioned(
        left: 12,
        top: 34,
        child: Opacity(
          opacity: 0.25 + (1 - wave) * 0.65,
          child: Transform.rotate(
            angle: progress * math.pi / 2,
            child: Icon(Icons.star_rounded, size: 12, color: color),
          ),
        ),
      ),
    ];
  }
}

class GardenRarityFrame extends StatelessWidget {
  const GardenRarityFrame({
    super.key,
    required this.item,
    required this.child,
    this.locked = false,
    this.padding = const EdgeInsets.all(10),
  });

  final ShopItem item;
  final Widget child;
  final bool locked;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = MongrooPalette.of(context);
    final accent = gardenRarityColor(
      scheme,
      item.rarity,
      palette: palette,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withAlpha(locked ? 12 : 28),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(locked ? 54 : 138)),
        boxShadow: [
          BoxShadow(
            color: palette.night.withAlpha(24),
            blurRadius: 0,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 희귀도 프레임과 작은 텍스트에 함께 쓸 수 있는 AA 대비 색상.
///
/// 밝은 테마에서는 채도를 유지한 짙은 톤, 어두운 테마에서는 밝은 톤을 써서
/// `surface` 위 11~13px 라벨도 최소 4.5:1 대비를 확보한다.
Color gardenRarityColor(
  ColorScheme scheme,
  int rarity, {
  required MongrooPalette palette,
}) {
  final dark = scheme.brightness == Brightness.dark;
  return switch (rarity) {
    >= 4 => dark ? palette.butter : const Color(0xFF655D00),
    3 => dark ? palette.coral : const Color(0xFF2B5267),
    2 => dark ? palette.leaf : const Color(0xFF315518),
    _ => dark ? palette.ink : palette.night,
  };
}

const _inkToneFilter = ColorFilter.matrix(<double>[
  1.08,
  -0.04,
  -0.04,
  0,
  -4,
  -0.04,
  1.08,
  -0.04,
  0,
  -4,
  -0.04,
  -0.04,
  1.08,
  0,
  -4,
  0,
  0,
  0,
  1,
  0,
]);

class _GardenInkFallback extends StatelessWidget {
  const _GardenInkFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = MongrooPalette.of(context);
    return Center(
      child: SizedBox.square(
        dimension: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paperDeep,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.night.withAlpha(110)),
            boxShadow: [
              BoxShadow(
                color: palette.night.withAlpha(26),
                offset: const Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Icon(icon, size: 34, color: palette.leaf),
        ),
      ),
    );
  }
}

Widget _gardenImage({
  required String? path,
  required BoxFit fit,
  required int cacheWidth,
  required Widget Function() fallback,
}) {
  if (path == null) return fallback();
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return Image.network(
      path,
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }
  return Image.asset(
    path,
    fit: fit,
    cacheWidth: cacheWidth,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
    errorBuilder: (_, __, ___) => fallback(),
  );
}

Duration _motionDuration(String motionKey) => switch (motionKey) {
      'baby_bounce' => const Duration(milliseconds: 1800),
      'prince_flourish' => const Duration(milliseconds: 2600),
      'pretty_sparkle' => const Duration(milliseconds: 2100),
      'tsundere_turn_away' => const Duration(milliseconds: 2300),
      'ninja_snap' => const Duration(milliseconds: 1800),
      'zombie_sway' => const Duration(milliseconds: 3600),
      'gumiho_float' => const Duration(milliseconds: 3000),
      'magical_hover' => const Duration(milliseconds: 2800),
      'aloof_glance' => const Duration(milliseconds: 4200),
      'student_adjust' => const Duration(milliseconds: 2800),
      'nurse_breathe' => const Duration(milliseconds: 3400),
      'maestro_cue' => const Duration(milliseconds: 3000),
      _ => const Duration(milliseconds: 2400),
    };

bool _showsSparkles(String motionKey) =>
    motionKey == 'pretty_sparkle' || motionKey == 'magical_hover';

_CharacterPose _characterPose(String motionKey, double progress) {
  final wave = math.sin(progress * math.pi * 2);
  final softWave = math.sin(progress * math.pi * 2 - math.pi / 2);
  return switch (motionKey) {
    'baby_bounce' => _CharacterPose(
        y: -math.max(0, wave) * 7,
        scaleX: 1 + math.max(0, -wave) * 0.035,
        scaleY: 1 - math.max(0, -wave) * 0.035,
      ),
    'prince_flourish' => _CharacterPose(
        x: wave * 2.5,
        y: -math.max(0, softWave) * 2,
        rotation: wave * 0.035,
        scaleX: 1 + math.max(0, wave) * 0.018,
        scaleY: 1 + math.max(0, wave) * 0.018,
      ),
    'pretty_sparkle' => _CharacterPose(
        y: wave * 2,
        rotation: wave * 0.018,
        scaleX: 1 + softWave * 0.012,
        scaleY: 1 + softWave * 0.012,
      ),
    'tsundere_turn_away' => _CharacterPose(
        x: math.max(0, wave) * 3.5,
        rotation: -math.max(0, wave) * 0.045,
        scaleX: 1 - math.max(0, wave) * 0.025,
      ),
    'zombie_sway' => _CharacterPose(
        x: wave * 2,
        rotation: wave * 0.055,
        scaleY: 1 + softWave * 0.012,
      ),
    'gumiho_float' => _CharacterPose(
        y: wave * 5,
        rotation: wave * 0.02,
        scaleX: 1 + softWave * 0.015,
        scaleY: 1 + softWave * 0.015,
      ),
    'ninja_snap' => _ninjaPose(progress),
    'aloof_glance' => _CharacterPose(
        x: wave * 1.4,
        rotation: -wave * 0.012,
        scaleX: 1 - math.max(0, wave) * 0.009,
      ),
    'student_adjust' => _CharacterPose(
        y: -math.max(0, wave) * 1.8,
        rotation: wave * 0.008,
        scaleY: 1 - math.max(0, -softWave) * 0.008,
      ),
    'nurse_breathe' => _CharacterPose(
        y: wave * 1.5,
        rotation: wave * .006,
        scaleX: 1 + softWave * .006,
        scaleY: 1 + softWave * .006,
      ),
    'maestro_cue' => _CharacterPose(
        x: wave * 1.8,
        rotation: wave * .012,
        scaleX: 1 + math.max(0, softWave) * .008,
      ),
    _ => _CharacterPose(
        y: wave * 3.5,
        rotation: wave * 0.015,
        scaleX: 1 + softWave * 0.012,
        scaleY: 1 + softWave * 0.012,
      ),
  };
}

bool _supportsTapMotion(String motionKey) => const {
      'baby_bounce',
      'prince_flourish',
      'pretty_sparkle',
      'tsundere_turn_away',
      'zombie_sway',
      'gumiho_float',
      'ninja_snap',
      'magical_hover',
      'aloof_glance',
      'student_adjust',
      'nurse_breathe',
      'maestro_cue',
    }.contains(motionKey);

_CharacterPose _tapPose(String motionKey, double progress) {
  if (progress <= 0 || progress >= 1) return const _CharacterPose();
  final envelope = math.sin(progress * math.pi);
  final oscillation = math.sin(progress * math.pi * 2);
  return switch (motionKey) {
    'baby_bounce' => _CharacterPose(
        y: -8 * envelope,
        rotation: oscillation * envelope * .035,
        scaleX: 1 + .055 * envelope,
        scaleY: 1 - .035 * envelope,
      ),
    'prince_flourish' => _CharacterPose(
        x: 2.4 * oscillation * envelope,
        y: -3 * envelope,
        rotation: .05 * oscillation * envelope,
        scaleX: 1 + .018 * envelope,
        scaleY: 1 + .018 * envelope,
      ),
    'pretty_sparkle' => _CharacterPose(
        y: -5 * envelope,
        rotation: .075 * oscillation * envelope,
        scaleX: 1 + .035 * envelope,
        scaleY: 1 + .035 * envelope,
      ),
    'tsundere_turn_away' => _CharacterPose(
        x: 7 * envelope,
        rotation: -.06 * envelope,
        scaleX: 1 - .035 * envelope,
      ),
    'zombie_sway' => _CharacterPose(
        x: 4.5 * oscillation * envelope,
        y: 2 * envelope,
        rotation: .085 * oscillation * envelope,
        scaleY: 1 - .025 * envelope,
      ),
    'gumiho_float' => _CharacterPose(
        y: -8 * envelope,
        rotation: .035 * oscillation * envelope,
        scaleX: 1 + .03 * envelope,
        scaleY: 1 + .03 * envelope,
      ),
    'ninja_snap' => _CharacterPose(
        x: 12 * oscillation * envelope,
        y: -2.5 * envelope,
        rotation: -.045 * oscillation * envelope,
        scaleX: 1 - .045 * envelope,
        opacity: 1 - .12 * envelope,
      ),
    'magical_hover' => _CharacterPose(
        y: -9 * envelope,
        rotation: .09 * oscillation * envelope,
        scaleX: 1 + .035 * envelope,
        scaleY: 1 + .035 * envelope,
      ),
    'aloof_glance' => _CharacterPose(
        x: -3.5 * envelope,
        rotation: -0.032 * envelope,
        scaleX: 1 - 0.018 * envelope,
        opacity: 1 - 0.025 * envelope,
      ),
    'student_adjust' => _CharacterPose(
        x: oscillation * envelope * 1.2,
        y: -3 * envelope,
        rotation: -oscillation * envelope * 0.012,
        scaleX: 1 + 0.008 * envelope,
        scaleY: 1 - 0.015 * envelope,
      ),
    'nurse_breathe' => _CharacterPose(
        y: -2.5 * envelope,
        scaleX: 1 + .018 * envelope,
        scaleY: 1 + .018 * envelope,
      ),
    'maestro_cue' => _CharacterPose(
        x: 2.4 * oscillation * envelope,
        rotation: -.025 * oscillation * envelope,
        scaleX: 1 + .016 * envelope,
      ),
    _ => const _CharacterPose(),
  };
}

_CharacterPose _ninjaPose(double progress) {
  if (progress < 0.12) {
    final snap = Curves.easeOutCubic.transform(progress / 0.12);
    return _CharacterPose(
      x: (1 - snap) * -9,
      scaleX: 0.94 + snap * 0.06,
      scaleY: 0.94 + snap * 0.06,
      opacity: 0.55 + snap * 0.45,
    );
  }
  if (progress > 0.86) {
    final ready = Curves.easeInOut.transform((progress - 0.86) / 0.14);
    return _CharacterPose(x: ready * 2.5, rotation: -ready * 0.025);
  }
  return const _CharacterPose();
}

class _CharacterPose {
  const _CharacterPose({
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.opacity = 1,
  });

  final double x;
  final double y;
  final double rotation;
  final double scaleX;
  final double scaleY;
  final double opacity;

  _CharacterPose combinedWith(_CharacterPose other) => _CharacterPose(
        x: x + other.x,
        y: y + other.y,
        rotation: rotation + other.rotation,
        scaleX: scaleX * other.scaleX,
        scaleY: scaleY * other.scaleY,
        opacity: opacity * other.opacity,
      );
}

class SeedBalanceBadge extends StatelessWidget {
  const SeedBalanceBadge({super.key, required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '보유 씨앗 $balance개',
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.toll_outlined,
              size: 18,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 6),
            Text(
              '$balance',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
