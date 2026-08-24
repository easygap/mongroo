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

  /// 아틀라스 조각 표. 굽기가 내놓은 JSON을 그대로 읽는다.
  Map<String, Rect> _atlasSlots = const <String, Rect>{};

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

  /// 조각 표를 읽는다.
  ///
  /// 굽는 쪽과 그리는 쪽이 배치를 각자 계산하면 언젠가 갈라진다. 실제로
  /// 조각을 스물넷 더했을 때 화면이 새까맣게 나왔다.
  Future<Map<String, Rect>> _loadAtlasSlots() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/adventure/overworld/expedition-tile-atlas-v2.json',
      );
      final manifest = json.decode(raw) as Map<String, dynamic>;
      final regions = manifest['regions'] as Map<String, dynamic>;
      final entries =
          regions[widget.expedition.region.code] as Map<String, dynamic>?;
      if (entries == null) return const <String, Rect>{};
      return <String, Rect>{
        for (final entry in entries.entries)
          entry.key: Rect.fromLTWH(
            ((entry.value as Map<String, dynamic>)['x'] as num).toDouble(),
            (entry.value['y'] as num).toDouble(),
            (entry.value['w'] as num).toDouble(),
            (entry.value['h'] as num).toDouble(),
          ),
      };
    } on Object catch (error) {
      debugPrint('Expedition tile atlas manifest unreadable: $error');
      return const <String, Rect>{};
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
      final slots = await _loadAtlasSlots();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _atlas?.dispose();
        _atlas = frame.image;
        if (slots.isNotEmpty) _atlasSlots = slots;
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

  /// 지금 이 화면이 서버에 무언가를 보낼 수 있는 상태인가.
  ///
  /// 말풍선이 떠 있는지는 **여기 넣지 않는다.** 말풍선은 걸음을 멈추라는
  /// 뜻이지 조우를 취소하라는 뜻이 아니다. 넣어 두었더니 엉킴에 말을 걸 때
  /// `_interact`가 말풍선을 먼저 띄우는 바람에 `_enterDestination`이 첫 줄에서
  /// 되돌아가, 전투가 영영 열리지 않았다. 실기에서 걸어 보고서야 나왔다.
  bool get _canReachServer =>
      widget.expedition.run.phase == 'exploring' &&
      !ref.read(expeditionControllerProvider).interactionLocked &&
      !_movePending;

  /// 걸어도 되는가. 말풍선을 읽는 동안에는 멈춘다.
  bool get _movementEnabled => _speech == null && _canReachServer;

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
      // 상자·조각도 자리마다 다른 말을 할 수 있다. 같은 문장만 돌아오면
      // 세 번째 상자부터는 열 이유가 사라진다.
      _TileObjectKind.chest => taken
          ? '이미 열어 본 기록함이에요. 안은 비어 있어요.'
          : object.speech ?? '기록함을 열었어요. 눅눅한 종이 냄새가 올라와요.',
      _TileObjectKind.item => taken
          ? '아까 주운 자리예요.'
          : object.speech ?? '기억 조각을 주웠어요. 손끝이 따뜻해져요.',
      _TileObjectKind.shelf => '서가가 기울어 있어요. 책등의 글씨는 지워졌어요.',
      _TileObjectKind.altar => '제단이 희미하게 빛나요. 여기서 다음 장면이 열려요.',
      _TileObjectKind.monster => '엉킴과 눈이 마주쳤어요. 여기서 붙습니다.',
      _TileObjectKind.pillar =>
        object.speech ?? '석주에 오래된 문양이 남아 있어요. 이끼가 홈을 따라 자랐어요.',
      _TileObjectKind.crystal => object.speech ??
          '기억 결정이 은은하게 울려요. 가까이 서면 오래된 장면이 스쳐요.',
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
    if (_movePending || !_canReachServer) return;
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
            // 캐릭터 상자를 **타일에 비례**시킨다. 70px로 못 박아 두었더니
            // 타일이 23px인 화면에서 캐릭터가 세 칸을 차지해 세계가 좁아
            // 보였다. 96×120 칸 안에서 몸이 차지하는 폭이 60이므로, 몸이 딱
            // 한 칸이 되려면 상자는 1.6칸이어야 한다.
            final actorSize = Size(
              camera.tilePixels * 1.6,
              camera.tilePixels * 1.6 * _walkerCellHeight / _walkerCellWidth,
            );
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
                          atlasSlots: _atlasSlots,
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
                    // 시트의 발 밑선이 칸 아래쪽에 닿게 맞춘 값이다. 발이
                    // 칸 한가운데에 있으면 칸 위에 떠 있는 것으로 보인다.
                    top: playerScreen.dy - actorSize.height * .725,
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
                          atlasSlots: _atlasSlots,
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
                    // 지도 비율(72:52)에 맞춘 상자. 비율이 다르면 안에서 지도가
                    // 붕 뜨고, 억지로 채우면 늘어난다.
                    width: size.width < 370 ? 96 : 112,
                    height: size.width < 370 ? 74 : 86,
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
                          facing: _facing,
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
  shelf,
  lantern,
  chest,
  item,
  npc,
  monster,
  altar,
  root,

  /// 돌기둥. 벽과 같은 돌 켜에서 파생한 조형물이라 같은 건물의 부재로 읽힌다.
  pillar,

  /// 기억 결정. 홀로 서면 이정표, 여럿이 모이면 정원이 된다.
  crystal,
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
        _TileObjectKind.shelf ||
        _TileObjectKind.lantern ||
        _TileObjectKind.root ||
        _TileObjectKind.pillar =>
          _TileObjectLayer.staticScenery,
        _TileObjectKind.chest ||
        _TileObjectKind.item ||
        _TileObjectKind.altar ||
        _TileObjectKind.crystal =>
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
        _TileObjectKind.pillar => Icons.view_column_rounded,
        _TileObjectKind.crystal => Icons.auto_awesome_rounded,
        _ => Icons.place_rounded,
      };

  Color get color => switch (kind) {
        _TileObjectKind.chest => const Color(0xFFFFD27A),
        _TileObjectKind.item => const Color(0xFF84F1E2),
        _TileObjectKind.npc => const Color(0xFFB9E6B1),
        _TileObjectKind.monster => const Color(0xFFFFA08F),
        _TileObjectKind.altar => const Color(0xFF9AE8F0),
        _TileObjectKind.root => const Color(0xFF91A55B),
        _TileObjectKind.pillar => const Color(0xFFBFB9A6),
        _TileObjectKind.crystal => const Color(0xFF9FE8FF),
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
      hash = _mul32(hash, 16777619);
    }
    _state = hash == 0 ? 1 : hash;
  }

  /// 32비트 곱셈. **한 번에 곱하지 않는다.**
  ///
  /// `(hash * 16777619) & 0xFFFFFFFF`로 쓰면 네이티브와 웹이 다른 땅을 만든다.
  /// 곱은 최대 2^56인데 dart2js에서 int는 double이라 2^53을 넘는 순간 아래
  /// 비트가 날아가고, 그 뒤에 마스크를 씌워 봐야 이미 다른 값이다. 실제로
  /// 웹에서 걸어 보니 테스트가 보는 지형과 출발 칸부터 달랐다.
  ///
  /// 16비트씩 쪼개면 중간값이 2^40을 넘지 않아 어느 쪽에서도 정확하다.
  static int _mul32(int a, int b) {
    final low = (a & 0xFFFF) * b;
    final high = ((a >> 16) * b) & 0xFFFF;
    return (low + (high << 16)) & 0xFFFFFFFF;
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

/// 칸의 재질.
///
/// 벽이 여기 들어온 것이 핵심이다. 앞 판은 벽을 **물건**으로 놓았는데, 물건은
/// 이웃을 볼 수 없어서 윗면·앞면·모서리를 가려 쓸 수가 없었다. 그래서 같은
/// 그림 하나를 늘어놓았고, 그게 쯔꾸르 기본 소재를 깐 화면처럼 보인 이유다.
enum _TileTerrain { floor, moss, water, wall }

class _TileCell {
  const _TileCell({
    required this.x,
    required this.y,
    required this.terrain,
    required this.variant,
    required this.mask,
  });

  /// 여덟 이웃이 **나와 같은 재질인가**. 오토타일은 이 한 값으로 정해진다.
  ///
  /// 변 넷과 대각선 넷을 함께 본다. 대각선은 양옆 변이 모두 같을 때만 뜻이
  /// 있다 - 점 하나로만 닿은 이웃은 그릴 것이 없기 때문이다. 47조각 블롭
  /// 오토타일이 256가지를 47가지로 줄이는 것도 같은 규칙이다.
  static const north = 1;
  static const east = 2;
  static const south = 4;
  static const west = 8;
  static const northEast = 16;
  static const southEast = 32;
  static const southWest = 64;
  static const northWest = 128;

  final int x;
  final int y;
  final _TileTerrain terrain;
  final int variant;

  /// 같은 재질인 이웃의 비트합.
  final int mask;

  bool same(int bit) => mask & bit != 0;

  /// 그 대각선 자리에만 다른 재질이 물려 있는가.
  ///
  /// 양옆 변이 이미 다르면 변 조각이 그 자리를 덮으므로 모서리는 그리지 않는다.
  bool cornerOnly(int corner, int sideA, int sideB) =>
      !same(corner) && same(sideA) && same(sideB);
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
        var mask = 0;
        // 같은 재질만 같은 것으로 친다.
        //
        // 처음에는 벽과 이끼를 한 덩어리로 쳤는데, 그러면 벽 아래가 이끼일 때
        // `이어져 있다`고 판단해 **앞면을 안 그린다.** 벽 덩어리의 바깥 경계도
        // 엄연한 끝이라 음영과 앞면이 붙어야 한다.
        bool alike(int nx, int ny) => terrainAt(nx, ny) == terrain;
        if (alike(x, y - 1)) mask |= _TileCell.north;
        if (alike(x + 1, y)) mask |= _TileCell.east;
        if (alike(x, y + 1)) mask |= _TileCell.south;
        if (alike(x - 1, y)) mask |= _TileCell.west;
        if (alike(x + 1, y - 1)) mask |= _TileCell.northEast;
        if (alike(x + 1, y + 1)) mask |= _TileCell.southEast;
        if (alike(x - 1, y + 1)) mask |= _TileCell.southWest;
        if (alike(x - 1, y - 1)) mask |= _TileCell.northWest;
        chunks[(y ~/ chunkSize) * chunkColumns + x ~/ chunkSize].cells.add(
              _TileCell(
                x: x,
                y: y,
                terrain: terrain,
                // The painterly ground is one sealed 4x4 macro texture. World
                // coordinates select its matching phase so natural brushwork
                // crosses cell boundaries without a visible grid.
                variant: (x & 3) | ((y & 3) << 2),
                mask: mask,
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

  /// 미니맵 투영. 배경과 그 위 레이어가 같은 눈금을 써야 점이 지형에 붙는다.
  ///
  /// 축척은 가로세로 중 작은 쪽 **하나**다. 앞 판은 두 축을 따로 늘여 상자에
  /// 맞췄는데, 그러면 방이 납작해져서 지도 모양과 걷는 땅의 모양이 어긋난다.
  /// 지도는 비율이 맞아야 모양만 보고 자리를 찾을 수 있다.
  ({double scale, Offset origin}) minimapFrame(Size size) {
    const inset = 5.0;
    final scale = math.min(
      (size.width - inset * 2) / width,
      (size.height - inset * 2) / height,
    );
    return (
      scale: scale,
      origin: Offset(
        (size.width - width * scale) / 2,
        (size.height - height * scale) / 2,
      ),
    );
  }

  /// 미니맵 배경. 지도가 할 일은 하나 - 구조가 한눈에 읽히는 것이다.
  ///
  /// 앞 판은 바닥색 판에 바닥이 아닌 칸을 덧칠해서 벽과 이끼가 한 색으로
  /// 뭉개졌고, 길을 막는 물건을 종류 불문 검은 점으로 찍어서 서가 하나하나가
  /// 후추처럼 흩어졌다. 방 모양은 안 보이고 얼룩만 보이는 지도였다.
  ///
  /// 지금은 값의 위계로 그린다. 어두운 바탕 위에 이끼는 살짝, 벽은 돌빛으로
  /// 도드라지고, 걷는 바닥이 가장 밝다. 벽 두 겹이 밝은 바닥을 두르면서
  /// 방과 복도의 윤곽선 노릇을 한다 - 선을 따로 긋지 않아도 구조가 남는다.
  ui.Picture minimapBackground(Size size) {
    final cached = _minimapPicture;
    if (cached != null && _minimapPictureSize == size) return cached;
    cached?.dispose();
    final frame = minimapFrame(size);
    final scale = frame.scale;
    final origin = frame.origin;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final map = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      width * scale,
      height * scale,
    );
    // 지형 덩어리가 각지게 끝나면 지도가 아니라 스크린샷 조각으로 보인다.
    // 모서리를 액자와 같은 결로 둥글려 둔다.
    canvas.clipRRect(
      RRect.fromRectAndRadius(map.inflate(1), const Radius.circular(4)),
    );
    canvas.drawRect(
      map.inflate(1),
      Paint()..color = Color.lerp(palette.voidColor, Colors.black, .38)!,
    );

    final mossInk = Paint()
      ..color = Color.lerp(palette.voidColor, palette.moss, .40)!;
    final wallInk = Paint()
      ..color = Color.lerp(palette.voidColor, palette.stone, .55)!;
    final floorInk = Paint()
      ..color = Color.lerp(palette.floorA, Colors.white, .30)!;
    final waterInk = Paint()
      ..color = Color.lerp(palette.water, Colors.white, .14)!;
    for (final chunk in _chunks) {
      for (final cell in chunk.cells) {
        final ink = switch (cell.terrain) {
          _TileTerrain.moss => mossInk,
          _TileTerrain.wall => wallInk,
          _TileTerrain.floor => floorInk,
          _TileTerrain.water => waterInk,
        };
        canvas.drawRect(
          Rect.fromLTWH(
            origin.dx + cell.x * scale,
            origin.dy + cell.y * scale,
            // 반 픽셀 겹침. 소수 축척에서 칸 사이가 실금으로 갈라지지 않게.
            scale + .5,
            scale + .5,
          ),
          ink,
        );
      }
    }

    // 표식은 다섯 가지뿐이다. 상자·결정·사람·엉킴, 그리고 제단.
    //
    // 서가나 기둥 같은 조형물은 찍지 않는다. 전부 찍으면 지도가 다시 후추가
    // 되는데, 눌러도 아무 일 없는 점은 지도에서 소음이다. 벽 너머 장식으로
    // 흩어 둔 결정도 바닥 위가 아니면 거른다 - 갈 수 없는 곳의 표식은 거짓말이다.
    void dot(Offset foot, Color color, double radius) {
      if (terrainAt(foot.dx.floor(), (foot.dy - .5).floor()) !=
          _TileTerrain.floor) {
        return;
      }
      final center = Offset(
        origin.dx + foot.dx * scale,
        origin.dy + foot.dy * scale,
      );
      // 밝은 바닥 위에서도 남게 어두운 받침을 깔고 색을 얹는다.
      canvas.drawCircle(
        center,
        radius + .9,
        Paint()..color = Color.lerp(palette.voidColor, Colors.black, .45)!,
      );
      canvas.drawCircle(center, radius, Paint()..color = color);
    }

    for (final chunk in _chunks) {
      for (final object in chunk.objects) {
        switch (object.kind) {
          case _TileObjectKind.chest:
            dot(
              object.position,
              Color.lerp(palette.metal, Colors.white, .32)!,
              1.5,
            );
          case _TileObjectKind.crystal:
            dot(object.position, Color.lerp(palette.glow, Colors.white, .2)!,
                1.5);
          case _TileObjectKind.npc:
            dot(object.position, const Color(0xFFCDEBC4), 1.5);
          case _TileObjectKind.monster:
            dot(object.position, const Color(0xFFFF9A85), 1.8);
          case _TileObjectKind.root:
            // 아치 문만 찍는다. 문은 지도에서 찾아 들어가는 곳이다.
            if (object.warp) {
              dot(object.position, Color.lerp(palette.metal, Colors.white, .1)!,
                  1.4);
            }
          default:
            break;
        }
      }
    }

    // 제단은 별 하나로 찍는다. 이 지도에 별은 하나뿐이라, 어디로 가야
    // 하는지가 글자 없이 정해진다.
    final goalCenter = Offset(
      origin.dx + goal.dx * scale,
      origin.dy + goal.dy * scale,
    );
    Path sparkle(double reach, double waist) => Path()
      ..moveTo(goalCenter.dx, goalCenter.dy - reach)
      ..quadraticBezierTo(goalCenter.dx + waist, goalCenter.dy - waist,
          goalCenter.dx + reach, goalCenter.dy)
      ..quadraticBezierTo(goalCenter.dx + waist, goalCenter.dy + waist,
          goalCenter.dx, goalCenter.dy + reach)
      ..quadraticBezierTo(goalCenter.dx - waist, goalCenter.dy + waist,
          goalCenter.dx - reach, goalCenter.dy)
      ..quadraticBezierTo(goalCenter.dx - waist, goalCenter.dy - waist,
          goalCenter.dx, goalCenter.dy - reach)
      ..close();
    canvas.drawPath(
      sparkle(4.6, 1.7),
      Paint()..color = Color.lerp(palette.voidColor, Colors.black, .45)!,
    );
    canvas.drawPath(sparkle(3.7, 1.25), Paint()..color = palette.glow);
    canvas.drawCircle(goalCenter, .95, Paint()..color = Colors.white);

    _minimapPictureSize = size;
    return _minimapPicture = recorder.endRecording();
  }

  void dispose() {
    _minimapPicture?.dispose();
    _minimapPicture = null;
  }

  /// 한 스테이지의 땅을 짓는다.
  ///
  /// 방 여덟을 한 줄로 이은 판을 지나, 이제 **본길 열 방 + 곁가지 세 방**이다.
  /// 순환 복도가 하나 있어 가운데에서 길을 고를 수 있고, 곁가지는 막다른
  /// 데서 함·결정으로 끝난다. 방마다 성격이 다르다 — 주랑에는 석주가 두 줄로
  /// 서고, 결정 정원에는 결정이 모여 자라고, 물뜰에는 못이 파여 있다. 벽 너머
  /// 이끼 벌판에도 조형물을 흩어 화면 어디에도 빈 데가 없게 한다.
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
    // 56×40에 방 여덟을 한 줄로 이은 판이었다. 방마다 볼 것은 생겼지만
    // 갈림길이 없어서 `길을 고른다`가 없었고, 본길 밖은 통째로 빈 이끼였다.
    // 격자를 키우고 본길 열 방에 곁가지 방 셋과 순환 복도 하나를 더한다.
    const width = 72;
    const height = 52;
    const mainRooms = 10;
    final palette = _TilePalette.forRegion(regionCode);
    final random = _FieldRandom(regionCode, stageNo);

    final walkable = List<bool>.filled(width * height, false);
    void carve(int x, int y) {
      if (x < 2 || y < 2 || x >= width - 2 || y >= height - 2) return;
      walkable[y * width + x] = true;
    }

    // ── 방 자리 ───────────────────────────────────────────────────────────
    //
    // 앞 열 개가 본길이다. 왼쪽 아래에서 오른쪽 위로 흐르되 두 번 크게
    // 되꺾는다 — 곧게만 이으면 복도가 그냥 통로가 되고, 되꺾여야 `어디까지
    // 왔지`가 생긴다. 방끼리 두 칸은 떨어져야 한 덩어리로 안 붙는다.
    //
    // 뒤 셋은 곁가지다. 본길 방 하나에서 갈라져 나가 막다른 데서 끝난다.
    // 굳이 안 가도 되지만 가면 함과 결정이 있다. 갈림길이 없는 던전은
    // 탐험이 아니라 이동이다.
    const anchors = <Offset>[
      Offset(9, 44),
      Offset(21, 40),
      Offset(15, 28),
      Offset(28, 24),
      Offset(24, 11),
      Offset(38, 8),
      Offset(45, 20),
      Offset(58, 24),
      Offset(63, 34),
      Offset(64, 12),
      // ── 곁가지: 보물 곁방, 명상 곁방, 침수 곁방 ─────────────────────────
      Offset(6, 18),
      Offset(48, 5),
      Offset(52, 44),
    ];
    // 곁가지가 어느 본길 방에서 갈라지는가.
    const branchParents = <int>[2, 5, 8];
    final rooms = <Rect>[];
    for (var index = 0; index < anchors.length; index++) {
      final anchor = anchors[index];
      // 방마다 크기를 벌린다. 다 비슷하면 열셋이 한 방처럼 느껴진다.
      // 곁가지는 본길보다 작아야 `곁`으로 읽힌다.
      final branch = index >= mainRooms;
      final w = branch ? 7 + random.next(2) * 2 : 10 + random.next(3) * 2;
      final h = branch ? 6 + random.next(2) : 7 + random.next(3);
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

    // 복도가 지나간 칸. 기둥을 여기 세우면 한 칸 폭 복도가 막힌다.
    final corridor = <int>{};

    // ── 복도 ──────────────────────────────────────────────────────────────
    //
    // 본길 아홉 구간 + 곁가지 셋 + 순환 하나. 순환 복도(3↔6)가 있어야 위로
    // 도는 서고 길과 가운데를 가로지르는 길 중에 **고를 수 있다.** 한 줄
    // 던전과 지어진 던전을 가르는 것이 이 선 하나다.
    //
    // 폭은 구간마다 바꾼다. 전부 세 칸이면 어디를 걷든 같은 느낌이라 길이
    // 길기만 하고 기억에 안 남는다. 좁아졌다 넓어지면 리듬이 생긴다.
    final links = <(int, int)>[
      for (var index = 0; index < mainRooms - 1; index++) (index, index + 1),
      (3, 6),
      for (var index = 0; index < branchParents.length; index++)
        (branchParents[index], mainRooms + index),
    ];
    for (final link in links) {
      final from = rooms[link.$1].center;
      final to = rooms[link.$2].center;
      final half = random.next(2);
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
          for (var dy = -half; dy <= half; dy++) {
            for (var dx = -half; dx <= half; dx++) {
              carve(x + dx, y + dy);
              corridor.add((y + dy) * width + x + dx);
            }
          }
        }
      }
    }

    // ── 지형 기둥 ─────────────────────────────────────────────────────────
    //
    // 큰 방이 텅 빈 직사각형이면 `지나가는 곳`이지 `있는 곳`이 아니다. 벽
    // 재질 기둥 몇 개만 박아도 시선이 걸리고 걷는 길이 생긴다.
    //
    // 출발 방(0)과 제단 방(9)은 건드리지 않는다 - 첫 걸음과 마지막 걸음이
    // 막히면 조작이 고장 난 것처럼 보인다. 주랑 방(3)은 석주 조형물이 서고,
    // 곁가지는 좁아서 뺀다. 길이 끊기지 않는지는 검사가 지킨다
    // (`expeditionTileWorldHasRoute`).
    for (var index = 1; index < mainRooms - 1; index++) {
      if (index == 3) continue;
      final room = rooms[index];
      if (room.width < 8 || room.height < 6) continue;
      final left = room.left.round();
      final top = room.top.round();
      final right = room.right.round() - 1;
      final bottom = room.bottom.round() - 1;
      for (final spot in <List<int>>[
        <int>[left + 2, top + 2],
        <int>[right - 2, bottom - 2],
        if (random.next(2) == 0) <int>[right - 2, top + 2],
      ]) {
        final index = spot[1] * width + spot[0];
        // 복도가 지나는 칸에는 세우지 않는다. 한 칸 폭 복도라면 기둥 하나로
        // 길이 통째로 끊긴다 - 그것도 기둥은 지형이라 물건 복구로는 못 살린다.
        if (corridor.contains(index)) continue;
        walkable[index] = false;
      }
    }

    // ── 복도 골방 ───────────────────────────────────────────────────────────
    //
    // 복도 중간에서 세 칸짜리 홈이 파여 막다른 데서 끝난다. 곁가지 방보다
    // 작은, 지나가다 흘낏 보고 줍는 자리다.
    //
    // **벽과 지형을 계산하기 전에** 판다. 나중에 파면 걷기 표만 바뀌고 그림은
    // 벽으로 남아, 지나갈 수 있다고 판단하면서 실제로는 막힌 칸이 생긴다.
    final sideChests = <List<int>>[];
    for (var index = 1; index < mainRooms - 1; index += 3) {
      final from = rooms[index].center;
      final to = rooms[index + 1].center;
      final midX = ((from.dx + to.dx) / 2).round();
      final midY = ((from.dy + to.dy) / 2).round();
      final dx = random.next(2) == 0 ? -1 : 1;
      var carved = 0;
      for (var step = 1; step <= 5; step++) {
        final x = midX + dx * step;
        for (var y = midY - 1; y <= midY + 1; y++) {
          if (x < 3 || x >= width - 3 || y < 3 || y >= height - 3) continue;
          carve(x, y);
          carved++;
        }
      }
      if (carved > 0) sideChests.add(<int>[midX + dx * 4, midY]);
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
      <int>[6, 7, 3],
      <int>[26, 4, 2],
      <int>[36, 30, 3],
      <int>[66, 46, 3],
      <int>[34, 47, 3],
      <int>[69, 26, 2],
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
    // 벽은 **두 겹**이다. 한 겹이면 위에서 봤을 때 선 하나라 두께가 안 읽히고,
    // 안쪽 겹이 있어야 가장자리 음영을 두를 자리가 생긴다.
    bool wallAt(int x, int y) =>
        x >= 0 &&
        y >= 0 &&
        x < width &&
        y < height &&
        terrain[y * width + x] == _TileTerrain.wall;
    for (var layer = 0; layer < 2; layer++) {
      final added = <int>[];
      for (var y = 1; y < height - 1; y++) {
        for (var x = 1; x < width - 1; x++) {
          if (open(x, y)) continue;
          final here = terrain[y * width + x];
          if (here == _TileTerrain.water || here == _TileTerrain.wall) continue;
          final touches = layer == 0
              ? open(x - 1, y) ||
                  open(x + 1, y) ||
                  open(x, y - 1) ||
                  open(x, y + 1)
              : wallAt(x - 1, y) ||
                  wallAt(x + 1, y) ||
                  wallAt(x, y - 1) ||
                  wallAt(x, y + 1);
          if (!touches) continue;
          added.add(y * width + x);
        }
      }
      for (final index in added) {
        terrain[index] = _TileTerrain.wall;
      }
    }

    // 방마다 성격을 준다.
    //
    // 앞 판은 여덟 방이 전부 `벽을 따라 서가, 가운데 뭔가 하나`였다. 상호작용
    // 가능한 것이 스테이지 전체에 셋뿐이라 걸어도 볼 게 없었다. 방마다 다른
    // 것을 두면 `아까 그 방`과 `여기`가 구분되고, 걸어 다닐 이유가 생긴다.
    //
    // 자리는 겹치지 않게 잡는다. 물건 위에 물건을 올리면 둘 다 못 알아본다.
    final taken = <int>{};
    // 길을 막는 물건이 어느 칸에 있는지 기억한다. 나중에 길이 끊기면 여기서
    // 되짚어 치운다.
    final blockers = <int, int>{};
    bool free(int x, int y) =>
        open(x, y) && !taken.contains(y * width + x);
    bool place(
      int x,
      int y, {
      required _TileObjectKind kind,
      required Size size,
      required String label,
      bool blocks = true,
      Size? collisionSize,
      String? speech,
      bool warp = false,
      double footOffset = 1.0,
    }) {
      if (!free(x, y)) return false;
      // 복도에는 막는 것을 두지 않는다. 한 칸 폭 복도가 섞여 있어서, 복도에
      // 서가 하나만 놓여도 제단까지 못 간다. 나중에 치우는 것보다 애초에
      // 안 놓는 편이 방이 헐거워지지 않는다.
      if (blocks && corridor.contains(y * width + x)) return false;
      taken.add(y * width + x);
      final object = _TileObject(
        kind: kind,
        position: Offset(x + .5, y + footOffset),
        size: size,
        label: label,
        blocks: blocks,
        collisionSize: collisionSize,
        speech: speech,
        warp: warp,
      );
      if (blocks) {
        // 한 칸만 적으면 안 된다. 서가처럼 옆으로 넓은 것은 이웃 칸까지
        // 막는데, 그걸 빼놓으면 길이 열려 있다고 잘못 판단한다.
        final bounds = object.collisionBounds.inflate(.34);
        for (var by = bounds.top.floor(); by <= bounds.bottom.floor(); by++) {
          for (var bx = bounds.left.floor(); bx <= bounds.right.floor(); bx++) {
            if (bx < 0 || by < 0 || bx >= width || by >= height) continue;
            blockers[by * width + bx] = objects.length;
          }
        }
      }
      objects.add(object);
      return true;
    }

    /// 그 자리가 막혔으면 **가까운 빈 칸**을 찾아 놓는다.
    ///
    /// 방 한가운데는 복도가 들어오는 자리라 막는 물건을 못 놓는다. 그렇다고
    /// NPC나 엉킴을 그냥 빼면 방이 비고 전투가 안 열린다. 한두 칸 옆으로 밀면
    /// 둘 다 산다.
    bool placeNear(
      int x,
      int y, {
      required _TileObjectKind kind,
      required Size size,
      required String label,
      bool blocks = true,
      Size? collisionSize,
      String? speech,
    }) {
      for (var ring = 0; ring <= 3; ring++) {
        for (var dy = -ring; dy <= ring; dy++) {
          for (var dx = -ring; dx <= ring; dx++) {
            if (ring > 0 && dx.abs() != ring && dy.abs() != ring) continue;
            if (place(
              x + dx,
              y + dy,
              kind: kind,
              size: size,
              label: label,
              blocks: blocks,
              collisionSize: collisionSize,
              speech: speech,
            )) {
              return true;
            }
          }
        }
      }
      return false;
    }

    void shelf(int x, int y, {String label = '무너진 서가'}) => place(
          x,
          y,
          kind: _TileObjectKind.shelf,
          size: const Size(1.8, 1.15),
          label: label,
          collisionSize: const Size(1.28, .4),
          footOffset: 1.9,
        );
    void lantern(int x, int y) => place(
          x,
          y,
          kind: _TileObjectKind.lantern,
          size: const Size(.9, 1.35),
          label: '기록 등불',
          collisionSize: const Size(.4, .3),
          footOffset: 1.9,
        );
    void chest(int x, int y, String label, {String? speech}) => placeNear(
          x,
          y,
          kind: _TileObjectKind.chest,
          size: const Size(1.1, 1.05),
          label: label,
          collisionSize: const Size(.7, .34),
          speech: speech,
        );
    void shard(int x, int y, String label, {String? speech}) => place(
          x,
          y,
          kind: _TileObjectKind.item,
          size: const Size(.55, .55),
          label: label,
          blocks: false,
          speech: speech,
        );
    void root(int x, int y, {String label = '기억의 뿌리'}) => place(
          x,
          y,
          kind: _TileObjectKind.root,
          size: const Size(2, 1.15),
          label: label,
          collisionSize: const Size(1.35, .36),
          footOffset: 1.6,
        );
    // 1.15×1.95칸. 세로 늘림이 1.7배로 뿌리와 같다 — 더 홀쭉하게 늘리면
    // 도트가 세로줄로 읽혀 캐릭터와 다른 세계가 된다.
    void pillar(int x, int y, {String label = '이끼 낀 석주'}) => place(
          x,
          y,
          kind: _TileObjectKind.pillar,
          size: const Size(1.15, 1.95),
          label: label,
          collisionSize: const Size(.52, .34),
          footOffset: 1.9,
        );
    void crystal(int x, int y, String label, {String? speech}) => placeNear(
          x,
          y,
          kind: _TileObjectKind.crystal,
          size: const Size(1.15, 1.7),
          label: label,
          collisionSize: const Size(.6, .36),
          speech: speech,
        );

    final spawn = rooms.first.center;
    final goal = rooms[mainRooms - 1].center;
    for (var index = 0; index < rooms.length; index++) {
      final room = rooms[index];
      final left = room.left.round();
      final top = room.top.round();
      final right = room.right.round() - 1;
      final bottom = room.bottom.round() - 1;
      final centerX = room.center.dx.round();
      final centerY = room.center.dy.round();

      // 벽을 따라 늘어놓는다. 방 한가운데 흩뿌리면 지나다닐 수가 없다.
      // 주랑(3)과 결정 정원(8)은 뺀다 — 제 조형물이 서는 방에 서가까지
      // 얹으면 무엇의 방인지 흐려진다.
      if (index != 3 && index != 8) {
        for (var x = left + 1; x <= right - 1; x += 2 + random.next(2)) {
          if (random.next(4) == 0) {
            lantern(x, top + 1);
          } else {
            shelf(x, top + 1);
          }
        }
      }

      switch (index) {
        // ── 출발 방. 첫인상이라 읽을 것을 하나 둔다 ───────────────────────
        case 0:
          shelf(left + 1, bottom - 1, label: '입구 선반');
          shard(right - 2, bottom - 2, '떨어진 이름표');
          lantern(right - 1, centerY);

        // ── 문이 있는 방. 아치로 안쪽 방에 든다 ───────────────────────────
        case 1:
          place(
            left + 2,
            bottom - 1,
            kind: _TileObjectKind.root,
            size: const Size(2, 1.15),
            label: '안쪽으로 난 아치',
            blocks: false,
            speech: '아치 안쪽에 작은 방이 있어요.',
            warp: true,
            footOffset: 1.6,
          );
          chest(centerX, centerY, '잠긴 기록함');
          shard(right - 2, top + 3, '눅눅한 쪽지');

        // ── 지킴이가 있는 방 ───────────────────────────────────────────────
        case 2:
          placeNear(
            centerX,
            centerY,
            kind: _TileObjectKind.npc,
            size: const Size(.8, 1.2),
            label: '기록지기 모아',
            collisionSize: const Size(.44, .32),
            speech: switch (regionCode) {
              'echo_well' => '물이 말을 되돌려줘요. 여기선 크게 말하지 않는 게 좋아요.',
              'starlight_seed_vault' =>
                '씨앗들이 아직 잠들지 못했어요. 이름표를 찾아 주면 좋을 텐데.',
              'heartwood_observatory' =>
                '나이테가 어긋난 자리가 있어요. 밟으면 소리가 달라요.',
              _ => '장부가 엉킨 자리는 돌아가세요. 억지로 풀면 더 엉켜요.',
            },
          );
          shard(centerX + 2, centerY + 1, '기억 조각');
          shard(left + 2, bottom - 2, '흩어진 낱장');
          lantern(right - 1, bottom - 2);

        // ── 주랑. 석주가 두 줄로 서고 끝에 결정이 빛난다 ──────────────────
        //
        // 순환 복도가 갈라지는 방이라 지나는 사람이 가장 많다. 기둥 사이로
        // 걷는 길이 곧 방의 정체라, 다른 꾸밈은 걷어 낸다.
        case 3:
          for (var x = left + 2; x <= right - 2; x += 3) {
            pillar(x, centerY - 2, label: '주랑의 석주');
            pillar(x, centerY + 2, label: '주랑의 석주');
          }
          crystal(
            right - 2,
            centerY,
            '주랑의 기억 결정',
            speech: '석주 사이를 지나간 발소리가 결정 안에 겹겹이 쌓여 있어요.',
          );
          shard(left + 2, centerY, '닳은 주춧돌 조각');

        // ── 서고. 서가를 줄줄이 세워 통로를 만든다 ────────────────────────
        case 4:
          for (var y = top + 3; y <= bottom - 2; y += 2) {
            for (var x = left + 2; x <= right - 2; x += 3) {
              shelf(x, y);
            }
          }
          shard(right - 1, bottom - 1, '색이 바랜 표찰');
          chest(left + 2, top + 3, '서고 구석의 함',
              speech: '서가 뒤에 밀려 들어가 있던 함이에요. 먼지가 손가락만큼 쌓였어요.');

        // ── 큰 홀. 엉킴이 웅크리거나, 등불이 홀을 밝힌다 ──────────────────
        case 5:
          if (withGuardian) {
            placeNear(
              centerX,
              centerY,
              kind: _TileObjectKind.monster,
              size: const Size(1.05, 1.05),
              label: '기록을 먹는 얽힘',
              collisionSize: const Size(.62, .38),
            );
            lantern(left + 2, top + 3);
            lantern(right - 2, top + 3);
          } else {
            // 엉킴이 없으면 텅 빈 방이 된다. 등불을 둘러 홀로 만든다.
            for (final spot in <List<int>>[
              <int>[left + 2, top + 3],
              <int>[right - 2, top + 3],
              <int>[left + 2, bottom - 2],
              <int>[right - 2, bottom - 2],
            ]) {
              lantern(spot[0], spot[1]);
            }
            shard(centerX, centerY, '식은 등불 심지');
          }

        // ── 물뜰. 방 안에 못을 파서 걷는 결을 바꾼다 ──────────────────────
        case 6:
          // 못은 **구석에** 판다. 복도는 방 중심으로 들어오므로 가운데를 파면
          // 길이 물에 잠겨 제단까지 못 간다(실제로 끊겼다). 중심을 지나는
          // 가로줄·세로줄도 비워 둬 물을 돌아갈 수 있게 한다.
          for (var y = bottom - 3; y <= bottom - 2; y++) {
            for (var x = right - 4; x <= right - 2; x++) {
              if (!open(x, y)) continue;
              if (y >= centerY - 1 && y <= centerY + 1) continue;
              if (x >= centerX - 1 && x <= centerX + 1) continue;
              terrain[y * width + x] = _TileTerrain.water;
              walkable[y * width + x] = false;
              taken.add(y * width + x);
            }
          }
          root(left + 2, top + 2);
          chest(left + 2, bottom - 2, '물가에 젖은 함');
          placeNear(
            centerX - 2,
            top + 2,
            kind: _TileObjectKind.npc,
            size: const Size(.8, 1.2),
            label: '물가 기록원',
            collisionSize: const Size(.44, .32),
            speech: switch (regionCode) {
              'echo_well' => '우물물이 여기까지 올라와요. 발소리가 두 번 들리면 한 번은 물속 것이에요.',
              'starlight_seed_vault' =>
                '물에 별빛이 고여요. 씨앗들이 목을 축이러 내려오곤 해요.',
              'heartwood_observatory' =>
                '이 못은 관측소가 목이 마를 때 판 거예요. 나무는 물을 기억하거든요.',
              _ => '젖은 기록은 급히 넘기면 찢어져요. 물가에서는 천천히 걸어요.',
            },
          );

        // ── 폐허. 뿌리가 무너져 들어온 방 ─────────────────────────────────
        case 7:
          root(left + 2, centerY, label: '무너진 뿌리');
          root(right - 3, bottom - 2, label: '갈라진 뿌리');
          pillar(right - 2, top + 2, label: '옛 석주');
          shard(centerX, top + 2, '떨어진 나이테');
          chest(centerX + 2, bottom - 2, '흙에 묻힌 함');
          placeNear(
            left + 2,
            bottom - 2,
            kind: _TileObjectKind.npc,
            size: const Size(.8, 1.2),
            label: '길 잃은 기록원',
            collisionSize: const Size(.44, .32),
            speech: '여기서부터는 발밑이 무너져요. 벽을 짚고 가세요.',
          );

        // ── 결정 정원. 결정이 모여 자라는 뜰 ──────────────────────────────
        case 8:
          crystal(
            centerX - 2,
            centerY - 1,
            '큰 기억 결정',
            speech: '어른 키만 한 결정이에요. 안쪽에서 빛이 숨처럼 오르내려요.',
          );
          crystal(
            centerX + 2,
            centerY,
            '갈라진 기억 결정',
            speech: '금 간 자리로 오래된 장면이 새어 나와요. 아는 얼굴이 스친 것 같아요.',
          );
          crystal(
            centerX,
            bottom - 2,
            '어린 기억 결정',
            speech: '아직 무릎 높이예요. 여린 빛이 손끝을 따라와요.',
          );
          shard(left + 2, top + 3, '결정 부스러기');
          shard(right - 2, bottom - 2, '맑은 결정 조각');
          placeNear(
            left + 2,
            centerY,
            kind: _TileObjectKind.npc,
            size: const Size(.8, 1.2),
            label: '정원지기 루',
            collisionSize: const Size(.44, .32),
            speech: switch (regionCode) {
              'echo_well' => '결정마다 메아리가 하나씩 잠들어 있어요. 두드리면 깨요.',
              'starlight_seed_vault' =>
                '떨어진 별빛이 굳어 결정이 됐다고 해요. 정말인지는 저도 몰라요.',
              'heartwood_observatory' =>
                '나이테 사이에서 자란 결정이에요. 나무의 꿈이 굳은 거래요.',
              _ => '결정은 함부로 캐면 빛이 죽어요. 눈으로만 담아 가세요.',
            },
          );
          lantern(right - 2, top + 3);

        // ── 제단 방. 석주가 제단으로 가는 길을 세운다 ─────────────────────
        case 9:
          pillar(centerX - 2, bottom - 1, label: '제단 앞 석주');
          pillar(centerX + 2, bottom - 1, label: '제단 앞 석주');
          lantern(left + 2, centerY);
          lantern(right - 2, centerY);

        // ── 보물 곁방. 막다른 데까지 온 값을 한다 ─────────────────────────
        case 10:
          chest(
            centerX,
            centerY,
            '감춰 둔 기록함',
            speech: '겹겹이 싸 둔 기록이 나왔어요. 숨긴 사람은 돌아오지 못했나 봐요.',
          );
          shard(left + 2, bottom - 2, '숨겨진 기억 조각');
          lantern(right - 2, top + 3);

        // ── 명상 곁방. 결정 하나가 방을 밝힌다 ────────────────────────────
        case 11:
          crystal(
            centerX,
            centerY,
            '고요한 기억 결정',
            speech: '이 방의 결정은 울리지 않고 듣기만 해요. 두고 간 말이 많이 쌓였대요.',
          );
          placeNear(
            left + 2,
            bottom - 2,
            kind: _TileObjectKind.npc,
            size: const Size(.8, 1.2),
            label: '견습 기록원',
            collisionSize: const Size(.44, .32),
            speech: '여기 앉아 있으면 결정이 웅웅 울어요. 무섭지만... 조금 좋아요.',
          );
          shard(right - 2, centerY, '기도문 낱장');

        // ── 침수 곁방. 물이 스며든 막다른 방 ──────────────────────────────
        default:
          for (var y = top + 1; y <= top + 3; y++) {
            for (var x = left + 1; x <= left + 3; x++) {
              if (!open(x, y)) continue;
              if (y >= centerY - 1 && y <= centerY + 1) continue;
              if (x >= centerX - 1 && x <= centerX + 1) continue;
              terrain[y * width + x] = _TileTerrain.water;
              walkable[y * width + x] = false;
              taken.add(y * width + x);
            }
          }
          chest(
            right - 2,
            top + 3,
            '물에 잠긴 함',
            speech: '함 안까지 물이 들었지만 글씨는 아직 읽을 수 있어요.',
          );
          shard(centerX, bottom - 2, '젖은 기억 조각');
          root(right - 3, bottom - 2, label: '물을 마시는 뿌리');
      }
    }

    for (final spot in sideChests) {
      chest(spot[0], spot[1], '골방의 기록함');
    }

    // ── 바깥 풍경 ─────────────────────────────────────────────────────────
    //
    // 벽 너머 이끼 벌판이 통째로 비어 있으면 방 안이 아무리 차도 화면
    // 절반이 휑하다. 닿을 수 없는 자리라 충돌은 없지만 카메라에는 늘
    // 담기므로, 뿌리·결정·석주를 드문드문 흩어 `던전 밖에도 세계가 있다`를
    // 만든다. 벽에 붙은 칸은 피한다 — 조형물이 벽 윗면을 덮으면 지붕이
    // 뚫린 것처럼 보인다.
    for (var y = 4; y < height - 4; y += 2) {
      for (var x = 4; x < width - 4; x += 2) {
        if (random.next(8) != 0) continue;
        bool mossAt(int nx, int ny) =>
            terrain[ny * width + nx] == _TileTerrain.moss;
        if (!mossAt(x, y) ||
            !mossAt(x - 1, y) ||
            !mossAt(x + 1, y) ||
            !mossAt(x, y - 1) ||
            !mossAt(x, y + 1)) {
          continue;
        }
        final pick = random.next(6);
        objects.add(
          _TileObject(
            kind: pick == 0
                ? _TileObjectKind.crystal
                : pick == 1
                    ? _TileObjectKind.pillar
                    : _TileObjectKind.root,
            position: Offset(x + .5, y + 1),
            size: pick == 0
                ? const Size(1.15, 1.7)
                : pick == 1
                    ? const Size(1.15, 1.95)
                    : const Size(2, 1.15),
            label: pick == 0
                ? '벌판의 기억 결정'
                : pick == 1
                    ? '쓰러질 듯한 석주'
                    : '벌판의 뿌리',
            blocks: false,
          ),
        );
      }
    }

    // ── 길 복구 ─────────────────────────────────────────────────────────────
    //
    // 복도 폭을 구간마다 바꾸면서 한 칸짜리 복도가 생겼는데, 그 입구에 서가가
    // 놓이면 제단까지 갈 수 없다(서른두 판 중 셋이 그랬다). 물건을 놓지 말아야
    // 할 자리를 규칙으로 다 적기보다, **막혔으면 막은 것을 치운다.**
    // 꾸미기를 어떻게 바꾸든 길은 남는다.
    final removed = <int>{};
    for (var attempt = 0; attempt < 120; attempt++) {
      final startIndex =
          spawn.dy.floor() * width + spawn.dx.floor();
      final goalIndex = goal.dy.floor() * width + goal.dx.floor();
      final queue = <int>[startIndex];
      final seen = <int>{startIndex};
      final frontier = <int>{};
      var cursor = 0;
      while (cursor < queue.length) {
        final index = queue[cursor++];
        final x = index % width;
        final y = index ~/ width;
        for (final step in <(int, int)>[
          (x + 1, y),
          (x - 1, y),
          (x, y + 1),
          (x, y - 1),
        ]) {
          if (step.$1 < 1 || step.$2 < 1) continue;
          if (step.$1 >= width - 1 || step.$2 >= height - 1) continue;
          final next = step.$2 * width + step.$1;
          if (seen.contains(next)) continue;
          if (terrain[next] == _TileTerrain.wall ||
              terrain[next] == _TileTerrain.water) {
            continue;
          }
          if (blockers.containsKey(next) && !removed.contains(next)) {
            // 여기서 길이 끊긴다. 후보로 적어 둔다.
            frontier.add(next);
            continue;
          }
          seen.add(next);
          queue.add(next);
        }
      }
      if (seen.contains(goalIndex)) break;
      if (frontier.isEmpty) break;
      // 닿은 데 맞닿은 것부터 하나씩 치운다. 엉킴과 문은 빼놓는다 -
      // 엉킴이 사라지면 전투가 안 열리고, 문이 사라지면 안쪽 방에 못 든다.
      final removable = frontier.where((tile) {
        final kind = objects[blockers[tile]!].kind;
        return kind != _TileObjectKind.monster && !objects[blockers[tile]!].warp;
      });
      if (removable.isEmpty) break;
      // 사람은 마지막에 치운다. 서가와 사람이 같이 길을 막고 있으면 서가를
      // 치워야지 사람을 지우면 안 된다 — 방의 대사가 통째로 사라진다.
      // 실제로 세 지역에서 기록원이 한둘씩 없어진 채 출시될 뻔했다.
      final scenery = removable.where(
        (tile) => objects[blockers[tile]!].kind != _TileObjectKind.npc,
      );
      final pool = scenery.isEmpty ? removable : scenery;
      removed.add(pool.reduce(math.min));
    }
    if (removed.isNotEmpty) {
      final drop = removed.map((tile) => blockers[tile]!).toSet();
      final kept = <_TileObject>[];
      for (var index = 0; index < objects.length; index++) {
        if (!drop.contains(index)) kept.add(objects[index]);
      }
      objects
        ..clear()
        ..addAll(kept);
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

    // 벽은 바깥 테두리 전체다. 실내는 밖이 없으니 두 겹을 통째로 벽으로 둔다.
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (inside(x, y)) continue;
        terrain[y * width + x] = _TileTerrain.wall;
      }
    }

    final objects = <_TileObject>[];
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
        speech: '실내 공기 덕에 기록이 덜 상했어요. 필체가 또렷해요.',
      ),
    );
    // 문 양옆의 석주와 구석의 결정. 안쪽 방은 창이 없어서, 결정 빛이
    // 등불을 대신해 방을 데운다.
    objects.add(
      const _TileObject(
        kind: _TileObjectKind.pillar,
        position: Offset(5.5, 10.9),
        size: Size(1.15, 1.95),
        label: '문가의 석주',
        blocks: true,
        collisionSize: Size(.52, .34),
      ),
    );
    objects.add(
      const _TileObject(
        kind: _TileObjectKind.pillar,
        position: Offset(11.5, 10.9),
        size: Size(1.15, 1.95),
        label: '문가의 석주',
        blocks: true,
        collisionSize: Size(.52, .34),
      ),
    );
    objects.add(
      const _TileObject(
        kind: _TileObjectKind.crystal,
        position: Offset(13.5, 8.5),
        size: Size(1.15, 1.7),
        label: '실내의 기억 결정',
        blocks: true,
        collisionSize: Size(.6, .36),
        speech: '집 안에서 자란 결정은 빛이 순해요. 오래 들여다보게 돼요.',
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

  /// 벽으로 채워진 칸 수. 방이 제대로 닫혔는지 세어 보는 데 쓴다.
  /// 바닥 칸 수.
  int get walkableTiles =>
      terrain.where((cell) => cell == _TileTerrain.floor).length;

  int get wallTiles =>
      terrain.where((cell) => cell == _TileTerrain.wall).length;

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
    // 벽은 이제 지형이다. 물건 목록을 뒤지지 않고 칸에서 바로 본다.
    if (samples.any(
      (sample) =>
          terrainAt(sample.dx.floor(), sample.dy.floor()) ==
          _TileTerrain.wall,
    )) {
      return true;
    }
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
        _TileObjectKind.root ||
        _TileObjectKind.pillar ||
        _TileObjectKind.crystal =>
          true,
        _ => false,
      };

  _TileObject? nearestDiscoverable(Offset player) {
    _TileObject? nearest;
    var distance = 1.6;
    for (final object
        in objectsIn(Rect.fromCircle(center: player, radius: distance + 1))) {
      if (object.kind == _TileObjectKind.shelf ||
          object.kind == _TileObjectKind.lantern ||
          object.kind == _TileObjectKind.root ||
          object.kind == _TileObjectKind.pillar) {
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
    // 출발 칸을 값으로 못 박는다. 지형 생성기가 흔들리면 여기서 걸린다 —
    // 특히 32비트 곱셈을 한 번에 하면 웹에서만 다른 값이 나온다.
    'outsideWallTiles': outside.wallTiles,
    'spawnX': outside.spawn.dx.floor(),
    'spawnY': outside.spawn.dy.floor(),
    'outsideWarps': warps(outside),
    'insideWarps': warps(inside),
    // 문이 막혀 있으면 들어갈 수가 없다.
    'blockingWarps': blockingWarps(outside) + blockingWarps(inside),
    // 벽은 물건이 아니라 지형이다. 칸을 세어 방이 닫혀 있는지 본다.
    'insideWalls': inside.wallTiles,
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
      'walkable': field.terrain
          .where((cell) => cell == _TileTerrain.floor)
          .length,
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
    required this.atlasSlots,
    required this.field,
    required this.camera,
    required this.playerY,
    required this.foreground,
    required this.pulse,
  });

  static const double _atlasCell = 96;
  static const double _atlasGutter = 2;

  /// 굽기가 내놓은 조각 표. 이름 → 아틀라스 안의 자리.
  final Map<String, Rect> atlasSlots;

  /// 벽 윗면 네 갈래. 바닥처럼 열여섯을 다 두면 아틀라스만 커지고, 벽은 넓게
  /// 이어지는 면이라 네 갈래로도 무늬가 안 잡힌다.
  static const List<String> _wallTopSuffixes = ['a', 'b', 'c', 'd'];

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
    // 벽 앞면은 맨 나중에, 아래 칸을 덮으며 그린다. 이게 있어야 벽에 높이가
    // 생긴다. 같은 무리에 섞어 그리면 옆 벽의 윗면이 앞면을 덮어 버린다.
    final faceTransforms = <ui.RSTransform>[];
    final faceRects = <Rect>[];
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
          // 벽 윗면도 위에서 내려다보는 수평면이라 네 갈래만 돌려 쓴다.
          _TileTerrain.wall => 'wall_top_${_wallTopSuffixes[variant & 3]}',
        };
        addSprite(baseTransforms, baseRects, base, screen);

        // 다른 재질과 맞닿은 자리에 전환 조각을 얹는다.
        void trim(String prefix) {
          if (!cell.same(_TileCell.north)) {
            addSprite(shoreTransforms, shoreRects, '${prefix}_n', screen);
          }
          if (!cell.same(_TileCell.east)) {
            addSprite(shoreTransforms, shoreRects, '${prefix}_e', screen);
          }
          if (!cell.same(_TileCell.south)) {
            addSprite(shoreTransforms, shoreRects, '${prefix}_s', screen);
          }
          if (!cell.same(_TileCell.west)) {
            addSprite(shoreTransforms, shoreRects, '${prefix}_w', screen);
          }
          // 대각선은 양옆 변이 모두 같을 때만 그린다. 아니면 변 조각이 이미
          // 그 자리를 덮고 있어 두 번 겹친다.
          if (cell.cornerOnly(
            _TileCell.northEast,
            _TileCell.north,
            _TileCell.east,
          )) {
            addSprite(shoreTransforms, shoreRects, '${prefix}_ne', screen);
          }
          if (cell.cornerOnly(
            _TileCell.southEast,
            _TileCell.south,
            _TileCell.east,
          )) {
            addSprite(shoreTransforms, shoreRects, '${prefix}_se', screen);
          }
          if (cell.cornerOnly(
            _TileCell.southWest,
            _TileCell.south,
            _TileCell.west,
          )) {
            addSprite(shoreTransforms, shoreRects, '${prefix}_sw', screen);
          }
          if (cell.cornerOnly(
            _TileCell.northWest,
            _TileCell.north,
            _TileCell.west,
          )) {
            addSprite(shoreTransforms, shoreRects, '${prefix}_nw', screen);
          }
        }

        switch (terrain) {
          case _TileTerrain.water:
            trim('shore');
          case _TileTerrain.floor:
            trim('edge');
          case _TileTerrain.wall:
            trim('rim');
            // 아래가 벽이 아니면 그쪽이 화면을 향한 **앞면**이다.
            if (!cell.same(_TileCell.south)) {
              addSprite(
                faceTransforms,
                faceRects,
                'wall',
                screen + Offset(0, camera.tilePixels * .42),
              );
            }
          case _TileTerrain.moss:
            break;
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
    if (faceRects.isNotEmpty) {
      canvas.drawAtlas(
        image,
        faceTransforms,
        faceRects,
        null,
        BlendMode.srcOver,
        cullRect,
        paint,
      );
    }
  }

  /// 조각의 자리. **표에서 읽는다.**
  ///
  /// 앞 판은 `지역 번호 × 64 + 칸 번호`로 계산하고 이름·번호 표를 코드에
  /// 박아 두었다. 아틀라스에 조각을 스물넷 더하자 한 지역이 88칸이 되면서
  /// 계산이 통째로 어긋났고, 화면이 새까맣게 나왔다. 굽는 쪽과 그리는 쪽이
  /// 같은 숫자를 각자 들고 있으면 언젠가 반드시 갈라진다.
  ///
  /// 이제 굽기가 내놓는 표(`expedition-tile-atlas-v2.json`)를 그대로 읽는다.
  Rect _atlasRect(String sprite) =>
      atlasSlots[sprite] ??
      Rect.fromLTWH(_atlasGutter, _atlasGutter, _atlasCell, _atlasCell);

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
      case _TileObjectKind.pillar:
        _paintPillar(canvas, bounds);
      case _TileObjectKind.crystal:
        _paintCrystal(canvas, bounds);
    }
  }

  void _paintPillar(Canvas canvas, Rect r) {
    final stone = field.palette.stone;
    final base = Rect.fromLTWH(
        r.left, r.bottom - r.height * .12, r.width, r.height * .12);
    canvas.drawRRect(RRect.fromRectAndRadius(base, const Radius.circular(2)),
        Paint()..color = Color.lerp(stone, Colors.black, .3)!);
    final shaft = Rect.fromLTWH(r.left + r.width * .24, r.top + r.height * .1,
        r.width * .52, r.height * .8);
    canvas.drawRRect(RRect.fromRectAndRadius(shaft, const Radius.circular(2)),
        Paint()..color = stone);
    canvas.drawRect(
        Rect.fromLTWH(shaft.left, shaft.top, shaft.width * .3, shaft.height),
        Paint()..color = Colors.white.withAlpha(28));
    final cap =
        Rect.fromLTWH(r.left + r.width * .12, r.top, r.width * .76, r.height * .1);
    canvas.drawRRect(RRect.fromRectAndRadius(cap, const Radius.circular(2)),
        Paint()..color = Color.lerp(stone, Colors.white, .18)!);
  }

  void _paintCrystal(Canvas canvas, Rect r) {
    final center = Offset(r.center.dx, r.top + r.height * .42);
    final path = Path()
      ..moveTo(center.dx, r.top)
      ..lineTo(center.dx + r.width * .34, center.dy)
      ..lineTo(center.dx + r.width * .1, r.bottom)
      ..lineTo(center.dx - r.width * .1, r.bottom)
      ..lineTo(center.dx - r.width * .34, center.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = field.palette.glow);
    canvas.drawPath(
        Path()
          ..moveTo(center.dx, r.top + r.height * .08)
          ..lineTo(center.dx + r.width * .14, center.dy)
          ..lineTo(center.dx, r.bottom - r.height * .08)
          ..lineTo(center.dx - r.width * .14, center.dy)
          ..close(),
        Paint()..color = Colors.white.withAlpha(70));
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
    // 등불은 넓고 밝게, 결정은 좁고 은은하게. 광원이 등불 하나뿐이면 방마다
    // 같은 빛이라 밤 풍경이 단조롭다.
    for (final source in field.objectsIn(camera.worldRect.inflate(2)).where(
        (o) =>
            (o.kind == _TileObjectKind.lantern ||
                o.kind == _TileObjectKind.crystal) &&
            camera.worldRect.inflate(2).contains(o.position))) {
      final lantern = source.kind == _TileObjectKind.lantern;
      final radius = camera.tilePixels * (lantern ? 2.1 : 1.55);
      final center = camera.project(
        source.position - Offset(0, lantern ? .85 : .6),
      );
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(colors: [
              field.palette.glow.withAlpha(lantern ? 42 : 30),
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
      oldDelegate.atlasSlots != atlasSlots ||
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
    required this.facing,
  });

  final _TileField field;
  final Offset player;
  final _WorldCamera camera;
  final _WalkFacing facing;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = field.minimapFrame(size);
    final scale = frame.scale;
    final origin = frame.origin;
    canvas.drawPicture(field.minimapBackground(size));
    // 카메라 창. 세게 그리면 지도 위에 흰 상자만 남는다 - 지금 화면이 지도의
    // 어디쯤인지 짚어 줄 만큼만 남긴다.
    final view = camera.worldRect;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          origin.dx + view.left * scale,
          origin.dy + view.top * scale,
          view.width * scale,
          view.height * scale,
        ),
        const Radius.circular(2),
      ),
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final at = Offset(
      origin.dx + player.dx * scale,
      origin.dy + player.dy * scale,
    );
    final ahead = switch (facing) {
      _WalkFacing.up => const Offset(0, -1),
      _WalkFacing.down => const Offset(0, 1),
      _WalkFacing.left => const Offset(-1, 0),
      _WalkFacing.right => const Offset(1, 0),
    };
    // 바라보는 쪽 앞에 작은 점을 하나 더 찍는다. 이 크기에서 화살표는
    // 뭉개지고, 큰 점 하나와 작은 점 하나면 방향이 읽힌다.
    canvas.drawCircle(at, 3.1, Paint()..color = field.palette.voidColor);
    canvas.drawCircle(
      at + ahead * 3.4,
      1.0,
      Paint()..color = Colors.white70,
    );
    canvas.drawCircle(at, 2.1, Paint()..color = const Color(0xFFFFE19A));
  }

  @override
  bool shouldRepaint(covariant _TileMinimapPainter oldDelegate) =>
      oldDelegate.field != field ||
      oldDelegate.player != player ||
      oldDelegate.facing != facing ||
      oldDelegate.camera.origin != camera.origin;
}
