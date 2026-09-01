import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 화면 한 곳을 밝히는 광원 하나.
///
/// 좌표와 반경은 **화면 픽셀**이다. 월드 좌표를 그대로 넘기면 카메라가 움직일
/// 때 빛만 제자리에 남는다.
@immutable
class SceneLight {
  const SceneLight({
    required this.center,
    required this.radius,
    required this.color,
    this.intensity = 1,
  });

  final Offset center;

  /// 빛이 닿는 끝. 여기서 세기가 0이 된다.
  final double radius;

  /// 이 광원이 어둠에서 걷어내는 색. **알파는 보지 않는다** — 세기는
  /// [intensity]로만 준다. 두 군데서 세기를 주면 어느 쪽이 이겼는지 못 읽는다.
  final Color color;

  /// 0이면 꺼진 것과 같고 1이 제 밝기다. 흔들리는 등불이 이 값을 흔든다.
  final double intensity;

  SceneLight scaled(double factor) => SceneLight(
        center: center,
        radius: radius,
        color: color,
        intensity: intensity * factor,
      );
}

/// 한 지역의 빛.
///
/// 네 지역이 **같은 아틀라스**를 쓴다. 바닥 도트의 평균색이 서로 20 남짓밖에
/// 차이 나지 않아서(모래빛 계열 넷), 도트만으로는 우물정원과 보관고가 같은
/// 방으로 보인다. 빛을 지역마다 다르게 주면 같은 바닥이 젖은 돌로도, 마른
/// 서고 바닥으로도 읽힌다 — 새 도트를 굽는 것보다 이쪽이 먼저다.
@immutable
class ExpeditionLighting {
  const ExpeditionLighting({
    required this.ambient,
    required this.edge,
    required this.lantern,
    required this.crystal,
    required this.skyTint,
    required this.bloom,
  });

  /// 아무 광원도 닿지 않는 자리에 **곱해질** 색. 어두울수록 밤이다.
  final Color ambient;

  /// 화면 가장자리에 곱해질 색. [ambient]보다 어둡다.
  final Color edge;

  /// 등불이 더하는 색.
  final Color lantern;

  /// 기억 결정이 더하는 색.
  final Color crystal;

  /// 그늘에 스며드는 하늘빛. 알파가 세기다.
  ///
  /// 곱하기는 **덜어내기만 한다.** 그래서 곱하기만 쓰면 어두운 곳이 결국
  /// 검은 회색으로 모인다 — 지역색이 그늘에서 사라진다. 실제 그늘이 푸른
  /// 것은 하늘빛이 따로 들어오기 때문이고, 여기서도 같은 이유로 한 겹 더한다.
  ///
  /// 이 겹은 `screen`으로 얹는다. 더하기로 얹었더니 등불 한가운데까지 같이
  /// 들려서 방 전체에 우유를 탄 것처럼 뿌옜다. `screen`은 어두운 곳을 많이,
  /// 밝은 곳을 거의 안 들어 올린다 — 그늘에만 색을 넣고 싶을 때 맞는 셈법이다.
  final Color skyTint;

  /// 광원 위에 더해지는 번짐의 세기(0~1). 등불을 쳐다볼 때 보이는 그 빛무리다.
  final double bloom;

  /// 고대비 모드에서 쓸 밝은 판.
  ///
  /// 어둠은 분위기지만 길을 못 찾으면 분위기가 아니라 장벽이다. 시스템이
  /// 고대비를 켜면 어둠을 걷고 빛만 남긴다.
  ExpeditionLighting lifted(double t) {
    if (t <= 0) return this;
    final amount = t.clamp(0.0, 1.0);
    return ExpeditionLighting(
      ambient: Color.lerp(ambient, Colors.white, amount)!,
      edge: Color.lerp(edge, Colors.white, amount * .82)!,
      lantern: lantern,
      crystal: crystal,
      skyTint: skyTint.withValues(alpha: skyTint.a * (1 - amount)),
      bloom: bloom * (1 - amount * .6),
    );
  }
}

/// 지역별 빛. 모르는 지역은 첫 지역의 빛을 쓴다.
ExpeditionLighting expeditionLightingFor(String? regionCode) =>
    switch (regionCode) {
      // 젖은 돌과 물그림자. 넷 중 가장 차고 어둡다.
      'echo_well' => const ExpeditionLighting(
          ambient: Color(0xFF4E6E92),
          edge: Color(0xFF2A3A4C),
          lantern: Color(0xFFFFC48A),
          crystal: Color(0xFF7CE0FF),
          skyTint: Color(0x2E1F6FA0),
          bloom: .9,
        ),
      // 별가루가 쌓인 밤. 보랏빛으로 가라앉는다.
      'starlight_seed_vault' => const ExpeditionLighting(
          ambient: Color(0xFF413D70),
          edge: Color(0xFF272442),
          lantern: Color(0xFFFFD1A0),
          crystal: Color(0xFFB4C8FF),
          skyTint: Color(0x2A3A2CA4),
          bloom: 1,
        ),
      // 나무 속 관측실. 등불이 많아 넷 중 가장 따뜻하고 밝다.
      'heartwood_observatory' => const ExpeditionLighting(
          ambient: Color(0xFF8F6E45),
          edge: Color(0xFF463322),
          lantern: Color(0xFFFFC978),
          crystal: Color(0xFFFFE1A6),
          skyTint: Color(0x1E8A4410),
          bloom: .8,
        ),
      // 기억서고. 천창으로 낮빛이 들어오는 방이라 가장 밝고 중립이다.
      _ => const ExpeditionLighting(
          ambient: Color(0xFFAAA07E),
          edge: Color(0xFF3F3E2E),
          lantern: Color(0xFFFFD79A),
          crystal: Color(0xFF9CE8E2),
          skyTint: Color(0x1C30553C),
          bloom: .75,
        ),
    };

/// 장면 위에 빛을 얹는다. **순서가 있는 세 겹이라 한 번에 다 그린다.**
///
/// 예전에는 광원을 장면 위에 반투명 원으로 그냥 얹었다. 그러면 색이 덧칠될
/// 뿐 **어두운 곳이 생기지 않아서**, 등불 옆이나 방 구석이나 같은 밝기였다.
/// 실제 화면에서 등불이 있는지조차 읽히지 않았다.
///
/// 그래서 겹을 따로 뜬다.
///
/// 1. 겹 하나를 떠서 어둠(`ambient`→`edge`)을 깔고, 광원으로 그 어둠을
///    **더하기로 지운다.** 다 지운 겹을 장면에 **곱한다.** 곱하기라서 바닥
///    무늬가 빛 속에서도 살아 있다 — 덧칠이면 무늬가 뭉갠다.
/// 2. 그늘에 하늘빛을 한 겹 더한다([ExpeditionLighting.skyTint]).
/// 3. 광원 자리에 빛무리를 더한다. 곱하기는 원래 그림보다 밝아질 수 없으니,
///    등불이 **빛나 보이려면** 이 겹이 있어야 한다.
void paintExpeditionLighting(
  Canvas canvas,
  Rect bounds, {
  required ExpeditionLighting lighting,
  required List<SceneLight> lights,
}) {
  if (bounds.isEmpty) return;

  canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.multiply);
  // 어둠의 바닥은 **평평하다.**
  //
  // 처음에는 화면 한가운데를 밝히고 가장자리로 갈수록 어둡게 깔았다. 그런데
  // 카메라가 사람을 따라다니므로, 그러면 같은 바닥이 가운데 있을 때는 밝고
  // 구석에 있을 때는 어두워진다. 걸어 보면 세계가 어두운 게 아니라 손전등을
  // 든 것처럼 읽힌다. 어둠은 세계에 붙어 있어야 하고, 밝은 곳은 **등불이
  // 있는 곳**이라야 한다. 가장자리는 화면을 감싸는 정도로만 남긴다.
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = RadialGradient(
        radius: 1.05,
        colors: [lighting.ambient, lighting.edge],
        stops: const [.62, 1],
      ).createShader(bounds),
  );
  for (final light in lights) {
    final shader = _falloff(light, _lightMapStops, _lightMapAlphas);
    if (shader == null) continue;
    canvas.drawCircle(
      light.center,
      light.radius,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = shader,
    );
  }
  canvas.restore();

  if (lighting.skyTint.a > 0) {
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.screen
        ..color = lighting.skyTint,
    );
  }

  if (lighting.bloom <= 0) return;
  for (final light in lights) {
    final radius = light.radius * _bloomReach;
    final shader = _falloff(
      SceneLight(
        center: light.center,
        radius: radius,
        color: light.color,
        intensity: light.intensity * lighting.bloom,
      ),
      _bloomStops,
      _bloomAlphas,
    );
    if (shader == null) continue;
    canvas.drawCircle(
      light.center,
      radius,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = shader,
    );
  }
}

/// 빛무리는 빛이 닿는 끝까지 가지 않는다. 끝까지 가면 등불이 아니라 안개다.
const double _bloomReach = .58;

const List<double> _lightMapStops = [0, .34, .68, 1];
const List<double> _lightMapAlphas = [1, .5, .14, 0];
const List<double> _bloomStops = [0, .42, 1];
const List<double> _bloomAlphas = [.34, .1, 0];

/// 광원의 감쇠.
///
/// 알파를 세기로 쓴다. `BlendMode.plus`는 **알파를 곱한 색**을 더하므로
/// 알파 .5짜리 색을 더하면 그 색의 절반이 더해진다. 색을 직접 흐리게 만들면
/// 같은 값을 두 번 계산하게 되고, 한쪽만 고치면 조용히 어긋난다.
Shader? _falloff(SceneLight light, List<double> stops, List<double> alphas) {
  final power = light.intensity.clamp(0.0, 1.0);
  if (power <= 0 || light.radius <= 0) return null;
  return RadialGradient(
    colors: [
      for (final alpha in alphas)
        light.color.withValues(alpha: alpha * power),
    ],
    stops: stops,
  ).createShader(
    Rect.fromCircle(center: light.center, radius: light.radius),
  );
}

/// 발밑 그림자.
///
/// 조형물에는 있었고 **걷는 사람에게만 없었다.** 그래서 캐릭터가 바닥에
/// 서 있지 않고 떠 보였다. 빛이 생기면 더 티가 난다 — 밝은 바닥 위에
/// 그림자 없는 사람은 오려 붙인 것처럼 보인다.
void paintContactShadow(
  Canvas canvas, {
  required Offset foot,
  required double width,
  double opacity = 1,
}) {
  if (width <= 0 || opacity <= 0) return;
  canvas.drawOval(
    Rect.fromCenter(
      center: foot,
      width: width,
      height: math.max(3, width * .34),
    ),
    Paint()
      ..color = Colors.black.withValues(alpha: .38 * opacity.clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
}

/// 등불이 흔들리는 정도.
///
/// 흔들림을 광원마다 다른 위상으로 준다. 같은 위상이면 방 안의 등불이 전부
/// 동시에 깜빡여서 불이 아니라 형광등 고장처럼 보인다.
double lanternFlicker(double phase, int seed, {bool still = false}) {
  if (still) return 1;
  final wave = math.sin((phase * 2 + seed * .37) * math.pi * 2);
  final slow = math.sin((phase + seed * .61) * math.pi * 2);
  return (1 + wave * .045 + slow * .05).clamp(.85, 1.1);
}
