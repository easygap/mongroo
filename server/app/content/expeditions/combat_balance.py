"""탐험 전투의 성장·지역 난이도 단일 원본.

피해 계수는 ``combat_identity.py``, 실제 라운드 판정은 ``combat.py``가 맡는다.
이 모듈은 레벨 이정표와 지역별 허용 밴드를 분리해 카탈로그 수치가 문서에서
조용히 벗어나지 않게 한다. 적 위력은 성장 레벨을 읽지 않는다.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from types import MappingProxyType
from typing import Any


COMBAT_BALANCE_VERSION = 3
STARTING_FOCUS_LEVEL = 18

# 레벨 1~9 / 10~18 / 19~26 / 27~30의 수호전 HP 이정표다.
COMBAT_HP_THRESHOLDS: tuple[tuple[int, int], ...] = (
    (1, 3),
    (10, 4),
    (19, 5),
    (27, 6),
)

# 각 지역의 카탈로그 수치 허용 범위다. 실제 엉킴 값은 이 범위 안의 정수이며,
# 성장지수 장벽 배수는 전투 시작 시 별도로 snapshot된다.
REGION_COMBAT_BANDS: Mapping[str, Mapping[str, tuple[int, int]]] = (
    MappingProxyType(
        {
            "moss_archive": MappingProxyType(
                {
                    "normal_barrier": (34, 38),
                    "elite_barrier": (70, 76),
                    "normal_intent": (1, 1),
                    "elite_intent": (1, 2),
                    "recommended_level": (3, 9),
                }
            ),
            "echo_well": MappingProxyType(
                {
                    "normal_barrier": (44, 50),
                    "elite_barrier": (88, 96),
                    "normal_intent": (1, 2),
                    "elite_intent": (2, 2),
                    "recommended_level": (9, 16),
                }
            ),
            "starlight_seed_vault": MappingProxyType(
                {
                    "normal_barrier": (56, 64),
                    "elite_barrier": (110, 120),
                    "normal_intent": (2, 2),
                    "elite_intent": (2, 3),
                    "recommended_level": (16, 25),
                }
            ),
            "heartwood_observatory": MappingProxyType(
                {
                    "normal_barrier": (70, 80),
                    "elite_barrier": (136, 148),
                    "normal_intent": (2, 3),
                    "elite_intent": (3, 3),
                    "recommended_level": (25, 30),
                }
            ),
        }
    )
)


def combat_level_from_snapshot(snapshot: Mapping[str, Any]) -> int:
    """저장 스냅샷을 1~30 전투 레벨로 복원한다."""

    if "level" in snapshot:
        return max(1, min(30, int(snapshot["level"])))
    # level이 없던 저장 run은 당시 열린 슬롯을 잃지 않도록 stage 하한으로 복원한다.
    # stage도 없는 초기 가이드·단위 fixture는 전 슬롯 호환 레벨을 유지한다.
    stage = snapshot.get("stage")
    if stage is None:
        return 25
    return {1: 1, 2: 3, 3: 9, 4: 16, 5: 25}.get(int(stage), 1)


def combat_hp_for_level(level: int) -> int:
    """레벨 이정표에 대응하는 수호전 최대 HP를 돌려준다."""

    safe_level = max(1, min(30, int(level)))
    hp = COMBAT_HP_THRESHOLDS[0][1]
    for threshold, value in COMBAT_HP_THRESHOLDS:
        if safe_level < threshold:
            break
        hp = value
    return hp


def owned_party_levels(profiles: Sequence[Mapping[str, Any]]) -> list[int]:
    """길잡이를 제외한 실소유 대원의 전투 레벨을 보존 순서로 반환한다."""

    levels = [
        combat_level_from_snapshot(profile.get("snapshot", {}))
        for profile in profiles
        if not bool(profile.get("is_guide"))
    ]
    return levels or [1]


def rounded_average_level(levels: Sequence[int]) -> int:
    """0.5를 위로 올리는 정수 평균으로 UI snapshot을 만든다."""

    if not levels:
        return 1
    return (sum(int(level) for level in levels) + len(levels) // 2) // len(levels)


def starting_focus_for_party(
    profiles: Sequence[Mapping[str, Any]],
    *,
    configured_focus: int,
    max_focus: int,
) -> tuple[int, bool, int]:
    """평균 Lv18 이정표를 표준 시작 집중력 3에만 한 번 적용한다.

    커스텀 encounter와 기록서가 이미 바꾼 0~2 또는 4~5 값에는 중복 보너스를
    얹지 않는다. 반환값은 ``(최종 집중력, 레벨 보너스 적용 여부, 평균 레벨)``이다.
    """

    levels = owned_party_levels(profiles)
    average_level = rounded_average_level(levels)
    level_bonus = (
        int(configured_focus) == 3
        and sum(levels) >= STARTING_FOCUS_LEVEL * len(levels)
    )
    focus = int(configured_focus) + int(level_bonus)
    return max(0, min(int(max_focus), focus)), level_bonus, average_level


def growth_index_for_party(profiles: Sequence[Mapping[str, Any]]) -> int:
    """실소유 대원 평균 레벨을 0~100 성장지수로 반올림한다."""

    levels = owned_party_levels(profiles)
    numerator = sum((level - 1) * 100 for level in levels)
    denominator = 29 * len(levels)
    return max(0, min(100, (numerator + denominator // 2) // denominator))


def validate_tangle_balance(catalog: Mapping[str, Mapping[str, Any]]) -> list[str]:
    """엉킴 장벽·의도 위력이 지역/난이도 밴드 안인지 검증한다."""

    errors: list[str] = []
    represented_regions: set[str] = set()
    for code, tangle in catalog.items():
        region_code = str(tangle.get("region_code", ""))
        band = REGION_COMBAT_BANDS.get(region_code)
        if band is None:
            errors.append(f"tangles.{code}: 알 수 없는 전투 지역 {region_code}")
            continue
        represented_regions.add(region_code)
        difficulty = "elite" if bool(tangle.get("elite")) else "normal"
        barrier = int(tangle.get("barrier", 0))
        barrier_low, barrier_high = band[f"{difficulty}_barrier"]
        if not barrier_low <= barrier <= barrier_high:
            errors.append(
                f"tangles.{code}.barrier: {region_code} {difficulty} "
                f"밴드 {barrier_low}~{barrier_high}를 벗어났습니다"
            )
        intent_low, intent_high = band[f"{difficulty}_intent"]
        for intent in tangle.get("intents") or []:
            power = int(intent.get("power", 0))
            if not intent_low <= power <= intent_high:
                errors.append(
                    f"tangles.{code}.{intent.get('code', 'intent')}.power: "
                    f"{region_code} {difficulty} 밴드 {intent_low}~{intent_high}를 "
                    "벗어났습니다"
                )
    if represented_regions != set(REGION_COMBAT_BANDS):
        errors.append("tangles.balance: 네 지역 전투 밴드를 모두 대표해야 합니다")
    return errors
