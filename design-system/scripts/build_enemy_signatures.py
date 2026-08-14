"""적 공격 signature 29종 — 엉킴 12종 × 2 + 수호자 5.

`ADVENTURE_AUDIO.md`는 16+8=24를 적고 있는데 실제 콘텐츠는 엉킴 24 + 수호자 5다.
품종 signature와 같은 이유로 **실제 콘텐츠 전부**를 만든다.

## 접촉음과 무엇이 다른가

이미 `contact-{재질}.wav` 여섯이 있다. 그건 **맞는 순간**이고, 여기 만드는 것은
**날아오기 시작하는 순간**이다. 둘은 한 공격에서 순서대로 들린다.

    [signature: 무엇이 오는가] → (예고 대기) → [contact: 무엇에 맞았는가]

그래서 signature는 접촉음보다 **먼저·조용히·덜 또렷하게** 들려야 한다. 접촉이
믹스 1순위, 적 signature가 2순위다.

## 무엇으로 구분하는가

기준 문서가 못 박은 것이 있다. *`적 공격 signature는 같은 공용 파동의 pitch·EQ
변형으로 세지 않는다`*. 그래서 세 축을 **각각 다른 근거**에서 가져온다.

- **몸통 재질** — 그 적이 무엇으로 되어 있는가. 같은 적의 두 공격이 공유한다.
  종이 뭉치는 종이로, 물방울은 물로 날아온다.
- **퍼짐** — `front`는 한 점으로 모이고, `all`은 넓게 흩어지며, `lowest`는 가늘게
  훑는다. 대상 방식이 소리 모양을 정한다.
- **무게** — 위력 1·2·3이 길이와 저역으로 드러난다.

셋 다 서버 콘텐츠에서 그대로 읽어 온다. 소리가 판정과 어긋날 수 없다.

사용법:
    python build_enemy_signatures.py --out <폴더>
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
MANIFEST = ROOT / "design-system" / "audio" / "enemy-signature-manifest.json"

# 접촉음(0.150)보다 확실히 조용하다. 오는 소리가 맞는 소리보다 크면 순서가
# 뒤집혀 들린다.
SIGNATURE_LOUDNESS = 0.078
# 예고 창 안에 들어가야 한다. 넘치면 접촉음과 겹쳐 둘 다 뭉갠다.
MAX_SECONDS = 0.62


# ── 몸통 재질 ────────────────────────────────────────────────────────────────
#
# (모드 주파수 셋, 노이즈 저역, 노이즈 고역, 노이즈 곡선)
# 접촉 재질음과 **같은 재료지만 다른 몸짓**이다. 접촉은 부딪고, 이쪽은 움직인다.
BODIES: dict[str, tuple[tuple[float, float, float], float, float, float]] = {
    # 종이 — 넘기고 스치는 결. 부딪는 소리가 아니다.
    "paper": ((1180, 1770, 2950), 1500, 6800, 2.1),
    # 잎 — 마르고 성긴 스침.
    "leaf": ((860, 1290, 2150), 900, 4600, 1.9),
    # 물 — 낮게 밀려오는 결. 방울이 아니라 흐름이다.
    "water": ((320, 480, 800), 220, 1700, 1.5),
    # 나무 — 몸통이 굴러가는 낮은 결.
    "wood": ((196, 294, 490), 160, 1300, 2.3),
    # 돌 — **갈리는** 마찰이지 때리는 소리가 아니다. `contact-stone`(치는 순간,
    # 1438Hz)보다 확실히 낮게 둔다. 붙여 두면 가장 짧고 가벼운 돌 공격이
    # 접촉음과 겹쳐 두 번 맞은 것처럼 들린다.
    "stone": ((330, 495, 825), 300, 1750, 2.6),
    # 돌비늘 — 수호자의 몸통. 같은 돌이라도 **덩치가 다르다.** 잔 돌조각과 같은
    # 소리를 내면 소굴에 들어선 것이 안 들리고, `contact-stone`과도 겹친다.
    "scale": ((138, 207, 345), 90, 900, 2.9),
}

# ── 퍼짐 ────────────────────────────────────────────────────────────────────
#
# (길이 배율, 노이즈 길이 배율, 모드 이득 배율, 노이즈 이득 배율)
# `front`는 한 점으로 모여 짧고 또렷하다. `all`은 길고 넓다. `lowest`는 가늘다.
SPREADS = {
    "front": (1.00, 0.80, 1.00, 0.85),
    "all": (1.45, 1.60, 0.78, 1.15),
    "lowest": (0.86, 1.05, 0.72, 0.95),
}

# ── 무게 ────────────────────────────────────────────────────────────────────
#
# 위력이 클수록 길고 낮다. 값은 정액이라 위력 3이 1의 세 배가 되지는 않는다.
WEIGHTS = {
    1: (1.00, 1.00),
    2: (1.22, 0.90),
    3: (1.48, 0.80),
}


def _attack(
    material: str, target: str, power: int, *, seed: int, tail_ms: float
) -> list[float]:
    modes, noise_low, noise_high, curve = BODIES[material]
    length_scale, noise_scale, mode_gain_scale, noise_gain_scale = SPREADS[target]
    weight_length, weight_pitch = WEIGHTS[power]

    decay_ms = tail_ms * length_scale * weight_length
    seconds = min(MAX_SECONDS, decay_ms / 1000 * 5 + 0.05)
    buffer = [0.0] * round(SAMPLE_RATE * seconds)

    _add_noise(
        buffer,
        duration_ms=decay_ms * noise_scale,
        low_hz=noise_low * weight_pitch,
        high_hz=noise_high * weight_pitch,
        gain=0.26 * noise_gain_scale,
        seed=seed,
        curve=curve,
    )
    for index, hz in enumerate(modes):
        _add_mode(
            buffer,
            frequency=hz * weight_pitch,
            decay_ms=decay_ms * (0.85 ** index),
            gain=(0.22, 0.12, 0.05)[index] * mode_gain_scale,
            # 넓게 퍼지는 공격은 모드가 조금씩 늦게 들어와 번진다.
            start=0.010 * index if target == "all" else 0.0,
        )
    return buffer


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _load_content() -> tuple[list[dict], list[dict]]:
    """서버 콘텐츠에서 (적, 공격) 쌍을 그대로 읽는다.

    파일명·재질·대상·위력을 여기서 지어내지 않는다. 콘텐츠가 바뀌면 소리도
    따라 바뀌어야 하고, 손으로 옮겨 적으면 반드시 어긋난다.
    """

    server = ROOT / "server"
    sys.path.insert(0, str(server))
    from app.content.expeditions.tangles import (  # noqa: E402
        TANGLE_CATALOG,
        TANGLE_INTENT_CONTACT_MATERIAL,
        TANGLE_CONTACT_MATERIAL,
    )

    tangles = []
    for code, definition in TANGLE_CATALOG.items():
        for intent in definition.get("intents") or []:
            material = TANGLE_INTENT_CONTACT_MATERIAL.get(
                intent["code"]
            ) or TANGLE_CONTACT_MATERIAL.get(code, "wood")
            tangles.append(
                {
                    "enemy": code,
                    "attack": intent["code"],
                    "material": material,
                    "target": intent.get("target", "front"),
                    "power": int(intent.get("power", 1)),
                }
            )

    # **실린 지역 팩을 전부** 훑는다. 한 파일만 보면 지역을 실은 날 그 수호자만
    # 소리 없이 남고, 눈으로는 안 보인다.
    guardians = []
    seen: set[str] = set()
    packs = sorted((server / "app/content/expeditions/v1").glob("*.json"))
    for pack in packs:
        content = json.loads(pack.read_text(encoding="utf-8"))
        for event_code, event in (content.get("events") or {}).items():
            encounter = event.get("encounter") or {}
            if encounter.get("kind") != "guardian":
                continue
            pools = [encounter.get("intents") or []]
            pools += [
                phase.get("intents") or [] for phase in (encounter.get("boss_phases") or [])
            ]
            for pool in pools:
                for intent in pool:
                    if intent["code"] in seen:
                        continue
                    seen.add(intent["code"])
                    guardians.append(
                        {
                            "enemy": event_code,
                            "attack": intent["code"],
                            # 수호자는 돌비늘이다. 잔 돌과 다른 몸통을 쓴다.
                            "material": intent.get("contact_material", "scale"),
                            "target": intent.get("target", "front"),
                            "power": int(intent.get("power", 2)),
                        }
                    )
    return tangles, guardians


def build(output_root: Path) -> list[dict]:
    tangles, guardians = _load_content()
    files: list[dict] = []

    for kind, entries in (("enemy", tangles), ("guardian", guardians)):
        for entry in entries:
            seed = int.from_bytes(
                hashlib.sha256(
                    f"{entry['enemy']}:{entry['attack']}".encode()
                ).digest()[:4],
                "big",
            )
            # 같은 적의 두 공격은 같은 몸통 여운을 쓴다 — 그래야 누가 오는지
            # 들린다. 적마다 여운 길이를 조금씩 달리해 개체를 구분한다.
            # 폭을 좁게 둔다. 넓으면 개체 차이가 **대상 모양**(front/all)의
            # 길이 차이를 덮어 버려 예고를 보고 방어를 고를 수 없게 된다.
            tail_ms = 62 + (seed % 4) * 5
            samples = _attack(
                entry["material"],
                entry["target"],
                entry["power"],
                seed=seed,
                tail_ms=tail_ms,
            )
            _fade(samples)
            samples = _normalise(
                samples, loudness=SIGNATURE_LOUDNESS, peak_ceiling=0.44
            )
            enemy_slug = entry["enemy"].replace("_", "-")
            attack_slug = entry["attack"].replace("_", "-")
            path = output_root / f"{kind}-{enemy_slug}-{attack_slug}.wav"
            _write_mono(path, samples)
            files.append(
                {
                    "kind": kind,
                    **entry,
                    "path": path.name,
                    "seconds": round(len(samples) / SAMPLE_RATE, 4),
                    "sha256": _sha256(path),
                }
            )
    return files


def _validate() -> None:
    tangles, guardians = _load_content()
    if not tangles or not guardians:
        raise ValueError("콘텐츠에서 적을 읽지 못했습니다")
    for entry in tangles + guardians:
        if entry["material"] not in BODIES:
            raise ValueError(f"{entry['attack']}: 모르는 재질 {entry['material']}")
        if entry["target"] not in SPREADS:
            raise ValueError(f"{entry['attack']}: 모르는 대상 {entry['target']}")
        if entry["power"] not in WEIGHTS:
            raise ValueError(f"{entry['attack']}: 모르는 위력 {entry['power']}")
    codes = [entry["attack"] for entry in tangles + guardians]
    if len(codes) != len(set(codes)):
        raise ValueError("공격 코드가 겹칩니다")


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
                {"loudness": SIGNATURE_LOUDNESS, "files": files},
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
