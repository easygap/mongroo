"""Build app-ready Mongroo growth assets from transparent ImageGen route sheets.

The input directory contains a shared seed, an observing sprout, and six
humanoid-growth route sheets.  Every route sheet is split into four stages and
normalized without changing the relative scale inside that route.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


CANVAS = (512, 768)
BASELINE_Y = 718
FORMS = ("sunny", "rainy", "ember", "moonlit", "sparkling", "mosaic")
PHASES = ("sprout", "branching", "bloom", "full-bloom")
PREVIEW_PHASES = ("SEED", "SPROUT", "BRANCH", "BLOOM", "FULL")


def _alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("The source contains no visible pixels.")
    return bbox


def _split_route(sheet: Image.Image) -> list[Image.Image]:
    width, height = sheet.size
    alpha = sheet.getchannel("A")
    # Soft chroma cleanup can leave almost invisible alpha noise in the
    # background.  Treat a column as occupied only when it contains a visible
    # pixel, then split at the three wide gutters between generated figures.
    occupied = [
        alpha.crop((x, 0, x + 1, height)).getextrema()[1] >= 64
        for x in range(width)
    ]
    empty_runs: list[tuple[int, int]] = []
    run_start: int | None = None
    for x, is_occupied in enumerate([*occupied, True]):
        if not is_occupied and run_start is None:
            run_start = x
        elif is_occupied and run_start is not None:
            if run_start > 0 and x < width and x - run_start >= 12:
                empty_runs.append((run_start, x - 1))
            run_start = None

    if len(empty_runs) < 3:
        raise ValueError(
            "Route sheet must contain four figures separated by visible gutters."
        )
    gutters = sorted(
        sorted(empty_runs, key=lambda run: run[1] - run[0], reverse=True)[:3]
    )
    boundaries = [0]
    boundaries.extend(round((left + right) / 2) for left, right in gutters)
    boundaries.append(width)

    panels: list[Image.Image] = []
    for index in range(4):
        left = boundaries[index]
        right = boundaries[index + 1]
        panel = sheet.crop((left, 0, right, height))
        panels.append(panel.crop(_alpha_bbox(panel)))
    return panels


def _render_asset(
    source: Image.Image,
    *,
    scale: float,
    output: Path,
) -> None:
    width = max(1, round(source.width * scale))
    height = max(1, round(source.height * scale))
    # Resize premultiplied RGBA so the chroma RGB left in fully transparent
    # pixels cannot bleed back into antialiased character edges.
    resized = (
        source.convert("RGBa")
        .resize((width, height), Image.Resampling.LANCZOS)
        .convert("RGBA")
    )
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    x = (CANVAS[0] - width) // 2
    y = BASELINE_Y - height
    if x < 0 or y < 0 or x + width > CANVAS[0] or y + height > CANVAS[1]:
        raise ValueError(f"{output.name} does not fit the 512x768 canvas.")
    canvas.alpha_composite(resized, (x, y))
    transparent_mask = canvas.getchannel("A").point(
        lambda alpha: 255 if alpha == 0 else 0
    )
    canvas.paste((0, 0, 0, 0), mask=transparent_mask)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, "WEBP", lossless=True, method=6)


def _route_scale(panels: list[Image.Image]) -> float:
    max_width = max(panel.width for panel in panels)
    max_height = max(panel.height for panel in panels)
    stage_two_width = panels[0].width
    return min(
        420 / stage_two_width,
        468 / max_width,
        704 / max_height,
    )


def build(alpha_dir: Path, output_dir: Path) -> None:
    for source_name, asset_name in (
        ("shared-seed-v2-alpha.png", "basic-sprout-25d-seed.webp"),
        (
            "shared-sprout-v2-alpha.png",
            "basic-sprout-25d-sprout.webp",
        ),
    ):
        shared = Image.open(alpha_dir / source_name).convert("RGBA")
        shared = shared.crop(_alpha_bbox(shared))
        shared_scale = min(420 / shared.width, 704 / shared.height)
        _render_asset(
            shared,
            scale=shared_scale,
            output=output_dir / asset_name,
        )

    for form in FORMS:
        sheet_path = alpha_dir / f"{form}-route-chroma-v2-alpha.png"
        sheet = Image.open(sheet_path).convert("RGBA")
        panels = _split_route(sheet)
        scale = _route_scale(panels)
        for phase, panel in zip(PHASES, panels, strict=True):
            _render_asset(
                panel,
                scale=scale,
                output=output_dir / f"basic-sprout-25d-{phase}-{form}.webp",
            )


def build_preview(output_dir: Path, preview_path: Path) -> None:
    canvas = Image.new("RGB", (1800, 1120), "#fff8ea")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=24)
    small_font = ImageFont.load_default(size=16)
    seed = Image.open(output_dir / "basic-sprout-25d-seed.webp").convert("RGBA")

    for form_index, form in enumerate(FORMS):
        group_x = 40 + (form_index % 2) * 880
        group_y = 32 + (form_index // 2) * 360
        draw.rounded_rectangle(
            (group_x, group_y, group_x + 840, group_y + 328),
            radius=24,
            fill="#fffdf7",
            outline="#ead7bd",
            width=2,
        )
        draw.text(
            (group_x + 26, group_y + 18),
            form.upper(),
            fill="#694f3c",
            font=font,
        )
        assets = [seed]
        assets.extend(
            Image.open(
                output_dir / f"basic-sprout-25d-{phase}-{form}.webp"
            ).convert("RGBA")
            for phase in PHASES
        )
        for stage_index, asset in enumerate(assets):
            x = group_x + 18 + stage_index * 164
            y = group_y + 70
            thumbnail = asset.copy()
            thumbnail.thumbnail((152, 228), Image.Resampling.LANCZOS)
            canvas.paste(
                thumbnail,
                (x + (152 - thumbnail.width) // 2, y),
                thumbnail,
            )
            label = PREVIEW_PHASES[stage_index]
            text_width = draw.textlength(label, font=small_font)
            draw.text(
                (x + (152 - text_width) / 2, group_y + 298),
                label,
                fill="#8a6d55",
                font=small_font,
            )

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(preview_path, "WEBP", quality=92, method=6)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--alpha-dir",
        type=Path,
        required=True,
        help="Directory containing transparent ImageGen route sheets.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Flutter asset output directory.",
    )
    parser.add_argument(
        "--preview",
        type=Path,
        help="Optional contact-sheet output path.",
    )
    args = parser.parse_args()
    build(args.alpha_dir, args.output_dir)
    if args.preview is not None:
        build_preview(args.output_dir, args.preview)


if __name__ == "__main__":
    main()
