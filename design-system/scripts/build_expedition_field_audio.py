"""탐험 현장음 7종 — 발걸음 4, 발견 3.

`build_expedition_contact_audio.py`의 모달 합성 도구를 그대로 쓴다. 같은 재질을
두 벌 만들지 않기 위해서다.

## 발걸음이 접촉음과 달라야 하는 이유

`contact-wood`는 **적을 때린 소리**, `step-wood`는 **내가 밟은 소리**다. 둘이
비슷하면 걷는 내내 전투가 일어나는 것처럼 들린다. 그래서 세 가지를 의도적으로
갈라 놓는다.

- **더 조용하다.** 걸음은 계속 난다. 접촉음과 같은 세기면 금방 지친다.
- **더 어둡다.** 때리는 소리의 밝은 상단을 덜어 낸다.
- **더 짧다.** 울림을 남기지 않는다. 울리면 공간이 아니라 사건이 된다.

검수기가 이 셋을 실제로 잰다. 같은 재질의 접촉음과 너무 닮으면 실패다.

## 발걸음에 `pot`이 있는 이유

주인공은 화분이다. 잎·나무·돌은 **바닥** 재질이지만 `pot`은 **자기 몸**이
바닥에 닿는 소리다. 도자기 몸통의 빈 공명이 들어간다.

## 발견 세 종의 관계

`normal → story → target`은 세기가 아니라 **무게**가 다르다. 음 수가 하나씩
늘고, 마지막 음이 `정원으로 돌아가는 동기`(C-G-A-E)의 뒤쪽으로 간다. 목표를
찾았을 때가 가장 멀리 간다. 검수기가 이 순서를 강제한다.

사용법:
    python build_expedition_field_audio.py --out <폴더>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_expedition_contact_audio import (  # noqa: E402
    SAMPLE_RATE,
    _add_mode,
    _add_noise,
    _fade,
    _normalise,
    _write_mono,
)

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "app" / "assets" / "adventure" / "sfx"
MANIFEST = ROOT / "design-system" / "audio" / "field-audio-manifest.json"

# 접촉음은 0.150이다. 걸음은 계속 나므로 그보다 확실히 낮춘다.
STEP_LOUDNESS = 0.052
# 발견은 보상이라 걸음보다 또렷하되 접촉음을 넘지 않는다.
DISCOVER_LOUDNESS = 0.105

# 정원으로 돌아가는 동기. release cadence와 같은 가족이라 귀가 이어 듣는다.
NOTE_HZ = {"C": 261.63, "G": 392.00, "A": 440.00, "E": 659.25}


def _buffer(seconds: float) -> list[float]:
    return [0.0] * round(SAMPLE_RATE * seconds)


# ── 발걸음 ───────────────────────────────────────────────────────────────────
#
# 넷 다 짧다. 밟는 순간의 마찰 잡음 + 바닥이 잠깐 우는 모드 한둘이 전부다.


def _step_leaf() -> list[float]:
    """마른 잎 — 부스러지는 잡음이 거의 전부, 음정은 없다시피 하다."""

    buffer = _buffer(0.14)
    _add_noise(
        buffer, duration_ms=78, low_hz=520, high_hz=3400, gain=0.42, seed=8101, curve=2.4
    )
    _add_mode(buffer, frequency=286, decay_ms=26, gain=0.052)
    return buffer


def _step_pot() -> list[float]:
    """도자기 몸통 — 바닥에 닿는 짧은 딱, 뒤에 빈 몸의 낮은 울림."""

    buffer = _buffer(0.18)
    _add_noise(
        buffer, duration_ms=22, low_hz=900, high_hz=5200, gain=0.24, seed=8203, curve=3.4
    )
    # 빈 화분의 공명. 두 모드가 살짝 어긋나 있어야 `통`하고 들린다.
    _add_mode(buffer, frequency=214, decay_ms=88, gain=0.30)
    _add_mode(buffer, frequency=498, decay_ms=52, gain=0.15)
    return buffer


def _step_wood() -> list[float]:
    """나무 마루 — 낮고 둔한 쿵, 상단이 거의 없다."""

    buffer = _buffer(0.16)
    _add_noise(
        buffer, duration_ms=26, low_hz=320, high_hz=1900, gain=0.28, seed=8307, curve=3.0
    )
    _add_mode(buffer, frequency=138, decay_ms=74, gain=0.34)
    _add_mode(buffer, frequency=232, decay_ms=44, gain=0.13)
    return buffer


def _step_stone() -> list[float]:
    """돌바닥 — 거의 울리지 않는다. 짧고 단단한 톡."""

    buffer = _buffer(0.11)
    _add_noise(
        buffer, duration_ms=15, low_hz=700, high_hz=4200, gain=0.30, seed=8419, curve=4.2
    )
    _add_mode(buffer, frequency=352, decay_ms=19, gain=0.22)
    _add_mode(buffer, frequency=624, decay_ms=12, gain=0.10)
    return buffer


STEP_BUILDERS = {
    "leaf": _step_leaf,
    "pot": _step_pot,
    "wood": _step_wood,
    "stone": _step_stone,
}


# ── 발견 ─────────────────────────────────────────────────────────────────────
#
# (음이름, 시작초, 감쇠ms, 이득)로 적는다. 배음을 얇게 얹어 종처럼 만든다.
DISCOVER_SPECS = {
    # 그냥 뭔가 있었다 — 한 음, 짧게.
    "normal": (("G", 0.0, 300, 0.30),),
    # 읽을 것이 있다 — 두 음이 올라간다.
    "story": (("G", 0.0, 260, 0.26), ("A", 0.085, 420, 0.28)),
    # 찾던 것이다 — 세 음, 마지막이 가장 멀리 간다.
    "target": (
        ("G", 0.0, 240, 0.24),
        ("A", 0.080, 300, 0.26),
        ("E", 0.170, 720, 0.32),
    ),
}


def _discover(key: str) -> list[float]:
    spec = DISCOVER_SPECS[key]
    last_start = max(start for _name, start, _decay, _gain in spec)
    longest = max(decay for _name, _start, decay, _gain in spec)
    buffer = _buffer(last_start + longest / 1000 * 6 + 0.05)
    for name, start, decay_ms, gain in spec:
        base = NOTE_HZ[name]
        _add_mode(buffer, frequency=base, decay_ms=decay_ms, gain=gain, start=start)
        # 2배·3배음을 얇게. 종 비슷한 밝기를 주되 날카롭지 않게 둔다.
        _add_mode(
            buffer,
            frequency=base * 2,
            decay_ms=decay_ms * 0.55,
            gain=gain * 0.20,
            start=start,
        )
        _add_mode(
            buffer,
            frequency=base * 3,
            decay_ms=decay_ms * 0.32,
            gain=gain * 0.07,
            start=start,
        )
    return buffer


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def build(output_root: Path) -> list[dict]:
    files: list[dict] = []

    for material, builder in STEP_BUILDERS.items():
        samples = builder()
        _fade(samples)
        # 걸음은 계속 난다. 세게 만들 이유가 없고, peak도 낮게 눌러 둔다.
        samples = _normalise(samples, loudness=STEP_LOUDNESS, peak_ceiling=0.34)
        path = output_root / f"step-{material}.wav"
        _write_mono(path, samples)
        files.append(
            {
                "role": "step",
                "key": material,
                "path": path.name,
                "seconds": round(len(samples) / SAMPLE_RATE, 4),
                "sha256": _sha256(path),
            }
        )

    for key in DISCOVER_SPECS:
        samples = _discover(key)
        _fade(samples)
        samples = _normalise(samples, loudness=DISCOVER_LOUDNESS, peak_ceiling=0.50)
        path = output_root / f"discover-{key}.wav"
        _write_mono(path, samples)
        files.append(
            {
                "role": "discover",
                "key": key,
                "path": path.name,
                "seconds": round(len(samples) / SAMPLE_RATE, 4),
                "sha256": _sha256(path),
            }
        )

    return files


def _validate() -> None:
    """만들기 전에 설계 규칙을 스스로 검사한다."""

    # 발견 셋은 음 수가 반드시 늘어야 `무게`가 읽힌다.
    counts = [len(DISCOVER_SPECS[key]) for key in ("normal", "story", "target")]
    if counts != sorted(counts) or len(set(counts)) != 3:
        raise ValueError(f"발견 cue의 음 수가 늘지 않습니다: {counts}")
    # 마지막 음의 여운도 순서대로 길어야 한다.
    tails = [
        max(decay for _n, _s, decay, _g in DISCOVER_SPECS[key])
        for key in ("normal", "story", "target")
    ]
    if tails != sorted(tails):
        raise ValueError(f"발견 cue의 여운이 순서대로 길어지지 않습니다: {tails}")
    for name, _start, _decay, _gain in (
        note for spec in DISCOVER_SPECS.values() for note in spec
    ):
        if name not in NOTE_HZ:
            raise ValueError(f"동기에 없는 음이름입니다: {name}")
    if STEP_LOUDNESS >= DISCOVER_LOUDNESS:
        raise ValueError("걸음이 발견보다 크면 안 됩니다")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=None, help="출력 폴더")
    args = parser.parse_args()

    _validate()
    output = args.out or RUNTIME_DIR
    files = build(output)

    if args.out is None:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(
            json.dumps(
                {
                    "step_loudness": STEP_LOUDNESS,
                    "discover_loudness": DISCOVER_LOUDNESS,
                    "files": files,
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    print(f"{len(files)}개 완료 → {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
