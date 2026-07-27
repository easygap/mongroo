"""Build six emotion-specific adult sprites for every Mongroo character.

ImageGen source sheets contain six transparent figures in the canonical form
order.  This script finds the gutters nearest the expected sixths, keeps one
stable scale per character, writes app-ready 512x768 lossless WebP assets, and
creates a single visual QA contact sheet.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_growth_assets import _alpha_bbox, _render_asset


FORMS = ("sunny", "rainy", "ember", "moonlit", "sparkling", "mosaic")
CHARACTERS = (
    ("baby-pot", "Ppoto"),
    ("handsome-pot", "Rozeon"),
    ("pretty-pot", "Bloomy"),
    ("tsundere-pot", "Gasiro"),
    ("zombie-pot", "Sideulip"),
    ("gumiho-pot", "Yeoubi"),
    ("ninja-pot", "Geurimsak"),
    ("magical-pot", "Byeolsol"),
    ("aloof-pot", "Seolhwa"),
    ("student-pot", "Haru"),
)


def _empty_runs(sheet: Image.Image) -> list[tuple[int, int]]:
    width, height = sheet.size
    alpha = sheet.getchannel("A")
    occupied = [
        alpha.crop((x, 0, x + 1, height)).getextrema()[1] >= 64
        for x in range(width)
    ]
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for x, is_occupied in enumerate([*occupied, True]):
        if not is_occupied and start is None:
            start = x
        elif is_occupied and start is not None:
            if start > 0 and x < width:
                runs.append((start, x - 1))
            start = None
    return runs


def _split_six(sheet: Image.Image) -> list[Image.Image]:
    width, height = sheet.size
    runs = _empty_runs(sheet)
    cuts: list[int] = []
    for index in range(1, 6):
        target = width * index / 6
        candidates = [
            run
            for run in runs
            if abs(((run[0] + run[1]) / 2) - target) <= width * 0.09
        ]
        if candidates:
            left, right = max(
                candidates,
                key=lambda run: (
                    run[1] - run[0],
                    -abs(((run[0] + run[1]) / 2) - target),
                ),
            )
            cuts.append(round((left + right) / 2))
        else:
            # Large tails can almost touch even when figures do not overlap.
            cuts.append(round(target))

    boundaries = [0, *cuts, width]
    if boundaries != sorted(boundaries) or len(set(boundaries)) != 7:
        raise ValueError(f"Invalid six-panel boundaries: {boundaries}")

    panels: list[Image.Image] = []
    for index in range(6):
        panel = sheet.crop(
            (boundaries[index], 0, boundaries[index + 1], height)
        )
        panels.append(panel.crop(_alpha_bbox(panel)))
    return panels


def _character_scale(slug: str, panels: list[Image.Image]) -> float:
    max_width = max(panel.width for panel in panels)
    max_height = max(panel.height for panel in panels)
    if slug == "baby-pot":
        return min(390 / max_width, 580 / max_height)
    return min(468 / max_width, 704 / max_height)


def build(alpha_dir: Path, output_dir: Path) -> None:
    for slug, _ in CHARACTERS:
        source_path = alpha_dir / f"{slug}-emotion-adults-v2-alpha.png"
        sheet = Image.open(source_path).convert("RGBA")
        panels = _split_six(sheet)
        scale = _character_scale(slug, panels)
        for form, panel in zip(FORMS, panels, strict=True):
            _render_asset(
                panel,
                scale=scale,
                output=(
                    output_dir
                    / f"{slug}-25d-full-bloom-{form}-v2.webp"
                ),
            )


def build_preview(output_dir: Path, preview_path: Path) -> None:
    width = 2100
    row_height = 300
    canvas = Image.new(
        "RGB",
        (width, 90 + row_height * len(CHARACTERS)),
        "#f8f2e8",
    )
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.load_default(size=30)
    name_font = ImageFont.load_default(size=23)
    label_font = ImageFont.load_default(size=17)
    draw.text(
        (42, 24),
        "MONGROO CHARACTER EMOTION ADULTS V2",
        fill="#563f32",
        font=title_font,
    )

    for character_index, (slug, name) in enumerate(CHARACTERS):
        top = 78 + character_index * row_height
        draw.rounded_rectangle(
            (24, top, width - 24, top + row_height - 16),
            radius=24,
            fill="#fffdf8",
            outline="#dfd1bf",
            width=2,
        )
        draw.text(
            (48, top + 30),
            f"{name}\n{slug}",
            fill="#624a39",
            font=name_font,
            spacing=8,
        )
        for form_index, form in enumerate(FORMS):
            asset = Image.open(
                output_dir
                / f"{slug}-25d-full-bloom-{form}-v2.webp"
            ).convert("RGBA")
            asset.thumbnail((250, 232), Image.Resampling.LANCZOS)
            cell_left = 270 + form_index * 298
            sprite_x = cell_left + (250 - asset.width) // 2
            sprite_y = top + 12 + (232 - asset.height)
            canvas.paste(asset, (sprite_x, sprite_y), asset)
            text_width = draw.textlength(form.upper(), font=label_font)
            draw.text(
                (
                    cell_left + (250 - text_width) / 2,
                    top + row_height - 48,
                ),
                form.upper(),
                fill="#806855",
                font=label_font,
            )

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(preview_path, "WEBP", quality=92, method=6)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--alpha-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    build(args.alpha_dir, args.output_dir)
    if args.preview is not None:
        build_preview(args.output_dir, args.preview)


if __name__ == "__main__":
    main()
