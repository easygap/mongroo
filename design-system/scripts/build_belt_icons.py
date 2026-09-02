#!/usr/bin/env python3
"""전투 벨트 아이콘을 런타임 크기로 굽는다.

## 왜 필요한가

6아이콘 벨트에서 고유 스킬과 감정 스킬은 전용 아이콘을 쓰는데, **기본 공격과
마음 지키기는 머티리얼 기본 아이콘**이 그대로 나가고 있었다
(`Icons.sports_martial_arts_rounded`, `Icons.shield_outlined`). 손그림 동화풍
화면에 안드로이드 기본 아이콘이 둘 섞여 있는 셈이다.

성장결 여섯도 화면에서는 글자 + `Icons.hub_outlined` **하나**로만 표시됐다.
여섯이 같은 그림이라 색과 글자를 못 읽으면 구분이 되지 않는다.

## 여기서 재는 것은 `똑같은 그림을 두 번 넣었는가` 하나다

여섯 성장결이 **색 없이도 갈려야 한다**는 요구가 있다. 화면에서 성장결은 글자
+ `Icons.hub_outlined` 하나로만 표시됐으니, 색과 글자를 못 읽으면 여섯이 전부
같은 것이었다.

그런데 **`모양이 충분히 다른가`는 여기서 재지 않는다.** 처음에는 실루엣을 뽑아
겹쳐 보려 했는데, 이 아이콘들은 비네트 배경 위의 불투명 그림이고 광채까지
밝아서 여섯 다 `꽉 찬 덩어리`로 이진화됐다(채움 52~73%). 그 값으로는 해와
불꽃이 0.06 차이로 나온다 - 그림이 아니라 **잣대가 틀린 것**이다. 이 저장소에서
픽셀 휴리스틱을 세우려다 실패한 세 번째 경우다.

그래서 범위를 좁혔다. 표준적인 average hash로 **같은 그림이 두 번 들어갔는지**만
본다. 실측하면 진짜 중복은 0.000이고 가장 닮은 진짜 짝(별빛↔햇살)이 0.074다.
그 사이에 선을 그으면 사고는 잡히고 판단은 넘보지 않는다.

**모양이 서로 갈리는지는 눈으로 본다.** concept README에 여섯을 나란히 붙여
두었고, 가장 닮은 짝이 무엇인지도 적어 뒀다.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
RUNTIME_ROOT = REPO / "app/assets/adventure/skill-icons"

#: 런타임 크기. 기존 스킬 아이콘과 같다.
ICON_SIZE = 256

#: 어느 폴더로 갈지. 성장결 마크와 행동 글리프를 나눠 둔다.
DESTINATIONS = {
    "kel-": "kel",
    "action-": "action",
}

#: 두 아이콘이 이만큼은 달라야 한다(average hash가 어긋나는 비율).
#:
#: 실측: 같은 그림 0.000, 가장 닮은 진짜 짝 0.074, 중앙값 0.191. 그 사이인
#: 0.03에 선을 둔다. **`충분히 다르게 생겼는가`를 심판하는 값이 아니다** -
#: 같은 파일을 두 번 넣거나 덮어쓴 사고를 잡는 값이다.
MIN_ICON_DISTANCE = 0.03


def _ahash(image: Image.Image, size: int = 16) -> np.ndarray:
    """average hash. 평균보다 밝은 칸을 1로 둔 16×16 비트맵."""

    grey = np.asarray(
        image.convert("L").resize((size, size), Image.LANCZOS), dtype=np.float32
    )
    return grey > grey.mean()


def _distance(left: np.ndarray, right: np.ndarray) -> float:
    """두 해시가 어긋나는 비율."""

    return float((left ^ right).mean())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--concept-root",
        type=Path,
        default=Path("design-system/concepts/battle-belt-icons-v15"),
    )
    args = parser.parse_args()

    concept = (REPO / args.concept_root).resolve()
    raw = concept / "_raw"
    sources = sorted(raw.glob("*.png")) if raw.exists() else []
    if not sources:
        sources = sorted(concept.glob("sources/*.png"))
    if not sources:
        raise SystemExit(f"{concept}에 구울 아이콘이 없습니다")

    hashes: dict[str, np.ndarray] = {}
    baked: list[str] = []
    for source in sources:
        name = source.stem
        folder = next(
            (value for prefix, value in DESTINATIONS.items() if name.startswith(prefix)),
            None,
        )
        if folder is None:
            raise SystemExit(f"{name}은 어느 폴더로 갈지 모르겠습니다")
        with Image.open(source) as opened:
            icon = opened.convert("RGB").resize(
                (ICON_SIZE, ICON_SIZE), Image.LANCZOS
            )
        hashes[name] = _ahash(icon)
        target = RUNTIME_ROOT / folder / f"{name.removeprefix(folder + '-')}-v1.webp"
        target.parent.mkdir(parents=True, exist_ok=True)
        icon.save(target, format="WEBP", quality=92, method=6)
        # 원본은 concept에 남긴다. 4.7이 요구하는 납품 묶음의 master다.
        keep = concept / "sources" / source.name
        keep.parent.mkdir(parents=True, exist_ok=True)
        if source.parent != keep.parent:
            keep.write_bytes(source.read_bytes())
        baked.append(str(target.relative_to(REPO)).replace("\\", "/"))

    # 같은 그림이 두 번 들어갔는가.
    names = sorted(hashes)
    worst: tuple[float, str, str] | None = None
    for index, left in enumerate(names):
        for right in names[index + 1:]:
            distance = _distance(hashes[left], hashes[right])
            if worst is None or distance < worst[0]:
                worst = (distance, left, right)
    if worst is not None:
        print(f"가장 닮은 짝: {worst[1]} ↔ {worst[2]} 차이 {worst[0]:.3f}")
        if worst[0] < MIN_ICON_DISTANCE:
            print(
                f"기준 {MIN_ICON_DISTANCE}보다 닮았습니다. "
                "같은 그림이 두 번 들어갔는지 보세요."
            )
            return 1

    for path in baked:
        print("구움:", path)
    print(f"{len(baked)}종을 런타임에 넣었습니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
