part of 'expedition_screen.dart';

/// 스테이지 안으로 들어가 걷는 타일 월드.
///
/// 완성된 배경 한 장을 움직이는 방식이 아니다. 바닥 타일, 충돌 지형, 조형물,
/// NPC/몬스터/보물/아이템, 목적 이벤트를 독립 데이터로 두고 카메라 안쪽만
/// 그린다. 그래서 맵 크기가 커져도 한 프레임의 페인트 비용은 뷰포트 크기에
/// 비례한다.
/// 캐릭터가 보는 쪽. 걷기 시트(`expedition-walker-v1.png`)의 줄 순서와 같다.
enum _WalkFacing { down, left, right, up }

/// 한 칸 옮기는 데 걸리는 시간. 포켓몬의 걸음이 대략 이 언저리다.
/// 더 빠르면 칸이 안 읽히고 더 느리면 답답하다.
const double _stepSeconds = .165;

/// 손가락을 이만큼 끌어야 방향으로 친다. 누르기만 한 것과 가르는 값이다.
const double _dragSlop = 12;

/// 걷기 시트 한 칸.
const double _walkerCellWidth = 96;
const double _walkerCellHeight = 120;

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

  /// 지금 서 있는 칸과 떠나온 칸, 그 사이의 진행도.
  ///
  /// 아날로그로 미끄러지던 것을 칸 단위로 바꿨다. 미끄러지면 `벽에 스쳤나`가 매
  /// 프레임 흔들려서 문턱을 밟았는지 물건 앞에 섰는지를 사람도 코드도 확신하지
  /// 못한다. 칸으로 끊으면 그 판정이 걸음이 끝나는 순간 한 번만 일어난다.
  /// 포켓몬과 탐험대가 둘 다 칸으로 끊는 이유이기도 하다.
  late int _tileX;
  late int _tileY;
  late int _fromX;
  late int _fromY;
  double _progress = 1;

  /// 두 발을 번갈아 내기 위한 값. 한 칸마다 뒤집힌다.
  int _footfall = 0;

  _WalkFacing _facing = _WalkFacing.down;

  /// 손가락이나 방향키가 붙잡고 있는 쪽. 놓으면 null이라 걸음이 멈춘다.
  _WalkFacing? _held;

  Offset? _stickCenter;
  Offset? _stickTouch;
  Duration _lastTick = Duration.zero;
  double _stride = 0;
  bool _movePending = false;
  ExpeditionCombatAudio? _steps;
  ui.Image? _atlas;
  ui.Image? _walker;

  /// 지금 실내인가. 실내에서는 제단 판정을 하지 않는다.
  bool _inside = false;

  /// 실내로 들어가기 직전에 서 있던 칸. 나오면 그 자리로 돌아온다.
  (int, int)? _outsideTile;

  /// 이미 열었거나 주운 것. 같은 상자를 두 번 열면 세계가 가벼워진다.
  final Set<String> _used = <String>{};

  /// 지금 떠 있는 말풍선. 닫아야 다시 걷는다.
  ({String title, String body})? _speech;

  /// 그릴 자리. 칸 사이를 오가는 동안만 소수점이 된다.
  Offset get _position => Offset(
        _fromX + (_tileX - _fromX) * _progress + .5,
        _fromY + (_tileY - _fromY) * _progress + .5,
      );

  bool get _moving => _progress < 1;

  @override
  void initState() {
    super.initState();
    _field = _buildField();
    _placeAtSpawn();
    _ticker = createTicker(_tick)..start();
    unawaited(_loadAtlas());
  }

  Future<void> _loadWalker() async {
    try {
      final bytes = await rootBundle.load(
        'assets/adventure/overworld/expedition-walker-v1.png',
      );
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _walker?.dispose();
        _walker = frame.image;
      });
    } catch (_) {
      // 걷기 시트를 못 읽어도 월드는 돌아야 한다. 그때는 기존 토큰으로 그린다.
    }
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
      unawaited(_loadWalker());
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
    _field = _buildField();
    _placeAtSpawn();
  }

  _TileField _buildField() => _TileField.forStage(
        widget.expedition.region.code,
        widget.expedition.run.stageNo ?? 1,
        withGuardian: widget.destination.type == 'guardian',
      );

  void _placeAtSpawn() {
    _tileX = _fromX = _field.spawn.dx.floor();
    _tileY = _fromY = _field.spawn.dy.floor();
    _progress = 1;
  }

  bool get _movementEnabled =>
      _speech == null &&
      widget.expedition.run.phase == 'exploring' &&
      !ref.read(expeditionControllerProvider).interactionLocked &&
      !_movePending;

  void _pointerDown(Offset local) {
    if (!_movementEnabled) return;
    setState(() {
      _stickCenter = local;
      _stickTouch = local;
    });
  }

  void _pointerMove(Offset local) {
    final center = _stickCenter;
    if (center == null) return;
    setState(() => _stickTouch = local);
    // 끌린 방향에서 **더 큰 축 하나만** 고른다. 대각선을 허용하면 좁은 복도에서
    // 모서리에 걸려 멈춘 것처럼 느껴진다.
    final drag = local - center;
    if (drag.distance < _dragSlop) return;
    _held = drag.dx.abs() >= drag.dy.abs()
        ? (drag.dx >= 0 ? _WalkFacing.right : _WalkFacing.left)
        : (drag.dy >= 0 ? _WalkFacing.down : _WalkFacing.up);
  }

  void _pointerUp() {
    _held = null;
    setState(() {
      _stickCenter = null;
      _stickTouch = null;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyW => _WalkFacing.up,
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.keyS => _WalkFacing.down,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.keyA => _WalkFacing.left,
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.keyD =>
        _WalkFacing.right,
      _ => null,
    };
    if (direction == null) {
      final act = event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.keyZ;
      if (act && event is KeyDownEvent) {
        if (_speech != null) {
          _closeSpeech();
        } else {
          _interact();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      if (_held == direction) _held = null;
      return KeyEventResult.handled;
    }
    _held = direction;
    return KeyEventResult.handled;
  }

  void _tick(Duration elapsed) {
    final rawSeconds = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (rawSeconds <= 0) return;
    // 프레임이 길게 끊겨도 걸음이 멈추지 않게 잘라 쓴다. 버리면 느린 기기에서
    // 한 발도 못 나간다.
    final seconds = math.min(rawSeconds, .12);

    if (_moving) {
      setState(() {
        _progress = math.min(1, _progress + seconds / _stepSeconds);
        _stride = (_stride + seconds * 3) % 2;
      });
      if (!_moving) _arrive();
      return;
    }
    if (!_movementEnabled) return;
    final held = _held;
    if (held != null) _tryStep(held);
  }

  /// 바라보는 칸의 물건. 없으면 null이라 단추가 안 뜬다.
  _TileObject? get _facingObject {
    final delta = _deltaOf(_facing);
    return _field.facingTarget(_tileX, _tileY, delta.$1, delta.$2);
  }

  String _keyOf(_TileObject object) =>
      '${object.kind.name}:${object.position.dx}:${object.position.dy}';

  /// A를 눌렀을 때. 말을 걸거나 열거나 줍는다.
  ///
  /// 상자와 아이템은 **이야기로만** 돌려준다. 씨앗·경험치 같은 보상은 서버가
  /// 쥐고 있고 앱이 임의로 만들어 낼 수 없다 — 필드 보상 계약이 생기면 그때
  /// 여기서 서버를 부른다.
  void _interact() {
    final object = _facingObject;
    if (object == null) return;
    final key = _keyOf(object);
    final taken = _used.contains(key);
    final line = switch (object.kind) {
      _TileObjectKind.npc => object.speech ??
          '여기 기록은 아직 정리가 안 됐어요. 조심해서 지나가세요.',
      _TileObjectKind.chest => taken
          ? '이미 열어 본 기록함이에요. 안은 비어 있어요.'
          : '기록함을 열었어요. 눅눅한 종이 냄새가 올라와요.',
      _TileObjectKind.item =>
        taken ? '아까 주운 자리예요.' : '기억 조각을 주웠어요. 손끝이 따뜻해져요.',
      _TileObjectKind.shelf => '서가가 기울어 있어요. 책등의 글씨는 지워졌어요.',
      _TileObjectKind.altar => '제단이 희미하게 빛나요. 여기서 다음 장면이 열려요.',
      _TileObjectKind.monster => '엉킴과 눈이 마주쳤어요. 여기서 붙습니다.',
      _ => object.label,
    };
    HapticFeedback.selectionClick();
    if (object.warp) {
      _travel();
      return;
    }
    if (object.kind == _TileObjectKind.monster) {
      // 붙는 순간 서버가 그 노드를 열고, 전투 화면이 이어받는다. 앱이 전투를
      // 따로 만들어 내지 않는다 — 규칙은 서버 것이다.
      setState(() => _speech = (title: object.label, body: line));
      unawaited(_enterDestination());
      return;
    }
    setState(() {
      if (object.kind == _TileObjectKind.chest ||
          object.kind == _TileObjectKind.item) {
        _used.add(key);
      }
      _speech = (title: object.label, body: line);
    });
  }

  void _closeSpeech() => setState(() => _speech = null);

  /// 아치를 지나 안팎을 오간다.
  void _travel() {
    setState(() {
      if (_inside) {
        _inside = false;
        _field = _buildField();
        final back = _outsideTile;
        _tileX = _fromX = back?.$1 ?? _field.spawn.dx.floor();
        _tileY = _fromY = back?.$2 ?? _field.spawn.dy.floor();
        _outsideTile = null;
      } else {
        _outsideTile = (_tileX, _tileY);
        _inside = true;
        _field = _TileField.interior(
          widget.expedition.region.code,
          widget.expedition.run.stageNo ?? 1,
        );
        _tileX = _fromX = _field.spawn.dx.floor();
        _tileY = _fromY = _field.spawn.dy.floor();
      }
      _progress = 1;
      _facing = _WalkFacing.down;
      _speech = null;
    });
  }

  /// 한 칸 내딛는다. 갈 수 없으면 바라보는 쪽만 바꾼다.
  void _tryStep(_WalkFacing direction) {
    final delta = _deltaOf(direction);
    final targetX = _tileX + delta.$1;
    final targetY = _tileY + delta.$2;
    if (_facing != direction) setState(() => _facing = direction);
    if (_field.blocked(Offset(targetX + .5, targetY + .5))) return;
    setState(() {
      _fromX = _tileX;
      _fromY = _tileY;
      _tileX = targetX;
      _tileY = targetY;
      _progress = 0;
      _footfall = (_footfall + 1) % 2;
    });
    _playStep();
  }

  /// 걸음이 끝난 순간. 도착 판정은 **여기서만** 한다.
  void _arrive() {
    if (_inside) return;
    if ((_position - _field.goal).distance <= 1.05) {
      unawaited(_enterDestination());
    }
  }

  (int, int) _deltaOf(_WalkFacing facing) => switch (facing) {
        _WalkFacing.up => (0, -1),
        _WalkFacing.down => (0, 1),
        _WalkFacing.left => (-1, 0),
        _WalkFacing.right => (1, 0),
      };

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
    _walker?.dispose();
    _steps?.dispose();
    _atlas?.dispose();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nearby = _field.nearestDiscoverable(_position);
    final facing = _movementEnabled ? _facingObject : null;
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
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            );
            final playerScreen = camera.project(_position);
            final visibleTiles = camera.visibleTileCount(_field);
            final visibleChunks = camera.visibleChunkCount(_field);
            const actorSize = Size(70, 82);
            return Focus(
              autofocus: true,
              onKeyEvent: _onKey,
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
                      child: Semantics(
                        label: '월드 안의 현재 위치',
                        child: _walker == null
                            ? const SizedBox.shrink()
                            : CustomPaint(
                                painter: _WalkerPainter(
                                  sheet: _walker!,
                                  facing: _facing,
                                  // 걷는 동안 1-2-3-2로 발을 번갈아 낸다.
                                  // 멈추면 가운데(선 자세)다.
                                  frame: _moving ? (_footfall == 0 ? 0 : 2) : 1,
                                ),
                              ),
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
                  if (facing != null && _speech == null)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _InteractButton(
                        label: facing.label,
                        kind: facing.kind,
                        onTap: _interact,
                      ),
                    ),
                  if (_speech != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: _SpeechBubble(
                        title: _speech!.title,
                        body: _speech!.body,
                        onClose: _closeSpeech,
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

/// 바라보는 물건이 있을 때 뜨는 단추. 포켓몬에서 A를 누르는 자리다.
class _InteractButton extends StatelessWidget {
  const _InteractButton({
    required this.label,
    required this.kind,
    required this.onTap,
  });

  final String label;
  final _TileObjectKind kind;
  final VoidCallback onTap;

  String get _action => switch (kind) {
        _TileObjectKind.npc => '말 걸기',
        _TileObjectKind.chest => '열기',
        _TileObjectKind.item => '줍기',
        _TileObjectKind.altar => '살펴보기',
        _TileObjectKind.monster => '살펴보기',
        _ => '살펴보기',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$label $_action',
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_rounded, size: 17, color: scheme.onPrimary),
                const SizedBox(width: 6),
                Text(
                  '$label · $_action',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 말을 건 결과. 닫아야 다시 걷는다 — 걸으면서 읽으면 아무도 안 읽는다.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.title,
    required this.body,
    required this.onClose,
  });

  final String title;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.surface.withAlpha(244),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(body, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                tooltip: '닫기',
                iconSize: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 걷기 시트에서 한 칸을 떠서 그린다.
///
/// 도트는 흐려지면 안 되므로 필터를 끈다. 위젯 크기에 맞춰 늘리되 가로세로
/// 비율은 시트의 것을 지킨다 — 늘어난 캐릭터는 바로 눈에 띈다.
class _WalkerPainter extends CustomPainter {
  const _WalkerPainter({
    required this.sheet,
    required this.facing,
    required this.frame,
  });

  final ui.Image sheet;
  final _WalkFacing facing;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    final source = Rect.fromLTWH(
      frame * _walkerCellWidth,
      facing.index * _walkerCellHeight,
      _walkerCellWidth,
      _walkerCellHeight,
    );
    final scale = math.min(
      size.width / _walkerCellWidth,
      size.height / _walkerCellHeight,
    );
    final width = _walkerCellWidth * scale;
    final height = _walkerCellHeight * scale;
    canvas.drawImageRect(
      sheet,
      source,
      Rect.fromLTWH(
        (size.width - width) / 2,
        size.height - height,
        width,
        height,
      ),
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(covariant _WalkerPainter oldDelegate) =>
      oldDelegate.sheet != sheet ||
      oldDelegate.facing != facing ||
      oldDelegate.frame != frame;
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
    this.speech,
    this.warp = false,
  });

  /// 말을 걸었을 때 나오는 말. 없으면 종류에 맞는 기본 문장을 쓴다.
  final String? speech;

  /// 드나드는 문인가. 아치 모양 뿌리를 문으로 쓴다 — 아틀라스에 문 그림이
  /// 따로 없고, 뿌리 아치가 이미 `지나갈 수 있는 구멍`으로 읽힌다.
  final bool warp;

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

/// 지역과 스테이지로 정해지는 난수.
///
/// `Random(seed)`도 결정적이지만 구현이 바뀌면 땅이 바뀐다. 직접 굴려서 다트
/// 판올림과 무관하게 같은 땅이 나오게 한다.
class _FieldRandom {
  _FieldRandom(String regionCode, int stageNo) {
    var hash = 2166136261;
    for (final unit in '$regionCode#$stageNo'.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    _state = hash == 0 ? 1 : hash;
  }

  late int _state;

  int next(int bound) {
    if (bound <= 0) return 0;
    _state ^= (_state << 13) & 0xFFFFFFFF;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0xFFFFFFFF;
    _state &= 0xFFFFFFFF;
    return _state % bound;
  }
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

  /// 한 스테이지의 땅을 짓는다.
  ///
  /// 앞 판은 42×30 평지에 물웅덩이 셋을 파고 물건을 손으로 찍어 둔 것이었다.
  /// 넓지만 텅 비어서 `던전 안`이 아니라 들판을 가로지르는 것으로 보였다.
  ///
  /// 이제는 **방과 복도**로 짓는다. 방 다섯을 출발점에서 제단까지 이어 놓고
  /// 세 칸 폭 복도로 연결한 뒤, 걸을 수 있는 땅의 테두리에 벽을 세운다. 방마다
  /// 벽을 따라 서가·등불을 앉히고 가운데에 상자·기록 조각을 둔다.
  ///
  /// 방 모양은 네 귀퉁이를 무작위로 베어 낸다. 대칭 직사각형은 아마추어 맵의
  /// 첫 번째 징후이고, 모서리만 어긋나도 `지어진 곳`으로 보인다.
  ///
  /// 같은 지역·같은 스테이지는 언제나 같은 땅이 나온다. 매번 달라지면 `여기 와
  /// 봤다`는 감각이 안 생긴다.
  factory _TileField.forStage(
    String regionCode,
    int stageNo, {
    bool withGuardian = false,
  }) {
    const width = 42;
    const height = 30;
    final palette = _TilePalette.forRegion(regionCode);
    final random = _FieldRandom(regionCode, stageNo);

    final walkable = List<bool>.filled(width * height, false);
    void carve(int x, int y) {
      if (x < 2 || y < 2 || x >= width - 2 || y >= height - 2) return;
      walkable[y * width + x] = true;
    }

    // ── 방 자리 ───────────────────────────────────────────────────────────
    //
    // 왼쪽 아래에서 오른쪽 위로 흐르게 둔다. 출발점과 제단이 그 양 끝이다.
    // 방끼리 두 칸은 떨어져야 한 덩어리로 안 붙는다. 처음에 (7,24)·(15,17)·
    // (22,22)로 뒀더니 왼쪽 아래 셋이 붙어 큰 홀이 됐다.
    const anchors = <Offset>[
      Offset(6, 25),
      Offset(14, 15),
      Offset(24, 25),
      Offset(32, 14),
      Offset(37, 6),
    ];
    final rooms = <Rect>[];
    for (final anchor in anchors) {
      final w = 7 + random.next(2) * 2;
      final h = 5 + random.next(3);
      final left = (anchor.dx - w / 2).round().clamp(3, width - 3 - w);
      final top = (anchor.dy - h / 2).round().clamp(3, height - 3 - h);
      rooms.add(
        Rect.fromLTWH(
          left.toDouble(),
          top.toDouble(),
          w.toDouble(),
          h.toDouble(),
        ),
      );
      final bites = [
        random.next(3),
        random.next(3),
        random.next(3),
        random.next(3),
      ];
      for (var y = top; y < top + h; y++) {
        for (var x = left; x < left + w; x++) {
          final fromLeft = x - left;
          final fromRight = left + w - 1 - x;
          final fromTop = y - top;
          final fromBottom = top + h - 1 - y;
          final cut = fromLeft + fromTop < bites[0] ||
              fromRight + fromTop < bites[1] ||
              fromLeft + fromBottom < bites[2] ||
              fromRight + fromBottom < bites[3];
          if (!cut) carve(x, y);
        }
      }
    }

    // ── 복도 ──────────────────────────────────────────────────────────────
    for (var index = 0; index < rooms.length - 1; index++) {
      final from = rooms[index].center;
      final to = rooms[index + 1].center;
      final horizontalFirst = random.next(2) == 0;
      final turn =
          horizontalFirst ? Offset(to.dx, from.dy) : Offset(from.dx, to.dy);
      for (final leg in <List<Offset>>[
        <Offset>[from, turn],
        <Offset>[turn, to],
      ]) {
        final a = leg[0];
        final b = leg[1];
        final steps =
            math.max((b.dx - a.dx).abs(), (b.dy - a.dy).abs()).ceil();
        for (var step = 0; step <= steps; step++) {
          final ratio = steps == 0 ? 0.0 : step / steps;
          final x = (a.dx + (b.dx - a.dx) * ratio).round();
          final y = (a.dy + (b.dy - a.dy) * ratio).round();
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              carve(x + dx, y + dy);
            }
          }
        }
      }
    }

    bool open(int x, int y) =>
        x >= 0 && y >= 0 && x < width && y < height && walkable[y * width + x];

    // ── 지형 ──────────────────────────────────────────────────────────────
    //
    // 걷는 곳은 바닥, 바깥은 이끼다. 물은 방 밖 구석에만 둬서 눈요기로 쓴다.
    final terrain = List<_TileTerrain>.filled(width * height, _TileTerrain.moss);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (open(x, y)) terrain[y * width + x] = _TileTerrain.floor;
      }
    }
    for (final pool in <List<int>>[
      <int>[5, 6, 3],
      <int>[34, 25, 3],
      <int>[20, 4, 2],
    ]) {
      final radius = pool[2];
      for (var y = pool[1] - radius; y <= pool[1] + radius; y++) {
        for (var x = pool[0] - radius; x <= pool[0] + radius; x++) {
          if (x < 1 || y < 1 || x >= width - 1 || y >= height - 1) continue;
          final dx = (x - pool[0]) / radius;
          final dy = (y - pool[1]) / (radius * .7);
          if (dx * dx + dy * dy > 1) continue;
          // 걷는 길은 절대 잠기지 않는다. 길이 끊기면 제단에 못 간다.
          if (open(x, y)) continue;
          terrain[y * width + x] = _TileTerrain.water;
        }
      }
    }

    // ── 벽 ────────────────────────────────────────────────────────────────
    //
    // 걸을 수 있는 땅에 맞닿은 바깥 칸마다 벽을 세운다. 이게 있어야 방이
    // `안`으로 읽히고, 없으면 바닥에 색만 칠한 평지가 된다.
    final objects = <_TileObject>[];
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (open(x, y)) continue;
        if (terrain[y * width + x] == _TileTerrain.water) continue;
        final touches =
            open(x - 1, y) || open(x + 1, y) || open(x, y - 1) || open(x, y + 1);
        if (!touches) continue;
        objects.add(
          _TileObject(
            kind: _TileObjectKind.wall,
            position: Offset(x + .5, y + 1),
            // 한 칸보다 높게 세운다. 발밑은 그대로 한 칸이라 걷는 느낌은
            // 안 바뀌고, 뒤로 지나가면 머리가 가려져 벽 안쪽에 있는 것으로
            // 읽힌다. 포켓몬의 벽이 그렇게 서 있다.
            // 폭은 정확히 한 칸. 벽 그림이 칸을 꽉 채우고 좌우가 물려 있어서
            // 조금이라도 넓히면 이음매가 겹쳐 두 번 그려진다.
            size: const Size(1, 1.5),
            label: '기록벽',
            blocks: true,
            collisionSize: const Size(1, 1),
          ),
        );
      }
    }

    // ── 방 꾸미기 ─────────────────────────────────────────────────────────
    // 출발점은 방 한가운데다. 한 칸이라도 벽 쪽으로 밀면 첫 걸음이 막혀서
    // 조작이 고장 난 것처럼 느껴진다(실제로 서쪽이 막혀 있었다).
    final spawn = rooms.first.center;
    final goal = rooms.last.center;
    for (var index = 0; index < rooms.length; index++) {
      final room = rooms[index];
      final left = room.left.round();
      final top = room.top.round();
      final right = room.right.round() - 1;
      final bottom = room.bottom.round() - 1;

      // 벽을 따라 서가와 등불. 방 한가운데 흩뿌리면 지나다닐 수 없다.
      for (var x = left + 1; x <= right - 1; x += 2 + random.next(2)) {
        if (!open(x, top + 1)) continue;
        final lantern = random.next(3) == 0;
        objects.add(
          _TileObject(
            kind: lantern ? _TileObjectKind.lantern : _TileObjectKind.shelf,
            position: Offset(x + .5, top + 1.9),
            size: lantern ? const Size(.9, 1.35) : const Size(1.8, 1.15),
            label: lantern ? '기록 등불' : '무너진 서가',
            blocks: true,
            collisionSize:
                lantern ? const Size(.4, .3) : const Size(1.28, .4),
          ),
        );
      }
      if (index != rooms.length - 1 && open(left + 2, bottom - 1)) {
        // 두 번째 방의 뿌리는 **문**이다. 지나갈 수 있어야 하므로 막지 않는다.
        final isDoor = index == 1;
        objects.add(
          _TileObject(
            kind: _TileObjectKind.root,
            position: Offset(left + 2.5, bottom - .4),
            size: const Size(2, 1.15),
            label: isDoor ? '안쪽으로 난 아치' : '기억의 뿌리',
            blocks: !isDoor,
            collisionSize: isDoor ? null : const Size(1.35, .36),
            speech: isDoor ? '아치 안쪽에 작은 방이 있어요.' : null,
            warp: isDoor,
          ),
        );
      }

      final centerX = room.center.dx;
      final centerY = room.center.dy;
      switch (index) {
        case 1:
          objects.add(
            _TileObject(
              kind: _TileObjectKind.chest,
              position: Offset(centerX, centerY),
              size: const Size(1.1, 1.05),
              label: '잠긴 기록함',
              blocks: true,
              collisionSize: const Size(.7, .34),
            ),
          );
        case 2:
          objects.add(
            _TileObject(
              kind: _TileObjectKind.npc,
              position: Offset(centerX, centerY),
              size: const Size(.8, 1.2),
              label: '기록지기 모아',
              blocks: true,
              collisionSize: const Size(.44, .32),
              speech: switch (regionCode) {
                'echo_well' =>
                  '물이 말을 되돌려줘요. 여기선 크게 말하지 않는 게 좋아요.',
                'starlight_seed_vault' =>
                  '씨앗들이 아직 잠들지 못했어요. 이름표를 찾아 주면 좋을 텐데.',
                'heartwood_observatory' =>
                  '나이테가 어긋난 자리가 있어요. 밟으면 소리가 달라요.',
                _ => '장부가 엉킨 자리는 돌아가세요. 억지로 풀면 더 엉켜요.',
              },
            ),
          );
          objects.add(
            _TileObject(
              kind: _TileObjectKind.item,
              position: Offset(centerX + 1.6, centerY + .8),
              size: const Size(.55, .55),
              label: '기억 조각',
            ),
          );
        case 3:
          // 엉킴은 **수호 스테이지에만** 둔다. 사건·발견 스테이지에 두면 붙었을
          // 때 열리는 것이 전투가 아니라 엉뚱한 사건이 된다.
          if (!withGuardian) break;
          objects.add(
            _TileObject(
              kind: _TileObjectKind.monster,
              position: Offset(centerX, centerY),
              size: const Size(1.05, 1.05),
              label: '기록을 먹는 얽힘',
              blocks: true,
              collisionSize: const Size(.62, .38),
            ),
          );
      }
    }

    objects.add(
      _TileObject(
        kind: _TileObjectKind.altar,
        position: goal,
        size: const Size(1.5, 1.6),
        label: '빛나는 기록 제단',
        blocks: true,
        collisionSize: const Size(.9, .42),
      ),
    );

    return _TileField(
      regionCode: regionCode,
      width: width,
      height: height,
      spawn: spawn,
      goal: goal,
      palette: palette,
      terrain: terrain,
      objects: objects,
    );
  }

  /// 아치 안쪽의 작은 방.
  ///
  /// 바깥 들판 하나로만 이루어진 스테이지는 `지나간다`는 느낌뿐이다. 들어갔다
  /// 나오는 곳이 하나만 있어도 세계가 접혀 있다는 인상이 생긴다 — 포켓몬의
  /// 집·동굴이 하는 일이 이것이다.
  factory _TileField.interior(String regionCode, int stageNo) {
    const width = 17;
    const height = 13;
    final palette = _TilePalette.forRegion(regionCode);
    final random = _FieldRandom('$regionCode#interior', stageNo);

    final terrain = List<_TileTerrain>.filled(
      width * height,
      _TileTerrain.moss,
    );
    bool inside(int x, int y) =>
        x >= 2 && y >= 2 && x < width - 2 && y < height - 2;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (inside(x, y)) terrain[y * width + x] = _TileTerrain.floor;
      }
    }

    final objects = <_TileObject>[];
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (inside(x, y)) continue;
        final touches = inside(x - 1, y) ||
            inside(x + 1, y) ||
            inside(x, y - 1) ||
            inside(x, y + 1);
        if (!touches) continue;
        objects.add(
          _TileObject(
            kind: _TileObjectKind.wall,
            position: Offset(x + .5, y + 1),
            // 한 칸보다 높게 세운다. 발밑은 그대로 한 칸이라 걷는 느낌은
            // 안 바뀌고, 뒤로 지나가면 머리가 가려져 벽 안쪽에 있는 것으로
            // 읽힌다. 포켓몬의 벽이 그렇게 서 있다.
            // 폭은 정확히 한 칸. 벽 그림이 칸을 꽉 채우고 좌우가 물려 있어서
            // 조금이라도 넓히면 이음매가 겹쳐 두 번 그려진다.
            size: const Size(1, 1.5),
            label: '기록벽',
            blocks: true,
            collisionSize: const Size(1, 1),
          ),
        );
      }
    }

    // 벽을 따라 서가와 등불. 안쪽이 비면 들어온 보람이 없다.
    for (var x = 3; x < width - 3; x += 3) {
      objects.add(
        _TileObject(
          kind: random.next(3) == 0
              ? _TileObjectKind.lantern
              : _TileObjectKind.shelf,
          position: Offset(x + .5, 3.9),
          size: const Size(1.8, 1.15),
          label: '안쪽 서가',
          blocks: true,
          collisionSize: const Size(1.28, .4),
        ),
      );
    }
    objects.add(
      const _TileObject(
        kind: _TileObjectKind.chest,
        position: Offset(8.5, 7.5),
        size: Size(1.1, 1.05),
        label: '안쪽 기록함',
        blocks: true,
        collisionSize: Size(.7, .34),
      ),
    );
    // 나가는 문.
    objects.add(
      const _TileObject(
        kind: _TileObjectKind.root,
        position: Offset(8.5, 10.5),
        size: Size(2, 1.15),
        label: '바깥으로 난 아치',
        blocks: false,
        speech: '아치를 지나 바깥으로 나가요.',
        warp: true,
      ),
    );

    return _TileField(
      regionCode: regionCode,
      width: width,
      height: height,
      spawn: const Offset(8.5, 9.5),
      goal: const Offset(8.5, 10.5),
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

  /// 바라보는 칸에 있는, 말을 걸 수 있는 물건.
  ///
  /// 가까운 것을 아무거나 집지 않는다. 포켓몬에서 A가 먹히는 조건이 `바로 앞을
  /// 보고 있을 때`인 것과 같다 — 옆에 있는 것이 집히면 무엇에 말을 거는지
  /// 사람이 예측하지 못한다.
  _TileObject? facingTarget(int tileX, int tileY, int dx, int dy) {
    final targetX = tileX + dx;
    final targetY = tileY + dy;
    for (final object in objectsIn(
      Rect.fromLTWH(targetX - .5, targetY - .5, 2, 2),
    )) {
      if (!_canTalkTo(object.kind)) continue;
      // 물건의 발이 그 칸 안에 있으면 그 칸의 물건이다.
      if (object.position.dx.floor() != targetX) continue;
      if (object.position.dy.floor() != targetY &&
          (object.position.dy - 1).floor() != targetY) {
        continue;
      }
      return object;
    }
    return null;
  }

  static bool _canTalkTo(_TileObjectKind kind) => switch (kind) {
        _TileObjectKind.npc ||
        _TileObjectKind.chest ||
        _TileObjectKind.item ||
        _TileObjectKind.shelf ||
        _TileObjectKind.altar ||
        _TileObjectKind.monster ||
        _TileObjectKind.root =>
          true,
        _ => false,
      };

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
/// 드나들 수 있는 문과 실내 방이 제대로 서 있는지.
@visibleForTesting
Map<String, int> expeditionTileWorldTravelDiagnostics(
  String regionCode,
  int stageNo,
) {
  final outside = _TileField.forStage(regionCode, stageNo);
  final inside = _TileField.interior(regionCode, stageNo);
  int warps(_TileField field) =>
      field.objects.where((object) => object.warp).length;
  int blockingWarps(_TileField field) =>
      field.objects.where((object) => object.warp && object.blocks).length;
  return <String, int>{
    'outsideWarps': warps(outside),
    'insideWarps': warps(inside),
    // 문이 막혀 있으면 들어갈 수가 없다.
    'blockingWarps': blockingWarps(outside) + blockingWarps(inside),
    'insideWalls': inside.objects
        .where((object) => object.kind == _TileObjectKind.wall)
        .length,
    'insideSpawnBlocked': inside.blocked(inside.spawn) ? 1 : 0,
  };
}

bool expeditionTileWorldHasRoute(String regionCode, int stageNo) =>
    _TileField.forStage(regionCode, stageNo).hasRouteToGoal;

@visibleForTesting
Map<String, int> expeditionTileWorldChunkDiagnostics(
  String regionCode,
  int stageNo, {
  bool withGuardian = false,
}) {
  final field = _TileField.forStage(
    regionCode,
    stageNo,
    withGuardian: withGuardian,
  );
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
    required double devicePixelRatio,
  }) {
    // 세로 7.25칸을 기준으로 잡았더니 가로가 열 칸밖에 안 들어와 좁았다.
    // BW2가 256×192 화면에 16px 타일로 **열여섯 칸**을 보여 준다. 가로를 기준
    // 으로 바꿔 폰에서 그 정도가 들어오게 하고, 넓은 화면에서는 타일이 너무
    // 커지지 않게 위를 막는다.
    final tilePixels = (viewport.width / 15.5).clamp(20.0, 40.0);
    final visible = Offset(
      viewport.width / tilePixels,
      viewport.height / tilePixels,
    );
    // 카메라를 **화면 픽셀 눈금에 맞춰** 세운다.
    //
    // 아틀라스를 도트로 구우면서 보간을 껐다(`FilterQuality.none`). 그러면
    // 카메라가 소수점 자리에 서 있을 때 픽셀 줄이 프레임마다 생겼다 사라져
    // 바닥이 지글거린다 — 도트 게임에서 제일 흔한 실수다. 원점만 눈금에
    // 맞추면 타일·물건·캐릭터가 **같이** 옮겨져 서로 어긋나지 않는다.
    final grid = tilePixels * devicePixelRatio;
    double snap(double value) => (value * grid).roundToDouble() / grid;
    final origin = Offset(
      snap(
        (player.dx - visible.dx / 2)
            .clamp(0.0, math.max(0.0, field.width - visible.dx)),
      ),
      snap(
        (player.dy - visible.dy / 2)
            .clamp(0.0, math.max(0.0, field.height - visible.dy)),
      ),
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
    // 도트는 **보간하지 않는다.** 땅만 medium으로 부드럽게 그리고 캐릭터는
    // none으로 또렷하게 그리면 발밑이 흐려서 같은 세계에 서 있지 않아 보인다.
    // 아틀라스를 24칸 격자로 구웠으니 늘릴 때도 최근접이라야 결이 산다.
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
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
          ..isAntiAlias = false
          ..filterQuality = FilterQuality.none,
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
