/// 지형 지도에서 **걸어 다닐 수 있는 땅**.
///
/// 배경은 그림이라 코드가 통로를 모른다. 자유 이동을 붙이려면 어디가 땅이고
/// 어디가 벽인지를 데이터로 줘야 한다. 노드를 눌러 이동하던 동안에는 간선이
/// 대신 그 일을 했지만(길이 아닌 곳으로는 애초에 갈 수 없었다), 아무 데나
/// 걸으려면 경계가 필요하다.
///
/// 처음에는 볼록 다각형 하나로 감쌌다. 그랬더니 개울 위와 유적 안을 걸어 다닐
/// 수 있었다 — 지형 지도의 길은 랜드마크를 잇는 **그물**이라 한 덩어리로
/// 감싸지지 않는다. 다각형을 여러 개 겹쳐도 마찬가지였다. 길이 곧지 않다.
///
/// 그래서 그림에서 직접 읽는다. `design-system/scripts/build_walk_masks.py`가
/// 원화를 80×45 격자로 훑어 글자 지도를 만들고, 이 파일은 그 지도를 읽는다.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'expedition_walk_masks.dart';

/// 지도 가로세로 비. 격자 한 칸은 가로가 세로보다 넓어서, 화면 거리를 재려면
/// 가로 좌표에 이만큼을 곱해야 한다.
const double _mapAspect = 16 / 9;

/// 걸을 수 있는 땅. 좌표는 0~1 정규화라 지도 크기와 무관하다.
class ExpeditionWalkArea {
  const ExpeditionWalkArea(this.rows);

  /// 한 줄이 격자 한 행. `#`이 걸을 수 있는 칸이다.
  final List<String> rows;

  int get columns => rows.isEmpty ? 0 : rows.first.length;

  bool cellAt(int column, int row) {
    if (row < 0 || row >= rows.length) return false;
    final line = rows[row];
    if (column < 0 || column >= line.length) return false;
    return line.codeUnitAt(column) == 0x23; // '#'
  }

  /// 이 점을 밟을 수 있는가.
  bool contains(Offset point) {
    if (rows.isEmpty) return false;
    return cellAt(
      (point.dx * columns).floor(),
      (point.dy * rows.length).floor(),
    );
  }

  /// 땅 밖으로 나간 점을 가장 가까운 땅으로 되돌린다.
  ///
  /// 벽에 부딪히면 멈추는 대신 **벽을 따라 미끄러지게** 하려는 것이다. 멈추면
  /// 조작이 걸린 것처럼 느껴지고, 되돌리면 벽을 훑으며 계속 걷는다.
  ///
  /// 칸 한가운데로 보내지 않고 **칸 안쪽 가장 가까운 자리**로 보낸다. 가운데로
  /// 보내면 벽을 스칠 때마다 캐릭터가 톡톡 튄다.
  Offset clampInside(Offset point) {
    if (contains(point)) return point;
    final cell = nearestCell(point);
    if (cell == null) return point;
    return _insideCell(cell.$1, cell.$2, point);
  }

  /// 이 점에서 화면상 가장 가까운 걸을 수 있는 칸.
  (int, int)? nearestCell(Offset point) {
    if (rows.isEmpty) return null;
    final height = rows.length;
    final startColumn = (point.dx * columns).floor().clamp(0, columns - 1);
    final startRow = (point.dy * height).floor().clamp(0, height - 1);
    if (cellAt(startColumn, startRow)) return (startColumn, startRow);

    // 고리 모양으로 넓혀 가며 찾는다. 첫 고리에서 찾아도 그 고리는 끝까지
    // 훑는다 — 격자 칸이 정사각형이 아니라, 먼저 만난 칸이 화면에서 더
    // 가깝다는 보장이 없다.
    (int, int)? best;
    var bestGap = double.infinity;
    final reach = math.max(columns, height);
    for (var ring = 1; ring <= reach; ring++) {
      for (var row = startRow - ring; row <= startRow + ring; row++) {
        for (var column = startColumn - ring;
            column <= startColumn + ring;
            column++) {
          final onEdge = (row - startRow).abs() == ring ||
              (column - startColumn).abs() == ring;
          if (!onEdge || !cellAt(column, row)) continue;
          final gap = (_cellCentre(column, row) - point);
          final distance = math.sqrt(
            math.pow(gap.dx * _mapAspect, 2) + gap.dy * gap.dy,
          );
          if (distance < bestGap) {
            bestGap = distance;
            best = (column, row);
          }
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  Offset _cellCentre(int column, int row) => Offset(
        (column + .5) / columns,
        (row + .5) / rows.length,
      );

  Offset _insideCell(int column, int row, Offset point) {
    final width = 1 / columns;
    final height = 1 / rows.length;
    // 가장자리에 딱 붙이면 반올림이 어느 쪽으로 떨어지느냐에 따라 다시 바깥
    // 칸으로 읽힌다. 아주 살짝 안쪽으로 넣는다.
    const inset = 1e-4;
    return Offset(
      point.dx.clamp(column * width + inset, (column + 1) * width - inset),
      point.dy.clamp(row * height + inset, (row + 1) * height - inset),
    );
  }
}

/// 지역별 걸을 수 있는 땅. 생성기가 만든 글자 지도를 그대로 감싼다.
final expeditionRegionWalkAreas = <String, ExpeditionWalkArea>{
  for (final entry in expeditionWalkMasks.entries)
    entry.key: ExpeditionWalkArea(entry.value),
};

/// 전용 지도가 없는 지역이 기대는 땅. 첫 지역의 것을 쓴다.
final expeditionSharedWalkArea =
    expeditionRegionWalkAreas['moss_archive'] ?? const ExpeditionWalkArea([]);

ExpeditionWalkArea expeditionWalkAreaFor(String? regionCode) =>
    expeditionRegionWalkAreas[regionCode] ?? expeditionSharedWalkArea;

/// 노드 표식 자리에서 캐릭터가 **실제로 설 자리**.
///
/// 표식은 랜드마크 위에 찍힌다 — 아치 안, 우물 위, 나무 그루터기 한가운데다.
/// 그 자리를 걸을 수 있게 뚫으면 그루터기 위를 걷게 되므로, 대신 가장 가까운
/// 길로 내려 세운다. 랜드마크에 다가가는 것이지 올라서는 게 아니다.
Offset expeditionStandPoint(ExpeditionWalkArea area, Offset marker) {
  if (area.contains(marker)) return marker;
  final cell = area.nearestCell(marker);
  if (cell == null) return marker;
  return Offset(
    (cell.$1 + .5) / area.columns,
    (cell.$2 + .5) / area.rows.length,
  );
}

/// 걸음이 땅을 벗어나지 않게 다듬은 다음 자리.
///
/// 자유 이동에서 매 프레임 부른다. 벽을 넘어서면 축을 하나씩 나눠 보아 **벽을
/// 따라 미끄러지게** 한다.
Offset expeditionStepWithin(
  ExpeditionWalkArea area,
  Offset from,
  Offset delta,
) {
  final target = Offset(
    (from.dx + delta.dx).clamp(0.0, 1.0),
    (from.dy + delta.dy).clamp(0.0, 1.0),
  );
  if (area.contains(target)) return target;

  final slideX = Offset(target.dx, from.dy);
  if (area.contains(slideX)) return slideX;
  final slideY = Offset(from.dx, target.dy);
  if (area.contains(slideY)) return slideY;

  return area.clampInside(target);
}

/// 길이 땅을 벗어나는 구간이 있는지.
///
/// 노드 사이의 길이 벽을 뚫는지 확인하는 데 쓴다. 길은 자동 생성이라 지도
/// 좌표를 손보면 벽을 지날 수 있고, 그건 눈으로는 잘 안 보인다.
bool expeditionRouteStaysInside(ExpeditionWalkArea area, List<Offset> route) {
  for (final point in route) {
    if (!area.contains(point)) return false;
  }
  return true;
}

/// 땅의 넓이(0~1). 너무 좁으면 걸어 다닐 곳이 없고, 너무 넓으면 경계가 없는
/// 것과 같다.
double expeditionWalkAreaCoverage(ExpeditionWalkArea area) {
  if (area.rows.isEmpty) return 0;
  var inside = 0;
  for (final line in area.rows) {
    for (var index = 0; index < line.length; index++) {
      if (line.codeUnitAt(index) == 0x23) inside++;
    }
  }
  return inside / (area.columns * area.rows.length);
}

/// 이 점이 땅에서 얼마나 안쪽인지. 지도 **세로 길이**를 1로 본 거리다.
///
/// 벽에 붙은 자리에 서면 88px 토큰이 벽을 먹는다. 노드의 설 자리를 고를 때
/// 쓴다.
double expeditionWalkAreaMargin(ExpeditionWalkArea area, Offset point) {
  if (!area.contains(point)) return -1;
  final columns = area.columns;
  final height = area.rows.length;
  final column = (point.dx * columns).floor();
  final row = (point.dy * height).floor();
  var best = double.infinity;
  final reach = math.max(columns, height);
  for (var ring = 1; ring <= reach; ring++) {
    var found = false;
    for (var r = row - ring; r <= row + ring; r++) {
      for (var c = column - ring; c <= column + ring; c++) {
        final onEdge = (r - row).abs() == ring || (c - column).abs() == ring;
        if (!onEdge || area.cellAt(c, r)) continue;
        found = true;
        // 막힌 칸의 가장 가까운 모서리까지의 거리.
        final left = c / columns;
        final right = (c + 1) / columns;
        final top = r / height;
        final bottom = (r + 1) / height;
        final dx = point.dx < left
            ? left - point.dx
            : (point.dx > right ? point.dx - right : 0.0);
        final dy = point.dy < top
            ? top - point.dy
            : (point.dy > bottom ? point.dy - bottom : 0.0);
        best = math.min(
          best,
          math.sqrt(math.pow(dx * _mapAspect, 2) + dy * dy),
        );
      }
    }
    // 한 고리에서 벽을 찾았어도 다음 고리까지는 본다 — 칸이 정사각형이
    // 아니라 더 먼 고리의 벽이 화면에서는 더 가까울 수 있다.
    if (found && ring > 1) break;
  }
  return best == double.infinity ? 1 : best;
}
