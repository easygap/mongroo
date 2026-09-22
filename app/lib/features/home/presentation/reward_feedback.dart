import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/mongroo_ui.dart';
import '../../expedition/presentation/expedition_settings.dart';
import '../domain/reward_result.dart';

/// 서버가 확정한 보상을 보여 준다. 잔액 저장과 연출의 수명은 서로 독립적이다.
/// 시트를 바로 닫아도 지급은 끝나 있으며, 재조회/화면 재진입에는 사용하지 않는다.
class RewardReceipt extends ConsumerStatefulWidget {
  const RewardReceipt({super.key, required this.reward});

  final RewardResult reward;

  @override
  ConsumerState<RewardReceipt> createState() => _RewardReceiptState();
}

class _RewardReceiptState extends ConsumerState<RewardReceipt>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _canvasKey = GlobalKey();
  final _sourceKey = GlobalKey();
  final _walletKey = GlobalKey();
  late final AnimationController _flight;
  late final ValueNotifier<int> _balance;
  final _sound = _RewardSound();
  bool _started = false;
  bool _arrived = false;

  int get _seeds => math.max(0, widget.reward.totalSeeds);
  int get _count => math.min(8, _seeds);
  int get _before => math.max(0, widget.reward.seedBalance - _seeds);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _balance = ValueNotifier(_before);
    _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _finish();
    } else if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _flight.value == 1) return;
        if (_seeds > 0 || widget.reward.totalExp > 0) {
          if (ref.read(expeditionBattleSettingsProvider).sfxEnabled) {
            unawaited(_sound.prepare('adventure/sfx/cue-patrol-return.wav'));
          }
          _flight.forward();
        } else {
          _finish();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant RewardReceipt oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 응답으로 갱신됐을 때 이전 잔액을 덮어쓰거나 축하를 재생하지 않는다.
    if (oldWidget.reward != widget.reward) _finish();
  }

  void _tick() {
    var landed = 0;
    for (var i = 0; i < _count; i++) {
      if (_flight.value >= _arrival(i)) landed++;
    }
    _balance.value = _count == 0
        ? widget.reward.seedBalance
        : _before + ((_seeds * landed) / _count).round();
    final hasReward = _seeds > 0 || widget.reward.totalExp > 0;
    if (!_arrived && hasReward && _flight.value >= _arrival(0)) {
      _arrived = true;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      unawaited(HapticFeedback.lightImpact());
      unawaited(_sound.play(
        'adventure/sfx/cue-patrol-return.wav',
        enabled: ref.read(expeditionBattleSettingsProvider).sfxEnabled,
      ));
    }
  }

  void _finish() {
    _started = true;
    _arrived = true;
    _flight.value = 1;
    _balance.value = widget.reward.seedBalance;
    _sound.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finish();
  }

  Offset? _center(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    final canvas = _canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox || canvas is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero), ancestor: canvas);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flight.dispose();
    _balance.dispose();
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(expeditionBattleSettingsProvider.select((s) => s.sfxEnabled),
        (_, enabled) {
      if (!enabled) _sound.stop();
    });
    final scheme = Theme.of(context).colorScheme;
    final reward = widget.reward;
    // 숫자는 접근성 트리에 최종 값으로 한 번만 알린다. 비행 중간 값은 장식이다.
    return Semantics(
      container: true,
      label: '받은 보상: 경험치 ${reward.totalExp}, 씨앗 $_seeds개. '
          '보유 씨앗 ${reward.seedBalance}개',
      child: ExcludeSemantics(
        child: Stack(
          key: _canvasKey,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('내 씨앗')),
                    RepaintBoundary(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _balance,
                        builder: (context, value, _) => AnimatedBuilder(
                          animation: _flight,
                          child: SizedBox(
                            key: _walletKey,
                            child:
                                MongrooSeedToken(value: value, animate: false),
                          ),
                          builder: (context, child) {
                            final landing =
                                ((_flight.value - .57) / .30).clamp(0.0, 1.0);
                            return Transform.scale(
                              scale: 1 + math.sin(landing * math.pi) * .12,
                              child: child,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 24,
                    runSpacing: 14,
                    children: [
                      if (reward.totalExp > 0)
                        _RewardAmount(
                            icon: Icons.spa_outlined,
                            label: '경험치',
                            amount: reward.totalExp),
                      if (_seeds > 0)
                        _RewardAmount(
                            iconKey: _sourceKey,
                            icon: Icons.eco_rounded,
                            label: '씨앗',
                            amount: _seeds),
                      if (_seeds == 0 && reward.totalExp == 0)
                        const Text('이미 받은 보상이에요.'),
                    ],
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SeedFlightPainter(
                      animation: _flight,
                      count: _count,
                      source: () => _center(_sourceKey),
                      target: () => _center(_walletKey),
                      color: scheme.primary,
                      ink: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _arrival(int index) => .57 + index * .035;

class _RewardAmount extends StatelessWidget {
  const _RewardAmount(
      {required this.icon,
      required this.label,
      required this.amount,
      this.iconKey});
  final GlobalKey? iconKey;
  final IconData icon;
  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, key: iconKey, size: 24),
          const SizedBox(width: 8),
          Flexible(
              child: Text('$label +$amount',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800))),
        ],
      );
}

class _SeedFlightPainter extends CustomPainter {
  _SeedFlightPainter(
      {required this.animation,
      required this.count,
      required this.source,
      required this.target,
      required this.color,
      required this.ink})
      : super(repaint: animation);
  final Animation<double> animation;
  final int count;
  final Offset? Function() source;
  final Offset? Function() target;
  final Color color;
  final Color ink;
  static final _leaf = Path()
    ..moveTo(-5, 4)
    ..cubicTo(-8, -3, -1, -7, 6, -7)
    ..cubicTo(7, 1, 3, 7, -5, 4)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0 || animation.value == 0 || animation.value == 1) return;
    final from = source();
    final to = target();
    if (from == null || to == null) return;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final t = (animation.value - (_arrival(i) - .42)) / .42;
      if (t < 0 || t > 1) continue;
      final progress = Curves.easeInOutCubic.transform(t);
      final spread = (i - (count - 1) / 2) * 24;
      final control = Offset(
          (from.dx + to.dx) / 2 + spread, math.max(14, from.dy - 72 - i * 3));
      final center = from * math.pow(1 - progress, 2).toDouble() +
          control * (2 * (1 - progress) * progress) +
          to * (progress * progress);
      final radius = 10 * math.min(1.0, t * 8) * (1 - .35 * progress);
      canvas.drawCircle(center, radius, paint..color = color);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(radius / 10);
      canvas.drawPath(_leaf, paint..color = ink);
      canvas.drawLine(
          const Offset(-5, 5),
          const Offset(3, -3),
          paint
            ..color = color
            ..strokeWidth = 1.2);
      canvas.restore();
    }
    final landing = (animation.value - .57) / .34;
    if (landing >= 0 && landing <= 1) {
      canvas.drawCircle(
          to,
          18 + landing * 12,
          paint
            ..color = color.withValues(alpha: (1 - landing) * .35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _SeedFlightPainter old) =>
      old.animation != animation || old.count != count || old.color != color;
}

/// 해금/성장처럼 드문 순간에만 재생하는 짧은 등장 연출.
/// 정적인 캐릭터 그림과 문구는 매 프레임 다시 만들지 않는다.
class MilestoneReveal extends ConsumerStatefulWidget {
  const MilestoneReveal({super.key, required this.child, this.sound = true});
  final Widget child;
  final bool sound;

  @override
  ConsumerState<MilestoneReveal> createState() => _MilestoneRevealState();
}

class _MilestoneRevealState extends ConsumerState<MilestoneReveal>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _reveal;
  final _sound = _RewardSound();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reveal = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _started = true;
      _reveal.value = 1;
      _sound.stop();
    } else if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _reveal.value == 1) return;
        _reveal.forward();
        if (widget.sound) {
          unawaited(HapticFeedback.mediumImpact());
          unawaited(_sound.play('adventure/sfx/cue-research-complete.wav',
              enabled: ref.read(expeditionBattleSettingsProvider).sfxEnabled));
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _reveal.value = 1;
      _sound.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reveal.dispose();
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(expeditionBattleSettingsProvider.select((s) => s.sfxEnabled),
        (_, enabled) {
      if (!enabled) _sound.stop();
    });
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _reveal,
          child: RepaintBoundary(child: widget.child),
          builder: (context, child) {
            final t = Curves.easeOutBack
                .transform((_reveal.value / .45).clamp(0.0, 1.0));
            return Transform.scale(scale: .90 + .10 * t, child: child);
          },
        ),
        Positioned.fill(
            child: IgnorePointer(
                child: RepaintBoundary(
          child: CustomPaint(
              painter: _MilestonePainter(
                  _reveal, Theme.of(context).colorScheme.primary)),
        ))),
      ],
    );
  }
}

class _MilestonePainter extends CustomPainter {
  _MilestonePainter(this.animation, this.color) : super(repaint: animation);
  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t == 0 || t == 1) return;
    final radius = size.shortestSide * .32;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - t) * .85)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final start = center + direction * (radius * (.65 + .95 * t));
      if (i.isEven) {
        final length = 3 + math.sin(t * math.pi) * 5;
        final star = Path()
          ..moveTo(start.dx, start.dy - length)
          ..lineTo(start.dx + length * .35, start.dy - length * .35)
          ..lineTo(start.dx + length, start.dy)
          ..lineTo(start.dx + length * .35, start.dy + length * .35)
          ..lineTo(start.dx, start.dy + length)
          ..lineTo(start.dx - length * .35, start.dy + length * .35)
          ..lineTo(start.dx - length, start.dy)
          ..lineTo(start.dx - length * .35, start.dy - length * .35)
          ..close();
        canvas.drawPath(star, paint);
      } else {
        canvas.drawLine(start, start + direction * (14 * (1 - t)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MilestonePainter old) => old.color != color;
}

/// 보상 하나에 플레이어 하나만 필요하다. 전투용 오디오 풀은 만들지 않는다.
class _RewardSound {
  AudioPlayer? _player;
  Future<void>? _ready;
  int _generation = 0;
  bool _disposed = false;

  Future<void> prepare(String path) => _ready ??= _prepare(path);

  Future<void> _prepare(String path) async {
    if (_disposed) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
      if (_disposed) return;
      await player.setSource(AssetSource(path));
      if (_disposed) return;
      await player.setVolume(.52);
    } on Object {
      // 오디오를 지원하지 않는 환경에서도 결과 화면을 계속 보여 준다.
    }
  }

  Future<void> play(String path, {required bool enabled}) async {
    if (!enabled || _disposed) return;
    final generation = ++_generation;
    try {
      // 느린 다운로드가 뒤늦게 성공음을 재생하지 않도록 시점을 제한한다.
      await prepare(path).timeout(const Duration(milliseconds: 250));
      if (_disposed || generation != _generation) return;
      await _player?.resume();
    } on Object {
      // 장치/자동 재생 정책 때문에 소리가 없어도 수령 흐름은 계속된다.
    }
  }

  void stop() {
    _generation++;
    final player = _player;
    if (player != null) unawaited(player.stop().catchError((Object _) {}));
  }

  void dispose() {
    _disposed = true;
    _generation++;
    final player = _player;
    if (player != null) unawaited(player.dispose().catchError((Object _) {}));
  }
}
