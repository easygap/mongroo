#!/usr/bin/env python3
"""Build runtime frames from reviewed expedition combat VFX sheets.

The source contract is intentionally small: every RGBA sheet is a 2 x 4 grid
whose cells share one camera and one pair of attack anchors.  Chroma removal is
kept outside this script so a reviewer can inspect the matte before packaging.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path
import sys

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - dependency failure is actionable.
    raise SystemExit("Pillow is required to build combat VFX sprites.") from exc


SHEET_COLUMNS = 2
SHEET_ROWS = 4
FRAME_COUNT = SHEET_COLUMNS * SHEET_ROWS
SOURCE_SIZE = (1536, 1024)
CELL_SIZE = (SOURCE_SIZE[0] // SHEET_COLUMNS, SOURCE_SIZE[1] // SHEET_ROWS)
VERTICAL_BLEED = 64
RUNTIME_SIZE = (576, 288)
MIN_COMPONENT_RATIO = 0.001
EFFECT_KEYS = (
    "care-vines",
    "safe-guard",
    "ember-arc",
    "prism-burst",
    "mist-dash",
    "insight-arc",
    "echo-wave",
    "enemy-wave",
)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Slice reviewed 2x4 combat VFX sheets into transparent WebP frames."
    )
    parser.add_argument(
        "--source-root",
        type=Path,
        default=Path("design-system/concepts/adventure-combat-vfx-v1/alpha"),
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("app/assets/adventure/effects"),
    )
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="Validate the source sheets without replacing runtime assets.",
    )
    return parser.parse_args()


def _component_mask(
    alpha: Image.Image,
    *,
    core_top: int,
    core_bottom: int,
) -> tuple[Image.Image, int]:
    """Drop only isolated sub-pixel debris while retaining deliberate shards.

    VFX legitimately contains several disconnected leaves, crystals, and impact
    rays.  A tiny area-ratio floor is therefore safer than keeping only the
    largest component, and remains independent from a particular frame.
    """

    width, height = alpha.size
    pixels = alpha.load()
    visited = bytearray(width * height)
    keep = bytearray(width * height)
    minimum_area = max(20, round(width * height * MIN_COMPONENT_RATIO))
    removed = 0

    for y in range(height):
        for x in range(width):
            index = y * width + x
            if visited[index] or pixels[x, y] <= 16:
                visited[index] = 1
                continue
            queue = deque([(x, y)])
            visited[index] = 1
            component: list[int] = []
            while queue:
                current_x, current_y = queue.popleft()
                current_index = current_y * width + current_x
                component.append(current_index)
                for next_y in range(max(0, current_y - 1), min(height, current_y + 2)):
                    for next_x in range(max(0, current_x - 1), min(width, current_x + 2)):
                        next_index = next_y * width + next_x
                        if visited[next_index]:
                            continue
                        visited[next_index] = 1
                        if pixels[next_x, next_y] > 16:
                            queue.append((next_x, next_y))
            core_pixels = sum(
                1
                for component_index in component
                if core_top <= component_index // width < core_bottom
            )
            belongs_to_frame = core_pixels / len(component) >= 0.65
            if len(component) >= minimum_area and belongs_to_frame:
                for component_index in component:
                    keep[component_index] = 1
            else:
                removed += 1

    cleaned = Image.new("L", alpha.size, 0)
    cleaned_pixels = cleaned.load()
    for y in range(height):
        for x in range(width):
            if keep[y * width + x]:
                cleaned_pixels[x, y] = pixels[x, y]
    return cleaned, removed


def _frame_cells(sheet: Image.Image):
    """Yield cells with vertical bleed so contact-sheet overlap is recoverable.

    Image generators occasionally let a large impact leaf or ray cross a row
    boundary.  Reading a small bleed and keeping only components that belong to
    the cell core restores that edge without importing the next frame.
    """

    cell_width, cell_height = CELL_SIZE
    for row in range(SHEET_ROWS):
        for column in range(SHEET_COLUMNS):
            source_top = max(0, row * cell_height - VERTICAL_BLEED)
            source_bottom = min(
                sheet.height,
                (row + 1) * cell_height + VERTICAL_BLEED,
            )
            source = sheet.crop(
                (
                    column * cell_width,
                    source_top,
                    (column + 1) * cell_width,
                    source_bottom,
                )
            )
            frame = Image.new(
                "RGBA",
                (cell_width, cell_height + VERTICAL_BLEED * 2),
                (0, 0, 0, 0),
            )
            paste_top = VERTICAL_BLEED - min(
                VERTICAL_BLEED,
                row * cell_height,
            )
            frame.alpha_composite(source, (0, paste_top))
            yield frame


def _validate_frame(frame: Image.Image, effect_key: str, frame_index: int) -> dict:
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"{effect_key} frame {frame_index}: empty alpha matte")
    values = (
        alpha.get_flattened_data()
        if hasattr(alpha, "get_flattened_data")
        else alpha.getdata()
    )
    opaque_pixels = sum(1 for value in values if value > 16)
    coverage = opaque_pixels / (frame.width * frame.height)
    if coverage < 0.003 or coverage > 0.72:
        raise ValueError(
            f"{effect_key} frame {frame_index}: suspicious coverage {coverage:.4f}"
        )
    touches_edge = bbox[0] == 0 or bbox[1] == 0 or bbox[2] == frame.width or bbox[3] == frame.height
    if touches_edge:
        raise ValueError(f"{effect_key} frame {frame_index}: effect touches a cell edge")
    return {
        "index": frame_index,
        "coverage": round(coverage, 4),
        "bbox": list(bbox),
    }


def _build_effect(source: Path, destination: Path, report_only: bool) -> dict:
    with Image.open(source) as opened:
        sheet = opened.convert("RGBA")
    if sheet.size != SOURCE_SIZE:
        raise ValueError(f"{source}: expected {SOURCE_SIZE}, got {sheet.size}")

    effect_key = source.stem
    frame_reports = []
    output_frames: list[Image.Image] = []
    removed_components = 0
    for frame_index, frame in enumerate(_frame_cells(sheet)):
        cleaned_alpha, removed = _component_mask(
            frame.getchannel("A"),
            core_top=VERTICAL_BLEED,
            core_bottom=VERTICAL_BLEED + CELL_SIZE[1],
        )
        frame.putalpha(cleaned_alpha)
        removed_components += removed
        frame_reports.append(_validate_frame(frame, effect_key, frame_index))
        output_frames.append(
            frame.resize(RUNTIME_SIZE, Image.Resampling.LANCZOS)
        )

    if not report_only:
        destination.mkdir(parents=True, exist_ok=True)
        for existing in destination.glob("frame-*.webp"):
            existing.unlink()
        for frame_index, frame in enumerate(output_frames):
            frame.save(
                destination / f"frame-{frame_index:02d}.webp",
                format="WEBP",
                quality=90,
                method=4,
            )

    return {
        "effect_key": effect_key.replace("-", "_"),
        "directory": effect_key,
        "frame_count": FRAME_COUNT,
        "frame_size": list(RUNTIME_SIZE),
        "removed_tiny_components": removed_components,
        "frames": frame_reports,
    }


def main() -> int:
    args = _parse_args()
    reports = []
    try:
        for effect_key in EFFECT_KEYS:
            source = args.source_root / f"{effect_key}.png"
            if not source.exists():
                raise FileNotFoundError(f"missing reviewed alpha sheet: {source}")
            reports.append(
                _build_effect(source, args.output_root / effect_key, args.report_only)
            )
    except (OSError, ValueError) as exc:
        print(f"combat-vfx build failed: {exc}", file=sys.stderr)
        return 1

    manifest = {
        "version": 1,
        "layout": {"columns": SHEET_COLUMNS, "rows": SHEET_ROWS},
        "effects": reports,
    }
    if not args.report_only:
        args.output_root.mkdir(parents=True, exist_ok=True)
        (args.output_root / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    mode = "validated" if args.report_only else "built"
    print(f"combat-vfx {mode}: {len(reports)} effects, {len(reports) * FRAME_COUNT} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
