"""탐험 현장음 7종을 적용 **전에** 검사한다.

이 스크립트가 지키는 것:

1. **걸음이 접촉음과 구분되는가** — 이게 핵심이다. `step-wood`가 `contact-wood`와
   비슷하면 걷는 내내 전투가 나는 것처럼 들린다. 세 축(음량·밝기·길이) 중
   **적어도 둘**에서 확실히 갈려야 통과한다.
2. **걸음끼리 구분되는가** — 넷이 같은 소리면 재질을 넷으로 나눈 뜻이 없다.
3. **발견 셋의 무게 순서** — normal → story → target으로 길이와 여운이 늘어야
   한다. 목표를 찾은 순간이 가장 멀리 간다.
4. **걸음 < 발견 < 접촉** 음량 순서 — 계속 나는 소리가 가장 조용해야 한다.
5. true peak·DC·끝단 무음 같은 기본기.

사용법:
    python verify_expedition_field_audio.py <검사할 폴더>
"""

from __future__ import annotations

import argparse
import cmath
import math
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_expedition_field_audio import (  # noqa: E402
    DISCOVER_SPECS,
    RUNTIME_DIR,
    STEP_BUILDERS,
)

MAX_TRUE_PEAK = 0.79  # 약 -2 dBTP
MAX_DC_OFFSET = 0.002
# 끝이 뚝 끊기면 클릭이 난다.
MAX_TAIL_LEVEL = 0.02

# 걸음은 짧아야 한다. 길면 공간이 아니라 사건이 된다.
MAX_STEP_SECONDS = 0.22
# 발견은 보상이라 여운이 필요하다.
MIN_TARGET_SECONDS = 0.6

# 걸음과 접촉음이 갈리는 기준. 셋 중 둘 이상을 넘겨야 `다른 소리`로 본다.
STEP_QUIETER_RATIO = 0.55  # 걸음 RMS ÷ 접촉 RMS가 이보다 작아야 한다
STEP_DARKER_RATIO = 0.85  # 걸음 무게중심 ÷ 접촉 무게중심
STEP_SHORTER_RATIO = 0.80  # 걸음 유효 길이 ÷ 접촉 유효 길이

# 걸음끼리 구분. 접촉음 검수기와 같은 방식이다.
MIN_CENTROID_RATIO = 1.22
MIN_DECAY_RATIO = 1.30


def _read(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as source:
        rate = source.getframerate()
        frames = source.readframes(source.getnframes())
    return [
        int.from_bytes(frames[index : index + 2], "little", signed=True) / 32768.0
        for index in range(0, len(frames), 2)
    ], rate


def _window_rms(samples: list[float], rate: int, window_ms: float = 50.0) -> float:
    size = max(1, round(rate * window_ms / 1000))
    if len(samples) <= size:
        return math.sqrt(sum(v * v for v in samples) / max(1, len(samples)))
    best = 0.0
    step = max(1, size // 4)
    for offset in range(0, len(samples) - size + 1, step):
        frame = samples[offset : offset + size]
        best = max(best, math.sqrt(sum(v * v for v in frame) / size))
    return best


def _effective_seconds(samples: list[float], rate: int) -> float:
    """소리가 실제로 들리는 길이 — 최대치의 5%까지 떨어지는 지점."""

    peak = max((abs(v) for v in samples), default=0.0)
    if peak <= 0:
        return 0.0
    threshold = peak * 0.05
    for index in range(len(samples) - 1, -1, -1):
        if abs(samples[index]) >= threshold:
            return (index + 1) / rate
    return 0.0


def _spectral_centroid(samples: list[float], rate: int) -> float:
    size = 1024
    hop = size // 2
    bins = size // 2
    hann = [
        0.5 - 0.5 * math.cos(math.tau * index / (size - 1)) for index in range(size)
    ]
    twiddle = [
        [
            cmath.exp(-2j * math.pi * bin_index * position / size)
            for position in range(size)
        ]
        for bin_index in range(bins)
    ]
    magnitude = [0.0] * bins
    frames = 0
    for offset in range(0, max(1, len(samples) - size + 1), hop):
        frame = samples[offset : offset + size]
        if len(frame) < size:
            frame = frame + [0.0] * (size - len(frame))
        frame = [frame[index] * hann[index] for index in range(size)]
        for bin_index in range(bins):
            row = twiddle[bin_index]
            total = sum(frame[position] * row[position] for position in range(size))
            magnitude[bin_index] += abs(total)
        frames += 1
    if not frames:
        return 0.0
    weighted = 0.0
    total = 0.0
    for bin_index in range(bins):
        value = magnitude[bin_index] / frames
        weighted += value * (bin_index * rate / size)
        total += value
    return weighted / total if total > 0 else 0.0


def verify(folder: Path) -> int:
    problems: list[str] = []
    steps: dict[str, tuple[float, float, float]] = {}
    discovers: dict[str, tuple[float, float]] = {}

    for material in STEP_BUILDERS:
        path = folder / f"step-{material}.wav"
        if not path.exists():
            problems.append(f"{path.name}: 파일이 없습니다")
            continue
        samples, rate = _read(path)
        seconds = len(samples) / rate
        rms = _window_rms(samples, rate)
        centroid = _spectral_centroid(samples, rate)
        effective = _effective_seconds(samples, rate)
        steps[material] = (rms, centroid, effective)

        if seconds > MAX_STEP_SECONDS:
            problems.append(
                f"step-{material}: {seconds:.2f}초는 걸음으로 깁니다 "
                f"(상한 {MAX_STEP_SECONDS}초)"
            )
        peak = max((abs(v) for v in samples), default=0.0)
        if peak > MAX_TRUE_PEAK:
            problems.append(f"step-{material}: peak {peak:.2f}가 상한을 넘습니다")
        offset = abs(sum(samples) / max(1, len(samples)))
        if offset > MAX_DC_OFFSET:
            problems.append(f"step-{material}: DC 오프셋 {offset:.4f}")
        tail = max((abs(v) for v in samples[-64:]), default=0.0)
        if tail > MAX_TAIL_LEVEL:
            problems.append(f"step-{material}: 끝이 {tail:.3f}에서 잘립니다")

    for key in DISCOVER_SPECS:
        path = folder / f"discover-{key}.wav"
        if not path.exists():
            problems.append(f"{path.name}: 파일이 없습니다")
            continue
        samples, rate = _read(path)
        rms = _window_rms(samples, rate)
        effective = _effective_seconds(samples, rate)
        discovers[key] = (rms, effective)
        peak = max((abs(v) for v in samples), default=0.0)
        if peak > MAX_TRUE_PEAK:
            problems.append(f"discover-{key}: peak {peak:.2f}가 상한을 넘습니다")
        tail = max((abs(v) for v in samples[-64:]), default=0.0)
        if tail > MAX_TAIL_LEVEL:
            problems.append(f"discover-{key}: 끝이 {tail:.3f}에서 잘립니다")

    # 1. 걸음 vs 같은 이름의 접촉음
    for material in ("leaf", "wood", "stone"):
        contact = RUNTIME_DIR / f"contact-{material}.wav"
        if material not in steps or not contact.exists():
            continue
        contact_samples, contact_rate = _read(contact)
        step_rms, step_centroid, step_seconds = steps[material]
        contact_rms = _window_rms(contact_samples, contact_rate)
        contact_centroid = _spectral_centroid(contact_samples, contact_rate)
        contact_seconds = _effective_seconds(contact_samples, contact_rate)

        quieter = step_rms / max(contact_rms, 1e-9) < STEP_QUIETER_RATIO
        darker = step_centroid / max(contact_centroid, 1e-9) < STEP_DARKER_RATIO
        shorter = step_seconds / max(contact_seconds, 1e-9) < STEP_SHORTER_RATIO
        passed = sum((quieter, darker, shorter))
        if passed < 2:
            problems.append(
                f"step-{material}이 contact-{material}과 너무 닮았습니다 "
                f"(조용함 {quieter}, 어두움 {darker}, 짧음 {shorter}). "
                f"걷는 내내 전투처럼 들립니다"
            )

    # 2. 걸음끼리
    names = sorted(steps)
    for first_index in range(len(names)):
        for second_index in range(first_index + 1, len(names)):
            first, second = names[first_index], names[second_index]
            _rms_a, centroid_a, seconds_a = steps[first]
            _rms_b, centroid_b, seconds_b = steps[second]
            centroid_ratio = max(centroid_a, centroid_b) / max(
                min(centroid_a, centroid_b), 1e-9
            )
            decay_ratio = max(seconds_a, seconds_b) / max(
                min(seconds_a, seconds_b), 1e-9
            )
            if centroid_ratio < MIN_CENTROID_RATIO and decay_ratio < MIN_DECAY_RATIO:
                problems.append(
                    f"step-{first}과 step-{second}이 구분되지 않습니다 "
                    f"(밝기 {centroid_ratio:.2f}배, 길이 {decay_ratio:.2f}배)"
                )

    # 3. 발견 셋의 무게 순서
    order = [key for key in ("normal", "story", "target") if key in discovers]
    lengths = [discovers[key][1] for key in order]
    if lengths != sorted(lengths):
        problems.append(
            f"발견 cue가 순서대로 길어지지 않습니다: "
            + ", ".join(f"{key} {discovers[key][1]:.2f}초" for key in order)
        )
    if "target" in discovers and discovers["target"][1] < MIN_TARGET_SECONDS:
        problems.append(
            f"discover-target이 {discovers['target'][1]:.2f}초로 짧습니다. "
            f"찾던 것을 찾은 순간인데 여운이 없습니다"
        )

    # 4. 걸음 < 발견 음량
    if steps and discovers:
        loudest_step = max(rms for rms, _c, _s in steps.values())
        quietest_discover = min(rms for rms, _s in discovers.values())
        if loudest_step >= quietest_discover:
            problems.append(
                f"가장 큰 걸음({loudest_step:.3f})이 가장 작은 발견"
                f"({quietest_discover:.3f})보다 큽니다"
            )

    print(f"걸음 {len(steps)}개, 발견 {len(discovers)}개")
    for material, (rms, centroid, seconds) in sorted(steps.items()):
        print(
            f"  step-{material:6} RMS {rms:.3f}  밝기 {centroid:5.0f}Hz  "
            f"길이 {seconds * 1000:5.0f}ms"
        )
    for key in ("normal", "story", "target"):
        if key in discovers:
            rms, seconds = discovers[key]
            print(f"  discover-{key:7} RMS {rms:.3f}  길이 {seconds * 1000:5.0f}ms")

    if problems:
        print("\n실패:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("\n모두 통과했습니다.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    return verify(args.folder)


if __name__ == "__main__":
    sys.exit(main())
