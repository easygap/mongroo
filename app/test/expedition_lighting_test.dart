import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/presentation/expedition_lighting.dart';

/// 라이트맵 계약.
///
/// 이 겹이 하는 일은 눈으로만 확인하기 쉬운데, 그래서 조용히 아무것도 안 하게
/// 되기도 쉽다. 실제로 이전 코드는 광원 자리에 반투명 원을 덧칠하기만 해서
/// **어두운 곳이 아예 생기지 않았고**, 등불이 있는지조차 화면에서 읽히지
/// 않았다. 여기서는 실제로 그려 보고 픽셀을 재서 그 실수를 막는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = 240;
  const base = Color(0xFF8A8070);

  /// 바닥 한 장을 깔고 빛을 얹어 실제 픽셀을 돌려준다.
  Future<ByteData> render({
    required ExpeditionLighting lighting,
    List<SceneLight> lights = const [],
    void Function(Canvas canvas)? extra,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const bounds = Rect.fromLTWH(0, 0, size * 1.0, size * 1.0);
    canvas.drawRect(bounds, Paint()..color = base);
    extra?.call(canvas);
    paintExpeditionLighting(
      canvas,
      bounds,
      lighting: lighting,
      lights: lights,
    );
    final image = await recorder.endRecording().toImage(size, size);
    return (await image.toByteData())!;
  }

  int luma(ByteData pixels, int x, int y) {
    final i = (y * size + x) * 4;
    return ((pixels.getUint8(i) * 299 +
                pixels.getUint8(i + 1) * 587 +
                pixels.getUint8(i + 2) * 114) /
            1000)
        .round();
  }

  Color colorAt(ByteData pixels, int x, int y) {
    final i = (y * size + x) * 4;
    return Color.fromARGB(255, pixels.getUint8(i), pixels.getUint8(i + 1),
        pixels.getUint8(i + 2));
  }

  const centre = Offset(size / 2, size / 2);

  test('광원이 닿는 곳은 밝아지고 닿지 않는 곳은 어두워진다', () async {
    final lighting = expeditionLightingFor('echo_well');
    final pixels = await render(
      lighting: lighting,
      lights: [
        SceneLight(center: centre, radius: 56, color: lighting.lantern),
      ],
    );

    final lit = luma(pixels, size ~/ 2, size ~/ 2);
    final dark = luma(pixels, 8, 8);
    // 원래 바닥보다 **어두워진 자리가 있어야** 조명이다. 예전처럼 덧칠만
    // 하면 이 값이 원래 밝기 언저리이거나 오히려 더 밝다.
    const floorLuma = 129; // base(0x8A8070)의 밝기
    expect(dark, lessThan(floorLuma * .72),
        reason: '광원에서 먼 곳이 충분히 어두워야 한다');
    expect(lit, greaterThan(floorLuma), reason: '등불 자리는 원래보다 밝다');
    expect(lit - dark, greaterThan(60), reason: '등불 자리와 구석의 차이');
  });

  test('빛은 바닥 무늬를 지우지 않는다', () async {
    final lighting = expeditionLightingFor('echo_well');
    final pixels = await render(
      lighting: lighting,
      lights: [
        SceneLight(center: centre, radius: 80, color: lighting.lantern),
      ],
      // 밝은 줄 하나. 빛 속에서도 이 줄이 바닥과 구분돼야 한다.
      extra: (canvas) => canvas.drawRect(
        const Rect.fromLTWH(0, size / 2 - 4, size * 1.0, 8),
        Paint()..color = const Color(0xFFB6AC98),
      ),
    );
    final stripe = luma(pixels, size ~/ 2, size ~/ 2);
    final floor = luma(pixels, size ~/ 2, size ~/ 2 + 14);
    // 곱하기라서 결이 남는다. 덧칠(srcOver)이면 둘이 같은 값으로 뭉갠다.
    expect(stripe - floor, greaterThan(8));
  });

  test('네 지역은 서로 다른 색으로 읽힌다', () async {
    // 같은 아틀라스를 쓰는 네 지역이라, 빛이 갈라 주지 않으면 같은 방이 된다.
    const codes = [
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ];
    final shades = <String, Color>{};
    for (final code in codes) {
      final pixels = await render(lighting: expeditionLightingFor(code));
      shades[code] = colorAt(pixels, size ~/ 2, size ~/ 2);
    }
    for (final a in codes) {
      for (final b in codes) {
        if (a == b) continue;
        final first = shades[a]!;
        final second = shades[b]!;
        final distance = ((first.r - second.r).abs() +
                (first.g - second.g).abs() +
                (first.b - second.b).abs()) *
            255;
        expect(distance, greaterThan(40), reason: '$a 와 $b 가 너무 비슷하다');
      }
    }
  });

  test('고대비를 켜면 어둠이 걷힌다', () async {
    final lighting = expeditionLightingFor('starlight_seed_vault');
    final normal = await render(lighting: lighting);
    final lifted = await render(lighting: lighting.lifted(.62));
    expect(
      luma(lifted, 12, 12),
      greaterThan(luma(normal, 12, 12) + 30),
      reason: '불 없는 구석이 눈에 띄게 밝아져야 한다',
    );
  });

  test('발밑 그림자는 바닥을 어둡게 한다', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, size * 1.0, size * 1.0),
      Paint()..color = base,
    );
    paintContactShadow(canvas, foot: centre, width: 40);
    final image = await recorder.endRecording().toImage(size, size);
    final pixels = (await image.toByteData())!;
    expect(luma(pixels, size ~/ 2, size ~/ 2),
        lessThan(luma(pixels, 8, 8) - 20));
  });

  test('등불은 저마다 다른 박자로 흔들린다', () {
    // 같은 위상이면 방 안의 불이 전부 동시에 깜빡여 형광등 고장처럼 보인다.
    final atSamePhase = [for (var seed = 0; seed < 5; seed++) lanternFlicker(.3, seed)];
    expect(atSamePhase.toSet(), hasLength(atSamePhase.length));
    for (final value in atSamePhase) {
      expect(value, inInclusiveRange(.85, 1.1));
    }
    // 동작 줄이기를 켜면 아예 멈춘다.
    expect(lanternFlicker(.3, 2, still: true), 1);
  });
}
