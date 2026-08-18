part of 'expedition_screen.dart';

/// 스테이지 안으로 들어가 걷는 타일 월드.
///
/// 완성된 배경 한 장을 움직이는 방식이 아니다. 바닥 타일, 충돌 지형, 조형물,
/// NPC/몬스터/보물/아이템, 목적 이벤트를 독립 데이터로 두고 카메라 안쪽만
/// 그린다. 그래서 맵 크기가 커져도 한 프레임의 페인트 비용은 뷰포트 크기에
/// 비례한다.
class _ExpeditionTileWorld extends ConsumerStatefulWidget {
  const _ExpeditionTileWorld({
    required this.expedition,
    required this.destination,
  });

  final ExpeditionSnapshot expedition;
  final ExpeditionNode destination;

  @override
  ConsumerState<_ExpeditionTileWorld> createState() =>
      _ExpeditionTileWorldState();
}

class _ExpeditionTileWorldState extends ConsumerState<_ExpeditionTileWorld>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late _TileField _field;
  late Offset _position;
  Offset? _stickCenter;
  Offset? _stickTouch;
  Duration _lastTick = Duration.zero;
  double _stride = 0;
  double _facing = 1;
  bool _movePending = false;
  ExpeditionCombatAudio? _steps;
  double _stepDistance = 0;
  ui.Image? _atlas;

  @override
  void initState() {
    super.initState();
    _field = _TileField.forStage(
      widget.expedition.region.code,
      widget.expedition.run.stageNo ?? 1,
    );
    _position = _field.spawn;
    _ticker = createTicker(_tick);
    unawaited(_loadAtlas());
  }

  Future<void> _loadAtlas() async {
    try {
      final bytes = await rootBundle.load(
        'assets/adventure/overworld/expedition-tile-atlas-v2.png',
      );
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      late final ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _atlas?.dispose();
        _atlas = frame.image;
      });
    } on Object catch (error) {
      // The procedural fallback keeps the stage playable if an asset bundle is
      // damaged, while CI verifies that a release bundle always has the atlas.
      debugPrint('Expedition tile atlas could not be decoded: $error');
    }
  }

  @override
  void didUpdateWidget(covariant _ExpeditionTileWorld oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expedition.region.code == widget.expedition.region.code &&
        oldWidget.expedition.run.stageNo == widget.expedition.run.stageNo) {
      return;
    }
    _field.dispose();
    _field = _TileField.forStage(
      widget.expedition.region.code,
      widget.expedition.run.stageNo ?? 1,
    );
    _position = _field.spawn;
  }

  bool get _movementEnabled =>
      widget.expedition.run.phase == 'exploring' &&
      !ref.read(expeditionControllerProvider).interactionLocked &&
      !_movePending;

  void _pointerDown(Offset local) {
    if (!_movementEnabled) return;
    setState(() {
      _stickCenter = local;
      _stickTouch = local;
    });
    _lastTick = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _pointerMove(Offset local) {
    if (_stickCenter == null) return;
    setState(() => _stickTouch = local);
  }

  void _pointerUp() {
    _ticker.stop();
    setState(() {
      _stickCenter = null;
      _stickTouch = null;
    });
  }

  void _tick(Duration elapsed) {
    final center = _stickCenter;
    final touch = _stickTouch;
    if (center == null || touch == null || !_movementEnabled) return;
    final rawSeconds = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (rawSeconds <= 0) return;
    final direction = expeditionStickVector(center, touch);
    if (direction == Offset.zero) return;
    final seconds = math.min(rawSeconds, .1);
    final delta = direction * (4.2 * seconds);
    final next = _field.slide(_position, delta);
    if (next == _position) return;
    final travelled = (next - _position).distance;
    setState(() {
      _position = next;
      _stride = (_stride + travelled * 1.75) % 2;
      if (direction.dx.abs() > .12) _facing = direction.dx.sign;
    });
    _stepDistance += travelled;
    if (_stepDistance >= .82) {
      _stepDistance = 0;
      _playStep();
    }
    if ((_position - _field.goal).distance <= 1.05) {
      unawaited(_enterDestination());
    }
  }

  void _playStep() {
    if (!ref.read(expeditionBattleSettingsProvider).sfxEnabled) return;
    _steps ??= ExpeditionCombatAudio(musicEnabled: false, sfxEnabled: true);
    unawaited(
      _steps!.play(
        ExpeditionCombatAudio.stepSoundFor(widget.destination.sceneKey),
        volume: .28,
      ),
    );
  }

  Future<void> _enterDestination() async {
    if (_movePending || !_movementEnabled) return;
    _movePending = true;
    _ticker.stop();
    try {
      final moved = await ref
          .read(expeditionControllerProvider.notifier)
          .move(widget.destination.code);
      if (moved && mounted) HapticFeedback.selectionClick();
    } finally {
      _movePending = false;
      if (mounted) _pointerUp();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _steps?.dispose();
    _atlas?.dispose();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final moving = _stickCenter != null &&
        expeditionStickVector(
              _stickCenter ?? Offset.zero,
              _stickTouch ?? Offset.zero,
            ) !=
            Offset.zero;
    final nearby = _field.nearestDiscoverable(_position);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: ColoredBox(
        color: _field.palette.voidColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final camera = _WorldCamera.follow(
              field: _field,
              player: _position,
              viewport: size,
            );
            final playerScreen = camera.project(_position);
            final visibleTiles = camera.visibleTileCount(_field);
            final visibleChunks = camera.visibleChunkCount(_field);
            const actorSize = Size(70, 82);
            return Focus(
              autofocus: true,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Semantics(
                    key: const ValueKey('tile-world-player-position'),
                    hidden: true,
                    value:
                        '${_position.dx.toStringAsFixed(2)},${_position.dy.toStringAsFixed(2)}',
                    child: const SizedBox.shrink(),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('tile-world-visible-layer'),
                        painter: _TileWorldPainter(
                          atlas: _atlas,
                          field: _field,
                          camera: camera,
                          playerY: _position.dy,
                          foreground: false,
                          pulse: _stride,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: playerScreen.dx - actorSize.width / 2,
                    top: playerScreen.dy - actorSize.height * .78,
                    width: actorSize.width,
                    height: actorSize.height,
                    child: IgnorePointer(
                      child: _PartyTrailMarker(
                        moving: moving,
                        ambient: _field.palette.actorGrade,
                        facing: _facing,
                        stride: _stride,
                        label: '월드 안의 현재 위치',
                        party: widget.expedition.party,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _TileWorldPainter(
                          atlas: _atlas,
                          field: _field,
                          camera: camera,
                          playerY: _position.dy,
                          foreground: true,
                          pulse: _stride,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Semantics(
                      label:
                          '${widget.expedition.region.name} 타일 필드. 벽과 물을 피해 ${widget.destination.name}까지 직접 걸어요.',
                      child: Listener(
                        key: const ValueKey('expedition-walk-surface'),
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _movementEnabled
                            ? (e) => _pointerDown(e.localPosition)
                            : null,
                        onPointerMove: _movementEnabled
                            ? (e) => _pointerMove(e.localPosition)
                            : null,
                        onPointerUp:
                            _movementEnabled ? (_) => _pointerUp() : null,
                        onPointerCancel:
                            _movementEnabled ? (_) => _pointerUp() : null,
                      ),
                    ),
                  ),
                  if (_stickCenter != null && _stickTouch != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _WalkStickPainter(
                            center: _stickCenter!,
                            knob: expeditionStickKnob(
                              _stickCenter!,
                              _stickTouch!,
                            ),
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _SceneHudTag(
                      icon: Icons.grid_view_rounded,
                      label: size.width < 370
                          ? '$visibleTiles/${_field.width * _field.height}칸 · $visibleChunks청크'
                          : '가시 타일 $visibleTiles/${_field.width * _field.height} · 청크 $visibleChunks',
                      color: const Color(0xFFFFE19A),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    width: size.width < 370 ? 82 : 96,
                    height: 70,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xCC151A18),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: CustomPaint(
                        key: const ValueKey('tile-world-minimap'),
                        painter: _TileMinimapPainter(
                          field: _field,
                          player: _position,
                          camera: camera,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Tooltip(
                      message: widget.destination.name,
                      child: Semantics(
                        button: true,
                        label: '${widget.destination.name} 접근성 바로가기',
                        child: Material(
                          color: const Color(0xDD193A34),
                          shape: const CircleBorder(),
                          child: InkWell(
                            key: const ValueKey('tile-world-destination'),
                            customBorder: const CircleBorder(),
                            onTap: _movementEnabled ? _enterDestination : null,
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(
                                Icons.flag_rounded,
                                color: Color(0xFFFFE19A),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (nearby != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _SceneHudTag(
                        icon: nearby.icon,
                        label: nearby.label,
                        color: nearby.color,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _TileObjectKind {
  wall,
  shelf,
  lantern,
  chest,
  item,
  npc,
  monster,
  altar,
  root,
}

enum _TileObjectLayer { staticScenery, interactable, actor }

class _TileObject {
  const _TileObject({
    required this.kind,
    required this.position,
    required this.size,
    required this.label,
    this.blocks = false,
    this.collisionSize,
  });

  final _TileObjectKind kind;
  final Offset position;
  final Size size;
  final String label;
  final bool blocks;
  final Size? collisionSize;

  _TileObjectLayer get layer => switch (kind) {
        _TileObjectKind.wall ||
        _TileObjectKind.shelf ||
        _TileObjectKind.lantern ||
        _TileObjectKind.root =>
          _TileObjectLayer.staticScenery,
        _TileObjectKind.chest ||
        _TileObjectKind.item ||
        _TileObjectKind.altar =>
          _TileObjectLayer.interactable,
        _TileObjectKind.npc ||
        _TileObjectKind.monster =>
          _TileObjectLayer.actor,
      };

  /// The sprite is anchored at its feet, not at its visual center.
  Rect get visualBounds => Rect.fromLTWH(
        position.dx - size.width / 2,
        position.dy - size.height,
        size.width,
        size.height,
      );

  /// Collision topology only covers the footprint touching the floor.
  Rect get collisionBounds {
    final footprint = collisionSize ??
        Size(
          math.max(.18, size.width * .58),
          math.max(.16, math.min(.42, size.height * .3)),
        );
    return Rect.fromCenter(
      center: position - Offset(0, footprint.height / 2),
      width: footprint.width,
      height: footprint.height,
    );
  }

  IconData get icon => switch (kind) {
        _TileObjectKind.chest => Icons.inventory_2_rounded,
        _TileObjectKind.item => Icons.diamond_rounded,
        _TileObjectKind.npc => Icons.chat_bubble_rounded,
        _TileObjectKind.monster => Icons.warning_amber_rounded,
        _TileObjectKind.altar => Icons.auto_stories_rounded,
        _TileObjectKind.root => Icons.park_rounded,
        _ => Icons.place_rounded,
      };

  Color get color => switch (kind) {
        _TileObjectKind.chest => const Color(0xFFFFD27A),
        _TileObjectKind.item => const Color(0xFF84F1E2),
        _TileObjectKind.npc => const Color(0xFFB9E6B1),
        _TileObjectKind.monster => const Color(0xFFFFA08F),
        _TileObjectKind.altar => const Color(0xFF9AE8F0),
        _TileObjectKind.root => const Color(0xFF91A55B),
        _ => const Color(0xFFD8D4C4),
      };
}

enum _TileTerrain { floor, moss, water }

class _TileCell {
  const _TileCell({
    required this.x,
    required this.y,
    required this.terrain,
    required this.variant,
    required this.shoreMask,
  });

  static const shoreNorth = 1;
  static const shoreEast = 2;
  static const shoreSouth = 4;
  static const shoreWest = 8;

  final int x;
  final int y;
  final _TileTerrain terrain;
  final int variant;
  final int shoreMask;
}

class _TileChunk {
  _TileChunk({required this.column, required this.row});

  final int column;
  final int row;
  final List<_TileCell> cells = <_TileCell>[];
  final List<_TileObject> staticScenery = <_TileObject>[];
  final List<_TileObject> interactables = <_TileObject>[];
  final List<_TileObject> actors = <_TileObject>[];

  Iterable<_TileObject> get objects sync* {
    yield* staticScenery;
    yield* interactables;
    yield* actors;
  }

  void addObject(_TileObject object) {
    switch (object.layer) {
      case _TileObjectLayer.staticScenery:
        staticScenery.add(object);
        return;
      case _TileObjectLayer.interactable:
        interactables.add(object);
        return;
      case _TileObjectLayer.actor:
        actors.add(object);
        return;
    }
  }
}

class _TilePalette {
  const _TilePalette({
    required this.floorA,
    required this.floorB,
    required this.moss,
    required this.water,
    required this.stone,
    required this.metal,
    required this.glow,
    required this.voidColor,
    required this.actorGrade,
  });

  final Color floorA;
  final Color floorB;
  final Color moss;
  final Color water;
  final Color stone;
  final Color metal;
  final Color glow;
  final Color voidColor;
  final Color actorGrade;

  static _TilePalette forRegion(String code) => switch (code) {
        'echo_well' => const _TilePalette(
            floorA: Color(0xFF334950),
            floorB: Color(0xFF3E5960),
            moss: Color(0xFF53726F),
            water: Color(0xFF246A78),
            stone: Color(0xFF526268),
            metal: Color(0xFF947454),
            glow: Color(0xFF69D8EC),
            voidColor: Color(0xFF101C22),
            actorGrade: Color(0x18004552)),
        'starlight_seed_vault' => const _TilePalette(
            floorA: Color(0xFF353653),
            floorB: Color(0xFF454567),
            moss: Color(0xFF5D5680),
            water: Color(0xFF303B75),
            stone: Color(0xFF585A78),
            metal: Color(0xFFA9885B),
            glow: Color(0xFF96D9FF),
            voidColor: Color(0xFF14142B),
            actorGrade: Color(0x180D0E55)),
        'heartwood_observatory' => const _TilePalette(
            floorA: Color(0xFF4A3E34),
            floorB: Color(0xFF58493A),
            moss: Color(0xFF65724A),
            water: Color(0xFF315E64),
            stone: Color(0xFF655B4D),
            metal: Color(0xFFAD7A4D),
            glow: Color(0xFFFFC66D),
            voidColor: Color(0xFF211712),
            actorGrade: Color(0x18A05018)),
        _ => const _TilePalette(
            floorA: Color(0xFF5A5548),
            floorB: Color(0xFF686252),
            moss: Color(0xFF64713C),
            water: Color(0xFF28636A),
            stone: Color(0xFF716B5B),
            metal: Color(0xFFA47B3D),
            glow: Color(0xFF63D8D4),
            voidColor: Color(0xFF18201A),
            actorGrade: Color(0x181C4B38)),
      };
}

class _TileField {
  _TileField({
    required this.regionCode,
    required this.width,
    required this.height,
    required this.spawn,
    required this.goal,
    required this.palette,
    required this.terrain,
    required this.objects,
  }) {
    _chunks = _buildChunks();
  }

  static const chunkSize = 8;

  final String regionCode;
  final int width;
  final int height;
  final Offset spawn;
  final Offset goal;
  final _TilePalette palette;
  final List<_TileTerrain> terrain;
  final List<_TileObject> objects;
  late final List<_TileChunk> _chunks;
  ui.Picture? _minimapPicture;
  Size? _minimapPictureSize;

  int get chunkColumns => (width + chunkSize - 1) ~/ chunkSize;
  int get chunkRows => (height + chunkSize - 1) ~/ chunkSize;

  List<_TileChunk> _buildChunks() {
    final chunks = List<_TileChunk>.generate(
      chunkColumns * chunkRows,
      (index) => _TileChunk(
        column: index % chunkColumns,
        row: index ~/ chunkColumns,
      ),
      growable: false,
    );
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final terrain = terrainAt(x, y);
        var shoreMask = 0;
        if (terrain == _TileTerrain.water) {
          if (terrainAt(x, y - 1) != _TileTerrain.water) {
            shoreMask |= _TileCell.shoreNorth;
          }
          if (terrainAt(x + 1, y) != _TileTerrain.water) {
            shoreMask |= _TileCell.shoreEast;
          }
          if (terrainAt(x, y + 1) != _TileTerrain.water) {
            shoreMask |= _TileCell.shoreSouth;
          }
          if (terrainAt(x - 1, y) != _TileTerrain.water) {
            shoreMask |= _TileCell.shoreWest;
          }
        }
        chunks[(y ~/ chunkSize) * chunkColumns + x ~/ chunkSize].cells.add(
              _TileCell(
                x: x,
                y: y,
                terrain: terrain,
                // The painterly ground is one sealed 4x4 macro texture. World
                // coordinates select its matching phase so natural brushwork
                // crosses cell boundaries without a visible grid.
                variant: (x & 3) | ((y & 3) << 2),
                shoreMask: shoreMask,
              ),
            );
      }
    }
    for (final object in objects) {
      final x = object.position.dx.floor().clamp(0, width - 1);
      final y = object.position.dy.floor().clamp(0, height - 1);
      chunks[(y ~/ chunkSize) * chunkColumns + x ~/ chunkSize]
          .addObject(object);
    }
    return chunks;
  }

  Iterable<_TileChunk> chunksIn(Rect worldRect) sync* {
    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final clipped = worldRect.intersect(bounds);
    if (clipped.isEmpty) return;
    final left = clipped.left.floor().clamp(0, width - 1) ~/ chunkSize;
    final top = clipped.top.floor().clamp(0, height - 1) ~/ chunkSize;
    final right = (clipped.right.ceil() - 1).clamp(0, width - 1) ~/ chunkSize;
    final bottom =
        (clipped.bottom.ceil() - 1).clamp(0, height - 1) ~/ chunkSize;
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        yield _chunks[row * chunkColumns + column];
      }
    }
  }

  Iterable<_TileObject> objectsIn(Rect worldRect) sync* {
    for (final chunk in chunksIn(worldRect)) {
      yield* chunk.objects;
    }
  }

  ui.Picture minimapBackground(Size size) {
    final cached = _minimapPicture;
    if (cached != null && _minimapPictureSize == size) return cached;
    cached?.dispose();
    const padding = 6.0;
    final sx = (size.width - padding * 2) / width;
    final sy = (size.height - padding * 2) / height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final map = Rect.fromLTWH(padding, padding, width * sx, height * sy);
    canvas.drawRect(map, Paint()..color = palette.floorA);
    for (final chunk in _chunks) {
      for (final cell in chunk.cells) {
        if (cell.terrain == _TileTerrain.floor) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            padding + cell.x * sx,
            padding + cell.y * sy,
            sx + .15,
            sy + .15,
          ),
          Paint()
            ..color = cell.terrain == _TileTerrain.water
                ? palette.water
                : palette.moss,
        );
      }
    }
    for (final chunk in _chunks) {
      for (final object in chunk.objects.where((object) => object.blocks)) {
        canvas.drawCircle(
          Offset(
            padding + object.position.dx * sx,
            padding + object.position.dy * sy,
          ),
          object.kind == _TileObjectKind.altar ? 2.5 : 1.1,
          Paint()
            ..color = object.kind == _TileObjectKind.altar
                ? palette.glow
                : palette.voidColor,
        );
      }
    }
    _minimapPictureSize = size;
    return _minimapPicture = recorder.endRecording();
  }

  void dispose() {
    _minimapPicture?.dispose();
    _minimapPicture = null;
  }

  factory _TileField.forStage(String regionCode, int stageNo) {
    const width = 42;
    const height = 30;
    final palette = _TilePalette.forRegion(regionCode);
    final phase = stageNo % 3;
    final regionSeed = switch (regionCode) {
      'echo_well' => 11,
      'starlight_seed_vault' => 23,
      'heartwood_observatory' => 37,
      _ => 3,
    };
    final terrain = List<_TileTerrain>.filled(
      width * height,
      _TileTerrain.floor,
    );
    final pools = <({Offset center, Size radii})>[
      (
        center: Offset(16.2 + phase * .18, 24.6),
        radii: const Size(3.55, 1.9),
      ),
      (
        center: Offset(20.5, 15.9 + phase * .16),
        radii: const Size(2.45, 1.75),
      ),
      (
        center: Offset(31.5 - phase * .14, 8.0),
        radii: const Size(3.15, 1.95),
      ),
    ];
    bool insideEllipse(Offset point, Offset center, Size radii) {
      final dx = (point.dx - center.dx) / radii.width;
      final dy = (point.dy - center.dy) / radii.height;
      return dx * dx + dy * dy <= 1;
    }

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final center = Offset(x + .5, y + .5);
        final water = pools.any(
          (pool) =>
              insideEllipse(center, pool.center, pool.radii) ||
              insideEllipse(
                center,
                pool.center + const Offset(.72, -.28),
                Size(pool.radii.width * .72, pool.radii.height * .72),
              ),
        );
        if (water) terrain[y * width + x] = _TileTerrain.water;
      }
    }
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final index = y * width + x;
        if (terrain[index] == _TileTerrain.water) continue;
        final bordersWater = <int>[
          index - width - 1,
          index - width,
          index - width + 1,
          index - 1,
          index + 1,
          index + width - 1,
          index + width,
          index + width + 1,
        ].any((neighbor) => terrain[neighbor] == _TileTerrain.water);
        final center = Offset(x + .5, y + .5);
        final broadMossPatch = insideEllipse(
              center,
              Offset(
                (7 + (regionSeed % 3)).toDouble(),
                (8 + phase).toDouble(),
              ),
              const Size(4.8, 2.7),
            ) ||
            insideEllipse(
              center,
              Offset(
                (33 - phase).toDouble(),
                (23 + (regionSeed % 2)).toDouble(),
              ),
              const Size(4.2, 2.4),
            );
        if (bordersWater || broadMossPatch) {
          terrain[index] = _TileTerrain.moss;
        }
      }
    }
    final objects = <_TileObject>[
      for (var x = 4; x <= 15; x += 2)
        if (x != 10)
          _TileObject(
            kind: _TileObjectKind.wall,
            position: Offset(x.toDouble(), 21.5),
            size: const Size(1.9, .8),
            label: '낮은 기록벽',
            blocks: true,
            collisionSize: const Size(1.55, .34),
          ),
      for (var x = 23; x <= 36; x += 3)
        if (x != 29)
          _TileObject(
            kind: _TileObjectKind.shelf,
            position: Offset(x.toDouble(), 13.2),
            size: const Size(1.8, 1.15),
            label: '무너진 서가',
            blocks: true,
            collisionSize: const Size(1.28, .4),
          ),
      const _TileObject(
        kind: _TileObjectKind.shelf,
        position: Offset(8, 16),
        size: Size(1.9, 1.2),
        label: '젖은 기록 서가',
        blocks: true,
        collisionSize: Size(1.34, .42),
      ),
      const _TileObject(
        kind: _TileObjectKind.shelf,
        position: Offset(31, 22),
        size: Size(1.9, 1.2),
        label: '뿌리 감긴 서가',
        blocks: true,
        collisionSize: Size(1.34, .42),
      ),
      for (final p in const [
        Offset(5, 24),
        Offset(17, 17),
        Offset(27, 9),
        Offset(36, 5),
      ])
        _TileObject(
          kind: _TileObjectKind.lantern,
          position: p,
          size: const Size(.65, 1.25),
          label: '기억 등불',
          blocks: true,
          collisionSize: const Size(.3, .28),
        ),
      const _TileObject(
        kind: _TileObjectKind.chest,
        position: Offset(19, 24),
        size: Size(1.15, .9),
        label: '봉인된 보물상자',
        blocks: true,
        collisionSize: Size(.78, .32),
      ),
      const _TileObject(
        kind: _TileObjectKind.item,
        position: Offset(25, 18),
        size: Size(.55, .55),
        label: '기억 조각',
      ),
      const _TileObject(
        kind: _TileObjectKind.npc,
        position: Offset(12, 10),
        size: Size(.8, 1.2),
        label: '기록지기 모아',
        blocks: true,
        collisionSize: Size(.44, .32),
      ),
      _TileObject(
        kind: _TileObjectKind.monster,
        position: Offset(24 + phase.toDouble(), 7),
        size: const Size(1.05, 1.05),
        label: '기록을 먹는 얽힘',
        blocks: true,
        collisionSize: const Size(.62, .38),
      ),
      const _TileObject(
        kind: _TileObjectKind.altar,
        position: Offset(37.5, 3.5),
        size: Size(1.5, 1.6),
        label: '빛나는 기록 제단',
        blocks: true,
        collisionSize: Size(.9, .42),
      ),
      const _TileObject(
        kind: _TileObjectKind.root,
        position: Offset(5.8, 6.6),
        size: Size(2.0, 1.15),
        label: '기억의 뿌리',
        blocks: true,
        collisionSize: Size(1.35, .36),
      ),
      const _TileObject(
        kind: _TileObjectKind.root,
        position: Offset(34.2, 17.4),
        size: Size(2.2, 1.2),
        label: '길을 감싼 뿌리',
        blocks: true,
        collisionSize: Size(1.5, .38),
      ),
    ];
    return _TileField(
      regionCode: regionCode,
      width: width,
      height: height,
      spawn: const Offset(3.5, 25.5),
      goal: const Offset(36.2, 4.5),
      palette: palette,
      terrain: terrain,
      objects: objects,
    );
  }

  _TileTerrain terrainAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return _TileTerrain.floor;
    }
    return terrain[y * width + x];
  }

  bool isWater(Offset point) =>
      terrainAt(point.dx.floor(), point.dy.floor()) == _TileTerrain.water;

  bool blocked(Offset point) {
    if (point.dx < 1.35 ||
        point.dy < 1.35 ||
        point.dx > width - 1.35 ||
        point.dy > height - 1.35) {
      return true;
    }
    const radius = .28;
    const diagonal = radius * .70710678118;
    final samples = <Offset>[
      point,
      point + const Offset(radius, 0),
      point - const Offset(radius, 0),
      point + const Offset(0, radius),
      point - const Offset(0, radius),
      point + const Offset(diagonal, diagonal),
      point + const Offset(diagonal, -diagonal),
      point + const Offset(-diagonal, diagonal),
      point - const Offset(diagonal, diagonal),
    ];
    if (samples.any(isWater)) return true;
    return objectsIn(Rect.fromCircle(center: point, radius: 2.5)).any((object) {
      if (!object.blocks || object.kind == _TileObjectKind.altar) return false;
      final bounds = object.collisionBounds.inflate(.06);
      final closest = Offset(
        point.dx.clamp(bounds.left, bounds.right),
        point.dy.clamp(bounds.top, bounds.bottom),
      );
      return (point - closest).distanceSquared <= radius * radius;
    });
  }

  Offset slide(Offset from, Offset delta) {
    final steps = math.max(1, (delta.distance / .12).ceil());
    final increment = delta / steps.toDouble();
    var current = from;
    for (var step = 0; step < steps; step++) {
      final horizontal = Offset(current.dx + increment.dx, current.dy);
      if (!blocked(horizontal)) current = horizontal;
      final vertical = Offset(current.dx, current.dy + increment.dy);
      if (!blocked(vertical)) current = vertical;
    }
    return current;
  }

  bool get hasRouteToGoal {
    final startX = spawn.dx.floor();
    final startY = spawn.dy.floor();
    final targetX = goal.dx.floor();
    final targetY = goal.dy.floor();
    final queue = <int>[startY * width + startX];
    final visited = <int>{queue.first};
    var cursor = 0;
    while (cursor < queue.length) {
      final index = queue[cursor++];
      final x = index % width;
      final y = index ~/ width;
      if (x == targetX && y == targetY) return true;
      for (final next in <(int, int)>[
        (x + 1, y),
        (x - 1, y),
        (x, y + 1),
        (x, y - 1),
      ]) {
        final nx = next.$1;
        final ny = next.$2;
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
        final nextIndex = ny * width + nx;
        if (visited.contains(nextIndex) || blocked(Offset(nx + .5, ny + .5))) {
          continue;
        }
        visited.add(nextIndex);
        queue.add(nextIndex);
      }
    }
    return false;
  }

  _TileObject? nearestDiscoverable(Offset player) {
    _TileObject? nearest;
    var distance = 1.6;
    for (final object
        in objectsIn(Rect.fromCircle(center: player, radius: distance + 1))) {
      if (object.kind == _TileObjectKind.wall ||
          object.kind == _TileObjectKind.shelf ||
          object.kind == _TileObjectKind.lantern ||
          object.kind == _TileObjectKind.root) {
        continue;
      }
      final next = (player - object.position).distance;
      if (next < distance) {
        distance = next;
        nearest = object;
      }
    }
    return nearest;
  }
}

@visibleForTesting
bool expeditionTileWorldHasRoute(String regionCode, int stageNo) =>
    _TileField.forStage(regionCode, stageNo).hasRouteToGoal;

@visibleForTesting
Map<String, int> expeditionTileWorldChunkDiagnostics(
  String regionCode,
  int stageNo,
) {
  final field = _TileField.forStage(regionCode, stageNo);
  try {
    return <String, int>{
      'chunkSize': _TileField.chunkSize,
      'chunkCount': field._chunks.length,
      'maxCellsPerChunk':
          field._chunks.map((chunk) => chunk.cells.length).reduce(math.max),
      'staticScenery': field._chunks
          .fold(0, (sum, chunk) => sum + chunk.staticScenery.length),
      'interactables': field._chunks
          .fold(0, (sum, chunk) => sum + chunk.interactables.length),
      'actors':
          field._chunks.fold(0, (sum, chunk) => sum + chunk.actors.length),
      'visibleChunks':
          field.chunksIn(const Rect.fromLTWH(8, 8, 10, 8).inflate(1)).length,
    };
  } finally {
    field.dispose();
  }
}

class _WorldCamera {
  const _WorldCamera({
    required this.origin,
    required this.tilePixels,
    required this.viewport,
  });

  final Offset origin;
  final double tilePixels;
  final Size viewport;

  factory _WorldCamera.follow({
    required _TileField field,
    required Offset player,
    required Size viewport,
  }) {
    final tilePixels = (viewport.height / 7.25).clamp(29.0, 52.0);
    final visible = Offset(
      viewport.width / tilePixels,
      viewport.height / tilePixels,
    );
    final origin = Offset(
      (player.dx - visible.dx / 2)
          .clamp(0.0, math.max(0.0, field.width - visible.dx)),
      (player.dy - visible.dy / 2)
          .clamp(0.0, math.max(0.0, field.height - visible.dy)),
    );
    return _WorldCamera(
      origin: origin,
      tilePixels: tilePixels,
      viewport: viewport,
    );
  }

  Offset project(Offset world) => (world - origin) * tilePixels;

  Rect get worldRect => Rect.fromLTWH(
        origin.dx,
        origin.dy,
        viewport.width / tilePixels,
        viewport.height / tilePixels,
      );

  int visibleTileCount(_TileField field) {
    final rect = worldRect.inflate(1);
    final left = rect.left.floor().clamp(0, field.width - 1);
    final top = rect.top.floor().clamp(0, field.height - 1);
    final right = rect.right.ceil().clamp(0, field.width);
    final bottom = rect.bottom.ceil().clamp(0, field.height);
    return (right - left) * (bottom - top);
  }

  int visibleChunkCount(_TileField field) =>
      field.chunksIn(worldRect.inflate(1)).length;
}

class _TileWorldPainter extends CustomPainter {
  const _TileWorldPainter({
    required this.atlas,
    required this.field,
    required this.camera,
    required this.playerY,
    required this.foreground,
    required this.pulse,
  });

  static const double _atlasCell = 96;
  static const double _atlasGutter = 2;
  static const double _atlasStride = 100;
  static const List<String> _terrainSuffixes = [
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
  ];
  static const Map<String, int> _atlasSpriteSlots = {
    'shore_n': 48,
    'shore_e': 49,
    'shore_s': 50,
    'shore_w': 51,
    'wall': 52,
    'shelf': 53,
    'lantern': 54,
    'chest': 55,
    'item': 56,
    'npc': 57,
    'monster': 58,
    'altar': 59,
    'root': 60,
  };

  final ui.Image? atlas;
  final _TileField field;
  final _WorldCamera camera;
  final double playerY;
  final bool foreground;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (!foreground) _paintVisibleGround(canvas);
    final visible = camera.worldRect.inflate(2);
    final objects = field
        .objectsIn(visible)
        .where((object) => visible.overlaps(object.visualBounds.inflate(1)))
        .where((object) => foreground
            ? object.position.dy > playerY
            : object.position.dy <= playerY)
        .toList()
      ..sort((a, b) => a.position.dy.compareTo(b.position.dy));
    for (final object in objects) {
      _paintObject(canvas, object);
    }
    if (foreground) _paintLighting(canvas, size);
    canvas.restore();
  }

  void _paintVisibleGround(Canvas canvas) {
    final rect = camera.worldRect.inflate(1);
    final left = rect.left.floor().clamp(0, field.width - 1);
    final top = rect.top.floor().clamp(0, field.height - 1);
    final right = rect.right.ceil().clamp(0, field.width);
    final bottom = rect.bottom.ceil().clamp(0, field.height);
    final image = atlas;
    if (image == null) {
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          _paintTile(canvas, x, y);
        }
      }
      return;
    }

    final baseTransforms = <ui.RSTransform>[];
    final baseRects = <Rect>[];
    final shoreTransforms = <ui.RSTransform>[];
    final shoreRects = <Rect>[];
    final scale = (camera.tilePixels + .7) / _atlasCell;

    void addSprite(
      List<ui.RSTransform> transforms,
      List<Rect> rects,
      String sprite,
      Offset screen,
    ) {
      transforms.add(
        ui.RSTransform.fromComponents(
          rotation: 0,
          scale: scale,
          anchorX: 0,
          anchorY: 0,
          translateX: screen.dx,
          translateY: screen.dy,
        ),
      );
      rects.add(_atlasRect(sprite));
    }

    for (final chunk in field.chunksIn(rect)) {
      for (final cell in chunk.cells) {
        final x = cell.x;
        final y = cell.y;
        if (x < left || x >= right || y < top || y >= bottom) continue;
        final screen = camera.project(Offset(x.toDouble(), y.toDouble()));
        final terrain = cell.terrain;
        final variant = cell.variant;
        final base = switch (terrain) {
          _TileTerrain.floor => 'floor_${_terrainSuffixes[variant]}',
          _TileTerrain.moss => 'moss_${_terrainSuffixes[variant]}',
          _TileTerrain.water => 'water_${_terrainSuffixes[variant]}',
        };
        addSprite(baseTransforms, baseRects, base, screen);
        if (terrain != _TileTerrain.water) continue;
        if (cell.shoreMask & _TileCell.shoreNorth != 0) {
          addSprite(shoreTransforms, shoreRects, 'shore_n', screen);
        }
        if (cell.shoreMask & _TileCell.shoreEast != 0) {
          addSprite(shoreTransforms, shoreRects, 'shore_e', screen);
        }
        if (cell.shoreMask & _TileCell.shoreSouth != 0) {
          addSprite(shoreTransforms, shoreRects, 'shore_s', screen);
        }
        if (cell.shoreMask & _TileCell.shoreWest != 0) {
          addSprite(shoreTransforms, shoreRects, 'shore_w', screen);
        }
      }
    }
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium;
    final cullRect = Offset.zero & camera.viewport;
    canvas.drawAtlas(
      image,
      baseTransforms,
      baseRects,
      null,
      BlendMode.srcOver,
      cullRect,
      paint,
    );
    if (shoreRects.isNotEmpty) {
      canvas.drawAtlas(
        image,
        shoreTransforms,
        shoreRects,
        null,
        BlendMode.srcOver,
        cullRect,
        paint,
      );
    }
  }

  Rect _atlasRect(String sprite) {
    final region = switch (field.regionCode) {
      'echo_well' => 1,
      'starlight_seed_vault' => 2,
      'heartwood_observatory' => 3,
      _ => 0,
    };
    final slot = switch (sprite) {
      final value when value.startsWith('floor_') =>
        value.codeUnitAt(value.length - 1) - 97,
      final value when value.startsWith('moss_') =>
        16 + value.codeUnitAt(value.length - 1) - 97,
      final value when value.startsWith('water_') =>
        32 + value.codeUnitAt(value.length - 1) - 97,
      _ => _atlasSpriteSlots[sprite]!,
    };
    final flatIndex = region * 64 + slot;
    return Rect.fromLTWH(
      (flatIndex % 8) * _atlasStride + _atlasGutter,
      (flatIndex ~/ 8) * _atlasStride + _atlasGutter,
      _atlasCell,
      _atlasCell,
    );
  }

  void _paintTile(Canvas canvas, int x, int y) {
    final p = camera.project(Offset(x.toDouble(), y.toDouble()));
    final tile = Rect.fromLTWH(
      p.dx,
      p.dy,
      camera.tilePixels + .7,
      camera.tilePixels + .7,
    );
    final terrain = field.terrainAt(x, y);
    if (terrain == _TileTerrain.water) {
      canvas.drawRect(tile, Paint()..color = field.palette.water);
      final ripple = Paint()
        ..color = field.palette.glow.withAlpha(64)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15;
      final phase = ((x * 7 + y * 3) % 5) / 5;
      canvas.drawArc(
        Rect.fromCenter(
          center: tile.center + Offset(0, phase * 4 - 2),
          width: tile.width * .58,
          height: tile.height * .25,
        ),
        .18,
        2.45,
        false,
        ripple,
      );
      return;
    }
    final alternate = (x * 13 + y * 7) % 5;
    canvas.drawRect(
      tile,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            alternate == 0 ? field.palette.floorB : field.palette.floorA,
            field.palette.floorB,
          ],
        ).createShader(tile),
    );
    final joint = Paint()
      ..color = field.palette.voidColor.withAlpha(86)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final inset = tile.deflate(1.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, const Radius.circular(3.5)),
      joint,
    );
    if (terrain == _TileTerrain.moss) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            tile.left + tile.width * .1,
            tile.bottom - tile.height * .18,
            tile.width * .32,
            tile.height * .1,
          ),
          const Radius.circular(5),
        ),
        Paint()..color = field.palette.moss.withAlpha(135),
      );
    }
  }

  void _paintObject(Canvas canvas, _TileObject object) {
    final foot = camera.project(object.position);
    final unit = camera.tilePixels;
    final w = object.size.width * unit;
    final h = object.size.height * unit;
    final bounds = Rect.fromLTWH(foot.dx - w / 2, foot.dy - h, w, h);
    if (object.kind != _TileObjectKind.item) {
      canvas.drawOval(
        Rect.fromCenter(
          center: foot + Offset(0, -2),
          width: w * .82,
          height: math.max(4, h * .12),
        ),
        Paint()
          ..color = Colors.black.withAlpha(82)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    final image = atlas;
    if (image != null) {
      final bob = object.kind == _TileObjectKind.item
          ? math.sin(pulse * math.pi * 2) * h * .1
          : 0.0;
      canvas.drawImageRect(
        image,
        _atlasRect(object.kind.name),
        bounds.shift(Offset(0, bob)),
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.medium,
      );
      return;
    }
    switch (object.kind) {
      case _TileObjectKind.wall:
        _paintWall(canvas, bounds);
      case _TileObjectKind.shelf:
        _paintShelf(canvas, bounds);
      case _TileObjectKind.lantern:
        _paintLantern(canvas, bounds);
      case _TileObjectKind.chest:
        _paintChest(canvas, bounds);
      case _TileObjectKind.item:
        _paintItem(canvas, bounds);
      case _TileObjectKind.npc:
        _paintNpc(canvas, bounds);
      case _TileObjectKind.monster:
        _paintMonster(canvas, bounds);
      case _TileObjectKind.altar:
        _paintAltar(canvas, bounds);
      case _TileObjectKind.root:
        _paintRoot(canvas, bounds);
    }
  }

  void _paintRoot(Canvas canvas, Rect r) {
    final root = Paint()
      ..color = Color.lerp(field.palette.metal, field.palette.voidColor, .48)!
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(4, r.height * .16);
    final path = Path()
      ..moveTo(r.left + r.width * .05, r.bottom - r.height * .1)
      ..cubicTo(r.left + r.width * .28, r.top, r.center.dx, r.top, r.center.dx,
          r.bottom - r.height * .18)
      ..cubicTo(r.right - r.width * .2, r.top + r.height * .2,
          r.right - r.width * .08, r.center.dy, r.right, r.bottom);
    canvas.drawPath(path, root);
    canvas.drawPath(
      path,
      Paint()
        ..color = field.palette.moss.withAlpha(130)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, r.height * .045),
    );
  }

  void _paintWall(Canvas canvas, Rect r) {
    final face = RRect.fromRectAndRadius(r, const Radius.circular(4));
    canvas.drawRRect(face, Paint()..color = field.palette.stone);
    canvas.drawRect(
      Rect.fromLTWH(r.left + 2, r.top + 2, r.width - 4, r.height * .24),
      Paint()..color = Color.lerp(field.palette.stone, Colors.white, .2)!,
    );
    canvas.drawLine(
      Offset(r.center.dx, r.top + 3),
      Offset(r.center.dx, r.bottom - 3),
      Paint()..color = field.palette.voidColor.withAlpha(90),
    );
    canvas.drawRRect(face, Paint()..color = field.palette.moss.withAlpha(22));
  }

  void _paintShelf(Canvas canvas, Rect r) {
    final wood =
        Color.lerp(field.palette.voidColor, const Color(0xFF8B623E), .45)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
      Paint()..color = wood,
    );
    for (var row = 0; row < 2; row++) {
      final shelf = Rect.fromLTWH(
        r.left + r.width * .09,
        r.top + r.height * (.18 + row * .38),
        r.width * .82,
        r.height * .25,
      );
      canvas.drawRect(
          shelf, Paint()..color = field.palette.voidColor.withAlpha(170));
      for (var book = 0; book < 4; book++) {
        final br = Rect.fromLTWH(
          shelf.left + 2 + book * (shelf.width - 4) / 4,
          shelf.top + 2,
          (shelf.width - 8) / 4,
          shelf.height - 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(br, const Radius.circular(1.5)),
          Paint()
            ..color = [
              field.palette.moss,
              field.palette.metal,
              field.palette.stone,
              const Color(0xFF4A5368)
            ][book],
        );
      }
    }
  }

  void _paintLantern(Canvas canvas, Rect r) {
    final post = Rect.fromLTWH(r.center.dx - r.width * .12,
        r.top + r.height * .33, r.width * .24, r.height * .63);
    canvas.drawRRect(RRect.fromRectAndRadius(post, const Radius.circular(2)),
        Paint()..color = field.palette.metal);
    final lamp = Rect.fromLTWH(
        r.left + r.width * .13, r.top, r.width * .74, r.height * .4);
    canvas.drawRRect(RRect.fromRectAndRadius(lamp, const Radius.circular(5)),
        Paint()..color = field.palette.metal);
    canvas.drawRRect(
        RRect.fromRectAndRadius(lamp.deflate(3), const Radius.circular(3)),
        Paint()..color = field.palette.glow);
  }

  void _paintChest(Canvas canvas, Rect r) {
    final body =
        Rect.fromLTWH(r.left, r.top + r.height * .22, r.width, r.height * .78);
    canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(5)),
        Paint()..color = const Color(0xFF543923));
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * .22)),
        Paint()..color = field.palette.metal.withAlpha(170));
    canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(3), Radius.circular(r.width * .18)),
        Paint()..color = const Color(0xFF5C4029));
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(r.center.dx, r.center.dy + 3),
            width: r.width * .18,
            height: r.height * .23),
        Paint()..color = field.palette.glow);
  }

  void _paintItem(Canvas canvas, Rect r) {
    final bob = math.sin(pulse * math.pi * 2) * r.height * .1;
    final center = r.center + Offset(0, bob);
    final path = Path()
      ..moveTo(center.dx, center.dy - r.height * .5)
      ..lineTo(center.dx + r.width * .42, center.dy)
      ..lineTo(center.dx, center.dy + r.height * .5)
      ..lineTo(center.dx - r.width * .42, center.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = field.palette.glow);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withAlpha(60)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  void _paintNpc(Canvas canvas, Rect r) {
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(r.center.dx, r.top + r.height * .24),
            width: r.width * .55,
            height: r.width * .55),
        Paint()..color = const Color(0xFFD4B28B));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left + r.width * .18, r.top + r.height * .4,
                r.width * .64, r.height * .58),
            const Radius.circular(7)),
        Paint()..color = field.palette.moss);
    canvas.drawArc(
        Rect.fromLTWH(r.left + r.width * .12, r.top + r.height * .04,
            r.width * .76, r.width * .5),
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = field.palette.metal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  void _paintMonster(Canvas canvas, Rect r) {
    final body = Path()
      ..moveTo(r.center.dx, r.top)
      ..cubicTo(r.right, r.top + r.height * .18, r.right,
          r.top + r.height * .98, r.center.dx, r.bottom)
      ..cubicTo(r.left, r.top + r.height * .98, r.left, r.top + r.height * .18,
          r.center.dx, r.top)
      ..close();
    canvas.drawPath(
        body,
        Paint()
          ..color =
              Color.lerp(field.palette.moss, const Color(0xFF2B2137), .65)!);
    canvas.drawCircle(Offset(r.center.dx - r.width * .16, r.center.dy - 2), 2.2,
        Paint()..color = const Color(0xFFFFB08F));
    canvas.drawCircle(Offset(r.center.dx + r.width * .16, r.center.dy - 2), 2.2,
        Paint()..color = const Color(0xFFFFB08F));
  }

  void _paintAltar(Canvas canvas, Rect r) {
    final base =
        Rect.fromLTWH(r.left, r.top + r.height * .44, r.width, r.height * .56);
    canvas.drawRRect(RRect.fromRectAndRadius(base, const Radius.circular(5)),
        Paint()..color = field.palette.stone);
    canvas.drawRRect(
        RRect.fromRectAndRadius(base.deflate(4), const Radius.circular(4)),
        Paint()..color = Color.lerp(field.palette.stone, Colors.black, .15)!);
    final book = Rect.fromLTWH(r.left + r.width * .15, r.top + r.height * .12,
        r.width * .7, r.height * .39);
    canvas.save();
    canvas.translate(book.center.dx, book.center.dy);
    canvas.rotate(-.12);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: book.width, height: book.height),
            const Radius.circular(4)),
        Paint()..color = const Color(0xFF1E4938));
    canvas.drawLine(
        Offset(-book.width * .38, book.height * .33),
        Offset(book.width * .38, book.height * .33),
        Paint()
          ..color = field.palette.glow
          ..strokeWidth = 2.5);
    canvas.restore();
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(base.center.dx, base.center.dy + 2),
            width: base.width * .23,
            height: base.height * .32),
        Paint()..color = field.palette.glow);
  }

  void _paintLighting(Canvas canvas, Size size) {
    for (final lantern in field.objectsIn(camera.worldRect.inflate(2)).where(
        (o) =>
            o.kind == _TileObjectKind.lantern &&
            camera.worldRect.inflate(2).contains(o.position))) {
      final center = camera.project(lantern.position - const Offset(0, .85));
      final rect =
          Rect.fromCircle(center: center, radius: camera.tilePixels * 2.1);
      canvas.drawCircle(
          center,
          camera.tilePixels * 2.1,
          Paint()
            ..shader = RadialGradient(colors: [
              field.palette.glow.withAlpha(42),
              Colors.transparent
            ]).createShader(rect));
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: .86,
          colors: [Colors.transparent, field.palette.voidColor.withAlpha(82)],
          stops: const [.54, 1],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _TileWorldPainter oldDelegate) =>
      oldDelegate.camera.origin != camera.origin ||
      oldDelegate.playerY != playerY ||
      oldDelegate.foreground != foreground ||
      oldDelegate.pulse != pulse ||
      oldDelegate.atlas != atlas ||
      oldDelegate.field != field;
}

class _TileMinimapPainter extends CustomPainter {
  const _TileMinimapPainter({
    required this.field,
    required this.player,
    required this.camera,
  });

  final _TileField field;
  final Offset player;
  final _WorldCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 6.0;
    final sx = (size.width - padding * 2) / field.width;
    final sy = (size.height - padding * 2) / field.height;
    canvas.drawPicture(field.minimapBackground(size));
    final view = camera.worldRect;
    canvas.drawRect(
      Rect.fromLTWH(
        padding + view.left * sx,
        padding + view.top * sy,
        view.width * sx,
        view.height * sy,
      ),
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(padding + player.dx * sx, padding + player.dy * sy),
      2.5,
      Paint()..color = const Color(0xFFFFE19A),
    );
  }

  @override
  bool shouldRepaint(covariant _TileMinimapPainter oldDelegate) =>
      oldDelegate.field != field ||
      oldDelegate.player != player ||
      oldDelegate.camera.origin != camera.origin;
}
