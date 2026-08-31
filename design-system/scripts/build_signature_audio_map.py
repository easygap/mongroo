#!/usr/bin/env python3
"""시그니처 음원 manifest를 검증하고 앱이 읽을 Dart 상수 지도를 만든다.

`build_species_signatures.py`·`build_enemy_signatures.py`·
`build_emotion_signatures.py`가 만든 음원은 지금까지 번들에만 들어 있었다.
파일 이름 규칙(`skill-<품종>-<코드>.wav`)을 앱 안에서 손으로 다시 조립하면
품종이 하나 늘 때마다 조용히 어긋나므로, **manifest를 유일한 원본으로 두고**
`행동 코드 → 에셋 경로` 지도를 생성한다.

검증하는 것:

- manifest가 가리키는 파일이 실제 번들에 있고 sha256이 일치한다.
- 행동 코드가 겹치지 않는다. 겹치면 소리로 행동을 구분할 수 없으므로 실패다.
- 코드가 서버 카탈로그에 실제로 존재한다. 없는 코드는 절대 울리지 않는 죽은
  파일이라는 뜻이고, 반대로 카탈로그에만 있는 코드는 아직 소리가 없는 행동이라
  이름을 세어 알려 준다.

사용법:
    python design-system/scripts/build_signature_audio_map.py
    python design-system/scripts/build_signature_audio_map.py --check
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIO_DIR = ROOT / "design-system" / "audio"
RUNTIME_DIR = ROOT / "app" / "assets" / "adventure" / "sfx"
OUTPUT = (
    ROOT
    / "app"
    / "lib"
    / "features"
    / "expedition"
    / "presentation"
    / "expedition_signature_audio.g.dart"
)
ASSET_PREFIX = "adventure/sfx/"
SHA256_PATTERN = re.compile(r"^[0-9A-F]{64}$")

SKILL_MANIFESTS = (
    ("species-signature-manifest.json", "skill"),
    ("emotion-signature-manifest.json", "skill"),
)
ENEMY_MANIFESTS = (("enemy-signature-manifest.json", "attack"),)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _dart_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def _collect(
    manifests: tuple[tuple[str, str], ...],
    problems: list[str],
) -> dict[str, str]:
    """manifest 여러 개를 하나의 `코드 → 경로` 지도로 모은다."""
    codes: dict[str, str] = {}
    for name, code_key in manifests:
        manifest_path = AUDIO_DIR / name
        if not manifest_path.exists():
            # 아직 만들지 않은 묶음은 건너뛴다. 있는 것만 지도에 들어간다.
            continue
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
        for entry in payload["files"]:
            code = str(entry[code_key])
            asset = str(entry["path"])
            runtime = RUNTIME_DIR / asset
            if code in codes:
                problems.append(f"{name}: 행동 코드 `{code}`가 두 파일에 걸쳐 있다")
                continue
            if not runtime.exists():
                problems.append(f"{name}: {asset}가 번들에 없다")
                continue
            expected = str(entry["sha256"]).upper()
            if not SHA256_PATTERN.match(expected):
                problems.append(f"{name}: {asset}의 sha256 형식이 아니다")
                continue
            actual = _sha256(runtime)
            if actual != expected:
                problems.append(
                    f"{name}: {asset}가 manifest 해시와 다르다 "
                    f"({actual[:12]}… != {expected[:12]}…)"
                )
                continue
            codes[code] = ASSET_PREFIX + asset
    return codes


def _server_codes() -> tuple[set[str], set[str]] | None:
    """서버 카탈로그의 실제 행동 코드. import에 실패하면 검사를 건너뛴다.

    적 공격은 음원 빌더가 이미 쓰고 있는 `_load_content`를 그대로 부른다.
    같은 목록을 두 번 짜면 지역 팩이 늘 때 한쪽만 낡는다.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.path.insert(0, str(ROOT / "server"))
    try:
        from app.content.expeditions.combat_identity import (
            FORM_COMBAT_SKILLS,
            SPECIES_SECONDARY_SKILLS,
            SPECIES_SKILLS,
        )
        from build_enemy_signatures import _load_content
    except ImportError:  # pragma: no cover - 서버 venv 밖에서 부를 수 있다.
        return None
    skills = {entry["code"] for entry in SPECIES_SKILLS.values()}
    skills |= {entry["code"] for entry in SPECIES_SECONDARY_SKILLS.values()}
    skills |= {entry["code"] for entry in FORM_COMBAT_SKILLS.values()}
    tangles, guardians = _load_content()
    attacks = {str(entry["attack"]) for entry in [*tangles, *guardians]}
    return skills, attacks


def _render(skills: dict[str, str], enemies: dict[str, str]) -> str:
    lines = [
        "// GENERATED FILE. 수정하지 말고 manifest와 생성 스크립트를 고쳐 주세요.",
        "// design-system/scripts/build_signature_audio_map.py",
        "part of 'expedition_signature_audio.dart';",
        "",
        "/// 품종 고유기와 여섯 성장결 스킬의 전용 소리.",
        "const Map<String, String> expeditionSkillSignatureAssets = {",
    ]
    for code in sorted(skills):
        lines.append(f"  {_dart_string(code)}: {_dart_string(skills[code])},")
    lines += [
        "};",
        "",
        "/// 엉킴과 수호짐승이 저마다 내는 공격 소리.",
        "const Map<String, String> expeditionEnemySignatureAssets = {",
    ]
    for code in sorted(enemies):
        lines.append(f"  {_dart_string(code)}: {_dart_string(enemies[code])},")
    lines += ["};", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="파일을 쓰지 않고 현재 생성물이 manifest와 같은지만 본다",
    )
    args = parser.parse_args()

    problems: list[str] = []
    skills = _collect(SKILL_MANIFESTS, problems)
    enemies = _collect(ENEMY_MANIFESTS, problems)
    overlap = set(skills) & set(enemies)
    if overlap:
        problems.append(f"우리 스킬과 적 공격이 같은 코드를 쓴다: {sorted(overlap)}")

    catalog = _server_codes()
    if catalog is not None:
        server_skills, server_attacks = catalog
        dead_skills = sorted(set(skills) - server_skills)
        dead_attacks = sorted(set(enemies) - server_attacks)
        if dead_skills:
            problems.append(f"서버에 없는 스킬 코드의 음원: {dead_skills}")
        if dead_attacks:
            problems.append(f"서버에 없는 적 공격 코드의 음원: {dead_attacks}")
        missing_skills = sorted(server_skills - set(skills))
        if missing_skills:
            print(f"소리 없는 스킬 {len(missing_skills)}종: {missing_skills}")

    if problems:
        for problem in problems:
            print(f"실패: {problem}")
        return 1

    rendered = _render(skills, enemies)
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != rendered:
            print("실패: 생성물이 manifest와 다르다. 스크립트를 다시 돌려 주세요.")
            return 1
        print(f"확인: 스킬 {len(skills)}종 · 적 공격 {len(enemies)}종")
        return 0

    OUTPUT.write_text(rendered, encoding="utf-8")
    print(
        f"작성: {OUTPUT.relative_to(ROOT)} — "
        f"스킬 {len(skills)}종 · 적 공격 {len(enemies)}종"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
