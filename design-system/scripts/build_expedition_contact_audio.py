"""접촉 재질·적 예고·풀려남 오디오를 결정론적으로 합성한다.

`design-system/ADVENTURE_AUDIO.md`의 세 항목을 코드로 옮긴다.

* 접촉 재질 6종 — `contact-{leaf|paper|water|wood|stone|guard}.wav`
* 적 의도 preview 5종 — `telegraph-{재질}.wav`, 120ms 이하
* 지역 풀려남 cadence 4종 — `release-{region}.wav`, 스테레오

재질을 귀로 구분하게 만드는 것이 목적이므로 공용 파동의 pitch 변형을 쓰지 않고
재질마다 **모달 합성**(감쇠하는 사인 모드의 합)과 **여기 신호**(짧은 노이즈 충격)를
따로 설계한다. 모드 주파수·감쇠 시간이 재질의 정체성이고, 노이즈 대역과 길이가
"무엇이 부딪혔는가"를 만든다. 물은 기포 공명 모형(시간에 따라 음이 올라가는 감쇠
사인)을 쓴다.

외부 샘플과 생성형 오디오 원본을 쓰지 않으므로 라이선스 추적이 필요 없고, 같은
시드에서 언제나 같은 PCM이 나온다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
import wave
from collections.abc import Sequence
from pathlib import Path

SAMPLE_RATE = 44_100

# 풀려남 cadence는 `정원으로 돌아가는 동기`(C-G-A-E)의 마지막 두 음을 지역 음색으로
# 다시 들려준다. 새 팡파르를 만들지 않고 "제자리로 돌아갔다"만 전한다.
GARDEN_RETURN_TAIL = ("A", "E")


def _fade(
    samples: list[float], attack_ms: float = 2.0, release_ms: float = 6.0
) -> None:
    """시작과 끝을 0으로 눌러 재생 경계의 click을 없앤다."""

    attack = max(1, round(SAMPLE_RATE * attack_ms / 1000))
    release = max(1, round(SAMPLE_RATE * release_ms / 1000))
    total = len(samples)
    for index in range(min(attack, total)):
        samples[index] *= math.sin(index / attack * math.pi / 2)
    for index in range(min(release, total)):
        samples[total - 1 - index] *= math.sin(index / release * math.pi / 2)


def _blank(duration: float) -> list[float]:
    return [0.0] * round(SAMPLE_RATE * duration)


def _add_mode(
    buffer: list[float],
    *,
    frequency: float,
    decay_ms: float,
    gain: float,
    start: float = 0.0,
    phase: float = 0.0,
    bend: float = 0.0,
) -> None:
    """감쇠하는 사인 모드 하나를 더한다.

    `bend`는 감쇠하는 동안 주파수가 몇 배로 올라가는지다. 기포 공명(물방울)은
    수축하면서 음이 올라가므로 이 값이 0보다 크다. 고체 충돌은 0이다.
    """

    first = round(start * SAMPLE_RATE)
    tau = decay_ms / 1000
    length = min(round(SAMPLE_RATE * tau * 6), len(buffer) - first)
    angle = phase
    for offset in range(max(0, length)):
        seconds = offset / SAMPLE_RATE
        current = frequency * (1 + bend * seconds / tau)
        angle += math.tau * current / SAMPLE_RATE
        buffer[first + offset] += math.sin(angle) * math.exp(-seconds / tau) * gain


def _add_noise(
    buffer: list[float],
    *,
    duration_ms: float,
    low_hz: float,
    high_hz: float,
    gain: float,
    seed: int,
    start: float = 0.0,
    curve: float = 3.0,
) -> None:
    """대역 제한 노이즈 충격을 더한다 — 재질이 부딪히는 순간의 마찰음이다.

    저역 통과를 2단(12dB/oct)으로 걸어 상단을 확실히 눌러야 종이·잎이 쉿 소리
    나는 화이트 노이즈로 들리지 않는다. 여기서 만드는 것은 사실적인 필터가
    아니라 재질별 밝기 차이다.
    """

    rng = random.Random(seed)
    first = round(start * SAMPLE_RATE)
    length = min(round(SAMPLE_RATE * duration_ms / 1000), len(buffer) - first)
    low_coefficient = math.exp(-math.tau * high_hz / SAMPLE_RATE)
    high_coefficient = math.exp(-math.tau * low_hz / SAMPLE_RATE)
    lowpass_a = 0.0
    lowpass_b = 0.0
    highpass = 0.0
    for offset in range(max(0, length)):
        raw = rng.uniform(-1, 1)
        lowpass_a = lowpass_a * low_coefficient + raw * (1 - low_coefficient)
        lowpass_b = lowpass_b * low_coefficient + lowpass_a * (1 - low_coefficient)
        highpass = highpass * high_coefficient + lowpass_b * (1 - high_coefficient)
        band = lowpass_b - highpass
        progress = offset / max(1, length - 1)
        buffer[first + offset] += band * ((1 - progress) ** curve) * gain


def _window_rms(samples: Sequence[float], window_ms: float = 50.0) -> float:
    """가장 큰 50ms 구간의 RMS — 짧은 one-shot의 체감 음량 대용값이다.

    EBU R128의 momentary 창이 400ms라 0.1~0.3초짜리 접촉음에는 integrated
    LUFS를 쓸 수 없다. 대신 짧은 창의 최대 RMS로 재질끼리 음량을 맞추고,
    true peak 한도는 별도로 지킨다.
    """

    window = max(1, round(SAMPLE_RATE * window_ms / 1000))
    if len(samples) <= window:
        energy = sum(value * value for value in samples)
        return math.sqrt(energy / max(1, len(samples)))
    energy = sum(samples[index] * samples[index] for index in range(window))
    best = energy
    for index in range(window, len(samples)):
        energy += samples[index] * samples[index]
        energy -= samples[index - window] * samples[index - window]
        best = max(best, energy)
    return math.sqrt(best / window)


def _normalise(
    samples: list[float],
    *,
    loudness: float,
    peak_ceiling: float = 0.63,
) -> list[float]:
    """체감 음량을 맞추고 true peak 여유를 남긴다.

    peak로만 맞추면 노이즈가 많은 종이가 모드가 또렷한 나무보다 훨씬 작게
    들린다. 50ms 창 RMS를 먼저 맞춘 뒤 peak 한도로 눌러 두 조건을 함께 지킨다.
    """

    top = max((abs(value) for value in samples), default=0.0)
    if top <= 0:
        return samples
    scale = loudness / max(_window_rms(samples), 1e-9)
    if top * scale > peak_ceiling:
        scale = peak_ceiling / top
    return [value * scale for value in samples]


def _write_mono(path: Path, samples: Sequence[float]) -> None:
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


def _write_stereo(path: Path, left: Sequence[float], right: Sequence[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for left_value, right_value in zip(left, right):
        for value in (left_value, right_value):
            frames.extend(struct.pack("<h", round(max(-1.0, min(1.0, value)) * 32767)))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


# ── 접촉 재질 6종 ────────────────────────────────────────────────────────────
#
# 모드 주파수는 실제 물체의 공명을 흉내 낸 값이다. 딱딱할수록 높은 모드가 많고,
# 무를수록 감쇠가 빠르며 음정이 흐릿하다. 같은 파일의 pitch만 바꾼 변형이 되지
# 않도록 재질마다 모드 개수·감쇠 시간·노이즈 대역을 모두 다르게 잡았다.


def _contact_paper() -> list[float]:
    """마른 종이 낱장 — 음정이 거의 없고 밝은 미세 transient가 여러 번 난다."""

    buffer = _blank(0.11)
    for index, (offset, gain, seed) in enumerate(
        ((0.0, 1.0, 601), (0.012, 0.62, 607), (0.027, 0.38, 613), (0.046, 0.2, 617))
    ):
        _add_noise(
            buffer,
            duration_ms=34 - index * 5,
            low_hz=1900,
            high_hz=7000,
            gain=0.55 * gain,
            seed=seed,
            start=offset,
            curve=4.2,
        )
    _add_mode(buffer, frequency=1620, decay_ms=13, gain=0.10)
    _add_mode(buffer, frequency=3140, decay_ms=9, gain=0.07)
    return buffer


def _contact_leaf() -> list[float]:
    """마른 잎·압화 스침 — 종이보다 어둡고 길며 끝이 부드럽게 사라진다."""

    buffer = _blank(0.155)
    _add_noise(
        buffer,
        duration_ms=118,
        low_hz=850,
        high_hz=3300,
        gain=0.52,
        seed=631,
        curve=2.2,
    )
    _add_noise(
        buffer,
        duration_ms=46,
        low_hz=2100,
        high_hz=5000,
        gain=0.22,
        seed=641,
        start=0.021,
        curve=3.4,
    )
    _add_mode(buffer, frequency=880, decay_ms=27, gain=0.13)
    _add_mode(buffer, frequency=1490, decay_ms=19, gain=0.09)
    return buffer


def _contact_wood() -> list[float]:
    """나무 선반 노크 — 낮은 비조화 모드 네 개가 또렷하게 남는다."""

    buffer = _blank(0.30)
    for frequency, decay_ms, gain in (
        (218.0, 195, 0.52),
        (391.0, 138, 0.34),
        (712.0, 92, 0.20),
        (1183.0, 58, 0.11),
    ):
        _add_mode(buffer, frequency=frequency, decay_ms=decay_ms, gain=gain)
    _add_noise(
        buffer,
        duration_ms=17,
        low_hz=700,
        high_hz=4200,
        gain=0.34,
        seed=653,
        curve=5.0,
    )
    return buffer


def _contact_stone() -> list[float]:
    """단단한 돌·유리 — 높은 모드가 빽빽하고 아주 빠르게 사라진다."""

    buffer = _blank(0.20)
    for frequency, decay_ms, gain in (
        (642.0, 96, 0.30),
        (1487.0, 68, 0.26),
        (2613.0, 44, 0.18),
        (3971.0, 28, 0.12),
    ):
        _add_mode(buffer, frequency=frequency, decay_ms=decay_ms, gain=gain)
    _add_noise(
        buffer,
        duration_ms=9,
        low_hz=1800,
        high_hz=11000,
        gain=0.44,
        seed=659,
        curve=6.0,
    )
    return buffer


def _contact_water() -> list[float]:
    """물방울·물보라 — 기포 공명 모형.

    기포는 수축하면서 공명 주파수가 올라간다. `bend`로 감쇠 구간 동안 음이
    올라가게 만들면 합성음만으로도 물이라고 들린다.
    """

    buffer = _blank(0.22)
    _add_noise(
        buffer,
        duration_ms=58,
        low_hz=1400,
        high_hz=6200,
        gain=0.30,
        seed=673,
        curve=3.6,
    )
    _add_mode(buffer, frequency=770, decay_ms=46, gain=0.42, bend=0.62)
    _add_mode(buffer, frequency=1245, decay_ms=31, gain=0.26, start=0.028, bend=0.74)
    _add_mode(buffer, frequency=1960, decay_ms=19, gain=0.13, start=0.055, bend=0.85)
    return buffer


def _contact_guard() -> list[float]:
    """마음 지키기 — 펠트와 천이 받아 낸 둔한 소리.

    나무 노크와 헷갈리면 "막았다"가 "때렸다"로 읽힌다. 나무보다 더 낮고 더
    빨리 멎게 만들어 울림이 아니라 흡수로 들리게 한다.
    """

    buffer = _blank(0.20)
    _add_mode(buffer, frequency=101.0, decay_ms=104, gain=0.52)
    _add_mode(buffer, frequency=176.0, decay_ms=62, gain=0.24)
    _add_noise(
        buffer,
        duration_ms=26,
        low_hz=140,
        high_hz=760,
        gain=0.30,
        seed=683,
        curve=3.4,
    )
    return buffer


CONTACT_BUILDERS = {
    "leaf": _contact_leaf,
    "paper": _contact_paper,
    "water": _contact_water,
    "wood": _contact_wood,
    "stone": _contact_stone,
    "guard": _contact_guard,
}


# ── 적 의도 preview 5종 ──────────────────────────────────────────────────────
#
# 예고는 "무엇이 오는가"만 알리는 신호라 접촉음보다 훨씬 짧고 조용하다. 접촉음과
# 같은 재질 어휘를 쓰되 두 개의 작은 transient로 끊어 "준비 중"으로 읽히게 한다.
TELEGRAPH_SPECS = {
    "paper": {"frequency": 2050.0, "low": 1900, "high": 7200, "seed": 701},
    "leaf": {"frequency": 1180.0, "low": 900, "high": 3600, "seed": 709},
    "water": {"frequency": 880.0, "low": 1200, "high": 4800, "seed": 719, "bend": 0.55},
    "wood": {"frequency": 430.0, "low": 600, "high": 3000, "seed": 727},
    "stone": {"frequency": 1490.0, "low": 1500, "high": 7600, "seed": 733},
}


def _telegraph(material: str) -> list[float]:
    spec = TELEGRAPH_SPECS[material]
    buffer = _blank(0.115)
    for index, start in enumerate((0.0, 0.052)):
        _add_mode(
            buffer,
            frequency=float(spec["frequency"]) * (1.0 if index == 0 else 1.12),
            decay_ms=13,
            gain=0.30 if index == 0 else 0.24,
            start=start,
            bend=float(spec.get("bend", 0.0)),
        )
        _add_noise(
            buffer,
            duration_ms=14,
            low_hz=float(spec["low"]),
            high_hz=float(spec["high"]),
            gain=0.18 if index == 0 else 0.14,
            seed=int(spec["seed"]) + index,
            start=start,
            curve=4.5,
        )
    return buffer


# ── 지역 풀려남 cadence 4종 ─────────────────────────────────────────────────
#
# `A → E` 두 음은 지역 BGM이 공유하는 정원 복귀 동기의 꼬리다. 음색과 옥타브만
# 지역을 따르고 음정 관계는 네 지역이 같아 "풀렸다"가 언제나 같은 뜻으로 들린다.
NOTE_HZ = {"A3": 220.00, "E4": 329.63, "A4": 440.00, "E5": 659.25}

RELEASE_SPECS = {
    # 이끼 낀 기억서고 — 낮은 마림바. 나무 배음이 짧게 남는다.
    "moss_archive": {
        "notes": ("A3", "E4"),
        "gap": 0.30,
        "decay_ms": 380,
        "harmonics": ((1.0, 1.0), (4.0, 0.24), (9.6, 0.08)),
        "noise": {"duration_ms": 12, "low": 500, "high": 3200, "gain": 0.10},
        "duration": 1.05,
    },
    # 메아리 우물정원 — 나무 플루트. 숨이 먼저 들리고 배음이 거의 없다.
    "echo_well": {
        "notes": ("A4", "E4"),
        "gap": 0.32,
        "decay_ms": 300,
        "harmonics": ((1.0, 1.0), (2.0, 0.16), (3.0, 0.05)),
        "noise": {"duration_ms": 46, "low": 1600, "high": 5200, "gain": 0.07},
        "attack_ms": 34,
        "duration": 1.10,
    },
    # 별빛 씨앗 보관고 — 펠트 피아노 위에 셀레스타 한 음.
    "starlight_seed_vault": {
        "notes": ("A4", "E5"),
        "gap": 0.28,
        "decay_ms": 340,
        "harmonics": ((1.0, 1.0), (2.0, 0.20), (3.0, 0.07), (6.0, 0.05)),
        "noise": {"duration_ms": 9, "low": 900, "high": 4200, "gain": 0.06},
        "duration": 1.05,
    },
    # 마음나무 관측실 — 낮은 펠트 피아노. 가장 느리고 조용하게 정리된다.
    "heartwood_observatory": {
        "notes": ("A3", "E4"),
        "gap": 0.38,
        "decay_ms": 460,
        "harmonics": ((1.0, 1.0), (2.0, 0.13), (3.0, 0.04)),
        "noise": {"duration_ms": 14, "low": 300, "high": 2000, "gain": 0.05},
        "duration": 1.25,
    },
}


def _release(region: str) -> tuple[list[float], list[float]]:
    spec = RELEASE_SPECS[region]
    duration = float(spec["duration"])
    left = _blank(duration)
    right = _blank(duration)
    attack_ms = float(spec.get("attack_ms", 6.0))
    for index, note in enumerate(spec["notes"]):
        start = index * float(spec["gap"])
        # 두 음을 살짝 다른 좌우 위치에 두면 마지막 화음이 넓게 정리된다.
        pan = -0.18 if index == 0 else 0.18
        left_gain = math.cos((pan + 1) * math.pi / 4)
        right_gain = math.sin((pan + 1) * math.pi / 4)
        voice = _blank(duration)
        for multiplier, gain in spec["harmonics"]:
            _add_mode(
                voice,
                frequency=NOTE_HZ[note] * multiplier,
                decay_ms=float(spec["decay_ms"]) / (1 + 0.35 * (multiplier - 1)),
                gain=0.42 * gain * (0.92 if index else 1.0),
                start=start,
            )
        noise = spec["noise"]
        _add_noise(
            voice,
            duration_ms=float(noise["duration_ms"]),
            low_hz=float(noise["low"]),
            high_hz=float(noise["high"]),
            gain=float(noise["gain"]),
            seed=811 + index * 7 + len(region),
            start=start,
            curve=3.0,
        )
        # 플루트처럼 천천히 열리는 음색은 앞머리를 눌러 숨결부터 들리게 한다.
        onset = round(SAMPLE_RATE * start)
        ramp = max(1, round(SAMPLE_RATE * attack_ms / 1000))
        for offset in range(min(ramp, len(voice) - onset)):
            voice[onset + offset] *= math.sin(offset / ramp * math.pi / 2)
        for position, value in enumerate(voice):
            left[position] += value * left_gain
            right[position] += value * right_gain
    return left, right


# ── 모험 UI cue 4종 ─────────────────────────────────────────────────────────
#
# `ADVENTURE_AUDIO.md`의 `효과음과 촉각`이 네 순간의 재료와 길이 상한을 이미
# 문장으로 정해 뒀다. 그 문장을 그대로 모드와 노이즈로 옮긴다. 실패·잠금에는
# 소리를 만들지 않는다 — 문구와 비활성 상태만 쓰라고 정해져 있다.


def _cue_patrol_depart() -> list[float]:
    """순찰 출발 — 종이 지도 펼침과 가벼운 나무 발판. 300ms 안."""

    buffer = _blank(0.29)
    # 지도가 펼쳐지는 동안은 transient가 아니라 이어지는 결이라 곡선을 눕힌다.
    _add_noise(
        buffer,
        duration_ms=150,
        low_hz=1600,
        high_hz=5200,
        gain=0.40,
        seed=901,
        curve=1.5,
    )
    for frequency, decay_ms, gain in ((188.0, 96, 0.34), (337.0, 62, 0.18)):
        _add_mode(
            buffer,
            frequency=frequency,
            decay_ms=decay_ms,
            gain=gain,
            start=0.108,
        )
    _add_noise(
        buffer,
        duration_ms=18,
        low_hz=600,
        high_hz=2800,
        gain=0.20,
        seed=907,
        start=0.108,
        curve=4.5,
    )
    return buffer


def _cue_patrol_return() -> list[float]:
    """귀환·새 장소 발견 — 작은 나무 걸쇠와 씨앗 두 알. 450ms 안."""

    buffer = _blank(0.44)
    for frequency, decay_ms, gain in (
        (262.0, 118, 0.38),
        (473.0, 82, 0.22),
        (818.0, 48, 0.12),
    ):
        _add_mode(buffer, frequency=frequency, decay_ms=decay_ms, gain=gain)
    _add_noise(
        buffer,
        duration_ms=16,
        low_hz=700,
        high_hz=3600,
        gain=0.26,
        seed=911,
        curve=5.0,
    )
    # 씨앗 두 알 — 짧고 마른 두 번의 닿음. 셋 이상으로 늘리지 않는다.
    for index, start in enumerate((0.168, 0.246)):
        _add_mode(
            buffer,
            frequency=1580.0 if index == 0 else 1940.0,
            decay_ms=26,
            gain=0.15 if index == 0 else 0.12,
            start=start,
        )
        _add_noise(
            buffer,
            duration_ms=12,
            low_hz=1400,
            high_hz=5200,
            gain=0.10,
            seed=917 + index,
            start=start,
            curve=5.0,
        )
    return buffer


def _cue_dungeon_clear() -> list[float]:
    """던전 완료 — 무광 도자기 차임. 400ms 안.

    `무광`이라 유리처럼 번쩍이는 고역 transient를 넣지 않는다. 도자기의
    약간 어긋난 배음만 남기고 어택을 부드럽게 눌러 둔다.
    """

    buffer = _blank(0.39)
    for frequency, decay_ms, gain in (
        (868.0, 250, 0.34),
        (1302.0, 172, 0.20),
        (2098.0, 104, 0.10),
    ):
        _add_mode(buffer, frequency=frequency, decay_ms=decay_ms, gain=gain)
    _add_noise(
        buffer,
        duration_ms=14,
        low_hz=900,
        high_hz=3200,
        gain=0.12,
        seed=929,
        curve=4.0,
    )
    return buffer


def _cue_research_complete() -> list[float]:
    """표본 연구 완료 — 나무 서랍 닫힘과 얇은 유리 차임. 350ms 안."""

    buffer = _blank(0.34)
    for frequency, decay_ms, gain in ((148.0, 104, 0.40), (259.0, 68, 0.20)):
        _add_mode(buffer, frequency=frequency, decay_ms=decay_ms, gain=gain)
    # 서랍이 미끄러져 닫히는 마찰 — 짧은 transient가 아니라 눌린 결이다.
    _add_noise(
        buffer,
        duration_ms=62,
        low_hz=260,
        high_hz=1500,
        gain=0.26,
        seed=937,
        curve=2.4,
    )
    # 얇은 유리 — 한 번만, 아주 여리게.
    _add_mode(buffer, frequency=2612.0, decay_ms=118, gain=0.11, start=0.148)
    return buffer


ADVENTURE_CUE_BUILDERS = {
    "patrol-depart": (_cue_patrol_depart, 300),
    "patrol-return": (_cue_patrol_return, 450),
    "dungeon-clear": (_cue_dungeon_clear, 400),
    "research-complete": (_cue_research_complete, 350),
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


# 접촉음은 여섯 재질이 같은 세기로 들려야 재질 차이만 남는다. 예고는 접촉보다
# 항상 조용해야 하므로 절반 이하의 목표를 쓴다(믹스 우선순위 1순위 대 2순위).
CONTACT_LOUDNESS = 0.150
TELEGRAPH_LOUDNESS = 0.052


def build(output_root: Path) -> dict:
    files: list[dict] = []

    for material, builder in CONTACT_BUILDERS.items():
        samples = builder()
        _fade(samples)
        samples = _normalise(samples, loudness=CONTACT_LOUDNESS)
        path = output_root / f"contact-{material}.wav"
        _write_mono(path, samples)
        files.append(
            {
                "role": "contact",
                "key": material,
                "path": path.as_posix(),
                "channels": 1,
                "duration_ms": round(len(samples) / SAMPLE_RATE * 1000),
                "window_rms": round(_window_rms(samples), 5),
                "sha256": _sha256(path),
            }
        )

    for material in TELEGRAPH_SPECS:
        samples = _telegraph(material)
        _fade(samples, attack_ms=1.5, release_ms=4.0)
        samples = _normalise(samples, loudness=TELEGRAPH_LOUDNESS, peak_ceiling=0.34)
        path = output_root / f"telegraph-{material}.wav"
        _write_mono(path, samples)
        files.append(
            {
                "role": "telegraph",
                "key": material,
                "path": path.as_posix(),
                "channels": 1,
                "duration_ms": round(len(samples) / SAMPLE_RATE * 1000),
                "window_rms": round(_window_rms(samples), 5),
                "sha256": _sha256(path),
            }
        )

    for key, (builder, limit_ms) in ADVENTURE_CUE_BUILDERS.items():
        samples = builder()
        _fade(samples, attack_ms=2.0, release_ms=10.0)
        samples = _normalise(samples, loudness=CONTACT_LOUDNESS)
        duration_ms = round(len(samples) / SAMPLE_RATE * 1000)
        if duration_ms > limit_ms:
            raise ValueError(f"{key}: {duration_ms}ms는 상한 {limit_ms}ms를 넘는다")
        path = output_root / f"cue-{key}.wav"
        _write_mono(path, samples)
        files.append(
            {
                "role": "adventure_cue",
                "key": key,
                "path": path.as_posix(),
                "channels": 1,
                "duration_ms": duration_ms,
                "limit_ms": limit_ms,
                "window_rms": round(_window_rms(samples), 5),
                "sha256": _sha256(path),
            }
        )

    for region in RELEASE_SPECS:
        left, right = _release(region)
        _fade(left, attack_ms=3.0, release_ms=40.0)
        _fade(right, attack_ms=3.0, release_ms=40.0)
        top = (
            max(
                max((abs(value) for value in left), default=0.0),
                max((abs(value) for value in right), default=0.0),
            )
            or 1.0
        )
        scale = 0.60 / top
        left = [value * scale for value in left]
        right = [value * scale for value in right]
        path = output_root / f"release-{region.replace('_', '-')}.wav"
        _write_stereo(path, left, right)
        files.append(
            {
                "role": "release",
                "key": region,
                "path": path.as_posix(),
                "channels": 2,
                "duration_ms": round(len(left) / SAMPLE_RATE * 1000),
                "notes": list(RELEASE_SPECS[region]["notes"]),
                "sha256": _sha256(path),
            }
        )

    return {
        "asset_key": "expedition_contact_audio_v1",
        "authorship": "original deterministic synthesis; no external samples",
        "method": "modal synthesis (damped sine modes) + band-limited noise excitation",
        "sample_rate": SAMPLE_RATE,
        "bit_depth": 16,
        "shared_motif_tail": list(GARDEN_RETURN_TAIL),
        "files": files,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("app/assets/adventure/sfx"),
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("design-system/audio/adventure-contact-v1/manifest.json"),
    )
    args = parser.parse_args()
    manifest = build(args.output_root)
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
