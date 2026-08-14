"""품종 고유 스킬 signature 32종 — 16품종 × 2스킬.

`ADVENTURE_AUDIO.md`의 음색표는 10품종 × 2 = 20종을 적고 있는데, 그 뒤로 캐릭터가
6종 늘었다(간호사·지휘자·복원가·담비·갤·안내자). 20종만 만들면 여섯 캐릭터가
소리 없이 남으므로 **실제 로스터 전부**를 만든다. 파일명은 서버의 스킬 코드를
그대로 따라가므로 코드가 이름의 단일 원본이다.

## 무엇을 들리게 하려는가

전투에서 귀가 답해야 하는 질문은 `누가 무엇을 했는가`다. 그래서 두 층으로 짠다.

- **품종 목소리** — 그 캐릭터의 재료. 같은 품종의 두 스킬은 같은 목소리를 쓴다.
  뽀또의 두 스킬은 서로 닮았고, 여우비와는 안 닮아야 한다.
- **스킬 크기** — 2번 스킬(Lv7 해금)이 1번보다 크고 길다. 같은 목소리로 더
  멀리 간다.

검수기가 이 구조를 실제로 잰다. **같은 품종끼리의 거리가 다른 품종과의 거리보다
가까워야** 통과한다. 이게 깨지면 소리로 캐릭터를 못 알아본다.

## 금지 방향

음색표는 각 품종에 `금지 방향`을 적어 뒀다(아기 목소리, 칼 소리, 우주 laser…).
여기서는 **목소리·타악 타격·금속 마찰을 아예 만들지 않는다.** 재료가 전부
잎·나무·종이·도자기·유리·천이라 금지 방향으로 갈 수단이 없다.

사용법:
    python build_species_signatures.py --out <폴더>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_expedition_contact_audio import (  # noqa: E402
    SAMPLE_RATE,
    _add_mode,
    _add_noise,
    _fade,
    _normalise,
    _write_mono,
)

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = ROOT / "app" / "assets" / "adventure" / "sfx"
MANIFEST = ROOT / "design-system" / "audio" / "species-signature-manifest.json"

# 접촉음(0.150)보다 조금 낮게. signature는 접촉 재질음 **뒤에** 들려야 한다
# (믹스 우선순위: 접촉 1순위, 시전자 signature 3순위).
PRIMARY_LOUDNESS = 0.108
SECONDARY_LOUDNESS = 0.126

# 한 순간에 또렷한 transient는 셋까지다. signature가 길면 다음 행동과 겹친다.
MAX_SECONDS = 1.10


# ── 품종 목소리 ──────────────────────────────────────────────────────────────
#
# `modes`   : (주파수Hz, 감쇠ms, 이득) — 그 재료가 우는 방식
# `noise`   : (길이ms, 저역Hz, 고역Hz, 이득, 감쇠곡선) — 재료가 스치는 방식
# `spread`  : 2번 스킬에서 음이 몇 배로 벌어지는지. 같은 목소리가 더 멀리 간다.
#
# 주파수는 재료의 크기다. 씨앗·유리는 높고, 나무 몸통·낮은 건반은 낮다.
VOICES: dict[str, dict] = {
    # 뽀또 — 씨앗 두 알, 짧은 잎 튕김.
    "baby-pot": {
        "modes": ((742, 46, 0.30), (1128, 30, 0.16), (1810, 18, 0.07)),
        "noise": (26, 617, 2881, 0.16, 3.2),
        "spread": 1.18,
    },
    # 로제온 — 얇은 나무판 정렬, 낮은 펠트 건반. 어두운 쪽에 넷이 몰려 시들잎과
    # 겹쳤다. 판이 **얇다**는 쪽을 살려 나무 부딪는 상단을 열어 뒀다.
    "handsome-pot": {
        "modes": ((262, 190, 0.30), (524, 120, 0.16), (786, 62, 0.09)),
        "noise": (34, 718, 2870, 0.19, 3.4),
        "spread": 1.12,
    },
    # 블루미 — 종이 꽃 펼침, 짧은 도자기 음.
    "pretty-pot": {
        "modes": ((624, 96, 0.26), (936, 58, 0.15), (1560, 26, 0.08)),
        "noise": (58, 1743, 7718, 0.2, 2.4),
        "spread": 1.22,
    },
    # 가시로 — 마른 줄기 스침 뒤 작은 천 소리.
    "tsundere-pot": {
        "modes": ((452, 64, 0.24), (688, 38, 0.13), (1044, 20, 0.06)),
        "noise": (72, 640, 3198, 0.24, 2.0),
        "spread": 1.16,
    },
    # 시들잎 — 낮은 잎마찰, 부드러운 숨. 지휘자와 밝기가 겹쳐 더 어둡게 눌렀다.
    "zombie-pot": {
        "modes": ((148, 210, 0.28), (232, 128, 0.13), (368, 66, 0.05)),
        "noise": (130, 107, 693, 0.24, 1.6),
        "spread": 1.10,
    },
    # 여우비 — 부채 천 스침, 작은 나무 방울.
    "gumiho-pot": {
        "modes": ((524, 118, 0.26), (786, 70, 0.14), (1310, 34, 0.07)),
        "noise": (86, 709, 3648, 0.21, 2.1),
        "spread": 1.20,
    },
    # 그림싹 — 짧은 잎 채찍과 대나무 click.
    "ninja-pot": {
        "modes": ((880, 28, 0.28), (1320, 18, 0.14), (2200, 11, 0.06)),
        "noise": (20, 890, 4370, 0.26, 4.0),
        "spread": 1.24,
    },
    # 별솔 — 유리 한 음, 나무 지팡이 회전.
    "magical-pot": {
        "modes": ((1176, 240, 0.24), (1764, 140, 0.12), (2940, 70, 0.06)),
        "noise": (30, 1455, 5675, 0.14, 3.0),
        "spread": 1.26,
    },
    # 설화 — 종이 넘김, 작은 렌즈 유리 click.
    "aloof-pot": {
        "modes": ((988, 84, 0.22), (1482, 48, 0.12), (2470, 24, 0.06)),
        "noise": (64, 2141, 8326, 0.22, 2.6),
        "spread": 1.14,
    },
    # 하루 — 연필 한 획, 노트 덮는 소리.
    "student-pot": {
        "modes": ((330, 74, 0.24), (496, 44, 0.13), (826, 22, 0.06)),
        "noise": (92, 312, 1689, 0.23, 2.2),
        "spread": 1.12,
    },
    # ── 음색표 이후에 늘어난 캐릭터 ─────────────────────────────────────────
    # 간호사 — 얇은 거즈 스침, 작은 은종 하나. 경보음으로 가지 않는다.
    "nurse-pot": {
        "modes": ((1046, 168, 0.24), (1568, 96, 0.12), (2614, 46, 0.05)),
        "noise": (48, 1365, 5095, 0.15, 2.8),
        "spread": 1.16,
    },
    # 지휘자 — 나무 지휘봉이 보면대를 스치는 소리와 현의 여운. 시들잎의 낮은
    # 숨과 겹치지 않도록 지휘봉 쪽 상단을 살려 뒀다.
    "maestro-pot": {
        "modes": ((294, 220, 0.24), (441, 132, 0.16), (882, 64, 0.13)),
        "noise": (26, 1756, 5351, 0.24, 3.2),
        "spread": 1.28,
    },
    # 복원가 — 금박을 문지르는 결, 가는 붓의 마찰. 금속 타격이 아니다.
    "restorer-pot": {
        "modes": ((586, 156, 0.24), (879, 92, 0.13), (1465, 44, 0.06)),
        "noise": (104, 1038, 5075, 0.19, 2.0),
        "spread": 1.18,
    },
    # 담비 — 부드러운 발바닥, 몸통의 낮은 울림.
    "marten-pot": {
        "modes": ((174, 150, 0.30), (261, 88, 0.14), (435, 42, 0.06)),
        "noise": (66, 199, 1589, 0.2, 2.4),
        "spread": 1.20,
    },
    # 갤 — 천이 탁 펴지는 소리와 굽의 짧은 톡.
    "gal-pot": {
        "modes": ((698, 54, 0.26), (1047, 32, 0.14), (1746, 16, 0.06)),
        "noise": (44, 1433, 7879, 0.24, 2.8),
        "spread": 1.22,
    },
    # 안내자 — 등불 유리와 밀랍 인장. 캐릭터가 아니라 서고의 목소리다.
    "archive_guide": {
        "modes": ((523, 200, 0.22), (784, 118, 0.12), (1307, 58, 0.05)),
        "noise": (54, 528, 2464, 0.16, 2.6),
        "spread": 1.08,
    },
}

# 스킬 코드. 서버 `SPECIES_SKILLS` / `SPECIES_SECONDARY_SKILLS`와 같아야 한다.
# 어긋나면 앱이 없는 파일을 찾는다 — `_validate`가 형식을 검사하고, 앱 테스트가
# 실제 번들 존재를 검사한다.
SKILLS: dict[str, tuple[str, str]] = {
    "baby-pot": ("sprout_cheer", "root_embrace"),
    "handsome-pot": ("command_blade", "command_crescendo"),
    "pretty-pot": ("heart_spotlight", "ribbon_encore"),
    "tsundere-pot": ("blazing_counter", "iron_uppercut"),
    "zombie-pot": ("grave_gravity", "undying_chain"),
    "gumiho-pot": ("heart_moon_charm", "nine_tail_eclipse"),
    "ninja-pot": ("venom_seam", "shadow_execution"),
    "magical-pot": ("prism_meteor", "timefold_comet"),
    "aloof-pot": ("absolute_zero_read", "steel_verdict"),
    "student-pot": ("ink_formula_burst", "seal_rewrite"),
    "nurse-pot": ("triage_bloom", "white_garden_oath"),
    "maestro-pot": ("golden_downbeat", "silent_coda"),
    "restorer-pot": ("patina_parry", "golden_seam"),
    "marten-pot": ("softpaw_rush", "den_guardian_roar"),
    "gal-pot": ("patchwork_relay", "runway_reversal"),
    "archive_guide": ("archive_lantern", "archive_seal"),
}


def _signature(species: str, *, secondary: bool, seed: int) -> list[float]:
    """한 품종의 목소리로 스킬 하나를 만든다.

    2번 스킬은 같은 재료가 **더 벌어지고 더 오래 운다.** 새 재료를 넣지 않는
    이유는, 넣는 순간 같은 캐릭터로 안 들리기 때문이다.
    """

    voice = VOICES[species]
    spread = voice["spread"] if secondary else 1.0
    # 2번이 더 길되 **같은 캐릭터로 들릴 만큼만** 길어야 한다. 크게 늘리면
    # 자기 1번 스킬보다 남의 스킬과 더 가까워진다(검수기가 잡아낸 값이다).
    stretch = 1.28 if secondary else 1.0
    modes = voice["modes"]
    longest = max(decay for _hz, decay, _gain in modes) * stretch
    seconds = min(MAX_SECONDS, longest / 1000 * 6 + 0.06)
    buffer = [0.0] * round(SAMPLE_RATE * seconds)

    duration_ms, low_hz, high_hz, gain, curve = voice["noise"]
    _add_noise(
        buffer,
        duration_ms=duration_ms * (1.25 if secondary else 1.0),
        low_hz=low_hz,
        high_hz=high_hz,
        gain=gain,
        seed=seed,
        curve=curve,
    )
    for index, (hz, decay_ms, mode_gain) in enumerate(modes):
        # 위쪽 모드일수록 더 벌어진다. 같은 재료가 커진 느낌이 이렇게 난다.
        frequency = hz * (spread ** (index * 0.5))
        _add_mode(
            buffer,
            frequency=frequency,
            decay_ms=decay_ms * stretch,
            gain=mode_gain,
            # 2번 스킬은 두 번째 모드가 살짝 늦게 들어와 두께가 생긴다.
            start=0.012 if secondary and index == 1 else 0.0,
        )
    return buffer


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def build(output_root: Path) -> list[dict]:
    files: list[dict] = []
    for species, (primary, secondary) in SKILLS.items():
        for is_secondary, code in ((False, primary), (True, secondary)):
            seed = int.from_bytes(
                hashlib.sha256(f"{species}:{code}".encode()).digest()[:4], "big"
            )
            samples = _signature(species, secondary=is_secondary, seed=seed)
            _fade(samples)
            samples = _normalise(
                samples,
                loudness=SECONDARY_LOUDNESS if is_secondary else PRIMARY_LOUDNESS,
                peak_ceiling=0.56,
            )
            slug = code.replace("_", "-")
            path = output_root / f"skill-{species}-{slug}.wav"
            _write_mono(path, samples)
            files.append(
                {
                    "species": species,
                    "skill": code,
                    "slot": "unique_2" if is_secondary else "unique_1",
                    "path": path.name,
                    "seconds": round(len(samples) / SAMPLE_RATE, 4),
                    "sha256": _sha256(path),
                }
            )
    return files


def _validate() -> None:
    if set(VOICES) != set(SKILLS):
        missing = set(SKILLS) - set(VOICES)
        extra = set(VOICES) - set(SKILLS)
        raise ValueError(f"목소리와 스킬 표가 어긋납니다. 없음={missing} 남음={extra}")
    seen: set[str] = set()
    for species, codes in SKILLS.items():
        if codes[0] == codes[1]:
            raise ValueError(f"{species}: 두 스킬 코드가 같습니다")
        for code in codes:
            if code in seen:
                raise ValueError(f"스킬 코드가 겹칩니다: {code}")
            seen.add(code)
    if PRIMARY_LOUDNESS >= SECONDARY_LOUDNESS:
        raise ValueError("2번 스킬이 1번보다 작으면 안 됩니다")
    for species, voice in VOICES.items():
        if len(voice["modes"]) < 2:
            raise ValueError(f"{species}: 모드가 둘 미만이면 재질이 안 읽힙니다")
        if voice["spread"] <= 1.0:
            raise ValueError(f"{species}: spread가 1 이하면 2번 스킬이 안 커집니다")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    _validate()
    output = args.out or RUNTIME_DIR
    files = build(output)

    if args.out is None:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(
            json.dumps(
                {
                    "primary_loudness": PRIMARY_LOUDNESS,
                    "secondary_loudness": SECONDARY_LOUDNESS,
                    "files": files,
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    print(f"{len(files)}개 완료 → {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
