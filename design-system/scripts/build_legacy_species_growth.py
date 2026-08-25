#!/usr/bin/env python3
"""가시니와 해바라기의 다섯 단계를 낱장 원화에서 빌드한다.

이 둘은 초기부터 `plant_species`에 있었고 상점에 100씨앗으로 올라가 있는데
성장 원화가 **한 장도 없었다.** 사면 씨앗부터 만개까지 다섯 단계 내내 대체
그림을 봤다. 세렌·백화(v6)와 달리 만개조차 없어서 다섯 장을 전부 받는다.

`build_premium_character_v6_growth.py`와 같은 조립 방식을 쓰되 셋이 다르다.

* 만개까지 다섯 칸을 낱장으로 받는다. v6는 만개가 이미 있어서 네 칸만 받았다.
* 키 비율이 다르다. 사람형 계보(0.23·0.66·0.87·0.975)는 씨앗이 아주 작고
  성인이 캔버스를 꽉 채우는 곡선인데, 화분에 든 식물은 씨앗도 화분을 이고
  있어 그만큼 작아지지 않는다. 모루(동물형)에 가까운 완만한 곡선을 쓴다.
* 잎이 양옆으로 벌어져 폭이 먼저 차는 칸이 있다. 그때는 폭 한계가 키를
  결정하므로 목표 높이에 못 미친다. 단조 증가만 지키면 성장은 읽힌다.

사용법:
    python design-system/scripts/build_legacy_species_growth.py
"""

from __future__ import annotations

import argparse
import itertools
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_character_expansion_v7 import (
    FORMS,
    _emotion_blend,
    _render_growth,
    _save_lossless_webp,
    _sha256,
    _visible_bbox,
)
from build_premium_character_v6_growth import _gate_stipple

CONCEPT_ROOT = Path("design-system/concepts/legacy-species-growth-v1")
ALPHA_ROOT = CONCEPT_ROOT / "alpha"
QA_ROOT = CONCEPT_ROOT / "qa"
PLANT_ROOT = Path("app/assets/plants")

PHASES = ("seed", "sprout", "branching", "bloom", "full-bloom")

#: 512x768 캔버스에서 각 단계가 차지할 목표 높이.
#:
#: 사람형 비율을 그대로 쓰면 새싹이 개화보다 커 보인다 - 개화·만개는 잎과
#: 곁가지가 폭을 먼저 채워서 목표 높이까지 커지지 못하기 때문이다. 폭에
#: 걸리는 칸까지 감안해 **실제로 단조 증가하는** 값으로 잡았다.
TARGET_HEIGHT = {
    "seed": 300,
    "sprout": 380,
    "branching": 460,
    "bloom": 530,
    "full-bloom": 620,
}

#: `_render_growth`가 허용하는 최대 폭. 잎이 벌어진 칸은 여기서 막힌다.
MAX_WIDTH = 468

SPECIES: dict[str, str] = {
    "cactus": "가시니",
    "sunflower": "해바라기",
}


def _panels(slug: str) -> tuple[dict[str, Image.Image], list[Path]]:
    paths = [ALPHA_ROOT / f"{slug}-{phase}.png" for phase in PHASES]
    missing = [path for path in paths if not path.exists()]
    if missing:
        names = "\n    ".join(path.name for path in missing)
        raise SystemExit(
            f"{SPECIES[slug]}의 성장 원화가 모자랍니다. 없는 파일:\n    {names}\n"
            f"  전부 {ALPHA_ROOT}/ 에 투명 PNG로 넣어 주세요.\n"
            f"  프롬프트와 규격은 {CONCEPT_ROOT / 'README.md'} 를 보세요."
        )
    panels = {}
    for phase, path in zip(PHASES, paths):
        image = Image.open(path).convert("RGBA")
        panels[phase] = image.crop(_visible_bbox(image))
    return panels, paths


def _build(slug: str, name: str) -> dict[str, Any]:
    panels, sources = _panels(slug)
    stipple = {
        path.name: _gate_stipple(path.name, Image.open(path).convert("RGBA"))
        for path in sources
    }

    stages: dict[str, Image.Image] = {}
    rendered: dict[str, int] = {}
    for phase in PHASES:
        panel = panels[phase]
        scale = min(TARGET_HEIGHT[phase] / panel.height, MAX_WIDTH / panel.width)
        stages[phase] = _render_growth(panel, scale=scale)
        rendered[phase] = round(panel.height * scale)

    # 자란다는 것이 눈에 보여야 한다. 폭에 걸려 목표를 못 채우는 칸이 있어도
    # 순서만은 지켜져야 하므로 여기서 막는다.
    heights = [rendered[phase] for phase in PHASES]
    if any(later <= earlier for earlier, later in itertools.pairwise(heights)):
        pairs = ", ".join(f"{p}={h}" for p, h in zip(PHASES, heights))
        raise SystemExit(
            f"{name}의 단계 키가 커지지 않습니다: {pairs}\n"
            "  잎이나 곁가지가 폭을 먼저 채우는 칸이 있습니다. 그 칸의 원화에서\n"
            "  옆으로 벌어진 부분을 줄이거나 TARGET_HEIGHT를 조정하세요."
        )

    outputs: list[Path] = []
    for phase in PHASES:
        canonical = PLANT_ROOT / f"{slug}-25d-{phase}.webp"
        _save_lossless_webp(stages[phase], canonical)
        outputs.append(canonical)

    # 씨앗에는 결이 없다. 아직 어떤 마음도 쌓이지 않은 단계라 앱이 부르지 않는다.
    for phase in PHASES[1:]:
        for form, (primary, secondary) in FORMS.items():
            destination = PLANT_ROOT / f"{slug}-25d-{phase}-{form}.webp"
            _save_lossless_webp(
                _emotion_blend(stages[phase], primary, secondary), destination
            )
            outputs.append(destination)

    _preview(slug, stages)
    return {
        "slug": slug,
        "name": name,
        "asset_count": len(outputs),
        "rendered_height": rendered,
        "stipple": stipple,
        "source_sha256": {path.name: _sha256(path) for path in sources},
        "runtime_sha256": {path.name: _sha256(path) for path in outputs},
    }


def _preview(slug: str, stages: dict[str, Image.Image]) -> None:
    """6결x5단계 검수 시트. 캔버스를 통째로 같은 배율로 줄여 상대 크기를 남긴다."""

    from PIL import ImageDraw, ImageFont

    scale = 0.30
    cell = (round(512 * scale), round(768 * scale))
    sheet = Image.new("RGB", (cell[0] * 5 + 90, cell[1] * len(FORMS) + 40), "#FFF8EA")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=15)
    for row, form in enumerate(FORMS):
        draw.text(
            (10, 34 + row * cell[1] + cell[1] // 2),
            form.upper(),
            fill="#654C3A",
            font=font,
        )
        for column, phase in enumerate(PHASES):
            image = (
                stages[phase]
                if phase == "seed"
                else _emotion_blend(stages[phase], *FORMS[form])
            )
            sheet.paste(
                image.resize(cell, Image.Resampling.LANCZOS),
                (86 + column * cell[0], 34 + row * cell[1]),
                image.resize(cell, Image.Resampling.LANCZOS),
            )
    for column, phase in enumerate(PHASES):
        draw.text((90 + column * cell[0], 10), phase.upper(), fill="#654C3A", font=font)
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    sheet.save(QA_ROOT / f"{slug}-growth-preview.webp", "WEBP", quality=92, method=6)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report",
        type=Path,
        default=QA_ROOT / "legacy-species-growth.json",
        help="빌드 결과와 원본·산출물 해시를 남길 경로",
    )
    args = parser.parse_args()

    reports = [_build(slug, name) for slug, name in SPECIES.items()]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps({"species": reports}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    total = sum(report["asset_count"] for report in reports)
    print(f"성장 원화 {total}개를 빌드했습니다. 보고서: {args.report}")
    for report in reports:
        heights = " ".join(f"{k}={v}" for k, v in report["rendered_height"].items())
        print(f"  {report['name']}: {heights}")
    print(
        "app/test/plant_sprite_coverage_test.dart 의 knownGaps 에서 두 종을 지우세요."
    )


if __name__ == "__main__":
    main()
