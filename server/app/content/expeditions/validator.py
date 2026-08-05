"""탐험 콘텐츠의 그래프·사건·안전 경로 정적 검증."""

from __future__ import annotations

import argparse
import copy
import heapq
import json
from pathlib import Path
from typing import Any


ALLOWED_STATS = {"care", "focus", "courage", "insight"}


class ContentValidationError(ValueError):
    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__("\n".join(errors))


def expand_map_templates(content: dict[str, Any]) -> list[dict[str, Any]]:
    """기준 튜토리얼 지도에 간선·좌표 override를 적용해 독립 스냅샷을 만든다."""
    base = content.get("map")
    if not isinstance(base, dict):
        return []
    maps = [copy.deepcopy(base)]
    for override in content.get("map_templates", []):
        if not isinstance(override, dict):
            continue
        expanded = copy.deepcopy(base)
        expanded["code"] = override.get("code")
        expanded["name"] = override.get("name")
        expanded["edges"] = copy.deepcopy(override.get("edges", []))
        coordinate_overrides = override.get("coordinate_overrides", {})
        if isinstance(coordinate_overrides, dict):
            for node in expanded.get("nodes", []):
                values = coordinate_overrides.get(node.get("code"))
                if isinstance(values, dict):
                    node.update(values)
        maps.append(expanded)
    return maps


def validate_content(content: dict[str, Any]) -> None:
    errors: list[str] = []
    if content.get("schema_version") != 1:
        errors.append("schema_version: 지원하는 버전은 1입니다")
    if not isinstance(content.get("content_version"), str):
        errors.append("content_version: 문자열이 필요합니다")
    region = content.get("region")
    if not isinstance(region, dict) or not region.get("code"):
        errors.append("region: code가 있는 객체가 필요합니다")
    else:
        reward = region.get("reward")
        if not isinstance(reward, dict) or any(
            not isinstance(reward.get(key), int) or reward[key] < 0
            for key in ("exp", "seeds")
        ):
            errors.append("region.reward: 0 이상의 exp와 seeds가 필요합니다")

    events = content.get("events")
    if not isinstance(events, dict) or not events:
        errors.append("events: 사건 객체가 하나 이상 필요합니다")
        events = {}
    for event_code, event in events.items():
        _validate_event(event_code, event, errors)

    discoveries = content.get("discoveries")
    if not isinstance(discoveries, dict):
        errors.append("discoveries: 객체가 필요합니다")
        discoveries = {}

    maps = expand_map_templates(content)
    if len(maps) < 3:
        errors.append(
            f"map_templates: 기준 지도를 포함해 3종 이상이어야 합니다 (현재 {len(maps)})"
        )
    codes = [item.get("code") for item in maps]
    if len(codes) != len(set(codes)):
        errors.append("maps: 지도 code가 중복됩니다")
    for map_data in maps:
        _validate_map(map_data, events, discoveries, errors)

    threads = content.get("run_threads")
    if not isinstance(threads, list) or not threads:
        errors.append("run_threads: 한 개 이상의 seed/echo/payoff가 필요합니다")
    else:
        thread_codes: set[str] = set()
        for index, thread in enumerate(threads):
            prefix = f"run_threads[{index}]"
            if not isinstance(thread, dict):
                errors.append(f"{prefix}: 객체가 필요합니다")
                continue
            code = thread.get("code")
            if not isinstance(code, str) or not code:
                errors.append(f"{prefix}.code: 값이 필요합니다")
            elif code in thread_codes:
                errors.append(f"{prefix}.code: {code}가 중복됩니다")
            thread_codes.add(code)
            for key in ("seed", "echo", "payoff"):
                if not isinstance(thread.get(key), str) or not thread[key].strip():
                    errors.append(f"{prefix}.{key}: 비어 있지 않은 문장이 필요합니다")

    if errors:
        raise ContentValidationError(errors)


def _validate_event(event_code: str, event: Any, errors: list[str]) -> None:
    prefix = f"events.{event_code}"
    if not isinstance(event, dict):
        errors.append(f"{prefix}: 객체가 필요합니다")
        return
    choices = event.get("choices")
    if not isinstance(choices, list) or len(choices) < 3:
        errors.append(f"{prefix}.choices: 능력치 선택 2개와 안전 선택이 필요합니다")
        return
    choice_codes: set[str] = set()
    stats: set[str] = set()
    safe_count = 0
    for index, choice in enumerate(choices):
        choice_prefix = f"{prefix}.choices[{index}]"
        if not isinstance(choice, dict):
            errors.append(f"{choice_prefix}: 객체가 필요합니다")
            continue
        code = choice.get("code")
        if not isinstance(code, str) or not code:
            errors.append(f"{choice_prefix}.code: 값이 필요합니다")
        elif code in choice_codes:
            errors.append(f"{choice_prefix}.code: {code}가 중복됩니다")
        choice_codes.add(code)
        if choice.get("safe") is True:
            safe_count += 1
            if choice.get("stat") is not None or choice.get("resolve_cost") != 0:
                errors.append(
                    f"{choice_prefix}: 안전 선택은 stat=null, resolve_cost=0이어야 합니다"
                )
            continue
        stat = choice.get("stat")
        if stat not in ALLOWED_STATS:
            errors.append(f"{choice_prefix}.stat: 지원하지 않는 능력치입니다")
        else:
            stats.add(stat)
        difficulty = choice.get("difficulty")
        if not isinstance(difficulty, int) or difficulty <= 0:
            errors.append(f"{choice_prefix}.difficulty: 1 이상의 정수가 필요합니다")
    if len(stats) < 2:
        errors.append(f"{prefix}: 서로 다른 능력치 해결법이 2개 이상 필요합니다")
    if safe_count != 1:
        errors.append(f"{prefix}: 안전 선택이 정확히 하나여야 합니다")


def _validate_map(
    map_data: Any,
    events: dict[str, Any],
    discoveries: dict[str, Any],
    errors: list[str],
) -> None:
    if not isinstance(map_data, dict):
        errors.append("maps: 지도 객체가 필요합니다")
        return
    code = map_data.get("code") or "<unknown>"
    prefix = f"maps.{code}"
    nodes = map_data.get("nodes")
    if not isinstance(nodes, list) or len(nodes) < 4:
        errors.append(f"{prefix}.nodes: 네 개 이상의 노드가 필요합니다")
        return
    by_code: dict[str, dict] = {}
    type_counts: dict[str, int] = {}
    for index, node in enumerate(nodes):
        node_prefix = f"{prefix}.nodes[{index}]"
        if not isinstance(node, dict):
            errors.append(f"{node_prefix}: 객체가 필요합니다")
            continue
        node_code = node.get("code")
        if not isinstance(node_code, str) or not node_code:
            errors.append(f"{node_prefix}.code: 값이 필요합니다")
            continue
        if node_code in by_code:
            errors.append(f"{node_prefix}.code: {node_code}가 중복됩니다")
        by_code[node_code] = node
        node_type = node.get("type")
        type_counts[node_type] = type_counts.get(node_type, 0) + 1
        if not isinstance(node.get("x"), (int, float)) or not 0 <= node["x"] <= 1:
            errors.append(f"{node_prefix}.x: 0~1 좌표가 필요합니다")
        if not isinstance(node.get("y"), (int, float)) or not 0 <= node["y"] <= 1:
            errors.append(f"{node_prefix}.y: 0~1 좌표가 필요합니다")
        if not isinstance(node.get("cost"), int) or node["cost"] < 0:
            errors.append(f"{node_prefix}.cost: 0 이상의 정수가 필요합니다")
        event_code = node.get("event_code")
        if event_code is not None and event_code not in events:
            errors.append(f"{node_prefix}.event_code: {event_code} 사건이 없습니다")
        if node_type == "discovery" and node_code not in discoveries:
            errors.append(f"{node_prefix}: 발견 문장이 없습니다")

    for required_type in ("entrance", "objective", "exit"):
        if type_counts.get(required_type) != 1:
            errors.append(f"{prefix}: {required_type} 노드가 정확히 하나여야 합니다")
    entrance = map_data.get("entrance")
    if entrance not in by_code or by_code.get(entrance, {}).get("type") != "entrance":
        errors.append(f"{prefix}.entrance: entrance 노드를 가리켜야 합니다")

    adjacency = {node_code: set() for node_code in by_code}
    seen_edges: set[tuple[str, str]] = set()
    edges = map_data.get("edges")
    if not isinstance(edges, list):
        errors.append(f"{prefix}.edges: 배열이 필요합니다")
        edges = []
    for index, edge in enumerate(edges):
        if not isinstance(edge, list) or len(edge) != 2:
            errors.append(f"{prefix}.edges[{index}]: 노드 code 두 개가 필요합니다")
            continue
        left, right = edge
        if left not in by_code or right not in by_code:
            errors.append(f"{prefix}.edges[{index}]: 존재하지 않는 노드를 참조합니다")
            continue
        if left == right:
            errors.append(f"{prefix}.edges[{index}]: 자기 자신을 연결할 수 없습니다")
            continue
        normalized = tuple(sorted((left, right)))
        if normalized in seen_edges:
            errors.append(f"{prefix}.edges[{index}]: 중복 간선입니다")
            continue
        seen_edges.add(normalized)
        adjacency[left].add(right)
        adjacency[right].add(left)

    if entrance in adjacency:
        reachable = _reachable(adjacency, entrance)
        missing = set(by_code) - reachable
        if missing:
            errors.append(f"{prefix}: 입구에서 갈 수 없는 노드 {sorted(missing)}")
    objective = next(
        (
            node_code
            for node_code, node in by_code.items()
            if node.get("type") == "objective"
        ),
        None,
    )
    exit_code = next(
        (
            node_code
            for node_code, node in by_code.items()
            if node.get("type") == "exit"
        ),
        None,
    )
    if entrance in adjacency and objective in adjacency:
        if _path_count(adjacency, entrance, objective, limit=2) < 2:
            errors.append(
                f"{prefix}: 입구에서 목표까지 서로 다른 경로가 2개 이상 필요합니다"
            )
        minimum_cost = _minimum_cost(adjacency, by_code, entrance, objective)
        if minimum_cost > 10:
            errors.append(f"{prefix}: 시작 길빛 10으로 목표에 도달할 수 없습니다")
    if entrance in adjacency and exit_code in adjacency and objective is not None:
        without_objective = {
            node: {neighbor for neighbor in neighbors if neighbor != objective}
            for node, neighbors in adjacency.items()
            if node != objective
        }
        if exit_code in _reachable(without_objective, entrance):
            errors.append(f"{prefix}: 목표를 거치지 않고 출구에 도달할 수 있습니다")
    initial = map_data.get("initial_revealed")
    if not isinstance(initial, list) or entrance not in initial:
        errors.append(f"{prefix}.initial_revealed: 입구를 포함해야 합니다")
    elif any(node_code not in by_code for node_code in initial):
        errors.append(f"{prefix}.initial_revealed: 존재하지 않는 노드가 있습니다")


def _reachable(adjacency: dict[str, set[str]], start: str) -> set[str]:
    if start not in adjacency:
        return set()
    seen = {start}
    pending = [start]
    while pending:
        current = pending.pop()
        for neighbor in adjacency.get(current, set()):
            if neighbor not in seen:
                seen.add(neighbor)
                pending.append(neighbor)
    return seen


def _path_count(
    adjacency: dict[str, set[str]], start: str, target: str, *, limit: int
) -> int:
    count = 0

    def visit(current: str, seen: set[str]) -> None:
        nonlocal count
        if count >= limit:
            return
        if current == target:
            count += 1
            return
        for neighbor in adjacency.get(current, set()):
            if neighbor not in seen:
                visit(neighbor, seen | {neighbor})

    visit(start, {start})
    return count


def _minimum_cost(
    adjacency: dict[str, set[str]], nodes: dict[str, dict], start: str, target: str
) -> int:
    distances = {start: 0}
    queue: list[tuple[int, str]] = [(0, start)]
    while queue:
        distance, current = heapq.heappop(queue)
        if current == target:
            return distance
        if distance != distances[current]:
            continue
        for neighbor in adjacency.get(current, set()):
            next_distance = distance + int(nodes[neighbor].get("cost", 0))
            if next_distance < distances.get(neighbor, 1_000_000):
                distances[neighbor] = next_distance
                heapq.heappush(queue, (next_distance, neighbor))
    return 1_000_000


def main() -> int:
    parser = argparse.ArgumentParser(description="직접 탐험 콘텐츠 계약 검증")
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.paths:
        try:
            with path.open(encoding="utf-8") as file:
                validate_content(json.load(file))
            print(f"OK {path}")
        except (OSError, json.JSONDecodeError, ContentValidationError) as error:
            failed = True
            print(f"FAIL {path}\n{error}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
