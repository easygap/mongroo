"""Build the release painterly expedition atlas from approved source masters.

The source masters are kept out of the Flutter bundle. This deterministic
pipeline performs the production work that a raw image generator cannot:

* continuous, wrapped 4x4 terrain macro phases;
* neutral-background alpha matting and white-fringe removal;
* bottom-centred sprite normalisation and atlas gutter extrusion;
* regional colour grading without duplicating source art;
* automated seam, alpha and high-frequency texture QA.

Running the script twice with unchanged sources produces byte-identical files.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageOps, ImageStat

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "design-system" / "concepts" / "expedition-overworld-v2" / "sources"
RUNTIME_DIR = ROOT / "app" / "assets" / "adventure" / "overworld"
ATLAS_PATH = RUNTIME_DIR / "expedition-tile-atlas-v2.png"
MANIFEST_PATH = RUNTIME_DIR / "expedition-tile-atlas-v2.json"
MONSTER_SOURCE = (
    ROOT
    / "app"
    / "assets"
    / "adventure"
    / "tangles"
    / "tangle-tangled-ledger-idle-v1.webp"
)

CELL = 96
GUTTER = 2
STRIDE = CELL + GUTTER * 2
COLS = 8
PHASE_SUFFIXES = tuple(chr(ord("a") + index) for index in range(16))
SPRITES = (
    *(f"floor_{suffix}" for suffix in PHASE_SUFFIXES),
    *(f"moss_{suffix}" for suffix in PHASE_SUFFIXES),
    *(f"water_{suffix}" for suffix in PHASE_SUFFIXES),
    "shore_n",
    "shore_e",
    "shore_s",
    "shore_w",
    "wall",
    "shelf",
    "lantern",
    "chest",
    "item",
    "npc",
    "monster",
    "altar",
    "root",
)
REGIONS = (
    "moss_archive",
    "echo_well",
    "starlight_seed_vault",
    "heartwood_observatory",
)
SOURCE_FILES = {
    "floor": "terrain-floor.png",
    "moss": "terrain-moss.png",
    "water": "terrain-water.png",
    "wall": "prop-wall.png",
    "shelf": "prop-shelf.png",
    "lantern": "prop-lantern.png",
    "chest": "prop-chest.png",
    "item": "prop-item.png",
    "npc": "prop-npc.png",
    "altar": "prop-altar.png",
    "root": "prop-root.png",
}

# (shadow, highlight, blend amount, saturation, brightness, contrast)
REGION_GRADES = {
    "moss_archive": ("#16281f", "#d9c994", 0.08, 0.96, 0.97, 1.04),
    "echo_well": ("#102e38", "#9fd5ca", 0.29, 0.88, 0.89, 1.06),
    "starlight_seed_vault": ("#181936", "#b4abd8", 0.34, 0.82, 0.84, 1.07),
    "heartwood_observatory": ("#2d1710", "#e1b16f", 0.22, 0.94, 0.92, 1.06),
}


def _rgb(hex_value: str) -> tuple[int, int, int]:
    value = hex_value.removeprefix("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def _source(name: str) -> Image.Image:
    path = SOURCE_DIR / SOURCE_FILES[name]
    if not path.exists():
        raise FileNotFoundError(f"missing approved source master: {path}")
    with Image.open(path) as image:
        return image.convert("RGB")


def _central_square(image: Image.Image) -> Image.Image:
    side = min(image.size)
    left = (image.width - side) // 2
    top = (image.height - side) // 2
    return image.crop((left, top, left + side, top + side))


def _material_source(name: str) -> Image.Image:
    source = _central_square(_source(name))
    # Use the centre 76%: generator borders often carry vignette or framing.
    inset = round(source.width * 0.12)
    return source.crop((inset, inset, source.width - inset, source.height - inset))


def _clean_material(image: Image.Image, size: int = CELL) -> Image.Image:
    image = image.resize((size, size), Image.Resampling.LANCZOS)
    # A 3px median pass removes isolated generator stipple while retaining the
    # large painted planes that define the approved visual language.
    image = image.filter(ImageFilter.MedianFilter(3))
    image = image.filter(ImageFilter.UnsharpMask(radius=0.65, percent=55, threshold=5))
    return image.convert("RGBA")


def _band_mask(width: int, height: int, axis: str, rising: bool) -> Image.Image:
    """띠 하나에 쓸 흐림 마스크. 회전으로 만들지 않는다 — 방향이 뒤집힌다."""

    mask = Image.new("L", (width, height))
    pixels = mask.load()
    span = width if axis == "x" else height
    for index in range(span):
        ratio = index / max(1, span - 1)
        value = ratio if rising else 1 - ratio
        smooth = value * value * (3 - 2 * value)
        level = round(255 * smooth)
        if axis == "x":
            for y in range(height):
                pixels[index, y] = level
        else:
            for x in range(width):
                pixels[x, index] = level
    return mask


def _wrap_edges(image: Image.Image, band: int) -> Image.Image:
    """가장자리 띠만 서로 맞춰 이어 붙인다. **거울 대칭을 만들지 않는다.**

    앞 판은 사분면 하나를 네 방향으로 뒤집어 4×4 매크로를 만들었다. 이음매는
    확실히 없어지지만 화면 전체가 마름모 벽지처럼 보이고, `floor_a~p` 열여섯 칸이
    사실은 같은 그림의 사분면 조각이라 결이 하나뿐이었다.

    여기서는 매크로를 원본에서 통째로 뜨고, 맞물리는 자리만 좁은 띠에서 **반대쪽
    띠를 뒤집어 섞는다.** 뒤집어 섞어야 양 끝 픽셀이 정확히 같은 값이 되어 이어
    붙었을 때 선이 안 보인다. 섞는 비율은 끝에서 50%, 띠 안쪽으로 가며 0%다.

    한 줄을 늘려 평균내는 방법도 써 봤는데, 띠가 통째로 뭉개져 가로 얼룩으로
    보였다. 반대쪽 결을 그대로 가져오면 무늬가 살아 있어 티가 안 난다.
    """

    width, height = image.size
    result = image.copy()

    def fade(span: int, axis: str, rising: bool) -> Image.Image:
        # 끝에서 50%(=128), 안쪽으로 0%. 부드럽게 떨어뜨린다.
        mask = Image.new("L", (band, height) if axis == "x" else (width, band))
        pixels = mask.load()
        for index in range(span):
            ratio = index / max(1, span - 1)
            value = ratio if rising else 1 - ratio
            level = round(128 * value * value * (3 - 2 * value))
            if axis == "x":
                for y in range(height):
                    pixels[index, y] = level
            else:
                for x in range(width):
                    pixels[x, index] = level
        return mask

    # ── 좌우 ────────────────────────────────────────────────────────────────
    left_band = result.crop((0, 0, band, height))
    right_band = result.crop((width - band, 0, width, height))
    result.paste(
        Image.composite(ImageOps.mirror(right_band), left_band, fade(band, "x", False)),
        (0, 0),
    )
    result.paste(
        Image.composite(ImageOps.mirror(left_band), right_band, fade(band, "x", True)),
        (width - band, 0),
    )

    # ── 위아래 ──────────────────────────────────────────────────────────────
    top_band = result.crop((0, 0, width, band))
    bottom_band = result.crop((0, height - band, width, height))
    result.paste(
        Image.composite(ImageOps.flip(bottom_band), top_band, fade(band, "y", False)),
        (0, 0),
    )
    result.paste(
        Image.composite(ImageOps.flip(top_band), bottom_band, fade(band, "y", True)),
        (0, height - band),
    )

    # ── 양 끝 한 블록은 아예 같은 띠로 ──────────────────────────────────────
    # 위 섞기는 끝 **픽셀**만 같게 만든다. 그런데 뒤에서 도트로 낮출 때 한
    # 블록(DOT픽셀)을 평균내므로, 끝에서 두세 번째 픽셀이 다르면 그 차이가
    # 블록 색을 갈라 이음매에 줄이 생긴다(실측 21). 양 끝 한 블록을 같은
    # 그림으로 못 박으면 평균이 같아져 0이 된다. 384px 중 4px이라 결은 그대로다.
    block = DOT
    shared_x = Image.blend(
        result.crop((0, 0, block, height)),
        result.crop((width - block, 0, width, height)),
        0.5,
    )
    result.paste(shared_x, (0, 0))
    result.paste(shared_x, (width - block, 0))
    shared_y = Image.blend(
        result.crop((0, 0, width, block)),
        result.crop((0, height - block, width, height)),
        0.5,
    )
    result.paste(shared_y, (0, 0))
    result.paste(shared_y, (0, height - block))
    return result


def _macro_cells(image: Image.Image) -> tuple[Image.Image, ...]:
    """매크로를 렌더러가 쓰는 열여섯 칸으로 자른다."""

    return tuple(
        image.crop(
            (column * CELL, row * CELL, (column + 1) * CELL, (row + 1) * CELL)
        )
        for row in range(4)
        for column in range(4)
    )


def _phase_mean_spread(phases: tuple[Image.Image, ...]) -> float:
    """열여섯 칸의 평균 밝기가 얼마나 벌어져 있나. 벌어질수록 격자가 보인다."""

    means = [
        ImageStat.Stat(ImageOps.grayscale(phase.convert("RGB"))).mean[0]
        for phase in phases
    ]
    return max(means) - min(means)


def _flatten_macro(image: Image.Image, target: float = 4.0) -> Image.Image:
    """타일보다 **큰** 밝기 기울기를 필요한 만큼만 깎는다.

    한 칸만 떼어 보면 거의 평평한데 화면에는 마름모 격자가 떴다. 범인은 칸 안의
    무늬가 아니라 매크로 전체에 걸린 명암 기울기다. 렌더러가 매크로를 네 칸마다
    통째로 반복하니(`(x&3)|((y&3)<<2)`), 그 기울기가 4칸 주기의 격자로 보인다.
    앞서 거울을 걷어냈는데도 벽지가 남아 있던 이유가 이것이다.

    한 칸보다 큰 성분만 빼고 평균 밝기를 다시 얹는다. 칸 안의 결은 남고 칸끼리의
    밝기 차만 사라진다. 이어 붙일 텍스처에서 저주파를 걷어내는 건 흔한 처리다.

    반경을 하나로 고정하지 않는 이유는 재료마다 필요한 양이 다르기 때문이다.
    바닥은 0.30칸이면 2.8까지 떨어지는데 이끼는 같은 반경에서 7.8이 남는다.
    이끼에 맞춰 좁히면 바닥의 얼룩까지 지워져 비닐장판이 된다. 그래서 넓은
    반경부터 시도해 **기준을 만족하는 가장 넓은 반경**을 쓴다.
    """

    rgb = image.convert("RGB")
    mean = tuple(round(value) for value in ImageStat.Stat(rgb).mean[:3])
    base = Image.new("RGB", rgb.size, mean)
    flat = rgb
    for ratio in (0.60, 0.45, 0.34, 0.26, 0.20, 0.15, 0.11):
        blur = rgb.filter(ImageFilter.GaussianBlur(CELL * ratio))
        detail = ImageChops.subtract(rgb, blur, scale=1, offset=128)
        flat = ImageChops.add(detail, base, scale=1, offset=-128)
        if _phase_mean_spread(_macro_cells(flat)) <= target:
            break
    return flat.convert("RGBA")


def _seamless_phases(name: str) -> tuple[Image.Image, ...]:
    source = _material_source(name)
    # 매크로 한 장을 원본에서 통째로 뜬다. 열여섯 칸이 전부 다른 그림이라
    # 바닥이 반복돼도 눈이 격자를 잡아내지 못한다.
    macro = _clean_material(source, CELL * 4)
    macro = _flatten_macro(macro)
    macro = _wrap_edges(macro, band=round(CELL * 4 * 0.06))
    return _macro_cells(macro)


def _grade(image: Image.Image, region: str) -> Image.Image:
    shadow, highlight, amount, saturation, brightness, contrast = REGION_GRADES[region]
    alpha = image.getchannel("A")
    rgb = image.convert("RGB")
    luminance = ImageOps.grayscale(rgb)
    tint = ImageOps.colorize(luminance, _rgb(shadow), _rgb(highlight))
    rgb = Image.blend(rgb, tint, amount)
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
    # Fixed-midpoint contrast is a point operation. Unlike ImageEnhance's
    # per-image mean, it maps equal seam pixels to equal output values even
    # after the macro tile has been split into separate atlas cells.
    lookup = [
        max(0, min(255, round((value - 128) * contrast + 128)))
        for value in range(256)
    ]
    rgb = rgb.point(lookup * 3)
    rgb.putalpha(alpha)
    return rgb


def _candidate_background(pixel: tuple[int, int, int]) -> bool:
    high = max(pixel)
    low = min(pixel)
    luma = pixel[0] * 0.2126 + pixel[1] * 0.7152 + pixel[2] * 0.0722
    return luma >= 222 and high - low <= 34


def _neutral_background_matte(image: Image.Image) -> Image.Image:
    """Extract centred art from a neutral generated background.

    Connected components keep pale highlights inside the object while clearing
    the outer backdrop and genuine enclosed background holes. A two-pixel
    feather followed by colour decontamination prevents white halos after atlas
    downsampling.
    """

    rgb = image.convert("RGB")
    longest = max(rgb.size)
    if longest > 640:
        scale = 640 / longest
        rgb = rgb.resize(
            (max(1, round(rgb.width * scale)), max(1, round(rgb.height * scale))),
            Image.Resampling.LANCZOS,
        )
    width, height = rgb.size
    pixels = rgb.load()
    candidates = bytearray(width * height)
    for y in range(height):
        row = y * width
        for x in range(width):
            if _candidate_background(pixels[x, y]):
                candidates[row + x] = 1

    background = bytearray(width * height)
    seen = bytearray(width * height)
    minimum_hole = max(24, width * height // 6000)
    for start in range(width * height):
        if not candidates[start] or seen[start]:
            continue
        queue: deque[int] = deque([start])
        seen[start] = 1
        component: list[int] = []
        touches_edge = False
        while queue:
            index = queue.popleft()
            component.append(index)
            x = index % width
            y = index // width
            if x == 0 or y == 0 or x == width - 1 or y == height - 1:
                touches_edge = True
            if x > 0:
                neighbor = index - 1
                if candidates[neighbor] and not seen[neighbor]:
                    seen[neighbor] = 1
                    queue.append(neighbor)
            if x + 1 < width:
                neighbor = index + 1
                if candidates[neighbor] and not seen[neighbor]:
                    seen[neighbor] = 1
                    queue.append(neighbor)
            if y > 0:
                neighbor = index - width
                if candidates[neighbor] and not seen[neighbor]:
                    seen[neighbor] = 1
                    queue.append(neighbor)
            if y + 1 < height:
                neighbor = index + width
                if candidates[neighbor] and not seen[neighbor]:
                    seen[neighbor] = 1
                    queue.append(neighbor)
        if touches_edge or len(component) >= minimum_hole:
            for index in component:
                background[index] = 255

    bg_mask = Image.frombytes("L", (width, height), bytes(background))
    # Close one-pixel islands, then feather the true object boundary.
    bg_mask = bg_mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.85))
    alpha = ImageOps.invert(bg_mask)
    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)

    # Remove neutral background contamination in semi-transparent edge pixels.
    data = list(rgba.get_flattened_data())
    cleaned: list[tuple[int, int, int, int]] = []
    for red, green, blue, opacity in data:
        if opacity == 0:
            cleaned.append((0, 0, 0, 0))
            continue
        if opacity < 250:
            factor = 255 / max(28, opacity)
            red = round(255 - (255 - red) * factor)
            green = round(255 - (255 - green) * factor)
            blue = round(255 - (255 - blue) * factor)
        cleaned.append((max(0, red), max(0, green), max(0, blue), opacity))
    rgba.putdata(cleaned)
    return rgba


def _wall_cell(course: Image.Image) -> Image.Image:
    """돌 한 켜를 쌓아 **옆 칸과 이어지는** 벽면 한 칸을 만든다.

    원본 벽 그림은 낮은 연석 한 켜다(칸의 아래 1/3, 채움 28%). 그것으로 방을
    두르면 바닥에 그은 선처럼 보여 안에 갇혀 있다는 느낌이 전혀 안 난다.
    타일셋에서 벽은 원래 이렇게 만든다 — 켜 하나를 그려 두고 세로로 쌓는다.

    두 가지를 지킨다.

    * 켜마다 좌우를 번갈아 뒤집는다. 안 뒤집으면 돌의 이음매가 세로로 줄 서서
      벽돌이 아니라 격자 무늬로 보인다.
    * 칸 **폭 끝까지** 채우고 좌우 가장자리를 서로 물린다. 가운데에 좁게 그리면
      벽을 나란히 놓았을 때 사이가 벌어져 울타리처럼 보인다.
    """

    courses = 3
    height = round(CELL * 0.30)
    band = course.resize((CELL, height), Image.Resampling.LANCZOS)

    # 좌우 물리기: 오른쪽 끝 띠를 뒤집어 왼쪽 끝에 섞고, 반대도 같이 한다.
    edge = max(2, CELL // 12)
    mask = Image.new("L", (edge, height))
    write = mask.load()
    for index in range(edge):
        level = round(128 * (1 - index / max(1, edge - 1)))
        for y in range(height):
            write[index, y] = level
    left = band.crop((0, 0, edge, height))
    right = band.crop((CELL - edge, 0, CELL, height))
    band.paste(Image.composite(ImageOps.mirror(right), left, mask), (0, 0))
    band.paste(
        Image.composite(ImageOps.mirror(left), right, ImageOps.mirror(mask)),
        (CELL - edge, 0),
    )

    stacked = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for index in range(courses):
        layer = band if index % 2 == 0 else ImageOps.mirror(band)
        alpha = layer.getchannel("A")
        # 위에서 빛이 떨어진다. 아래 켜일수록 어둡다.
        rgb = ImageEnhance.Brightness(layer.convert("RGB")).enhance(1 - 0.14 * index)
        rgb.putalpha(alpha)
        stacked.alpha_composite(rgb, (0, CELL - (courses - index) * height))
    return stacked


def _normalise_sprite(image: Image.Image, kind: str) -> Image.Image:
    if image.mode != "RGBA":
        image = _neutral_background_matte(image)
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise RuntimeError(f"empty alpha matte for {kind}")
    image = image.crop(bbox)
    if kind == "wall":
        # 벽은 칸을 꽉 채워야 옆 칸과 이어진다. 가운데 맞춤을 거치지 않는다.
        return _wall_cell(image)
    # Each source is normalised into the full atlas cell; object dimensions in
    # the world data control its actual footprint and depth sorting.
    margins = {
        "shelf": (84, 91),
        "lantern": (67, 91),
        "chest": (88, 78),
        "item": (48, 82),
        "npc": (67, 92),
        "monster": (84, 90),
        "altar": (89, 92),
        "root": (92, 81),
    }
    max_width, max_height = margins[kind]
    scale = min(max_width / image.width, max_height / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    image = image.resize(size, Image.Resampling.LANCZOS)
    image = image.filter(ImageFilter.UnsharpMask(radius=0.55, percent=55, threshold=5))
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    x = (CELL - image.width) // 2
    y = CELL - image.height - 2
    canvas.alpha_composite(image, (x, y))
    return canvas


def _shore_overlay(moss: Image.Image, side: str) -> Image.Image:
    """Use the approved moss material for a restrained painterly bank strip."""

    alpha = Image.new("L", (CELL, CELL), 0)
    alpha_pixels = alpha.load()
    for x in range(CELL):
        edge = 10 + round(2.2 * math.sin(x * math.pi / 24)) + (1 if (x // 19) % 2 else 0)
        for y in range(max(0, edge + 2)):
            if y < edge:
                alpha_pixels[x, y] = 238
            elif y == edge:
                alpha_pixels[x, y] = 140
            elif y == edge + 1:
                alpha_pixels[x, y] = 48
    north = moss.copy()
    north.putalpha(alpha)
    if side == "n":
        return north
    if side == "e":
        return north.rotate(-90)
    if side == "s":
        return north.rotate(180)
    if side == "w":
        return north.rotate(90)
    raise ValueError(side)


def _texture_metrics(image: Image.Image) -> tuple[float, float]:
    pixels = image.load()
    opaque_edges = high_edges = opaque_centers = isolated = 0

    def luma(pixel: tuple[int, int, int, int]) -> float:
        return pixel[0] * 0.2126 + pixel[1] * 0.7152 + pixel[2] * 0.0722

    for y in range(CELL):
        for x in range(CELL):
            current = pixels[x, y]
            if current[3] >= 224:
                for nx, ny in ((x + 1, y), (x, y + 1)):
                    if nx < CELL and ny < CELL and pixels[nx, ny][3] >= 224:
                        opaque_edges += 1
                        if abs(luma(current) - luma(pixels[nx, ny])) >= 36:
                            high_edges += 1
            if not (0 < x < CELL - 1 and 0 < y < CELL - 1 and current[3] >= 224):
                continue
            neighbors = (
                pixels[x - 1, y],
                pixels[x + 1, y],
                pixels[x, y - 1],
                pixels[x, y + 1],
            )
            if any(pixel[3] < 224 for pixel in neighbors):
                continue
            opaque_centers += 1
            values = [luma(pixel) for pixel in neighbors]
            average = sum(values) / len(values)
            if max(values) - min(values) <= 14 and abs(luma(current) - average) >= 30:
                isolated += 1
    return high_edges / max(1, opaque_edges), isolated / max(1, opaque_centers)


def _seam_error(phases: tuple[Image.Image, ...]) -> int:
    """매크로가 **자기 자신과 이어지는 자리**의 어긋남.

    앞 판은 열여섯 칸의 모든 인접면을 재고 픽셀이 같기를 요구했다. 그건 사분면을
    거울로 뒤집어 만들 때만 0이 된다 — 뒤집힌 경계는 반사축이라 양쪽 픽셀이
    문자 그대로 같기 때문이다. 그래서 그 검사를 통과하려면 거울을 써야 했고,
    거울을 쓰니 바닥이 마름모 벽지가 됐다.

    지금은 매크로를 원본에서 통째로 뜬다. 인접한 칸은 원본에서 **옆에 붙어 있던
    픽셀**이라 연속이지 동일하지 않다. 그림이 세밀할수록 차이가 커지는데, 그건
    결함이 아니라 결이다.

    이어 붙일 때 실제로 티가 나는 곳은 매크로의 오른쪽 끝이 왼쪽 끝과 만나는
    자리, 아래 끝이 위 끝과 만나는 자리뿐이다. 그 둘만 잰다.
    """

    comparisons = []
    for row in range(4):
        # 오른쪽 끝 칸의 오른쪽 변 ↔ 왼쪽 끝 칸의 왼쪽 변.
        right_edge = phases[row * 4 + 3].crop((CELL - 1, 0, CELL, CELL))
        left_edge = phases[row * 4].crop((0, 0, 1, CELL))
        comparisons.append((right_edge, left_edge))
    for column in range(4):
        bottom_edge = phases[3 * 4 + column].crop((0, CELL - 1, CELL, CELL))
        top_edge = phases[column].crop((0, 0, CELL, 1))
        comparisons.append((bottom_edge, top_edge))
    return max(
        max(channel[1] for channel in ImageChops.difference(left, right).getextrema())
        for left, right in comparisons
    )


def _composite_with_gutter(atlas: Image.Image, sprite: Image.Image, cell_x: int, cell_y: int) -> None:
    x = cell_x + GUTTER
    y = cell_y + GUTTER
    atlas.alpha_composite(sprite, (x, y))
    atlas.alpha_composite(sprite.crop((0, 0, CELL, 1)).resize((CELL, GUTTER)), (x, cell_y))
    atlas.alpha_composite(
        sprite.crop((0, CELL - 1, CELL, CELL)).resize((CELL, GUTTER)),
        (x, y + CELL),
    )
    atlas.alpha_composite(sprite.crop((0, 0, 1, CELL)).resize((GUTTER, CELL)), (cell_x, y))
    atlas.alpha_composite(
        sprite.crop((CELL - 1, 0, CELL, CELL)).resize((GUTTER, CELL)),
        (x + CELL, y),
    )
    for source, destination in (
        ((0, 0, 1, 1), (cell_x, cell_y)),
        ((CELL - 1, 0, CELL, 1), (x + CELL, cell_y)),
        ((0, CELL - 1, 1, CELL), (cell_x, y + CELL)),
        ((CELL - 1, CELL - 1, CELL, CELL), (x + CELL, y + CELL)),
    ):
        atlas.alpha_composite(sprite.crop(source).resize((GUTTER, GUTTER)), destination)


# ── 도트 패스 ─────────────────────────────────────────────────────────────
# 원화는 붓질이 살아 있는 96px 그림이다. 그런데 화면에서 한 칸은 24~40px로
# 줄어 그려지고, 캐릭터 시트는 색이 백 개 남짓인 도트다. 둘을 그대로 겹치면
# 땅은 뭉개지고 캐릭터만 또렷해 한 세계로 안 읽힌다.
#
# 그래서 굽기 단계에서 한 번만 낮춘다. 24칸 격자로 내리고 지역마다 팔레트
# 하나에 맞춘다. 참고한 DS 시절 타일도 화면 해상도만큼만 그리고 지역별
# 팔레트를 돌려 썼다 — 용량 때문이기도 했지만 그 덕에 한 지역이 한 색으로
# 묶여 보인다.
DOT = 4
DOT_GRID = CELL // DOT
PALETTE_COLORS = 32
PALETTE_SAMPLE = 420


def _downsample(image: Image.Image) -> Image.Image:
    """알파로 가중해 한 칸을 평균낸다.

    그냥 줄이면 투명한 자리의 색까지 섞여 테두리에 검은 후광이 남는다. 생성
    이미지에서 제일 먼저 눈에 띄는 티가 그것이라 여기서 끊는다.
    """

    source = image.load()
    low = Image.new("RGBA", (DOT_GRID, DOT_GRID))
    target = low.load()
    area = DOT * DOT
    for block_y in range(DOT_GRID):
        for block_x in range(DOT_GRID):
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
            # 알파는 반만 덮여도 있는 것으로 친다. DS 스프라이트가 그랬듯
            # 있거나 없거나 둘 중 하나여야 가장자리가 흐물거리지 않는다.
            target[block_x, block_y] = (
                red // weight,
                green // weight,
                blue // weight,
                255 if coverage // area >= 128 else 0,
            )
    return low


def _region_palette(materials: tuple[Image.Image, ...]) -> Image.Image:
    """지역 하나가 나눠 쓸 색.

    픽셀 수대로 뽑으면 바닥 타일이 팔레트를 독차지해 물빛과 등불빛이 사라진다.
    재료마다 같은 수만큼 뽑아 발언권을 맞춘다.
    """

    pixels: list[tuple[int, int, int]] = []
    for material in materials:
        low = _downsample(material)
        read = low.load()
        opaque = [
            read[x, y][:3]
            for y in range(low.height)
            for x in range(low.width)
            if read[x, y][3]
        ]
        if not opaque:
            continue
        step = max(1, len(opaque) // PALETTE_SAMPLE)
        pixels.extend(opaque[::step][:PALETTE_SAMPLE])
    board = Image.new("RGB", (len(pixels), 1))
    board.putdata(pixels)
    return board.quantize(colors=PALETTE_COLORS, method=Image.Quantize.MEDIANCUT)


def _dot_pass(image: Image.Image, palette: Image.Image) -> Image.Image:
    """한 칸을 도트로 굽는다. 색 고르기는 점 연산이라 이음매가 흐트러지지 않는다."""

    low = _downsample(image)
    alpha = low.getchannel("A")
    flat = low.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE)
    flat = flat.convert("RGB")
    flat.putalpha(alpha)
    # 도로 키울 때는 최근접이다. 부드럽게 키우면 도트로 낮춘 뜻이 없어진다.
    return flat.resize((CELL, CELL), Image.Resampling.NEAREST)


def _masters() -> tuple[dict[str, tuple[Image.Image, ...]], dict[str, Image.Image]]:
    terrain = {name: _seamless_phases(name) for name in ("floor", "moss", "water")}
    props: dict[str, Image.Image] = {}
    for kind in ("wall", "shelf", "lantern", "chest", "item", "npc", "altar", "root"):
        props[kind] = _normalise_sprite(_source(kind), kind)
    with Image.open(MONSTER_SOURCE) as monster:
        props["monster"] = _normalise_sprite(monster.convert("RGBA"), "monster")
    return terrain, props


def build() -> tuple[bytes, bytes]:
    terrain, props = _masters()
    per_region = ((len(SPRITES) + COLS - 1) // COLS) * COLS
    rows = len(REGIONS) * (per_region // COLS)
    atlas = Image.new("RGBA", (COLS * STRIDE, rows * STRIDE), (0, 0, 0, 0))
    manifest: dict[str, object] = {
        "version": 3,
        "cell": CELL,
        "gutter": GUTTER,
        "stride": STRIDE,
        "columns": COLS,
        "sprites_per_region_padded": per_region,
        "regions": {},
    }
    max_edge = max_speck = 0.0
    max_seam_error = 0
    max_spread = 0.0
    min_ground_alpha = 255
    min_prop_transparent = 255

    for region_index, region in enumerate(REGIONS):
        graded_terrain = {
            name: tuple(_grade(phase, region) for phase in phases)
            for name, phases in terrain.items()
        }
        graded_props = {name: _grade(sprite, region) for name, sprite in props.items()}
        # 지역 하나가 나눠 쓸 색을 먼저 정하고, 그 색으로만 모든 재료를 굽는다.
        palette = _region_palette(
            tuple(phases[0] for phases in graded_terrain.values())
            + tuple(graded_props.values())
        )
        dotted_terrain = {
            name: tuple(_dot_pass(phase, palette) for phase in phases)
            for name, phases in graded_terrain.items()
        }
        entries: dict[str, object] = {}
        for sprite_index, name in enumerate(SPRITES):
            if name.startswith(("floor_", "moss_", "water_")):
                terrain_name, suffix = name.rsplit("_", 1)
                sprite = dotted_terrain[terrain_name][ord(suffix) - ord("a")]
                min_ground_alpha = min(min_ground_alpha, sprite.getchannel("A").getextrema()[0])
            elif name.startswith("shore_"):
                # 물가 띠는 매끈한 이끼에서 만들고 나서 굽는다. 구운 것에서
                # 만들면 격자 위에 격자가 얹혀 계단이 두 겹으로 보인다.
                sprite = _dot_pass(
                    _shore_overlay(graded_terrain["moss"][0], name[-1]), palette
                )
            else:
                sprite = _dot_pass(graded_props[name], palette)
                min_prop_transparent = min(min_prop_transparent, sprite.getchannel("A").getextrema()[0])
            edge, speck = _texture_metrics(sprite)
            max_edge = max(max_edge, edge)
            max_speck = max(max_speck, speck)
            atlas_index = region_index * per_region + sprite_index
            cell_x = (atlas_index % COLS) * STRIDE
            cell_y = (atlas_index // COLS) * STRIDE
            _composite_with_gutter(atlas, sprite, cell_x, cell_y)
            entries[name] = {"x": cell_x + GUTTER, "y": cell_y + GUTTER, "w": CELL, "h": CELL}
        manifest["regions"][region] = entries  # type: ignore[index]
        for phases in dotted_terrain.values():
            max_seam_error = max(max_seam_error, _seam_error(phases))
            max_spread = max(max_spread, _phase_mean_spread(phases))

    if min_ground_alpha != 255:
        raise RuntimeError(f"ground tiles must be fully opaque: {min_ground_alpha}")
    if min_prop_transparent != 0:
        raise RuntimeError(f"props require real transparent pixels: {min_prop_transparent}")
    # Interior macro-cell boundaries are consecutive painted pixels rather than
    # duplicated pixels. Their channel delta must remain below a normal broad
    # brush transition; the wrapped outer macro boundary is mirror-exact.
    # 도트로 굽고 나서 실측은 이음매 0, 고주파 0.044, 고립 점 0이다. 한계를
    # 실측 언저리로 조여야 검사가 실제로 지킨다 — 40/0.19처럼 헐거우면 화풍이
    # 무너져도 통과한다.
    if max_seam_error > 4:
        raise RuntimeError(f"terrain phase seam error: {max_seam_error}")
    if max_edge > 0.10:
        raise RuntimeError(f"high-frequency texture ratio too high: {max_edge:.6f}")
    if max_speck > 0.0005:
        raise RuntimeError(f"isolated-speck ratio too high: {max_speck:.6f}")
    # 칸끼리 밝기가 벌어지면 네 칸 주기의 마름모 벽지가 된다.
    if max_spread > 6.0:
        raise RuntimeError(f"phase mean luma spread too wide: {max_spread:.2f}")

    source_hashes = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(SOURCE_DIR.glob("*.png"))
    }
    source_hashes[MONSTER_SOURCE.name] = hashlib.sha256(MONSTER_SOURCE.read_bytes()).hexdigest()
    manifest["source_assets"] = source_hashes
    manifest["texture_qa"] = {
        "policy": "ds-era-dot-one-palette-per-region-1bit-alpha",
        "resampling": "lanczos-median-unsharp-then-alpha-weighted-box-and-nearest",
        "dot_grid": DOT_GRID,
        "palette_colors": PALETTE_COLORS,
        "max_opaque_high_frequency_ratio": round(max_edge, 6),
        "max_isolated_speck_ratio": round(max_speck, 6),
        "max_seam_channel_error": max_seam_error,
        "seam_channel_limit": 4,
        "ground_alpha_min": min_ground_alpha,
        "prop_alpha_min": min_prop_transparent,
        "high_frequency_limit": 0.10,
        "isolated_speck_limit": 0.0005,
        "max_phase_mean_spread": round(max_spread, 3),
        "phase_mean_spread_limit": 6.0,
    }

    png = io.BytesIO()
    atlas.save(png, format="PNG", optimize=True, compress_level=9)
    png_bytes = png.getvalue()
    manifest["atlas"] = {
        "path": "assets/adventure/overworld/expedition-tile-atlas-v2.png",
        "width": atlas.width,
        "height": atlas.height,
        "sha256": hashlib.sha256(png_bytes).hexdigest(),
        "alpha_extrema": list(atlas.getchannel("A").getextrema()),
    }
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    return png_bytes, manifest_bytes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    png_bytes, manifest_bytes = build()
    if args.check:
        if not ATLAS_PATH.exists() or ATLAS_PATH.read_bytes() != png_bytes:
            raise SystemExit("expedition tile atlas v2 is stale")
        if not MANIFEST_PATH.exists() or MANIFEST_PATH.read_bytes() != manifest_bytes:
            raise SystemExit("expedition tile atlas v2 manifest is stale")
        print("expedition tile atlas v2 is deterministic and current")
        return 0
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    ATLAS_PATH.write_bytes(png_bytes)
    MANIFEST_PATH.write_bytes(manifest_bytes)
    print(f"wrote {ATLAS_PATH} ({len(png_bytes)} bytes)")
    print(f"wrote {MANIFEST_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
