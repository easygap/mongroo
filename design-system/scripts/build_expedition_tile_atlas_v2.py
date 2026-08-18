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
from collections import deque
import hashlib
import io
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageOps


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


def _seamless_phases(name: str) -> tuple[Image.Image, ...]:
    source = _material_source(name)
    # Build one 4x4 macro tile from a clean 2x2 source quadrant. Only the macro
    # perimeter and its centre are mirrored; each 96px cell keeps natural
    # painted continuity instead of exposing a repeated per-cell border.
    quadrant_side = min(source.size) * 3 // 4
    left = (source.width - quadrant_side) // 2
    top = (source.height - quadrant_side) // 2
    quadrant = _clean_material(
        source.crop((left, top, left + quadrant_side, top + quadrant_side)),
        CELL * 2,
    )
    macro = Image.new("RGBA", (CELL * 4, CELL * 4), (0, 0, 0, 255))
    macro.alpha_composite(quadrant, (0, 0))
    macro.alpha_composite(ImageOps.mirror(quadrant), (CELL * 2, 0))
    macro.alpha_composite(ImageOps.flip(quadrant), (0, CELL * 2))
    macro.alpha_composite(
        ImageOps.flip(ImageOps.mirror(quadrant)),
        (CELL * 2, CELL * 2),
    )
    return tuple(
        macro.crop(
            (
                column * CELL,
                row * CELL,
                (column + 1) * CELL,
                (row + 1) * CELL,
            )
        )
        for row in range(4)
        for column in range(4)
    )


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


def _normalise_sprite(image: Image.Image, kind: str) -> Image.Image:
    if image.mode != "RGBA":
        image = _neutral_background_matte(image)
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise RuntimeError(f"empty alpha matte for {kind}")
    image = image.crop(bbox)
    # Each source is normalised into the full atlas cell; object dimensions in
    # the world data control its actual footprint and depth sorting.
    margins = {
        "wall": (92, 70),
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
    comparisons = []
    for row in range(4):
        for column in range(4):
            current = phases[row * 4 + column]
            right = phases[row * 4 + (column + 1) % 4]
            below = phases[((row + 1) % 4) * 4 + column]
            comparisons.extend(
                (
                    (current.crop((CELL - 1, 0, CELL, CELL)), right.crop((0, 0, 1, CELL))),
                    (current.crop((0, CELL - 1, CELL, CELL)), below.crop((0, 0, CELL, 1))),
                )
            )
    return max(max(channel[1] for channel in ImageChops.difference(left, right).getextrema()) for left, right in comparisons)


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
    min_ground_alpha = 255
    min_prop_transparent = 255

    for region_index, region in enumerate(REGIONS):
        graded_terrain = {
            name: tuple(_grade(phase, region) for phase in phases)
            for name, phases in terrain.items()
        }
        graded_props = {name: _grade(sprite, region) for name, sprite in props.items()}
        entries: dict[str, object] = {}
        for sprite_index, name in enumerate(SPRITES):
            if name.startswith(("floor_", "moss_", "water_")):
                terrain_name, suffix = name.rsplit("_", 1)
                sprite = graded_terrain[terrain_name][ord(suffix) - ord("a")]
                min_ground_alpha = min(min_ground_alpha, sprite.getchannel("A").getextrema()[0])
            elif name.startswith("shore_"):
                sprite = _shore_overlay(graded_terrain["moss"][0], name[-1])
            else:
                sprite = graded_props[name]
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
        for phases in graded_terrain.values():
            max_seam_error = max(max_seam_error, _seam_error(phases))

    if min_ground_alpha != 255:
        raise RuntimeError(f"ground tiles must be fully opaque: {min_ground_alpha}")
    if min_prop_transparent != 0:
        raise RuntimeError(f"props require real transparent pixels: {min_prop_transparent}")
    # Interior macro-cell boundaries are consecutive painted pixels rather than
    # duplicated pixels. Their channel delta must remain below a normal broad
    # brush transition; the wrapped outer macro boundary is mirror-exact.
    if max_seam_error > 40:
        raise RuntimeError(f"terrain phase seam error: {max_seam_error}")
    if max_edge > 0.19:
        raise RuntimeError(f"high-frequency texture ratio too high: {max_edge:.6f}")
    if max_speck > 0.0015:
        raise RuntimeError(f"isolated-speck ratio too high: {max_speck:.6f}")

    source_hashes = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(SOURCE_DIR.glob("*.png"))
    }
    source_hashes[MONSTER_SOURCE.name] = hashlib.sha256(MONSTER_SOURCE.read_bytes()).hexdigest()
    manifest["source_assets"] = source_hashes
    manifest["texture_qa"] = {
        "policy": "painted-broad-planes-no-stipple-no-dither",
        "resampling": "lanczos-median-unsharp",
        "max_opaque_high_frequency_ratio": round(max_edge, 6),
        "max_isolated_speck_ratio": round(max_speck, 6),
        "max_seam_channel_error": max_seam_error,
        "seam_channel_limit": 40,
        "ground_alpha_min": min_ground_alpha,
        "prop_alpha_min": min_prop_transparent,
        "high_frequency_limit": 0.19,
        "isolated_speck_limit": 0.0015,
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
