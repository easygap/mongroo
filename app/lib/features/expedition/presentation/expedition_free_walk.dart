/// 지도를 **직접 걸어 다니는** 조작의 판정부.
///
/// 화면을 그리는 코드와 섞지 않는다. 스틱이 어느 쪽을 가리키는지, 한 프레임에
/// 얼마나 나아가는지, 지금 어느 자리에 서 있는지는 전부 순수 계산이라 위젯을
/// 띄우지 않고 시험할 수 있어야 한다.
///
/// 노드를 눌러 이동하는 길은 **없애지 않는다.** 가상 스틱은 화면을 보고 손가락을
/// 끄는 사람의 것이고, 스크린리더 사용자에게는 쓸 수 없는 조작이다. 둘 다 남겨
/// 두고 마지막에는 같은 서버 `move` 호출로 모인다.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'expedition_walk_area.dart';

/// 스틱 손잡이가 움직일 수 있는 반지름(논리 픽셀).
const double expeditionStickRadius = 52;

/// 이 안에서는 움직이지 않는다. 손가락을 얹기만 해도 캐릭터가 흐르는 것을 막는다.
const double expeditionStickDeadZone = 8;

/// 1초에 지도를 얼마나 가로지르는가(0~1 정규화 기준).
///
/// 0.42면 지도 가로를 약 2.4초에 건넌다. 더 빠르면 좁은 통로에서 벽에 계속
/// 부딪히고, 더 느리면 3분 세션에서 이동이 지루해진다.
const double expeditionWalkSpeed = 0.42;

/// 노드에 이만큼 다가가면 그 자리에 선 것으로 본다.
///
/// 토큰이 88px이고 지도가 대략 360~720px이라, 0.06이면 토큰 반쯤이 노드에
/// 겹쳤을 때다. 더 좁히면 정확히 밟아야 해서 답답하고, 넓히면 지나가다 원치
/// 않는 곳으로 들어간다.
const double expeditionNodeReach = 0.06;

/// 스틱이 가리키는 방향과 세기.
///
/// 세기는 0~1이고 손잡이가 반지름 끝에 닿으면 1이다. 죽은 구역 안에서는
/// `Offset.zero`를 돌려주므로 호출부가 따로 판단하지 않아도 된다.
Offset expeditionStickVector(Offset center, Offset touch) {
  final delta = touch - center;
  final distance = delta.distance;
  if (distance <= expeditionStickDeadZone) return Offset.zero;
  final clamped = math.min(distance, expeditionStickRadius);
  // 죽은 구역 바로 바깥에서 갑자기 최고 속도가 되지 않도록 다시 0부터 센다.
  final strength = (clamped - expeditionStickDeadZone) /
      (expeditionStickRadius - expeditionStickDeadZone);
  return delta / distance * strength;
}

/// 손잡이를 그릴 자리. 반지름 밖으로 나가지 않는다.
Offset expeditionStickKnob(Offset center, Offset touch) {
  final delta = touch - center;
  final distance = delta.distance;
  if (distance <= expeditionStickRadius) return touch;
  return center + delta / distance * expeditionStickRadius;
}

/// 한 프레임 걸은 뒤의 자리.
///
/// 지도는 가로가 세로보다 길어서 정규화 좌표로 같은 값을 더하면 세로로 더 빨리
/// 움직인다. `aspect`(가로÷세로)로 세로 성분을 눌러 **화면에서 같은 속도**로
/// 보이게 한다.
Offset expeditionWalkStep({
  required ExpeditionWalkArea area,
  required Offset from,
  required Offset direction,
  required double seconds,
  required double aspect,
}) {
  if (direction == Offset.zero || seconds <= 0) return from;
  final distance = expeditionWalkSpeed * seconds;
  final delta = Offset(
    direction.dx * distance,
    direction.dy * distance * (aspect <= 0 ? 1 : aspect),
  );

  // 한 번에 멀리 옮기면 **벽을 통째로 뛰어넘는다.** 걸음은 도착 자리만 보고
  // 판정하므로, 프레임이 한 번 길게 끊기면(탭 전환·첫 로딩) 개울 건너편에
  // 착지할 수 있다. 통행 칸보다 짧게 잘라 여러 번 걷는다.
  final span = math.max(delta.dx.abs(), delta.dy.abs());
  final slices = math.max(1, (span / _maxStep).ceil());
  var position = from;
  for (var index = 0; index < slices; index++) {
    position = expeditionStepWithin(area, position, delta / slices.toDouble());
  }
  return position;
}

/// 한 번에 옮길 수 있는 최대 거리(정규화 좌표).
///
/// 통행 격자 한 칸이 세로 1/45라, 반 칸이면 어떤 벽도 뛰어넘지 못한다.
const double _maxStep = .5 / 45;

/// 지금 서 있는 자리의 노드 코드. 아무 데도 아니면 null.
///
/// 여러 노드가 가까우면 **가장 가까운 것**을 고른다. 겹친 자리에서 뒤쪽 노드가
/// 뽑히면 사용자가 보고 있는 것과 다른 곳으로 들어간다.
String? expeditionNodeAt(
  Map<String, Offset> nodes,
  Offset point, {
  double reach = expeditionNodeReach,
}) {
  String? best;
  var bestDistance = double.infinity;
  for (final entry in nodes.entries) {
    final distance = (entry.value - point).distance;
    if (distance <= reach && distance < bestDistance) {
      bestDistance = distance;
      best = entry.key;
    }
  }
  return best;
}

/// 지도에서 앞뒤를 가르는 값. 클수록 화면 앞이다.
///
/// 위에서 비스듬히 본 그림이라 **아래에 있을수록 앞**이다. 캐릭터와 랜드마크를
/// 이 값으로 정렬하면 기둥 뒤로 지나갈 수 있다.
double expeditionDepthOf(Offset point) => point.dy;

/// 걸음에 맞춰 그림자가 얼마나 짧아지는가.
///
/// 발이 떴을 때 그림자가 그대로면 붙어 다니는 판처럼 보인다. 들썩임과 반대로
/// 줄여 바닥에 닿았다 떨어지는 느낌을 만든다.
double expeditionShadowScale(bool moving, double stride) {
  if (!moving) return 1;
  final lift = math.sin(stride * 9 * math.pi).abs();
  return 1 - lift * .22;
}
