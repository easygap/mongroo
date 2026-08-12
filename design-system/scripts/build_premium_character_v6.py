#!/usr/bin/env python3
"""서사 기반 프리미엄 캐릭터를 로스터 공통 캔버스로 내보낸다."""

from __future__ import annotations

import argparse
from pathlib import Path

from build_growth_assets import _alpha_bbox, _render_asset
from PIL import Image, ImageDraw, ImageFont

CHARACTERS = (
    ("nurse-pot", "백화"),
    ("maestro-pot", "세렌"),
)


def build(alpha_dir: Path, character_dir: Path, plant_dir: Path) -> None:
    for slug, _name in CHARACTERS:
        source = Image.open(alpha_dir / f"{slug}-v6.png").convert("RGBA")
        source = source.crop(_alpha_bbox(source))
        scale = min(468 / source.width, 704 / source.height)
        character_asset = character_dir / f"{slug}-v6.webp"
        growth_asset = plant_dir / f"{slug}-25d-full-bloom-v6.webp"
        canonical_growth_asset = plant_dir / f"{slug}-25d-full-bloom.webp"
        _render_asset(source, scale=scale, output=character_asset)
        _render_asset(source, scale=scale, output=growth_asset)
        _render_asset(source, scale=scale, output=canonical_growth_asset)


def _place(
    canvas: Image.Image,
    draw: ImageDraw.ImageDraw,
    path: Path,
    *,
    left: int,
    top: int,
    label: str,
    label_font: ImageFont.ImageFont,
) -> None:
    draw.rounded_rectangle(
        (left, top, left + 290, top + 470),
        radius=22,
        fill="#fffdf8",
        outline="#d9cbb8",
        width=2,
    )
    sprite = Image.open(path).convert("RGBA")
    sprite.thumbnail((264, 398), Image.Resampling.LANCZOS)
    x = left + (290 - sprite.width) // 2
    y = top + 16 + (398 - sprite.height)
    canvas.alpha_composite(sprite, (x, y))
    text_width = draw.textlength(label, font=label_font)
    draw.text(
        (left + (290 - text_width) / 2, top + 428),
        label,
        fill="#5b4739",
        font=label_font,
    )


def build_preview(repo_root: Path, destination: Path) -> None:
    canvas = Image.new("RGBA", (1280, 1060), "#f3ecdf")
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.load_default(size=30)
    label_font = ImageFont.load_default(size=17)
    draw.text(
        (40, 24),
        "MONGROO NARRATIVE-LED CHARACTER IDENTITY V6",
        fill="#49382d",
        font=title_font,
    )

    rows = (
        (
            ("app/assets/characters/gumiho-pot-v3.webp", "STYLE / YEOUBI"),
            ("app/assets/characters/aloof-pot-v2.webp", "STYLE / SEOLHWA"),
            ("app/assets/characters/pretty-pot-v2.webp", "STYLE / BLOOMY"),
            ("app/assets/characters/nurse-pot-v6.webp", "V6 / BAEKHWA / CURVE"),
        ),
        (
            ("app/assets/characters/tsundere-pot-v3.webp", "STYLE / GASIRO"),
            ("app/assets/characters/magical-pot-v2.webp", "STYLE / BYEOLSOL"),
            ("app/assets/characters/student-pot-v2.webp", "STYLE / HARU"),
            ("app/assets/characters/maestro-pot-v6.webp", "V6 / SEREN / ANGLE"),
        ),
    )
    for row_index, row in enumerate(rows):
        top = 80 + row_index * 490
        for column_index, (path, label) in enumerate(row):
            _place(
                canvas,
                draw,
                repo_root / path,
                left=24 + column_index * 312,
                top=top,
                label=label,
                label_font=label_font,
            )
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, "WEBP", quality=94, method=6)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--alpha-dir", type=Path, required=True)
    parser.add_argument("--character-dir", type=Path, required=True)
    parser.add_argument("--plant-dir", type=Path, required=True)
    parser.add_argument("--preview", type=Path, required=True)
    args = parser.parse_args()
    build(args.alpha_dir, args.character_dir, args.plant_dir)
    build_preview(Path.cwd(), args.preview)


if __name__ == "__main__":
    main()
