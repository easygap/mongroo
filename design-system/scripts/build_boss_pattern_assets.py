#!/usr/bin/env python3
"""Imagegen 2×4 시트를 보스 전용 투명 런타임 프레임으로 패키징한다."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


SOURCE_SIZE = (1536, 1024)
RUNTIME_SIZE = (576, 288)
FRAME_COUNT = 8
FRAME_DURATIONS_MS = (150, 110, 90, 90, 80, 100, 80, 80)
GRID_PADDING = 6


def _args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--effect-key", required=True)
    parser.add_argument("--concept-root", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    return parser.parse_args()


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _aggregate_sha256(paths: list[Path]) -> str:
    hashes = "".join(_sha256(path) for path in paths)
    return hashlib.sha256(hashes.encode("ascii")).hexdigest().upper()


def _remove_cyan(cell: Image.Image) -> Image.Image:
    rgb = np.asarray(cell.convert("RGB"), dtype=np.int16)
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    cyan_score = np.minimum(green - red, blue - red)
    core = (cyan_score < 48) | (red > 86) | (green < 115) | (blue < 115)
    alpha = Image.fromarray((core * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(radius=0.65)
    )
    alpha_values = np.asarray(alpha, dtype=np.uint8).copy()
    # Imagegen의 셀 구분선은 반드시 셀 가장자리에 닿는다. 가장자리 3px를 지워
    # 공격 본체가 아닌 표 선이 bbox와 런타임 프레임으로 들어오는 것을 막는다.
    alpha_values[:8, :] = 0
    alpha_values[-8:, :] = 0
    alpha_values[:, :8] = 0
    alpha_values[:, -8:] = 0

    edge_rgb = rgb.astype(np.float32).copy()
    known = core.copy()
    height, width = known.shape
    for _ in range(6):
        color_sum = np.zeros_like(edge_rgb)
        count = np.zeros((height, width), dtype=np.float32)
        for delta_y in (-1, 0, 1):
            for delta_x in (-1, 0, 1):
                if delta_x == 0 and delta_y == 0:
                    continue
                source_y = slice(max(0, -delta_y), min(height, height - delta_y))
                source_x = slice(max(0, -delta_x), min(width, width - delta_x))
                target_y = slice(max(0, delta_y), min(height, height + delta_y))
                target_x = slice(max(0, delta_x), min(width, width + delta_x))
                neighbor_known = known[source_y, source_x]
                color_sum[target_y, target_x] += (
                    edge_rgb[source_y, source_x] * neighbor_known[..., None]
                )
                count[target_y, target_x] += neighbor_known
        new_pixels = (~known) & (count > 0)
        if not np.any(new_pixels):
            break
        edge_rgb[new_pixels] = color_sum[new_pixels] / count[new_pixels][:, None]
        known |= new_pixels
    rgba = np.dstack((np.clip(edge_rgb, 0, 255).astype(np.uint8), alpha_values))
    return Image.fromarray(rgba, "RGBA")


def _foreground_mask(image: Image.Image) -> np.ndarray:
    """시안 키가 아닌 픽셀을 찾는다.

    Imagegen 시트는 지정한 2×4 구성을 지키지만 구분선을 정확히 같은 픽셀에
    놓지는 않는다. 전체 폭·높이를 가로지르는 선만 찾아 셀 경계로 사용하면
    일러스트의 잔상이나 긴 공격 궤적을 구분선으로 오인하지 않는다.
    """

    rgb = np.asarray(image.convert("RGB"), dtype=np.int16)
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    cyan_score = np.minimum(green - red, blue - red)
    return (cyan_score < 48) | (red > 86) | (green < 115) | (blue < 115)


def _find_divider(scores: np.ndarray, expected: int, radius: int) -> int:
    start = max(1, expected - radius)
    end = min(len(scores) - 1, expected + radius + 1)
    window = scores[start:end]
    candidates = np.flatnonzero(window >= 0.72)
    if candidates.size:
        # 두꺼운 선은 연속 후보의 중앙을 택한다. 예상 위치에 가장 가까운
        # 후보부터 고르면 공격 본체가 길게 뻗은 행을 경계로 고르는 일을 막는다.
        positions = candidates + start
        nearest = int(positions[np.argmin(np.abs(positions - expected))])
        left = nearest
        right = nearest
        while left - 1 >= start and scores[left - 1] >= 0.72:
            left -= 1
        while right + 1 < end and scores[right + 1] >= 0.72:
            right += 1
        return (left + right) // 2
    return start + int(np.argmax(window))


def _grid_bounds(sheet: Image.Image) -> tuple[list[int], list[int]]:
    foreground = _foreground_mask(sheet)
    row_scores = foreground.mean(axis=1)
    column_scores = foreground.mean(axis=0)
    row_bounds = [0]
    for index in range(1, 4):
        row_bounds.append(
            _find_divider(row_scores, round(sheet.height * index / 4), 72)
        )
    row_bounds.append(sheet.height)
    column_bounds = [
        0,
        _find_divider(column_scores, round(sheet.width / 2), 72),
        sheet.width,
    ]
    if any(b - a < 160 for a, b in zip(row_bounds, row_bounds[1:])):
        raise ValueError(f"invalid row boundaries: {row_bounds}")
    if any(b - a < 500 for a, b in zip(column_bounds, column_bounds[1:])):
        raise ValueError(f"invalid column boundaries: {column_bounds}")
    return row_bounds, column_bounds


def _fit_frame(image: Image.Image) -> tuple[Image.Image, list[int], float]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("empty alpha frame")
    # 각 셀에서 본체만 다시 확대하면 작은 예고 동작과 큰 접촉 동작의 크기가
    # 같아져 모션 정보가 사라진다. 셀 전체를 같은 기준으로 축소해 Imagegen이
    # 만든 위치·크기 변화를 프레임 사이에 그대로 보존한다.
    scale = min(552 / image.width, 264 / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )
    frame = Image.new("RGBA", RUNTIME_SIZE)
    frame.alpha_composite(
        resized,
        ((RUNTIME_SIZE[0] - resized.width) // 2, (RUNTIME_SIZE[1] - resized.height) // 2),
    )
    alpha = frame.getchannel("A")
    values = (
        alpha.get_flattened_data()
        if hasattr(alpha, "get_flattened_data")
        else alpha.getdata()
    )
    visible = sum(value > 16 for value in values)
    coverage = visible / (RUNTIME_SIZE[0] * RUNTIME_SIZE[1])
    if not 0.0003 <= coverage <= 0.55:
        raise ValueError(f"suspicious alpha coverage {coverage:.4f}")
    return frame, list(bbox), round(coverage, 4)


def _qa(frames: list[Image.Image], destination: Path) -> None:
    cell_size = (288, 144)
    sheet = Image.new("RGB", (4 * cell_size[0], 4 * cell_size[1]))
    draw = ImageDraw.Draw(sheet)
    for background_index, background in enumerate(((18, 24, 26), (244, 239, 218))):
        for index, frame in enumerate(frames):
            canvas = Image.new("RGBA", RUNTIME_SIZE, (*background, 255))
            canvas.alpha_composite(frame)
            preview = canvas.convert("RGB").resize(cell_size, Image.Resampling.LANCZOS)
            x = (index % 4) * cell_size[0]
            y = (background_index * 2 + index // 4) * cell_size[1]
            sheet.paste(preview, (x, y))
            draw.rectangle((x, y, x + cell_size[0] - 1, y + cell_size[1] - 1), outline=(77, 87, 83))
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, format="WEBP", quality=90, method=6)


def _animated_preview(frames: list[Image.Image], destination: Path) -> None:
    previews = []
    for frame in frames:
        canvas = Image.new("RGBA", RUNTIME_SIZE, (18, 24, 26, 255))
        canvas.alpha_composite(frame)
        previews.append(canvas.convert("RGB"))
    destination.parent.mkdir(parents=True, exist_ok=True)
    previews[0].save(
        destination,
        format="WEBP",
        save_all=True,
        append_images=previews[1:],
        duration=list(FRAME_DURATIONS_MS),
        loop=0,
        quality=88,
        method=6,
    )


def main() -> int:
    args = _args()
    with Image.open(args.source) as opened:
        sheet = opened.convert("RGB")
    if sheet.size != SOURCE_SIZE:
        raise ValueError(f"expected {SOURCE_SIZE}, got {sheet.size}")

    source_root = args.concept_root / "sources"
    alpha_root = args.concept_root / "alpha"
    runtime_root = args.runtime_root / f"{args.effect_key.replace('_', '-')}-v1"
    for directory in (source_root, alpha_root, runtime_root):
        directory.mkdir(parents=True, exist_ok=True)
    source_copy = source_root / f"{args.effect_key}-sheet-chroma.png"
    sheet.save(source_copy, format="PNG", optimize=True)

    row_bounds, column_bounds = _grid_bounds(sheet)

    frames: list[Image.Image] = []
    runtime_paths: list[Path] = []
    metrics: list[dict[str, object]] = []
    for index in range(FRAME_COUNT):
        row, column = divmod(index, 2)
        left = column_bounds[column] + (GRID_PADDING if column else 0)
        right = column_bounds[column + 1] - (
            GRID_PADDING if column + 1 < len(column_bounds) - 1 else 0
        )
        top = row_bounds[row] + (GRID_PADDING if row else 0)
        bottom = row_bounds[row + 1] - (
            GRID_PADDING if row + 1 < len(row_bounds) - 1 else 0
        )
        cell = sheet.crop(
            (left, top, right, bottom)
        )
        alpha = _remove_cyan(cell)
        alpha_path = alpha_root / f"frame-{index:02d}.png"
        alpha.save(alpha_path, format="PNG", optimize=True)
        frame, bbox, coverage = _fit_frame(alpha)
        runtime_path = runtime_root / f"frame-{index:02d}.webp"
        frame.save(runtime_path, format="WEBP", quality=88, method=6)
        frames.append(frame)
        runtime_paths.append(runtime_path)
        metrics.append(
            {
                "index": index,
                "duration_ms": FRAME_DURATIONS_MS[index],
                "bbox": bbox,
                "coverage": coverage,
                "alpha_sha256": _sha256(alpha_path),
                "runtime_sha256": _sha256(runtime_path),
            }
        )

    _qa(frames, args.concept_root / "qa" / f"{args.effect_key}-v1-light-dark.webp")
    _animated_preview(
        frames, args.concept_root / "qa" / f"{args.effect_key}-v1-preview.webp"
    )
    manifest = {
        "version": 1,
        "effect_key": args.effect_key,
        "runtime_directory": runtime_root.name,
        "frame_size": list(RUNTIME_SIZE),
        "frame_count": FRAME_COUNT,
        "frame_durations_ms": list(FRAME_DURATIONS_MS),
        "contact_frame": 4,
        "detected_grid": {
            "row_bounds": row_bounds,
            "column_bounds": column_bounds,
            "padding": GRID_PADDING,
        },
        "source_sha256": _sha256(source_copy),
        "runtime_sha256": _aggregate_sha256(runtime_paths),
        "production_candidate": True,
        "production_ready": False,
        "frames": metrics,
    }
    (args.concept_root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"built {args.effect_key}: {FRAME_COUNT} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
