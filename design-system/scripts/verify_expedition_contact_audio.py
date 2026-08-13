"""생성한 접촉·예고·풀려남 오디오가 오디오 기준을 지키는지 검사한다.

`ADVENTURE_AUDIO.md`의 세 계약을 자동으로 확인한다.

1. true peak −2dBTP 이하, DC offset 없음, 끝의 불필요한 무음 없음.
2. 여섯 접촉 재질이 서로 **다른 소리**다. 같은 파동의 pitch 변형이면
   스펙트럼 무게중심과 감쇠 시간이 함께 붙어 버리므로 두 축을 모두 본다.
3. 예고는 접촉보다 조용하고 120ms 이하다.

ffmpeg가 있으면 true peak을 ffmpeg로 재고, 없으면 4배 오버샘플 추정으로
대체한다. 실패한 항목을 모아 0이 아닌 종료 코드로 알린다.
"""

from __future__ import annotations

import argparse
import cmath
import json
import math
import shutil
import subprocess
import wave
from pathlib import Path

TRUE_PEAK_CEILING_DBTP = -2.0
TELEGRAPH_MAX_MS = 120.0
CONTACT_MATERIALS = ("leaf", "paper", "water", "wood", "stone", "guard")


def _read(path: Path) -> tuple[list[float], int, int]:
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        rate = source.getframerate()
        width = source.getsampwidth()
        raw = source.readframes(source.getnframes())
    if width != 2:
        raise ValueError(f"{path}: 16bit PCM만 검사합니다")
    values = [
        int.from_bytes(raw[index : index + 2], "little", signed=True) / 32768
        for index in range(0, len(raw), 2)
    ]
    if channels == 1:
        return values, rate, channels
    mono = [
        (values[index] + values[index + 1]) / 2 for index in range(0, len(values), 2)
    ]
    return mono, rate, channels


def _true_peak_dbtp(path: Path) -> float:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is not None:
        result = subprocess.run(
            [
                ffmpeg,
                "-hide_banner",
                "-nostats",
                "-i",
                str(path),
                "-af",
                "ebur128=peak=true",
                "-f",
                "null",
                "-",
            ],
            capture_output=True,
            check=False,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        lines = (result.stderr or "").splitlines()
        for index, line in enumerate(lines):
            if "True peak" in line:
                for follow in lines[index : index + 4]:
                    if "Peak:" in follow:
                        return float(follow.split("Peak:")[1].split()[0])
    samples, _, _ = _read(path)
    # ffmpeg가 없을 때만 쓰는 보수적 대체값 — 샘플 peak에 인터샘플 여유 1dB.
    peak = max((abs(value) for value in samples), default=0.0)
    return 20 * math.log10(max(peak, 1e-9)) + 1.0


def _spectral_centroid(samples: list[float], rate: int) -> float:
    """소리 전체의 평균 스펙트럼 무게중심(Hz) — 재질의 밝기다.

    한 프레임만 보면 첫 노이즈 충격이 결과를 지배해 무른 재질과 단단한 재질이
    같아 보인다. Hann 창 1024점을 512씩 겹쳐 전체를 훑고 크기 스펙트럼을
    평균한 뒤 무게중심을 구한다.
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
    for offset in range(0, max(1, len(samples) - size + 1), hop):
        frame = samples[offset : offset + size]
        if len(frame) < size:
            frame = frame + [0.0] * (size - len(frame))
        if max(abs(value) for value in frame) < 1e-4:
            continue
        windowed = [value * hann[index] for index, value in enumerate(frame)]
        for bin_index in range(bins):
            row = twiddle[bin_index]
            total = 0j
            for position in range(size):
                value = windowed[position]
                if value:
                    total += value * row[position]
            magnitude[bin_index] += abs(total)
        frames += 1
    if not frames:
        return 0.0
    weighted = sum(
        value * (index * rate / size) for index, value in enumerate(magnitude)
    )
    total_energy = sum(magnitude)
    return weighted / total_energy if total_energy else 0.0


def _decay_ms(samples: list[float], rate: int) -> float:
    """최대 진폭의 10%까지 떨어지는 데 걸리는 시간 — 재질의 단단함이다."""

    peak = max((abs(value) for value in samples), default=0.0)
    if peak <= 0:
        return 0.0
    peak_index = max(range(len(samples)), key=lambda index: abs(samples[index]))
    threshold = peak * 0.1
    for index in range(peak_index, len(samples)):
        if all(
            abs(value) < threshold
            for value in samples[index : index + max(1, rate // 200)]
        ):
            return (index - peak_index) / rate * 1000
    return (len(samples) - peak_index) / rate * 1000


def _dc_offset(samples: list[float]) -> float:
    return sum(samples) / max(1, len(samples))


def _trailing_silence_ms(samples: list[float], rate: int) -> float:
    for index in range(len(samples) - 1, -1, -1):
        if abs(samples[index]) > 0.0005:
            return (len(samples) - 1 - index) / rate * 1000
    return len(samples) / rate * 1000


def verify(root: Path) -> list[str]:
    problems: list[str] = []
    profiles: dict[str, dict[str, float]] = {}

    for material in CONTACT_MATERIALS:
        path = root / f"contact-{material}.wav"
        if not path.exists():
            problems.append(f"{path.name}: 파일이 없습니다")
            continue
        samples, rate, channels = _read(path)
        peak = _true_peak_dbtp(path)
        if peak > TRUE_PEAK_CEILING_DBTP:
            problems.append(
                f"{path.name}: true peak {peak:.1f}dBTP > {TRUE_PEAK_CEILING_DBTP}"
            )
        if channels != 1:
            problems.append(f"{path.name}: 접촉음은 모노여야 합니다")
        if abs(_dc_offset(samples)) > 0.002:
            problems.append(f"{path.name}: DC offset {_dc_offset(samples):.4f}")
        trailing = _trailing_silence_ms(samples, rate)
        if trailing > 40:
            problems.append(f"{path.name}: 끝에 {trailing:.0f}ms 무음이 남았습니다")
        profiles[material] = {
            "centroid": _spectral_centroid(samples, rate),
            "decay_ms": _decay_ms(samples, rate),
            "duration_ms": len(samples) / rate * 1000,
        }

    # 재질이 실제로 구분되는지 — 밝기와 감쇠가 동시에 붙은 쌍이 있으면 실패다.
    materials = sorted(profiles)
    for first_index, first in enumerate(materials):
        for second in materials[first_index + 1 :]:
            left, right = profiles[first], profiles[second]
            centroid_ratio = max(left["centroid"], right["centroid"]) / max(
                min(left["centroid"], right["centroid"]), 1e-6
            )
            decay_ratio = max(left["decay_ms"], right["decay_ms"]) / max(
                min(left["decay_ms"], right["decay_ms"]), 1e-6
            )
            if centroid_ratio < 1.25 and decay_ratio < 1.35:
                problems.append(
                    f"contact-{first} / contact-{second}: 밝기 {centroid_ratio:.2f}배, "
                    f"감쇠 {decay_ratio:.2f}배 — 두 재질을 귀로 구분하기 어렵습니다"
                )

    for material in ("leaf", "paper", "water", "wood", "stone"):
        path = root / f"telegraph-{material}.wav"
        if not path.exists():
            problems.append(f"{path.name}: 파일이 없습니다")
            continue
        samples, rate, _ = _read(path)
        duration = len(samples) / rate * 1000
        if duration > TELEGRAPH_MAX_MS:
            problems.append(f"{path.name}: {duration:.0f}ms > {TELEGRAPH_MAX_MS}ms")
        peak = _true_peak_dbtp(path)
        if peak > TRUE_PEAK_CEILING_DBTP:
            problems.append(f"{path.name}: true peak {peak:.1f}dBTP")
        contact_peak = max(
            (abs(value) for value in _read(root / f"contact-{material}.wav")[0]),
            default=1.0,
        )
        telegraph_peak = max((abs(value) for value in samples), default=0.0)
        if telegraph_peak > contact_peak * 0.65:
            problems.append(
                f"{path.name}: 예고가 접촉음({contact_peak:.2f})만큼 큽니다 "
                f"({telegraph_peak:.2f}) — 믹스 우선순위 위반"
            )

    # 모험 UI cue — 문서가 순간마다 길이 상한을 정해 뒀다.
    for key, limit_ms in (
        ("patrol-depart", 300),
        ("patrol-return", 450),
        ("dungeon-clear", 400),
        ("research-complete", 350),
    ):
        path = root / f"cue-{key}.wav"
        if not path.exists():
            problems.append(f"{path.name}: 파일이 없습니다")
            continue
        samples, rate, channels = _read(path)
        duration = len(samples) / rate * 1000
        if duration > limit_ms:
            problems.append(f"{path.name}: {duration:.0f}ms > 상한 {limit_ms}ms")
        if channels != 1:
            problems.append(f"{path.name}: UI cue는 모노여야 합니다")
        peak = _true_peak_dbtp(path)
        if peak > TRUE_PEAK_CEILING_DBTP:
            problems.append(f"{path.name}: true peak {peak:.1f}dBTP")

    for region in (
        "moss-archive",
        "echo-well",
        "starlight-seed-vault",
        "heartwood-observatory",
    ):
        path = root / f"release-{region}.wav"
        if not path.exists():
            problems.append(f"{path.name}: 파일이 없습니다")
            continue
        with wave.open(str(path), "rb") as source:
            if source.getnchannels() != 2:
                problems.append(f"{path.name}: 풀려남 cadence는 스테레오여야 합니다")
        peak = _true_peak_dbtp(path)
        if peak > TRUE_PEAK_CEILING_DBTP:
            problems.append(f"{path.name}: true peak {peak:.1f}dBTP")

    return problems


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("app/assets/adventure/sfx"))
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()
    problems = verify(args.root)
    report = {"root": args.root.as_posix(), "problems": problems, "ok": not problems}
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    print(text)
    raise SystemExit(1 if problems else 0)


if __name__ == "__main__":
    main()
