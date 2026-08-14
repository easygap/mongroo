"""탐험 스테이지의 위협도와 적 기믹 단일 원본.

캐릭터 레벨에 맞춰 적 공격력을 몰래 올리지 않는다. 같은 스테이지는 언제 들어가도
같은 규칙을 사용하고, 후반 스테이지일수록 장벽과 패턴의 깊이가 늘어난다. 전투 시작
시 이 값을 상태에 스냅샷해 콘텐츠 패치 뒤에도 진행 중인 런을 그대로 재생한다.
"""

from __future__ import annotations

import copy
from collections.abc import Mapping
from types import MappingProxyType
from typing import Any


COMBAT_DIFFICULTY_VERSION = 1


# 배율은 모두 basis point다. `intent_power_bonus`는 파티 성장과 무관한 스테이지 고정
# 값이다. 지역 위력은 몬스터 카탈로그가 담당하므로 여기서는 스테이지 안의 학습
# 곡선만 표현한다.
STAGE_THREAT_PROFILES: Mapping[str, Mapping[str, Any]] = MappingProxyType(
    {
        "legacy": MappingProxyType(
            {
                "code": "legacy",
                "name": "기본 탐험",
                "tier": 0,
                "rank": "legacy",
                "recommended_level": 1,
                "barrier_bp": 10_000,
                "intent_power_bonus": 0,
                "mechanic_level": 0,
                "affix_slots": 0,
                "single_hit_cap_bp": 10_000,
                "pattern_depth": 1,
            }
        ),
        "stage_1": MappingProxyType(
            {
                "code": "stage_1",
                "name": "첫걸음",
                "tier": 1,
                "rank": "tutorial",
                "recommended_level": 3,
                "barrier_bp": 10_000,
                "intent_power_bonus": 0,
                "mechanic_level": 0,
                "affix_slots": 0,
                "single_hit_cap_bp": 6_700,
                "pattern_depth": 1,
            }
        ),
        "stage_3": MappingProxyType(
            {
                "code": "stage_3",
                "name": "표준",
                "tier": 2,
                "rank": "standard",
                "recommended_level": 5,
                "barrier_bp": 10_500,
                "intent_power_bonus": 0,
                "mechanic_level": 1,
                "affix_slots": 0,
                "single_hit_cap_bp": 6_700,
                "pattern_depth": 2,
            }
        ),
        "stage_2": MappingProxyType(
            {
                "code": "stage_2",
                "name": "기초 사건",
                "tier": 1,
                "rank": "story",
                "recommended_level": 4,
                "barrier_bp": 10_000,
                "intent_power_bonus": 0,
                "mechanic_level": 0,
                "affix_slots": 0,
                "single_hit_cap_bp": 6_700,
                "pattern_depth": 1,
            }
        ),
        "stage_4": MappingProxyType(
            {
                "code": "stage_4",
                "name": "큰 엉킴",
                "tier": 3,
                "rank": "elite",
                "recommended_level": 7,
                # 큰 엉킴은 기본 장벽 자체가 일반의 약 두 배다. 여기에 1.10배를
                # 다시 얹으면 후반 지역의 권장 레벨 하한에서 파훼 정책조차
                # 과도하게 탈락했다. 1.05배와 기믹 2단계로 난도를 만든다.
                "barrier_bp": 10_500,
                "intent_power_bonus": 0,
                "mechanic_level": 2,
                "affix_slots": 1,
                "single_hit_cap_bp": 6_700,
                "pattern_depth": 2,
            }
        ),
        "stage_5": MappingProxyType(
            {
                "code": "stage_5",
                "name": "쉼터",
                "tier": 3,
                "rank": "camp",
                "recommended_level": 7,
                "barrier_bp": 10_500,
                "intent_power_bonus": 0,
                "mechanic_level": 2,
                "affix_slots": 1,
                "single_hit_cap_bp": 6_700,
                "pattern_depth": 2,
            }
        ),
        "stage_6": MappingProxyType(
            {
                "code": "stage_6",
                "name": "심화 사건",
                "tier": 3,
                "rank": "story",
                "recommended_level": 8,
                "barrier_bp": 11_000,
                "intent_power_bonus": 0,
                "mechanic_level": 2,
                "affix_slots": 1,
                "single_hit_cap_bp": 6_700,
                "pattern_depth": 2,
            }
        ),
        "stage_7": MappingProxyType(
            {
                "code": "stage_7",
                "name": "숙련",
                "tier": 4,
                "rank": "mastery",
                "recommended_level": 9,
                "barrier_bp": 11_800,
                "intent_power_bonus": 0,
                "mechanic_level": 3,
                "affix_slots": 1,
                "single_hit_cap_bp": 6_700,
                "pattern_depth": 3,
            }
        ),
        "stage_8": MappingProxyType(
            {
                "code": "stage_8",
                "name": "수호짐승",
                "tier": 5,
                "rank": "boss",
                "recommended_level": 9,
                "barrier_bp": 12_000,
                "intent_power_bonus": 0,
                "mechanic_level": 3,
                "affix_slots": 1,
                "single_hit_cap_bp": 6_700,
                "pattern_depth": 3,
            }
        ),
        # 깊은 조사 — 지역을 완주한 사람만 들어온다. 첫 도전 승률 45~70%를
        # 노리는 유일한 난이도이고 **보상은 늘지 않는다**(9.2: 최초 기록서·서사만).
        #
        # 보스보다 장벽을 더 두껍게 하지 않는다. 장벽만 키우면 전투가 길어지기만
        # 하고 어려워지지는 않는다. 대신 **한 방 상한을 올려** 예고를 잘못 읽은
        # 대가가 실제로 아프게 만든다 — 실패가 숨은 확률이 아니라 읽고 감수한
        # 선택에서 나오게 하는 장치다.
        "deep": MappingProxyType(
            {
                "code": "deep",
                "name": "깊은 조사",
                "tier": 5,
                "rank": "deep",
                "recommended_level": 9,
                "barrier_bp": 11_500,
                "intent_power_bonus": 1,
                "mechanic_level": 3,
                "affix_slots": 1,
                "single_hit_cap_bp": 8_400,
                "pattern_depth": 3,
            }
        ),
    }
)


# 적 기믹은 공격 이름과 분리한다. 같은 판정 문법을 여러 적이 사용하더라도 이름과
# 설명은 각 서사에 맞춰 달라질 수 있고, 런타임은 trigger/effect만 해석한다.
ENEMY_MECHANICS: Mapping[str, Mapping[str, Any]] = MappingProxyType(
    {
        "focus_leak": MappingProxyType(
            {
                "code": "focus_leak",
                "name": "집중 누수",
                "trigger": "on_unblocked",
                "effect": "focus_drain",
                "value": 1,
                "counter": "피해를 모두 막으면 집중력이 줄지 않아요.",
            }
        ),
        "expose": MappingProxyType(
            {
                "code": "expose",
                "name": "빈틈 표식",
                "trigger": "on_unblocked",
                "effect": "expose",
                "value": 1,
                "counter": "피해를 모두 막으면 빈틈 표식이 남지 않아요.",
            }
        ),
        "weakness_check": MappingProxyType(
            {
                "code": "weakness_check",
                "name": "상성 압박",
                "trigger": "no_weakness_hit",
                "effect": "power_bonus",
                "value": 1,
                "counter": "이번 라운드에 약점을 한 번 맞히면 추가 위력이 사라져요.",
            }
        ),
        "guard_check": MappingProxyType(
            {
                "code": "guard_check",
                "name": "대열 압박",
                "trigger": "no_guard_action",
                "effect": "power_bonus",
                "value": 1,
                "counter": "한 명 이상 마음 지키기를 쓰면 추가 위력이 사라져요.",
            }
        ),
        "repairing_index": MappingProxyType(
            {
                "code": "repairing_index",
                "name": "살아 있는 색인",
                "trigger": "no_weakness_hit",
                "effect": "barrier_mend",
                "value": 2,
                "counter": "약점을 맞히면 색인이 장벽을 복구하지 못해요.",
            }
        ),
        "resonant_pressure": MappingProxyType(
            {
                "code": "resonant_pressure",
                "name": "공명 압력",
                "trigger": "no_guard_action",
                "effect": "power_bonus",
                "value": 1,
                "counter": "한 명 이상 마음 지키기로 울림을 받아 내세요.",
            }
        ),
        "reverse_winding": MappingProxyType(
            {
                "code": "reverse_winding",
                "name": "역감기 태엽",
                "trigger": "no_weakness_hit",
                "effect": "power_bonus",
                "value": 1,
                "counter": "약점을 맞히면 역감기 동력이 끊겨요.",
            }
        ),
        "double_exposure": MappingProxyType(
            {
                "code": "double_exposure",
                "name": "이중 노출",
                "trigger": "on_unblocked",
                "effect": "expose",
                "value": 1,
                "counter": "공격을 모두 막으면 겹친 초점이 표식을 남기지 못해요.",
            }
        ),
    }
)


def difficulty_profile_for_encounter(encounter: Mapping[str, Any]) -> dict[str, Any]:
    """encounter가 사용할 고정 위협 프로필을 독립 dict로 반환한다."""

    requested = encounter.get("difficulty_code")
    if isinstance(requested, str) and requested in STAGE_THREAT_PROFILES:
        code = requested
    elif encounter.get("boss_phases"):
        # 기존 자유 탐험의 보스도 신규 보스 규칙을 사용한다.
        code = "stage_8"
    else:
        code = "legacy"
    return copy.deepcopy(dict(STAGE_THREAT_PROFILES[code]))


def enemy_mechanic(
    code: str | None,
    *,
    unlock_level: int,
    mechanic_level: int,
) -> dict[str, Any] | None:
    """현재 위협도에서 열린 기믹만 클라이언트 계약으로 펼친다."""

    definition = ENEMY_MECHANICS.get(str(code)) if code else None
    if definition is None or mechanic_level < max(1, int(unlock_level)):
        return None
    return {
        **copy.deepcopy(dict(definition)),
        "unlock_level": max(1, int(unlock_level)),
    }


def validate_enemy_mechanic_code(code: Any) -> bool:
    return isinstance(code, str) and code in ENEMY_MECHANICS


def validate_threat_profiles() -> None:
    for code, profile in STAGE_THREAT_PROFILES.items():
        if profile["code"] != code:
            raise ValueError(f"difficulty profile code mismatch: {code}")
        if not 0 <= int(profile["tier"]) <= 5:
            raise ValueError(f"difficulty profile tier out of range: {code}")
        if not 10_000 <= int(profile["barrier_bp"]) <= 12_000:
            raise ValueError(f"difficulty barrier budget out of range: {code}")
        if not 0 <= int(profile["mechanic_level"]) <= 3:
            raise ValueError(f"difficulty mechanic level out of range: {code}")
        if not 6_000 <= int(profile["single_hit_cap_bp"]) <= 10_000:
            raise ValueError(f"difficulty hit cap out of range: {code}")


validate_threat_profiles()
