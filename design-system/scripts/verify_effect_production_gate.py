#!/usr/bin/env python3
"""전투 연출을 `production_ready`로 올려도 되는지 기계로 잴 수 있는 만큼 잰다.

## 왜 필요한가

지금 `production_ready:true`인 40종은 **아무 검사도 통과한 적이 없다.**
`build_signature_skill_completion_v8.py`가 family 이름만 보고 무조건 `True`를
찍었다. 설계서 4.7과 각 concept README가 적어 둔 승격 조건은 따로 있는데,
그 조건과 플래그가 아무 관계도 없이 지내 온 것이다.

이 스크립트는 그 조건 중 **기계로 확정할 수 있는 것만** 검사로 만든다.
`판단이 갈리는 것`은 일부러 넣지 않았다 — 애매한 기준으로 승격/강등을 하면
플래그가 다시 의미를 잃는다. 실제로 `가장 밝은 프레임이 접촉 프레임이다`라는
그럴듯한 검사를 먼저 만들어 봤다가 버렸다. 얼음이 퍼지는 `absolute-zero`는
맨 처음의 작고 밝은 핵이 가장 밝아서, 승인된 연출 17종이 무더기로 걸렸다.
접촉이 몇 번째 칸인지는 아트 디렉션 판단이지 픽셀 통계가 아니다.

## 재는 것

1. **프레임 무결성** — 선언한 수만큼 있고, 크기가 맞고, 진짜 알파가 있는가.
2. **크로마 잔류** — 걷다 만 배경이 그림인 척 남았는가(`verify_enemy_attack_effects`와 같은 잣대).
3. **실제 배경 위 가독성** — 설계서 4.7의 `실제 배경 합성`. 평평한 회색이 아니라
   그 지역의 진짜 전투 배경 위에 얹어, 연출이 배경과 구분되는지를 본다.
   밝은 곳과 어두운 곳 **양쪽**에서 본다(README들이 `밝은·어두운 전투 배경`을
   요구한다).
4. **디코딩 피크** — 8프레임을 RGBA로 펼쳤을 때의 메모리. 저사양 기기에서
   먼저 터지는 것이 이 값이다.

## 프레임 타임은 여기가 아니라 하네스가 잰다

정적 검사로는 `재생할 때 얼마나 무거운가`를 알 수 없다. 그건
`design-system/benchmarks/effect-frame-time`이 실제 래스터 파이프라인에서 재고,
결과는 `docs/performance.md`와 manifest의 `gate_profile`에 있다.

## 그래도 재지 못하는 것

**저사양 Android·iOS 실기기.** 이 기계에는 Android SDK도 실기기도 없다.
데스크톱 GPU는 모바일의 발열·전력 제한·메모리 압박을 대신하지 않는다.
`pending`에 이름으로 남겨 둔다 — `production_ready:true`가 `전부 끝났다`로
읽히지 않게.
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
BACKDROP_ROOT = REPO / "app/assets/adventure"

#: 실제 전투 배경. 지역을 아는 연출은 그 지역 것으로, 나머지는 공용 전장으로 본다.
BACKDROPS = {
    "moss_archive": "expedition-monster-den-battle-v1.webp",
    "echo_well": "expedition-monster-den-echo-well-v1.webp",
    "starlight_seed_vault": "expedition-monster-den-starlight-seed-vault-v1.webp",
    "heartwood_observatory": "expedition-monster-den-heartwood-observatory-v1.webp",
}
DEFAULT_BACKDROP = "expedition-monster-den-battle-v1.webp"

#: 키 색 범위와 상한. `verify_enemy_attack_effects.py`와 같은 값을 쓴다.
KEY_MAX_RED, KEY_MIN_GREEN, KEY_MIN_BLUE = 96, 200, 200
MAX_KEY_FRAME_SHARE = 0.01

#: 배경 위에 얹었을 때 바뀌어야 하는 최소 밝기 차이(0~1).
#:
#: **회귀 바닥이다.** 지금 실려 있는 69종을 재면 0.229~0.838이고, 가장 약한
#: 것이 `baby-pot.root-embrace`다. 그 바로 아래에 선을 둔다.
#:
#: 이 선은 지금 것들을 검증하지 않는다 — 전부 이미 위에 있다. 앞으로 들어올
#: 연출이 **배경에 묻혀 안 보이는 것**을 막는 용도다. 처음에는 0.02로 뒀다가
#: 지웠다. 최솟값의 10분의 1이라 무엇도 걸릴 수 없었고, 걸릴 수 없는 검사는
#: 검사가 아니다.
MIN_CONTRAST = 0.20

#: 재생 프레임 타임 실측. `design-system/benchmarks/effect-frame-time`이 낸 값이다.
#:
#: 69종을 이어 재생하며 Windows 데스크톱 profile 빌드에서 두 번 쟀다. 합격
#: 판단에 쓰는 값은 `raster`와 `build`다 — `total`은 모니터 주사율(약 120Hz)에
#: 묶여서 연출의 비용이 아니라 화면의 리듬을 보여 준다.
GATE_PROFILE = {
    "runtime": "windows-desktop-profile",
    "harness": "design-system/benchmarks/effect-frame-time",
    "effects": 69,
    "runs": [
        {"sampled_frames": 3371, "raster_p95_ms": 0.635, "raster_p99_ms": 0.846,
         "raster_max_ms": 6.758, "build_p95_ms": 0.566, "total_p95_ms": 15.749,
         "over_20ms": 3, "over_33_4ms": 0},
        {"sampled_frames": 3370, "raster_p95_ms": 0.580, "raster_p99_ms": 0.734,
         "raster_max_ms": 1.175, "build_p95_ms": 0.497, "total_p95_ms": 15.796,
         "over_20ms": 0, "over_33_4ms": 0},
    ],
    "scope": "effect_layer_only",
    "pending": ["low_end_android_p95", "ios_p95"],
}

#: 한 연출이 RGBA로 펼쳐졌을 때의 메모리 상한.
#:
#: 576×288×4바이트 = 663KB/프레임이다. 설계서 S3A가 목표로 두는 10프레임
#: 패키지가 6.3MB라, 그것을 담고 8MB에서 막는다.
#:
#: 처음에 6MB로 뒀더니 `care-vines`·`ledger-claw`·`kel.sunny` 셋이 걸렸다 —
#: 이 프로젝트에서 가장 공들인 10프레임 연출들이다. 설계가 원하는 것을 상한이
#: 막고 있었으니 상한이 틀린 것이었다.
MAX_DECODED_BYTES = 8 * 1024 * 1024


def _region_of(family: str) -> str | None:
    """family가 어느 지역 것인지. 엉킴 카탈로그가 원본이다."""

    sys.path.insert(0, str(REPO / "server"))
    from app.content.expeditions.tangles import TANGLE_CATALOG  # noqa: PLC0415

    for tangle in TANGLE_CATALOG.values():
        for intent in tangle["intents"]:
            if intent["vfx_family"] == family:
                return str(tangle["region_code"])
    return None


def _backdrop(name: str, size: tuple[int, int], *, dim: float) -> np.ndarray:
    with Image.open(BACKDROP_ROOT / name) as opened:
        image = opened.convert("RGB").resize(size, Image.LANCZOS)
    return np.asarray(image, dtype=np.float32) / 255.0 * dim


def _luminance(rgb: np.ndarray) -> np.ndarray:
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def _check(effect: dict, backdrop_name: str) -> tuple[list[str], dict]:
    """`(실패 사유, 잰 값)`."""

    directory = RUNTIME_ROOT / str(effect["directory"])
    width, height = effect["frame_size"]
    failures: list[str] = []
    decoded = 0
    worst_key = 0.0
    best_contrast = 0.0
    opaque_only = True

    frames = []
    for index in range(effect["frame_count"]):
        path = directory / f"frame-{index:02d}.webp"
        if not path.exists():
            failures.append(f"frame-{index:02d} 없음")
            continue
        with Image.open(path) as opened:
            rgba = np.asarray(opened.convert("RGBA"), dtype=np.float32)
        if rgba.shape[1] != width or rgba.shape[0] != height:
            failures.append(f"frame-{index:02d} 크기 {rgba.shape[1]}×{rgba.shape[0]}")
            continue
        decoded += rgba.shape[0] * rgba.shape[1] * 4
        alpha = rgba[..., 3] / 255.0
        if alpha.min() < 1.0:
            opaque_only = False
        # 키 색 잔류.
        red, green, blue = rgba[..., 0], rgba[..., 1], rgba[..., 2]
        key = (
            (alpha > 0.09)
            & (red < KEY_MAX_RED)
            & (green > KEY_MIN_GREEN)
            & (blue > KEY_MIN_BLUE)
        )
        worst_key = max(worst_key, float(key.sum() / key.size))
        frames.append((rgba[..., :3] / 255.0, alpha))

    if opaque_only and frames:
        failures.append("알파가 없다(불투명 사각형)")
    if worst_key > MAX_KEY_FRAME_SHARE:
        failures.append(f"크로마 잔류 {worst_key:.2%}")
    if decoded > MAX_DECODED_BYTES:
        failures.append(f"디코딩 {decoded / 1024 / 1024:.1f}MB")

    # 실제 배경 위 가독성. 밝은 쪽과 어두운 쪽 모두에서 본다.
    for dim in (1.0, 0.45):
        background = _backdrop(backdrop_name, (width, height), dim=dim)
        base = _luminance(background)
        for rgb, alpha in frames:
            composited = background * (1 - alpha[..., None]) + rgb * alpha[..., None]
            delta = np.abs(_luminance(composited) - base)
            lit = alpha > 0.25
            if not lit.any():
                continue
            best_contrast = max(best_contrast, float(delta[lit].mean()))
    if frames and best_contrast < MIN_CONTRAST:
        failures.append(f"배경 위 대비 {best_contrast:.3f}")

    return failures, {
        "decoded_mb": round(decoded / 1024 / 1024, 2),
        "key_share": round(worst_key, 5),
        "backdrop_contrast": round(best_contrast, 4),
        "backdrop": backdrop_name,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--promote",
        action="store_true",
        help="통과한 것을 production_ready:true로 올리고, 떨어진 것을 내린다.",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    passed: list[str] = []
    failed: list[tuple[str, list[str]]] = []

    for effect in manifest["effects"]:
        family = str(effect["family"])
        region = _region_of(family)
        backdrop = BACKDROPS.get(region or "", DEFAULT_BACKDROP)
        failures, measured = _check(effect, backdrop)
        if failures:
            failed.append((family, failures))
        else:
            passed.append(family)
        if args.promote:
            effect["production_ready"] = not failures
            effect["gate"] = {
                **measured,
                "checks": [
                    "frame_integrity",
                    "chroma_residue",
                    "backdrop_legibility",
                    "decoded_peak",
                ],
                # 통과해도 이건 남는다. 실기기가 있어야 한다.
                "pending": GATE_PROFILE["pending"],
            }

    print(f"통과 {len(passed)} / 전체 {len(manifest['effects'])}")
    if failed:
        print()
        print("떨어진 것:")
        for family, reasons in failed:
            print(f"  {family}: {', '.join(reasons)}")

    if args.promote:
        manifest["gate_profile"] = GATE_PROFILE
        MANIFEST.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print()
        print("manifest에 반영했습니다.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
