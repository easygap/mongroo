"""여섯 성장결 signature를 적용 **전에** 검사한다.

품종 검수기가 묻는 것은 `누가 했는가`이고, 여기서 묻는 것은 다르다.

    **여섯 결이 서로 구분되면서도 서열이 생기지 않았는가.**

기획은 어느 결도 유불리를 갖지 않는다고 못 박았다. 소리에서 서열은 두 가지로
샌다 — 더 크거나, 더 길거나. 그래서 이 검수기의 핵심 검사 셋은

1. **크기 동등** — 여섯의 50ms 최대 RMS가 서로 8% 안.
2. **길이 동등** — 여섯의 유효 길이가 서로 10% 안.
3. **음색 구분** — 가장 가까운 두 결도 로그 밝기로 0.14 이상 떨어진다.

1·2가 깨지면 특정 결이 더 세게 들리고, 3이 깨지면 결이 안 읽힌다. 세 조건이
동시에 성립해야 `같은 무게의 다른 언어`가 된다.

그 밖에 접촉음보다 조용한지, 품종 고유기를 덮지 않는지, 예산·peak·DC·끝단
무음을 함께 본다.

사용법:
    python verify_emotion_signatures.py <검사할 폴더>
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_emotion_signatures import (
    KELS,
    SECONDS,
)
from build_species_signatures import RUNTIME_DIR, SKILLS
from verify_species_signatures import (
    MAX_DC_OFFSET,
    MAX_TAIL_LEVEL,
    MAX_TRUE_PEAK,
    MAX_VS_CONTACT_RMS,
    MIN_BETWEEN_DISTANCE,
    _effective_seconds,
    _read,
    _spectral_centroid,
    _window_rms,
)

# 여섯 사이에 허용하는 크기·길이 편차. 이보다 벌어지면 서열이 들린다.
MAX_LOUDNESS_SPREAD = 0.08
MAX_LENGTH_SPREAD = 0.10


def _spread(values: list[float]) -> float:
    """가장 큰 값이 가장 작은 값보다 몇 배 큰지를 비율로 돌려준다."""

    low = min(values)
    if low <= 0:
        return math.inf
    return max(values) / low - 1.0


def verify(folder: Path) -> int:
    problems: list[str] = []
    measured: dict[str, tuple[float, float, float]] = {}

    for kel, material in KELS.items():
        slug = str(material["code"]).replace("_", "-")
        path = folder / f"skill-emotion-{slug}.wav"
        if not path.exists():
            problems.append(f"{path.name}: 파일이 없습니다")
            continue
        samples, rate = _read(path)
        seconds = len(samples) / rate
        measured[kel] = (
            _spectral_centroid(samples, rate),
            _effective_seconds(samples, rate),
            _window_rms(samples, rate),
        )
        if seconds > SECONDS + 0.01:
            problems.append(
                f"{path.name}: {seconds:.2f}초가 예산 {SECONDS}초를 넘습니다"
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

    if len(measured) == len(KELS):
        loudness_spread = _spread([rms for _c, _s, rms in measured.values()])
        if loudness_spread > MAX_LOUDNESS_SPREAD:
            loudest = max(measured, key=lambda kel: measured[kel][2])
            problems.append(
                f"여섯 결의 크기가 {loudness_spread:.0%} 벌어졌습니다"
                f"(가장 큰 결 {loudest}). 결 사이에 서열이 생깁니다"
            )
        length_spread = _spread([sec for _c, sec, _r in measured.values()])
        if length_spread > MAX_LENGTH_SPREAD:
            longest = max(measured, key=lambda kel: measured[kel][1])
            problems.append(
                f"여섯 결의 길이가 {length_spread:.0%} 벌어졌습니다"
                f"(가장 긴 결 {longest}). 더 오래 우는 결이 더 센 결로 읽힙니다"
            )

        # 밝기만으로 갈려야 한다. 길이가 같으므로 거리는 로그 밝기 차이다.
        pairs = sorted(measured)
        for index, kel in enumerate(pairs):
            for other in pairs[index + 1 :]:
                gap = abs(
                    math.log(max(measured[kel][0], 1.0))
                    - math.log(max(measured[other][0], 1.0))
                )
                if gap < MIN_BETWEEN_DISTANCE:
                    problems.append(
                        f"{kel}와 {other}가 밝기로 {gap:.2f}만큼밖에 안 떨어져 "
                        f"있습니다. 두 결이 같은 소리로 들립니다"
                    )

    contact = RUNTIME_DIR / "contact-wood.wav"
    if contact.exists() and measured:
        contact_samples, contact_rate = _read(contact)
        contact_rms = _window_rms(contact_samples, contact_rate)
        loudest = max(rms for _c, _s, rms in measured.values())
        if loudest > contact_rms * MAX_VS_CONTACT_RMS:
            problems.append(
                f"가장 큰 성장결 소리({loudest:.3f})가 접촉음"
                f"({contact_rms:.3f})보다 큽니다. 접촉이 먼저 들려야 합니다"
            )

    # 선택 스킬이 품종 고유기를 덮으면 자기 캐릭터가 안 들린다.
    unique_rms: list[float] = []
    for species, (primary, _secondary) in SKILLS.items():
        path = RUNTIME_DIR / f"skill-{species}-{primary.replace('_', '-')}.wav"
        if not path.exists():
            continue
        samples, rate = _read(path)
        unique_rms.append(_window_rms(samples, rate))
    if unique_rms and measured:
        budget = max(unique_rms)
        loudest = max(rms for _c, _s, rms in measured.values())
        if loudest > budget * 1.02:
            problems.append(
                f"성장결 소리({loudest:.3f})가 가장 큰 품종 고유기"
                f"({budget:.3f})보다 큽니다"
            )

    print(f"검사한 성장결 signature {len(measured)}종")
    for kel in sorted(measured, key=lambda name: measured[name][0]):
        centroid, seconds, rms = measured[kel]
        print(
            f"  {kel:10} 밝기 {centroid:5.0f}Hz  길이 {seconds * 1000:4.0f}ms  "
            f"크기 {rms:.3f}"
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
