"""탐험 배경을 모바일 게임용 제한 팔레트 에셋으로 마감한다."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


TARGET_SIZE = (1600, 900)
PREVIEW_SIZE = (346, 195)
PALETTE_COLORS = 192


def _crop_to_ratio(image: Image.Image, ratio: float = 16 / 9) -> Image.Image:
    width, height = image.size
    current = width / height
    if abs(current - ratio) < 0.0001:
        return image
    if current > ratio:
        cropped_width = round(height * ratio)
        left = (width - cropped_width) // 2
        return image.crop((left, 0, left + cropped_width, height))
    cropped_height = round(width / ratio)
    top = (height - cropped_height) // 2
    return image.crop((0, top, width, top + cropped_height))


def _noise_score(image: Image.Image) -> float:
    gray = image.convert("L")
    blurred = gray.filter(ImageFilter.GaussianBlur(radius=1.1))
    histogram = ImageChops.difference(gray, blurred).histogram()
    total = sum(histogram)
    weighted = sum(index * count for index, count in enumerate(histogram))
    return weighted / max(total, 1) / 255


def finalize(source: Path, output: Path, preview: Path | None) -> tuple[float, float]:
    with Image.open(source) as opened:
        raw = _crop_to_ratio(opened.convert("RGB"))
        raw = raw.resize(TARGET_SIZE, Image.Resampling.LANCZOS)

    # 단일 픽셀 잡티를 먼저 걷어낸 뒤 디더링 없는 제한 팔레트로 색을 묶는다.
    # 굵은 외곽선과 셀 명암은 유지하면서 생성형 이미지 특유의 모래 질감을 줄인다.
    cleaned = raw.filter(ImageFilter.MedianFilter(size=3))
    cleaned = cleaned.quantize(
        colors=PALETTE_COLORS,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGB")

    output.parent.mkdir(parents=True, exist_ok=True)
    cleaned.save(output, "WEBP", quality=92, method=6)

    raw_mobile = raw.resize(PREVIEW_SIZE, Image.Resampling.LANCZOS)
    clean_mobile = cleaned.resize(PREVIEW_SIZE, Image.Resampling.LANCZOS)
    if preview is not None:
        preview.parent.mkdir(parents=True, exist_ok=True)
        comparison = Image.new("RGB", (PREVIEW_SIZE[0] * 2, PREVIEW_SIZE[1]))
        comparison.paste(raw_mobile, (0, 0))
        comparison.paste(clean_mobile, (PREVIEW_SIZE[0], 0))
        comparison.save(preview, "PNG", optimize=True)
    return _noise_score(raw_mobile), _noise_score(clean_mobile)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()

    raw_score, clean_score = finalize(args.source, args.output, args.preview)
    reduction = 0 if raw_score == 0 else (1 - clean_score / raw_score) * 100
    print(
        f"{args.output}: mobile-noise {raw_score:.5f} -> "
        f"{clean_score:.5f} ({reduction:.1f}% 감소)"
    )


if __name__ == "__main__":
    main()
