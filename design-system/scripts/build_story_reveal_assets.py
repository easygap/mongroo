"""이미지 생성 콘택트 시트에서 런타임 엽서 공개 연출을 만든다.

마스터의 크로마 키는 번들 이미지 도구로 미리 제거한다. 이 스크립트는 3×2 시트
분리, 낮은 알파의 자홍색 테두리 제거, 무손실 WebP 인코딩, QA manifest와 미리보기
생성처럼 결과가 항상 같은 제작 작업만 수행한다. Flutter가 프레임을 바꿀 때
오브젝트가 튀지 않도록 모든 프레임을 같은 512px 캔버스에 유지한다.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

FRAME_COUNT = 6
FRAME_SIZE = 512


def _clean_key_fringe(image: Image.Image) -> Image.Image:
    """키를 제거한 광원 가장자리에 남은 낮은 알파의 적·자홍색만 걷어 낸다."""

    rgba = image.convert("RGBA")
    cleaned: list[tuple[int, int, int, int]] = []
    pixels = (
        rgba.get_flattened_data()
        if hasattr(rgba, "get_flattened_data")
        else rgba.getdata()
    )
    for red, green, blue, alpha in pixels:
        contaminated = (
            alpha < 245
            and red > 110
            and red > green * 1.42
            and red > blue * 1.20
        )
        cleaned.append((0, 0, 0, 0) if contaminated else (red, green, blue, alpha))
    rgba.putdata(cleaned)
    return rgba


def _alpha_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("frame has no visible pixels")
    return bounds


def build(source: Path, output_root: Path, preview_path: Path) -> dict:
    sheet = Image.open(source).convert("RGBA")
    expected = (FRAME_SIZE * 3, FRAME_SIZE * 2)
    if sheet.size != expected:
        raise ValueError(f"expected {expected[0]}x{expected[1]}, got {sheet.size}")

    output_root.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    report_frames: list[dict] = []
    for index in range(FRAME_COUNT):
        column = index % 3
        row = index // 3
        frame = sheet.crop(
            (
                column * FRAME_SIZE,
                row * FRAME_SIZE,
                (column + 1) * FRAME_SIZE,
                (row + 1) * FRAME_SIZE,
            )
        )
        frame = _clean_key_fringe(frame)
        bounds = _alpha_bounds(frame)
        alpha_channel = frame.getchannel("A")
        alpha_pixels = (
            alpha_channel.get_flattened_data()
            if hasattr(alpha_channel, "get_flattened_data")
            else alpha_channel.getdata()
        )
        visible = sum(1 for alpha in alpha_pixels if alpha > 8)
        ratio = visible / (FRAME_SIZE * FRAME_SIZE)
        if not 0.12 <= ratio <= 0.72:
            raise ValueError(f"frame {index} visible ratio out of range: {ratio:.3f}")
        destination = output_root / f"frame-{index:02d}.webp"
        frame.save(destination, "WEBP", lossless=True, method=6)
        frames.append(frame)
        report_frames.append(
            {
                "index": index,
                "file": destination.name,
                "canvas": [FRAME_SIZE, FRAME_SIZE],
                "alpha_bounds": list(bounds),
                "visible_ratio": round(ratio, 4),
            }
        )

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        preview_path,
        save_all=True,
        append_images=frames[1:] + [frames[-1], frames[-1]],
        duration=[150, 150, 150, 170, 190, 420, 420, 420],
        loop=0,
        disposal=2,
    )

    report = {
        "asset_key": "archive_postcard_reveal_v1",
        "source": source.as_posix(),
        "frame_count": FRAME_COUNT,
        "frame_size": [FRAME_SIZE, FRAME_SIZE],
        "timing_ms": [150, 150, 150, 170, 190, 420],
        "story_cue_frame": 3,
        "reveal_cue_frame": 5,
        "reduced_motion_frame": 5,
        "frames": report_frames,
    }
    (output_root / "manifest.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--preview", type=Path, required=True)
    args = parser.parse_args()
    report = build(args.input, args.output_root, args.preview)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
