import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/plant.dart';

/// 잠깐 보여 주는 UI 반응. 성장 형태와 기본 표정은 일기 분석
/// 분기가 결정하며, 수동 mood level을 여기에 연결하지 않는다.
enum PlantExpression { neutral, acknowledged, happy, sad }

/// 감정 성체 원화가 제공하는 실제 자세.
///
/// 직접 지정하지 않으면 [PlantExpression]에서 일기 반응과 성장 축하 자세를
/// 자동으로 고른다.
enum PlantSpritePose {
  idle('idle'),
  diary('diary'),
  grow('grow');

  const PlantSpritePose(this.code);
  final String code;
}

/// 몽그루의 성장 캐릭터를 단계별 래스터 에셋으로 보여 주는 뷰.
///
/// 검수한 래스터 에셋이 아직 없는 조합만 런타임 벡터 painter로 대체한다.
/// idle은 완성된 레이어에 Transform만 적용하고, 동작 줄이기 설정에서는
/// 컨트롤러까지 멈춰 배터리와 프레임을 소모하지 않는다.
class PlantView extends StatefulWidget {
  const PlantView({
    super.key,
    required this.stage,
    this.expression = PlantExpression.neutral,
    this.spritePose,
    this.form,
    this.secondaryForm,
    this.speciesCode = 'basic_sprout',
    this.speciesName,
    this.growthVisual,
    this.size = 180,
    this.width,
    this.height,
    this.preferRasterAssets = true,
  });

  final int stage;
  final PlantExpression expression;
  final PlantSpritePose? spritePose;
  final PlantGrowthForm? form;
  final PlantGrowthForm? secondaryForm;
  final String speciesCode;
  final String? speciesName;
  final PlantGrowthVisual? growthVisual;

  /// 기존 정사각 호출부를 유지하기 위한 기본 크기다.
  final double size;
  final double? width;
  final double? height;

  /// 래스터 에셋이 없는 품종·단계는 기존 벡터 painter로 돌아간다.
  @visibleForTesting
  final bool preferRasterAssets;

  @override
  State<PlantView> createState() => _PlantViewState();
}

class _PlantViewState extends State<PlantView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idleController;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: _motion.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant PlantView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.form != widget.form ||
        oldWidget.secondaryForm != widget.secondaryForm ||
        oldWidget.stage != widget.stage ||
        oldWidget.speciesCode != widget.speciesCode) {
      _idleController.duration = _motion.duration;
      _syncMotion(restart: true);
    }
  }

  _PlantIdleMotion get _motion => _PlantIdleMotion.forStage(
        widget.stage,
        form: widget.stage >= 3 ? widget.form : null,
        speciesCode: widget.speciesCode,
      );

  PlantSpritePose get _spritePose =>
      widget.spritePose ??
      switch (widget.expression) {
        PlantExpression.neutral => PlantSpritePose.idle,
        PlantExpression.acknowledged ||
        PlantExpression.sad =>
          PlantSpritePose.diary,
        PlantExpression.happy => PlantSpritePose.grow,
      };

  void _syncMotion({bool restart = false}) {
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled) {
      _idleController
        ..stop()
        ..value = 0;
      return;
    }
    if (restart) _idleController.value = 0;
    if (!_idleController.isAnimating) {
      _idleController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clamped = widget.stage.clamp(1, 5).toInt();
    final revealedForm = clamped >= 2 ? widget.form : null;
    final visual = widget.growthVisual ??
        PlantGrowthVisual.fallback(speciesCode: widget.speciesCode);
    final branchLabel = clamped < 3 || revealedForm == null
        ? '성장 분기 관찰 중'
        : clamped >= 4 && widget.secondaryForm != null
            ? '${revealedForm.label} 주결, ${widget.secondaryForm!.label} 보조결'
            : '${revealedForm.label}, ${revealedForm.personalityName}';
    final visualLabel = clamped == 1
        ? '${visual.seedLabel}, ${visual.vesselLabel}'
        : visual.vesselLabel;
    final viewWidth = widget.width ?? widget.size;
    final viewHeight = widget.height ?? widget.size;
    final vectorSize = math.min(viewWidth, viewHeight);
    final vectorFallback = Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox.square(
        dimension: vectorSize,
        child: CustomPaint(
          size: Size.square(vectorSize),
          isComplex: true,
          willChange: false,
          painter: PlantPainter(
            stage: clamped,
            expression: widget.expression,
            form: revealedForm,
            secondaryForm: clamped >= 4 ? widget.secondaryForm : null,
            speciesCode: widget.speciesCode,
            growthVisual: visual,
          ),
        ),
      ),
    );
    final assetCandidates = PlantGrowthAssetResolver.candidates(
      speciesCode: widget.speciesCode,
      stage: clamped,
      form: revealedForm,
      secondaryForm: clamped >= 4 ? widget.secondaryForm : null,
      visual: visual,
      pose: _spritePose,
    );
    final painting = SizedBox(
      width: viewWidth,
      height: viewHeight,
      child: widget.preferRasterAssets && assetCandidates.isNotEmpty
          ? _RasterPlantArtwork(
              candidates: assetCandidates,
              fallback: vectorFallback,
              logicalWidth: viewWidth,
            )
          : vectorFallback,
    );
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final speciesLabel = widget.speciesName?.trim().isNotEmpty == true
        ? widget.speciesName!.trim()
        : switch (widget.speciesCode) {
            'cactus' => '가시니',
            'sunflower' => '해바라기',
            _ => '새싹몬',
          };
    return Semantics(
      image: true,
      label: '식물 모습: $speciesLabel, ${plantStageName(clamped)} 단계, '
          '$visualLabel, $branchLabel',
      child: animationsDisabled
          ? painting
          : AnimatedBuilder(
              animation: _idleController,
              child: painting,
              builder: (context, child) {
                final wave = math.sin(_idleController.value * math.pi);
                final motion = _motion;
                return Transform.translate(
                  offset: Offset(motion.dx * wave, motion.dy * wave),
                  child: Transform.rotate(
                    angle: motion.rotation * wave,
                    child: Transform.scale(
                      scaleX: 1 + motion.scaleX * wave,
                      scaleY: 1 + motion.scaleY * wave,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 서버의 계층형 asset key를 Flutter 번들에서 사용할 평면 파일명으로 바꾼다.
///
/// 감정 형태별 파일을 먼저 찾고, 아직 제작되지 않았으면 같은 단계의 공통 파일,
/// 그마저 없으면 [PlantPainter]로 내려간다.
class PlantGrowthAssetResolver {
  const PlantGrowthAssetResolver._();

  static const _emotionAdultV2Species = {
    'baby-pot',
    'handsome-pot',
    'pretty-pot',
    'tsundere-pot',
    'zombie-pot',
    'gumiho-pot',
    'ninja-pot',
    'magical-pot',
    'aloof-pot',
    'student-pot',
  };

  static const _emotionAdultV4Species = _emotionAdultV2Species;

  static const _emotionAdultV3Species = {
    'tsundere-pot',
    'gumiho-pot',
  };

  static const _phases = <int, String>{
    1: 'seed',
    2: 'sprout',
    3: 'branching',
    4: 'bloom',
    5: 'full-bloom',
  };

  static List<String> candidates({
    required String speciesCode,
    required int stage,
    PlantGrowthForm? form,
    PlantGrowthForm? secondaryForm,
    PlantGrowthVisual? visual,
    PlantSpritePose pose = PlantSpritePose.idle,
  }) {
    final clamped = stage.clamp(1, 5).toInt();
    final serverPhase = _slug(visual?.phase ?? '');
    final phase = serverPhase.isEmpty ? _phases[clamped]! : serverPhase;
    final slugs = <String>{
      _slug(speciesCode),
      _namespaceSlug(visual?.assetNamespace),
    }..removeWhere((value) => value.isEmpty || value == 'generic');
    final paths = <String>[];
    for (final species in slugs) {
      final artFamilies = species == 'basic-sprout'
          ? const [
              'basic-sprout-25d',
              'basic-sprout-cute',
              'basic-sprout',
            ]
          : ['$species-25d', species];
      for (final family in artFamilies) {
        if (clamped == 5 &&
            form != null &&
            family == '$species-25d' &&
            _emotionAdultV2Species.contains(species)) {
          if (_emotionAdultV4Species.contains(species)) {
            paths.add(
              'assets/plants/$family-$phase-${form.code}'
              '-v4-${pose.code}.webp',
            );
          }
          if (_emotionAdultV3Species.contains(species)) {
            paths.add(
              'assets/plants/$family-$phase-${form.code}-v3.webp',
            );
          }
          paths.add(
            'assets/plants/$family-$phase-${form.code}-v2.webp',
          );
        }
        if (clamped >= 4 && form != null && secondaryForm != null) {
          paths.add(
            'assets/plants/$family-$phase-${form.code}-${secondaryForm.code}.webp',
          );
        }
        if (clamped >= 2 && form != null) {
          paths.add('assets/plants/$family-$phase-${form.code}.webp');
        }
        paths.add('assets/plants/$family-$phase.webp');
      }
    }
    return paths.toSet().toList(growable: false);
  }

  static String _namespaceSlug(String? namespace) {
    final value = namespace?.trim() ?? '';
    if (value.isEmpty) return '';
    final withoutPrefix =
        value.startsWith('plants/') ? value.substring('plants/'.length) : value;
    return _slug(withoutPrefix);
  }

  static String _slug(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _RasterPlantArtwork extends StatefulWidget {
  const _RasterPlantArtwork({
    required this.candidates,
    required this.fallback,
    required this.logicalWidth,
  });

  final List<String> candidates;
  final Widget fallback;
  final double logicalWidth;

  @override
  State<_RasterPlantArtwork> createState() => _RasterPlantArtworkState();
}

class _RasterPlantArtworkState extends State<_RasterPlantArtwork> {
  int _candidateIndex = 0;
  bool _advanceScheduled = false;

  @override
  void didUpdateWidget(covariant _RasterPlantArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.candidates, widget.candidates)) {
      _candidateIndex = 0;
      _advanceScheduled = false;
    }
  }

  void _tryNextCandidate() {
    if (_advanceScheduled || _candidateIndex >= widget.candidates.length - 1) {
      return;
    }
    _advanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _candidateIndex += 1;
        _advanceScheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candidates.isEmpty) return widget.fallback;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth =
        (widget.logicalWidth * dpr).round().clamp(128, 1024).toInt();
    final path = widget.candidates[_candidateIndex];
    return Image.asset(
      path,
      key: ValueKey(path),
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      filterQuality: FilterQuality.medium,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [widget.fallback, child],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        _tryNextCandidate();
        return widget.fallback;
      },
    );
  }
}

/// 성장 연재 화면에서 다섯 단계를 한눈에 비교하는 정적 미리보기.
/// idle controller를 만들지 않아 여러 개를 나란히 둬도 프레임 비용이 늘지 않는다.
class PlantStagePreview extends StatelessWidget {
  const PlantStagePreview({
    super.key,
    required this.stage,
    this.form,
    this.secondaryForm,
    this.speciesCode = 'basic_sprout',
    this.speciesName,
    this.growthVisual,
    this.size = 48,
  });

  final int stage;
  final PlantGrowthForm? form;
  final PlantGrowthForm? secondaryForm;
  final String speciesCode;
  final String? speciesName;
  final PlantGrowthVisual? growthVisual;
  final double size;

  @override
  Widget build(BuildContext context) {
    final clamped = stage.clamp(1, 5).toInt();
    final visual =
        growthVisual ?? PlantGrowthVisual.fallback(speciesCode: speciesCode);
    final fallback = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        size: Size.square(size),
        isComplex: true,
        willChange: false,
        painter: PlantPainter(
          stage: clamped,
          expression: PlantExpression.neutral,
          form: clamped >= 2 ? form : null,
          secondaryForm: clamped >= 4 ? secondaryForm : null,
          speciesCode: speciesCode,
          growthVisual: visual,
        ),
      ),
    );
    final candidates = PlantGrowthAssetResolver.candidates(
      speciesCode: speciesCode,
      stage: clamped,
      form: clamped >= 2 ? form : null,
      secondaryForm: clamped >= 4 ? secondaryForm : null,
      visual: visual,
    );
    return Semantics(
      image: true,
      label:
          '${speciesName?.trim().isNotEmpty == true ? speciesName!.trim() : '식물'} '
          '${plantStageName(clamped)} 모습 미리보기, ${visual.vesselLabel}',
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: size,
            child: _RasterPlantArtwork(
              candidates: candidates,
              fallback: fallback,
              logicalWidth: size,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlantIdleMotion {
  const _PlantIdleMotion({
    required this.duration,
    this.dx = 0,
    this.dy = 0,
    this.rotation = 0,
    this.scaleX = 0,
    this.scaleY = 0,
  });

  final Duration duration;
  final double dx;
  final double dy;
  final double rotation;
  final double scaleX;
  final double scaleY;

  static _PlantIdleMotion forStage(
    int stage, {
    PlantGrowthForm? form,
    String speciesCode = 'basic_sprout',
  }) {
    final clamped = stage.clamp(1, 5).toInt();
    final stageMotion = switch (clamped) {
      1 => const _PlantIdleMotion(
          duration: Duration(milliseconds: 3400),
          scaleX: .004,
          scaleY: .008,
        ),
      2 => const _PlantIdleMotion(
          duration: Duration(milliseconds: 2600),
          rotation: .012,
          scaleY: .005,
        ),
      3 => const _PlantIdleMotion(
          duration: Duration(milliseconds: 2100),
          dy: -1.8,
          scaleX: .005,
          scaleY: .009,
        ),
      4 => const _PlantIdleMotion(
          duration: Duration(milliseconds: 2300),
          dy: -1.2,
          rotation: -.008,
          scaleY: .007,
        ),
      _ => _forForm(form),
    };
    return stageMotion._withCharacterSignature(
      speciesCode,
      stage: clamped,
    );
  }

  _PlantIdleMotion _withCharacterSignature(
    String speciesCode, {
    required int stage,
  }) {
    final slug = PlantGrowthAssetResolver._slug(speciesCode);
    final signature = switch (slug) {
      'baby-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 1800),
          dy: -1.8,
          scaleX: .008,
          scaleY: -.004,
        ),
      'handsome-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 2600),
          dx: .5,
          rotation: .005,
        ),
      'pretty-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 2100),
          dy: -.6,
          rotation: .007,
          scaleX: .003,
          scaleY: .003,
        ),
      'tsundere-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 2300),
          dx: .9,
          rotation: -.009,
        ),
      'zombie-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 3600),
          dx: 1.1,
          rotation: .014,
          scaleY: -.004,
        ),
      'gumiho-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 3000),
          dy: -1.4,
          rotation: .006,
          scaleX: .004,
          scaleY: .004,
        ),
      'ninja-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 1700),
          dx: 1.6,
          rotation: -.014,
          scaleX: -.006,
        ),
      'magical-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 2800),
          dy: -1.8,
          rotation: .004,
          scaleX: .004,
          scaleY: .004,
        ),
      'aloof-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 3900),
          dx: .35,
          rotation: -.004,
        ),
      'student-pot' => const _PlantIdleMotion(
          duration: Duration(milliseconds: 2800),
          dy: -.7,
          rotation: .003,
        ),
      _ => null,
    };
    if (signature == null) return this;
    final strength = switch (stage) {
      1 => .30,
      2 => .45,
      3 => .65,
      4 => .82,
      _ => 1.0,
    };
    return _PlantIdleMotion(
      duration: signature.duration,
      dx: dx + signature.dx * strength,
      dy: dy + signature.dy * strength,
      rotation: rotation + signature.rotation * strength,
      scaleX: scaleX + signature.scaleX * strength,
      scaleY: scaleY + signature.scaleY * strength,
    );
  }

  static _PlantIdleMotion _forForm(PlantGrowthForm? form) => switch (form) {
        PlantGrowthForm.sunny => const _PlantIdleMotion(
            duration: Duration(milliseconds: 1900),
            dy: -2.2,
            scaleX: .006,
            scaleY: .009,
          ),
        PlantGrowthForm.rainy => const _PlantIdleMotion(
            duration: Duration(milliseconds: 3100),
            dx: .8,
            rotation: .012,
          ),
        PlantGrowthForm.ember => const _PlantIdleMotion(
            duration: Duration(milliseconds: 1250),
            dy: -1.5,
            scaleY: .008,
          ),
        PlantGrowthForm.moonlit => const _PlantIdleMotion(
            duration: Duration(milliseconds: 3800),
            scaleX: .006,
            scaleY: .014,
          ),
        PlantGrowthForm.sparkling => const _PlantIdleMotion(
            duration: Duration(milliseconds: 1650),
            dx: 1.2,
            rotation: -.018,
          ),
        PlantGrowthForm.mosaic => const _PlantIdleMotion(
            duration: Duration(milliseconds: 2700),
            dx: .7,
            dy: -.8,
            rotation: .007,
            scaleY: .006,
          ),
        null => const _PlantIdleMotion(
            duration: Duration(milliseconds: 3000),
            dy: -.7,
            scaleY: .004,
          ),
      };
}

class PlantPainter extends CustomPainter {
  const PlantPainter({
    required this.stage,
    required this.expression,
    this.form,
    this.secondaryForm,
    this.speciesCode = 'basic_sprout',
    this.growthVisual,
  });

  final int stage;
  final PlantExpression expression;
  final PlantGrowthForm? form;
  final PlantGrowthForm? secondaryForm;
  final String speciesCode;
  final PlantGrowthVisual? growthVisual;

  PlantGrowthVisual get _visual =>
      growthVisual ?? PlantGrowthVisual.fallback(speciesCode: speciesCode);

  static const _ink = Color(0xFF493B32);
  static const _inkSoft = Color(0x99493B32);
  static const _pot = Color(0xFFC87955);
  static const _potLight = Color(0xFFD99570);
  static const _potShadow = Color(0xFFA95F45);
  static const _soil = Color(0xFF69503E);
  static const _seed = Color(0xFF9A7149);
  static const _seedLight = Color(0xFFC49A68);
  static const _seedShadow = Color(0xFF755137);

  _PlantGrowthPalette get _palette => switch (stage >= 2 ? form : null) {
        PlantGrowthForm.sunny => const _PlantGrowthPalette(
            stem: Color(0xFF5E874B),
            leaf: Color(0xFF7FAE58),
            leafLight: Color(0xFFA9C96A),
            leafShadow: Color(0xFF547844),
            petal: Color(0xFFF4C94E),
            petalLight: Color(0xFFFFE789),
            petalShadow: Color(0xFFD99A37),
            center: Color(0xFFB96F37),
            centerShadow: Color(0xFF8E4E31),
          ),
        PlantGrowthForm.rainy => const _PlantGrowthPalette(
            stem: Color(0xFF567873),
            leaf: Color(0xFF6C9A9E),
            leafLight: Color(0xFF9DC1BD),
            leafShadow: Color(0xFF476B73),
            petal: Color(0xFF789BC2),
            petalLight: Color(0xFFAEC8DE),
            petalShadow: Color(0xFF586F9B),
            center: Color(0xFFDFD5B7),
            centerShadow: Color(0xFF9F9A91),
          ),
        PlantGrowthForm.ember => const _PlantGrowthPalette(
            stem: Color(0xFF6A7545),
            leaf: Color(0xFF82904A),
            leafLight: Color(0xFFA5A95A),
            leafShadow: Color(0xFF595D38),
            petal: Color(0xFFE66048),
            petalLight: Color(0xFFF58A52),
            petalShadow: Color(0xFFB73E3C),
            center: Color(0xFFF2B544),
            centerShadow: Color(0xFFC96F32),
          ),
        PlantGrowthForm.moonlit => const _PlantGrowthPalette(
            stem: Color(0xFF53656B),
            leaf: Color(0xFF687989),
            leafLight: Color(0xFF9CA9B6),
            leafShadow: Color(0xFF444B61),
            petal: Color(0xFF7775B5),
            petalLight: Color(0xFFB1ADD5),
            petalShadow: Color(0xFF565484),
            center: Color(0xFFD8D3BC),
            centerShadow: Color(0xFF9693A0),
          ),
        PlantGrowthForm.sparkling => const _PlantGrowthPalette(
            stem: Color(0xFF4D7A68),
            leaf: Color(0xFF5B9B82),
            leafLight: Color(0xFF8FD2AC),
            leafShadow: Color(0xFF3C6D63),
            petal: Color(0xFFE879A3),
            petalLight: Color(0xFFFFB4C9),
            petalShadow: Color(0xFFB95885),
            center: Color(0xFFF2D567),
            centerShadow: Color(0xFFBFA145),
          ),
        PlantGrowthForm.mosaic => const _PlantGrowthPalette(
            stem: Color(0xFF58755B),
            leaf: Color(0xFF719366),
            leafLight: Color(0xFF91AD7E),
            leafShadow: Color(0xFF4C704A),
            petal: Color(0xFFE88A87),
            petalLight: Color(0xFF8EB7B3),
            petalShadow: Color(0xFF8E7096),
            center: Color(0xFFE0B34F),
            centerShadow: Color(0xFF9D7040),
          ),
        null => const _PlantGrowthPalette(
            stem: Color(0xFF557B4F),
            leaf: Color(0xFF719366),
            leafLight: Color(0xFF91AD7E),
            leafShadow: Color(0xFF4C704A),
            petal: Color(0xFFE88A87),
            petalLight: Color(0xFFF2AAA2),
            petalShadow: Color(0xFFBE686B),
            center: Color(0xFFE0B34F),
            centerShadow: Color(0xFFB98335),
          ),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 180;
    final dx = (size.width - 180 * scale) / 2;
    final dy = (size.height - 180 * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    _drawGroundShadow(canvas);
    _drawVesselBack(canvas);
    _drawGrowthAura(canvas);
    switch (stage) {
      case 1:
        _drawSeedStage(canvas);
      case 2:
        _drawSproutStage(canvas);
      case 3:
        _drawStemStage(canvas);
      case 4:
        _drawBloomStage(canvas, full: false);
      case 5:
        _drawBloomStage(canvas, full: true);
    }
    _drawSecondaryAccent(canvas);
    if (expression == PlantExpression.acknowledged) {
      _drawAcknowledgementMark(canvas);
    }
    _drawPot(canvas);
    _drawRarityEffect(canvas);
    canvas.restore();
  }

  void _drawGroundShadow(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(90, 174), width: 82, height: 12),
      Paint()..color = _ink.withAlpha(38),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(90, 173), width: 57, height: 7),
      Paint()..color = _ink.withAlpha(24),
    );
  }

  void _drawGrowthAura(Canvas canvas) {
    if (stage < 3 || form == null) return;
    final top = stage == 3 ? 57.0 : 46.0;
    final stroke = Paint()
      ..color = _palette.petalLight.withAlpha(175)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (form!) {
      case PlantGrowthForm.sunny:
        final center = Offset(90, top);
        for (var index = 0; index < 8; index++) {
          final angle = index * math.pi / 4;
          canvas.drawLine(
            center + Offset(math.cos(angle) * 28, math.sin(angle) * 24),
            center + Offset(math.cos(angle) * 36, math.sin(angle) * 31),
            stroke,
          );
        }
      case PlantGrowthForm.rainy:
        for (final point in [
          Offset(49, top + 8),
          Offset(132, top + 20),
          Offset(45, top + 55),
        ]) {
          final drop = Path()
            ..moveTo(point.dx, point.dy - 5)
            ..quadraticBezierTo(
                point.dx - 5, point.dy + 2, point.dx, point.dy + 6)
            ..quadraticBezierTo(
                point.dx + 5, point.dy + 2, point.dx, point.dy - 5);
          canvas.drawPath(drop, stroke);
        }
      case PlantGrowthForm.ember:
        for (final point in [Offset(48, top + 48), Offset(133, top + 33)]) {
          final flame = Path()
            ..moveTo(point.dx, point.dy + 8)
            ..quadraticBezierTo(
                point.dx - 8, point.dy, point.dx - 1, point.dy - 11)
            ..quadraticBezierTo(
                point.dx + 1, point.dy - 3, point.dx + 7, point.dy - 16)
            ..quadraticBezierTo(
                point.dx + 11, point.dy, point.dx, point.dy + 8);
          canvas.drawPath(flame, stroke..color = _palette.petal.withAlpha(190));
        }
      case PlantGrowthForm.moonlit:
        canvas.drawArc(
          Rect.fromCenter(center: Offset(91, top + 2), width: 78, height: 68),
          -math.pi * .72,
          math.pi * 1.35,
          false,
          stroke,
        );
        canvas.drawCircle(
            Offset(132, top + 35), 2.6, Paint()..color = _palette.petalLight);
      case PlantGrowthForm.sparkling:
        for (final point in [
          Offset(47, top + 5),
          Offset(137, top + 26),
          Offset(54, top + 65),
        ]) {
          canvas.drawLine(
              point.translate(-5, 0), point.translate(5, 0), stroke);
          canvas.drawLine(
              point.translate(0, -5), point.translate(0, 5), stroke);
        }
      case PlantGrowthForm.mosaic:
        final colors = [_palette.petal, _palette.petalLight, _palette.center];
        for (var index = 0; index < colors.length; index++) {
          final angle = index * math.pi * 2 / colors.length - math.pi / 2;
          canvas.drawCircle(
            Offset(90 + math.cos(angle) * 43, top + 18 + math.sin(angle) * 35),
            3.4,
            Paint()..color = colors[index].withAlpha(205),
          );
        }
    }
  }

  void _drawSecondaryAccent(Canvas canvas) {
    final secondary = secondaryForm;
    if (stage < 4 || secondary == null || secondary == form) return;
    final accent = switch (secondary) {
      PlantGrowthForm.sunny => const Color(0xFFF4C94E),
      PlantGrowthForm.rainy => const Color(0xFF789BC2),
      PlantGrowthForm.ember => const Color(0xFFE66048),
      PlantGrowthForm.moonlit => const Color(0xFF7775B5),
      PlantGrowthForm.sparkling => const Color(0xFFE879A3),
      PlantGrowthForm.mosaic => const Color(0xFF719366),
    };
    final fill = Paint()..color = accent.withAlpha(225);
    final stroke = Paint()
      ..color = _ink.withAlpha(175)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    const points = [Offset(59, 83), Offset(118, 72), Offset(103, 105)];
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      switch (secondary) {
        case PlantGrowthForm.sunny:
          canvas.drawCircle(point, 3.1, fill);
          for (var ray = 0; ray < 4; ray++) {
            final angle = ray * math.pi / 2;
            canvas.drawLine(
              point + Offset(math.cos(angle) * 4.7, math.sin(angle) * 4.7),
              point + Offset(math.cos(angle) * 7.0, math.sin(angle) * 7.0),
              stroke,
            );
          }
        case PlantGrowthForm.rainy:
          final drop = Path()
            ..moveTo(point.dx, point.dy - 5)
            ..quadraticBezierTo(
              point.dx - 4,
              point.dy + 1,
              point.dx,
              point.dy + 5,
            )
            ..quadraticBezierTo(
              point.dx + 4,
              point.dy + 1,
              point.dx,
              point.dy - 5,
            );
          canvas.drawPath(drop, fill);
          canvas.drawPath(drop, stroke);
        case PlantGrowthForm.ember:
          final flame = Path()
            ..moveTo(point.dx, point.dy + 5)
            ..quadraticBezierTo(
              point.dx - 4,
              point.dy,
              point.dx + 1,
              point.dy - 6,
            )
            ..quadraticBezierTo(
              point.dx + 5,
              point.dy,
              point.dx,
              point.dy + 5,
            );
          canvas.drawPath(flame, fill);
          canvas.drawPath(flame, stroke);
        case PlantGrowthForm.moonlit:
          canvas.drawArc(
            Rect.fromCircle(center: point, radius: 5),
            -.75 * math.pi,
            1.45 * math.pi,
            false,
            stroke..color = accent,
          );
        case PlantGrowthForm.sparkling:
          canvas.drawLine(
              point.translate(-5, 0), point.translate(5, 0), stroke);
          canvas.drawLine(
              point.translate(0, -5), point.translate(0, 5), stroke);
          canvas.drawCircle(point, 2, fill);
        case PlantGrowthForm.mosaic:
          canvas.drawCircle(point, 3.6, fill);
          canvas.drawCircle(point.translate(4.2, -2.8), 2.3,
              Paint()..color = const Color(0xFFE88A87));
      }
    }
  }

  void _drawVesselBack(Canvas canvas) {
    final style = _visual.vesselStyle;
    final isGlass = style == 'sunbeam_bell_jar' || style == 'glass_pod';
    final isTube = style == 'crystal_growth_tube' || style == 'culture_tube';
    if (stage > 3 || (!isGlass && !isTube)) {
      return;
    }
    final rect = isTube
        ? const Rect.fromLTWH(50, 30, 80, 139)
        : const Rect.fromLTWH(58, 65, 64, 104);
    final radius = isTube ? 38.0 : 29.0;
    final glass = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      glass,
      Paint()
        ..color = (isTube ? const Color(0xFFB9EE84) : const Color(0xFFB9E0FD))
            .withAlpha(38),
    );
    canvas.drawRRect(
      glass,
      Paint()
        ..color = _ink.withAlpha(125)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isTube ? 2.8 : 2.2,
    );
    canvas.drawArc(
      Rect.fromLTWH(
          rect.left + 8, rect.top + 8, rect.width * .38, rect.height - 16),
      math.pi * .7,
      math.pi * .55,
      false,
      Paint()
        ..color = Colors.white.withAlpha(145)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawPot(Canvas canvas) {
    switch (_visual.vesselStyle) {
      case 'ribbed_desert_incubator' || 'stone_bowl':
        _drawStoneBowl(canvas);
      case 'sunbeam_bell_jar' || 'glass_pod':
        _drawGlassPod(canvas);
      case 'crystal_growth_tube' || 'culture_tube':
        _drawCultureTube(canvas);
      default:
        _drawTerracottaPot(canvas);
    }
  }

  void _drawTerracottaPot(Canvas canvas) {
    final body = Path()
      ..moveTo(61, 137)
      ..quadraticBezierTo(62, 157, 68, 170)
      ..quadraticBezierTo(90, 178, 112, 170)
      ..quadraticBezierTo(118, 157, 119, 137)
      ..close();
    _fillPath(canvas, body, _pot);

    final bodyShade = Path()
      ..moveTo(104, 139)
      ..quadraticBezierTo(112, 151, 108, 169)
      ..quadraticBezierTo(115, 166, 119, 137)
      ..close();
    canvas.drawPath(bodyShade, Paint()..color = _potShadow);

    final bodyLight = Path()
      ..moveTo(67, 141)
      ..quadraticBezierTo(69, 156, 74, 163)
      ..quadraticBezierTo(78, 165, 80, 162)
      ..quadraticBezierTo(75, 151, 76, 141)
      ..close();
    canvas.drawPath(bodyLight, Paint()..color = _potLight.withAlpha(150));
    _strokePath(canvas, body, width: 3.4);

    final rim = RRect.fromRectAndRadius(
      const Rect.fromLTWH(55, 126, 70, 18),
      const Radius.circular(8),
    );
    canvas.drawRRect(rim, Paint()..color = _potLight);
    canvas.drawOval(
      const Rect.fromLTWH(61, 127, 58, 11),
      Paint()..color = _soil,
    );
    canvas.drawArc(
      const Rect.fromLTWH(58, 127, 64, 16),
      .1,
      math.pi * .82,
      false,
      Paint()
        ..color = _potShadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4,
    );
    _drawSpeciesBadge(canvas);
  }

  void _drawStoneBowl(Canvas canvas) {
    const stone = Color(0xFF7D786F);
    const stoneLight = Color(0xFFA7A198);
    const stoneShadow = Color(0xFF5D5A55);
    final body = Path()
      ..moveTo(54, 136)
      ..lineTo(62, 163)
      ..lineTo(73, 173)
      ..lineTo(108, 173)
      ..lineTo(118, 162)
      ..lineTo(126, 136)
      ..close();
    _fillPath(canvas, body, stone);
    canvas.drawPath(
      Path()
        ..moveTo(91, 138)
        ..lineTo(108, 173)
        ..lineTo(118, 162)
        ..lineTo(126, 136)
        ..close(),
      Paint()..color = stoneShadow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(61, 140)
        ..lineTo(73, 167)
        ..lineTo(83, 168)
        ..lineTo(76, 140)
        ..close(),
      Paint()..color = stoneLight.withAlpha(150),
    );
    _strokePath(canvas, body, width: 3.4);
    final rim = RRect.fromRectAndRadius(
      const Rect.fromLTWH(49, 125, 82, 19),
      const Radius.circular(7),
    );
    canvas.drawRRect(rim, Paint()..color = stoneLight);
    canvas.drawOval(
      const Rect.fromLTWH(56, 127, 68, 11),
      Paint()..color = _soil,
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4,
    );
    for (final crack in const [
      [Offset(68, 149), Offset(75, 154), Offset(70, 160)],
      [Offset(110, 146), Offset(103, 151), Offset(108, 158)],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(crack[0].dx, crack[0].dy)
          ..lineTo(crack[1].dx, crack[1].dy)
          ..lineTo(crack[2].dx, crack[2].dy),
        Paint()
          ..color = _inkSoft
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
    _drawSpeciesBadge(canvas);
  }

  void _drawGlassPod(Canvas canvas) {
    const glass = Color(0xFFB9E0FD);
    const water = Color(0xFF84B9DA);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(57, 126, 66, 49),
      const Radius.circular(16),
    );
    canvas.drawRRect(body, Paint()..color = glass.withAlpha(125));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(62, 143, 56, 27),
        const Radius.circular(11),
      ),
      Paint()..color = water.withAlpha(135),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawArc(
      const Rect.fromLTWH(64, 131, 18, 35),
      math.pi * .72,
      math.pi * .5,
      false,
      Paint()
        ..color = Colors.white.withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    final collar = RRect.fromRectAndRadius(
      const Rect.fromLTWH(53, 123, 74, 16),
      const Radius.circular(8),
    );
    canvas.drawRRect(collar, Paint()..color = glass.withAlpha(215));
    canvas.drawOval(
      const Rect.fromLTWH(60, 125, 60, 10),
      Paint()..color = _soil,
    );
    canvas.drawRRect(
      collar,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    _drawSpeciesBadge(canvas);
  }

  void _drawCultureTube(Canvas canvas) {
    const glass = Color(0xFFB9EE84);
    const ring = Color(0xFFFAED27);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(54, 122, 72, 54),
      const Radius.circular(26),
    );
    canvas.drawRRect(body, Paint()..color = glass.withAlpha(105));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(59, 143, 62, 28),
        const Radius.circular(13),
      ),
      Paint()..color = glass.withAlpha(125),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(49, 122, 82, 15),
        const Radius.circular(7),
      ),
      Paint()..color = ring,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(49, 122, 82, 15),
        const Radius.circular(7),
      ),
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    _drawSpeciesBadge(canvas);
  }

  void _drawRarityEffect(Canvas canvas) {
    if (_visual.rarityEffect == 'none') return;
    final color = _visual.rarityEffect == 'prismatic'
        ? const Color(0xFFB9E0FD)
        : _visual.rarityEffect == 'warm_dust_glint'
            ? const Color(0xFFD9A15B)
            : const Color(0xFFFAED27);
    final points = _visual.rarityEffect == 'prismatic'
        ? const [Offset(45, 64), Offset(137, 85), Offset(132, 128)]
        : const [Offset(49, 112), Offset(132, 105)];
    final stroke = Paint()
      ..color = color.withAlpha(210)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final point in points) {
      canvas.drawLine(point.translate(-4, 0), point.translate(4, 0), stroke);
      canvas.drawLine(point.translate(0, -4), point.translate(0, 4), stroke);
    }
  }

  void _drawSpeciesBadge(Canvas canvas) {
    final center = const Offset(90, 156);
    final badge = Paint()
      ..color = _inkSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (speciesCode) {
      case 'cactus':
        canvas.drawLine(center.translate(0, -6), center.translate(0, 6), badge);
        canvas.drawLine(
            center.translate(0, -1), center.translate(-4, -4), badge);
        canvas.drawLine(
            center.translate(-4, -4), center.translate(-4, -1), badge);
        canvas.drawLine(center.translate(0, 2), center.translate(4, -1), badge);
        canvas.drawLine(center.translate(4, -1), center.translate(4, 2), badge);
      case 'sunflower':
        canvas.drawCircle(center, 3.2, badge);
        for (var index = 0; index < 8; index++) {
          final angle = index * math.pi / 4;
          canvas.drawLine(
            center + Offset(math.cos(angle) * 5, math.sin(angle) * 5),
            center + Offset(math.cos(angle) * 7, math.sin(angle) * 7),
            badge,
          );
        }
      default:
        canvas.drawLine(center.translate(0, 6), center.translate(0, -1), badge);
        canvas.drawArc(
          Rect.fromCenter(
              center: center.translate(-3, -3), width: 7, height: 5),
          .15,
          math.pi,
          false,
          badge,
        );
        canvas.drawArc(
          Rect.fromCenter(center: center.translate(3, -4), width: 7, height: 5),
          math.pi,
          math.pi,
          false,
          badge,
        );
    }
  }

  void _drawSeedStage(Canvas canvas) {
    switch (_visual.seedShape) {
      case 'spined_star_seed' || 'thorn_star':
        _drawSpinedStarSeed(canvas);
      case 'striped_sun_seed' || 'striped_drop':
        _drawStripedSunSeed(canvas);
      case 'crystal_seed' || 'crystal':
        _drawCrystalSeed(canvas);
      default:
        _drawBeanSeed(canvas);
    }
  }

  void _drawBeanSeed(Canvas canvas) {
    final seed = Path()
      ..moveTo(74, 126)
      ..cubicTo(69, 113, 75, 99, 89, 96)
      ..cubicTo(103, 93, 113, 104, 108, 116)
      ..cubicTo(104, 126, 89, 132, 74, 126)
      ..close();
    _fillPath(canvas, seed, _seed);
    canvas.drawPath(
      Path()
        ..moveTo(94, 97)
        ..cubicTo(108, 101, 110, 113, 103, 122)
        ..cubicTo(99, 126, 95, 127, 92, 128)
        ..cubicTo(100, 115, 100, 105, 94, 97)
        ..close(),
      Paint()..color = _seedShadow,
    );
    canvas.drawArc(
      const Rect.fromLTWH(75, 99, 25, 19),
      3.55,
      1.35,
      false,
      Paint()
        ..color = _seedLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    _strokePath(canvas, seed, width: 3.2);
    if (_visual.seedShape == 'heart_speck_seed') {
      canvas.drawPath(
        Path()
          ..moveTo(90, 106)
          ..cubicTo(82, 101, 85, 96, 90, 100)
          ..cubicTo(95, 96, 99, 101, 90, 106)
          ..close(),
        Paint()..color = _seedLight,
      );
    } else {
      canvas.drawCircle(
        const Offset(90, 102),
        2.5,
        Paint()..color = _seedLight,
      );
    }
    _drawFace(canvas, const Offset(89, 114), 6.2);
  }

  void _drawSpinedStarSeed(Canvas canvas) {
    const center = Offset(90, 113);
    final seed = Path();
    for (var index = 0; index < 16; index++) {
      final angle = -math.pi / 2 + index * math.pi / 8;
      final radius = index.isEven ? 19.0 : 13.0;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (index == 0) {
        seed.moveTo(point.dx, point.dy);
      } else {
        seed.lineTo(point.dx, point.dy);
      }
    }
    seed.close();
    _fillPath(canvas, seed, const Color(0xFF78935E));
    canvas.drawCircle(
        center.translate(4, 4), 10, Paint()..color = const Color(0xFF526F4A));
    _strokePath(canvas, seed, width: 3);
    for (var index = 0; index < 4; index++) {
      final angle = index * math.pi / 2 + math.pi / 4;
      canvas.drawLine(
        center + Offset(math.cos(angle) * 7, math.sin(angle) * 7),
        center + Offset(math.cos(angle) * 12, math.sin(angle) * 12),
        Paint()
          ..color = const Color(0xFFB8C98C)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    _drawFace(canvas, center.translate(0, 1), 5.8);
  }

  void _drawStripedSunSeed(Canvas canvas) {
    const center = Offset(90, 112);
    final seed = Path()
      ..moveTo(90, 91)
      ..cubicTo(104, 99, 105, 119, 90, 132)
      ..cubicTo(75, 119, 76, 99, 90, 91)
      ..close();
    _fillPath(canvas, seed, const Color(0xFF40362F));
    canvas.save();
    canvas.clipPath(seed);
    for (final dx in [82.0, 88.0, 94.0, 100.0]) {
      canvas.drawLine(
        Offset(dx, 91),
        Offset(dx - 3, 132),
        Paint()
          ..color = const Color(0xFFD9C49A)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
    _strokePath(canvas, seed, width: 3);
    _drawFace(canvas, center.translate(0, 3), 5.7);
  }

  void _drawCrystalSeed(Canvas canvas) {
    const center = Offset(90, 112);
    final seed = Path()
      ..moveTo(90, 89)
      ..lineTo(107, 106)
      ..lineTo(99, 130)
      ..lineTo(81, 130)
      ..lineTo(73, 106)
      ..close();
    _fillPath(canvas, seed, const Color(0xFFB9E0FD));
    canvas.drawPath(
      Path()
        ..moveTo(90, 89)
        ..lineTo(90, 130)
        ..lineTo(107, 106)
        ..close(),
      Paint()..color = const Color(0xFF78A9CE).withAlpha(180),
    );
    canvas.drawLine(
      const Offset(80, 104),
      const Offset(88, 96),
      Paint()
        ..color = Colors.white.withAlpha(210)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    _strokePath(canvas, seed, width: 3);
    _drawFace(canvas, center.translate(0, 5), 5.5);
  }

  void _drawSproutStage(Canvas canvas) {
    _drawCrackedSeedShell(canvas);
    _drawStem(canvas, const Offset(90, 133), const Offset(90, 87), width: 5);
    _drawLeaf(canvas, const Offset(90, 102), length: 34, left: true);
    _drawLeaf(canvas, const Offset(90, 98), length: 34, left: false);
    _drawClayBud(canvas, const Offset(90, 82), 14);
  }

  void _drawCrackedSeedShell(Canvas canvas) {
    final shellColor = switch (_visual.seedShape) {
      'spined_star_seed' || 'thorn_star' => const Color(0xFF78935E),
      'striped_sun_seed' || 'striped_drop' => const Color(0xFF51463D),
      'crystal_seed' || 'crystal' => const Color(0xFF8FC5E8),
      _ => _seed,
    };
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final left = Path()
      ..moveTo(68, 127)
      ..quadraticBezierTo(74, 118, 86, 124)
      ..lineTo(80, 132)
      ..quadraticBezierTo(72, 133, 68, 127)
      ..close();
    final right = Path()
      ..moveTo(94, 124)
      ..quadraticBezierTo(106, 118, 112, 128)
      ..quadraticBezierTo(105, 134, 98, 132)
      ..close();
    canvas.drawPath(left, Paint()..color = shellColor);
    canvas.drawPath(right, Paint()..color = shellColor);
    canvas.drawPath(left, stroke);
    canvas.drawPath(right, stroke);
  }

  void _drawStemStage(Canvas canvas) {
    switch (form) {
      case PlantGrowthForm.sunny:
        _drawStem(canvas, const Offset(90, 133), const Offset(90, 57),
            width: 6.2);
        _drawLeaf(canvas, const Offset(90, 112), length: 43, left: true);
        _drawLeaf(canvas, const Offset(90, 108), length: 43, left: false);
        _drawLeaf(canvas, const Offset(90, 84), length: 34, left: true);
        _drawLeaf(canvas, const Offset(90, 82), length: 34, left: false);
        _drawClayBud(canvas, const Offset(90, 54), 18);
      case PlantGrowthForm.rainy:
        _drawStem(canvas, const Offset(90, 133), const Offset(84, 63),
            width: 4.8);
        _drawLeaf(canvas, const Offset(88, 113), length: 40, left: true);
        _drawLeaf(canvas, const Offset(86, 98), length: 43, left: false);
        _drawLeaf(canvas, const Offset(85, 82), length: 31, left: true);
        _drawClayBud(canvas, const Offset(84, 60), 16);
      case PlantGrowthForm.ember:
        _drawStem(canvas, const Offset(90, 133), const Offset(91, 56),
            width: 8);
        _drawStem(canvas, const Offset(89, 103), const Offset(68, 82),
            width: 4.5);
        _drawStem(canvas, const Offset(92, 98), const Offset(115, 76),
            width: 4.5);
        _drawLeaf(canvas, const Offset(88, 114), length: 42, left: true);
        _drawLeaf(canvas, const Offset(93, 107), length: 42, left: false);
        _drawLeaf(canvas, const Offset(90, 82), length: 35, left: true);
        _drawLeaf(canvas, const Offset(92, 78), length: 35, left: false);
        _drawClayBud(canvas, const Offset(91, 53), 19);
      case PlantGrowthForm.moonlit:
        _drawStem(canvas, const Offset(90, 133), const Offset(94, 48),
            width: 4.5);
        _drawLeaf(canvas, const Offset(91, 111), length: 34, left: true);
        _drawLeaf(canvas, const Offset(92, 91), length: 36, left: false);
        _drawLeaf(canvas, const Offset(93, 71), length: 29, left: true);
        _drawClayBud(canvas, const Offset(94, 46), 16);
      case PlantGrowthForm.sparkling:
        _drawStem(canvas, const Offset(90, 133), const Offset(98, 58),
            width: 5.4);
        _drawStem(canvas, const Offset(92, 104), const Offset(68, 79),
            width: 3.8);
        _drawLeaf(canvas, const Offset(91, 113), length: 38, left: true);
        _drawLeaf(canvas, const Offset(93, 100), length: 44, left: false);
        _drawLeaf(canvas, const Offset(96, 79), length: 29, left: true);
        _drawClayBud(canvas, const Offset(98, 55), 17);
      case PlantGrowthForm.mosaic:
        _drawStem(canvas, const Offset(90, 133), const Offset(78, 62),
            width: 5.2);
        _drawStem(canvas, const Offset(91, 131), const Offset(104, 66),
            width: 5.2);
        _drawLeaf(canvas, const Offset(84, 108), length: 37, left: true);
        _drawLeaf(canvas, const Offset(97, 105), length: 41, left: false);
        _drawLeaf(canvas, const Offset(82, 84), length: 28, left: false);
        _drawClayBud(canvas, const Offset(91, 59), 18);
      case null:
        _drawStem(canvas, const Offset(90, 133), const Offset(92, 58),
            width: 5.5);
        _drawLeaf(canvas, const Offset(90, 112), length: 38, left: true);
        _drawLeaf(canvas, const Offset(91, 95), length: 38, left: false);
        _drawLeaf(canvas, const Offset(92, 78), length: 31, left: true);
        _drawClayBud(canvas, const Offset(93, 55), 17);
    }
  }

  void _drawBloomStage(Canvas canvas, {required bool full}) {
    final top = switch (form) {
      PlantGrowthForm.rainy => const Offset(84, 52),
      PlantGrowthForm.moonlit => const Offset(94, 39),
      PlantGrowthForm.sparkling => const Offset(98, 47),
      PlantGrowthForm.mosaic => const Offset(91, 46),
      _ => const Offset(90, 45),
    };
    final width = switch (form) {
      PlantGrowthForm.ember => 8.2,
      PlantGrowthForm.rainy || PlantGrowthForm.moonlit => 4.8,
      _ => 5.8,
    };
    _drawStem(canvas, const Offset(90, 133), top.translate(0, 4), width: width);
    if (form == PlantGrowthForm.ember) {
      _drawStem(canvas, const Offset(90, 107), const Offset(62, 83),
          width: 4.6);
      _drawStem(canvas, const Offset(91, 102), const Offset(121, 78),
          width: 4.6);
    } else if (form == PlantGrowthForm.mosaic) {
      _drawStem(canvas, const Offset(90, 125), const Offset(68, 74),
          width: 4.2);
      _drawStem(canvas, const Offset(91, 123), const Offset(116, 76),
          width: 4.2);
    } else if (form == PlantGrowthForm.sparkling) {
      _drawStem(canvas, const Offset(91, 106), const Offset(61, 79),
          width: 3.8);
    }
    _drawLeaf(canvas, const Offset(89, 114),
        length: form == PlantGrowthForm.sunny ? 46 : 41, left: true);
    _drawLeaf(canvas, const Offset(91, 101),
        length: form == PlantGrowthForm.ember ? 47 : 42, left: false);
    _drawLeaf(canvas, const Offset(90, 81),
        length: form == PlantGrowthForm.moonlit ? 38 : 34, left: true);
    if (full) {
      _drawLeaf(canvas, const Offset(91, 70), length: 32, left: false);
      if (form != PlantGrowthForm.moonlit) {
        _drawSideBloom(canvas, const Offset(55, 78), left: true);
      }
      if (form != PlantGrowthForm.rainy) {
        _drawSideBloom(canvas, const Offset(126, 82), left: false);
      }
    }
    _drawFlower(canvas, top, full: full);
  }

  void _drawStem(
    Canvas canvas,
    Offset start,
    Offset end, {
    required double width,
  }) {
    final delta = end - start;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx - 3,
        start.dy + delta.dy * .35,
        end.dx + 4,
        end.dy - delta.dy * .2,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _palette.stem
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _palette.leafLight.withAlpha(155)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawLeaf(
    Canvas canvas,
    Offset joint, {
    required double length,
    required bool left,
  }) {
    final direction = left ? -1.0 : 1.0;
    final branchForm = stage >= 3 ? form : null;
    final tipY = switch (branchForm) {
      PlantGrowthForm.sunny => -length * .35,
      PlantGrowthForm.rainy => length * .28,
      PlantGrowthForm.ember => -length * .08,
      PlantGrowthForm.moonlit => -length * .48,
      PlantGrowthForm.sparkling => (left ? -1 : 1) * length * .3,
      PlantGrowthForm.mosaic => (left ? .2 : -.38) * length,
      null => -length * .22,
    };
    final upperLift = switch (branchForm) {
      PlantGrowthForm.rainy => .2,
      PlantGrowthForm.ember => .32,
      PlantGrowthForm.moonlit => .62,
      _ => .52,
    };
    final lowerDrop = switch (branchForm) {
      PlantGrowthForm.sunny => .38,
      PlantGrowthForm.rainy => .18,
      PlantGrowthForm.moonlit => .15,
      PlantGrowthForm.ember => .22,
      _ => .3,
    };
    final tip = joint.translate(direction * length, tipY);
    if (speciesCode == 'cactus') {
      _drawCactusPaddle(canvas, joint, tip, length: length);
      return;
    }
    if (speciesCode == 'sunflower') {
      _drawSunLeaf(canvas, joint, tip, length: length);
      return;
    }
    switch (branchForm) {
      case PlantGrowthForm.rainy:
        _drawRainLeaf(canvas, joint, tip, length: length);
        return;
      case PlantGrowthForm.ember:
        _drawEmberLeaf(canvas, joint, tip, length: length);
        return;
      case PlantGrowthForm.moonlit:
        _drawMoonLeaf(canvas, joint, tip, length: length);
        return;
      case PlantGrowthForm.sparkling:
        _drawSparkLeaf(canvas, joint, tip, length: length);
        return;
      case PlantGrowthForm.sunny || PlantGrowthForm.mosaic || null:
        break;
    }
    final path = Path()
      ..moveTo(joint.dx, joint.dy)
      ..quadraticBezierTo(
        joint.dx + direction * length * .48,
        joint.dy - length * upperLift,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(
        joint.dx + direction * length * .46,
        joint.dy + length * lowerDrop,
        joint.dx,
        joint.dy,
      )
      ..close();
    _fillPath(canvas, path, _palette.leaf);
    final shade = Path()
      ..moveTo(joint.dx, joint.dy)
      ..lineTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        joint.dx + direction * length * .45,
        joint.dy + length * .24,
        joint.dx,
        joint.dy,
      )
      ..close();
    canvas.drawPath(
      shade,
      Paint()..color = _palette.leafShadow.withAlpha(190),
    );
    _strokePath(canvas, path, width: 3);
    canvas.drawLine(
      joint,
      Offset.lerp(joint, tip, .76)!,
      Paint()
        ..color = _inkSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset.lerp(joint, tip, .52)!,
        width: length * .45,
        height: length * .28,
      ),
      left ? 3.55 : 5.2,
      .8,
      false,
      Paint()
        ..color = _palette.leafLight.withAlpha(185)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawSunLeaf(
    Canvas canvas,
    Offset joint,
    Offset tip, {
    required double length,
  }) {
    final vector = tip - joint;
    final distance = math.max(vector.distance, 1);
    final normal = Offset(-vector.dy / distance, vector.dx / distance);
    final breadth = length * .34;
    final path = Path()
      ..moveTo(joint.dx, joint.dy)
      ..cubicTo(
        joint.dx + vector.dx * .28 + normal.dx * breadth,
        joint.dy + vector.dy * .28 + normal.dy * breadth,
        tip.dx + normal.dx * breadth * .42,
        tip.dy + normal.dy * breadth * .42,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        tip.dx - normal.dx * breadth * .42,
        tip.dy - normal.dy * breadth * .42,
        joint.dx + vector.dx * .28 - normal.dx * breadth,
        joint.dy + vector.dy * .28 - normal.dy * breadth,
        joint.dx,
        joint.dy,
      )
      ..close();
    _paintSpecialLeaf(canvas, path, joint, tip, veinWidth: 1.6);
    canvas.drawCircle(
      Offset.lerp(joint, tip, .45)!,
      2,
      Paint()..color = _palette.leafLight.withAlpha(190),
    );
  }

  void _drawRainLeaf(
    Canvas canvas,
    Offset joint,
    Offset tip, {
    required double length,
  }) {
    final vector = tip - joint;
    final distance = math.max(vector.distance, 1);
    final normal = Offset(-vector.dy / distance, vector.dx / distance);
    final breadth = length * .19;
    final path = Path()
      ..moveTo(joint.dx, joint.dy)
      ..quadraticBezierTo(
        joint.dx + vector.dx * .62 + normal.dx * breadth,
        joint.dy + vector.dy * .62 + normal.dy * breadth,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(
        joint.dx + vector.dx * .5 - normal.dx * breadth,
        joint.dy + vector.dy * .5 - normal.dy * breadth,
        joint.dx,
        joint.dy,
      )
      ..close();
    _paintSpecialLeaf(canvas, path, joint, tip);
    canvas.drawCircle(
      tip.translate(0, 3),
      2.4,
      Paint()..color = _palette.petalLight.withAlpha(210),
    );
  }

  void _drawEmberLeaf(
    Canvas canvas,
    Offset joint,
    Offset tip, {
    required double length,
  }) {
    final vector = tip - joint;
    final distance = math.max(vector.distance, 1);
    final normal = Offset(-vector.dy / distance, vector.dx / distance);
    final breadth = length * .2;
    final path = Path()
      ..moveTo(joint.dx, joint.dy)
      ..lineTo(
        joint.dx + vector.dx * .44 + normal.dx * breadth,
        joint.dy + vector.dy * .44 + normal.dy * breadth,
      )
      ..lineTo(
        joint.dx + vector.dx * .65 + normal.dx * breadth * .42,
        joint.dy + vector.dy * .65 + normal.dy * breadth * .42,
      )
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(
        joint.dx + vector.dx * .58 - normal.dx * breadth,
        joint.dy + vector.dy * .58 - normal.dy * breadth,
      )
      ..close();
    _paintSpecialLeaf(canvas, path, joint, tip, outlineWidth: 3.2);
  }

  void _drawMoonLeaf(
    Canvas canvas,
    Offset joint,
    Offset tip, {
    required double length,
  }) {
    final vector = tip - joint;
    final distance = math.max(vector.distance, 1);
    final normal = Offset(-vector.dy / distance, vector.dx / distance);
    final breadth = length * .27;
    final path = Path()
      ..moveTo(joint.dx, joint.dy)
      ..cubicTo(
        joint.dx + vector.dx * .36 + normal.dx * breadth,
        joint.dy + vector.dy * .36 + normal.dy * breadth,
        tip.dx + normal.dx * breadth * .45,
        tip.dy + normal.dy * breadth * .45,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(
        joint.dx + vector.dx * .48 + normal.dx * breadth * .25,
        joint.dy + vector.dy * .48 + normal.dy * breadth * .25,
        joint.dx,
        joint.dy,
      )
      ..close();
    _paintSpecialLeaf(canvas, path, joint, tip);
  }

  void _drawSparkLeaf(
    Canvas canvas,
    Offset joint,
    Offset tip, {
    required double length,
  }) {
    final vector = tip - joint;
    final distance = math.max(vector.distance, 1);
    final normal = Offset(-vector.dy / distance, vector.dx / distance);
    final breadth = length * .22;
    final middle = Offset.lerp(joint, tip, .54)!;
    final path = Path()
      ..moveTo(joint.dx, joint.dy)
      ..lineTo(middle.dx + normal.dx * breadth, middle.dy + normal.dy * breadth)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(middle.dx - normal.dx * breadth, middle.dy - normal.dy * breadth)
      ..close();
    _paintSpecialLeaf(canvas, path, joint, tip);
  }

  void _paintSpecialLeaf(
    Canvas canvas,
    Path path,
    Offset joint,
    Offset tip, {
    double outlineWidth = 3,
    double veinWidth = 1.35,
  }) {
    _fillPath(canvas, path, _palette.leaf);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(
      tip.translate(5, 5),
      14,
      Paint()..color = _palette.leafShadow.withAlpha(165),
    );
    canvas.restore();
    _strokePath(canvas, path, width: outlineWidth);
    canvas.drawLine(
      joint,
      Offset.lerp(joint, tip, .8)!,
      Paint()
        ..color = _inkSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = veinWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawCactusPaddle(
    Canvas canvas,
    Offset joint,
    Offset tip, {
    required double length,
  }) {
    final vector = tip - joint;
    final distance = math.max(vector.distance, 1);
    final normal = Offset(-vector.dy / distance, vector.dx / distance);
    final breadth = length * .2;
    final path = Path()
      ..moveTo(joint.dx, joint.dy)
      ..cubicTo(
        joint.dx + vector.dx * .28 + normal.dx * breadth,
        joint.dy + vector.dy * .28 + normal.dy * breadth,
        tip.dx + normal.dx * breadth * .72,
        tip.dy + normal.dy * breadth * .72,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        tip.dx - normal.dx * breadth * .72,
        tip.dy - normal.dy * breadth * .72,
        joint.dx + vector.dx * .28 - normal.dx * breadth,
        joint.dy + vector.dy * .28 - normal.dy * breadth,
        joint.dx,
        joint.dy,
      )
      ..close();
    _fillPath(canvas, path, _palette.leaf);
    _strokePath(canvas, path, width: 3);

    final spine = Paint()
      ..color = _inkSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final progress in [.35, .58, .78]) {
      final point = Offset.lerp(joint, tip, progress)!;
      final half = progress == .58 ? 3.8 : 3.0;
      canvas.drawLine(point - normal * half, point + normal * half, spine);
    }
    canvas.drawLine(
      Offset.lerp(joint, tip, .18)!,
      Offset.lerp(joint, tip, .82)!,
      Paint()
        ..color = _palette.leafLight.withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawClayBud(Canvas canvas, Offset center, double radius) {
    final shape = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    _fillPath(canvas, shape, _palette.leaf);
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(radius * .55, radius * .35),
        width: radius * 1.35,
        height: radius * 1.7,
      ),
      Paint()..color = _palette.leafShadow,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center.translate(-2, -2), radius: radius * .68),
      3.55,
      1.25,
      false,
      Paint()
        ..color = _palette.leafLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    _strokePath(canvas, shape, width: 3.2);
    _drawFace(canvas, center.translate(0, 1), radius * .38);
  }

  void _drawFlower(Canvas canvas, Offset center, {required bool full}) {
    final branchForm = form ?? PlantGrowthForm.mosaic;
    final formPetalCount = switch (branchForm) {
      PlantGrowthForm.sunny => full ? 10 : 7,
      PlantGrowthForm.rainy => full ? 6 : 4,
      PlantGrowthForm.ember => full ? 7 : 5,
      PlantGrowthForm.moonlit => full ? 5 : 4,
      PlantGrowthForm.sparkling => full ? 9 : 6,
      PlantGrowthForm.mosaic => full ? 8 : 5,
    };
    final petalCount = switch (speciesCode) {
      'sunflower' => formPetalCount + 2,
      'cactus' => math.max(5, formPetalCount - 2),
      _ => formPetalCount,
    };
    final orbit = switch (branchForm) {
      PlantGrowthForm.rainy => full ? 18.0 : 15.0,
      PlantGrowthForm.moonlit => full ? 20.0 : 17.0,
      PlantGrowthForm.sparkling => full ? 25.0 : 20.0,
      _ => full ? 23.0 : 19.0,
    };
    final basePetalLength = switch (branchForm) {
      PlantGrowthForm.sunny => full ? 34.0 : 29.0,
      PlantGrowthForm.rainy => full ? 35.0 : 30.0,
      PlantGrowthForm.ember => full ? 38.0 : 31.0,
      PlantGrowthForm.moonlit => full ? 32.0 : 27.0,
      PlantGrowthForm.sparkling => full ? 33.0 : 27.0,
      PlantGrowthForm.mosaic => full ? 31.0 : 27.0,
    };
    for (var index = 0; index < petalCount; index++) {
      final baseAngle = index * math.pi * 2 / petalCount - math.pi / 2;
      final angle = branchForm == PlantGrowthForm.rainy
          ? baseAngle + math.pi * .12
          : baseAngle;
      final petalLength = branchForm == PlantGrowthForm.sparkling
          ? basePetalLength * (index.isEven ? 1 : .65)
          : branchForm == PlantGrowthForm.mosaic
              ? basePetalLength * (.78 + (index % 3) * .12)
              : basePetalLength;
      _drawPetal(
        canvas,
        center,
        angle: angle,
        orbit: orbit,
        length: petalLength,
        color: index.isEven ? _palette.petal : _palette.petalLight,
      );
    }
    final coreRadius = speciesCode == 'sunflower'
        ? (full ? 20.0 : 17.0)
        : (full ? 16.0 : 14.0);
    final core = Path()
      ..addOval(Rect.fromCircle(center: center, radius: coreRadius));
    _fillPath(canvas, core, _palette.center);
    canvas.save();
    canvas.clipPath(core);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(coreRadius * .5, coreRadius * .4),
        width: coreRadius * 1.25,
        height: coreRadius * 1.5,
      ),
      Paint()..color = _palette.centerShadow,
    );
    canvas.restore();
    _strokePath(canvas, core, width: 3.2);
    _drawFace(canvas, center, coreRadius * .36);
    _drawBranchDetails(canvas, center, full: full);
  }

  void _drawPetal(
    Canvas canvas,
    Offset center, {
    required double angle,
    required double orbit,
    required double length,
    required Color color,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final petal = Path()
      ..moveTo(5, 0)
      ..quadraticBezierTo(length * .5, -length * .32, length, 0)
      ..quadraticBezierTo(length * .5, length * .32, 5, 0)
      ..close();
    canvas.translate(orbit - length * .42, 0);
    _fillPath(canvas, petal, color);
    canvas.drawPath(
      Path()
        ..moveTo(length * .52, 1)
        ..quadraticBezierTo(length * .7, length * .18, length * .88, 0)
        ..quadraticBezierTo(
            length * .72, length * .28, length * .45, length * .16)
        ..close(),
      Paint()..color = _palette.petalShadow.withAlpha(175),
    );
    _strokePath(canvas, petal, width: 2.8);
    canvas.drawLine(
      const Offset(8, -1),
      Offset(length * .63, -1),
      Paint()
        ..color = Colors.white.withAlpha(90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _drawSideBloom(Canvas canvas, Offset center, {required bool left}) {
    final stemStart = const Offset(90, 92);
    final stemEnd = center.translate(left ? 8 : -8, 8);
    _drawStem(canvas, stemStart, stemEnd, width: 3.5);
    for (var index = 0; index < 5; index++) {
      _drawPetal(
        canvas,
        center,
        angle: index * math.pi * 2 / 5 - math.pi / 2,
        orbit: 11,
        length: 17,
        color: index.isEven ? _palette.petal : _palette.petalLight,
      );
    }
    final core = Path()..addOval(Rect.fromCircle(center: center, radius: 7));
    _fillPath(canvas, core, _palette.center);
    _strokePath(canvas, core, width: 2.4);
  }

  void _drawBranchDetails(Canvas canvas, Offset center, {required bool full}) {
    if (stage < 4 || form == null) return;
    final stroke = Paint()
      ..color = _inkSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    switch (form!) {
      case PlantGrowthForm.sunny:
        for (final direction in [-1.0, 1.0]) {
          canvas.drawLine(
            center.translate(direction * 31, -22),
            center.translate(direction * (full ? 39 : 35), -29),
            stroke,
          );
        }
      case PlantGrowthForm.rainy:
        for (final offset in [const Offset(-25, 30), const Offset(26, 27)]) {
          final drop = Path()
            ..moveTo(center.dx + offset.dx, center.dy + offset.dy - 6)
            ..quadraticBezierTo(
              center.dx + offset.dx - 6,
              center.dy + offset.dy + 3,
              center.dx + offset.dx,
              center.dy + offset.dy + 6,
            )
            ..quadraticBezierTo(
              center.dx + offset.dx + 6,
              center.dy + offset.dy + 3,
              center.dx + offset.dx,
              center.dy + offset.dy - 6,
            );
          _fillPath(canvas, drop, _palette.petalLight);
          _strokePath(canvas, drop, width: 1.8);
        }
      case PlantGrowthForm.ember:
        final crown = Path()
          ..moveTo(center.dx - 12, center.dy - 15)
          ..lineTo(center.dx - 5, center.dy - 27)
          ..lineTo(center.dx, center.dy - 18)
          ..lineTo(center.dx + 8, center.dy - 29)
          ..lineTo(center.dx + 13, center.dy - 14);
        canvas.drawPath(crown, stroke..color = _palette.petalShadow);
      case PlantGrowthForm.moonlit:
        canvas.drawArc(
          Rect.fromCircle(center: center.translate(1, -1), radius: 10),
          -math.pi * .6,
          math.pi * 1.15,
          false,
          Paint()
            ..color = _palette.petalLight
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      case PlantGrowthForm.sparkling:
        for (final offset in [const Offset(-34, -25), const Offset(35, -13)]) {
          final point = center + offset;
          canvas.drawLine(
              point.translate(-4, 0), point.translate(4, 0), stroke);
          canvas.drawLine(
              point.translate(0, -4), point.translate(0, 4), stroke);
        }
      case PlantGrowthForm.mosaic:
        final colors = [
          const Color(0xFFF0C84B),
          const Color(0xFF799FC5),
          const Color(0xFFE36C73),
        ];
        for (var index = 0; index < colors.length; index++) {
          canvas.drawCircle(
            center.translate(-28 + index * 28, index.isEven ? -25 : 29),
            full ? 3.5 : 2.5,
            Paint()..color = colors[index],
          );
        }
    }
  }

  void _drawAcknowledgementMark(Canvas canvas) {
    final center = stage <= 2 ? const Offset(118, 76) : const Offset(130, 43);
    final paint = Paint()
      ..color = _palette.center
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center.translate(-7, 0), center.translate(7, 0), paint);
    canvas.drawLine(center.translate(0, -7), center.translate(0, 7), paint);
    canvas.drawCircle(center, 2, Paint()..color = _palette.centerShadow);
  }

  /// 1~2단계는 공통 표정, 3단계부터는 감정을 다루는 방식이 드러나는
  /// 서로 다른 눈·입 실루엣을 사용한다.
  void _drawFace(Canvas canvas, Offset center, double unit) {
    final fill = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.25, unit * .28)
      ..strokeCap = StrokeCap.round;
    final eyeOffset = unit * .95;
    final eyeY = center.dy - unit * .38;
    final branchForm = stage >= 3 ? form : null;
    final showsHappyEyes = expression == PlantExpression.happy ||
        branchForm == PlantGrowthForm.sunny;
    if (showsHappyEyes) {
      for (final direction in [-1.0, 1.0]) {
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(center.dx + direction * eyeOffset, eyeY),
            width: unit * .85,
            height: unit * .62,
          ),
          math.pi + .2,
          math.pi - .4,
          false,
          stroke,
        );
      }
    } else if (branchForm == PlantGrowthForm.rainy) {
      for (final direction in [-1.0, 1.0]) {
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(center.dx + direction * eyeOffset, eyeY),
            width: unit * .72,
            height: unit * .46,
          ),
          .2,
          math.pi - .4,
          false,
          stroke,
        );
      }
    } else if (branchForm == PlantGrowthForm.moonlit) {
      canvas.drawCircle(Offset(center.dx - eyeOffset, eyeY), unit * .2, fill);
      canvas.drawLine(
        Offset(center.dx + eyeOffset - unit * .35, eyeY),
        Offset(center.dx + eyeOffset + unit * .35, eyeY),
        stroke,
      );
    } else if (branchForm == PlantGrowthForm.mosaic) {
      canvas.drawCircle(Offset(center.dx - eyeOffset, eyeY), unit * .2, fill);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(center.dx + eyeOffset, eyeY),
          width: unit * .75,
          height: unit * .5,
        ),
        math.pi + .2,
        math.pi - .4,
        false,
        stroke,
      );
    } else {
      final eyeRadius =
          branchForm == PlantGrowthForm.sparkling ? unit * .3 : unit * .2;
      canvas.drawCircle(Offset(center.dx - eyeOffset, eyeY), unit * .2, fill);
      canvas.drawCircle(Offset(center.dx + eyeOffset, eyeY), eyeRadius, fill);
      if (branchForm == PlantGrowthForm.ember) {
        canvas.drawLine(
          Offset(center.dx - eyeOffset - unit * .45, eyeY - unit * .55),
          Offset(center.dx - eyeOffset + unit * .3, eyeY - unit * .25),
          stroke,
        );
        canvas.drawLine(
          Offset(center.dx + eyeOffset - unit * .3, eyeY - unit * .25),
          Offset(center.dx + eyeOffset + unit * .45, eyeY - unit * .55),
          stroke,
        );
      }
    }

    final mouth = Rect.fromCenter(
      center: center.translate(0, unit * .55),
      width: unit * 1.25,
      height: unit * .85,
    );
    switch (expression) {
      case PlantExpression.happy:
        canvas.drawArc(mouth, .45, math.pi - .9, false, stroke);
      case PlantExpression.sad:
        canvas.drawArc(
          mouth.translate(0, unit * .4),
          math.pi + .45,
          math.pi - .9,
          false,
          stroke,
        );
      case PlantExpression.neutral || PlantExpression.acknowledged:
        switch (branchForm) {
          case PlantGrowthForm.sunny:
            canvas.drawArc(mouth, .45, math.pi - .9, false, stroke);
          case PlantGrowthForm.rainy:
            canvas.drawArc(mouth.translate(0, -unit * .1), .2, math.pi * .6,
                false, stroke);
          case PlantGrowthForm.ember:
            canvas.drawLine(
              Offset(center.dx - unit * .5, center.dy + unit * .55),
              Offset(center.dx + unit * .55, center.dy + unit * .35),
              stroke,
            );
          case PlantGrowthForm.moonlit:
            canvas.drawCircle(
              center.translate(0, unit * .62),
              unit * .28,
              stroke,
            );
          case PlantGrowthForm.sparkling:
            canvas.drawOval(
              Rect.fromCenter(
                center: center.translate(0, unit * .6),
                width: unit * .7,
                height: unit * .9,
              ),
              stroke,
            );
          case PlantGrowthForm.mosaic:
            canvas.drawArc(mouth, .45, math.pi - .9, false, stroke);
          case null:
            canvas.drawLine(
              Offset(center.dx - unit * .42, center.dy + unit * .55),
              Offset(center.dx + unit * .42, center.dy + unit * .55),
              stroke,
            );
        }
    }
  }

  void _fillPath(Canvas canvas, Path path, Color color) {
    canvas.drawPath(path, Paint()..color = color);
  }

  void _strokePath(Canvas canvas, Path path, {required double width}) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant PlantPainter oldDelegate) {
    final previousVisual = oldDelegate._visual;
    final nextVisual = _visual;
    return oldDelegate.stage != stage ||
        oldDelegate.expression != expression ||
        oldDelegate.form != form ||
        oldDelegate.secondaryForm != secondaryForm ||
        oldDelegate.speciesCode != speciesCode ||
        previousVisual.seedShape != nextVisual.seedShape ||
        previousVisual.vesselStyle != nextVisual.vesselStyle ||
        previousVisual.rarityEffect != nextVisual.rarityEffect ||
        previousVisual.rarity != nextVisual.rarity ||
        previousVisual.assetNamespace != nextVisual.assetNamespace;
  }
}

class _PlantGrowthPalette {
  const _PlantGrowthPalette({
    required this.stem,
    required this.leaf,
    required this.leafLight,
    required this.leafShadow,
    required this.petal,
    required this.petalLight,
    required this.petalShadow,
    required this.center,
    required this.centerShadow,
  });

  final Color stem;
  final Color leaf;
  final Color leafLight;
  final Color leafShadow;
  final Color petal;
  final Color petalLight;
  final Color petalShadow;
  final Color center;
  final Color centerShadow;
}
