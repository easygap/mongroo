/// 통행 마스크 위에서 **실제 길을 따라가는** 경로를 찾는다.
///
/// 전에는 두 노드를 잇고 가운데를 부풀린 굽이를 썼다. 굽는 방향은 노드 코드
/// 해시로 정했으므로 그림과는 아무 상관이 없었고, 그래서 캐릭터가 개울과 수풀을
/// 가로질렀다. 이제는 걸을 수 있는 칸이 데이터로 있으니 그 위에서 찾으면 된다.
///
/// 격자 A*로 칸 경로를 얻고, 계단처럼 각진 것을 **줄 당기기**로 펴고, 마지막에
/// 모서리를 둥글린다. 셋 다 필요하다 — 칸 경로만 쓰면 톱니처럼 걷고, 펴기만
/// 하면 꺾이는 자리가 각지고, 둥글리기만 하면 길 밖으로 나간다.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'expedition_walk_area.dart';

/// 지도 가로세로 비. 칸이 정사각형이 아니라 거리를 잴 때 가로를 늘려야 한다.
const double _aspect = 16 / 9;

/// 줄 당기기·둥글리기가 만든 점이 이만큼 벽에 가까우면 물린다.
///
/// 0이면 벽에 딱 붙은 경로가 나오고, 88px 토큰이 벽을 반쯤 먹는다.
const double _clearance = .012;

/// `start`에서 `end`까지 걸어갈 길. 못 찾으면 빈 목록.
///
/// 좌표는 0~1 정규화 값이라 지도 크기가 바뀌어도 그대로 쓴다.
List<Offset> expeditionWalkPath(
  ExpeditionWalkArea area,
  Offset start,
  Offset end,
) {
  if (area.rows.isEmpty) return const [];
  final from = area.nearestCell(start);
  final to = area.nearestCell(end);
  if (from == null || to == null) return const [];
  if (from == to) return [start, end];

  final cells = _search(area, from, to);
  if (cells.isEmpty) return const [];

  final columns = area.columns;
  final height = area.rows.length;
  final points = <Offset>[
    start,
    for (final cell in cells.skip(1).take(cells.length - 2))
      Offset((cell.$1 + .5) / columns, (cell.$2 + .5) / height),
    end,
  ];
  return _smooth(area, _pullString(area, points));
}

/// 칸 단위 A*. 대각선을 허용하되 **모서리를 뚫지 못하게** 한다.
List<(int, int)> _search(
  ExpeditionWalkArea area,
  (int, int) from,
  (int, int) to,
) {
  final columns = area.columns;
  final height = area.rows.length;

  int key((int, int) cell) => cell.$2 * columns + cell.$1;
  double heuristic((int, int) cell) {
    final dx = (cell.$1 - to.$1) / columns * _aspect;
    final dy = (cell.$2 - to.$2) / height;
    return math.sqrt(dx * dx + dy * dy);
  }

  final cost = <int, double>{key(from): 0};
  final cameFrom = <int, (int, int)>{};
  // 우선순위 큐 대신 정렬된 집합을 쓴다. 칸이 3600개뿐이라 충분하다.
  // 값이 같을 때를 칸 번호로 갈라 준다 — 갈라 주지 않으면 값이 같은 칸이
  // 서로를 덮어써 사라진다.
  final open = SplayTreeMap<(double, int), (int, int)>(
    (a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1),
  );
  open[(heuristic(from), key(from))] = from;

  while (open.isNotEmpty) {
    final head = open.firstKey()!;
    final current = open.remove(head)!;
    if (current == to) {
      final path = <(int, int)>[current];
      var cursor = current;
      while (cameFrom.containsKey(key(cursor))) {
        cursor = cameFrom[key(cursor)]!;
        path.add(cursor);
      }
      return path.reversed.toList(growable: false);
    }

    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final column = current.$1 + dx;
        final row = current.$2 + dy;
        if (!area.cellAt(column, row)) continue;
        // 대각선으로 갈 때 양옆이 막혀 있으면 벽 모서리를 뚫고 지나간다.
        if (dx != 0 && dy != 0) {
          if (!area.cellAt(current.$1 + dx, current.$2)) continue;
          if (!area.cellAt(current.$1, current.$2 + dy)) continue;
        }
        final stepX = dx / columns * _aspect;
        final stepY = dy / height;
        final next = cost[key(current)]! + math.sqrt(stepX * stepX + stepY * stepY);
        final id = key((column, row));
        if (cost.containsKey(id) && cost[id]! <= next) continue;
        cost[id] = next;
        cameFrom[id] = current;
        open[(next + heuristic((column, row)), id)] = (column, row);
      }
    }
  }
  return const [];
}

/// 사이에 낀 점을 빼도 길 안에 머무르면 뺀다.
///
/// 칸 경로는 계단처럼 각져 있다. 곧게 갈 수 있는 구간을 곧게 펴야 걷는 것처럼
/// 보인다.
List<Offset> _pullString(ExpeditionWalkArea area, List<Offset> points) {
  if (points.length <= 2) return points;
  final kept = <Offset>[points.first];
  var anchor = 0;
  while (anchor < points.length - 1) {
    var farthest = anchor + 1;
    for (var probe = points.length - 1; probe > anchor + 1; probe--) {
      if (_clearLine(area, points[anchor], points[probe])) {
        farthest = probe;
        break;
      }
    }
    kept.add(points[farthest]);
    anchor = farthest;
  }
  return kept;
}

/// 두 점을 잇는 직선이 길 안에서 **벽과 떨어져** 지나는가.
///
/// 안에 있기만 하면 된다고 보면 지름길이 길 가장자리를 훑어, 88px 토큰이 벽을
/// 반쯤 먹은 채로 걷는다. 좌우로도 한 뼘 떨어져 있어야 지나갈 수 있다고 본다.
bool _clearLine(ExpeditionWalkArea area, Offset a, Offset b) {
  final span = b - a;
  final steps = math.max(
    2,
    (math.sqrt(math.pow(span.dx * _aspect, 2) + span.dy * span.dy) * 160).ceil(),
  );
  for (var index = 0; index <= steps; index++) {
    final point = Offset.lerp(a, b, index / steps)!;
    if (!_clearPoint(area, point)) return false;
  }
  return true;
}

bool _clearPoint(ExpeditionWalkArea area, Offset point) =>
    // 상하좌우로만 찔러 보면 안 된다. 벽 모서리는 어느 축으로도 멀지만 대각선
    // 으로는 바로 옆이라, 네 방향만 보면 모서리를 스치는 점이 통과한다.
    expeditionWalkAreaMargin(area, point) >= _clearance;

/// 꺾이는 자리를 둥글린다(차이킨).
///
/// 둥글리면 모서리가 안쪽으로 잘리는데, 그 안쪽이 벽일 수 있다. 안에 있기만
/// 하면 된다고 두면 벽에 스치는 경로가 나오므로, **여유를 잃은 점은 받지 않고
/// 원래 점을 그대로 쓴다.** 그러면 최악이라도 칸 한가운데를 지나간다.
List<Offset> _smooth(ExpeditionWalkArea area, List<Offset> points) {
  var path = points;
  for (var round = 0; round < 2; round++) {
    if (path.length < 3) break;
    final next = <Offset>[path.first];
    for (var index = 0; index < path.length - 1; index++) {
      final a = path[index];
      final b = path[index + 1];
      final near = Offset.lerp(a, b, .25)!;
      final far = Offset.lerp(a, b, .75)!;
      next.add(_clearPoint(area, near) ? near : a);
      next.add(_clearPoint(area, far) ? far : b);
    }
    next.add(path.last);
    path = next;
  }
  // 같은 점이 잇달아 남으면 길이 계산만 늘어난다.
  final tidy = <Offset>[path.first];
  for (final point in path.skip(1)) {
    if ((point - tidy.last).distanceSquared > 1e-12) tidy.add(point);
  }
  return tidy;
}

/// 길 위에서 진행도 `progress`에 해당하는 자리.
///
/// 조각마다 길이가 달라서 조각 번호로 나누면 굽은 곳에서 걸음이 빨라진다.
/// 실제 길이로 나눠 **일정한 속도로** 걷게 한다.
Offset expeditionPathPosition(List<Offset> route, double progress) {
  if (route.isEmpty) return Offset.zero;
  if (route.length == 1 || progress <= 0) return route.first;
  if (progress >= 1) return route.last;
  final lengths = <double>[];
  var total = 0.0;
  for (var index = 1; index < route.length; index++) {
    final span = route[index] - route[index - 1];
    final length = math.sqrt(
      math.pow(span.dx * _aspect, 2) + span.dy * span.dy,
    );
    lengths.add(length);
    total += length;
  }
  if (total == 0) return route.last;
  var remaining = progress * total;
  for (var index = 0; index < lengths.length; index++) {
    if (remaining <= lengths[index]) {
      return Offset.lerp(
            route[index],
            route[index + 1],
            lengths[index] == 0 ? 0 : remaining / lengths[index],
          ) ??
          route[index + 1];
    }
    remaining -= lengths[index];
  }
  return route.last;
}

/// 길 위에서 진행도 `progress`일 때 캐릭터가 보는 쪽. 오른쪽 1, 왼쪽 -1.
///
/// 앞을 살짝 내다본다. 지금 자리와 다음 자리를 그대로 비교하면 조각 경계에서
/// 방향이 튄다.
double expeditionPathFacing(List<Offset> route, double progress) {
  if (route.length < 2) return 1;
  final here = expeditionPathPosition(route, progress);
  final ahead = expeditionPathPosition(route, math.min(1, progress + .06));
  final step = ahead.dx - here.dx;
  if (step.abs() < 1e-6) {
    // 세로로만 걷는 구간에서는 길 전체의 방향을 쓴다. 0을 돌려주면 캐릭터가
    // 갑자기 정면을 보다가 다시 돌아 어색하다.
    return route.last.dx >= route.first.dx ? 1 : -1;
  }
  return step >= 0 ? 1 : -1;
}

/// 길이 벽에 스치지 않는지. 경로 품질을 재는 테스트가 쓴다.
///
/// 기준은 **칸 반쪽**이다. 격자 한 칸은 화면에서 정사각형이라(1600×900을 80×45로
/// 나눴다) 칸 한가운데는 어느 쪽 벽에서도 반 칸만큼 떨어져 있다. 그보다 가까운
/// 점이 있다면 다듬는 과정이 길을 벽 쪽으로 밀었다는 뜻이다.
bool expeditionPathKeepsClear(ExpeditionWalkArea area, List<Offset> route) {
  if (area.rows.isEmpty) return false;
  final half = .5 / area.rows.length - 1e-6;
  for (final point in route) {
    if (expeditionWalkAreaMargin(area, point) < half) return false;
  }
  return true;
}
