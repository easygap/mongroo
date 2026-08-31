#!/usr/bin/env python3
"""여섯 성장결 스킬 signature 6종.

품종 고유기 32종은 소리를 가졌는데 **여섯 성장결 스킬만 tier 대체음으로 남아
있었다.** 누구든 선택 I 자리에 자기 결의 스킬을 끼우므로, 이 여섯이 없으면
모든 사용자가 전투마다 `크기만 아는 소리`를 듣는다.

## 여섯이 지켜야 하는 것 — 크기가 아니라 음색으로만 갈린다

기획의 불변식은 `여섯 성장결은 동등한 전술 언어이고 어느 결도 범용 상위호환이
될 수 없다`이다. 소리도 그 계약을 지켜야 한다. 그래서 여섯 곡은

- **같은 크기**로 만든다. 어느 결이 더 크게 들리면 귀가 먼저 서열을 만든다.
- **같은 길이**로 만든다. 더 오래 우는 결이 더 센 결로 읽힌다.
- **음색(밝기)으로만 갈린다.** 재료가 다를 뿐 무게는 같다.

`verify_emotion_signatures.py`가 이 셋을 숫자로 강제한다. 크기·길이가 벌어지면
실패고, 밝기가 붙어도 실패다.

## 재료

재료는 여기서 정하지 않는다. `ADVENTURE_AUDIO.md`의 성장결 음색표가 여섯의
핵심 질감과 피할 방향을 이미 못 박아 뒀고, 이 스크립트는 그 표를 소리로 옮길
뿐이다. 원소 이름(불·번개)을 흉내 내지 않고 정원에 있는 재료만 쓴다는 규칙도
그대로다.

    도자기 낮은 물결   ← 빗물 · 달빛 · 불씨 · 햇살 · 모아 · 별빛 →   유리구슬

불씨결이 가운데인 것이 뜻밖으로 보일 수 있는데, 음색표가 적은 것은 `마른 씨앗
껍질의 또렷한 짧은 튕김`이다. **또렷함은 어택의 속도이지 높이가 아니다.** 마른
씨앗은 중역의 마른 나무 소리로 튄다. 여기서 불씨결을 제일 밝게 만들면 음색표가
금지한 `금속 타격`으로 미끄러진다.

사용법:
    python build_emotion_signatures.py --out <폴더>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_expedition_contact_audio import (
    SAMPLE_RATE,
    _add_mode,
    _add_noise,
    _fade,
    _normalise,
    _write_mono,
)

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "app" / "assets" / "adventure" / "sfx"
MANIFEST = ROOT / "design-system" / "audio" / "emotion-signature-manifest.json"

# 품종 1번 스킬과 같은 크기다. 선택 스킬이 고유기를 덮으면 안 되고, 고유기보다
# 작으면 자기 결의 스킬이 곁다리로 들린다. 같은 자리에 둔다.
LOUDNESS = 0.108

# 여섯이 모두 이 길이다. 길이는 크기이므로 결마다 다르면 서열이 생긴다.
SECONDS = 0.62

# 여섯이 **함께 쓰는 감쇠 봉투**(ms). 결마다 다르게 두면 오래 우는 결이 더 센
# 결로 읽힌다. 그래서 무게는 여기서 한 번만 정하고, 정체성은 아래 표의 주파수와
# 마찰음이 만든다. 검수기가 길이 편차 10%를 강제하는데, 손으로 맞추면 재료를
# 하나 바꿀 때마다 다시 어긋난다 — 구조로 막는 편이 낫다.
DECAY_MS = (140.0, 84.0, 44.0)

# 마찰음 길이도 함께 묶는다. 오래 스치는 재료가 곧 긴 소리가 되기 때문이다.
NOISE_MS = 96.0

# ── 여섯 결의 재료 ───────────────────────────────────────────────────────────
#
# `modes`  : (주파수Hz, 이득) — 그 재료가 우는 높이. 감쇠는 여섯이 공유한다.
# `noise`  : (저역Hz, 고역Hz, 이득, 감쇠곡선) — 재료가 스치는 방식
# `bend`   : 감쇠하는 동안 음이 올라가는 정도. 물·공기는 움직이고 나무는 안 는다.
KELS: dict[str, dict] = {
    # 빗물결 — 도자기 가장자리를 낮게 훑는 물결 한 번. 불협화음도 울음소리도
    # 아니다. 슬픔은 시끄럽지 않다.
    "rainy": {
        "code": "rainy_frozen_tide",
        "modes": ((175, 0.30), (262, 0.14), (349, 0.06)),
        "noise": (132, 880, 0.22, 2.0),
        # 물이 물러가며 공명이 올라간다. 기포 모형과 같은 방향이다.
        "bend": 0.08,
    },
    # 달빛결 — 천 위에 놓인 작은 나무 방울이 감쇠한다. 공포 drone도 경고음도
    # 아니다. 불안은 큰 소리가 아니라 멈추지 않고 도는 것이다.
    "moonlit": {
        "code": "moonlit_lonesome_tempest",
        "modes": ((294, 0.28), (441, 0.14), (588, 0.06)),
        # 천이 오래 스치므로 마찰 곡선이 여섯 중 가장 완만하다.
        "noise": (196, 1180, 0.22, 1.5),
        "bend": 0.03,
    },
    # 불씨결 — 마른 씨앗 껍질의 또렷한 짧은 튕김. 폭발도 금속 타격도 아니고,
    # 무엇보다 **더 큰 음량이 아니다**(음색표의 금지 방향).
    "ember": {
        "code": "ember_rage_breaker",
        "modes": ((523, 0.30), (698, 0.15), (1046, 0.06)),
        "noise": (430, 2340, 0.26, 3.6),
        "bend": 0.0,
    },
    # 햇살결 — 얇은 나뭇잎 두 장이 넓게 펴지는 숨. 보상 팡파르로 가지 않으려면
    # 또렷한 음보다 **넓은 숨**이 앞서야 한다.
    "sunny": {
        "code": "sunny_radiant_heart",
        "modes": ((784, 0.22), (1046, 0.12), (1568, 0.06)),
        "noise": (760, 3900, 0.28, 2.2),
        "bend": 0.0,
    },
    # 모아결 — 서로 다른 두 종이 질감이 한 박자로 합쳐진다. 겹침이 흔들리면
    # 안 되므로 두 마찰을 같은 시작점에 둔다.
    "mosaic": {
        "code": "mosaic_steel_equilibrium",
        "modes": ((1046, 0.20), (1397, 0.11), (2093, 0.05)),
        "noise": (1240, 5200, 0.26, 2.8),
        "bend": 0.0,
    },
    # 별빛결 — 유리구슬 한 번과 가벼운 잎 click. 슬롯머신 반짝임으로 가지
    # 않도록 반복 없이 한 번만 친다.
    "sparkling": {
        "code": "sparkling_shock_wonder",
        "modes": ((1568, 0.24), (2093, 0.12), (3136, 0.05)),
        "noise": (2960, 11200, 0.24, 3.8),
        "bend": 0.0,
    },

}


def _signature(kel: str, *, seed: int) -> list[float]:
    """한 결의 재료로 스킬 하나를 만든다. 길이와 크기는 여섯이 공유한다."""

    material = KELS[kel]
    buffer = [0.0] * round(SAMPLE_RATE * SECONDS)

    low_hz, high_hz, gain, curve = material["noise"]
    _add_noise(
        buffer,
        duration_ms=NOISE_MS,
        low_hz=low_hz,
        high_hz=high_hz,
        gain=gain,
        seed=seed,
        curve=curve,
    )
    for index, (hz, mode_gain) in enumerate(material["modes"]):
        _add_mode(
            buffer,
            frequency=hz,
            decay_ms=DECAY_MS[index],
            gain=mode_gain,
            # 위 모드가 아주 조금 늦게 들어와 재료에 두께가 생긴다. 여섯 모두
            # 같은 값이라 이 지연이 결 사이의 차이를 만들지는 않는다.
            start=0.008 * index,
            bend=material["bend"],
        )
    return buffer


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def build(output_root: Path) -> list[dict]:
    files: list[dict] = []
    for kel, material in KELS.items():
        code = material["code"]
        seed = int.from_bytes(
            hashlib.sha256(f"kel:{kel}:{code}".encode()).digest()[:4], "big"
        )
        samples = _signature(kel, seed=seed)
        _fade(samples)
        samples = _normalise(samples, loudness=LOUDNESS, peak_ceiling=0.56)
        slug = code.replace("_", "-")
        path = output_root / f"skill-emotion-{slug}.wav"
        _write_mono(path, samples)
        files.append(
            {
                "kel": kel,
                "skill": code,
                "slot": "selected_1",
                "path": path.name,
                "seconds": round(len(samples) / SAMPLE_RATE, 4),
                "sha256": _sha256(path),
            }
        )
    return files


def _validate() -> None:
    """서버 카탈로그와 코드가 어긋나면 만들기 전에 멈춘다."""

    codes = [material["code"] for material in KELS.values()]
    if len(set(codes)) != len(codes):
        raise ValueError("성장결 스킬 코드가 겹칩니다")
    for kel, material in KELS.items():
        if len(material["modes"]) != len(DECAY_MS):
            raise ValueError(f"{kel}: 모드 수가 공유 감쇠 봉투와 다릅니다")
    sys.path.insert(0, str(ROOT / "server"))
    try:
        from app.content.expeditions.combat_identity import (
            FORM_COMBAT_SKILLS,
        )
    except ImportError:  # pragma: no cover - 서버 venv 밖에서 부를 수 있다.
        return
    expected = {kel: entry["code"] for kel, entry in FORM_COMBAT_SKILLS.items()}
    actual = {kel: material["code"] for kel, material in KELS.items()}
    if expected != actual:
        raise ValueError(f"서버 성장결 스킬과 다릅니다. 서버={expected} 여기={actual}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    _validate()
    output = args.out or RUNTIME_DIR
    files = build(output)

    if args.out is None:
        MANIFEST.write_text(
            json.dumps(
                {"loudness": LOUDNESS, "seconds": SECONDS, "files": files},
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"manifest: {MANIFEST.relative_to(ROOT)}")
    print(f"성장결 signature {len(files)}종을 {output}에 만들었습니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
