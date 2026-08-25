"""생성한 걷기 시트를 검수하고 앱 규격으로 들여온다.

앱에 들어가는 `expedition-walker-v1.png`를 만드는 곳이 여기다. 코드로 그리는
`build_expedition_walker.py`는 대체본으로 물러났다 — 게임 배율에서 방향이 구분되지
않고 다리가 없어서다.

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

한 장에 12칸을 요구하면 일관성이 무너진다. **방향마다 한 장씩** 받아 여기서
잇는다. 실측으로도 그 편이 낫다 - 게임 배율에서 가장 비슷한 두 방향의 픽셀
차이가 502에서 595로 벌어졌고, 무엇보다 다리가 생겨 걸음이 읽힌다.

품종별 시트도 같은 자리에서 굽는다. `--species`를 주면
`expedition-walker-<품종>-v1.png`로 나가고, 앱이 그 품종부터 새 시트를 쓴다
(없으면 공용으로 떨어진다). 지금 번들에 있는 것은 공용 한 장뿐이라 어떤
캐릭터로 들어가도 같은 여행자가 걷는다 — 품종을 하나씩 채워 넣으라고 자리를
열어 둔 것이다.

사용법:
    # 방향마다 288×120 띠 네 장 (아래·왼쪽·오른쪽·위 순서)
    python import_expedition_walker.py --strips 아래.png 왼쪽.png 오른쪽.png 위.png

    # 한 장짜리 288×480 시트
    python import_expedition_walker.py <받은시트.png>
    python import_expedition_walker.py <받은시트.png> --check   # 검사만

    # 가시니만 쓰는 시트로 굽기
    python import_expedition_walker.py --strips ... --species cactus
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("Pillow가 필요합니다: pip install Pillow")
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[2]
OVERWORLD_DIR = ROOT / "app" / "assets" / "adventure" / "overworld"


def out_path(species: str | None) -> Path:
    """구운 시트를 놓을 자리.

    품종을 주면 그 품종만 쓰는 시트가 되고, 안 주면 공용 시트를 덮는다.
    앱은 품종 시트를 먼저 찾고 없으면 공용으로 떨어진다
    (`expeditionWalkerAssetCandidates`). 그래서 한 품종씩 채워 넣을 수 있다.
    """
    if not species:
        return OVERWORLD_DIR / "expedition-walker-v1.png"
    slug = re.sub(r"[^a-z0-9]+", "-", species.strip().lower()).strip("-")
    if not slug:
        raise SystemExit("품종 코드가 비어 있습니다.")
    return OVERWORLD_DIR / f"expedition-walker-{slug}-v1.png"

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


#: 방향 순서. 다트의 `_WalkFacing`과 같아야 한다.
FACINGS = ("아래", "왼쪽", "오른쪽", "위")


def stitch(paths: list[Path]) -> Image.Image:
    """방향별 띠 넉 장을 한 시트로 잇는다."""

    sheet = Image.new("RGBA", SHEET, (0, 0, 0, 0))
    for row, path in enumerate(paths):
        with Image.open(path) as opened:
            strip = opened.convert("RGBA")
        if strip.size != (COLUMNS * CELL_W, CELL_H):
            raise SystemExit(
                f"{FACINGS[row]} 띠가 {strip.size}입니다. "
                f"{(COLUMNS * CELL_W, CELL_H)}이어야 합니다"
            )
        sheet.paste(strip, (0, row * CELL_H))
    return sheet


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="*")
    parser.add_argument(
        "--strips",
        type=Path,
        nargs=4,
        metavar=("아래", "왼쪽", "오른쪽", "위"),
        help="방향별 288×120 띠 네 장",
    )
    parser.add_argument(
        "--species",
        help="이 품종만 쓰는 시트로 굽는다. 안 주면 공용 시트를 덮는다",
    )
    parser.add_argument("--check", action="store_true", help="검사만 하고 쓰지 않는다")
    args = parser.parse_args()

    if args.strips:
        sheet = stitch(list(args.strips))
    elif args.source:
        with Image.open(args.source[0]) as opened:
            sheet = opened.convert("RGBA")
    else:
        parser.error("시트 한 장이나 --strips 넉 장이 필요합니다")

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
    target = out_path(args.species)
    target.parent.mkdir(parents=True, exist_ok=True)
    baked.save(target, "PNG")
    print(f"  {target.name} 갱신  {target.stat().st_size // 1024}KB")
    if args.species:
        print("  pubspec의 assets/adventure/overworld/ 항목이 폴더째라 따로 등록할 것은 없다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
