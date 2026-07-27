"""Build the simplified v2 character portraits into 512x768 app sprites."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_growth_assets import _alpha_bbox, _render_asset


CHARACTERS = (
    ("baby-pot", "뽀또"),
    ("handsome-pot", "로제온"),
    ("pretty-pot", "블루미"),
    ("tsundere-pot", "가시로"),
    ("zombie-pot", "시들잎"),
    ("gumiho-pot", "여우비"),
    ("ninja-pot", "그림싹"),
    ("magical-pot", "별솔"),
    ("aloof-pot", "설화"),
    ("student-pot", "하루"),
)


def build(input_dir: Path, output_dir: Path) -> None:
    for slug, _ in CHARACTERS:
        source = Image.open(input_dir / f"{slug}-v2-alpha.png").convert("RGBA")
        source = source.crop(_alpha_bbox(source))
        max_width, max_height = (
            (320, 480) if slug == "baby-pot" else (468, 704)
        )
        scale = min(max_width / source.width, max_height / source.height)
        _render_asset(
            source,
            scale=scale,
            output=output_dir / f"{slug}-v2.webp",
        )


def build_preview(output_dir: Path, preview_path: Path) -> None:
    canvas = Image.new("RGB", (1600, 1060), "#f2ede3")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=21)

    for index, (slug, name) in enumerate(CHARACTERS):
        column = index % 5
        row = index // 5
        left = 24 + column * 312
        top = 24 + row * 512
        draw.rounded_rectangle(
            (left, top, left + 288, top + 488),
            radius=20,
            fill="#fffdf7",
            outline="#dfd2c0",
            width=2,
        )
        sprite = Image.open(output_dir / f"{slug}-v2.webp").convert("RGBA")
        sprite.thumbnail((270, 420), Image.Resampling.LANCZOS)
        x = left + (288 - sprite.width) // 2
        y = top + 18
        canvas.paste(sprite, (x, y), sprite)
        label = slug
        label_width = draw.textlength(label, font=font)
        draw.text(
            (left + (288 - label_width) / 2, top + 444),
            label,
            fill="#3b1f06",
            font=font,
        )

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(preview_path, "WEBP", quality=94, method=6)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    build(args.input_dir, args.output_dir)
    if args.preview is not None:
        build_preview(args.output_dir, args.preview)


if __name__ == "__main__":
    main()
