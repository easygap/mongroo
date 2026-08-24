#!/usr/bin/env python3
"""백화와 세렌의 씨앗~개화 네 단계를 성장 시트에서 빌드한다.

`build_premium_character_v6.py`는 만개 원화 한 장만 내보낸다. v6 두 사람은
만개 지원가로 설계됐는데 `plant_species`에는 심을 수 있는 종으로 올라가 있어서,
240·280 씨앗을 주고 사면 씨앗부터 개화까지 네 단계 내내 대체 그림을 보게 된다.
그 네 단계를 채우는 스크립트다.

v7 3종과 같은 파이프라인을 쓴다. 네 칸짜리 성장 시트 한 장을 칸별로 자르고,
같은 배율로 512x768 캔버스에 발끝을 맞춰 앉힌 뒤, 감정 여섯 결은 원화를 새로
그리지 않고 `_emotion_blend`로 얹는다. 캐릭터 본체를 코드로 그리지 않는다는
규칙은 그대로다 - 이 스크립트는 검수한 원화를 자르고 앉히기만 한다.

**이미 나가 있는 만개 원화는 건드리지 않는다.** 만개 중립본은
`build_premium_character_v6.py`가 만든 것을 그대로 두고, 감정 여섯 결만
그 파일에서 파생한다. 배율 기준이 서로 달라(468 대 448) 다시 만들면 지금
빌드에 들어간 파일이 소리 없이 바뀐다.

사용법:
    python design-system/scripts/build_premium_character_v6_growth.py

성장 시트가 아직 없으면 어떤 파일이 어디에 필요한지 알리고 실패한다. 조용히
건너뛰면 "돌렸는데 왜 그대로냐"가 된다.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_character_expansion_v7 import (
    FORMS,
    _build_growth_preview,
    _emotion_blend,
    _render_growth,
    _save_lossless_webp,
    _sha256,
    _split_growth_sheet,
)

CONCEPT_ROOT = Path("design-system/concepts/character-redesign-v6")
ALPHA_ROOT = CONCEPT_ROOT / "alpha"
QA_ROOT = CONCEPT_ROOT / "qa"
PLANT_ROOT = Path("app/assets/plants")

# 성장 시트에 담기는 네 칸. 만개는 이미 있는 원화를 쓴다.
SHEET_PHASES = ("seed", "sprout", "branching", "bloom")

CHARACTERS: dict[str, str] = {
    "nurse-pot": "백화",
    "maestro-pot": "세렌",
}


def _require_sheet(slug: str) -> Path:
    path = ALPHA_ROOT / f"{slug}-growth.png"
    if path.exists():
        return path
    raise SystemExit(
        f"성장 시트가 없습니다: {path}\n"
        f"  {CHARACTERS[slug]}의 씨앗·새싹·가지·개화 네 칸을 한 줄로 담은 투명 PNG가\n"
        f"  필요합니다. 프롬프트와 규격은 {CONCEPT_ROOT / 'README.md'}의\n"
        f"  `성장 시트 생성 규격` 절을 보세요."
    )


def _build(slug: str, name: str) -> dict[str, Any]:
    sheet_path = _require_sheet(slug)
    full_bloom_path = PLANT_ROOT / f"{slug}-25d-full-bloom.webp"
    if not full_bloom_path.exists():
        raise SystemExit(
            f"만개 원화가 없습니다: {full_bloom_path}\n"
            "  build_premium_character_v6.py 를 먼저 돌리세요."
        )

    sheet = Image.open(sheet_path).convert("RGBA")
    panels = _split_growth_sheet(sheet)
    if len(panels) != len(SHEET_PHASES):
        raise SystemExit(
            f"{sheet_path.name}에서 칸 {len(panels)}개를 찾았습니다. "
            f"{len(SHEET_PHASES)}개여야 합니다."
        )

    # 네 칸에 같은 배율을 먹인다. 칸마다 따로 맞추면 씨앗이 성인만큼 커져서
    # 자란다는 느낌이 사라진다. 시트 안의 상대 크기가 곧 성장 곡선이다.
    common_scale = min(
        448 / max(panel.width for panel in panels),
        704 / max(panel.height for panel in panels),
    )
    stages = {
        phase: _render_growth(panel, scale=common_scale)
        for phase, panel in zip(SHEET_PHASES, panels)
    }
    stages["full-bloom"] = Image.open(full_bloom_path).convert("RGBA")

    outputs: list[Path] = []
    for phase in SHEET_PHASES:
        canonical = PLANT_ROOT / f"{slug}-25d-{phase}.webp"
        _save_lossless_webp(stages[phase], canonical)
        outputs.append(canonical)

    # 씨앗은 결이 없다. 어떤 마음이 쌓일지 아직 아무것도 안 정해진 단계라
    # 여섯 벌을 만들어도 앱이 부르지 않는다.
    for phase in (*SHEET_PHASES[1:], "full-bloom"):
        for form, (primary, secondary) in FORMS.items():
            destination = PLANT_ROOT / f"{slug}-25d-{phase}-{form}.webp"
            _save_lossless_webp(
                _emotion_blend(stages[phase], primary, secondary), destination
            )
            outputs.append(destination)

    _build_growth_preview_into(slug, stages)
    return {
        "slug": slug,
        "name": name,
        "asset_count": len(outputs),
        "source_sha256": {
            sheet_path.name: _sha256(sheet_path),
            full_bloom_path.name: _sha256(full_bloom_path),
        },
        "runtime_sha256": {path.name: _sha256(path) for path in outputs},
    }


def _build_growth_preview_into(slug: str, stages: dict[str, Image.Image]) -> None:
    """v7과 같은 6결x5단계 검수 시트를 v6 콘셉트 폴더에 남긴다."""

    import build_character_expansion_v7 as v7

    previous = v7.QA_ROOT
    v7.QA_ROOT = QA_ROOT
    try:
        _build_growth_preview(slug, stages)
    finally:
        v7.QA_ROOT = previous


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report",
        type=Path,
        default=QA_ROOT / "premium-character-v6-growth.json",
        help="빌드 결과와 원본·산출물 해시를 남길 경로",
    )
    args = parser.parse_args()

    reports = [_build(slug, name) for slug, name in CHARACTERS.items()]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps({"characters": reports}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    total = sum(report["asset_count"] for report in reports)
    print(f"v6 성장 원화 {total}개를 빌드했습니다. 보고서: {args.report}")
    print(
        "app/test/plant_sprite_coverage_test.dart 의 knownGaps 에서 두 종을 지우세요."
    )


if __name__ == "__main__":
    main()
