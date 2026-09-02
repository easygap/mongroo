// 전투 연출 전부를 실제 래스터 파이프라인에서 재생하며 프레임 타임을 잰다.
//
// `docs/performance.md` 3장이 정한 표본 규칙을 따른다 — 390×844, 연출이 실제로
// 차지하는 크기, 프레임별 선언 길이. 다만 브라우저 rAF가 아니라 Flutter가 직접
// 주는 `FrameTiming`을 쓴다. 창이 가려지면 rAF가 1Hz로 묶여 표본을 버려야 하는데,
// 이 세션의 브라우저 패널은 숨어 있어서 그 길이 막혔다.
//
// 재는 것은 `연출을 재생할 때 프레임 예산을 넘기는가` 하나다. 저사양 Android의
// GPU·발열·메모리 압박을 대신하지 않는다.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const repo = r'C:\y2026\99_개인폴더\99_project\mood_pot';
const effectsRoot = '$repo/app/assets/adventure/effects';

/// 준비 구간. 셰이더 워밍업과 첫 디코드는 표본에서 뺀다.
const warmupFrames = 90;

void main() {
  runApp(const _Bench());
}

class _Bench extends StatefulWidget {
  const _Bench();

  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> with SingleTickerProviderStateMixin {
  final List<_Effect> _effects = [];
  final List<double> _totals = [];
  final List<double> _rasters = [];
  final List<double> _builds = [];
  int _seen = 0;
  int _effect = 0;
  int _frame = 0;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  int _elapsedMs = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manifest = jsonDecode(
      File('$effectsRoot/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final raw in manifest['effects'] as List) {
      final entry = raw as Map<String, dynamic>;
      final directory = entry['directory'] as String;
      final durations = (entry['frame_durations_ms'] as List)
          .map((value) => (value as num).toInt())
          .toList(growable: false);
      final images = <ui.Image>[];
      for (var index = 0; index < durations.length; index++) {
        final bytes = File(
          '$effectsRoot/$directory/frame-${index.toString().padLeft(2, '0')}.webp',
        ).readAsBytesSync();
        final codec = await ui.instantiateImageCodec(bytes);
        images.add((await codec.getNextFrame()).image);
      }
      _effects.add(_Effect(entry['family'] as String, images, durations));
    }
    if (!mounted) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _ticker = createTicker(_tick)..start();
    setState(() {});
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _seen++;
      if (_seen <= warmupFrames) continue;
      _totals.add(timing.totalSpan.inMicroseconds / 1000);
      _rasters.add(timing.rasterDuration.inMicroseconds / 1000);
      _builds.add(timing.buildDuration.inMicroseconds / 1000);
    }
  }

  void _tick(Duration now) {
    if (_effects.isEmpty || _done) return;
    final delta = _last == Duration.zero ? 16 : (now - _last).inMilliseconds;
    _last = now;
    _elapsedMs += delta;
    final current = _effects[_effect];
    if (_elapsedMs >= current.durations[_frame]) {
      _elapsedMs = 0;
      _frame++;
      if (_frame >= current.images.length) {
        _frame = 0;
        _effect++;
        if (_effect >= _effects.length) {
          _effect = 0;
          if (_seen > warmupFrames + 400) {
            _finish();
            return;
          }
        }
      }
    }
    setState(() {});
  }

  void _finish() {
    _done = true;
    _ticker?.stop();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    stdout.writeln('FXBENCH_BEGIN');
    stdout.writeln(
      jsonEncode({
        'effects': _effects.length,
        'sampled_frames': _totals.length,
        'total': _stats(_totals),
        'raster': _stats(_rasters),
        'build': _stats(_builds),
      }),
    );
    stdout.writeln('FXBENCH_END');
    exit(0);
  }

  Map<String, dynamic> _stats(List<double> values) {
    if (values.isEmpty) return const {};
    final sorted = [...values]..sort();
    double at(double q) => sorted[((sorted.length - 1) * q).round()];
    final mean = sorted.reduce((a, b) => a + b) / sorted.length;
    return {
      'mean_ms': double.parse(mean.toStringAsFixed(3)),
      'p50_ms': double.parse(at(.50).toStringAsFixed(3)),
      'p95_ms': double.parse(at(.95).toStringAsFixed(3)),
      'p99_ms': double.parse(at(.99).toStringAsFixed(3)),
      'max_ms': double.parse(sorted.last.toStringAsFixed(3)),
      'over_20ms': sorted.where((value) => value > 20).length,
      'over_33_4ms': sorted.where((value) => value > 33.4).length,
      'fps': double.parse((1000 / mean).toStringAsFixed(2)),
    };
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _effects.isNotEmpty;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF12181A),
        body: Center(
          child: ready
              ? SizedBox(
                  // 전장에서 연출이 실제로 차지하는 크기(390 폭의 2:1 무대).
                  width: 390,
                  height: 195,
                  child: RawImage(
                    image: _effects[_effect].images[_frame],
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _Effect {
  const _Effect(this.family, this.images, this.durations);

  final String family;
  final List<ui.Image> images;
  final List<int> durations;
}
