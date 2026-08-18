"""Build the deterministic, noise-free expedition tile texture atlas.

The atlas is intentionally generated from broad vector-like shapes. It has no
random texture, stipple, dither, or generated-image cleanup step. Re-running
the script must produce byte-identical PNG and manifest output.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "app" / "assets" / "adventure" / "overworld"
ATLAS_PATH = RUNTIME_DIR / "expedition-tile-atlas-v1.png"
MANIFEST_PATH = RUNTIME_DIR / "expedition-tile-atlas-v1.json"

CELL = 96
GUTTER = 2
STRIDE = CELL + GUTTER * 2
SCALE = 2
COLS = 8
SPRITES = (
    "floor_a",
    "floor_b",
    "floor_c",
    "floor_d",
    "moss_a",
    "moss_b",
    "water_a",
    "water_b",
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
PALETTES = {
    "moss_archive": {
        "floor": "#676152",
        "floor_hi": "#77705f",
        "floor_lo": "#4c493f",
        "moss": "#69783e",
        "water": "#28656e",
        "water_hi": "#62c6c8",
        "stone": "#77705f",
        "metal": "#b08342",
        "glow": "#68e0db",
        "wood": "#563b2b",
        "ink": "#1a211c",
    },
    "echo_well": {
        "floor": "#3e5960",
        "floor_hi": "#587078",
        "floor_lo": "#293d43",
        "moss": "#587b76",
        "water": "#236d7d",
        "water_hi": "#74d9ec",
        "stone": "#596b70",
        "metal": "#987758",
        "glow": "#76e4f5",
        "wood": "#493b37",
        "ink": "#101d23",
    },
    "starlight_seed_vault": {
        "floor": "#454568",
        "floor_hi": "#62638a",
        "floor_lo": "#2e304f",
        "moss": "#625983",
        "water": "#32427e",
        "water_hi": "#9edfff",
        "stone": "#626381",
        "metal": "#ae8a5d",
        "glow": "#a5e4ff",
        "wood": "#43354b",
        "ink": "#17172e",
    },
    "heartwood_observatory": {
        "floor": "#584a3b",
        "floor_hi": "#705d47",
        "floor_lo": "#3c3028",
        "moss": "#6c774b",
        "water": "#315f65",
        "water_hi": "#87c9c0",
        "stone": "#6c6152",
        "metal": "#b77d4d",
        "glow": "#ffd078",
        "wood": "#613c29",
        "ink": "#241813",
    },
}


def rgba(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = hex_color.lstrip("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4)) + (
        alpha,
    )


def mix_rgba(
    first: str,
    second: str,
    amount: float,
) -> tuple[int, int, int, int]:
    a = rgba(first)
    b = rgba(second)
    return tuple(round(a[index] + (b[index] - a[index]) * amount) for index in range(3)) + (255,)


def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (CELL * SCALE, CELL * SCALE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def box(values: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    return tuple(value * SCALE for value in values)


def points(values: list[tuple[int, int]]) -> list[tuple[int, int]]:
    return [(x * SCALE, y * SCALE) for x, y in values]


def finish(image: Image.Image) -> Image.Image:
    # Preserve deliberately drawn edges. Lanczos introduces ringing pixels and
    # false colour fringes which read as AI grain once a tile is repeated.
    return image.resize((CELL, CELL), Image.Resampling.NEAREST)


def floor_tile(palette: dict[str, str], variant: int) -> Image.Image:
    image, draw = canvas()
    draw.rectangle(box((0, 0, 96, 96)), fill=rgba(palette["floor"]))
    # Each tile is one broad material plane. Two low-contrast seams at most
    # retain hand-built topology without turning the repeated map into confetti.
    draw.polygon(
        points([(0, 0), (96, 0), (96, 18), (18, 18), (18, 96), (0, 96)]),
        fill=mix_rgba(palette["floor"], palette["floor_hi"], .16),
    )
    seams = (
        ([(0, 63), (96, 63)],),
        ([(34, 0), (34, 96)],),
        ([(0, 36), (58, 36)], [(58, 36), (58, 96)]),
        ([(0, 69), (43, 69)], [(43, 0), (43, 69)]),
    )
    for seam in seams[variant]:
        draw.line(
            points(seam),
            fill=mix_rgba(palette["floor"], palette["floor_lo"], .42),
            width=2 * SCALE,
        )
    draw.line(
        points([(0, 2), (96, 2)]),
        fill=mix_rgba(palette["floor"], palette["floor_hi"], .35),
        width=1 * SCALE,
    )
    return finish(image)


def moss_tile(palette: dict[str, str], variant: int) -> Image.Image:
    image = floor_tile(palette, variant + 1).resize((CELL * SCALE, CELL * SCALE))
    draw = ImageDraw.Draw(image)
    cushions = (
        ((-10, 57, 55, 104), (47, 49, 108, 101)),
        ((-10, -8, 57, 42), (45, -9, 108, 48)),
    )
    for rect in cushions[variant]:
        draw.rounded_rectangle(
            box(rect),
            radius=18 * SCALE,
            fill=rgba(palette["moss"]),
            outline=mix_rgba(palette["moss"], palette["floor_hi"], .32),
            width=1 * SCALE,
        )
    return finish(image)


def water_tile(palette: dict[str, str], variant: int) -> Image.Image:
    image, draw = canvas()
    draw.rectangle(box((0, 0, 96, 96)), fill=rgba(palette["water"]))
    offset = 7 if variant else 0
    for x, y, w in ((-10, 25 + offset, 61), (38, 62 - offset, 68)):
        draw.arc(
            box((x, y, x + w, y + 19)),
            start=18,
            end=158,
            fill=mix_rgba(palette["water"], palette["water_hi"], .62),
            width=2 * SCALE,
        )
    return finish(image)


def texture_metrics(image: Image.Image) -> tuple[float, float]:
    """Return opaque high-frequency edge and isolated-speck ratios.

    Transparent sprite boundaries are excluded: the test is aimed at material
    texture, not silhouette complexity. A stippled/noisy fill fails both ratios.
    """

    pixels = image.load()
    opaque_edges = 0
    high_edges = 0
    opaque_centers = 0
    isolated = 0

    def luma(pixel: tuple[int, int, int, int]) -> float:
        return pixel[0] * .2126 + pixel[1] * .7152 + pixel[2] * .0722

    for y in range(CELL):
        for x in range(CELL):
            current = pixels[x, y]
            if current[3] >= 224:
                if x + 1 < CELL and pixels[x + 1, y][3] >= 224:
                    opaque_edges += 1
                    if abs(luma(current) - luma(pixels[x + 1, y])) >= 32:
                        high_edges += 1
                if y + 1 < CELL and pixels[x, y + 1][3] >= 224:
                    opaque_edges += 1
                    if abs(luma(current) - luma(pixels[x, y + 1])) >= 32:
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
            neighbor_luma = [luma(pixel) for pixel in neighbors]
            average = sum(neighbor_luma) / len(neighbor_luma)
            if max(neighbor_luma) - min(neighbor_luma) <= 12 and abs(luma(current) - average) >= 28:
                isolated += 1
    return (
        high_edges / max(1, opaque_edges),
        isolated / max(1, opaque_centers),
    )


def composite_with_gutter(
    atlas: Image.Image,
    sprite: Image.Image,
    cell_x: int,
    cell_y: int,
) -> None:
    """Extrude edge pixels so linear sampling cannot leak adjacent cells."""

    x = cell_x + GUTTER
    y = cell_y + GUTTER
    atlas.alpha_composite(sprite, (x, y))
    atlas.alpha_composite(
        sprite.crop((0, 0, CELL, 1)).resize((CELL, GUTTER)),
        (x, cell_y),
    )
    atlas.alpha_composite(
        sprite.crop((0, CELL - 1, CELL, CELL)).resize((CELL, GUTTER)),
        (x, y + CELL),
    )
    atlas.alpha_composite(
        sprite.crop((0, 0, 1, CELL)).resize((GUTTER, CELL)),
        (cell_x, y),
    )
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
        atlas.alpha_composite(
            sprite.crop(source).resize((GUTTER, GUTTER)),
            destination,
        )


def shore_overlay(palette: dict[str, str], side: str) -> Image.Image:
    image, draw = canvas()
    dark = rgba(palette["ink"], 135)
    moss = rgba(palette["moss"], 230)
    if side == "n":
        draw.polygon(points([(0, 0), (96, 0), (96, 12), (72, 9), (45, 14), (21, 8), (0, 12)]), fill=dark)
        draw.line(points([(0, 10), (21, 7), (45, 13), (72, 8), (96, 11)]), fill=moss, width=3 * SCALE)
    elif side == "s":
        draw.polygon(points([(0, 84), (22, 88), (47, 82), (73, 89), (96, 84), (96, 96), (0, 96)]), fill=dark)
        draw.line(points([(0, 85), (22, 89), (47, 83), (73, 90), (96, 85)]), fill=moss, width=3 * SCALE)
    elif side == "e":
        draw.polygon(points([(84, 0), (88, 22), (82, 46), (89, 72), (84, 96), (96, 96), (96, 0)]), fill=dark)
        draw.line(points([(85, 0), (89, 22), (83, 46), (90, 72), (85, 96)]), fill=moss, width=3 * SCALE)
    else:
        draw.polygon(points([(0, 0), (12, 0), (8, 23), (14, 48), (7, 73), (12, 96), (0, 96)]), fill=dark)
        draw.line(points([(11, 0), (7, 23), (13, 48), (6, 73), (11, 96)]), fill=moss, width=3 * SCALE)
    return finish(image)


def prop_sprite(palette: dict[str, str], kind: str) -> Image.Image:
    image, draw = canvas()
    stone = rgba(palette["stone"])
    metal = rgba(palette["metal"])
    glow = rgba(palette["glow"])
    wood = rgba(palette["wood"])
    ink = rgba(palette["ink"])
    moss = rgba(palette["moss"])

    if kind == "wall":
        draw.rounded_rectangle(box((5, 39, 91, 89)), 7 * SCALE, fill=stone, outline=ink, width=3 * SCALE)
        draw.rounded_rectangle(box((4, 33, 92, 49)), 6 * SCALE, fill=rgba(palette["floor_hi"]), outline=ink, width=2 * SCALE)
        draw.line(points([(48, 50), (48, 87)]), fill=rgba(palette["floor_lo"]), width=2 * SCALE)
        draw.rectangle(box((11, 62, 85, 67)), fill=metal)
        draw.rounded_rectangle(box((9, 34, 31, 44)), 5 * SCALE, fill=moss)
    elif kind == "shelf":
        draw.rounded_rectangle(box((11, 15, 85, 91)), 6 * SCALE, fill=wood, outline=ink, width=3 * SCALE)
        for top in (32, 62):
            draw.rectangle(box((17, top, 79, top + 22)), fill=ink)
            for i, color in enumerate((palette["moss"], palette["metal"], palette["stone"], palette["water"])):
                left = 19 + i * 15
                draw.rounded_rectangle(box((left, top + 3, left + 11, top + 19)), 2 * SCALE, fill=rgba(color))
        draw.rectangle(box((9, 53, 87, 59)), fill=wood)
        draw.rounded_rectangle(box((12, 13, 37, 25)), 6 * SCALE, fill=moss)
    elif kind == "lantern":
        draw.ellipse(box((31, 83, 65, 94)), fill=stone, outline=ink, width=2 * SCALE)
        draw.rounded_rectangle(box((43, 38, 53, 87)), 3 * SCALE, fill=metal)
        draw.rounded_rectangle(box((28, 13, 68, 47)), 8 * SCALE, fill=metal, outline=ink, width=2 * SCALE)
        draw.rounded_rectangle(box((34, 18, 62, 42)), 5 * SCALE, fill=glow)
        draw.polygon(points([(48, 5), (57, 16), (39, 16)]), fill=metal)
    elif kind == "chest":
        draw.rounded_rectangle(box((18, 42, 78, 88)), 8 * SCALE, fill=wood, outline=ink, width=3 * SCALE)
        draw.rounded_rectangle(box((17, 30, 79, 62)), 14 * SCALE, fill=wood, outline=metal, width=5 * SCALE)
        draw.rectangle(box((43, 53, 55, 73)), fill=metal)
        draw.rounded_rectangle(box((46, 57, 52, 66)), 2 * SCALE, fill=glow)
    elif kind == "item":
        draw.polygon(points([(48, 18), (70, 48), (48, 82), (26, 48)]), fill=glow, outline=rgba("#eefeff"))
        draw.polygon(points([(48, 23), (48, 73), (31, 48)]), fill=rgba(palette["water_hi"], 155))
    elif kind == "npc":
        draw.ellipse(box((34, 14, 62, 42)), fill=rgba("#d7b78f"), outline=ink, width=2 * SCALE)
        draw.rounded_rectangle(box((27, 38, 69, 88)), 13 * SCALE, fill=moss, outline=ink, width=2 * SCALE)
        draw.arc(box((29, 7, 67, 37)), 185, 355, fill=metal, width=4 * SCALE)
        draw.ellipse(box((40, 27, 44, 31)), fill=ink)
        draw.ellipse(box((52, 27, 56, 31)), fill=ink)
    elif kind == "monster":
        draw.polygon(points([(48, 11), (76, 28), (82, 62), (68, 88), (48, 78), (28, 88), (14, 62), (20, 28)]), fill=rgba(palette["ink"]), outline=moss)
        draw.arc(box((16, 17, 80, 83)), 200, 332, fill=rgba(palette["moss"]), width=7 * SCALE)
        draw.ellipse(box((34, 43, 43, 52)), fill=rgba("#ffad91"))
        draw.ellipse(box((53, 43, 62, 52)), fill=rgba("#ffad91"))
    elif kind == "altar":
        draw.rounded_rectangle(box((15, 50, 81, 92)), 7 * SCALE, fill=stone, outline=ink, width=3 * SCALE)
        draw.rounded_rectangle(box((22, 35, 74, 65)), 6 * SCALE, fill=rgba(palette["floor_hi"]), outline=ink, width=2 * SCALE)
        draw.rounded_rectangle(box((29, 12, 69, 47)), 5 * SCALE, fill=rgba("#244a39"), outline=metal, width=3 * SCALE)
        draw.line(points([(33, 43), (65, 43)]), fill=glow, width=4 * SCALE)
        draw.ellipse(box((42, 66, 54, 82)), fill=glow, outline=metal, width=2 * SCALE)
    elif kind == "root":
        draw.line(points([(8, 90), (24, 61), (19, 38), (43, 54), (57, 17), (65, 50), (90, 31)]), fill=wood, width=13 * SCALE, joint="curve")
        draw.line(points([(8, 86), (24, 58), (19, 38), (43, 51), (57, 17), (65, 47), (90, 29)]), fill=rgba(palette["floor_hi"]), width=4 * SCALE, joint="curve")
        draw.rounded_rectangle(box((23, 49, 47, 61)), 6 * SCALE, fill=moss)
    else:
        raise ValueError(kind)
    return finish(image)


def render_sprite(palette: dict[str, str], name: str) -> Image.Image:
    if name.startswith("floor_"):
        return floor_tile(palette, ord(name[-1]) - ord("a"))
    if name.startswith("moss_"):
        return moss_tile(palette, ord(name[-1]) - ord("a"))
    if name.startswith("water_"):
        return water_tile(palette, ord(name[-1]) - ord("a"))
    if name.startswith("shore_"):
        return shore_overlay(palette, name[-1])
    return prop_sprite(palette, name)


def build() -> tuple[bytes, bytes]:
    per_region = ((len(SPRITES) + COLS - 1) // COLS) * COLS
    rows = len(REGIONS) * (per_region // COLS)
    atlas = Image.new("RGBA", (COLS * STRIDE, rows * STRIDE), (0, 0, 0, 0))
    manifest: dict[str, object] = {
        "version": 2,
        "cell": CELL,
        "gutter": GUTTER,
        "stride": STRIDE,
        "columns": COLS,
        "regions": {},
    }
    edge_ratios: list[float] = []
    speck_ratios: list[float] = []
    ground_alpha_min = 255
    for region_index, region in enumerate(REGIONS):
        entries: dict[str, object] = {}
        for sprite_index, name in enumerate(SPRITES):
            atlas_index = region_index * per_region + sprite_index
            cell_x = (atlas_index % COLS) * STRIDE
            cell_y = (atlas_index // COLS) * STRIDE
            sprite = render_sprite(PALETTES[region], name)
            if name.startswith(("floor_", "moss_", "water_")):
                ground_alpha_min = min(
                    ground_alpha_min,
                    sprite.getchannel("A").getextrema()[0],
                )
            edge_ratio, speck_ratio = texture_metrics(sprite)
            edge_ratios.append(edge_ratio)
            speck_ratios.append(speck_ratio)
            composite_with_gutter(atlas, sprite, cell_x, cell_y)
            entries[name] = {
                "x": cell_x + GUTTER,
                "y": cell_y + GUTTER,
                "w": CELL,
                "h": CELL,
            }
        manifest["regions"][region] = entries  # type: ignore[index]

    max_edge_ratio = max(edge_ratios)
    max_speck_ratio = max(speck_ratios)
    if max_edge_ratio > .18:
        raise RuntimeError(f"high-frequency texture ratio too high: {max_edge_ratio:.6f}")
    if max_speck_ratio > .001:
        raise RuntimeError(f"isolated-speck ratio too high: {max_speck_ratio:.6f}")
    if ground_alpha_min != 255:
        raise RuntimeError(f"ground tiles must be fully opaque: {ground_alpha_min}")
    manifest["texture_qa"] = {
        "policy": "broad-shapes-no-noise-no-dither",
        "resampling": "nearest",
        "max_opaque_high_frequency_ratio": round(max_edge_ratio, 6),
        "max_isolated_speck_ratio": round(max_speck_ratio, 6),
        "ground_alpha_min": ground_alpha_min,
        "high_frequency_limit": .18,
        "isolated_speck_limit": .001,
    }

    png = io.BytesIO()
    atlas.save(png, format="PNG", optimize=True, compress_level=9)
    png_bytes = png.getvalue()
    manifest["atlas"] = {
        "path": "assets/adventure/overworld/expedition-tile-atlas-v1.png",
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
            raise SystemExit("expedition tile atlas is stale")
        if not MANIFEST_PATH.exists() or MANIFEST_PATH.read_bytes() != manifest_bytes:
            raise SystemExit("expedition tile atlas manifest is stale")
        print("expedition tile atlas is deterministic and current")
        return 0
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    ATLAS_PATH.write_bytes(png_bytes)
    MANIFEST_PATH.write_bytes(manifest_bytes)
    print(f"wrote {ATLAS_PATH} ({len(png_bytes)} bytes)")
    print(f"wrote {MANIFEST_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
