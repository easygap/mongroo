"""생성한 걷기 시트를 검수하고 앱 규격으로 들여온다.

지금 들어 있는 `expedition-walker-v1.png`는 `build_expedition_walker.py`가 도형을
겹쳐 만든 **자리표시**다. 진짜 도트를 뽑아 오면 이 스크립트로 갈아 끼운다.

받은 그림을 바로 넣지 않는다. 생성 이미지에서 반복해 나오는 결함이 있고, 그게
그대로 들어가면 화면에서만 티가 난다. 그래서 넣기 전에 수치로 잰다.

* **자글자글한 점묘.** 같은 면인데 픽셀마다 색이 튄다. 인접 픽셀의 밝기 차가 큰
  비율로 잡는다. 도트라면 한 칸이 여러 픽셀로 이어져 이 값이 낮다.
* **반투명 테두리.** 가장자리 알파가 어중간하면 최근접으로 키울 때 지저분한
  띠가 남는다. 알파는 0 아니면 255여야 한다.
* **색 수.** 아틀라스가 지역마다 서른두 색이라 캐릭터만 수천 색이면 뜬다.
* **칸 규격.** 12칸이 모두 채워져 있고 위아래로 잘리지 않아야 한다.

검사를 통과하면 아틀라스와 **같은 방식으로** 굽는다(24칸 격자, 알파 1비트,
팔레트 고정). 그래야 발밑과 캐릭터가 한 세계로 읽힌다.

사용법:
    python import_expedition_walker.py <받은시트.png>
    python import_expedition_walker.py <받은시트.png> --check   # 재지 않고 검사만
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("Pillow가 필요합니다: pip install Pillow")
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = (
    ROOT / "app" / "assets" / "adventure" / "overworld" / "expedition-walker-v1.png"
)

CELL_W, CELL_H = 96, 120
COLUMNS, ROWS = 3, 4
SHEET = (COLUMNS * CELL_W, ROWS * CELL_H)

#: 굽는 격자. `build_expedition_tile_atlas_v2.py`의 DOT과 같아야 한다.
DOT = 4
PALETTE_COLORS = 24

#: 검사 한계. 아틀라스 실측(고주파 0.07, 고립 점 0.0)에 맞춰 잡았다.
HIGH_FREQUENCY_LIMIT = 0.16
SPECK_LIMIT = 0.002


def _luma(pixel: tuple[int, int, int, int]) -> float:
    return pixel[0] * 0.2126 + pixel[1] * 0.7152 + pixel[2] * 0.0722


def measure(sheet: Image.Image) -> dict[str, float]:
    """자글거림과 튀는 점을 잰다. 아틀라스 검사와 같은 척도다."""

    read = sheet.load()
    width, height = sheet.size
    edges = high = centers = isolated = 0
    for y in range(height):
        for x in range(width):
            here = read[x, y]
            if here[3] < 224:
                continue
            for nx, ny in ((x + 1, y), (x, y + 1)):
                if nx >= width or ny >= height:
                    continue
                other = read[nx, ny]
                if other[3] < 224:
                    continue
                edges += 1
                if abs(_luma(here) - _luma(other)) >= 36:
                    high += 1
            if not (0 < x < width - 1 and 0 < y < height - 1):
                continue
            around = (
                read[x - 1, y],
                read[x + 1, y],
                read[x, y - 1],
                read[x, y + 1],
            )
            if any(pixel[3] < 224 for pixel in around):
                continue
            centers += 1
            values = [_luma(pixel) for pixel in around]
            if max(values) - min(values) <= 14 and abs(
                _luma(here) - sum(values) / 4
            ) >= 30:
                isolated += 1
    return {
        "high_frequency": high / max(1, edges),
        "speck": isolated / max(1, centers),
    }


def verify(sheet: Image.Image) -> list[str]:
    problems: list[str] = []
    if sheet.size != SHEET:
        problems.append(f"시트 크기가 {sheet.size}입니다. {SHEET}이어야 합니다")
        return problems
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
            if box is None:
                problems.append(f"{row}행 {column}칸이 비어 있습니다")
                continue
            if box[1] == 0 or box[3] == CELL_H:
                problems.append(f"{row}행 {column}칸이 위아래로 잘렸습니다 {box}")
    metrics = measure(sheet)
    if metrics["high_frequency"] > HIGH_FREQUENCY_LIMIT:
        problems.append(
            f"자글거림이 큽니다 {metrics['high_frequency']:.3f} "
            f"(한계 {HIGH_FREQUENCY_LIMIT}). 점묘나 디더가 섞인 그림입니다"
        )
    if metrics["speck"] > SPECK_LIMIT:
        problems.append(
            f"튀는 점이 많습니다 {metrics['speck']:.4f} (한계 {SPECK_LIMIT})"
        )
    return problems


def _downsample(cell: Image.Image) -> Image.Image:
    """알파로 가중해 한 칸을 평균낸다. 투명한 자리의 색이 섞이면 후광이 생긴다."""

    read = cell.load()
    low = Image.new("RGBA", (CELL_W // DOT, CELL_H // DOT))
    write = low.load()
    area = DOT * DOT
    for block_y in range(CELL_H // DOT):
        for block_x in range(CELL_W // DOT):
            red = green = blue = coverage = weight = 0
            for y in range(block_y * DOT, block_y * DOT + DOT):
                for x in range(block_x * DOT, block_x * DOT + DOT):
                    pixel = read[x, y]
                    coverage += pixel[3]
                    weight += pixel[3]
                    red += pixel[0] * pixel[3]
                    green += pixel[1] * pixel[3]
                    blue += pixel[2] * pixel[3]
            if weight == 0:
                write[block_x, block_y] = (0, 0, 0, 0)
                continue
            write[block_x, block_y] = (
                red // weight,
                green // weight,
                blue // weight,
                255 if coverage // area >= 128 else 0,
            )
    return low


def bake(sheet: Image.Image) -> Image.Image:
    """아틀라스와 같은 방식으로 굽는다."""

    lows = [
        [
            _downsample(
                sheet.crop(
                    (
                        column * CELL_W,
                        row * CELL_H,
                        (column + 1) * CELL_W,
                        (row + 1) * CELL_H,
                    )
                )
            )
            for column in range(COLUMNS)
        ]
        for row in range(ROWS)
    ]
    pixels: list[tuple[int, int, int]] = []
    for row in lows:
        for low in row:
            read = low.load()
            pixels.extend(
                read[x, y][:3]
                for y in range(low.height)
                for x in range(low.width)
                if read[x, y][3]
            )
    board = Image.new("RGB", (len(pixels), 1))
    board.putdata(pixels)
    palette = board.quantize(colors=PALETTE_COLORS, method=Image.Quantize.MEDIANCUT)

    out = Image.new("RGBA", SHEET, (0, 0, 0, 0))
    for row_index, row in enumerate(lows):
        for column_index, low in enumerate(row):
            alpha = low.getchannel("A")
            flat = low.convert("RGB").quantize(
                palette=palette, dither=Image.Dither.NONE
            )
            flat = flat.convert("RGB")
            flat.putalpha(alpha)
            out.paste(
                flat.resize((CELL_W, CELL_H), Image.Resampling.NEAREST),
                (column_index * CELL_W, row_index * CELL_H),
            )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--check", action="store_true", help="검사만 하고 쓰지 않는다")
    args = parser.parse_args()

    with Image.open(args.source) as opened:
        sheet = opened.convert("RGBA")

    problems = verify(sheet)
    metrics = measure(sheet)
    print(f"  자글거림 {metrics['high_frequency']:.3f}  튀는 점 {metrics['speck']:.4f}")
    if problems:
        for problem in problems:
            print(f"  ✗ {problem}")
        return 1
    print("  검사 통과")
    if args.check:
        return 0

    baked = bake(sheet)
    colors = {
        pixel for pixel in baked.get_flattened_data() if pixel[3]
    }
    alphas = {pixel[3] for pixel in baked.get_flattened_data()}
    print(f"  구운 뒤 색 {len(colors)}개, 알파 {sorted(alphas)}")
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    baked.save(OUT_PATH, "PNG")
    print(f"  {OUT_PATH.name} 갱신  {OUT_PATH.stat().st_size // 1024}KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
