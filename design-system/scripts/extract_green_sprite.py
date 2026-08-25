#!/usr/bin/env python3
"""초록 크로마로 받은 캐릭터 원화에서 배경을 지우고 투명 마스터를 만든다.

`extract_magenta_sprite.py`와 같은 일을 하되 키 색이 초록이다. v6·v7 캐릭터
프롬프트가 `solid #00FF00 background`를 요구하므로 캐릭터 쪽은 이쪽을 쓴다.

거리 기반으로 자르지 않고 **초록 우세도**로 자른다. ImageGen이 배경에 넓고
느린 밝기 변화를 남기는데, 한 점을 표본으로 잡아 거리를 재면 그 변화를
따라가지 못한다. 초록이 빨강·파랑보다 얼마나 앞서는지를 보면 밝기가 변해도
같은 판정이 나온다.

초록 번짐(despill)도 함께 지운다. 크로마 배경에서 뽑은 그림은 머리카락처럼
가는 부분의 가장자리에 초록이 배어 있어서, 알파만 잘라 내면 밝은 배경 위에서
초록 테두리로 남는다. 초록이 빨강·파랑 최댓값을 넘는 만큼만 눌러 준다.

사용법:
    python design-system/scripts/extract_green_sprite.py --input a.png --out b.png
    python design-system/scripts/extract_green_sprite.py --input-dir alpha --out-dir out
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

#: 초록 우세도 임계. 아래는 그림, 위는 배경, 사이는 안티에일리어싱 경사다.
#: v6·v7 원본 실측에서 그림 쪽은 26을 넘지 않고 배경은 84 아래로 내려오지 않는다.
SUBJECT_BELOW = 40
BACKGROUND_ABOVE = 96


def _green_score(rgb: np.ndarray) -> np.ndarray:
    """초록이 빨강·파랑 중 큰 쪽을 얼마나 앞서는가."""

    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return green - np.maximum(red, blue)


def extract(source_path: Path, output_path: Path) -> dict[str, float]:
    source = Image.open(source_path).convert("RGB")
    rgb = np.asarray(source, dtype=np.int16)
    score = _green_score(rgb)

    ramp = np.clip(
        (BACKGROUND_ABOVE - score) / (BACKGROUND_ABOVE - SUBJECT_BELOW), 0, 1
    )
    alpha = Image.fromarray((ramp * 255).round().astype(np.uint8), "L")
    # 한 겹 깎아 배경 쪽 반투명 띠를 없앤다. 마젠타 쪽과 같은 처리다.
    alpha = alpha.filter(ImageFilter.MinFilter(3))
    alpha_array = np.asarray(alpha, dtype=np.int16)

    # 남은 초록 번짐을 누른다. **가장자리 띠에만** 건다 - 번짐은 배경과 닿는
    # 화소에서 생기고, 안쪽까지 누르면 씨앗의 떡잎처럼 진짜 초록인 부분이
    # 회색이 된다. 알파를 한 번 깎은 것과 원본의 차이가 곧 그 띠다.
    inner = Image.fromarray((alpha_array >= 224).astype(np.uint8) * 255, "L")
    eroded = np.asarray(inner.filter(ImageFilter.MinFilter(7)), dtype=np.int16)
    edge_band = (alpha_array > 0) & (eroded == 0)

    despilled = rgb.copy()
    despilled[..., 1] = np.where(
        edge_band & (score > 0),
        np.maximum(rgb[..., 0], rgb[..., 2]),
        rgb[..., 1],
    )

    result = np.dstack((despilled, alpha_array)).astype(np.uint8)
    result[alpha_array == 0] = 0
    output_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(result, "RGBA").save(output_path, "PNG", optimize=True)

    solid = int((alpha_array >= 224).sum())
    return {
        "opaque_ratio": solid / alpha_array.size,
        "soft_edge_ratio": float(((alpha_array > 0) & (alpha_array < 224)).sum())
        / max(1, solid),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--input-dir", type=Path)
    parser.add_argument("--out-dir", type=Path)
    args = parser.parse_args()

    if args.input_dir:
        if not args.out_dir:
            raise SystemExit("--input-dir 을 쓰면 --out-dir 도 필요합니다.")
        sources = sorted(args.input_dir.glob("*.png"))
        if not sources:
            raise SystemExit(f"{args.input_dir} 에 PNG가 없습니다.")
        for path in sources:
            report = extract(path, args.out_dir / path.name)
            print(
                f"{path.name:<32} 불투명 {report['opaque_ratio']:.1%}"
                f"  경사 {report['soft_edge_ratio']:.3%}"
            )
        return

    if not (args.input and args.out):
        raise SystemExit(
            "--input 과 --out, 또는 --input-dir 과 --out-dir 이 필요합니다."
        )
    report = extract(args.input, args.out)
    print(f"{args.input.name} -> {args.out} 불투명 {report['opaque_ratio']:.1%}")


if __name__ == "__main__":
    main()
