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
    color: float = 0.64,
) -> None:
    """손으로 만지는 재질 한 겹 — 종이·도자기·브러시·나무를 같은 식으로 만든다.

    `color`는 한 극점 저역 통과의 계수다. 값이 클수록 어둡고 뭉근해서 나무·펠트에
    가깝고, 작을수록 밝고 서걱거려 종이·브러시에 가깝다. 재질을 바꾸려고 새 합성기를
    만들지 않고 이 계수와 길이만 바꾼다.
    """

    rng = random.Random(seed)
    first = round(start * SAMPLE_RATE)
    length = min(round(duration * SAMPLE_RATE), SAMPLE_COUNT - first)
    left_gain, right_gain = _pan_gains(pan)
    filtered = 0.0
    for offset in range(max(0, length)):
        progress = offset / max(1, length - 1)
        raw = rng.uniform(-1, 1)
        filtered = filtered * color + raw * (1 - color)
        envelope = math.sin(math.pi * progress) ** 1.8
        value = filtered * envelope * gain
        index = first + offset
        left[index] += value * left_gain
        right[index] += value * right_gain


# ── 지역 네 곳의 악보 ────────────────────────────────────────────────────────
#
# `ADVENTURE_AUDIO.md`의 지역별 BPM·악기·금지 방향을 그대로 옮긴 표다. 네 지역은
# 서로 다른 곡이지만 **정원으로 돌아가는 동기 C-G-A-E**를 각자 한 번씩 낮은
# 음량으로 지나간다. 뒤 지역이라고 악기 수나 음량을 올리지 않는다 — 정규화
# 목표값은 지역과 무관하게 아래 MIX_TARGETS 하나만 쓴다.
#
# 순환 경계가 정확히 이어지려면 두 조건을 지켜야 한다.
#   1) 드론 주기(cycles)는 16초 안의 정수여야 한다.
#   2) 16초 안의 박자 수가 정수여야 combat pulse가 loop에서 튀지 않는다.
#      BPM = 3.75 × (박자 수)이므로 60 / 63.75 / 56.25만 문서 범위에 들어온다.

NOTE = {
    "C3": 130.81,
    "E3": 164.81,
    "G3": 196.00,
    "A3": 220.00,
    "B3": 246.94,
    "C4": 261.63,
    "D4": 293.66,
    "E4": 329.63,
    "F4": 349.23,
    "G4": 392.00,
    "A4": 440.00,
    "B4": 493.88,
    "C5": 523.25,
    "E5": 659.25,
    "C6": 1046.50,
}

# 정원 복귀 동기. 네 지역 악보의 앞 네 음이 반드시 이 순서를 지난다.
GARDEN_RETURN_MOTIF = ("C", "G", "A", "E")

REGIONS: dict[str, dict] = {
    # 이끼 낀 기억서고 — 낮은 마림바, 종이 넘김, 한 음의 따뜻한 드론.
    "moss_archive": {
        "slug": "moss-archive",
        "name": "이끼 낀 기억서고",
        "bpm": 60,
        "beats": 16,
        "drones": ((1048, 0.022, -0.22, 2), (1568, 0.016, 0.22, 1)),
        "notes": ("C4", "G3", "A3", "E4", "D4", "A3", "G3", "C4"),
        "note_beat_step": 2,
        "note_duration": 0.82,
        "note_gain": 0.105,
        "note_harmonics": ((1, 1), (2, 0.17), (3, 0.05)),
        "note_attack": 0.018,
        "note_decay": 5.0,
        "textures": (
            (3.35, 0.34, 401, 0.018, -0.4, 0.64),
            (11.35, 0.34, 409, 0.018, 0.4, 0.64),
        ),
        "pulse_hz": (196, 147),
        "pulse_color": 0.64,
        "guardian_low_hz": 73.5,
        "guardian_bell_hz": 392.0,
    },
    # 메아리 우물정원 — 나무 플루트, 빈 도자기 스침, 아주 낮은 물결.
    # 금지: 반복되는 물방울, 우물을 무섭게 만드는 저음.
    "echo_well": {
        "slug": "echo-well",
        "name": "메아리 우물정원",
        "bpm": 63.75,
        "beats": 17,
        # 물결은 드론의 숨 주기를 늘려 만든다. 새 저음 악기를 넣지 않는다.
        "drones": ((1136, 0.021, -0.24, 3), (1704, 0.015, 0.24, 2)),
        "notes": ("C5", "G4", "A4", "E5", "B4", "A4", "G4", "E4"),
        "note_beat_step": 2,
        "note_duration": 0.88,
        "note_gain": 0.088,
        # 플루트는 배음이 약하고 짝수 배음만 살짝 남는다.
        "note_harmonics": ((1, 1), (2, 0.12), (3, 0.04)),
        "note_attack": 0.090,
        "note_decay": 3.2,
        # 메아리 — 같은 플루트를 한 박자 뒤 반대편에서 훨씬 작게 되풀이한다.
        "echo": {"delay_beats": 1, "gain_ratio": 0.34, "pan": 0.42},
        # 빈 도자기를 손으로 스치는 소리. 종이보다 밝고 짧다.
        "textures": (
            (2.6, 0.30, 421, 0.015, 0.38, 0.52),
            (10.6, 0.30, 431, 0.015, -0.38, 0.52),
        ),
        "pulse_hz": (233, 175),
        "pulse_color": 0.52,
        "guardian_low_hz": 87.3,
        "guardian_bell_hz": 466.2,
    },
    # 별빛 씨앗 보관고 — 펠트 피아노, 짧은 셀레스타 한 음, 부드러운 구리 브러시.
    # 금지: 유리 효과음 반복, 우주·마법 분위기의 과장.
    "starlight_seed_vault": {
        "slug": "starlight-seed-vault",
        "name": "별빛 씨앗 보관고",
        "bpm": 56.25,
        "beats": 15,
        "drones": ((880, 0.022, -0.20, 2), (1320, 0.015, 0.20, 1)),
        "notes": ("C4", "G4", "A4", "E4", "F4", "D4", "B3", "C4"),
        "note_beat_step": 2,
        "note_duration": 0.94,
        "note_gain": 0.098,
        # 펠트 해머는 배음이 부드럽게 남고 고배음이 빨리 사라진다.
        "note_harmonics": ((1, 1), (2, 0.20), (3, 0.06), (6, 0.03)),
        "note_attack": 0.030,
        "note_decay": 4.6,
        # 셀레스타는 한 곡에 **한 음**뿐이다. 반짝임을 반복하지 않는다.
        "sparkle": {
            "note": "C6",
            "start": 7.2,
            "duration": 1.10,
            "gain": 0.030,
            "harmonics": ((1, 1), (3, 0.10), (5, 0.04)),
            "decay": 5.6,
            "pan": 0.30,
        },
        # 구리 브러시 — 길고 아주 여린 결.
        "textures": (
            (1.9, 0.52, 443, 0.012, -0.36, 0.40),
            (9.9, 0.52, 449, 0.012, 0.36, 0.40),
        ),
        "pulse_hz": (208, 156),
        "pulse_color": 0.40,
        "guardian_low_hz": 78.0,
        "guardian_bell_hz": 415.3,
    },
    # 마음나무 관측실 — 펠트 피아노, 낮은 나무 타악기, 숨결이 짧은 플루트.
    # 완주를 선언하는 팡파르 대신 조용히 정리되는 두 마디로 마친다.
    "heartwood_observatory": {
        "slug": "heartwood-observatory",
        "name": "마음나무 관측실",
        "bpm": 56.25,
        "beats": 15,
        "drones": ((816, 0.023, -0.18, 2), (1224, 0.014, 0.18, 1)),
        # 다른 지역보다 음이 적다. 마지막 두 음이 조용히 정리하는 두 마디다.
        "notes": ("C4", "G3", "A3", "E4", "D4", "G3"),
        "note_beat_step": 2,
        "note_duration": 1.00,
        "note_gain": 0.094,
        "note_harmonics": ((1, 1), (2, 0.13), (3, 0.04)),
        "note_attack": 0.034,
        "note_decay": 4.2,
        "closing": {
            "notes": ("G3", "C3"),
            "starts": (12.1, 13.7),
            "duration": 1.05,
            "gain": 0.062,
            "harmonics": ((1, 1), (2, 0.10)),
            "decay": 3.6,
        },
        # 숨결이 짧은 플루트 두 번.
        "breaths": (
            {"note": "E4", "start": 5.4, "duration": 0.46, "gain": 0.034},
            {"note": "C4", "start": 11.0, "duration": 0.46, "gain": 0.030},
        ),
        # 낮은 나무 타악기 — 가장 어둡고 뭉근한 결.
        "textures": (
            (3.0, 0.26, 461, 0.017, -0.32, 0.76),
            (9.4, 0.26, 463, 0.017, 0.32, 0.76),
        ),
        "pulse_hz": (175, 131),
        "pulse_color": 0.76,
        "guardian_low_hz": 65.4,
        "guardian_bell_hz": 349.2,
    },
}

# 지역과 무관한 단일 믹스 목표. 뒤 지역이 더 크게 들리는 수직 강화를 코드로 막는다.
MIX_TARGETS = {
    "base": (0.048, -20),
    "combat": (0.060, -19),
    "guardian": (0.070, -18),
}

# 수호자 층의 타점 수. loop를 정확히 나누는 값이어야 순환에서 박자가 튀지 않는다.
GUARDIAN_HITS = 4
GUARDIAN_BELLS = 2

# loudnorm의 true peak 한도. 문서 상한은 −2dBTP인데 loudnorm의 리미터가 정확히
# 맞추지 못해 −1.8dBTP까지 새어 나온다. 목표를 0.5dB 낮춰 상한을 확실히 지킨다.
TRUE_PEAK_TARGET_DBTP = -2.5


def _base_score(region: dict) -> tuple[array, array]:
    left, right = _empty()
    beat_seconds = 60.0 / float(region["bpm"])
    # 모든 주파수를 16초 안의 정수 주기로 맞춰 순환 경계가 정확히 이어진다.
    for cycles, gain, pan, breath in region["drones"]:
        _add_loop_drone(
            left,
            right,
            cycles=cycles,
            gain=gain,
            pan=pan,
            breath_cycles=breath,
        )
    step = int(region["note_beat_step"])
    echo = region.get("echo")
    for index, name in enumerate(region["notes"]):
        start = index * step * beat_seconds
        _add_tone(
            left,
            right,
            start=start,
            duration=float(region["note_duration"]),
            frequency=NOTE[name],
            gain=float(region["note_gain"]),
            pan=-0.30 if index % 2 == 0 else 0.30,
            harmonics=region["note_harmonics"],
            attack=float(region["note_attack"]),
            decay=float(region["note_decay"]),
        )
        if echo is None:
            continue
        # 메아리는 새 악기가 아니라 같은 음의 여린 되풀이다.
        echo_start = start + float(echo["delay_beats"]) * beat_seconds
        if echo_start + float(region["note_duration"]) >= LOOP_SECONDS:
            continue
        _add_tone(
            left,
            right,
            start=echo_start,
            duration=float(region["note_duration"]) * 0.7,
            frequency=NOTE[name],
            gain=float(region["note_gain"]) * float(echo["gain_ratio"]),
            pan=float(echo["pan"]) * (1 if index % 2 == 0 else -1),
            harmonics=region["note_harmonics"],
            attack=float(region["note_attack"]),
            decay=float(region["note_decay"]) * 1.4,
        )

    sparkle = region.get("sparkle")
    if sparkle is not None:
        _add_tone(
            left,
            right,
            start=float(sparkle["start"]),
            duration=float(sparkle["duration"]),
            frequency=NOTE[str(sparkle["note"])],
            gain=float(sparkle["gain"]),
            pan=float(sparkle["pan"]),
            harmonics=sparkle["harmonics"],
            decay=float(sparkle["decay"]),
        )

    for breath in region.get("breaths", ()):
        _add_tone(
            left,
            right,
            start=float(breath["start"]),
            duration=float(breath["duration"]),
            frequency=NOTE[str(breath["note"])],
            gain=float(breath["gain"]),
            pan=0.14,
            harmonics=((1, 1), (2, 0.09)),
            attack=0.120,
            decay=3.0,
        )

    closing = region.get("closing")
    if closing is not None:
        for name, start in zip(closing["notes"], closing["starts"]):
            _add_tone(
                left,
                right,
                start=float(start),
                duration=float(closing["duration"]),
                frequency=NOTE[name],
                gain=float(closing["gain"]),
                pan=-0.12,
                harmonics=closing["harmonics"],
                decay=float(closing["decay"]),
            )

    for start, duration, seed, gain, pan, color in region["textures"]:
        _add_paper(
            left,
            right,
            start=start,
            duration=duration,
            seed=seed,
            gain=gain,
            pan=pan,
            color=color,
        )
    return left, right


def _add_combat_pulse(
    left: array,
    right: array,
    *,
    region: dict,
    guardian: bool,
) -> None:
    """명령과 접촉의 박자를 붙잡는 얇은 layer. 새 곡으로 바뀌지 않는다."""

    beat_seconds = 60.0 / float(region["bpm"])
    beats = int(region["beats"])
    high_hz, low_hz = region["pulse_hz"]
    for index in range(beats):
        start = index * beat_seconds
        _add_tone(
            left,
            right,
            start=start + 0.02,
            duration=0.085,
            frequency=high_hz if index % 4 else low_hz,
            gain=0.040 if guardian else 0.028,
            pan=-0.12 if index % 2 == 0 else 0.12,
            harmonics=((1, 1), (2, 0.22)),
            attack=0.006,
            decay=8.0,
        )
        _add_paper(
            left,
            right,
            start=start + 0.015,
            duration=0.055,
            seed=700 + index + (100 if guardian else 0),
            gain=0.010 if guardian else 0.007,
            pan=0.08 if index % 2 == 0 else -0.08,
            color=float(region["pulse_color"]),
        )
    if not guardian:
        return
    # 수호자 층은 나무 타악과 벨 한 겹뿐이다. 곡을 갈아 끼우지 않는다.
    #
    # 타점을 `4박마다`로 두면 16초에 박자 수가 4의 배수가 아닌 지역에서 순환
    # 경계의 간격만 짧아져 박자가 덜컥거린다(17박이면 마지막 타점과 다음 첫
    # 타점이 1박 간격). 그래서 박이 아니라 **loop를 정확히 나눈 자리**에 찍는다.
    for index in range(GUARDIAN_HITS):
        _add_tone(
            left,
            right,
            start=index * LOOP_SECONDS / GUARDIAN_HITS,
            duration=0.54,
            frequency=float(region["guardian_low_hz"]),
            gain=0.095,
            harmonics=((1, 1), (1.5, 0.18), (2, 0.09)),
            attack=0.006,
            decay=4.8,
        )
    for index in range(GUARDIAN_BELLS):
        _add_tone(
            left,
            right,
            start=index * LOOP_SECONDS / GUARDIAN_BELLS + 0.1,
            duration=1.25,
            frequency=float(region["guardian_bell_hz"]),
            gain=0.045,
            pan=0.18,
            harmonics=((1, 1), (2, 0.09)),
            decay=3.4,
        )


def _normalise(left: array, right: array, target_rms: float) -> tuple[array, array]:
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right))
    energy = sum(value * value for value in left) + sum(
        value * value for value in right
    )
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
            f"loudnorm=I={target_lufs}:TP={TRUE_PEAK_TARGET_DBTP}:LRA=4",
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


def _validate_regions() -> None:
    """악보가 문서 계약을 어기면 렌더링 전에 멈춘다."""

    ranges = {
        "moss_archive": (58, 64),
        "echo_well": (60, 66),
        "starlight_seed_vault": (56, 62),
        "heartwood_observatory": (54, 60),
    }
    for code, region in REGIONS.items():
        bpm = float(region["bpm"])
        low, high = ranges[code]
        if not low <= bpm <= high:
            raise ValueError(f"{code}: BPM {bpm}은 문서 범위 {low}~{high} 밖이다")
        beats = int(region["beats"])
        if abs(bpm * LOOP_SECONDS / 60 - beats) > 1e-9:
            raise ValueError(f"{code}: 16초에 {beats}박이 정확히 들어가지 않는다")
        for cycles, *_ in region["drones"]:
            if int(cycles) != cycles:
                raise ValueError(f"{code}: 드론 주기는 정수여야 순환이 이어진다")
        # 앞 네 음이 정원 복귀 동기를 지나야 네 지역이 한 정원으로 읽힌다.
        opening = tuple(name[0] for name in region["notes"][:4])
        if opening != GARDEN_RETURN_MOTIF:
            raise ValueError(f"{code}: 앞 네 음 {opening}이 정원 복귀 동기가 아니다")
        # 마지막 음이 16초를 넘으면 순환 경계에서 잘려 click이 난다.
        beat_seconds = 60.0 / bpm
        last = (len(region["notes"]) - 1) * int(region["note_beat_step"]) * beat_seconds
        if last + float(region["note_duration"]) >= LOOP_SECONDS:
            raise ValueError(f"{code}: 마지막 음이 순환 경계를 넘는다")
        for extra in (region.get("closing"), *region.get("breaths", ())):
            if extra is None:
                continue
            starts = extra.get("starts", (extra.get("start"),))
            for start in starts:
                if float(start) + float(extra["duration"]) >= LOOP_SECONDS:
                    raise ValueError(f"{code}: 덧붙인 음이 순환 경계를 넘는다")
        sparkle = region.get("sparkle")
        if sparkle is not None and (
            float(sparkle["start"]) + float(sparkle["duration"]) >= LOOP_SECONDS
        ):
            raise ValueError(f"{code}: 셀레스타 한 음이 순환 경계를 넘는다")

    # 수호자 타점은 loop를 정확히 나눠야 순환에서 간격이 짧아지지 않는다.
    for hits in (GUARDIAN_HITS, GUARDIAN_BELLS):
        if hits <= 0 or LOOP_SECONDS % (LOOP_SECONDS / hits) > 1e-9:
            raise ValueError(f"수호자 타점 {hits}개가 loop를 고르게 나누지 않는다")


def build_region(code: str, master_root: Path, runtime_root: Path) -> dict:
    region = REGIONS[code]
    slug = str(region["slug"])
    base_left, base_right = _base_score(region)
    mixes: dict[str, tuple[array, array]] = {
        state: (array("f", base_left), array("f", base_right)) for state in MIX_TARGETS
    }
    _add_combat_pulse(*mixes["combat"], region=region, guardian=False)
    _add_combat_pulse(*mixes["guardian"], region=region, guardian=True)

    files: list[dict] = []
    for state, (left, right) in mixes.items():
        target_rms, target_lufs = MIX_TARGETS[state]
        _normalise(left, right, target_rms)
        master = master_root / f"{slug}-{state}-master.wav"
        runtime = runtime_root / f"{slug}-{state}.m4a"
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
        "asset_key": f"{code}_adaptive_music_v1",
        "region_code": code,
        "region_name": region["name"],
        "authorship": "original deterministic synthesis; no external samples",
        "bpm": region["bpm"],
        "beats_per_loop": region["beats"],
        "loop_seconds": LOOP_SECONDS,
        "shared_motif": "C-G-A-E, four-note Garden Return motif",
        "notes": list(region["notes"]),
        "files": files,
    }
    master_root.mkdir(parents=True, exist_ok=True)
    (master_root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest


def build(master_root: Path, runtime_root: Path) -> dict:
    """이끼 기억서고만 만든다. 기존 호출부와 산출 경로를 그대로 유지한다."""

    _validate_regions()
    return build_region("moss_archive", master_root, runtime_root)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--region",
        choices=(*REGIONS, "all"),
        default="moss_archive",
    )
    parser.add_argument(
        "--master-root",
        type=Path,
        default=None,
        help="지정하지 않으면 design-system/audio/adventure-{slug}-v1을 쓴다",
    )
    parser.add_argument(
        "--runtime-root",
        type=Path,
        default=Path("app/assets/adventure/music"),
    )
    args = parser.parse_args()
    _validate_regions()
    codes = list(REGIONS) if args.region == "all" else [args.region]
    manifests = []
    for code in codes:
        master_root = args.master_root or Path(
            f"design-system/audio/adventure-{REGIONS[code]['slug']}-v1"
        )
        manifests.append(build_region(code, master_root, args.runtime_root))
    print(json.dumps(manifests, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
