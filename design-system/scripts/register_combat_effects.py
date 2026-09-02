#!/usr/bin/env python3
"""전투 연출 시트를 런타임 프레임으로 굽고 효과 manifest에 등록한다.

`build_boss_pattern_assets.py`가 시트 한 장을 자르고 크로마를 걷어 내는 일까지
해 주지만, 그 결과를 **앱이 읽는** `app/assets/adventure/effects/manifest.json`에
넣는 일은 여태 손으로 했다. 손으로 넣으면 family 이름이나 성장결을 적으면서
서버 콘텐츠와 어긋나기 쉽다 — 어긋나면 앱은 조용히 공용 연출로 떨어지고,
고유 연출을 만들어 놓고도 공용 연출이 나간다.

그래서 등록에 필요한 값은 전부 **서버 콘텐츠에서 읽는다**. 이 스크립트가
아는 것은 `어느 시트가 어느 행동인가` 하나뿐이고, 그것도 파일 이름으로 안다.

엉킴 의도 24종, 수호짐승 의도 12종, 대원 감정 스킬 6종을 같은 표에 담는다.
셋 다 자기 콘텐츠에 `vfx_family`를 적어 두므로, 굽는 쪽은 어느 쪽인지 알 필요가
없다. 예전 이름은 `register_enemy_attack_effects.py`였는데, 대원 스킬까지
들어오면서 `enemy`가 거짓말이 됐다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
RUNTIME_MANIFEST = REPO / "app/assets/adventure/effects/manifest.json"
RUNTIME_ROOT = REPO / "app/assets/adventure/effects"
BUILDER = REPO / "design-system/scripts/build_boss_pattern_assets.py"


#: 대원 쪽 연출이 어디에서 이는가. 대원 스킬은 카탈로그에 anchor를 적어 두지
#: 않아서 여기서 정한다 — 기존 대원 고유기들이 쓰는 값과 같은 규칙이다:
#: 스스로에게 두르는 것은 `actor_center`, 탐험대 전체를 감싸는 것은 `party_all`,
#: 무대를 건너가는 것은 `stage_center`.
MEMBER_SKILL_ANCHORS = {
    "sunny_radiant_heart": "stage_center",
    "rainy_frozen_tide": "stage_center",
    "ember_rage_breaker": "actor_center",
    "moonlit_lonesome_tempest": "stage_center",
    "sparkling_shock_wonder": "stage_center",
    "mosaic_steel_equilibrium": "actor_center",
    # 길잡이 둘과 기록서 하나. 등불은 탐험대를 덮고, 봉인과 되울림은 건너간다.
    "archive_lantern": "party_all",
    "archive_seal": "stage_center",
    "field_note_echo": "stage_center",
    # T3 감정층은 무대 전체에 얹히는 덧칠이다.
    "fusion_sunny": "stage_center",
    "fusion_rainy": "stage_center",
    "fusion_ember": "stage_center",
    "fusion_moonlit": "stage_center",
    "fusion_sparkling": "stage_center",
    "fusion_mosaic": "stage_center",
}


def _action_index() -> dict[str, dict[str, object]]:
    """`행동 코드 → 등록에 필요한 값`. 서버 콘텐츠가 원본이다."""

    sys.path.insert(0, str(REPO / "server"))
    from app.content.expeditions.combat_identity import (  # noqa: PLC0415
        ELEMENT_KEL,
        FIELD_NOTE_SKILL,
        FORM_COMBAT_SKILLS,
        FUSION_LAYER_PROFILES,
        SPECIES_SECONDARY_SKILLS,
        SPECIES_SKILLS,
    )
    from app.content.expeditions.joint_guard import BEAST_CATALOG  # noqa: PLC0415
    from app.content.expeditions.tangles import TANGLE_CATALOG  # noqa: PLC0415

    index: dict[str, dict[str, object]] = {}

    intent_sources = [tangle["intents"] for tangle in TANGLE_CATALOG.values()]
    for beast in BEAST_CATALOG.values():
        # 잠꼬대도 자기 이름과 대상을 가진 의도다. 빼면 그것만 공용 연출로
        # 떨어져서, 고치려던 문제가 넷 남는다.
        intent_sources.append(list(beast["intents"]) + [beast["sleeptalk"]])

    for intents in intent_sources:
        for intent in intents:
            index[intent["code"]] = {
                "family": intent["vfx_family"],
                "kel": intent["kel"],
                # 카탈로그의 `effect_key`가 아니라 **행동 코드**를 쓴다.
                # 아직 고유 연출이 없던 의도들은 그 자리에 `prism_burst`처럼
                # 공용 키가 적혀 있어서, 그대로 등록하면 새 연출이 공용 연출의
                # 레거시 매핑을 빼앗는다. 이미 고유 연출이 있는 의도들도
                # 행동 코드를 키로 쓰고 있다.
                "effect_key": intent["code"],
                # 엉킴은 몸 한가운데서, 짐승은 잠든 몸 전체에서 인다.
                "anchor": (
                    "beast_center"
                    if "-keeper." in str(intent["vfx_family"])
                    else "tangle_center"
                ),
            }

    # 감정 스킬은 자기 성장결이 곧 이름이다.
    member_skills = [(kel, skill) for kel, skill in FORM_COMBAT_SKILLS.items()]
    # 길잡이 둘과 기록서 하나는 성장결이 따로 적혀 있지 않아 원소에서 끌어온다.
    # 서버의 `ELEMENT_KEL`을 그대로 쓴다 — 손으로 옮기면 어긋난다.
    member_skills += [
        (ELEMENT_KEL[str(skill["element"])], skill)
        for skill in (
            SPECIES_SKILLS["archive_guide"],
            SPECIES_SECONDARY_SKILLS["archive_guide"],
            FIELD_NOTE_SKILL,
        )
    ]
    for kel, skill in member_skills:
        index[str(skill["code"])] = {
            "family": skill["vfx_family"],
            "kel": kel,
            "effect_key": skill["code"],
            "anchor": MEMBER_SKILL_ANCHORS[str(skill["code"])],
        }

    # T3 감정층. 고유기 연출을 **바꾸지 않고** 그 위에 겹치는 두 번째 레이어라,
    # 대원 스킬과 같은 표에 넣되 자기 family를 따로 가진다.
    for kel, profile in FUSION_LAYER_PROFILES.items():
        code = f"fusion_{kel}"
        index[code] = {
            "family": profile["vfx_family"],
            "kel": kel,
            "effect_key": code,
            "anchor": MEMBER_SKILL_ANCHORS[code],
        }
    return index


def _build(source: Path, effect_key: str, concept_root: Path) -> dict[str, object]:
    concept_root.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--source",
            str(source),
            "--effect-key",
            effect_key,
            "--concept-root",
            str(concept_root),
            "--runtime-root",
            str(RUNTIME_ROOT),
        ],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"{effect_key} 굽기 실패\n{result.stdout}\n{result.stderr}"
        )
    return json.loads((concept_root / "manifest.json").read_text(encoding="utf-8"))


#: 이 시트들이 실제로 접촉하는 프레임.
#
# 굽는 스크립트는 `contact_frame: 4`를 박아 두는데, 그것은 v9 시트가 5번째 칸에서
# 부딪히도록 그려졌기 때문이다. v10 시트는 프롬프트가 6번째 칸을 접촉 정점으로
# 지정해서 한 칸 뒤다. 이 값이 어긋나면 타격 정지와 피해 숫자가 그림보다 한 프레임
# 먼저 튄다 — 눈에 띄지는 않아도 손끝에서 어긋난 것으로 읽힌다.
CONTACT_FRAME = 5

#: 스필로 보는 기준. 초록·파랑이 빨강보다 이만큼 높으면 키 색이 번진 것으로 본다.
SPILL_SCORE = 40

#: 스필을 걷어 낸 뒤 초록·파랑이 빨강보다 높아도 되는 여유.
SPILL_HEADROOM = 24


def _despill(directory: Path) -> None:
    """가장자리에 번진 키 색을 걷어 낸다.

    굽는 스크립트는 매트 바깥으로 RGB를 넓혀 주지만 **번진 색까지 되돌리지는
    않는다.** 그래서 짙은 보라 채찍의 테두리에 민트색 잔털이 남았다 — 알파는
    맞는데 색이 배경 쪽으로 끌려간 것이다. 넓이로 세면 0.13%라 검사는 통과하는데
    눈에는 팔레트에 없는 색이 보인다.

    시안이 번진 픽셀만 골라 초록·파랑을 빨강 쪽으로 눌러 준다. 원래 차가운
    그림(물·얼음)은 빨강도 함께 높아서 이 기준에 걸리지 않는다.
    """

    for frame in sorted(directory.glob("frame-*.webp")):
        with Image.open(frame) as opened:
            rgba = np.asarray(opened.convert("RGBA"), dtype=np.int16).copy()
        red, green, blue = rgba[..., 0], rgba[..., 1], rgba[..., 2]
        spill = (
            (rgba[..., 3] > 0)
            & (np.minimum(green - red, blue - red) >= SPILL_SCORE)
        )
        if not spill.any():
            continue
        ceiling = red + SPILL_HEADROOM
        green[spill] = np.minimum(green[spill], ceiling[spill])
        blue[spill] = np.minimum(blue[spill], ceiling[spill])
        Image.fromarray(rgba.astype(np.uint8), "RGBA").save(
            frame, format="WEBP", quality=88, method=6
        )


def _refresh_qa(directory: Path, concept_root: Path, effect_key: str) -> None:
    """스필을 걷어 낸 **뒤의** 프레임으로 QA 증거를 다시 만든다.

    굽는 스크립트는 QA 시트를 먼저 만들고 끝난다. 그 뒤에 스필을 걷으면 증거와
    실제로 나가는 그림이 달라진다 — 4.7이 요구하는 납품 묶음의 뜻이 없어진다.
    """

    sys.path.insert(0, str(BUILDER.parent))
    import build_boss_pattern_assets as builder  # noqa: PLC0415

    frames = [
        Image.open(path).convert("RGBA")
        for path in sorted(directory.glob("frame-*.webp"))
    ]
    qa = concept_root / "qa"
    qa.mkdir(parents=True, exist_ok=True)
    builder._qa(frames, qa / f"{effect_key}-v1-light-dark.webp")
    builder._animated_preview(frames, qa / f"{effect_key}-v1-preview.webp")


def _runtime_hash(directory: Path) -> str:
    """프레임 해시를 모은 해시. 굽는 스크립트와 같은 방식이다."""

    frames = sorted(directory.glob("frame-*.webp"))
    joined = "".join(
        hashlib.sha256(frame.read_bytes()).hexdigest().upper() for frame in frames
    )
    return hashlib.sha256(joined.encode("ascii")).hexdigest().upper()


def _entry(built: dict[str, object], meta: dict[str, object]) -> dict[str, object]:
    return {
        "family": meta["family"],
        # 앱은 서버가 보낸 effect_key로도 찾는다. 카탈로그의 값을 그대로 쓴다.
        "effect_keys": [meta["effect_key"]],
        "kel": meta["kel"],
        "directory": built["runtime_directory"],
        "frame_count": built["frame_count"],
        "frame_size": built["frame_size"],
        "frame_durations_ms": built["frame_durations_ms"],
        "contact_frame": CONTACT_FRAME,
        "pivot": [0.5, 0.5],
        "anchor": meta["anchor"],
        # 실기 프로파일·배경 합성 검수 전에는 후보다(설계서 4.7).
        "production_ready": False,
        "source_hash": built["source_sha256"],
        "runtime_hash": built["runtime_sha256"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--concept-root", type=Path, required=True)
    parser.add_argument(
        "--raw",
        type=Path,
        default=None,
        help="시트가 든 디렉터리. 기본값은 <concept-root>/_raw",
    )
    args = parser.parse_args()

    concept_root = (REPO / args.concept_root).resolve()
    raw = (REPO / args.raw).resolve() if args.raw else concept_root / "_raw"
    actions = _action_index()

    manifest = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))
    existing = {entry["family"]: index for index, entry in enumerate(manifest["effects"])}

    # 새로 받은 시트는 `_raw`에 있고, 이미 등록한 것은 각 effect의 `sources`에
    # 원본 그대로 남아 있다. 다시 구울 때 시트를 또 받지 않아도 되게 둘 다 본다.
    sheets = sorted(raw.glob("*-sheet.png")) if raw.exists() else []
    if not sheets:
        sheets = sorted(concept_root.glob("*/sources/*-sheet-chroma.png"))
    if not sheets:
        raise SystemExit(f"{concept_root}에 구울 시트가 없습니다")

    added: list[str] = []
    for sheet in sheets:
        effect_key = sheet.stem.removesuffix("-sheet").removesuffix("-sheet-chroma")
        meta = actions.get(effect_key)
        if meta is None:
            raise SystemExit(f"{effect_key}는 서버 콘텐츠에 없는 행동입니다")
        built = _build(sheet, effect_key, concept_root / effect_key.replace("_", "-"))
        runtime = RUNTIME_ROOT / str(built["runtime_directory"])
        _despill(runtime)
        _refresh_qa(runtime, concept_root / effect_key.replace("_", "-"), effect_key)
        built["runtime_sha256"] = _runtime_hash(runtime)
        entry = _entry(built, meta)
        if entry["family"] in existing:
            manifest["effects"][existing[entry["family"]]] = entry
        else:
            manifest["effects"].append(entry)
        added.append(str(entry["family"]))

    manifest["effects"].sort(key=lambda item: item["family"])
    RUNTIME_MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for family in added:
        print("등록:", family)
    print(f"{len(added)}종을 manifest에 넣었습니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
