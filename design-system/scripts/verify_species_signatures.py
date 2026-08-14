"""품종 signature 32종을 적용 **전에** 검사한다.

핵심 질문은 하나다. **소리만 듣고 누가 했는지 알 수 있는가.**

그래서 가장 중요한 검사는 구조적이다.

- **같은 품종의 두 스킬은 서로 가까워야 한다.** 뽀또의 1번과 2번은 같은 재료다.
- **다른 품종과는 멀어야 한다.** 뽀또와 여우비가 비슷하면 캐릭터가 안 읽힌다.
- 두 조건을 하나로 묶으면: **품종 내부 거리 < 그 품종이 남과 갖는 최소 거리**.
  이게 깨지면 signature가 signature가 아니다.

그 밖에:

- 2번 스킬은 1번보다 크고 길다(Lv7에 열리는 쪽이 더 멀리 간다).
- 접촉 재질음보다 조용하다 — 믹스에서 접촉이 1순위, 시전자 signature가 3순위다.
- 길이 예산·peak·DC·끝단 무음.

거리는 **로그 밝기와 로그 길이의 2차원 유클리드 거리**로 잰다. 사람 귀는 주파수와
시간을 비율로 느끼므로 로그가 맞다.

사용법:
    python verify_species_signatures.py <검사할 폴더>
"""

from __future__ import annotations

import argparse
import cmath
import math
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_species_signatures import (  # noqa: E402
    MAX_SECONDS,
    RUNTIME_DIR,
    SKILLS,
)

MAX_TRUE_PEAK = 0.79
MAX_DC_OFFSET = 0.002
MAX_TAIL_LEVEL = 0.02

# 접촉 재질음보다 이 배 이상 크면 안 된다. 접촉이 먼저 들려야 한다.
MAX_VS_CONTACT_RMS = 0.95

# 같은 품종 두 스킬이 이보다 멀면 같은 캐릭터로 안 들린다.
MAX_WITHIN_DISTANCE = 0.32
# 다른 품종과 이보다 가까우면 헷갈린다.
MIN_BETWEEN_DISTANCE = 0.14


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


# 길이 축의 가중치. **정체성은 음색(밝기)이고 길이는 크기다.** 2번 스킬이
# 1번보다 긴 것은 의도된 설계인데, 길이를 밝기와 같은 무게로 재면 그 의도가
# `같은 캐릭터가 아니다`로 잘못 읽힌다. 길이도 정보이긴 하므로 0은 아니다.
LENGTH_WEIGHT = 0.45


def _distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    """로그 밝기·로그 길이 평면에서의 가중 거리.

    귀는 400Hz→800Hz와 800Hz→1600Hz를 같은 크기의 변화로 느낀다. 선형 Hz로
    재면 높은 소리끼리만 멀어 보이고 낮은 소리끼리는 다 붙어 보인다.

    길이 축에는 `LENGTH_WEIGHT`를 곱한다 — 위 상수의 이유를 보라.
    """

    brightness = math.log(max(a[0], 1.0)) - math.log(max(b[0], 1.0))
    length = math.log(max(a[1], 1e-4)) - math.log(max(b[1], 1e-4))
    return math.hypot(brightness, length * LENGTH_WEIGHT)


def verify(folder: Path) -> int:
    problems: list[str] = []
    # (species, slot) → (centroid, seconds, rms)
    measured: dict[tuple[str, str], tuple[float, float, float]] = {}

    for species, (primary, secondary) in SKILLS.items():
        for slot, code in (("unique_1", primary), ("unique_2", secondary)):
            slug = code.replace("_", "-")
            path = folder / f"skill-{species}-{slug}.wav"
            if not path.exists():
                problems.append(f"{path.name}: 파일이 없습니다")
                continue
            samples, rate = _read(path)
            seconds = len(samples) / rate
            measured[(species, slot)] = (
                _spectral_centroid(samples, rate),
                _effective_seconds(samples, rate),
                _window_rms(samples, rate),
            )
            if seconds > MAX_SECONDS + 0.01:
                problems.append(
                    f"{path.name}: {seconds:.2f}초가 예산 {MAX_SECONDS}초를 넘습니다"
                )
            peak = max((abs(v) for v in samples), default=0.0)
            if peak > MAX_TRUE_PEAK:
                problems.append(f"{path.name}: peak {peak:.2f}가 상한을 넘습니다")
            offset = abs(sum(samples) / max(1, len(samples)))
            if offset > MAX_DC_OFFSET:
                problems.append(f"{path.name}: DC 오프셋 {offset:.4f}")
            tail = max((abs(v) for v in samples[-64:]), default=0.0)
            if tail > MAX_TAIL_LEVEL:
                problems.append(f"{path.name}: 끝이 {tail:.3f}에서 잘립니다")

    # 1. 2번 스킬이 1번보다 크고 길다.
    for species in SKILLS:
        first = measured.get((species, "unique_1"))
        second = measured.get((species, "unique_2"))
        if first is None or second is None:
            continue
        if second[1] <= first[1]:
            problems.append(
                f"{species}: 2번 스킬이 1번보다 길지 않습니다 "
                f"({second[1] * 1000:.0f}ms ≤ {first[1] * 1000:.0f}ms)"
            )
        if second[2] < first[2]:
            problems.append(f"{species}: 2번 스킬이 1번보다 작습니다")

    # 2. 품종 내부 거리 < 품종 간 최소 거리 — 이게 핵심이다.
    voices = {
        species: (
            (measured[(species, "unique_1")][0] + measured[(species, "unique_2")][0])
            / 2,
            (measured[(species, "unique_1")][1] + measured[(species, "unique_2")][1])
            / 2,
        )
        for species in SKILLS
        if (species, "unique_1") in measured and (species, "unique_2") in measured
    }
    for species in voices:
        first = measured[(species, "unique_1")]
        second = measured[(species, "unique_2")]
        within = _distance((first[0], first[1]), (second[0], second[1]))
        if within > MAX_WITHIN_DISTANCE:
            problems.append(
                f"{species}: 두 스킬이 서로 {within:.2f}만큼 떨어져 있습니다. "
                f"같은 캐릭터로 안 들립니다"
            )
        others = [
            (_distance(voices[species], voices[other]), other)
            for other in voices
            if other != species
        ]
        if not others:
            continue
        nearest, neighbour = min(others)
        if nearest < MIN_BETWEEN_DISTANCE:
            problems.append(
                f"{species}와 {neighbour}가 {nearest:.2f}만큼밖에 안 떨어져 "
                f"있습니다. 소리로 구분되지 않습니다"
            )
        if within >= nearest:
            problems.append(
                f"{species}: 자기 두 스킬 사이({within:.2f})가 "
                f"{neighbour}와의 거리({nearest:.2f})보다 멉니다. "
                f"품종이 아니라 스킬이 들립니다"
            )

    # 3. 접촉 재질음보다 조용한가.
    contact = RUNTIME_DIR / "contact-wood.wav"
    if contact.exists() and measured:
        contact_samples, contact_rate = _read(contact)
        contact_rms = _window_rms(contact_samples, contact_rate)
        loudest = max(rms for _c, _s, rms in measured.values())
        if loudest > contact_rms * MAX_VS_CONTACT_RMS:
            problems.append(
                f"가장 큰 signature({loudest:.3f})가 접촉음"
                f"({contact_rms:.3f})보다 큽니다. 접촉이 먼저 들려야 합니다"
            )

    print(f"검사한 signature {len(measured)}개, 품종 {len(voices)}종")
    for species in sorted(voices):
        centroid, seconds = voices[species]
        first = measured[(species, "unique_1")]
        second = measured[(species, "unique_2")]
        within = _distance((first[0], first[1]), (second[0], second[1]))
        nearest = min(
            _distance(voices[species], voices[other])
            for other in voices
            if other != species
        )
        print(
            f"  {species:16} 밝기 {centroid:5.0f}Hz  길이 {seconds * 1000:4.0f}ms  "
            f"내부 {within:.2f} / 최근접 {nearest:.2f}"
        )

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
