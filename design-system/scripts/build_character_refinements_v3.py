"""Build the focused Yeoubi/Gasiro v3 sprite refinement.

The v3 pass preserves every v2 asset and replaces only the two character
identities whose appeal needed to read more clearly: alluring gumiho Yeoubi
and caring-but-denying tsundere Gasiro.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from build_character_emotion_adults_v2 import FORMS, _split_six
from build_growth_assets import _alpha_bbox, _render_asset


CHARACTERS = (
    ("gumiho-pot", "Yeoubi"),
    ("tsundere-pot", "Gasiro"),
)


def _stable_scale(panels: list[Image.Image]) -> float:
    return min(
        468 / max(panel.width for panel in panels),
        704 / max(panel.height for panel in panels),
    )


def _keep_primary_component(image: Image.Image) -> Image.Image:
    """Remove disconnected neighbor fragments left by wide-sheet cropping."""

    alpha = image.getchannel("A")
    width, height = image.size
    visible = alpha.point(lambda value: 255 if value >= 64 else 0)
    pixels = visible.load()
    seen: set[tuple[int, int]] = set()
    largest: list[tuple[int, int]] = []

    for y in range(height):
        for x in range(width):
            if pixels[x, y] == 0 or (x, y) in seen:
                continue
            component: list[tuple[int, int]] = []
            queue = deque([(x, y)])
            seen.add((x, y))
            while queue:
                current_x, current_y = queue.popleft()
                component.append((current_x, current_y))
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    point = (next_x, next_y)
                    if (
                        0 <= next_x < width
                        and 0 <= next_y < height
                        and pixels[next_x, next_y] != 0
                        and point not in seen
                    ):
                        seen.add(point)
                        queue.append(point)
            if len(component) > len(largest):
                largest = component

    if not largest:
        raise ValueError("Emotion panel contains no visible character.")
    mask = Image.new("L", image.size, 0)
    mask_pixels = mask.load()
    for x, y in largest:
        mask_pixels[x, y] = 255
    # Restore the original low-alpha antialiasing fringe around the component.
    mask = mask.filter(ImageFilter.MaxFilter(7))
    result = image.copy()
    result.putalpha(ImageChops.multiply(alpha, mask))
    return result.crop(_alpha_bbox(result))


def build(
    main_alpha_dir: Path,
    emotion_alpha_dir: Path,
    character_output_dir: Path,
    plant_output_dir: Path,
) -> None:
    for slug, _ in CHARACTERS:
        main = Image.open(
            main_alpha_dir / f"{slug}-v3-alpha.png"
        ).convert("RGBA")
        main = main.crop(_alpha_bbox(main))
        main_scale = min(468 / main.width, 704 / main.height)
        _render_asset(
            main,
            scale=main_scale,
            output=character_output_dir / f"{slug}-v3.webp",
        )

        sheet = Image.open(
            emotion_alpha_dir / f"{slug}-emotion-adults-v3-alpha.png"
        ).convert("RGBA")
        panels = [
            _keep_primary_component(panel) for panel in _split_six(sheet)
        ]
        scale = _stable_scale(panels)
        for form, panel in zip(FORMS, panels, strict=True):
            _render_asset(
                panel,
                scale=scale,
                output=(
                    plant_output_dir
                    / f"{slug}-25d-full-bloom-{form}-v3.webp"
                ),
            )


def build_preview(
    character_output_dir: Path,
    plant_output_dir: Path,
    preview_path: Path,
) -> None:
    width = 2100
    row_height = 520
    canvas = Image.new(
        "RGB",
        (width, 90 + row_height * len(CHARACTERS)),
        "#f5eee4",
    )
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.load_default(size=30)
    name_font = ImageFont.load_default(size=24)
    label_font = ImageFont.load_default(size=17)
    draw.text(
        (42, 24),
        "MONGROO CHARACTER REFINEMENT V3",
        fill="#563f32",
        font=title_font,
    )

    for index, (slug, name) in enumerate(CHARACTERS):
        top = 78 + index * row_height
        draw.rounded_rectangle(
            (24, top, width - 24, top + row_height - 18),
            radius=24,
            fill="#fffdf8",
            outline="#dfd1bf",
            width=2,
        )
        draw.text(
            (48, top + 28),
            f"{name}\n{slug}\nV3 MAIN",
            fill="#624a39",
            font=name_font,
            spacing=9,
        )
        main = Image.open(
            character_output_dir / f"{slug}-v3.webp"
        ).convert("RGBA")
        main.thumbnail((330, 420), Image.Resampling.LANCZOS)
        canvas.paste(
            main,
            (212 + (330 - main.width) // 2, top + 34),
            main,
        )

        for form_index, form in enumerate(FORMS):
            asset = Image.open(
                plant_output_dir
                / f"{slug}-25d-full-bloom-{form}-v3.webp"
            ).convert("RGBA")
            asset.thumbnail((225, 380), Image.Resampling.LANCZOS)
            cell_left = 545 + form_index * 250
            canvas.paste(
                asset,
                (
                    cell_left + (225 - asset.width) // 2,
                    top + 34 + (380 - asset.height),
                ),
                asset,
            )
            label_width = draw.textlength(form.upper(), font=label_font)
            draw.text(
                (
                    cell_left + (225 - label_width) / 2,
                    top + 450,
                ),
                form.upper(),
                fill="#806855",
                font=label_font,
            )

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(preview_path, "WEBP", quality=94, method=6)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--main-alpha-dir", type=Path, required=True)
    parser.add_argument("--emotion-alpha-dir", type=Path, required=True)
    parser.add_argument("--character-output-dir", type=Path, required=True)
    parser.add_argument("--plant-output-dir", type=Path, required=True)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    build(
        args.main_alpha_dir,
        args.emotion_alpha_dir,
        args.character_output_dir,
        args.plant_output_dir,
    )
    if args.preview is not None:
        build_preview(
            args.character_output_dir,
            args.plant_output_dir,
            args.preview,
        )


if __name__ == "__main__":
    main()
