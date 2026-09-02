#!/usr/bin/env python3
"""엉킴 공격 런타임 프레임에 크로마 배경이 남았는지 센다.

설계서 4.7: `key color 잔류·불투명 모서리가 있으면 투명 에셋으로 인정하지
않는다.` 시안 배경 위에 그린 시트를 걷어 냈을 때, **걷다 만 배경**이 그림인
척 남아 있는지를 본다.

## 무엇을 세는가

키 색은 시트의 최빈색을 재서 알아냈다 — `(0~8, 240~248, 248)`, 빨강이 거의
없는 새파란 시안이다. 그래서 `빨강이 낮고 초록·파랑이 높은` 픽셀만 센다.

`초록·파랑이 빨강보다 높으면 시안`처럼 느슨하게 세 봤더니 얼음·물처럼 원래
차가운 연출이 전부 걸렸다(`aloof-pot.absolute-zero`가 67%). 그 그림들은
**연한** 파랑이라 빨강이 높다.

## 왜 비율이 아니라 넓이인가

처음에는 `보이는 그림 대비 키 색 비율`로 쟀는데, 마지막 소멸 프레임처럼 남은
그림이 몇백 픽셀뿐인 곳에서 잔류 60픽셀이 16%로 찍혔다. 576×288에서 60픽셀은
보이지 않는다. 반대로 진짜 실패한 시트는 프레임의 5분의 1이 배경 조각이었다.

그래서 **프레임에서 배경이 차지하는 넓이**로 센다. 사람이 보는 것이 그것이다.
비율은 참고로만 같이 찍는다.

## 이 검사가 못 보는 것

너무 많이 걷어 내서 그림에 구멍이 난 경우는 여기서 안 잡힌다. 그것은 각
concept 디렉터리의 밝은/어두운 QA 시트를 눈으로 봐야 한다.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover - 실행 환경 오류를 바로 설명한다.
    raise SystemExit("Pillow와 NumPy가 필요합니다.") from exc

REPO = Path(__file__).resolve().parents[2]
MANIFEST = REPO / "app/assets/adventure/effects/manifest.json"
RUNTIME_ROOT = REPO / "app/assets/adventure/effects"

#: 키 색의 범위.
KEY_MAX_RED = 96
KEY_MIN_GREEN = 200
KEY_MIN_BLUE = 200

#: 한 프레임에서 배경이 차지해도 되는 최대 넓이.
#:
#: 지금 실려 있는 것 중 가장 나쁜 것이 0.28%(수백 픽셀의 가장자리 잔털)이고,
#: 다시 만들기 전의 실패작들은 10%대였다. 그 사이에 선을 둔다.
MAX_KEY_FRAME_SHARE = 0.01


def _key_pixels(path: Path) -> tuple[int, int, int]:
    """`(키 픽셀 수, 보이는 픽셀 수, 프레임 픽셀 수)`."""

    with Image.open(path) as opened:
        rgba = np.asarray(opened.convert("RGBA"), dtype=np.int16)
    visible = rgba[..., 3] > 24
    red, green, blue = rgba[..., 0], rgba[..., 1], rgba[..., 2]
    key = (red < KEY_MAX_RED) & (green > KEY_MIN_GREEN) & (blue > KEY_MIN_BLUE)
    return int((key & visible).sum()), int(visible.sum()), int(visible.size)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--families",
        nargs="*",
        default=None,
        help="검사할 family. 안 주면 manifest 전체를 본다.",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    failures: list[str] = []
    worst: list[tuple[float, float, str]] = []
    for effect in manifest["effects"]:
        if args.families and effect["family"] not in args.families:
            continue
        directory = RUNTIME_ROOT / effect["directory"]
        peak_share = 0.0
        peak_ratio = 0.0
        for index in range(effect["frame_count"]):
            frame = directory / f"frame-{index:02d}.webp"
            if not frame.exists():
                print(f"없음: {frame}")
                return 1
            left, visible, total = _key_pixels(frame)
            share = left / total
            ratio = left / visible if visible else 0.0
            if share > peak_share:
                peak_share, peak_ratio = share, ratio
            if share > MAX_KEY_FRAME_SHARE:
                failures.append(
                    f"  {effect['family']} frame-{index:02d} "
                    f"프레임의 {share:.2%}({left}픽셀), 그림 대비 {ratio:.1%}"
                )
        worst.append((peak_share, peak_ratio, effect["family"]))

    worst.sort(reverse=True)
    print("배경이 가장 많이 남은 순:")
    for share, ratio, family in worst[:8]:
        print(f"  프레임의 {share:6.3%} (그림 대비 {ratio:5.1%})  {family}")

    if failures:
        print()
        print(f"기준({MAX_KEY_FRAME_SHARE:.0%}) 초과 프레임 {len(failures)}개:")
        for line in failures:
            print(line)
        return 1
    print()
    print(f"크로마 잔류 없음 — {len(worst)}종 모두 기준 아래입니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
