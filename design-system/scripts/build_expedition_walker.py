"""걷기 시트를 코드로 그린다. **지금은 대체본이다.**

한때 이 스크립트가 런타임 자산을 직접 만들었다. 지금은 아니다. 실제로 앱에
들어가는 `expedition-walker-v1.png`는 방향별로 뽑은 그림 넉 장을
`import_expedition_walker.py`가 검수하고 구워서 만든다.

바꾼 이유는 게임 배율에서 갈렸다. 여기서 나온 시트는 얼굴과 비례가 더 예쁜데,
옆·뒤 세 방향이 전부 `큰 흰 머리`라 방향이 구분되지 않았고 다리가 없어 걸음이
미끄러지는 것처럼 보였다. 방향이 안 읽히면 `바라보는 칸의 물건에만 말을 건다`는
규칙이 근거를 잃는다.

그래도 지우지 않는다. 규격(3프레임 × 4방향, 96×120칸, 288×480 시트, 색 스물)을
코드로 못 박아 두는 값이 있고, 그림을 다시 뽑기 전까지 기댈 곳이 필요하다.
산출물은 런타임이 아니라 `design-system/concepts/expedition-walker-v2/reference/`로
간다 — 여기서 런타임을 덮으면 뽑아 온 그림이 말없이 사라진다.

사용법:
    python build_expedition_walker.py
    python build_expedition_walker.py --check
"""

from __future__ import annotations

import argparse
import sys
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    print("Pillow is required: pip install Pillow")
    raise SystemExit(1)


ROOT = Path(__file__).resolve().parents[2]
# 런타임이 아니라 참고본 자리다. 실제 자산은 뽑아 온 그림에서 굽는다.
OUT_PATH = (
    ROOT
    / "design-system"
    / "concepts"
    / "expedition-walker-v2"
    / "reference"
    / "builder-sheet.png"
)

CELL_W, CELL_H = 96, 120
COLUMNS, ROWS = 3, 4
FACINGS = ("down", "left", "right", "up")

# A 3x logical pixel gives the requested coarse, hard-edged DS-era look while
# still allowing the animation's head group to bob by one physical pixel.
PIXEL = 3
LOGICAL_W, LOGICAL_H = CELL_W // PIXEL, CELL_H // PIXEL
GROUND_Y = CELL_H - 12

# Twenty opaque colours in total. Each material has at most one highlight,
# one base, and one shadow tone; LINE is shared by eyes and the silhouette.
LINE = (54, 38, 29, 255)
SKIN_LIGHT = (255, 242, 199, 255)
SKIN = (244, 222, 174, 255)
SKIN_DARK = (216, 185, 132, 255)
BLUSH = (235, 143, 133, 255)
LEAF_LIGHT = (159, 202, 88, 255)
LEAF = (104, 157, 59, 255)
LEAF_DARK = (57, 105, 46, 255)
CLOAK_LIGHT = (117, 148, 77, 255)
CLOAK = (78, 113, 61, 255)
CLOAK_DARK = (49, 78, 48, 255)
POT_LIGHT = (214, 130, 73, 255)
POT = (174, 86, 51, 255)
POT_DARK = (116, 55, 39, 255)
BOOT_LIGHT = (66, 102, 59, 255)
BOOT = (42, 75, 48, 255)
BOOT_DARK = (29, 49, 37, 255)
BAG_LIGHT = (224, 174, 99, 255)
BAG = (184, 126, 67, 255)
BAG_DARK = (119, 76, 43, 255)

OPAQUE_PALETTE = {
    LINE,
    SKIN_LIGHT,
    SKIN,
    SKIN_DARK,
    BLUSH,
    LEAF_LIGHT,
    LEAF,
    LEAF_DARK,
    CLOAK_LIGHT,
    CLOAK,
    CLOAK_DARK,
    POT_LIGHT,
    POT,
    POT_DARK,
    BOOT_LIGHT,
    BOOT,
    BOOT_DARK,
    BAG_LIGHT,
    BAG,
    BAG_DARK,
}


def _canvas() -> Image.Image:
    return Image.new("RGBA", (LOGICAL_W, LOGICAL_H), (0, 0, 0, 0))


def _boot(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], toe: str) -> None:
    """Draw one sturdy boot with a one-logical-pixel outline."""

    left, top, right, bottom = box
    points = [(left, top), (right - 1, top)]
    if toe == "left":
        points.extend(
            [
                (right, bottom - 1),
                (right - 1, bottom),
                (left, bottom),
                (left - 1, bottom - 1),
            ]
        )
    elif toe == "right":
        points.extend(
            [
                (right + 1, bottom - 1),
                (right, bottom),
                (left + 1, bottom),
                (left, bottom - 1),
            ]
        )
    else:
        points.extend([(right, bottom), (left, bottom)])
    draw.polygon(points, fill=LINE)
    inner_left = left if toe == "left" else left + 1
    inner_right = right - 1 if toe == "right" else right
    draw.rectangle((inner_left, top + 1, inner_right, bottom - 1), fill=BOOT)
    draw.point((inner_left, top + 1), fill=BOOT_LIGHT)
    draw.point((inner_right, bottom - 1), fill=BOOT_DARK)


def _draw_boots(draw: ImageDraw.ImageDraw, facing: str, frame: int) -> None:
    """Draw independent left/stand/right-foot poses on the shared y=108 line."""

    if facing == "down":
        # Anatomical left is screen-right in the front view.
        poses = {
            0: (((18, 32, 22, 35), "right"), ((10, 32, 13, 34), "left")),
            1: (((18, 32, 22, 35), "right"), ((9, 32, 13, 35), "left")),
            2: (((18, 32, 21, 34), "right"), ((9, 32, 13, 35), "left")),
        }
    elif facing == "up":
        # Anatomical left is screen-left in the back view.
        poses = {
            0: (((9, 32, 13, 35), "left"), ((18, 32, 21, 34), "right")),
            1: (((9, 32, 13, 35), "left"), ((18, 32, 22, 35), "right")),
            2: (((10, 32, 13, 34), "left"), ((18, 32, 22, 35), "right")),
        }
    elif facing == "left":
        # The near (left) foot and far (right) foot are authored separately.
        poses = {
            0: (((7, 33, 13, 35), "left"), ((16, 32, 19, 34), "right")),
            1: (((10, 33, 15, 35), "left"), ((16, 32, 20, 35), "right")),
            2: (((10, 32, 14, 34), "left"), ((17, 33, 23, 35), "right")),
        }
    else:  # right; deliberately not a mirrored left profile
        poses = {
            0: (((18, 33, 24, 35), "right"), ((12, 32, 15, 34), "left")),
            1: (((17, 33, 22, 35), "right"), ((12, 32, 16, 35), "left")),
            2: (((17, 32, 21, 34), "right"), ((8, 33, 14, 35), "left")),
        }

    for box, toe in poses[frame]:
        _boot(draw, box, toe)


def _draw_pot(draw: ImageDraw.ImageDraw, facing: str) -> None:
    """Draw the terracotta, flower-pot-shaped torso."""

    if facing in {"down", "up"}:
        draw.polygon([(8, 27), (23, 27), (21, 34), (10, 34)], fill=LINE)
        draw.polygon([(9, 29), (22, 29), (20, 33), (11, 33)], fill=POT)
        draw.rectangle((8, 27, 23, 30), fill=POT, outline=LINE, width=1)
        draw.rectangle((9, 28, 14, 28), fill=POT_LIGHT)
        draw.rectangle((21, 28, 22, 29), fill=POT_DARK)
        draw.polygon([(19, 30), (21, 30), (20, 33), (18, 33)], fill=POT_DARK)
    elif facing == "left":
        draw.polygon([(8, 27), (23, 27), (20, 34), (9, 34)], fill=LINE)
        draw.polygon([(9, 29), (22, 29), (19, 33), (10, 33)], fill=POT)
        draw.rectangle((8, 27, 22, 30), fill=POT, outline=LINE, width=1)
        draw.rectangle((9, 28, 13, 28), fill=POT_LIGHT)
        draw.polygon([(19, 29), (21, 29), (19, 33), (17, 33)], fill=POT_DARK)
    else:  # right, independently shaped and lit from upper-left
        draw.polygon([(9, 27), (24, 27), (23, 34), (12, 34)], fill=LINE)
        draw.polygon([(10, 29), (23, 29), (22, 33), (13, 33)], fill=POT)
        draw.rectangle((10, 27, 24, 30), fill=POT, outline=LINE, width=1)
        draw.rectangle((11, 28, 15, 28), fill=POT_LIGHT)
        draw.polygon([(21, 29), (23, 29), (22, 33), (20, 33)], fill=POT_DARK)


def _draw_cloak(draw: ImageDraw.ImageDraw, facing: str) -> None:
    """Draw the moss-green cloak and hood mass behind the head."""

    if facing == "down":
        draw.polygon(
            [(6, 21), (25, 21), (27, 27), (23, 31), (8, 31), (4, 27)],
            fill=LINE,
        )
        draw.polygon(
            [(7, 22), (24, 22), (25, 27), (22, 29), (9, 29), (6, 27)],
            fill=CLOAK,
        )
        draw.polygon(
            [(7, 23), (10, 22), (9, 28), (7, 28), (6, 26)],
            fill=CLOAK_LIGHT,
        )
        draw.polygon(
            [(22, 22), (24, 23), (25, 27), (22, 29), (20, 29)],
            fill=CLOAK_DARK,
        )
    elif facing == "left":
        draw.polygon(
            [(7, 21), (23, 21), (26, 26), (22, 31), (7, 30), (5, 26)],
            fill=LINE,
        )
        draw.polygon(
            [(8, 22), (22, 22), (24, 26), (21, 29), (8, 29), (7, 26)],
            fill=CLOAK,
        )
        draw.polygon(
            [(8, 23), (11, 22), (10, 28), (8, 28), (7, 26)],
            fill=CLOAK_LIGHT,
        )
        draw.polygon(
            [(20, 22), (22, 23), (24, 26), (21, 29), (19, 29)],
            fill=CLOAK_DARK,
        )
    elif facing == "right":
        draw.polygon(
            [(8, 21), (24, 21), (27, 26), (25, 30), (10, 31), (6, 26)],
            fill=LINE,
        )
        draw.polygon(
            [(9, 22), (23, 22), (25, 26), (24, 29), (11, 29), (8, 26)],
            fill=CLOAK,
        )
        draw.polygon(
            [(9, 23), (12, 22), (11, 28), (9, 28), (8, 26)],
            fill=CLOAK_LIGHT,
        )
        draw.polygon(
            [(21, 22), (23, 23), (25, 26), (24, 29), (21, 29)],
            fill=CLOAK_DARK,
        )
    else:
        draw.polygon(
            [(6, 21), (25, 21), (27, 27), (23, 32), (8, 32), (4, 27)],
            fill=LINE,
        )
        draw.polygon(
            [(7, 22), (24, 22), (25, 27), (22, 30), (9, 30), (6, 27)],
            fill=CLOAK,
        )
        draw.polygon(
            [(7, 23), (10, 22), (9, 29), (7, 28), (6, 26)],
            fill=CLOAK_LIGHT,
        )
        draw.polygon(
            [(21, 22), (24, 23), (25, 27), (22, 30), (19, 30)],
            fill=CLOAK_DARK,
        )


def _draw_satchel(draw: ImageDraw.ImageDraw, facing: str) -> None:
    """Place the bag on the character's anatomical left hip."""

    if facing == "right":
        return  # Anatomical left is the far side and is completely hidden.

    if facing == "down":
        # Front view: anatomical left is screen-right.
        draw.line((10, 22, 21, 30), fill=LINE, width=2)
        draw.line((10, 22, 21, 30), fill=BAG_DARK, width=1)
        box = (19, 27, 25, 33)
    elif facing == "left":
        # The left hip is the near side in this requested profile convention.
        draw.line((20, 22, 12, 30), fill=LINE, width=2)
        draw.line((20, 22, 12, 30), fill=BAG_DARK, width=1)
        box = (8, 27, 15, 33)
    else:  # back: anatomical left is screen-left
        draw.line((21, 22, 11, 30), fill=LINE, width=2)
        draw.line((21, 22, 11, 30), fill=BAG_DARK, width=1)
        box = (7, 27, 14, 33)

    draw.rounded_rectangle(box, radius=1, fill=BAG, outline=LINE, width=1)
    left, top, right, bottom = box
    draw.rectangle((left + 1, top + 1, right - 2, top + 1), fill=BAG_LIGHT)
    draw.rectangle((right - 1, top + 2, right - 1, bottom - 1), fill=BAG_DARK)
    draw.point(((left + right) // 2, top + 2), fill=BAG_LIGHT)


def _draw_collar(draw: ImageDraw.ImageDraw, facing: str) -> None:
    """Foreground collar makes the cloak read as hooded without soft shading."""

    if facing == "down":
        draw.polygon(
            [(6, 21), (10, 20), (15, 23), (21, 20), (25, 21), (22, 25), (9, 25)],
            fill=LINE,
        )
        draw.polygon(
            [(8, 22), (10, 21), (15, 24), (21, 21), (23, 22), (21, 24), (10, 24)],
            fill=CLOAK,
        )
        draw.point((9, 22), fill=CLOAK_LIGHT)
        draw.point((21, 23), fill=CLOAK_DARK)
    elif facing == "left":
        draw.polygon(
            [(6, 21), (10, 20), (22, 20), (25, 22), (22, 25), (8, 25)],
            fill=LINE,
        )
        draw.polygon(
            [(8, 22), (11, 21), (21, 21), (23, 22), (21, 24), (9, 24)],
            fill=CLOAK,
        )
        draw.point((9, 22), fill=CLOAK_LIGHT)
        draw.point((21, 23), fill=CLOAK_DARK)
    elif facing == "right":
        draw.polygon(
            [(7, 22), (10, 20), (22, 20), (26, 21), (24, 25), (9, 25)],
            fill=LINE,
        )
        draw.polygon(
            [(9, 22), (11, 21), (21, 21), (24, 22), (22, 24), (10, 24)],
            fill=CLOAK,
        )
        draw.point((10, 22), fill=CLOAK_LIGHT)
        draw.point((22, 23), fill=CLOAK_DARK)
    else:
        # Back hood rises over the nape; no face is exposed.
        draw.polygon(
            [(6, 20), (10, 18), (21, 18), (25, 20), (24, 25), (8, 25)],
            fill=LINE,
        )
        draw.polygon(
            [(8, 21), (11, 19), (20, 19), (23, 21), (22, 24), (10, 24)],
            fill=CLOAK,
        )
        draw.polygon(
            [(9, 21), (11, 20), (13, 20), (12, 23), (10, 23)],
            fill=CLOAK_LIGHT,
        )
        draw.polygon(
            [(20, 20), (22, 21), (21, 23), (19, 23)],
            fill=CLOAK_DARK,
        )


def _draw_leaves(draw: ImageDraw.ImageDraw, facing: str) -> None:
    """Draw exactly three leaves, all comfortably inside the cell."""

    # Direction-specific silhouettes are separately authored, not mirrored.
    if facing == "left":
        leaves = (
            (
                [(15, 10), (11, 9), (7, 6), (11, 6), (16, 9)],
                [(14, 9), (11, 8), (9, 7), (11, 7)],
                (10, 7),
            ),
            (
                [(15, 9), (13, 5), (15, 2), (17, 5), (16, 9)],
                [(15, 8), (14, 5), (15, 3), (16, 5)],
                (15, 4),
            ),
            (
                [(17, 10), (20, 7), (24, 7), (22, 10), (17, 11)],
                [(18, 9), (20, 8), (22, 8), (21, 9)],
                (20, 8),
            ),
        )
    elif facing == "right":
        leaves = (
            (
                [(14, 10), (10, 8), (7, 7), (9, 10), (15, 11)],
                [(13, 9), (10, 9), (9, 8), (11, 8)],
                (10, 8),
            ),
            (
                [(15, 9), (14, 5), (16, 2), (18, 5), (17, 9)],
                [(16, 8), (15, 5), (16, 3), (17, 5)],
                (16, 4),
            ),
            (
                [(17, 10), (21, 9), (25, 6), (24, 10), (18, 11)],
                [(18, 9), (21, 9), (23, 8), (23, 9)],
                (22, 8),
            ),
        )
    else:
        leaves = (
            (
                [(14, 10), (10, 9), (6, 6), (10, 6), (15, 9)],
                [(13, 9), (10, 8), (8, 7), (10, 7)],
                (9, 7),
            ),
            (
                [(15, 9), (13, 5), (15, 2), (17, 5), (16, 9)],
                [(15, 8), (14, 5), (15, 3), (16, 5)],
                (15, 4),
            ),
            (
                [(17, 10), (21, 8), (25, 7), (23, 10), (17, 11)],
                [(18, 9), (21, 9), (23, 8), (22, 9)],
                (21, 8),
            ),
        )

    for outline, inner, highlight in leaves:
        draw.polygon(outline, fill=LINE)
        draw.polygon(inner, fill=LEAF)
        draw.point(highlight, fill=LEAF_LIGHT)
    # A shared lower-right shadow anchors the leaves to the crown.
    draw.rectangle((16, 8, 17, 9), fill=LEAF_DARK)


def _draw_head(draw: ImageDraw.ImageDraw, facing: str) -> None:
    _draw_leaves(draw, facing)

    if facing == "down":
        draw.ellipse((7, 8, 24, 24), fill=LINE)
        draw.ellipse((8, 9, 23, 23), fill=SKIN)
        draw.polygon([(9, 11), (11, 9), (16, 9), (14, 11)], fill=SKIN_LIGHT)
        draw.polygon(
            [(21, 12), (23, 14), (23, 20), (21, 22), (20, 22)],
            fill=SKIN_DARK,
        )
        draw.rectangle((11, 16, 12, 18), fill=LINE)
        draw.rectangle((19, 16, 20, 18), fill=LINE)
        draw.point((9, 19), fill=BLUSH)
        draw.point((22, 19), fill=BLUSH)
        draw.point((16, 20), fill=LINE)
    elif facing == "left":
        # Independently drawn left profile: nose and visible left cheek point left.
        draw.ellipse((8, 8, 24, 24), fill=LINE)
        draw.rectangle((6, 16, 10, 20), fill=LINE)
        draw.ellipse((9, 9, 23, 23), fill=SKIN)
        draw.rectangle((7, 17, 10, 19), fill=SKIN)
        draw.polygon([(10, 11), (12, 9), (16, 9), (14, 11)], fill=SKIN_LIGHT)
        draw.polygon([(21, 12), (23, 14), (23, 21), (21, 22)], fill=SKIN_DARK)
        draw.rectangle((10, 16, 11, 18), fill=LINE)
        draw.point((9, 19), fill=BLUSH)
    elif facing == "right":
        # Independently drawn right profile; lighting remains upper-left.
        draw.ellipse((7, 8, 23, 24), fill=LINE)
        draw.rectangle((21, 16, 25, 20), fill=LINE)
        draw.ellipse((8, 9, 22, 23), fill=SKIN)
        draw.rectangle((21, 17, 24, 19), fill=SKIN)
        draw.polygon([(9, 11), (11, 9), (15, 9), (13, 11)], fill=SKIN_LIGHT)
        draw.polygon([(20, 12), (22, 14), (22, 21), (20, 22)], fill=SKIN_DARK)
        draw.rectangle((20, 16, 21, 18), fill=LINE)
        draw.point((22, 19), fill=BLUSH)
    else:
        draw.ellipse((7, 8, 24, 24), fill=LINE)
        draw.ellipse((8, 9, 23, 23), fill=SKIN)
        draw.polygon([(9, 11), (11, 9), (16, 9), (14, 11)], fill=SKIN_LIGHT)
        draw.polygon(
            [(21, 12), (23, 14), (23, 21), (21, 22), (20, 22)],
            fill=SKIN_DARK,
        )
        # Intentionally no eyes, blush, or mouth in the back view.


def _cell(facing: str, frame: int) -> Image.Image:
    body = _canvas()
    body_draw = ImageDraw.Draw(body)
    _draw_boots(body_draw, facing, frame)
    _draw_pot(body_draw, facing)
    _draw_cloak(body_draw, facing)
    _draw_satchel(body_draw, facing)

    head = _canvas()
    _draw_head(ImageDraw.Draw(head), facing)

    collar = _canvas()
    _draw_collar(ImageDraw.Draw(collar), facing)

    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    nearest = Image.Resampling.NEAREST
    cell.alpha_composite(body.resize((CELL_W, CELL_H), nearest))

    # Columns 1 and 3: the whole head-and-leaves group is exactly one final
    # pixel lower than the standing frame. Nothing else bobs.
    head_bob = 0 if frame == 1 else 1
    cell.alpha_composite(head.resize((CELL_W, CELL_H), nearest), dest=(0, head_bob))
    cell.alpha_composite(collar.resize((CELL_W, CELL_H), nearest))
    return cell


def build() -> Image.Image:
    sheet = Image.new(
        "RGBA", (COLUMNS * CELL_W, ROWS * CELL_H), (0, 0, 0, 0)
    )
    for row, facing in enumerate(FACINGS):
        for frame in range(COLUMNS):
            sheet.alpha_composite(
                _cell(facing, frame), (frame * CELL_W, row * CELL_H)
            )
    _validate(sheet)
    return sheet


def _validate(sheet: Image.Image) -> None:
    assert sheet.mode == "RGBA"
    assert sheet.size == (288, 480)

    colors = {pixel for pixel in sheet.get_flattened_data() if pixel[3]}
    assert colors <= OPAQUE_PALETTE
    assert len(colors) <= 24
    assert {pixel[3] for pixel in sheet.get_flattened_data()} <= {0, 255}

    for row in range(ROWS):
        for column in range(COLUMNS):
            cell = sheet.crop(
                (
                    column * CELL_W,
                    row * CELL_H,
                    (column + 1) * CELL_W,
                    (row + 1) * CELL_H,
                )
            )
            box = cell.getchannel("A").getbbox()
            assert box is not None
            # Leaves are at least four pixels below the top and every frame's
            # lowest opaque pixel is y=107, leaving exactly 12 transparent rows.
            assert box[1] >= 4
            assert box[3] == GROUND_Y
            assert box[0] > 0 and box[2] < CELL_W


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    sheet = build()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    if args.check:
        buffer = BytesIO()
        sheet.save(buffer, "PNG", optimize=False)
        if not OUT_PATH.exists() or OUT_PATH.read_bytes() != buffer.getvalue():
            print(f"x {OUT_PATH.name} differs from the deterministic builder")
            return 1
        print(f"  {OUT_PATH.name} matches")
        return 0

    sheet.save(OUT_PATH, "PNG", optimize=False)
    print(
        f"  {OUT_PATH.name}  {sheet.width}x{sheet.height}  "
        f"{len(OPAQUE_PALETTE)} colours  {OUT_PATH.stat().st_size // 1024}KB"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
