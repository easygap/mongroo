#!/usr/bin/env python3
"""Imagegen 2×2 시트를 엉킴 몸체 4상태 투명 WebP로 패키징한다."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


RUNTIME_SIZE = (768, 768)
MOBILE_SIZE = (576, 576)
STATES = ("idle", "attack", "hit", "release")


def _args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--tangle-code", required=True)
    parser.add_argument("--concept-root", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    return parser.parse_args()


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _remove_cyan(cell: Image.Image) -> Image.Image:
    rgb = np.asarray(cell.convert("RGB"), dtype=np.int16)
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    cyan_likeness = np.minimum(green - red, blue - red)
    foreground = (cyan_likeness < 55) | (red > 88) | (green < 110) | (blue < 110)
    alpha = Image.fromarray((foreground * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(radius=0.72)
    )
    alpha_values = np.asarray(alpha, dtype=np.uint8).copy()
    alpha_values[:6, :] = 0
    alpha_values[-6:, :] = 0
    alpha_values[:, :6] = 0
    alpha_values[:, -6:] = 0

    # 반투명 가장자리의 cyan RGB가 dark 배경에서 번지지 않도록 안쪽 색을 확장한다.
    edge_rgb = rgb.astype(np.float32).copy()
    known = foreground.copy()
    height, width = known.shape
    for _ in range(7):
        color_sum = np.zeros_like(edge_rgb)
        count = np.zeros((height, width), dtype=np.float32)
        for delta_y in (-1, 0, 1):
            for delta_x in (-1, 0, 1):
                if delta_x == delta_y == 0:
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


def _fit(image: Image.Image, size: tuple[int, int]) -> tuple[Image.Image, list[int], float]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("empty alpha state")
    cropped = image.crop(bbox)
    scale = min((size[0] - 44) / cropped.width, (size[1] - 44) / cropped.height)
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.Resampling.LANCZOS,
    )
    frame = Image.new("RGBA", size)
    # 네 상태 모두 같은 발끝 기준선을 써 공격·피격 전환에서 발밑이 튀지 않는다.
    frame.alpha_composite(resized, ((size[0] - resized.width) // 2, size[1] - 22 - resized.height))
    visible = np.count_nonzero(np.asarray(frame.getchannel("A")) > 16)
    coverage = visible / (size[0] * size[1])
    if not 0.04 <= coverage <= 0.70:
        raise ValueError(f"suspicious alpha coverage {coverage:.4f}")
    return frame, list(bbox), round(coverage, 4)


def _qa(frames: list[Image.Image], destination: Path) -> None:
    cell_size = (288, 288)
    sheet = Image.new("RGB", (4 * cell_size[0], 2 * cell_size[1]))
    draw = ImageDraw.Draw(sheet)
    for row, background in enumerate(((20, 25, 27), (246, 241, 220))):
        for index, frame in enumerate(frames):
            canvas = Image.new("RGBA", RUNTIME_SIZE, (*background, 255))
            canvas.alpha_composite(frame)
            preview = canvas.convert("RGB").resize(cell_size, Image.Resampling.LANCZOS)
            x, y = index * cell_size[0], row * cell_size[1]
            sheet.paste(preview, (x, y))
            draw.rectangle((x, y, x + 287, y + 287), outline=(76, 87, 83))
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, "WEBP", quality=90, method=6)


def main() -> int:
    args = _args()
    with Image.open(args.source) as opened:
        sheet = opened.convert("RGB")
    if sheet.width < 1024 or sheet.height < 1024:
        raise ValueError(f"source sheet is too small: {sheet.size}")
    cell_width = sheet.width // 2
    cell_height = sheet.height // 2

    source_root = args.concept_root / "sources"
    alpha_root = args.concept_root / "alpha"
    for directory in (source_root, alpha_root, args.runtime_root):
        directory.mkdir(parents=True, exist_ok=True)
    source_copy = source_root / f"{args.tangle_code}-sheet-chroma.png"
    sheet.save(source_copy, "PNG", optimize=True)

    frames: list[Image.Image] = []
    metrics: list[dict[str, object]] = []
    for index, state in enumerate(STATES):
        row, column = divmod(index, 2)
        cell = sheet.crop(
            (
                column * cell_width,
                row * cell_height,
                (column + 1) * cell_width,
                (row + 1) * cell_height,
            )
        )
        alpha = _remove_cyan(cell)
        alpha_path = alpha_root / f"{args.tangle_code}-{state}.png"
        alpha.save(alpha_path, "PNG", optimize=True)
        frame, bbox, coverage = _fit(alpha, RUNTIME_SIZE)
        runtime_path = args.runtime_root / f"tangle-{args.tangle_code}-{state}-v1.webp"
        frame.save(runtime_path, "WEBP", quality=90, method=6, exact=True)
        mobile = frame.resize(MOBILE_SIZE, Image.Resampling.LANCZOS)
        mobile_path = runtime_path.with_name(f"{runtime_path.stem}-mobile.webp")
        mobile.save(mobile_path, "WEBP", quality=88, method=6, exact=True)
        frames.append(frame)
        metrics.append(
            {
                "state": state,
                "bbox": bbox,
                "coverage": coverage,
                "runtime_sha256": _sha256(runtime_path),
                "mobile_sha256": _sha256(mobile_path),
            }
        )

    _qa(frames, args.concept_root / "qa" / f"{args.tangle_code}-states-light-dark.webp")
    manifest = {
        "version": 1,
        "tangle_code": args.tangle_code,
        "states": list(STATES),
        "frame_size": list(RUNTIME_SIZE),
        "mobile_size": list(MOBILE_SIZE),
        "source_sha256": _sha256(source_copy),
        "production_candidate": True,
        "production_ready": False,
        "frames": metrics,
    }
    (args.concept_root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"built {args.tangle_code}: {len(STATES)} states")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
