"""지역 ambience를 적용 **전에** 검사한다.

만든 사람이 스스로 `잘 됐다`고 말하는 대신, 들어야 하는 성질을 숫자로 재서
못 지키면 실패시킨다. 이 스크립트가 막는 것들:

1. **이음매** — loop가 한 바퀴 돌아 처음으로 붙을 때 튀지 않는가. 경계의 표본
   변화량을 내부 표본 변화량 분포와 비교한다. 이어 붙인 자국은 반드시 내부보다
   큰 계단으로 나타난다.
2. **도드라지는 소리** — 배경에 튀는 사건이 있으면 loop가 들킨다. 짧은 창 최대
   RMS가 중앙값 RMS보다 지나치게 크면 실패다.
3. **대역 분리** — A는 BGM 핵심(816~1704Hz 드론) 아래, B는 위에 있어야 한다.
   같은 자리에 앉으면 서로 갉아먹는다.
4. **음량** — 배경이 배경 자리에 있는가.
5. **좌우 폭** — 좌우가 같은 신호면 헤드폰에서 답답하고 공간이 안 생긴다.
6. **DC 오프셋** — 스피커를 밀어 둔 채 두는 소리는 헤드룸만 먹는다.
7. **겹친 반복 주기** — A와 B 길이가 서로 달라 실제 반복이 충분히 먼가.

사용법:
    python verify_expedition_ambience.py <검사할 폴더>
"""

from __future__ import annotations

import argparse
import cmath
import json
import math
import statistics
import subprocess
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_expedition_ambience import (  # noqa: E402
    LAYER_SECONDS,
    REGIONS,
    ROOT,
    TARGET_LUFS,
)

# BGM 핵심 대역. 지역 드론이 816~1704Hz에 있고 마림바 음이 그 아래로 깔린다.
# ambience는 이 구간을 비켜야 서로 살아난다.
BGM_CORE_LOW_HZ = 700.0
BGM_CORE_HIGH_HZ = 1900.0

# A는 핵심 아래, B는 위. 무게중심으로 판정한다.
MAX_FLOOR_CENTROID_HZ = 700.0
MIN_AIR_CENTROID_HZ = 2600.0

# 배경에 사건이 없어야 한다. 짧은 창 최대 RMS가 중앙값의 이 배를 넘으면
# `무언가 튄다`는 뜻이다.
MAX_PEAK_TO_MEDIAN = 2.4

# 이음매 판정. 경계의 계단이 내부 변화량 99.9분위의 이 배를 넘으면 실패다.
MAX_SEAM_RATIO = 3.0

LOUDNESS_RANGE_LUFS = (TARGET_LUFS - 2.5, TARGET_LUFS + 2.5)
MAX_TRUE_PEAK_DBTP = -6.0
MAX_DC_OFFSET = 0.002
# 좌우가 이보다 닮으면 사실상 모노다.
MAX_CHANNEL_CORRELATION = 0.85


def _read(path: Path) -> tuple[list[float], list[float], int]:
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        rate = source.getframerate()
        frames = source.readframes(source.getnframes())
    if channels != 2:
        raise ValueError(f"{path.name}: ambience는 스테레오여야 합니다")
    values = [
        int.from_bytes(frames[index : index + 2], "little", signed=True) / 32768.0
        for index in range(0, len(frames), 2)
    ]
    return values[0::2], values[1::2], rate


def _seam_ratio(samples: list[float]) -> float:
    """경계 계단 ÷ 내부 변화량 99.9분위.

    1에 가까우면 경계가 내부와 구분되지 않는다는 뜻이다. 이어 붙인 자국이
    있으면 이 값이 크게 튄다.
    """

    deltas = sorted(
        abs(samples[index + 1] - samples[index]) for index in range(len(samples) - 1)
    )
    if not deltas:
        return 0.0
    reference = deltas[min(len(deltas) - 1, int(len(deltas) * 0.999))]
    seam = abs(samples[0] - samples[-1])
    return seam / reference if reference > 0 else 0.0


def _window_rms(samples: list[float], rate: int, window_ms: float = 250.0) -> list[float]:
    size = max(1, round(rate * window_ms / 1000.0))
    values = []
    for offset in range(0, len(samples) - size + 1, size):
        frame = samples[offset : offset + size]
        values.append(math.sqrt(sum(value * value for value in frame) / len(frame)))
    return values


def _spectral_centroid(samples: list[float], rate: int) -> float:
    """평균 스펙트럼 무게중심(Hz).

    한 프레임만 보면 그 순간의 우연이 결과를 지배한다. Hann 창 1024점을 512씩
    겹쳐 훑고 크기 스펙트럼을 평균한 뒤 무게중심을 구한다.
    """

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
    # 전체를 다 훑으면 32초 × 48kHz라 너무 느리다. 고르게 흩은 64프레임이면
    # 정상 상태 스펙트럼을 충분히 대표한다.
    positions = max(1, len(samples) - size)
    step = max(hop, positions // 64)
    for offset in range(0, positions, step):
        frame = [samples[offset + index] * hann[index] for index in range(size)]
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


def _band_share(samples: list[float], rate: int, low: float, high: float) -> float:
    """주어진 대역이 전체 에너지에서 차지하는 몫."""

    size = 1024
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
    positions = max(1, len(samples) - size)
    step = max(size // 2, positions // 64)
    frames = 0
    for offset in range(0, positions, step):
        frame = [samples[offset + index] * hann[index] for index in range(size)]
        for bin_index in range(bins):
            row = twiddle[bin_index]
            total = sum(frame[position] * row[position] for position in range(size))
            magnitude[bin_index] += abs(total)
        frames += 1
    inside = 0.0
    total = 0.0
    for bin_index in range(bins):
        hz = bin_index * rate / size
        value = magnitude[bin_index]
        total += value
        if low <= hz <= high:
            inside += value
    return inside / total if total > 0 else 0.0


def _correlation(left: list[float], right: list[float]) -> float:
    step = max(1, len(left) // 200_000)
    a = left[::step]
    b = right[::step]
    mean_a = sum(a) / len(a)
    mean_b = sum(b) / len(b)
    num = sum((x - mean_a) * (y - mean_b) for x, y in zip(a, b))
    den_a = math.sqrt(sum((x - mean_a) ** 2 for x in a))
    den_b = math.sqrt(sum((y - mean_b) ** 2 for y in b))
    return abs(num / (den_a * den_b)) if den_a and den_b else 1.0


def _loudness(path: Path) -> tuple[float, float]:
    """ffmpeg ebur128로 integrated LUFS와 true peak를 잰다.

    ambience는 32초 이상이라 400ms momentary 창이 여러 번 들어가고, integrated
    LUFS가 유효하다. 0.1초 one-shot과 다른 점이다.
    """

    result = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-filter_complex",
            "ebur128=peak=true",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    text = result.stderr
    lufs = peak = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("I:") and "LUFS" in stripped:
            lufs = float(stripped.split()[1])
        if stripped.startswith("Peak:") and "dBFS" in stripped:
            peak = float(stripped.split()[1])
    if lufs is None or peak is None:
        raise RuntimeError(f"{path.name}: ebur128 결과를 읽지 못했습니다\n{text[-800:]}")
    return lufs, peak


def _find_runtime(folder: Path, override: Path | None) -> Path | None:
    """런타임 M4A가 있는 폴더를 찾는다.

    스크래치(`<out>/master` 옆의 `runtime`)와 실제 경로(앱 번들) 둘 다에서
    돌아야 한다. 못 찾으면 None을 돌려주고 호출부가 **실패로** 다룬다.
    """

    if override is not None:
        return override if override.exists() else None
    candidates = (
        folder.parent / "runtime",
        ROOT / "app" / "assets" / "adventure" / "ambience",
    )
    for candidate in candidates:
        if candidate.exists() and any(candidate.glob("*.m4a")):
            return candidate
    return None


def verify(folder: Path, runtime_override: Path | None = None) -> int:
    problems: list[str] = []
    runtime_dir = _find_runtime(folder, runtime_override)
    checked = 0
    centroids: dict[tuple[str, str], float] = {}

    for code, region in REGIONS.items():
        for layer in ("a", "b"):
            master = folder / f"{region['slug']}-{layer}-master.wav"
            if not master.exists():
                problems.append(f"{master.name}: 파일이 없습니다")
                continue
            checked += 1
            left, right, rate = _read(master)
            label = f"{region['name']} {layer.upper()}"

            expected = round(rate * LAYER_SECONDS[layer])
            if abs(len(left) - expected) > 1:
                problems.append(
                    f"{label}: 길이가 {len(left) / rate:.2f}초로 "
                    f"{LAYER_SECONDS[layer]}초와 다릅니다"
                )

            # 1. 이음매
            for channel, samples in (("L", left), ("R", right)):
                ratio = _seam_ratio(samples)
                if ratio > MAX_SEAM_RATIO:
                    problems.append(
                        f"{label} {channel}: loop 경계가 튑니다 "
                        f"(내부 변화량의 {ratio:.1f}배)"
                    )

            # 2. 도드라지는 소리
            for channel, samples in (("L", left), ("R", right)):
                windows = _window_rms(samples, rate)
                median = statistics.median(windows)
                if median <= 0:
                    problems.append(f"{label} {channel}: 무음입니다")
                    continue
                ratio = max(windows) / median
                if ratio > MAX_PEAK_TO_MEDIAN:
                    problems.append(
                        f"{label} {channel}: 배경에 튀는 사건이 있습니다 "
                        f"(최대/중앙 {ratio:.2f}배). loop가 들립니다"
                    )

            # 3. 대역 분리
            mono = [(l + r) * 0.5 for l, r in zip(left, right)]
            centroid = _spectral_centroid(mono, rate)
            centroids[(code, layer)] = centroid
            if layer == "a" and centroid > MAX_FLOOR_CENTROID_HZ:
                problems.append(
                    f"{label}: 바닥층 무게중심이 {centroid:.0f}Hz로 너무 높습니다 "
                    f"(BGM 드론과 겹칩니다)"
                )
            if layer == "b" and centroid < MIN_AIR_CENTROID_HZ:
                problems.append(
                    f"{label}: 공기층 무게중심이 {centroid:.0f}Hz로 너무 낮습니다 "
                    f"(BGM 드론과 겹칩니다)"
                )
            core = _band_share(mono, rate, BGM_CORE_LOW_HZ, BGM_CORE_HIGH_HZ)
            if core > 0.22:
                problems.append(
                    f"{label}: BGM 핵심 대역에 에너지의 {core:.0%}가 있습니다"
                )

            # 5. 좌우 폭
            correlation = _correlation(left, right)
            if correlation > MAX_CHANNEL_CORRELATION:
                problems.append(
                    f"{label}: 좌우가 너무 닮았습니다(상관 {correlation:.2f}). "
                    f"사실상 모노입니다"
                )

            # 6. DC 오프셋
            for channel, samples in (("L", left), ("R", right)):
                offset = abs(sum(samples) / len(samples))
                if offset > MAX_DC_OFFSET:
                    problems.append(f"{label} {channel}: DC 오프셋 {offset:.4f}")

    # 4. 음량 — 런타임 M4A를 잰다. 실제로 재생되는 것이 그것이다.
    #
    # 런타임 폴더를 못 찾으면 **조용히 넘어가지 않고 실패한다.** 건너뛴 검사는
    # 검사가 아니고, 통과 메시지가 거짓말이 된다.
    if runtime_dir is None:
        problems.append(
            "런타임 폴더를 찾지 못해 음량을 재지 못했습니다. --runtime으로 지정하세요"
        )
    else:
        for code, region in REGIONS.items():
            for layer in ("a", "b"):
                runtime = runtime_dir / f"{region['slug']}-{layer}.m4a"
                if not runtime.exists():
                    problems.append(f"{runtime.name}: 런타임 파일이 없습니다")
                    continue
                lufs, peak = _loudness(runtime)
                label = f"{region['name']} {layer.upper()}"
                low, high = LOUDNESS_RANGE_LUFS
                if not low <= lufs <= high:
                    problems.append(
                        f"{label}: {lufs:.1f} LUFS가 목표 {TARGET_LUFS}±2.5 밖입니다"
                    )
                if peak > MAX_TRUE_PEAK_DBTP:
                    problems.append(
                        f"{label}: true peak {peak:.1f} dBTP가 "
                        f"{MAX_TRUE_PEAK_DBTP} 상한을 넘습니다"
                    )

    # 7. 겹친 반복 주기
    combined = math.lcm(round(LAYER_SECONDS["a"]), round(LAYER_SECONDS["b"]))
    if combined < 120:
        problems.append(f"겹친 반복 주기가 {combined}초로 너무 짧습니다")

    # 지역끼리 구분되는가 — 넷이 다 같은 소리면 지역을 나눈 뜻이 없다.
    floors = [centroids[(code, "a")] for code in REGIONS if (code, "a") in centroids]
    if len(floors) >= 2 and max(floors) - min(floors) < 12:
        problems.append("네 지역 바닥층이 사실상 같은 소리입니다")

    print(
        f"검사한 파일 {checked}개, 겹친 반복 주기 {combined}초, "
        f"런타임 {runtime_dir if runtime_dir else '못 찾음'}"
    )
    for (code, layer), centroid in sorted(centroids.items()):
        print(f"  {REGIONS[code]['name']} {layer.upper()}: 무게중심 {centroid:.0f}Hz")
    if problems:
        print("\n실패:")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("\n모두 통과했습니다.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="마스터 WAV가 있는 폴더")
    parser.add_argument(
        "--runtime", type=Path, default=None, help="런타임 M4A 폴더(자동 탐색 대체)"
    )
    args = parser.parse_args()
    return verify(args.folder, args.runtime)


if __name__ == "__main__":
    sys.exit(main())
