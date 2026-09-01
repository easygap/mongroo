"""생성한 걷기 그림을 `import_expedition_walker.py`가 받는 띠로 다듬는다.

`import_expedition_walker.py`는 방향마다 **288×120 띠**를 받는다. 그런데 이미지
생성이 내놓는 것은 1536×1024처럼 큰 판이고, 두 가지가 늘 어긋난다.

* **투명 배경을 그려서 준다.** 알파를 비우는 대신 회색 격자무늬를 *픽셀로*
  칠해 놓는다. 알파는 전부 255다. 그대로 구우면 캐릭터 뒤에 체크무늬가 박힌다.
* **크기와 자리가 매번 다르다.** 방향마다 판 크기도 캐릭터 키도 달라서, 그냥
  줄이면 아래를 볼 때와 옆을 볼 때 캐릭터 키가 달라진다.

그래서 여기서 두 가지를 한다.

1. 가장자리에서 물을 채우듯 번지며 배경색만 지운다. 색으로 한 번에 지우면
   얼굴의 밝은 색까지 같이 날아간다 — 얼굴은 어두운 선으로 둘러싸여 있으므로
   가장자리에서 번져 들어가는 방식은 안전하다.
2. **키를 맞춰** 줄인다. 방향마다 캐릭터의 알파 상자 높이를 재서 같은 키가
   되도록 각각 다른 배율을 준다. 그래야 걸을 때 방향을 바꿔도 커졌다 작아지지
   않는다.

사용법:
    python prepare_walker_strip.py --down 아래.png --left 왼쪽.png \
        --right 오른쪽.png --up 위.png --out-dir <폴더>

나온 네 장을 그대로 넘긴다:
    python import_expedition_walker.py --strips <폴더>/walk-down.png ... --species ninja-pot
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover
    print("Pillow가 필요합니다: pip install Pillow")
    raise SystemExit(1)

CELL_W, CELL_H = 96, 120
COLUMNS = 3

#: 칸 안에서 캐릭터가 차지할 키. 위아래로 여백이 남아야 한다 —
#: `import_expedition_walker.py`의 verify가 위아래로 잘린 칸을 거부한다.
FIGURE_H = 106
BOTTOM_PAD = 6

#: 배경으로 볼 색의 허용 오차. 체크무늬는 두 가지 밝은 회색이라 넉넉해도 된다.
TOLERANCE = 26


def _close(a: tuple[int, ...], b: tuple[int, ...]) -> bool:
    return all(abs(a[i] - b[i]) <= TOLERANCE for i in range(3))


def strip_background(image: Image.Image) -> Image.Image:
    """가장자리에서 번지며 배경을 지운다."""

    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()

    # 네 귀퉁이의 색을 배경 후보로 삼는다. 체크무늬라 두 색이 나온다.
    seeds: list[tuple[int, int, int, int]] = []
    for x, y in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)):
        colour = pixels[x, y]
        if not any(_close(colour, known) for known in seeds):
            seeds.append(colour)

    seen = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        for y in (0, height - 1):
            queue.append((x, y))
    for y in range(height):
        for x in (0, width - 1):
            queue.append((x, y))

    while queue:
        x, y = queue.popleft()
        index = y * width + x
        if seen[index]:
            continue
        seen[index] = 1
        colour = pixels[x, y]
        if not any(_close(colour, known) for known in seeds):
            continue
        pixels[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < width and 0 <= ny < height and not seen[ny * width + nx]:
                queue.append((nx, ny))
    return image


def _opaque_box(image: Image.Image) -> tuple[int, int, int, int]:
    box = image.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if box is None:
        raise SystemExit("배경을 지우고 나니 아무것도 남지 않았습니다.")
    return box


def _premultiplied(image: Image.Image) -> Image.Image:
    """알파를 색에 곱해 둔다.

    PIL은 줄일 때 알파를 곱하지 않으므로, 투명한 자리의 색이 가장자리로 번져
    후광이 생긴다. 배경을 지운 뒤에도 그 자리에는 지워진 배경색이 남아 있어서
    특히 티가 난다.
    """

    red, green, blue, alpha = image.split()
    return Image.merge(
        "RGBA",
        (
            ImageChops.multiply(red, alpha),
            ImageChops.multiply(green, alpha),
            ImageChops.multiply(blue, alpha),
            alpha,
        ),
    )


def _straight(image: Image.Image) -> Image.Image:
    """곱해 둔 알파를 되돌린다."""

    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (
                    min(255, red * 255 // alpha),
                    min(255, green * 255 // alpha),
                    min(255, blue * 255 // alpha),
                    alpha,
                )
    return image


def shrink(image: Image.Image, size: tuple[int, int], stages: int = 3) -> Image.Image:
    """큰 판을 도트 크기로 줄인다.

    한 번에 줄이면 안 된다. 1536픽셀짜리 그림을 180픽셀로 곧장 줄이면 원본의
    자수·머리카락 같은 잔무늬가 픽셀마다 튀는 값으로 남고, 그건 도트가 아니라
    노이즈다. `import_expedition_walker.py`의 자글거림 검사가 정확히 그걸
    잡는다 — 실제로 마법사 시트가 0.238로 걸렸다.

    그래서 여러 번에 나눠 줄인다. 단계마다 이웃 화소를 평균 내므로 잔무늬가
    차곡차곡 뭉개지고, 굽는 쪽(24칸 격자)이 받는 그림이 깨끗해진다. 같은
    그림이 0.238에서 0.146으로 내려간다.

    기본 세 단계로 대부분 통과하지만, 자수가 촘촘한 옷은 한 단계가 더 필요하다
    (`냉미남 로제온`이 0.168로 걸려 네 단계에서 0.152가 됐다). 검사를 느슨하게
    하는 대신 **통과하는 가장 적은 단계**를 쓴다 — 더 뭉개면 도트가 흐려진다.
    """

    work = _premultiplied(image)
    width, height = work.size
    target_w, target_h = size
    for step in range(stages - 1, 0, -1):
        ratio = (step + 1) / stages * .5
        work = work.resize(
            (
                max(1, round(target_w + (width - target_w) * ratio)),
                max(1, round(target_h + (height - target_h) * ratio)),
            ),
            Image.Resampling.BILINEAR,
        )
    return _straight(work.resize(size, Image.Resampling.BILINEAR))


def to_strip(image: Image.Image, scale: float, stages: int) -> Image.Image:
    """한 판을 288×120 띠로 만든다."""

    width, height = image.size
    scaled = shrink(
        image,
        (max(1, round(width * scale)), max(1, round(height * scale))),
        stages,
    )
    column_width = scaled.width / COLUMNS
    strip = Image.new("RGBA", (COLUMNS * CELL_W, CELL_H), (0, 0, 0, 0))
    for index in range(COLUMNS):
        cell = scaled.crop(
            (round(index * column_width), 0, round((index + 1) * column_width), scaled.height)
        )
        box = _opaque_box(cell)
        figure = cell.crop(box)
        if figure.width > CELL_W:
            # 옆모습에서 망토나 꼬리가 길게 뻗으면 칸을 넘길 수 있다. 그때만 더 줄인다.
            figure = shrink(
                figure,
                (CELL_W, max(1, round(figure.height * CELL_W / figure.width))),
                stages,
            )
        strip.paste(
            figure,
            (
                index * CELL_W + (CELL_W - figure.width) // 2,
                CELL_H - BOTTOM_PAD - figure.height,
            ),
            figure,
        )
    return strip


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("down", "left", "right", "up"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument(
        "--mirror-right",
        action="store_true",
        help=(
            "오른쪽 띠를 왼쪽 띠를 뒤집어 만든다. 네발 짐승처럼 좌우가 거의 "
            "대칭인 캐릭터에서 생성이 오른쪽을 못 그릴 때 쓴다."
        ),
    )
    parser.add_argument(
        "--smooth",
        type=int,
        default=3,
        help="줄이는 단계 수. 자글거림 검사에 걸리면 하나씩 올린다(기본 3).",
    )
    args = parser.parse_args()

    sources = {
        name: strip_background(Image.open(getattr(args, name)))
        for name in ("down", "left", "right", "up")
    }

    # 네 방향의 키를 하나로 맞춘다. 방향마다 따로 맞추면 걸음 중에 캐릭터가
    # 커졌다 작아진다.
    scales = {}
    for name, image in sources.items():
        box = _opaque_box(image)
        scales[name] = FIGURE_H / (box[3] - box[1])

    args.out_dir.mkdir(parents=True, exist_ok=True)
    strips = {
        name: to_strip(image, scales[name], args.smooth)
        for name, image in sources.items()
    }
    if args.mirror_right:
        # **칸마다** 뒤집는다. 띠를 통째로 뒤집으면 프레임 순서까지 거꾸로 돼서
        # 왼발과 오른발이 바뀐다.
        left = strips["left"]
        right = Image.new("RGBA", left.size, (0, 0, 0, 0))
        for index in range(COLUMNS):
            cell = left.crop(
                (index * CELL_W, 0, (index + 1) * CELL_W, CELL_H)
            ).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            right.paste(cell, (index * CELL_W, 0), cell)
        strips["right"] = right

    for name, strip in strips.items():
        out = args.out_dir / f"walk-{name}.png"
        strip.save(out)
        print(f"{out} {strip.size}")


if __name__ == "__main__":
    main()
