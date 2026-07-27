"""Build Mongroo's emotion-archetype adult sprite set.

Each character has three transparent source sheets (idle, diary, grow). Every
sheet contains the same six emotion routes in canonical order. This builder
splits the sheets, keeps one stable scale for each route across its three
states, writes app-ready 512x768 lossless WebP assets, and creates visual QA
contact sheets.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from build_character_emotion_adults_v2 import FORMS, _split_six
from build_growth_assets import _alpha_bbox, _render_asset


STATES = ("idle", "diary", "grow")
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


def _remove_edge_fragments(image: Image.Image) -> Image.Image:
    """Drop disconnected pieces borrowed from a neighboring wide-sheet panel.

    Wide tails, coats, and bloom effects may cross an exact sixth boundary.
    The character is always the largest connected component. Smaller
    components that touch a vertical crop edge belong to the adjacent route;
    interior floating petals and magic effects are intentionally retained.
    """

    alpha = image.getchannel("A")
    visible = alpha.point(lambda value: 255 if value >= 64 else 0)
    pixels = visible.load()
    width, height = image.size
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []

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
            components.append(component)

    if not components:
        raise ValueError("Emotion panel contains no visible character.")
    primary = max(components, key=len)
    retained = [primary]
    for component in components:
        if component is primary:
            continue
        left = min(point[0] for point in component)
        right = max(point[0] for point in component)
        if left <= 1 or right >= width - 2:
            continue
        retained.append(component)

    mask = Image.new("L", image.size, 0)
    mask_pixels = mask.load()
    for component in retained:
        for x, y in component:
            mask_pixels[x, y] = 255
    mask = mask.filter(ImageFilter.MaxFilter(7))
    result = image.copy()
    result.putalpha(ImageChops.multiply(alpha, mask))
    return result.crop(_alpha_bbox(result))


def _clip_edge_effect(
    image: Image.Image,
    *,
    left_fraction: float = 0,
    right_fraction: float = 0,
) -> Image.Image:
    """Trim a known cross-panel effect while leaving the centered body intact."""

    alpha = image.getchannel("A")
    mask = Image.new("L", image.size, 255)
    draw = ImageDraw.Draw(mask)
    if left_fraction > 0:
        draw.rectangle(
            (0, 0, round(image.width * left_fraction), image.height),
            fill=0,
        )
    if right_fraction > 0:
        draw.rectangle(
            (
                round(image.width * (1 - right_fraction)),
                0,
                image.width,
                image.height,
            ),
            fill=0,
        )
    result = image.copy()
    result.putalpha(ImageChops.multiply(alpha, mask))
    return result.crop(_alpha_bbox(result))


def _route_scale(slug: str, panels: list[Image.Image]) -> float:
    """Keep a route's apparent size stable while its pose changes."""

    max_width = max(panel.width for panel in panels)
    max_height = max(panel.height for panel in panels)
    if slug == "baby-pot":
        return min(390 / max_width, 580 / max_height)
    return min(468 / max_width, 704 / max_height)


def _asset_path(
    output_dir: Path,
    *,
    slug: str,
    form: str,
    state: str,
) -> Path:
    return (
        output_dir
        / f"{slug}-25d-full-bloom-{form}-v4-{state}.webp"
    )


def build(source_root: Path, output_dir: Path) -> None:
    for slug, _ in CHARACTERS:
        state_panels: dict[str, list[Image.Image]] = {}
        for state in STATES:
            source_path = source_root / slug / f"{state}-alpha.png"
            sheet = Image.open(source_path).convert("RGBA")
            panels = [
                _remove_edge_fragments(panel) for panel in _split_six(sheet)
            ]
            if slug == "gumiho-pot" and state == "grow":
                panels[1] = _clip_edge_effect(
                    panels[1],
                    left_fraction=0.19,
                )
                panels[4] = _clip_edge_effect(
                    panels[4],
                    right_fraction=0.19,
                )
            if slug == "gumiho-pot" and state == "diary":
                panels[4] = _clip_edge_effect(
                    panels[4],
                    right_fraction=0.19,
                )
            state_panels[state] = panels

        for form_index, form in enumerate(FORMS):
            route_panels = [
                state_panels[state][form_index] for state in STATES
            ]
            scale = _route_scale(slug, route_panels)
            for state, panel in zip(STATES, route_panels, strict=True):
                _render_asset(
                    panel,
                    scale=scale,
                    output=_asset_path(
                        output_dir,
                        slug=slug,
                        form=form,
                        state=state,
                    ),
                )


def _draw_sprite(
    canvas: Image.Image,
    asset: Image.Image,
    *,
    left: int,
    top: int,
    width: int,
    height: int,
) -> None:
    sprite = asset.copy()
    sprite.thumbnail((width, height), Image.Resampling.LANCZOS)
    x = left + (width - sprite.width) // 2
    y = top + height - sprite.height
    canvas.paste(sprite, (x, y), sprite)


def build_character_previews(
    source_root: Path,
    output_dir: Path,
) -> None:
    width = 1640
    header_height = 86
    label_width = 180
    cell_width = 232
    row_height = 300
    title_font = ImageFont.load_default(size=30)
    name_font = ImageFont.load_default(size=22)
    label_font = ImageFont.load_default(size=17)

    for slug, name in CHARACTERS:
        canvas = Image.new(
            "RGB",
            (width, header_height + row_height * len(STATES) + 28),
            "#f4eee5",
        )
        draw = ImageDraw.Draw(canvas)
        draw.text(
            (32, 22),
            f"{name.upper()} / {slug.upper()} / EMOTION ARCHETYPES V4",
            fill="#543f34",
            font=title_font,
        )
        for state_index, state in enumerate(STATES):
            top = header_height + state_index * row_height
            draw.rounded_rectangle(
                (18, top, width - 18, top + row_height - 12),
                radius=22,
                fill="#fffdf8",
                outline="#dfd1bf",
                width=2,
            )
            draw.text(
                (42, top + 115),
                state.upper(),
                fill="#624a39",
                font=name_font,
            )
            for form_index, form in enumerate(FORMS):
                left = label_width + form_index * cell_width
                asset = Image.open(
                    _asset_path(
                        output_dir,
                        slug=slug,
                        form=form,
                        state=state,
                    )
                ).convert("RGBA")
                _draw_sprite(
                    canvas,
                    asset,
                    left=left,
                    top=top + 8,
                    width=cell_width - 12,
                    height=242,
                )
                text_width = draw.textlength(
                    form.upper(),
                    font=label_font,
                )
                draw.text(
                    (
                        left + (cell_width - 12 - text_width) / 2,
                        top + 258,
                    ),
                    form.upper(),
                    fill="#806855",
                    font=label_font,
                )

        preview_path = source_root / slug / "preview.webp"
        preview_path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(preview_path, "WEBP", quality=94, method=6)


def build_idle_overview(
    output_dir: Path,
    preview_path: Path,
) -> None:
    width = 2100
    row_height = 300
    canvas = Image.new(
        "RGB",
        (width, 90 + row_height * len(CHARACTERS)),
        "#f4eee5",
    )
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.load_default(size=30)
    name_font = ImageFont.load_default(size=22)
    label_font = ImageFont.load_default(size=17)
    draw.text(
        (42, 24),
        "MONGROO EMOTION ARCHETYPES V4 / IDLE",
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
                _asset_path(
                    output_dir,
                    slug=slug,
                    form=form,
                    state="idle",
                )
            ).convert("RGBA")
            cell_left = 270 + form_index * 298
            _draw_sprite(
                canvas,
                asset,
                left=cell_left,
                top=top + 10,
                width=250,
                height=232,
            )
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
    canvas.save(preview_path, "WEBP", quality=94, method=6)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--idle-preview", type=Path)
    args = parser.parse_args()

    build(args.source_root, args.output_dir)
    build_character_previews(args.source_root, args.output_dir)
    if args.idle_preview is not None:
        build_idle_overview(args.output_dir, args.idle_preview)


if __name__ == "__main__":
    main()
