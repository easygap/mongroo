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

#: 만개 키를 1로 둔 씨앗 목표 키.
#:
#: 씨앗은 시트가 아니라 낱장으로 들어온다. 낱장은 파일마다 인물이 캔버스를
#: 채우도록 그려져서 칸 사이의 상대 키 정보가 없고, 그대로 캔버스에 맞춰
#: 키우면 씨앗이 성인만 해진다. 그러면 홈과 도감에서 씨앗 → 새싹으로 갈 때
#: 캐릭터가 오히려 작아진다.
#:
#: 값은 `build_premium_character_v6_growth.PHASE_HEIGHT_RATIO["seed"]`와
#: 같다 — 사람형 계보 둘의 실측 평균이다.
SEED_HEIGHT_RATIO = 0.23


def seed_scale(seed: Image.Image, full_bloom_height: int) -> float:
    """만개 키를 기준으로 씨앗 배율을 정한다. 입력은 이미 crop된 원본이다."""

    target = max(1, round(full_bloom_height * SEED_HEIGHT_RATIO))
    return target / seed.height


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
    full_bloom_heights: list[int] = []
    for form in FORMS:
        sheet_path = alpha_dir / f"{form}-route-chroma-v2-alpha.png"
        sheet = Image.open(sheet_path).convert("RGBA")
        panels = _split_route(sheet)
        scale = _route_scale(panels)
        full_bloom_heights.append(round(panels[-1].height * scale))
        for phase, panel in zip(PHASES, panels, strict=True):
            _render_asset(
                panel,
                scale=scale,
                output=output_dir / f"basic-sprout-25d-{phase}-{form}.webp",
            )

    sprout = Image.open(alpha_dir / "shared-sprout-v2-alpha.png").convert("RGBA")
    sprout = sprout.crop(_alpha_bbox(sprout))
    _render_asset(
        sprout,
        scale=min(420 / sprout.width, 704 / sprout.height),
        output=output_dir / "basic-sprout-25d-sprout.webp",
    )

    # 씨앗은 다 자란 키를 기준으로 줄인다. 캔버스에 맞춰 키우면 새싹보다
    # 커져서 성장이 거꾸로 읽힌다.
    seed = Image.open(alpha_dir / "shared-seed-v2-alpha.png").convert("RGBA")
    seed = seed.crop(_alpha_bbox(seed))
    _render_asset(
        seed,
        scale=seed_scale(seed, max(full_bloom_heights)),
        output=output_dir / "basic-sprout-25d-seed.webp",
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
