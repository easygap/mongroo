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
    seed_scale,
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
    full_bloom_heights: list[int] = []
    for form in FORMS:
        sheet = Image.open(
            source_dir / slug / f"{form}-route-chroma-v1-alpha.png"
        ).convert("RGBA")
        panels = _split_character_route(sheet)
        scale = _route_scale(panels)
        full_bloom_heights.append(round(panels[-1].height * scale))
        for phase, panel in zip(PHASES, panels, strict=True):
            _render_asset(
                panel,
                scale=scale,
                output=output_dir / f"{slug}-25d-{phase}-{form}.webp",
            )

    # 씨앗 낱장은 캔버스를 채우도록 그려져 있다. 시트에서 뽑은 2~5단계와
    # 같은 자리에 그대로 놓으면 씨앗이 다 자란 모습만 해지고, 홈·도감에서
    # 씨앗 → 새싹으로 갈 때 캐릭터가 작아진다.
    seed = Image.open(source_dir / slug / "shared-seed-v1-alpha.png").convert(
        "RGBA"
    )
    seed = seed.crop(_alpha_bbox(seed))
    _render_asset(
        seed,
        scale=seed_scale(seed, max(full_bloom_heights)),
        output=output_dir / f"{slug}-25d-seed.webp",
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


def build_overview(
    preview_dir: Path, slugs: list[str], output_path: Path
) -> None:
    """열 계보의 미리보기를 2열로 붙인 README용 한 장.

    낱장 미리보기와 같은 그림을 절반 크기로 붙인다. 순서는 매니페스트를
    따르므로 계보를 다시 구우면 이 장도 같은 자리에서 갱신된다.
    """

    if not slugs:
        raise ValueError("overview requires at least one lineage")
    first = Image.open(preview_dir / f"{slugs[0]}-growth-preview.webp")
    cell = (first.width // 2, first.height // 2)
    rows = (len(slugs) + 1) // 2
    canvas = Image.new("RGB", (cell[0] * 2, cell[1] * rows), "#fff8ea")
    for index, slug in enumerate(slugs):
        sheet = Image.open(preview_dir / f"{slug}-growth-preview.webp").convert(
            "RGB"
        )
        row, column = divmod(index, 2)
        canvas.paste(
            sheet.resize(cell, Image.Resampling.LANCZOS),
            (column * cell[0], row * cell[1]),
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, "WEBP", quality=92, method=6)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--preview-dir", type=Path)
    parser.add_argument(
        "--overview",
        type=Path,
        help="README용 계보 모음 한 장을 쓸 경로. --preview-dir와 함께 쓴다.",
    )
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    built: list[str] = []
    for lineage in manifest["lineages"]:
        slug = lineage["slug"]
        build_lineage(args.source_dir, args.output_dir, slug)
        built.append(slug)
        if args.preview_dir is not None:
            build_preview(
                args.output_dir,
                args.preview_dir / f"{slug}-growth-preview.webp",
                slug,
            )
    if args.overview is not None:
        if args.preview_dir is None:
            parser.error("--overview는 --preview-dir가 있어야 만들 수 있어요.")
        available = [
            slug
            for slug in built
            if (args.preview_dir / f"{slug}-growth-preview.webp").exists()
        ]
        build_overview(args.preview_dir, available, args.overview)


if __name__ == "__main__":
    main()
