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

import numpy as np
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
    _visible_bbox,
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


#: 점묘 관문. `import_expedition_walker.py`와 같은 척도를 쓰되 한계는 다르다 -
#: 그쪽은 24색 도트 아틀라스(0.16)에 맞춘 값이고, 여기는 붓질이 남는 캐릭터
#: 원화다. 승인된 원화 다섯 장의 실측이 고주파 0.036~0.050, 튀는 점
#: 0.0001~0.0003이라 여유를 두고 잡았다. 생성물이 자글거리면 눈으로 다투지
#: 않고 여기서 막는다.
HIGH_FREQUENCY_LIMIT = 0.075
SPECK_LIMIT = 0.0010


def _measure_stipple(image: Image.Image) -> dict[str, float]:
    """자글거림과 튀는 점을 잰다.

    `import_expedition_walker.measure`와 같은 정의를 numpy로 옮긴 것이다.
    거기 구현은 픽셀을 하나씩 도는데 96x480 시트를 재려고 만든 것이라,
    1700x900 원화에 그대로 쓰면 너무 느리다. 두 구현이 같은 값을 내는 것은
    작은 이미지로 대조해 확인했다.
    """

    array = np.asarray(image.convert("RGBA"), dtype=np.float64)
    rgb, alpha = array[..., :3], array[..., 3]
    luma = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
    solid = alpha >= 224

    # 맞닿은 두 불투명 픽셀의 밝기 차. 같은 면인데 자주 튀면 점묘다.
    pair_h = solid[:, :-1] & solid[:, 1:]
    pair_v = solid[:-1, :] & solid[1:, :]
    edges = int(pair_h.sum() + pair_v.sum())
    high = int(
        ((np.abs(luma[:, :-1] - luma[:, 1:]) >= 36) & pair_h).sum()
        + ((np.abs(luma[:-1, :] - luma[1:, :]) >= 36) & pair_v).sum()
    )

    # 사방이 고른데 혼자 튀는 픽셀.
    center = (
        solid[1:-1, 1:-1]
        & solid[1:-1, :-2]
        & solid[1:-1, 2:]
        & solid[:-2, 1:-1]
        & solid[2:, 1:-1]
    )
    around = np.stack(
        (luma[1:-1, :-2], luma[1:-1, 2:], luma[:-2, 1:-1], luma[2:, 1:-1])
    )
    isolated = int(
        (
            (around.max(0) - around.min(0) <= 14)
            & (np.abs(luma[1:-1, 1:-1] - around.mean(0)) >= 30)
            & center
        ).sum()
    )
    return {
        "high_frequency": high / max(1, edges),
        "speck": isolated / max(1, int(center.sum())),
    }


def _gate_stipple(label: str, image: Image.Image) -> dict[str, float]:
    metrics = _measure_stipple(image)
    problems = []
    if metrics["high_frequency"] > HIGH_FREQUENCY_LIMIT:
        problems.append(
            f"자글거림 {metrics['high_frequency']:.3f} > {HIGH_FREQUENCY_LIMIT}"
        )
    if metrics["speck"] > SPECK_LIMIT:
        problems.append(f"튀는 점 {metrics['speck']:.4f} > {SPECK_LIMIT}")
    if problems:
        raise SystemExit(
            f"{label}에 점묘가 섞여 있습니다: {', '.join(problems)}\n"
            "  승인된 원화 실측은 고주파 0.036~0.050, 튀는 점 0.0001~0.0003입니다.\n"
            "  README의 프롬프트에 있는 점묘 금지 블록을 넣고 다시 생성하세요."
        )
    return metrics


def _panel_sources(slug: str) -> tuple[list[Image.Image], list[Path], bool]:
    """네 칸을 읽는다. 한 장짜리 시트와 낱장 넷을 모두 받는다.

    낱장을 먼저 본다. 네 나이를 한 번에 요구하면 칸마다 얼굴이 흔들려서,
    한 칸씩 만들고 나쁜 칸만 다시 굽는 편이 낫다. 걷기 시트에서도 방향마다
    한 장씩 받는 쪽이 나았던 것과 같은 이유다.

    세 번째 값은 `낱장인가`다. 낱장은 파일마다 따로 프레이밍돼서 칸 사이의
    상대 키가 사라지므로 뒤에서 키를 따로 잡아 줘야 한다.
    """

    singles = [ALPHA_ROOT / f"{slug}-{phase}.png" for phase in SHEET_PHASES]
    if all(path.exists() for path in singles):
        panels = []
        for path in singles:
            image = Image.open(path).convert("RGBA")
            panels.append(image.crop(_visible_bbox(image)))
        return panels, singles, True

    sheet_path = ALPHA_ROOT / f"{slug}-growth.png"
    if sheet_path.exists():
        sheet = Image.open(sheet_path).convert("RGBA")
        panels = _split_growth_sheet(sheet)
        if len(panels) != len(SHEET_PHASES):
            raise SystemExit(
                f"{sheet_path.name}에서 칸 {len(panels)}개를 찾았습니다. "
                f"{len(SHEET_PHASES)}개여야 합니다. 칸 사이를 더 벌려 주세요."
            )
        return panels, [sheet_path], False

    missing = "\n    ".join(path.name for path in singles)
    raise SystemExit(
        f"{CHARACTERS[slug]}의 성장 원화가 없습니다. 둘 중 하나를 넣으세요.\n"
        f"  낱장 넷 (권장): {ALPHA_ROOT}/\n    {missing}\n"
        f"  또는 네 칸 시트 한 장: {sheet_path}\n"
        f"  프롬프트와 규격은 {CONCEPT_ROOT / 'README.md'}의"
        " `성장 시트 생성 규격` 절을 보세요."
    )


#: 만개 키를 1로 둔 단계별 키 비율. 사람형 계보 둘의 실측 평균이다 -
#: 리아 0.245·0.687·0.876·0.976, 에단 0.210·0.634·0.864·0.974. 모루는
#: 동물형이라 곡선이 달라서(씨앗 0.511) 넣지 않았다.
#:
#: 낱장으로 받을 때만 쓴다. 시트 한 장에는 칸 사이의 상대 키가 이미 들어
#: 있지만, 낱장은 파일마다 인물이 캔버스를 채우도록 그려져서 그 정보가
#: 없다. 그대로 같은 배율을 먹이면 씨앗이 성인만 해진다.
PHASE_HEIGHT_RATIO = {
    "seed": 0.23,
    "sprout": 0.66,
    "branching": 0.87,
    "bloom": 0.975,
}


def _visible_height(image: Image.Image) -> int:
    box = _visible_bbox(image)
    return box[3] - box[1]


def _render_singles(
    panels: list[Image.Image], full_bloom: Image.Image
) -> dict[str, Image.Image]:
    """낱장 넷을 만개 키에 맞춰 앉힌다."""

    target_full = _visible_height(full_bloom)
    stages: dict[str, Image.Image] = {}
    for phase, panel in zip(SHEET_PHASES, panels):
        target = target_full * PHASE_HEIGHT_RATIO[phase]
        scale = min(target / panel.height, 448 / panel.width)
        stages[phase] = _render_growth(panel, scale=scale)
    return stages


def _build(slug: str, name: str) -> dict[str, Any]:
    panels, sources, singles = _panel_sources(slug)
    full_bloom_path = PLANT_ROOT / f"{slug}-25d-full-bloom.webp"
    if not full_bloom_path.exists():
        raise SystemExit(
            f"만개 원화가 없습니다: {full_bloom_path}\n"
            "  build_premium_character_v6.py 를 먼저 돌리세요."
        )

    stipple = {
        path.name: _gate_stipple(path.name, Image.open(path).convert("RGBA"))
        for path in sources
    }

    full_bloom = Image.open(full_bloom_path).convert("RGBA")
    if singles:
        stages = _render_singles(panels, full_bloom)
    else:
        # 시트는 네 칸에 같은 배율을 먹인다. 칸마다 따로 맞추면 씨앗이 성인만큼
        # 커져서 자란다는 느낌이 사라진다. 시트 안의 상대 크기가 곧 성장 곡선이다.
        common_scale = min(
            448 / max(panel.width for panel in panels),
            704 / max(panel.height for panel in panels),
        )
        stages = {
            phase: _render_growth(panel, scale=common_scale)
            for phase, panel in zip(SHEET_PHASES, panels)
        }
    stages["full-bloom"] = full_bloom

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
        "stipple": stipple,
        "source_sha256": {
            **{path.name: _sha256(path) for path in sources},
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
