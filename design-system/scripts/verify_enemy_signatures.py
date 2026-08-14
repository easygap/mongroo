"""적 공격 signature 29종을 적용 **전에** 검사한다.

한 공격에서 소리는 순서대로 들린다.

    [signature: 무엇이 오는가] → (예고 대기) → [contact: 무엇에 맞았는가]

그래서 검사도 그 순서를 지킨다.

1. **접촉음보다 조용한가** — 오는 소리가 맞는 소리보다 크면 순서가 뒤집혀
   들린다. 믹스에서 접촉이 1순위다.
2. **같은 재질의 접촉음과 헷갈리지 않는가** — `enemy-…-paper-…`가 `contact-paper`와
   똑같이 들리면 두 번 맞은 것처럼 들린다.
3. **대상 방식이 소리 모양으로 읽히는가** — `all`은 `front`보다 길게 번져야 한다.
   `설계서가 예고를 보고 방어를 고르라고 하는데, 예고가 안 들리면 고를 수 없다.`
4. **위력이 무게로 읽히는가** — 같은 재질·같은 대상이면 위력 3이 1보다 길다.
5. **예고 창 안에 들어가는가** — 넘치면 접촉음과 겹쳐 둘 다 뭉갠다.
6. peak·DC·끝단 무음.

사용법:
    python verify_enemy_signatures.py <검사할 폴더>
"""

from __future__ import annotations

import argparse
import cmath
import math
import sys
import wave
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_enemy_signatures import (  # noqa: E402
    MAX_SECONDS,
    RUNTIME_DIR,
    _load_content,
)

MAX_TRUE_PEAK = 0.79
MAX_DC_OFFSET = 0.002
MAX_TAIL_LEVEL = 0.02

# 접촉음 대비 상한. 오는 소리는 맞는 소리보다 작아야 한다.
MAX_VS_CONTACT_RMS = 0.80

# 같은 재질 접촉음과 갈리는 기준. 밝기·길이 중 하나는 확실히 달라야 한다.
MIN_VS_CONTACT_CENTROID_RATIO = 1.20
MIN_VS_CONTACT_LENGTH_RATIO = 1.35

# `all`이 `front`보다 이 배는 길어야 넓게 퍼지는 것으로 들린다.
MIN_ALL_VS_FRONT_LENGTH = 1.15


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


def verify(folder: Path) -> int:
    problems: list[str] = []
    tangles, guardians = _load_content()
    entries = [("enemy", e) for e in tangles] + [("guardian", g) for g in guardians]

    measured: dict[str, dict] = {}
    for kind, entry in entries:
        name = (
            f"{kind}-{entry['enemy'].replace('_', '-')}"
            f"-{entry['attack'].replace('_', '-')}.wav"
        )
        path = folder / name
        if not path.exists():
            problems.append(f"{name}: 파일이 없습니다")
            continue
        samples, rate = _read(path)
        seconds = len(samples) / rate
        measured[entry["attack"]] = {
            **entry,
            "rms": _window_rms(samples, rate),
            "centroid": _spectral_centroid(samples, rate),
            "length": _effective_seconds(samples, rate),
            "name": name,
        }
        if seconds > MAX_SECONDS + 0.01:
            problems.append(
                f"{name}: {seconds:.2f}초가 예고 창 {MAX_SECONDS}초를 넘습니다"
            )
        peak = max((abs(v) for v in samples), default=0.0)
        if peak > MAX_TRUE_PEAK:
            problems.append(f"{name}: peak {peak:.2f}가 상한을 넘습니다")
        offset = abs(sum(samples) / max(1, len(samples)))
        if offset > MAX_DC_OFFSET:
            problems.append(f"{name}: DC 오프셋 {offset:.4f}")
        tail = max((abs(v) for v in samples[-64:]), default=0.0)
        if tail > MAX_TAIL_LEVEL:
            problems.append(f"{name}: 끝이 {tail:.3f}에서 잘립니다")

    # 1·2. 같은 재질의 접촉음과 비교
    contacts: dict[str, tuple[float, float, float]] = {}
    for material in ("leaf", "paper", "water", "wood", "stone"):
        contact = RUNTIME_DIR / f"contact-{material}.wav"
        if not contact.exists():
            continue
        samples, rate = _read(contact)
        contacts[material] = (
            _window_rms(samples, rate),
            _spectral_centroid(samples, rate),
            _effective_seconds(samples, rate),
        )

    for data in measured.values():
        contact = contacts.get(data["material"])
        if contact is None:
            continue
        contact_rms, contact_centroid, contact_length = contact
        if data["rms"] > contact_rms * MAX_VS_CONTACT_RMS:
            problems.append(
                f"{data['name']}: 접촉음보다 큽니다 "
                f"({data['rms']:.3f} vs {contact_rms:.3f}). "
                f"오는 소리가 맞는 소리보다 크면 순서가 뒤집혀 들립니다"
            )
        centroid_ratio = max(data["centroid"], contact_centroid) / max(
            min(data["centroid"], contact_centroid), 1e-9
        )
        length_ratio = max(data["length"], contact_length) / max(
            min(data["length"], contact_length), 1e-9
        )
        if (
            centroid_ratio < MIN_VS_CONTACT_CENTROID_RATIO
            and length_ratio < MIN_VS_CONTACT_LENGTH_RATIO
        ):
            problems.append(
                f"{data['name']}: contact-{data['material']}과 구분되지 않습니다 "
                f"(밝기 {centroid_ratio:.2f}배, 길이 {length_ratio:.2f}배). "
                f"두 번 맞은 것처럼 들립니다"
            )

    # 3. 대상 방식이 길이로 읽히는가 — 같은 재질·같은 위력끼리만 비교한다.
    by_shape: dict[tuple[str, int], dict[str, list[float]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for data in measured.values():
        by_shape[(data["material"], data["power"])][data["target"]].append(
            data["length"]
        )
    compared = 0
    for (material, power), targets in sorted(by_shape.items()):
        if "all" not in targets or "front" not in targets:
            continue
        compared += 1
        widest = sum(targets["all"]) / len(targets["all"])
        focused = sum(targets["front"]) / len(targets["front"])
        if widest < focused * MIN_ALL_VS_FRONT_LENGTH:
            problems.append(
                f"{material} 위력{power}: 전체 공격({widest * 1000:.0f}ms)이 "
                f"단일 공격({focused * 1000:.0f}ms)보다 넓게 들리지 않습니다"
            )

    # 4. 위력이 무게로 읽히는가 — 같은 재질·같은 대상끼리만.
    by_weight: dict[tuple[str, str], list[tuple[int, float]]] = defaultdict(list)
    for data in measured.values():
        by_weight[(data["material"], data["target"])].append(
            (data["power"], data["length"])
        )
    for (material, target), values in sorted(by_weight.items()):
        powers = {power for power, _length in values}
        if len(powers) < 2:
            continue
        lightest = min(values)[0]
        heaviest = max(values)[0]
        light = [length for power, length in values if power == lightest]
        heavy = [length for power, length in values if power == heaviest]
        if sum(heavy) / len(heavy) <= sum(light) / len(light):
            problems.append(
                f"{material}/{target}: 위력 {heaviest}가 위력 {lightest}보다 "
                f"무겁게 들리지 않습니다"
            )

    print(f"검사한 signature {len(measured)}개 (엉킴 {len(tangles)}, 수호자 {len(guardians)})")
    print(f"  대상 모양 비교 {compared}쌍, 재질 {len(contacts)}종과 대조")
    for material in sorted(contacts):
        group = [d for d in measured.values() if d["material"] == material]
        if not group:
            continue
        print(
            f"  {material:6} signature {len(group)}개  "
            f"밝기 {sum(d['centroid'] for d in group) / len(group):5.0f}Hz  "
            f"접촉 {contacts[material][1]:5.0f}Hz"
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
