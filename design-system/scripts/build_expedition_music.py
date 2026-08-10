"""이끼 기억서고 세로 슬라이스용 반응형 음악 에셋을 합성한다.

외부 샘플 없이 부드러운 순환 드론, 펠트·마림바 계열 배음, 종이 질감과 절제한
나무 타격음을 합성해 기본·전투·수호자 믹스로 나눈다. 마스터는 48kHz 24비트
스테레오 WAV, 런타임 파일은 AAC-LC M4A로 만든다. 다운로드 파일이나 생성형
오디오 원본은 사용하지 않는다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import shutil
import subprocess
import wave
from array import array
from pathlib import Path

SAMPLE_RATE = 48_000
LOOP_SECONDS = 16.0
SAMPLE_COUNT = round(SAMPLE_RATE * LOOP_SECONDS)


def _empty() -> tuple[array, array]:
    return array("f", [0.0]) * SAMPLE_COUNT, array("f", [0.0]) * SAMPLE_COUNT


def _pan_gains(pan: float) -> tuple[float, float]:
    angle = (max(-1.0, min(1.0, pan)) + 1) * math.pi / 4
    return math.cos(angle), math.sin(angle)


def _add_tone(
    left: array,
    right: array,
    *,
    start: float,
    duration: float,
    frequency: float,
    gain: float,
    pan: float = 0,
    harmonics: tuple[tuple[float, float], ...] = ((1.0, 1.0),),
    attack: float = 0.018,
    decay: float = 4.2,
) -> None:
    first = round(start * SAMPLE_RATE)
    length = min(round(duration * SAMPLE_RATE), SAMPLE_COUNT - first)
    left_gain, right_gain = _pan_gains(pan)
    phase = 0.0
    for offset in range(max(0, length)):
        progress = offset / max(1, length - 1)
        fade_in = min(1.0, progress / attack)
        envelope = math.sin(fade_in * math.pi / 2) * (1 - progress) ** decay
        phase += math.tau * frequency / SAMPLE_RATE
        sample = sum(
            harmonic_gain * math.sin(phase * multiplier)
            for multiplier, harmonic_gain in harmonics
        )
        value = sample * envelope * gain
        index = first + offset
        left[index] += value * left_gain
        right[index] += value * right_gain


def _add_loop_drone(
    left: array,
    right: array,
    *,
    cycles: int,
    gain: float,
    pan: float,
    breath_cycles: int,
) -> None:
    left_gain, right_gain = _pan_gains(pan)
    for index in range(SAMPLE_COUNT):
        progress = index / SAMPLE_COUNT
        breath = 0.74 + 0.26 * math.cos(math.tau * breath_cycles * progress)
        value = math.sin(math.tau * cycles * progress) * breath * gain
        left[index] += value * left_gain
        right[index] += value * right_gain


def _add_paper(
    left: array,
    right: array,
    *,
    start: float,
    duration: float,
    seed: int,
    gain: float,
    pan: float,
) -> None:
    rng = random.Random(seed)
    first = round(start * SAMPLE_RATE)
    length = min(round(duration * SAMPLE_RATE), SAMPLE_COUNT - first)
    left_gain, right_gain = _pan_gains(pan)
    filtered = 0.0
    for offset in range(max(0, length)):
        progress = offset / max(1, length - 1)
        raw = rng.uniform(-1, 1)
        filtered = filtered * 0.64 + raw * 0.36
        envelope = math.sin(math.pi * progress) ** 1.8
        value = filtered * envelope * gain
        index = first + offset
        left[index] += value * left_gain
        right[index] += value * right_gain


def _base_score() -> tuple[array, array]:
    left, right = _empty()
    # 모든 주파수를 16초 안의 정수 주기로 맞춰 순환 경계가 정확히 이어진다.
    _add_loop_drone(left, right, cycles=1048, gain=0.022, pan=-0.22, breath_cycles=2)
    _add_loop_drone(left, right, cycles=1568, gain=0.016, pan=0.22, breath_cycles=1)
    notes = [261.63, 196.00, 220.00, 329.63, 293.66, 220.00, 196.00, 261.63]
    for index, (beat, frequency) in enumerate(zip(range(0, 16, 2), notes)):
        _add_tone(
            left,
            right,
            start=float(beat),
            duration=0.82,
            frequency=frequency,
            gain=0.105,
            pan=-0.30 if index % 2 == 0 else 0.30,
            harmonics=((1, 1), (2, 0.17), (3, 0.05)),
            decay=5.0,
        )
    _add_paper(left, right, start=3.35, duration=0.34, seed=401, gain=0.018, pan=-0.4)
    _add_paper(left, right, start=11.35, duration=0.34, seed=409, gain=0.018, pan=0.4)
    return left, right


def _add_combat_pulse(left: array, right: array, *, guardian: bool) -> None:
    for beat in range(16):
        _add_tone(
            left,
            right,
            start=beat + 0.02,
            duration=0.085,
            frequency=196 if beat % 4 else 147,
            gain=0.040 if guardian else 0.028,
            pan=-0.12 if beat % 2 == 0 else 0.12,
            harmonics=((1, 1), (2, 0.22)),
            attack=0.006,
            decay=8.0,
        )
        _add_paper(
            left,
            right,
            start=beat + 0.015,
            duration=0.055,
            seed=700 + beat + (100 if guardian else 0),
            gain=0.010 if guardian else 0.007,
            pan=0.08 if beat % 2 == 0 else -0.08,
        )
    if guardian:
        for beat in (0, 4, 8, 12):
            _add_tone(
                left,
                right,
                start=beat,
                duration=0.54,
                frequency=73.5,
                gain=0.095,
                harmonics=((1, 1), (1.5, 0.18), (2, 0.09)),
                attack=0.006,
                decay=4.8,
            )
        for beat in (0, 8):
            _add_tone(
                left,
                right,
                start=beat + 0.1,
                duration=1.25,
                frequency=392.0,
                gain=0.045,
                pan=0.18,
                harmonics=((1, 1), (2, 0.09)),
                decay=3.4,
            )


def _normalise(left: array, right: array, target_rms: float) -> tuple[array, array]:
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
    energy = sum(value * value for value in left) + sum(value * value for value in right)
    rms = math.sqrt(energy / max(1, len(left) + len(right)))
    scale = min(0.82 / max(peak, 1e-9), target_rms / max(rms, 1e-9))
    for index in range(SAMPLE_COUNT):
        left[index] *= scale
        right[index] *= scale
    return left, right


def _write_pcm24(path: Path, left: array, right: array) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for left_value, right_value in zip(left, right):
        for value in (left_value, right_value):
            integer = round(max(-1.0, min(1.0, value)) * 8_388_607)
            frames.extend(integer.to_bytes(3, "little", signed=True))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(3)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


def _runtime_encode(master: Path, runtime: Path, target_lufs: int) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("ffmpeg is required to encode the runtime M4A assets")
    runtime.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(master),
            "-af",
            f"loudnorm=I={target_lufs}:TP=-2:LRA=4",
            "-ar",
            str(SAMPLE_RATE),
            "-c:a",
            "aac",
            "-profile:a",
            "aac_low",
            "-b:a",
            "128k",
            str(runtime),
        ],
        check=True,
    )


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(master_root: Path, runtime_root: Path) -> dict:
    base_left, base_right = _base_score()
    mixes: dict[str, tuple[array, array, float, int]] = {
        "base": (array("f", base_left), array("f", base_right), 0.048, -20),
        "combat": (array("f", base_left), array("f", base_right), 0.060, -19),
        "guardian": (array("f", base_left), array("f", base_right), 0.070, -18),
    }
    _add_combat_pulse(mixes["combat"][0], mixes["combat"][1], guardian=False)
    _add_combat_pulse(mixes["guardian"][0], mixes["guardian"][1], guardian=True)

    files: list[dict] = []
    for state, (left, right, target_rms, target_lufs) in mixes.items():
        _normalise(left, right, target_rms)
        master = master_root / f"moss-archive-{state}-master.wav"
        runtime = runtime_root / f"moss-archive-{state}.m4a"
        _write_pcm24(master, left, right)
        _runtime_encode(master, runtime, target_lufs)
        files.append(
            {
                "state": state,
                "master": master.as_posix(),
                "runtime": runtime.as_posix(),
                "duration_seconds": LOOP_SECONDS,
                "sample_rate": SAMPLE_RATE,
                "master_bit_depth": 24,
                "target_lufs": target_lufs,
                "master_sha256": _sha256(master),
                "runtime_sha256": _sha256(runtime),
            }
        )
    manifest = {
        "asset_key": "moss_archive_adaptive_music_v1",
        "authorship": "original deterministic synthesis; no external samples",
        "bpm": 60,
        "loop_seconds": LOOP_SECONDS,
        "shared_motif": "C-G-A-E, four-note Garden Return motif",
        "files": files,
    }
    master_root.mkdir(parents=True, exist_ok=True)
    (master_root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--master-root",
        type=Path,
        default=Path("design-system/audio/adventure-moss-archive-v1"),
    )
    parser.add_argument(
        "--runtime-root",
        type=Path,
        default=Path("app/assets/adventure/music"),
    )
    args = parser.parse_args()
    print(json.dumps(build(args.master_root, args.runtime_root), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
