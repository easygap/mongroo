"""지형 원화에서 **걸어 다닐 수 있는 칸**을 뽑아 다트 데이터로 낸다.

## 왜 손으로 그린 다각형이 아니라 그림에서 뽑는가

자유 이동을 붙이면서 걸을 수 있는 땅을 볼록 다각형 하나로 감쌌더니 개울 위와
유적 안을 걸어 다닐 수 있었다. 지형 원화의 길은 랜드마크를 잇는 **그물**이라
한 덩어리로 감싸지지 않는다. 다각형을 여러 개 겹쳐도 마찬가지다 — 길이 곧지
않아서, 다각형 열두 개로도 그림과 어긋난다.

그림이 원본이다. 그래서 그림에서 읽는다. 읽은 결과는 80×45 격자의 **글자 지도**로
다트에 박아 둔다. 격자 한 칸은 1600×900에서 20×20 픽셀이고, 걷는 토큰이 88px라
칸 단위로도 충분히 곱게 걸린다. 글자 지도라 사람이 눈으로 읽고 손으로 고칠 수
있으며, 원화를 다시 뽑으면 이 스크립트를 다시 돌리면 된다.

## 어떻게 가르는가

밝기 하나로는 안 된다 — 밤 조명이라 수풀도 길만큼 밝다. 색 덩어리 대표색으로
가르는 것도 안 됐다 — 그늘 진 길이 이끼 쪽으로 붙어 길이 토막 났다.

그래서 세 가지를 함께 본다.
* **밝기**: 길은 조명을 받는다.
* **따뜻함**(R−B): 모랫길·나무 회랑은 따뜻하고, 물·밤하늘은 차다.
* **초록 치우침**(G−R): 수풀은 초록이 앞선다. 길은 그렇지 않다.

문턱은 지역마다 다르다. 별씨앗 보관고 바닥은 창백한 돌이라 따뜻하지 않고,
심장나무 회랑은 아주 따뜻하다. 세 숫자를 지역표에 적어 두고 겹쳐 본 그림으로
맞춘다(`--overlay`).

사용법:
    python build_walk_masks.py            # 다트 파일을 다시 쓴다
    python build_walk_masks.py --check    # 다시 쓰지 않고 어긋나면 실패한다
    python build_walk_masks.py --overlay <폴더>   # 원화 위에 겹쳐 눈으로 검사
"""

from __future__ import annotations

import argparse
import sys
from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("Pillow가 필요합니다: pip install Pillow")
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[2]
ART_DIR = ROOT / "app" / "assets" / "adventure"
OUT_PATH = (
    ROOT
    / "app"
    / "lib"
    / "features"
    / "expedition"
    / "presentation"
    / "expedition_walk_masks.dart"
)

# 격자 크기. 1600×900 원화에서 한 칸이 20×20픽셀이다.
COLS, ROWS = 80, 45
# 한 칸을 몇 등분해 표본을 뜨는지. 4면 칸마다 16점을 본다.
SUB = 4
# 칸의 표본 중 이만큼이 길이면 그 칸을 걸을 수 있다고 본다.
CELL_CUT = 0.5
# 노드 표식에서 설 자리까지 허용하는 거리. 지도 **세로 길이** 대비 비율이다.
#
# 칸 수로 세면 안 된다 — 격자 이웃은 상하좌우뿐이라 대각선이 두 배로 세어지고,
# 게다가 칸은 가로세로 픽셀 수가 달라 같은 `한 칸`이 화면에서 다른 거리다.
# 표식은 랜드마크 **위에** 찍히고 캐릭터는 그 **발치에** 선다. 나무 탑이나
# 그루터기처럼 큰 랜드마크는 그 발치가 제법 떨어져 있어서, 0.22(900px에서
# 200px)까지 둔다. 이보다 멀면 노드 좌표와 원화가 서로 다른 자리를 가리키는
# 것이라 사람이 봐야 한다.
MAX_REACH = 0.22

WALK = "#"
BLOCK = "."


class Region:
    """한 지역의 원화·문턱·노드."""

    def __init__(
        self,
        code: str,
        art: str,
        luma_min: float,
        warm_min: float,
        green_max: float,
        chroma_min: float,
        slack: tuple[float, float, float],
        blocks: list[tuple[float, float, float, float]],
        nodes: dict[str, tuple[float, float]],
        edges: list[tuple[str, str]],
    ) -> None:
        self.code = code
        self.art = art
        #: 이보다 어두우면 그늘이 아니라 덤불 속이다.
        self.luma_min = luma_min
        #: R−B가 이보다 작으면 물·얼음·밤하늘 쪽이다.
        self.warm_min = warm_min
        #: G−R가 이보다 크면 잎사귀다.
        self.green_max = green_max
        #: 색이 이보다 옅으면 돌이다(max−min). 모랫길·나무는 색이 짙고 돌 아치·
        #: 담장은 무채색에 가깝다. 밝기와 따뜻함만으로는 달빛 받은 돌을 못 뗀다.
        #: 별씨앗 보관고는 바닥 자체가 돌이라 0으로 끈다.
        self.chroma_min = chroma_min
        #: 씨앗에 이어져 있을 때만 받아 주는 여유 (밝기, 따뜻함, 초록).
        #:
        #: 밝기는 넉넉히 푼다 — 그늘은 어둡게 만들 뿐이다. 따뜻함은 조금만,
        #: 초록 치우침은 거의 풀지 않는다. 그늘진 길은 여전히 따뜻하고 초록이
        #: 아니지만, 옆에 붙은 돌 아치는 그 둘로만 갈리기 때문이다.
        self.slack = slack
        #: 색으로는 못 가르는 자리를 손으로 막는다 (x0, y0, x1, y1, 0~1).
        #:
        #: 비스듬히 내려다본 그림에서는 **세워진 면**이 바닥과 같은 색으로
        #: 칠해진다. 별씨앗 보관고의 씨앗 서랍장과 대형 시계가 그렇다 — 둘 다
        #: 벽면인데 바닥 돌과 밝기·채도가 같아서, 문턱을 어떻게 잡아도 바닥으로
        #: 읽힌다. 그 위에 서면 캐릭터가 벽을 타고 오른 것처럼 보인다.
        #:
        #: 색 규칙으로 갈리는 것을 여기에 적지 않는다. 여기 목록이 길어지면
        #: 문턱이 잘못 잡힌 것이다.
        self.blocks = blocks
        self.nodes = nodes
        self.edges = edges


# 세 지역이 같은 노드 배치를 쓴다(`server/scripts/build_region_packs.py`의
# NODE_LAYOUT). 기억서고만 자기 배치를 쓴다.
SHARED_NODES = {
    "entrance": (0.08, 0.50),
    "first_event": (0.27, 0.30),
    "second_event": (0.27, 0.70),
    "camp": (0.48, 0.50),
    "discovery": (0.50, 0.20),
    "guardian": (0.69, 0.50),
    "objective": (0.86, 0.32),
    "exit": (0.94, 0.62),
}
SHARED_EDGES = [
    ("entrance", "first_event"),
    ("entrance", "second_event"),
    ("first_event", "camp"),
    ("second_event", "camp"),
    ("camp", "discovery"),
    ("camp", "guardian"),
    ("guardian", "objective"),
    ("objective", "exit"),
    ("first_event", "discovery"),
    ("second_event", "discovery"),
    ("discovery", "guardian"),
    ("first_event", "second_event"),
]

MOSS_NODES = {
    "entrance": (0.08, 0.50),
    "wet_labels": (0.28, 0.27),
    "root_catalogue": (0.29, 0.72),
    "quiet_camp": (0.49, 0.19),
    "pressed_gallery": (0.50, 0.81),
    "ledger_keeper": (0.69, 0.50),
    "memory_drawer": (0.84, 0.34),
    "exit": (0.93, 0.67),
}
MOSS_EDGES = [
    ("entrance", "wet_labels"),
    ("entrance", "root_catalogue"),
    ("wet_labels", "quiet_camp"),
    ("wet_labels", "pressed_gallery"),
    ("root_catalogue", "quiet_camp"),
    ("root_catalogue", "pressed_gallery"),
    ("quiet_camp", "pressed_gallery"),
    ("quiet_camp", "ledger_keeper"),
    ("pressed_gallery", "ledger_keeper"),
    ("ledger_keeper", "memory_drawer"),
    ("memory_drawer", "exit"),
]

REGIONS = [
    Region(
        "moss_archive",
        "expedition-moss-archive-terrain-v3.webp",
        # 밝은 모랫길만 씨앗으로 삼는다. 이끼 언덕과 돌 아치가 바로 옆이라
        # 씨앗을 느슨하게 잡으면 언덕 위를 걷게 된다.
        luma_min=112,
        warm_min=42,
        green_max=-2,
        chroma_min=40,
        slack=(46, 14, 3),
        blocks=[],
        nodes=MOSS_NODES,
        edges=MOSS_EDGES,
    ),
    Region(
        "echo_well",
        "expedition-echo-well-terrain-v1.webp",
        # 달빛만 드는 밤이라 길도 어둡다. 밝기를 낮추고 따뜻함으로 가른다.
        luma_min=92,
        warm_min=30,
        green_max=8,
        chroma_min=24,
        slack=(34, 12, 3),
        blocks=[],
        nodes=SHARED_NODES,
        edges=SHARED_EDGES,
    ),
    Region(
        "starlight_seed_vault",
        "expedition-starlight-seed-vault-terrain-v1.webp",
        # 창백한 돌바닥이라 따뜻하지 않다. 밝기와 `덜 푸름`으로 가른다.
        luma_min=134,
        warm_min=-14,
        green_max=10,
        chroma_min=0,
        slack=(34, 12, 3),
        blocks=[
            # 씨앗 서랍장 벽면.
            (0.20, 0.06, 0.35, 0.31),
            # 대형 시계 문자판.
            (0.22, 0.52, 0.37, 0.78),
        ],
        nodes=SHARED_NODES,
        edges=SHARED_EDGES,
    ),
    Region(
        "heartwood_observatory",
        "expedition-heartwood-observatory-terrain-v1.webp",
        # 나무 회랑. 아주 따뜻하고 나무껍질보다 밝다.
        luma_min=74,
        warm_min=52,
        green_max=4,
        chroma_min=42,
        slack=(34, 12, 3),
        blocks=[],
        nodes=SHARED_NODES,
        edges=SHARED_EDGES,
    ),
]


# ── 격자 만들기 ────────────────────────────────────────────────────────────


def _is_path(region: Region, loose: bool, r: int, g: int, b: int) -> bool:
    luma_slack, warm_slack, green_slack = region.slack if loose else (0, 0, 0)
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    return (
        luma >= region.luma_min - luma_slack
        and (r - b) >= region.warm_min - warm_slack
        and (g - r) <= region.green_max + green_slack
        and max(r, g, b) - min(r, g, b) >= region.chroma_min
    )


def _classify(region: Region) -> list[list[bool]]:
    """길 칸을 정한다. 문턱 하나가 아니라 **두 겹**으로 본다.

    문턱을 빡빡하게 잡으면 그늘에 든 길이 떨어져 나가 지도가 토막 나고, 느슨하게
    잡으면 돌 아치와 이끼 언덕까지 걸을 수 있게 된다(기억서고에서 둘 다 겪었다).

    그래서 가장자리 검출에서 쓰는 이력(hysteresis)을 그대로 쓴다. 빡빡한 문턱을
    **씨앗**으로 삼고, 느슨한 문턱은 그 씨앗에 **이어져 있을 때만** 받아들인다.
    같은 길의 그늘진 구간은 밝은 구간에 붙어 있으니 살아나고, 따로 떨어진 아치
    지붕은 씨앗이 없으니 들어오지 못한다.
    """

    image = (
        Image.open(ART_DIR / region.art)
        .convert("RGB")
        .resize((COLS * SUB, ROWS * SUB), Image.LANCZOS)
    )
    pixels = image.load()

    def layer(loose: bool) -> list[list[bool]]:
        out = []
        for row in range(ROWS):
            line = []
            for col in range(COLS):
                hits = sum(
                    1
                    for dy in range(SUB)
                    for dx in range(SUB)
                    if _is_path(
                        region, loose, *pixels[col * SUB + dx, row * SUB + dy]
                    )
                )
                line.append(hits / (SUB * SUB) >= CELL_CUT)
            out.append(line)
        return out

    seed = layer(False)
    loose = layer(True)

    grid = [[False] * COLS for _ in range(ROWS)]
    queue = deque()
    for row in range(ROWS):
        for col in range(COLS):
            if seed[row][col] and loose[row][col]:
                grid[row][col] = True
                queue.append((col, row))
    while queue:
        col, row = queue.popleft()
        for ncol, nrow in _neighbours(col, row):
            if loose[nrow][ncol] and not grid[nrow][ncol]:
                grid[nrow][ncol] = True
                queue.append((ncol, nrow))
    return grid


def _neighbours(col: int, row: int):
    for dcol, drow in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ncol, nrow = col + dcol, row + drow
        if 0 <= ncol < COLS and 0 <= nrow < ROWS:
            yield ncol, nrow


def _tidy(grid: list[list[bool]]) -> list[list[bool]]:
    """잔점을 지우고 바늘구멍을 메운다.

    처음에는 형태학의 열기(침식→팽창)를 썼는데, 길이 두세 칸 폭이라 침식 한 번에
    좁은 구간이 통째로 사라져 길이 토막 났다(덮개 16%→9%). 길은 원래 얇으므로
    **얇다는 이유로 지우면 안 된다.** 이웃 수만 보고 다듬는다.
    """

    out = [row[:] for row in grid]
    for row in range(ROWS):
        for col in range(COLS):
            around = sum(1 for c, r in _neighbours(col, row) if grid[r][c])
            if grid[row][col]:
                # 홀로 뜬 칸은 등불빛·이끼 반사 같은 잡티다.
                if around == 0:
                    out[row][col] = False
            elif around >= 3:
                # 길 한가운데 뚫린 구멍은 화분·돌 같은 작은 물건이다.
                out[row][col] = True
    return out


def _bridge(grid: list[list[bool]]) -> list[list[bool]]:
    """길 사이의 한 칸짜리 틈을 잇는다.

    같은 길인데 그림자나 덩굴이 가로질러 마스크가 끊기는 곳이 있다. 양쪽이
    **마주 보는** 이웃일 때만 잇는다 — 아무 이웃이나 세면 수풀 섬이 길과 붙는다.
    """

    out = [row[:] for row in grid]
    for row in range(ROWS):
        for col in range(COLS):
            if grid[row][col]:
                continue
            left = col > 0 and grid[row][col - 1]
            right = col < COLS - 1 and grid[row][col + 1]
            up = row > 0 and grid[row - 1][col]
            down = row < ROWS - 1 and grid[row + 1][col]
            if (left and right) or (up and down):
                out[row][col] = True
    return out


def _component(grid: list[list[bool]], seed: tuple[int, int]) -> list[list[bool]]:
    seen = [[False] * COLS for _ in range(ROWS)]
    col, row = seed
    if not grid[row][col]:
        return seen
    seen[row][col] = True
    queue = deque([(col, row)])
    while queue:
        col, row = queue.popleft()
        for ncol, nrow in _neighbours(col, row):
            if grid[nrow][ncol] and not seen[nrow][ncol]:
                seen[nrow][ncol] = True
                queue.append((ncol, nrow))
    return seen


def node_cell(x: float, y: float) -> tuple[int, int]:
    return (
        min(COLS - 1, max(0, int(x * COLS))),
        min(ROWS - 1, max(0, int(y * ROWS))),
    )


def build(region: Region) -> tuple[list[str], dict]:
    grid = _classify(region)
    for left, top, right, bottom in region.blocks:
        for row in range(ROWS):
            for col in range(COLS):
                x = (col + 0.5) / COLS
                y = (row + 0.5) / ROWS
                if left <= x <= right and top <= y <= bottom:
                    grid[row][col] = False
    grid = _tidy(grid)
    grid = _bridge(grid)

    cells = {code: node_cell(*xy) for code, xy in region.nodes.items()}
    # 노드 표식은 **랜드마크 위에** 찍힌다 — 아치 안, 우물 위, 나무 그루터기
    # 한가운데다. 그 자리를 억지로 길로 뚫으면 그루터기 위를 걷게 된다. 대신
    # 가장 가까운 길 칸을 `설 자리`로 삼는다. 랜드마크에 다가가는 것이지
    # 올라서는 게 아니다.
    # 걸어 다니는 곳은 **가장 큰 한 덩어리**다. 등불빛·지붕·이끼 반사처럼
    # 밝지만 갈 수 없는 자리가 잔섬으로 남는데, 노드의 설 자리를 `가장 가까운
    # 길`로 잡으면 그런 잔섬에 올라타 지도 전체가 한 칸짜리가 된다(실제로
    # 심장나무 관측소가 덮개 0%로 무너졌다). 큰 덩어리만 남긴다.
    main, islands = _main_component(grid)
    grid = main

    stands = {}
    reach = {}
    for code, cell in cells.items():
        stand = _nearest_walkable(grid, cell)
        stands[code] = stand
        reach[code] = round(_screen_gap(cell, stand), 3)

    rows = ["".join(WALK if cell else BLOCK for cell in line) for line in grid]
    report = {
        "coverage": sum(sum(line) for line in grid) / (COLS * ROWS),
        "islands": islands,
        "reach": reach,
        "stands": stands,
        "cells": cells,
        "grid": grid,
    }
    return rows, report


def _main_component(grid: list[list[bool]]) -> tuple[list[list[bool]], int]:
    """가장 큰 덩어리만 남기고, 버린 잔섬의 수를 함께 돌려준다."""

    seen = [[False] * COLS for _ in range(ROWS)]
    best: list[tuple[int, int]] = []
    islands = 0
    for row in range(ROWS):
        for col in range(COLS):
            if not grid[row][col] or seen[row][col]:
                continue
            islands += 1
            patch = []
            queue = deque([(col, row)])
            seen[row][col] = True
            while queue:
                here = queue.popleft()
                patch.append(here)
                for step in _neighbours(*here):
                    if grid[step[1]][step[0]] and not seen[step[1]][step[0]]:
                        seen[step[1]][step[0]] = True
                        queue.append(step)
            if len(patch) > len(best):
                best = patch
    out = [[False] * COLS for _ in range(ROWS)]
    for col, row in best:
        out[row][col] = True
    return out, islands - 1


def _screen_gap(a: tuple[int, int], b: tuple[int, int]) -> float:
    """두 칸 사이의 화면 거리. 지도 세로 길이를 1로 본다."""

    dx = (a[0] - b[0]) / COLS * (16 / 9)
    dy = (a[1] - b[1]) / ROWS
    return (dx * dx + dy * dy) ** 0.5


def _nearest_walkable(
    grid: list[list[bool]], cell: tuple[int, int]
) -> tuple[int, int]:
    """노드 칸에서 **화면상** 가장 가까운 길 칸.

    격자 이웃을 세면 대각선이 두 배로 세어져 엉뚱한 자리를 고른다. 후보를 모두
    보고 화면 거리로 고른다 — 칸이 3600개뿐이라 다 봐도 싸다.
    """

    if grid[cell[1]][cell[0]]:
        return cell
    best = cell
    best_gap = float("inf")
    for row in range(ROWS):
        for col in range(COLS):
            if not grid[row][col]:
                continue
            gap = _screen_gap(cell, (col, row))
            if gap < best_gap:
                best_gap, best = gap, (col, row)
    return best


# ── 검사 ──────────────────────────────────────────────────────────────────


def path_exists(grid: list[list[bool]], start, goal) -> bool:
    seen = _component(grid, start)
    return seen[goal[1]][goal[0]]


def verify(region: Region, rows: list[str], report: dict) -> list[str]:
    problems = []
    # 설 자리가 표식에서 멀면 캐릭터가 랜드마크에서 동떨어져 선다.
    far = {code: steps for code, steps in report["reach"].items() if steps > MAX_REACH}
    if far:
        problems.append(
            f"설 자리가 표식에서 멉니다(칸): {far} — 좌표나 원화가 어긋났습니다"
        )
    coverage = report["coverage"]
    if coverage < 0.12:
        problems.append(f"걸을 땅이 너무 좁습니다({coverage:.2f})")
    if coverage > 0.72:
        problems.append(
            f"걸을 땅이 너무 넓습니다({coverage:.2f}) — 경계가 없는 것과 같습니다"
        )
    grid = report["grid"]
    for a, b in region.edges:
        if not path_exists(grid, report["stands"][a], report["stands"][b]):
            problems.append(f"{a} → {b} 로 걸어갈 길이 없습니다")
    if len(rows) != ROWS or any(len(row) != COLS for row in rows):
        problems.append("격자 크기가 어긋났습니다")
    return problems


# ── 다트로 내보내기 ────────────────────────────────────────────────────────


def render_dart(masks: dict[str, list[str]]) -> str:
    lines = [
        "// 자동 생성 파일입니다. 손으로 고치지 마세요.",
        "// design-system/scripts/build_walk_masks.py 로 다시 만듭니다.",
        "",
        "/// 지형 원화에서 뽑은 **걸어 다닐 수 있는 칸**.",
        "///",
        "/// 한 줄이 격자 한 행이고 `#`이 걸을 수 있는 칸, `.`이 막힌 칸이다.",
        "/// 배경은 그림이라 코드가 통로를 모른다. 손으로 다각형을 찍으면 그림과",
        "/// 어긋나 개울 위를 걷게 되므로(실제로 그랬다), 그림에서 직접 읽는다.",
        "///",
        "/// 원화를 다시 뽑으면 생성기를 다시 돌린다. 이 파일이 원화와 어긋나면",
        "/// `--check`가 잡는다.",
        "library;",
        "",
        f"const expeditionWalkMaskColumns = {COLS};",
        f"const expeditionWalkMaskRows = {ROWS};",
        "",
        "const expeditionWalkMasks = <String, List<String>>{",
    ]
    for code, rows in masks.items():
        lines.append(f"  '{code}': [")
        lines.extend(f"    '{row}'," for row in rows)
        lines.append("  ],")
    lines.append("};")
    lines.append("")
    return "\n".join(lines)


def write_overlay(region: Region, rows: list[str], report: dict, out_dir: Path) -> Path:
    """원화 위에 걸을 수 있는 칸을 덮어 눈으로 검사할 그림을 낸다."""

    width, height = 880, 495
    image = Image.open(ART_DIR / region.art).convert("RGB").resize((width, height))
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    mark = layer.load()
    for row in range(ROWS):
        for col in range(COLS):
            if rows[row][col] != WALK:
                continue
            for y in range(round(row * height / ROWS), round((row + 1) * height / ROWS)):
                for x in range(
                    round(col * width / COLS), round((col + 1) * width / COLS)
                ):
                    mark[x, y] = (60, 255, 120, 92)
    merged = Image.alpha_composite(image.convert("RGBA"), layer).convert("RGB")
    for col, row in report.get("stands", {}).values():
        x = round((col + 0.5) * width / COLS)
        y = round((row + 0.5) * height / ROWS)
        for dx in range(-6, 7):
            for dy in range(-6, 7):
                if abs(dx) + abs(dy) <= 6 and 0 <= x + dx < width and 0 <= y + dy < height:
                    merged.putpixel((x + dx, y + dy), (255, 220, 0))
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"walk-mask-{region.code}.png"
    merged.save(path)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="다시 쓰지 않고 원화와 어긋나면 실패한다",
    )
    parser.add_argument(
        "--overlay",
        type=Path,
        help="원화 위에 겹친 검사 그림을 이 폴더에 낸다",
    )
    args = parser.parse_args()

    masks: dict[str, list[str]] = {}
    failures: list[str] = []
    for region in REGIONS:
        rows, report = build(region)
        masks[region.code] = rows
        problems = verify(region, rows, report)
        mark = "  " if not problems else "✗ "
        print(f"{mark}{region.code:<24} 덮개 {report['coverage'] * 100:4.1f}%")
        for problem in problems:
            print(f"      {problem}")
        failures.extend(f"{region.code}: {problem}" for problem in problems)
        if args.overlay:
            print(f"      {write_overlay(region, rows, report, args.overlay)}")

    if args.overlay:
        return 0

    if failures:
        print(f"\n{len(failures)}건이 걸렸습니다.")
        return 1

    source = render_dart(masks)
    if args.check:
        current = OUT_PATH.read_text(encoding="utf-8") if OUT_PATH.exists() else ""
        if current != source:
            print(f"\n{OUT_PATH.name}가 원화와 어긋납니다. 생성기를 다시 도세요.")
            return 1
        print(f"\n{OUT_PATH.name}가 원화와 맞습니다.")
        return 0

    OUT_PATH.write_text(source, encoding="utf-8")
    print(f"\n{OUT_PATH.relative_to(ROOT)} 를 다시 썼습니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
