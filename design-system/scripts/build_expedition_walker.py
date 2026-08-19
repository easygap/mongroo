"""던전을 걷는 캐릭터의 4방향 걷기 시트를 만든다.

지금까지 월드 안의 플레이어는 지도에서 쓰던 파티 토큰(`_PartyTrailMarker`)을
그대로 얹은 것이었다. 한 장짜리라 위로 걸어도 정면을 보고, 걷는 동작이 없다.
포켓몬·탐험대 계열이 주는 인상의 절반이 여기서 갈린다.

여기서 만드는 그림은 **자리표시**다. 진짜 도트는 ImageGen으로 뽑아 같은 규격에
갈아 끼운다(`design-system/ADVENTURE_ASSET_PROMPTS.md`의 걷기 스프라이트 항목).
그래도 지금 만들어 두는 이유는 규격을 코드가 아니라 파일로 못 박기 위해서다.

## 규격

* 한 칸 96×120. 아틀라스 타일이 96이라 폭을 맞추고, 키는 타일보다 높다 —
  머리가 타일 위로 올라와야 바닥에 **서 있는** 것으로 보인다.
* 가로 3칸 = 걷기 3프레임(왼발·선 자세·오른발). `1-2-3-2`로 돌린다.
* 세로 4칸 = 아래·왼쪽·오른쪽·위. 오른쪽을 왼쪽의 반전으로 때우지 않는다 —
  어깨에 멘 가방이 반대로 붙는다.
* 시트 288×480, 배경 투명.

사용법:
    python build_expedition_walker.py
    python build_expedition_walker.py --check
"""

from __future__ import annotations

import argparse
import math
import sys
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover
    print("Pillow가 필요합니다: pip install Pillow")
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = (
    ROOT / "app" / "assets" / "adventure" / "overworld" / "expedition-walker-v1.png"
)

CELL_W, CELL_H = 96, 120
COLUMNS, ROWS = 3, 4
#: 줄 순서. 다트의 `_WalkFacing`과 같아야 한다.
FACINGS = ("down", "left", "right", "up")

SKIN = (247, 226, 200)
CLOAK = (108, 138, 96)
CLOAK_DARK = (74, 100, 68)
POT = (186, 112, 68)
POT_DARK = (140, 80, 48)
LEAF = (150, 200, 110)
LINE = (48, 38, 34)
BAG = (150, 112, 70)


def _shade(color, amount: float):
    if amount >= 0:
        return tuple(round(c + (255 - c) * amount) for c in color[:3])
    return tuple(round(c * (1 + amount)) for c in color[:3])


def _cell(facing: str, frame: int) -> Image.Image:
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(cell)
    mid = CELL_W // 2
    # 세로 배분: 잎 4~28, 머리 26~62, 몸통 58~88, 다리 74~106.
    # 앞 판은 머리를 22에 두어 잎이 칸 위로 잘려 나갔다 — 싹이 몽그루의
    # 상징인데 그게 안 보였다.
    ground = CELL_H - 12

    # 걸음마다 몸이 오르내리고 두 발이 번갈아 나간다.
    bob = 0 if frame == 1 else -3
    swing = {0: -9, 1: 0, 2: 9}[frame]

    # 발밑 그림자. 캐릭터가 떠 보이지 않게 먼저 깐다.
    shadow = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        (mid - 26, ground - 9, mid + 26, ground + 9), fill=(0, 0, 0, 110)
    )
    cell.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(3)))

    # 다리.
    for side, offset in ((-1, swing), (1, -swing)):
        x = mid + side * 13 + offset // 2
        draw.rounded_rectangle(
            (x - 8, ground - 34 + bob, x + 8, ground - 2),
            radius=7,
            fill=_shade(CLOAK_DARK, -0.1),
            outline=LINE,
            width=2,
        )

    # 화분 몸통.
    body_top = ground - 50 + bob
    draw.polygon(
        [
            (mid - 26, body_top + 10),
            (mid + 26, body_top + 10),
            (mid + 20, ground - 20),
            (mid - 20, ground - 20),
        ],
        fill=POT,
        outline=LINE,
    )
    draw.rectangle(
        (mid - 29, body_top, mid + 29, body_top + 12),
        fill=_shade(POT, 0.18),
        outline=LINE,
        width=2,
    )
    # 왼쪽 위에서 빛이 온다. 오른쪽에 그늘을 넣어 둥글게 보이게 한다.
    draw.polygon(
        [
            (mid + 8, body_top + 12),
            (mid + 26, body_top + 12),
            (mid + 20, ground - 21),
            (mid + 6, ground - 21),
        ],
        fill=_shade(POT_DARK, -0.05),
    )

    # 망토. 방향마다 어깨선이 다르다.
    if facing == "up":
        draw.polygon(
            [
                (mid - 30, body_top + 4),
                (mid + 30, body_top + 4),
                (mid + 22, body_top + 40),
                (mid - 22, body_top + 40),
            ],
            fill=CLOAK,
            outline=LINE,
        )
    else:
        draw.polygon(
            [
                (mid - 30, body_top + 2),
                (mid + 30, body_top + 2),
                (mid + 24, body_top + 26),
                (mid - 24, body_top + 26),
            ],
            fill=CLOAK,
            outline=LINE,
        )

    # 가방. 옆·뒤에서만 보인다. 오른쪽을 반전으로 만들지 않는 이유가 이것이다.
    if facing == "left":
        draw.ellipse(
            (mid + 14, body_top + 16, mid + 34, body_top + 40),
            fill=BAG,
            outline=LINE,
            width=2,
        )
    elif facing == "right":
        draw.ellipse(
            (mid - 34, body_top + 16, mid - 14, body_top + 40),
            fill=BAG,
            outline=LINE,
            width=2,
        )
    elif facing == "up":
        draw.ellipse(
            (mid - 12, body_top + 14, mid + 12, body_top + 38),
            fill=BAG,
            outline=LINE,
            width=2,
        )

    # 머리.
    # 머리를 화분 아가리에 걸쳐 놓는다. 앞 판은 몸에서 22px 떠 있어 목이
    # 없는 게 아니라 머리가 공중에 뜬 것으로 보였다.
    head_y = body_top - 14
    draw.ellipse(
        (mid - 18, head_y - 18, mid + 18, head_y + 18),
        fill=SKIN,
        outline=LINE,
        width=2,
    )
    if facing != "up":
        eyes = {"down": (-7, 7), "left": (-10, -2), "right": (2, 10)}[facing]
        for dx in eyes:
            draw.ellipse(
                (mid + dx - 3, head_y - 2, mid + dx + 3, head_y + 5), fill=LINE
            )
        for dx in (-13, 11):
            draw.ellipse(
                (mid + dx - 4, head_y + 6, mid + dx + 4, head_y + 10),
                fill=(244, 176, 168),
            )

    # 잎 세 장. 걸을 때 살짝 흔들린다.
    for index in range(3):
        angle = -0.8 + index * 0.8 + swing * 0.012
        points = []
        # 길이는 칸 안에 들어오게 맞춘 값이다. 늘리면 다시 잘린다.
        for step in range(0, 22, 2):
            points.append(
                (
                    mid + math.sin(angle) * step,
                    head_y - 16 - math.cos(angle) * step,
                )
            )
        draw.line(points, fill=_shade(LEAF, -0.05), width=6, joint="curve")
        draw.line(points, fill=LEAF, width=3, joint="curve")

    return cell


# ── 도트 패스 ─────────────────────────────────────────────────────────────
# 아틀라스와 같은 격자·같은 방식으로 굽는다(`build_expedition_tile_atlas_v2.py`).
# 땅은 24칸 도트인데 캐릭터만 매끈하게 그리면 오려 붙인 것처럼 뜬다. 두 파일이
# 각자 굽는 것이 중복처럼 보이지만, 이 저장소의 빌드 스크립트는 저마다 혼자
# 돌아가는 것이 규칙이라 여기서도 그 규칙을 따른다.
DOT = 4
DOT_W, DOT_H = CELL_W // DOT, CELL_H // DOT
PALETTE_COLORS = 24


def _dot(cell: Image.Image) -> Image.Image:
    """한 칸을 24×30 도트로 낮춘다. 알파로 가중해 검은 후광을 막는다."""

    source = cell.load()
    low = Image.new("RGBA", (DOT_W, DOT_H))
    target = low.load()
    area = DOT * DOT
    for block_y in range(DOT_H):
        for block_x in range(DOT_W):
            red = green = blue = coverage = weight = 0
            for y in range(block_y * DOT, block_y * DOT + DOT):
                for x in range(block_x * DOT, block_x * DOT + DOT):
                    pixel_r, pixel_g, pixel_b, pixel_a = source[x, y]
                    coverage += pixel_a
                    weight += pixel_a
                    red += pixel_r * pixel_a
                    green += pixel_g * pixel_a
                    blue += pixel_b * pixel_a
            if weight == 0:
                target[block_x, block_y] = (0, 0, 0, 0)
                continue
            target[block_x, block_y] = (
                red // weight,
                green // weight,
                blue // weight,
                # 알파는 있거나 없거나. 반투명 가장자리는 최근접으로 키우면
                # 지저분한 테두리로 남는다.
                255 if coverage // area >= 128 else 0,
            )
    return low


def _palette(cells: list[Image.Image]) -> Image.Image:
    """시트 전체가 나눠 쓸 색. 네 방향이 같은 색이라야 한 사람으로 보인다."""

    pixels: list[tuple[int, int, int]] = []
    for cell in cells:
        read = cell.load()
        pixels.extend(
            read[x, y][:3]
            for y in range(cell.height)
            for x in range(cell.width)
            if read[x, y][3]
        )
    board = Image.new("RGB", (len(pixels), 1))
    board.putdata(pixels)
    return board.quantize(colors=PALETTE_COLORS, method=Image.Quantize.MEDIANCUT)


def build() -> Image.Image:
    grid = [
        [_dot(_cell(facing, frame)) for frame in range(COLUMNS)]
        for facing in FACINGS
    ]
    palette = _palette([cell for row in grid for cell in row])
    sheet = Image.new("RGBA", (COLUMNS * CELL_W, ROWS * CELL_H), (0, 0, 0, 0))
    for row, cells in enumerate(grid):
        for frame, low in enumerate(cells):
            alpha = low.getchannel("A")
            flat = low.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE)
            flat = flat.convert("RGB")
            flat.putalpha(alpha)
            sheet.paste(
                flat.resize((CELL_W, CELL_H), Image.Resampling.NEAREST),
                (frame * CELL_W, row * CELL_H),
            )
    return sheet


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    sheet = build()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    if args.check:
        buffer = BytesIO()
        sheet.save(buffer, "PNG")
        if not OUT_PATH.exists() or OUT_PATH.read_bytes() != buffer.getvalue():
            print(f"✗ {OUT_PATH.name}가 생성기와 어긋납니다")
            return 1
        print(f"  {OUT_PATH.name} 맞음")
        return 0

    sheet.save(OUT_PATH, "PNG")
    print(
        f"  {OUT_PATH.name}  {sheet.width}×{sheet.height}  "
        f"{OUT_PATH.stat().st_size // 1024}KB"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
