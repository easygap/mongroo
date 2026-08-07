"""탐험 전투에 사용할 짧은 효과음을 결정론적으로 만든다.

외부 샘플을 쓰지 않고 기본 파형과 제한된 노이즈만 합성해 저작권과
번들 용량 문제를 피한다. 같은 시드에서 항상 같은 PCM WAV가 만들어진다.
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44_100


def _envelope(index: int, total: int, attack: float = 0.025) -> float:
    progress = index / max(1, total - 1)
    fade_in = min(1.0, progress / attack)
    # 짧은 효과음이 끝에서 튀지 않도록 매끄럽게 감쇠시킨다.
    fade_out = (1 - progress) ** 2.15
    return math.sin(fade_in * math.pi / 2) * fade_out


def _tone(
    duration: float,
    start_hz: float,
    end_hz: float,
    *,
    harmonics: tuple[tuple[float, float], ...] = ((1.0, 1.0),),
) -> list[float]:
    total = round(SAMPLE_RATE * duration)
    phase = 0.0
    samples: list[float] = []
    for index in range(total):
        progress = index / max(1, total - 1)
        frequency = start_hz + (end_hz - start_hz) * progress
        phase += math.tau * frequency / SAMPLE_RATE
        value = sum(
            gain * math.sin(phase * multiplier)
            for multiplier, gain in harmonics
        )
        samples.append(value * _envelope(index, total))
    return samples


def _noise(duration: float, *, seed: int, decay: float = 4.0) -> list[float]:
    rng = random.Random(seed)
    total = round(SAMPLE_RATE * duration)
    previous = 0.0
    samples: list[float] = []
    for index in range(total):
        # 난수를 한 번 필터링해 거친 백색 잡음 대신 작은 충격감만 남긴다.
        current = rng.uniform(-1, 1)
        previous = previous * 0.35 + current * 0.65
        progress = index / max(1, total - 1)
        samples.append(previous * (1 - progress) ** decay)
    return samples


def _mix(*tracks: tuple[list[float], float, float]) -> list[float]:
    """(samples, gain, start_seconds) 트랙을 하나로 합친다."""

    total = max(
        round(start * SAMPLE_RATE) + len(samples)
        for samples, _, start in tracks
    )
    output = [0.0] * total
    for samples, gain, start in tracks:
        offset = round(start * SAMPLE_RATE)
        for index, value in enumerate(samples):
            output[offset + index] += value * gain
    peak = max(abs(value) for value in output) or 1.0
    scale = 0.86 / peak
    return [value * scale for value in output]


def _write(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", round(max(-1.0, min(1.0, value)) * 32767))
        for value in samples
    )
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


def build(output_root: Path) -> None:
    sounds = {
        "combat-command.wav": _mix(
            (_tone(0.085, 430, 690, harmonics=((1, 1), (2, 0.18))), 0.9, 0),
            (_noise(0.045, seed=11, decay=5.5), 0.24, 0),
        ),
        "combat-hit.wav": _mix(
            (_tone(0.19, 155, 64, harmonics=((1, 1), (2, 0.28))), 0.75, 0),
            (_noise(0.16, seed=23, decay=3.2), 0.72, 0),
        ),
        "combat-weakness.wav": _mix(
            (_tone(0.20, 650, 900, harmonics=((1, 1), (2, 0.12))), 0.7, 0),
            (_tone(0.22, 880, 1180, harmonics=((1, 1), (2, 0.1))), 0.55, 0.07),
            (_tone(0.20, 1100, 1450), 0.4, 0.15),
        ),
        "combat-enemy.wav": _mix(
            (_tone(0.34, 118, 72, harmonics=((1, 1), (1.5, 0.22))), 0.82, 0),
            (_noise(0.28, seed=37, decay=2.6), 0.34, 0.04),
        ),
        "combat-guard.wav": _mix(
            (_tone(0.23, 940, 510, harmonics=((1, 1), (2, 0.2))), 0.62, 0),
            (_tone(0.20, 470, 390), 0.4, 0.025),
            (_noise(0.07, seed=51, decay=5), 0.18, 0),
        ),
        "combat-victory.wav": _mix(
            (_tone(0.28, 523, 659, harmonics=((1, 1), (2, 0.12))), 0.72, 0),
            (_tone(0.32, 659, 784, harmonics=((1, 1), (2, 0.1))), 0.66, 0.09),
            (_tone(0.36, 784, 1046, harmonics=((1, 1), (2, 0.08))), 0.58, 0.18),
            (_noise(0.20, seed=67, decay=5.8), 0.10, 0.20),
        ),
        "combat-defeat.wav": _mix(
            (_tone(0.42, 330, 196, harmonics=((1, 1), (1.5, 0.16))), 0.76, 0),
            (_tone(0.35, 247, 147, harmonics=((1, 1), (2, 0.12))), 0.56, 0.14),
            (_noise(0.22, seed=79, decay=3.8), 0.16, 0.04),
        ),
    }
    for filename, samples in sounds.items():
        _write(output_root / filename, samples)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("app/assets/adventure/sfx"),
    )
    args = parser.parse_args()
    build(args.output_root)


if __name__ == "__main__":
    main()
