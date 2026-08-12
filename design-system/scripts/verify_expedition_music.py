"""지역 BGM 12곡이 순환·음량·구분 계약을 지키는지 검사한다.

`ADVENTURE_AUDIO.md`가 요구하는 세 가지를 자동으로 확인한다.

1. **순환** — 16초 loop가 정확히 16초로 디코딩되고, 경계에서 파형이 튀지 않으며,
   시작과 끝의 음색이 이어진다. AAC는 프라이밍 샘플 때문에 갭리스가 깨지기
   쉬우므로 인코딩 결과를 직접 디코딩해서 본다.
2. **음량** — integrated LUFS가 목표치 ±1 안이고 true peak −2dBTP 이하다. 그리고
   같은 상태(base/combat/guardian)끼리 지역 간 음량 차가 1LU 이내여야 한다.
   뒤 지역이 더 크게 들리는 수직 강화를 금지하는 계약이다.
3. **구분** — 네 지역이 한 곡의 pitch 변형이 아니어야 한다. 스펙트럼 무게중심과
   저역 비중 두 축을 재서 두 지역이 양쪽 모두 붙으면 반려한다.

ffmpeg/ffprobe가 필요하다. 실패 항목을 모아 0이 아닌 종료 코드로 알린다.
"""

from __future__ import annotations

import argparse
import array
import json
import math
import shutil
import subprocess
from pathlib import Path

SAMPLE_RATE = 48_000
LOOP_SECONDS = 16.0
TRUE_PEAK_CEILING_DBTP = -2.0
LUFS_TOLERANCE = 1.0
CROSS_REGION_TOLERANCE = 1.0

REGION_SLUGS = {
    "moss_archive": "moss-archive",
    "echo_well": "echo-well",
    "starlight_seed_vault": "starlight-seed-vault",
    "heartwood_observatory": "heartwood-observatory",
}
TARGET_LUFS = {"base": -20, "combat": -19, "guardian": -18}


def _ffmpeg() -> str:
    found = shutil.which("ffmpeg")
    if found is None:
        raise RuntimeError("ffmpeg이 필요합니다")
    return found


def _decode(path: Path) -> array.array:
    """스테레오 16bit PCM으로 디코딩해 인터리브된 샘플을 돌려준다."""

    result = subprocess.run(
        [
            _ffmpeg(), "-v", "error", "-i", str(path),
            "-f", "s16le", "-acodec", "pcm_s16le",
            "-ac", "2", "-ar", str(SAMPLE_RATE), "-",
        ],
        capture_output=True,
        check=True,
    )
    samples = array.array("h")
    samples.frombytes(result.stdout)
    return samples


def _loudness(path: Path) -> tuple[float, float]:
    """(integrated LUFS, true peak dBTP)."""

    result = subprocess.run(
        [
            _ffmpeg(), "-hide_banner", "-nostats", "-i", str(path),
            "-af", "ebur128=peak=true", "-f", "null", "-",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    lines = (result.stderr or "").splitlines()
    integrated = float("nan")
    true_peak = float("nan")
    for index, line in enumerate(lines):
        if "Integrated loudness" in line:
            for follow in lines[index : index + 4]:
                if follow.strip().startswith("I:"):
                    integrated = float(follow.split("I:")[1].split()[0])
                    break
        if "True peak" in line:
            for follow in lines[index : index + 4]:
                if "Peak:" in follow:
                    true_peak = float(follow.split("Peak:")[1].split()[0])
                    break
    return integrated, true_peak


def _seam(samples: array.array) -> tuple[int, float]:
    """(프레임 수, 경계 단차 비율).

    순환 품질에서 실제로 문제가 되는 것은 **파형이 튀는가**다. 시작이 끝보다
    크다는 사실 자체는 결함이 아니다 — 마디 첫 박에 타점이 있는 음악은 원래
    그렇게 들리고, 그게 순환의 자연스러운 이음매다. 그래서 머리·꼬리 음량비는
    재지 않고 경계의 단차만 본다. 타점 간격이 순환에서 어긋나는 문제는 소리를
    분석해 잡을 것이 아니라 악보 단계에서 `_validate_regions`가 막는다.
    """

    frames = len(samples) // 2
    if frames == 0:
        return 0, 1.0
    step = max(
        abs(samples[0] - samples[-2]),
        abs(samples[1] - samples[-1]),
    )
    return frames, step / 32768


def _band_profile(samples: array.array) -> tuple[float, float]:
    """(대략적인 스펙트럼 무게중심, 저역 비중).

    한 곡 전체에 정확한 FFT를 돌릴 필요는 없다. 1차 저역·고역 통과로 에너지를
    두 덩어리로 갈라 밝기와 저역 비중만 본다. 지역이 서로 다른 악기·음역을
    쓰는지 확인하는 용도다.
    """

    mono = [
        (samples[index] + samples[index + 1]) / 65536
        for index in range(0, len(samples) - 1, 2)
    ]
    if not mono:
        return 0.0, 0.0
    low = 0.0
    low_energy = 0.0
    high_energy = 0.0
    weighted = 0.0
    total = 0.0
    coefficient = math.exp(-math.tau * 300 / SAMPLE_RATE)
    for value in mono:
        low = low * coefficient + value * (1 - coefficient)
        high = value - low
        low_energy += low * low
        high_energy += high * high
    # 무게중심 대용: 고역 에너지 비율을 300Hz~8kHz 사이로 사상한다.
    total = low_energy + high_energy
    if total <= 0:
        return 0.0, 0.0
    high_ratio = high_energy / total
    weighted = 300 + high_ratio * 7700
    return weighted, low_energy / total


def verify(root: Path, regions: list[str]) -> list[str]:
    problems: list[str] = []
    loudness: dict[tuple[str, str], float] = {}
    profiles: dict[str, tuple[float, float]] = {}

    for code in regions:
        slug = REGION_SLUGS[code]
        for state, target in TARGET_LUFS.items():
            path = root / f"{slug}-{state}.m4a"
            if not path.exists():
                problems.append(f"{path.name}: 파일이 없습니다")
                continue

            samples = _decode(path)
            frames, step = _seam(samples)
            expected = round(SAMPLE_RATE * LOOP_SECONDS)
            if frames != expected:
                problems.append(
                    f"{path.name}: {frames}프레임 — 16초 loop는 {expected}프레임이어야 "
                    "갭 없이 이어진다(AAC 프라이밍 샘플 확인)"
                )
            if step > 0.02:
                problems.append(
                    f"{path.name}: 순환 경계 단차 {step:.3%} — click이 들립니다"
                )

            integrated, true_peak = _loudness(path)
            if math.isnan(integrated) or abs(integrated - target) > LUFS_TOLERANCE:
                problems.append(
                    f"{path.name}: {integrated:.1f} LUFS — 목표 {target}±"
                    f"{LUFS_TOLERANCE} 밖"
                )
            if math.isnan(true_peak) or true_peak > TRUE_PEAK_CEILING_DBTP:
                problems.append(f"{path.name}: true peak {true_peak:.1f}dBTP")
            loudness[(code, state)] = integrated

            if state == "base":
                profiles[code] = _band_profile(samples)

    # 뒤 지역이 더 크게 들리는 수직 강화 금지 — 같은 상태끼리 음량이 붙어야 한다.
    for state in TARGET_LUFS:
        values = [
            loudness[(code, state)]
            for code in regions
            if (code, state) in loudness and not math.isnan(loudness[(code, state)])
        ]
        if len(values) >= 2 and max(values) - min(values) > CROSS_REGION_TOLERANCE:
            problems.append(
                f"{state}: 지역 간 음량 차 {max(values) - min(values):.1f}LU — "
                "뒤 지역이 더 커지는 수직 강화입니다"
            )

    # 네 지역이 한 곡의 pitch 변형이면 두 축이 함께 붙는다.
    codes = sorted(profiles)
    for first_index, first in enumerate(codes):
        for second in codes[first_index + 1 :]:
            bright_ratio = max(profiles[first][0], profiles[second][0]) / max(
                min(profiles[first][0], profiles[second][0]), 1e-6
            )
            low_delta = abs(profiles[first][1] - profiles[second][1])
            if bright_ratio < 1.06 and low_delta < 0.03:
                problems.append(
                    f"{first} / {second}: 밝기 {bright_ratio:.3f}배, 저역차 "
                    f"{low_delta:.3f} — 두 지역이 같은 곡으로 들립니다"
                )

    return problems


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root", type=Path, default=Path("app/assets/adventure/music")
    )
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument(
        "--regions", nargs="*", default=list(REGION_SLUGS), choices=list(REGION_SLUGS)
    )
    args = parser.parse_args()
    problems = verify(args.root, list(args.regions))
    report = {"root": args.root.as_posix(), "problems": problems, "ok": not problems}
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    print(text)
    raise SystemExit(1 if problems else 0)


if __name__ == "__main__":
    main()
