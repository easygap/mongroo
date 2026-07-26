"""Build the ten character lineages into app-ready 512x768 WebP sprites."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_growth_assets import (
    CANVAS,
    FORMS,
    PHASES,
    _alpha_bbox,
    _render_asset,
    _route_scale,
    _split_route,
)


def _remove_divider_lines(image: Image.Image) -> Image.Image:
    """Drop near-white vertical panel guides occasionally drawn by ImageGen."""
    result = image.copy()
    pixels = result.load()
    for x in range(result.width):
        near_white = 0
        opaque = 0
        for y in range(result.height):
            red, green, blue, alpha = pixels[x, y]
            if alpha >= 180:
                opaque += 1
                if red >= 238 and green >= 238 and blue >= 238:
                    near_white += 1
        if opaque > result.height * 0.65 and near_white / opaque >= 0.92:
            for clear_x in range(max(0, x - 2), min(result.width, x + 3)):
                for y in range(result.height):
                    pixels[clear_x, y] = (0, 0, 0, 0)
    return result


def _split_route_with_valleys(sheet: Image.Image) -> list[Image.Image]:
    """Split a four-stage sheet even when a ribbon crosses an otherwise clear gutter."""
    width, height = sheet.size
    alpha = sheet.getchannel("A")
    visible_pixels = [
        sum(
            1
            for value in alpha.crop((x, 0, x + 1, height)).get_flattened_data()
            if value >= 64
        )
        for x in range(width)
    ]
    half_window = max(3, width // 320)
    smoothed = []
    for x in range(width):
        left = max(0, x - half_window)
        right = min(width, x + half_window + 1)
        smoothed.append(sum(visible_pixels[left:right]))

    cuts = []
    for target, radius in ((0.22, 0.08), (0.45, 0.08), (0.70, 0.08)):
        left = round(width * (target - radius))
        right = round(width * (target + radius))
        cut = min(range(left, right), key=lambda x: (smoothed[x], abs(x / width - target)))
        cuts.append(cut)

    boundaries = [0, *cuts, width]
    panels = []
    for index in range(4):
        panel = sheet.crop((boundaries[index], 0, boundaries[index + 1], height))
        panels.append(panel.crop(_alpha_bbox(panel)))
    return panels


def _split_character_route(sheet: Image.Image) -> list[Image.Image]:
    cleaned = _remove_divider_lines(sheet)
    try:
        return _split_route(cleaned)
    except ValueError:
        return _split_route_with_valleys(cleaned)


def build_lineage(source_dir: Path, output_dir: Path, slug: str) -> None:
    seed = Image.open(source_dir / slug / "shared-seed-v1-alpha.png").convert(
        "RGBA"
    )
    seed = seed.crop(_alpha_bbox(seed))
    _render_asset(
        seed,
        scale=min(420 / seed.width, 704 / seed.height),
        output=output_dir / f"{slug}-25d-seed.webp",
    )

    for form in FORMS:
        sheet = Image.open(
            source_dir / slug / f"{form}-route-chroma-v1-alpha.png"
        ).convert("RGBA")
        panels = _split_character_route(sheet)
        scale = _route_scale(panels)
        for phase, panel in zip(PHASES, panels, strict=True):
            _render_asset(
                panel,
                scale=scale,
                output=output_dir / f"{slug}-25d-{phase}-{form}.webp",
            )


def build_preview(output_dir: Path, preview_path: Path, slug: str) -> None:
    canvas = Image.new("RGB", (1800, 1120), "#fff8ea")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=24)
    small = ImageFont.load_default(size=16)
    labels = ("SEED", "SPROUT", "TODDLER", "GROWING", "ADULT")
    seed = Image.open(output_dir / f"{slug}-25d-seed.webp").convert("RGBA")
    for index, form in enumerate(FORMS):
        group_x = 40 + (index % 2) * 880
        group_y = 32 + (index // 2) * 360
        draw.rounded_rectangle(
            (group_x, group_y, group_x + 840, group_y + 328),
            radius=24,
            fill="#fffdf7",
            outline="#ead7bd",
            width=2,
        )
        draw.text((group_x + 26, group_y + 18), form.upper(), fill="#694f3c", font=font)
        assets = [seed]
        assets.extend(
            Image.open(output_dir / f"{slug}-25d-{phase}-{form}.webp").convert(
                "RGBA"
            )
            for phase in PHASES
        )
        for stage, asset in enumerate(assets):
            x = group_x + 18 + stage * 164
            thumb = asset.copy()
            thumb.thumbnail((152, 228), Image.Resampling.LANCZOS)
            canvas.paste(
                thumb,
                (x + (152 - thumb.width) // 2, group_y + 70),
                thumb,
            )
            width = draw.textlength(labels[stage], font=small)
            draw.text(
                (x + (152 - width) / 2, group_y + 298),
                labels[stage],
                fill="#8a6d55",
                font=small,
            )
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(preview_path, "WEBP", quality=92, method=6)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--preview-dir", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    for lineage in manifest["lineages"]:
        slug = lineage["slug"]
        build_lineage(args.source_dir, args.output_dir, slug)
        if args.preview_dir is not None:
            build_preview(
                args.output_dir,
                args.preview_dir / f"{slug}-growth-preview.webp",
                slug,
            )


if __name__ == "__main__":
    main()
