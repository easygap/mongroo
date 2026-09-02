#!/usr/bin/env python3
"""지역 전용 장면 원화를 런타임 크기로 굽는다.

## 왜 필요한가

장면은 7종인데 지역 전용 원화는 여덟 칸뿐이고, 나머지는 **기억서고 원화에 지역
색 보정만 얹어** 나갔다. `expedition_scene.dart`의 주석도 그렇게 적어 두고
있었다 — `나머지 장면은 여전히 공용 원화 + 지역 색 보정으로 간다`.

각 지역이 **실제로 쓰는** 장면만 세면 빌린 칸은 셋이었다. 그 셋을 채우면 모든
지역이 자기가 쓰는 장면을 전부 자기 원화로 갖는다.

## 굽는 것

imagegen이 주는 1536×1024를 런타임 규격인 1600×900으로 맞춘다. 비율이 다르니
**가운데를 잘라낸다** — 위아래를 눌러 담으면 바닥 원근이 무너진다. 자른 뒤
960×540 모바일 판까지 만든다(기존 장면과 같은 규칙).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
RUNTIME_ROOT = REPO / "app/assets/adventure"

#: 런타임 규격. 기존 장면 원화와 같다.
SCENE_SIZE = (1600, 900)
MOBILE_SIZE = (960, 540)

#: `<concept 파일 이름>`: `<런타임 파일 이름>`.
#:
#: 지역과 장면을 잇는 것은 앱의 `expeditionRegionSceneAssets`다. 여기서는
#: 이름만 맞춘다.
TARGETS = {
    "echo-well-flooded-cave": "expedition-flooded-cave-echo-well-v1",
    "echo-well-root-tunnel": "expedition-root-tunnel-echo-well-v1",
    "heartwood-observatory-root-tunnel":
        "expedition-root-tunnel-heartwood-observatory-v1",
}


def _fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """비율을 지키며 가운데를 잘라 맞춘다.

    눌러 담으면 바닥 원근이 무너져 대원이 떠 보인다.
    """

    target = size[0] / size[1]
    width, height = image.size
    if width / height > target:
        crop_width = int(round(height * target))
        left = (width - crop_width) // 2
        image = image.crop((left, 0, left + crop_width, height))
    else:
        crop_height = int(round(width / target))
        top = (height - crop_height) // 2
        image = image.crop((0, top, width, top + crop_height))
    return image.resize(size, Image.LANCZOS)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--concept-root",
        type=Path,
        default=Path("design-system/concepts/region-scene-art-v16"),
    )
    args = parser.parse_args()

    concept = (REPO / args.concept_root).resolve()
    raw = concept / "_raw"
    sources = sorted(raw.glob("*.png")) if raw.exists() else []
    if not sources:
        sources = sorted(concept.glob("sources/*.png"))
    if not sources:
        raise SystemExit(f"{concept}에 구울 장면이 없습니다")

    baked: list[str] = []
    for source in sources:
        target_name = TARGETS.get(source.stem)
        if target_name is None:
            raise SystemExit(f"{source.stem}은 어느 장면인지 모르겠습니다")
        with Image.open(source) as opened:
            scene = opened.convert("RGB")
        full = _fit(scene, SCENE_SIZE)
        mobile = full.resize(MOBILE_SIZE, Image.LANCZOS)
        for image, suffix in ((full, ""), (mobile, "-mobile")):
            path = RUNTIME_ROOT / f"{target_name}{suffix}.webp"
            image.save(path, format="WEBP", quality=88, method=6)
            baked.append(str(path.relative_to(REPO)).replace("\\", "/"))
        keep = concept / "sources" / source.name
        keep.parent.mkdir(parents=True, exist_ok=True)
        if source.parent != keep.parent:
            keep.write_bytes(source.read_bytes())

    for path in baked:
        print("구움:", path)
    print(f"장면 {len(sources)}종을 런타임에 넣었습니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
