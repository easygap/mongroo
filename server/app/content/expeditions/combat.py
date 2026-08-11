"""탐험 수호전의 결정론적 전투 규칙.

HTTP와 데이터베이스에 의존하지 않는다. 클라이언트가 보낸 행동 순서를 그대로
계산하고, 같은 전투 상태와 명령에는 항상 같은 결과를 돌려준다. 전투 밸런스와
표시용 수치는 이 파일에서 함께 관리해 서버 판정과 UI 설명이 어긋나지 않게 한다.
"""

from __future__ import annotations

import copy
from typing import Any

from app.content.expeditions.combat_balance import (
    COMBAT_BALANCE_VERSION,
    combat_hp_for_level,
    combat_level_from_snapshot,
    growth_index_for_party,
    starting_focus_for_party,
)
from app.content.expeditions.combat_identity import (
    CORE_AFFINITIES as IDENTITY_AFFINITIES,
    CORE_AFFINITY_LABELS as IDENTITY_AFFINITY_LABELS,
    CURRENT_KEL_MAP_VERSION,
    DAMAGE_TYPE_LABELS,
    EFFECT_POWER_BP,
    ELEMENT_LABELS,
    ELEMENT_RUNTIME_EFFECTS,
    EMOTION_DISCIPLINES,
    FUSION_LAYER_PROFILES,
    FIELD_NOTE_SKILL as IDENTITY_FIELD_NOTE_SKILL,
    FORM_COMBAT_SKILLS as IDENTITY_FORM_COMBAT_SKILLS,
    INITIAL_KEL_MAP_VERSION,
    KEL_LABELS,
    MATCHUP_POWER_BP,
    SPECIES_SECONDARY_SKILLS as IDENTITY_SPECIES_SECONDARY_SKILLS,
    SPECIES_SKILLS as IDENTITY_SPECIES_SKILLS,
    TANGLE_ELEMENT_MATCHUPS,
    TIER_POWER_BP,
    basic_scale_bp,
    combat_tier,
    element_kel_map,
    rarity_scale_bp,
    scaled_power,
)
from app.content.expeditions.combat_motion import (
    combat_motion,
    kel_fallback_family,
    present_intent,
)
from app.content.expeditions.tangles import tangle_definition


# 캐릭터, 감정 성장, 레벨/희귀도 계수의 단일 원본은 combat_identity.py다.
AFFINITIES = IDENTITY_AFFINITIES
AFFINITY_LABELS = IDENTITY_AFFINITY_LABELS
SPECIES_SKILLS = IDENTITY_SPECIES_SKILLS
SPECIES_SECONDARY_SKILLS = IDENTITY_SPECIES_SECONDARY_SKILLS
FORM_COMBAT_SKILLS = IDENTITY_FORM_COMBAT_SKILLS
FIELD_NOTE_SKILL = IDENTITY_FIELD_NOTE_SKILL


class CombatRuleError(ValueError):
    """클라이언트가 복구 가능한 전투 명령 오류."""

    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def _battle_kel_map_version(state: dict[str, Any]) -> int:
    raw_version = state.get("kel_map_version", INITIAL_KEL_MAP_VERSION)
    try:
        version = int(raw_version)
        element_kel_map(version)
    except (TypeError, ValueError) as error:
        raise CombatRuleError(
            "EXPEDITION_COMBAT_KEL_MAP_UNSUPPORTED",
            "저장된 전투 규칙 버전을 불러올 수 없어요. 다시 시도해 주세요.",
        ) from error
    return version


def _stats(profile: dict[str, Any]) -> dict[str, int]:
    raw = profile.get("snapshot", {}).get("stats", {})
    return {key: int(raw.get(key, 0)) for key in AFFINITIES}


def _member_affinity(profile: dict[str, Any]) -> str:
    form = profile.get("snapshot", {}).get("form", "mosaic")
    if form in EMOTION_DISCIPLINES:
        return str(EMOTION_DISCIPLINES[form]["affinity"])
    stats = _stats(profile)
    # 동률일 때도 서버 버전이나 dict 순서에 영향받지 않도록 고정 순서를 쓴다.
    return max(AFFINITIES, key=lambda key: (stats[key], -AFFINITIES.index(key)))


def _kel_matchup(
    kels: list[str],
    *,
    weak_kel: str | None,
    resist_kel: str | None,
) -> str:
    """다중 결은 약점 우선, 그다음 내성, 나머지는 중립으로 판정한다."""

    if weak_kel and weak_kel in kels:
        return "weak"
    if resist_kel and resist_kel in kels:
        return "resist"
    return "neutral"


def member_battle_kit(
    profile: dict[str, Any],
    *,
    current_weakness: str | None = None,
    current_weak_element: str | None = None,
    current_resist_element: str | None = None,
    kel_map_version: int = CURRENT_KEL_MAP_VERSION,
    member_state: dict[str, Any] | None = None,
    round_number: int = 1,
) -> dict[str, Any]:
    element_kels = element_kel_map(kel_map_version)
    snapshot = profile.get("snapshot", {})
    species_code = snapshot.get("species", {}).get("code", "archive_guide")
    form = snapshot.get("form", "mosaic")
    discipline = EMOTION_DISCIPLINES.get(form, EMOTION_DISCIPLINES["mosaic"])
    affinity = _member_affinity(profile)
    stats = _stats(profile)
    level = combat_level_from_snapshot(snapshot)
    rarity = max(1, min(5, int(snapshot.get("rarity", 1))))
    tier = combat_tier(level)
    signature_scale = rarity_scale_bp(level, rarity)
    basic_scale = basic_scale_bp(level, rarity)
    weak_kel = element_kels.get(str(current_weak_element))
    resist_kel = element_kels.get(str(current_resist_element))
    state_cooldowns = member_state or {}
    cooldowns = state_cooldowns.get("ready_round") or state_cooldowns.get(
        "cooldown_until_round", {}
    )

    def cooldown_remaining(code: str) -> int:
        return max(0, int(cooldowns.get(code, 0)) - int(round_number))

    def resolve_skill(
        definition: dict[str, Any],
        *,
        slot: str,
        source: str,
        unlock_level: int,
    ) -> dict[str, Any]:
        skill = dict(definition)
        skill_affinity = (
            current_weakness
            if skill["effect"] == "prism_shift" and current_weakness in AFFINITIES
            else affinity
        )
        element = str(skill["element"])
        prism_shifted = skill["effect"] == "prism_shift" and weak_kel is not None
        skill_kel = str(weak_kel) if prism_shifted else element_kels[element]
        kels = [skill_kel]
        elements = [element]
        secondary_element = skill.get("secondary_element")
        if secondary_element is not None:
            secondary_element = str(secondary_element)
            if secondary_element not in elements:
                elements.append(secondary_element)
            secondary_kel = element_kels[secondary_element]
            if secondary_kel not in kels:
                kels.append(secondary_kel)
        fusion_profile: dict[str, str] | None = None
        fusion_variant: str | None = None
        if source == "signature" and tier >= 3:
            emotion_element = str(discipline["primary_element"])
            if emotion_element not in elements:
                elements.append(emotion_element)
            emotion_kel = element_kels[emotion_element]
            if emotion_kel not in kels:
                kels.append(emotion_kel)
            fusion_profile = FUSION_LAYER_PROFILES[form]
            fusion_variant = f"{species_code}.{form}.{slot}.t3"
        matchup = _kel_matchup(kels, weak_kel=weak_kel, resist_kel=resist_kel)
        matchup_key = "prism_weak" if prism_shifted and matchup == "weak" else matchup
        matchup_bp = MATCHUP_POWER_BP[matchup_key]
        cooldown_turns = int(skill["cooldown_turns"])
        if source == "signature" and tier >= 3 and cooldown_turns > 0:
            cooldown_turns = max(1, cooldown_turns - 1)
        raw_power = int(skill["power"]) + stats[skill_affinity]
        power_scale = signature_scale if source == "signature" else 10_000
        tier_power_bp = TIER_POWER_BP[tier]
        growth_power = scaled_power(raw_power, power_scale)
        neutral_power = scaled_power(growth_power, tier_power_bp)
        matched_power = scaled_power(neutral_power, matchup_bp)
        effect_bp = 10_000
        if skill["effect"] == "weakness_pierce" and matchup == "weak":
            effect_bp = EFFECT_POWER_BP["weakness_pierce"]
        elif skill["effect"] == "steady_read" and matchup != "weak":
            effect_bp = EFFECT_POWER_BP["steady_read"]
        elif (
            skill["effect"] == "last_stand"
            and int((member_state or {}).get("hp", 0)) == 1
        ):
            effect_bp = EFFECT_POWER_BP["last_stand"]
        ready_round = int(cooldowns.get(str(skill["code"]), 0))
        return {
            **skill,
            "slot": slot,
            "source": source,
            "available": level >= unlock_level,
            "unlock_level": unlock_level,
            "tier": tier,
            "tier_label": skill["tier_names"][tier - 1],
            "level": level,
            "rarity": rarity,
            "raw_power": raw_power,
            "power_scale_bp": power_scale,
            "tier_power_bp": tier_power_bp,
            "power_neutral": neutral_power,
            "matchup": matchup,
            "matchup_bp": matchup_bp,
            "effect_power_bp": effect_bp,
            "power": scaled_power(matched_power, effect_bp),
            "affinity": skill_affinity,
            "affinity_label": AFFINITY_LABELS[skill_affinity],
            "element": element,
            "element_label": ELEMENT_LABELS[element],
            "elements": elements,
            "kel": skill_kel,
            "kel_label": KEL_LABELS[skill_kel],
            "kels": kels,
            "kel_labels": [KEL_LABELS[item] for item in kels],
            "fusion_variant": fusion_variant,
            "fusion_vfx_family": (
                fusion_profile["vfx_family"] if fusion_profile is not None else None
            ),
            "fusion_contact_material": (
                fusion_profile["contact_material"]
                if fusion_profile is not None
                else None
            ),
            "fusion_production_ready": False if fusion_profile is not None else None,
            "prism_shifted": prism_shifted,
            "damage_type_label": DAMAGE_TYPE_LABELS[skill["damage_type"]],
            "effect_key": ELEMENT_RUNTIME_EFFECTS[element],
            "kel_fallback_family": kel_fallback_family(skill_kel),
            "motion": combat_motion(
                str(skill["motion_profile"]),
                ultimate=slot == "unique_2",
            ),
            "cooldown_turns": cooldown_turns,
            "cooldown_remaining": cooldown_remaining(str(skill["code"])),
            "ready_round": ready_round,
            # v5 앱·저장 run 호환 alias. 신규 코드는 ready_round를 권위로 쓴다.
            "cooldown_until_round": ready_round,
        }

    unique_1 = resolve_skill(
        SPECIES_SKILLS.get(species_code, SPECIES_SKILLS["archive_guide"]),
        slot="unique_1",
        source="signature",
        unlock_level=3,
    )
    unique_2 = resolve_skill(
        SPECIES_SECONDARY_SKILLS.get(
            species_code, SPECIES_SECONDARY_SKILLS["archive_guide"]
        ),
        slot="unique_2",
        source="signature",
        unlock_level=3,
    )
    selected_1 = resolve_skill(
        FORM_COMBAT_SKILLS.get(form, FORM_COMBAT_SKILLS["mosaic"]),
        slot="selected_1",
        source="emotion",
        unlock_level=9,
    )
    selected_2 = resolve_skill(
        FIELD_NOTE_SKILL,
        slot="selected_2",
        source="skillbook",
        unlock_level=23,
    )
    basic_element = str(discipline["primary_element"])
    basic_raw_power = 10 + stats[affinity] // 2
    basic_kel = element_kels[basic_element]
    basic_matchup = _kel_matchup([basic_kel], weak_kel=weak_kel, resist_kel=resist_kel)
    basic_neutral_power = scaled_power(
        scaled_power(basic_raw_power, basic_scale), TIER_POWER_BP[tier]
    )
    return {
        "version": 6,
        "kel_map_version": int(kel_map_version),
        "level": level,
        "rarity": rarity,
        "signature_tier": tier,
        "signature_scale_bp": signature_scale,
        "basic_scale_bp": basic_scale,
        "tier_power_bp": TIER_POWER_BP[tier],
        "affinity": affinity,
        "affinity_label": AFFINITY_LABELS[affinity],
        "emotion_discipline": discipline["name"],
        "primary_element": basic_element,
        "primary_element_label": ELEMENT_LABELS[basic_element],
        "secondary_element": discipline["secondary_element"],
        "secondary_element_label": ELEMENT_LABELS[discipline["secondary_element"]],
        "basic": {
            "code": "attack",
            "name": f"{ELEMENT_LABELS[basic_element]} 공명 공격",
            "description": "집중력 1을 얻고 현재 감정 속성으로 장벽을 공격해요.",
            "available": True,
            "tier": tier,
            "tier_label": f"감정 공명 {tier}단계",
            "level": level,
            "rarity": rarity,
            "raw_power": basic_raw_power,
            "power_scale_bp": basic_scale,
            "tier_power_bp": TIER_POWER_BP[tier],
            "power_neutral": basic_neutral_power,
            "matchup": basic_matchup,
            "matchup_bp": MATCHUP_POWER_BP[basic_matchup],
            "effect_power_bp": 10_000,
            "power": scaled_power(basic_neutral_power, MATCHUP_POWER_BP[basic_matchup]),
            "focus_delta": 1,
            "affinity": affinity,
            "affinity_label": AFFINITY_LABELS[affinity],
            "element": basic_element,
            "element_label": ELEMENT_LABELS[basic_element],
            "elements": [basic_element],
            "kel": basic_kel,
            "kel_label": KEL_LABELS[basic_kel],
            "kels": [basic_kel],
            "kel_labels": [KEL_LABELS[basic_kel]],
            "damage_type": "projectile",
            "damage_type_label": DAMAGE_TYPE_LABELS["projectile"],
            "motion_profile": discipline["motion_profile"],
            "vfx_family": discipline["basic_vfx_family"],
            "effect_key": ELEMENT_RUNTIME_EFFECTS[basic_element],
            "kel_fallback_family": kel_fallback_family(basic_kel),
            "motion": combat_motion(str(discipline["motion_profile"])),
            "cooldown_turns": 0,
            "cooldown_remaining": 0,
        },
        # `skill`은 저장 중인 v1 run과 구버전 앱을 위한 읽기 alias다.
        "skill": unique_1,
        "unique_skills": [unique_1, unique_2],
        "selected_skills": [selected_1, selected_2],
        "guard": {
            "code": "guard",
            "name": "마음 지키기",
            "description": "피해를 두 칸 막고 집중력 1을 얻어요.",
            "available": True,
            "guard": 2,
            "focus_delta": 1,
            "motion_profile": "guard.channel",
            "vfx_family": "common.safe-guard",
            "effect_key": "safe_guard",
            "kel_fallback_family": None,
            "motion": combat_motion("guard.channel", impact_shake_px=0.0),
            "cooldown_turns": 0,
            "cooldown_remaining": 0,
        },
    }


def _resolve_waves(
    encounter: dict[str, Any],
    *,
    kel_map_version: int,
) -> list[dict[str, Any]]:
    """웨이브 엉킴 code를 전투 스냅샷용 정의로 펼친다.

    battle 상태에 펼친 값을 저장하므로 진행 중 run은 이후 카탈로그 패치의
    영향을 받지 않는다(시작 snapshot 유지 계약).
    """

    element_kels = element_kel_map(kel_map_version)
    waves: list[dict[str, Any]] = []
    for code in encounter.get("waves") or []:
        tangle = tangle_definition(code)
        weak_element, resist_element = TANGLE_ELEMENT_MATCHUPS[code]
        waves.append(
            {
                "code": code,
                "name": tangle["name"],
                "region_code": tangle["region_code"],
                "elite": bool(tangle["elite"]),
                "barrier": int(tangle["barrier"]),
                "weakness_cycle": list(tangle["weakness_cycle"]),
                "weak_element": weak_element,
                "resist_element": resist_element,
                "weak_kel": element_kels[weak_element],
                "resist_kel": element_kels[resist_element],
                "intents": [dict(intent) for intent in tangle["intents"]],
                "appear_caption": tangle["appear_caption"],
                "release_caption": tangle["release_caption"],
            }
        )
    return waves


def _party_growth_scale_bp(profiles: list[dict[str, Any]]) -> tuple[int, int]:
    growth_index = growth_index_for_party(profiles)
    # Lv1~3에서는 계수 반올림으로 플레이어 위력이 아직 오르지 않을 수 있다.
    # 이 구간부터 장벽만 두꺼워지는 역성장을 막고, 이후 90% 구간에서 1.30배까지
    # 선형 보간한다.
    scalable_growth = max(0, growth_index - 10)
    barrier_bonus_bp = (3_000 * scalable_growth + 45) // 90
    return growth_index, 10_000 + barrier_bonus_bp


def _current_wave(state: dict[str, Any]) -> dict[str, Any] | None:
    waves = state.get("waves") or []
    index = int(state.get("wave_index", 0))
    return waves[index] if 0 <= index < len(waves) else None


def new_guardian_battle(
    event_code: str,
    encounter: dict[str, Any],
    profiles: list[dict[str, Any]],
) -> dict[str, Any]:
    kel_map_version = CURRENT_KEL_MAP_VERSION
    element_kels = element_kel_map(kel_map_version)
    waves = _resolve_waves(encounter, kel_map_version=kel_map_version)
    growth_index, barrier_scale_bp = _party_growth_scale_bp(profiles)
    max_focus = int(encounter.get("max_focus", 5))
    configured_focus = int(encounter.get("starting_focus", 3))
    starting_focus, starting_focus_level_bonus, average_party_level = (
        starting_focus_for_party(
            profiles,
            configured_focus=configured_focus,
            max_focus=max_focus,
        )
    )
    for wave in waves:
        wave["base_barrier"] = int(wave["barrier"])
        wave["barrier"] = scaled_power(int(wave["barrier"]), barrier_scale_bp)
    if waves:
        first = waves[0]
        weakness_cycle = list(first["weakness_cycle"])
        weak_element = first["weak_element"]
        resist_element = first["resist_element"]
        barrier = int(first["barrier"])
        opening_caption = first["appear_caption"]
    else:
        weakness_cycle = list(encounter.get("weakness_cycle") or AFFINITIES)
        weak_element = encounter.get("weak_element")
        resist_element = encounter.get("resist_element")
        base_barrier = int(encounter.get("enemy_max_guard", 100))
        barrier = scaled_power(base_barrier, barrier_scale_bp)
        opening_caption = "돌비늘 장부지기가 길을 막았어요."
    return {
        "version": 2,
        "balance_version": COMBAT_BALANCE_VERSION,
        "kel_map_version": kel_map_version,
        "event_code": event_code,
        "status": "active",
        "round": 1,
        "max_rounds": int(encounter.get("max_rounds", 6)),
        "focus": starting_focus,
        "max_focus": max_focus,
        "configured_starting_focus": configured_focus,
        "starting_focus_level_bonus": starting_focus_level_bonus,
        "average_party_level": average_party_level,
        "enemy_kind": "tangle" if waves else "guardian",
        "waves": waves,
        "wave_index": 0,
        "enemy_guard": barrier,
        "enemy_max_guard": barrier,
        "growth_index": growth_index,
        "barrier_scale_bp": barrier_scale_bp,
        "weakness": weakness_cycle[0],
        "weak_element": weak_element,
        "resist_element": resist_element,
        "weak_kel": element_kels.get(str(weak_element)),
        "resist_kel": element_kels.get(str(resist_element)),
        "intent_index": 0,
        "party": [
            {
                "member_id": int(profile["id"]),
                "hp": combat_hp_for_level(
                    combat_level_from_snapshot(profile.get("snapshot", {}))
                ),
                "max_hp": combat_hp_for_level(
                    combat_level_from_snapshot(profile.get("snapshot", {}))
                ),
                "guard": 0,
                "cooldown_until_round": {},
                "ready_round": {},
            }
            for profile in profiles
        ],
        "pending": None,
        "round_exchange": [],
        "last_exchange": [],
        "battle_log": [opening_caption],
        "defeat_reason": None,
    }


def _intent(
    encounter: dict[str, Any],
    index: int,
    wave: dict[str, Any] | None = None,
) -> dict[str, Any]:
    intents = (wave or {}).get("intents") or encounter.get("intents") or []
    if not intents:
        return present_intent({
            "code": "guardian_strike",
            "name": encounter.get("attack_name", "수호자의 공격"),
            "telegraph": encounter.get("telegraph", "공격을 준비하고 있어요."),
            "target": "front",
            "power": 1,
        })
    return present_intent(dict(intents[index % len(intents)]))


def guardian_battle_payload(
    state: dict[str, Any],
    encounter: dict[str, Any],
    profiles: list[dict[str, Any]],
) -> dict[str, Any]:
    """직렬화 상태에 이름·스킬·현재 적 의도를 결합한 클라이언트 계약."""

    profile_by_id = {int(profile["id"]): profile for profile in profiles}
    kel_map_version = _battle_kel_map_version(state)
    weakness = state.get("weakness", AFFINITIES[0])
    weak_element = state.get("weak_element")
    resist_element = state.get("resist_element")
    party = []
    for member_state in state.get("party", []):
        member_id = int(member_state["member_id"])
        profile = profile_by_id.get(member_id)
        if profile is None:
            continue
        snapshot = profile.get("snapshot", {})
        party.append(
            {
                **member_state,
                "name": snapshot.get("name", "탐험대원"),
                "position": int(profile.get("position", 0)),
                "is_guide": bool(profile.get("is_guide")),
                "species_code": snapshot.get("species", {}).get("code", ""),
                "form": snapshot.get("form", "mosaic"),
                "kit": member_battle_kit(
                    profile,
                    current_weakness=weakness,
                    current_weak_element=weak_element,
                    current_resist_element=resist_element,
                    kel_map_version=kel_map_version,
                    member_state=member_state,
                    round_number=int(state.get("round", 1)),
                ),
            }
        )
    wave = _current_wave(state)
    intent = _intent(encounter, int(state.get("intent_index", 0)), wave=wave)
    pending = state.get("pending")
    acted = [
        int(member_id)
        for member_id in (pending.get("acted", []) if isinstance(pending, dict) else [])
    ]
    living_ids = [
        int(member["member_id"])
        for member in state.get("party", [])
        if int(member["hp"]) > 0
    ]
    return {
        **copy.deepcopy(state),
        "kel_map_version": kel_map_version,
        "weakness_label": AFFINITY_LABELS.get(weakness, weakness),
        "enemy_kind": state.get("enemy_kind", "guardian"),
        "enemy": {
            "name": (wave["name"] if wave else encounter.get("enemy_name", "수호자")),
            "kind": state.get("enemy_kind", "guardian"),
            "elite": bool(wave["elite"]) if wave else False,
            "guard": int(state.get("enemy_guard", 0)),
            "max_guard": int(state.get("enemy_max_guard", 100)),
            "weakness": weakness,
            "weakness_label": AFFINITY_LABELS.get(weakness, weakness),
            "weak_element": weak_element,
            "weak_element_label": ELEMENT_LABELS.get(weak_element, weak_element),
            "resist_element": resist_element,
            "resist_element_label": ELEMENT_LABELS.get(resist_element, resist_element),
            "weak_kel": state.get("weak_kel"),
            "weak_kel_label": KEL_LABELS.get(
                state.get("weak_kel"), state.get("weak_kel")
            ),
            "resist_kel": state.get("resist_kel"),
            "resist_kel_label": KEL_LABELS.get(
                state.get("resist_kel"), state.get("resist_kel")
            ),
            "intent": intent,
        },
        "wave": (
            {
                "index": int(state.get("wave_index", 0)) + 1,
                "count": len(state.get("waves") or []),
                "name": wave["name"],
            }
            if wave
            else None
        ),
        "pending_round": {
            "acted": acted,
            "awaiting": [
                member_id for member_id in living_ids if member_id not in acted
            ],
        },
        "party": party,
    }


def _living_party(state: dict[str, Any]) -> list[dict[str, Any]]:
    return [member for member in state.get("party", []) if int(member["hp"]) > 0]


def _target_members(
    state: dict[str, Any], intent: dict[str, Any]
) -> list[dict[str, Any]]:
    living = _living_party(state)
    target = intent.get("target", "front")
    if target == "all":
        return living
    if target == "lowest":
        return [min(living, key=lambda item: (int(item["hp"]), item["member_id"]))]
    return [living[0]]


def _pending_round(state: dict[str, Any]) -> dict[str, Any] | None:
    pending = state.get("pending")
    return pending if isinstance(pending, dict) else None


def _begin_round_if_needed(state: dict[str, Any]) -> dict[str, Any]:
    """라운드의 첫 행동 직전에 방어를 정리하고 진행 중 상태를 만든다."""

    pending = _pending_round(state)
    if pending is not None:
        return pending
    # 방어는 라운드 단위다. 지난 적 행동 뒤 남은 수치를 다음 라운드에 이월하지 않는다.
    for member in state.get("party", []):
        member["guard"] = 0
    pending = {"acted": [], "intent_power_delta": 0}
    state["pending"] = pending
    state["round_exchange"] = []
    return pending


def _push_event(state: dict[str, Any], event: dict[str, Any]) -> dict[str, Any]:
    exchange = state.setdefault("round_exchange", [])
    event = {"sequence": len(exchange), **event}
    exchange.append(event)
    return event


def _extend_log(state: dict[str, Any], events: list[dict[str, Any]]) -> None:
    log = list(state.get("battle_log", []))
    log.extend(
        event["caption"]
        for event in events
        if isinstance(event.get("caption"), str) and event["caption"]
    )
    state["battle_log"] = log[-8:]


def _apply_member_command(
    state: dict[str, Any],
    command: dict[str, Any],
    profile_by_id: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    """대원 한 명의 행동을 해석해 상태를 바꾸고 이벤트 하나를 돌려준다.

    일괄 라운드와 순차 명령이 같은 함수를 지나므로 두 입력 방식의 판정
    결과는 정의상 동일하다.
    """

    pending = _begin_round_if_needed(state)
    member_id = int(command.get("member_id", 0))
    requested_action = command.get("action")
    action = "unique_1" if requested_action == "skill" else requested_action
    if action not in {
        "attack",
        "unique_1",
        "unique_2",
        "selected_1",
        "selected_2",
        "guard",
    }:
        raise CombatRuleError(
            "EXPEDITION_COMBAT_ACTION_INVALID",
            "기본 공격, 고유 스킬, 선택 스킬, 마음 지키기 중 하나를 골라 주세요.",
        )
    profile = profile_by_id.get(member_id)
    member_state = next(
        (
            member
            for member in state.get("party", [])
            if int(member["member_id"]) == member_id
        ),
        None,
    )
    if profile is None or member_state is None:
        raise CombatRuleError(
            "EXPEDITION_COMBAT_MEMBER_INVALID",
            "이 전투에 없는 대원이에요.",
        )
    if int(member_state["hp"]) <= 0:
        raise CombatRuleError(
            "EXPEDITION_COMBAT_MEMBER_DOWN",
            "지쳐서 물러난 대원은 이번 라운드에 행동할 수 없어요.",
        )
    if member_id in pending["acted"]:
        raise CombatRuleError(
            "EXPEDITION_COMBAT_DUPLICATE_MEMBER",
            "한 라운드에는 대원별 행동을 한 번만 정할 수 있어요.",
        )

    # 행동 순서는 집중력 계산뿐 아니라 현재 전열이다. 첫 번째로 행동한 대원이
    # front 의도의 대상이 되므로, 순서 선택이 방어 판단에도 실제로 영향을 준다.
    party = state["party"]
    index = next(
        position
        for position, member in enumerate(party)
        if int(member["member_id"]) == member_id
    )
    party.insert(len(pending["acted"]), party.pop(index))
    pending["acted"].append(member_id)

    weakness = state.get("weakness", AFFINITIES[0])
    weak_element = state.get("weak_element")
    resist_element = state.get("resist_element")
    focus = int(state.get("focus", 0))
    max_focus = int(state.get("max_focus", 5))
    round_number = int(state.get("round", 1))
    kel_map_version = _battle_kel_map_version(state)
    kit = member_battle_kit(
        profile,
        current_weakness=weakness,
        current_weak_element=weak_element,
        current_resist_element=resist_element,
        kel_map_version=kel_map_version,
        member_state=member_state,
        round_number=round_number,
    )
    actor_name = profile.get("snapshot", {}).get("name", "탐험대원")
    enemy_before = int(state["enemy_guard"])
    damage = 0
    weakness_hit = False
    resistance_hit = False
    matchup = "neutral"
    effect_key = "safe_guard"
    motion_profile = "guard.channel"
    vfx_family = "common.safe-guard"
    kel_fallback = None
    motion = combat_motion("guard.channel", impact_shake_px=0.0)
    action_element = None
    action_elements: list[str] = []
    action_kel = None
    action_kels: list[str] = []
    fusion_variant = None
    fusion_vfx_family = None
    power_neutral = 0
    matchup_bp = 10_000
    cooldown_turns = 0
    cooldown_until_round = 0
    caption = ""

    if action == "guard":
        focus = min(max_focus, focus + int(kit["guard"]["focus_delta"]))
        member_state["guard"] = int(kit["guard"]["guard"])
        action_name = kit["guard"]["name"]
        caption = f"{actor_name}이(가) 마음을 다잡고 공격에 대비했어요."
    else:
        skill_by_slot = {
            item["slot"]: item
            for item in [*kit["unique_skills"], *kit["selected_skills"]]
        }
        action_data = kit["basic"] if action == "attack" else skill_by_slot[action]
        action_name = action_data["name"]
        if action != "attack":
            if not bool(action_data.get("available", True)):
                raise CombatRuleError(
                    "EXPEDITION_COMBAT_LEVEL_LOCKED",
                    f"레벨 {action_data['unlock_level']}부터 사용할 수 있는 스킬이에요.",
                )
            remaining = int(action_data.get("cooldown_remaining", 0))
            if remaining > 0:
                raise CombatRuleError(
                    "EXPEDITION_COMBAT_COOLDOWN",
                    f"{action_name}은(는) {remaining}턴 뒤 다시 사용할 수 있어요.",
                )
            cost = int(action_data["focus_cost"])
            if focus < cost:
                raise CombatRuleError(
                    "EXPEDITION_COMBAT_FOCUS_SHORTAGE",
                    f"{actor_name}의 스킬에 필요한 집중력이 부족해요.",
                )
            focus -= cost
        else:
            focus = min(max_focus, focus + int(action_data["focus_delta"]))
        affinity = action_data["affinity"]
        effect_key = action_data["effect_key"]
        motion_profile = str(action_data.get("motion_profile", "combat.lunge"))
        vfx_family = str(action_data.get("vfx_family", "fallback.echo-wave"))
        kel_fallback = action_data.get("kel_fallback_family")
        motion = dict(action_data.get("motion") or combat_motion(motion_profile))
        action_element = action_data.get("element")
        action_elements = [str(item) for item in action_data.get("elements", [])]
        action_kel = action_data.get("kel")
        action_kels = [str(item) for item in action_data.get("kels", [])]
        fusion_variant = action_data.get("fusion_variant")
        fusion_vfx_family = action_data.get("fusion_vfx_family")
        power_neutral = int(action_data.get("power_neutral", action_data["power"]))
        matchup_bp = int(action_data.get("matchup_bp", 10_000))
        damage = int(action_data["power"])
        modern_matchup = int(state.get("version", 1)) >= 2 and bool(
            state.get("weak_kel")
        )
        if modern_matchup:
            matchup = str(action_data.get("matchup", "neutral"))
            weakness_hit = matchup == "weak"
            resistance_hit = matchup == "resist"
        else:
            # 구버전 저장 run은 당시의 원소 정액식 또는 네 능력치 상성을 유지한다.
            if weak_element:
                weakness_hit = weak_element in action_elements
                resistance_hit = not weakness_hit and resist_element in action_elements
            else:
                weakness_hit = affinity == weakness
            if weakness_hit:
                damage += 7
                matchup = "weak"
            elif resistance_hit:
                damage = max(1, damage - 4)
                matchup = "resist"
        effect = action_data.get("effect")
        if effect == "shield_all":
            for target in _living_party(state):
                target["guard"] = int(target["guard"]) + 1
        elif effect == "focus_refund":
            focus = min(max_focus, focus + 1)
        elif effect == "heal_lowest":
            target = min(
                _living_party(state),
                key=lambda item: (int(item["hp"]), item["member_id"]),
            )
            target["hp"] = min(int(target["max_hp"]), int(target["hp"]) + 1)
        elif effect == "guard_self":
            member_state["guard"] = int(member_state["guard"]) + 2
        elif (
            not modern_matchup
            and effect == "last_stand"
            and int(member_state["hp"]) == 1
        ):
            damage += 8
        elif effect == "weaken_intent":
            pending["intent_power_delta"] = (
                int(pending.get("intent_power_delta", 0)) - 1
            )
        elif not modern_matchup and effect == "weakness_pierce" and weakness_hit:
            damage += 6
        elif not modern_matchup and effect == "steady_read" and not weakness_hit:
            damage += 5
        elif effect == "study_refund":
            focus = min(max_focus, focus + 2)
        if action != "attack":
            cooldown_turns = int(action_data.get("cooldown_turns", 0))
            if cooldown_turns > 0:
                cooldown_until_round = round_number + cooldown_turns + 1
                member_state.setdefault("ready_round", {})[action_data["code"]] = (
                    cooldown_until_round
                )
                member_state.setdefault("cooldown_until_round", {})[
                    action_data["code"]
                ] = cooldown_until_round
        state["enemy_guard"] = max(0, enemy_before - damage)
        if weakness_hit:
            caption = f"{actor_name}의 {action_name}! 약점을 꿰뚫어 장벽 {damage} 피해."
        elif resistance_hit:
            caption = (
                f"{actor_name}의 {action_name}! 내성에 막혔지만 장벽 {damage} 피해."
            )
        else:
            caption = f"{actor_name}의 {action_name}! 장벽 {damage} 피해."

    state["focus"] = focus
    return _push_event(
        state,
        {
            "type": "party_action",
            "kel_map_version": kel_map_version,
            "member_id": member_id,
            "actor_name": actor_name,
            "action": action,
            "action_name": action_name,
            "effect_key": effect_key,
            "motion_profile": motion_profile,
            "motion": motion,
            "vfx_family": vfx_family,
            "kel_fallback_family": kel_fallback,
            "element": action_element,
            "elements": action_elements,
            "kel": action_kel,
            "kels": action_kels,
            "fusion_variant": fusion_variant,
            "fusion_vfx_family": fusion_vfx_family,
            "power_neutral": power_neutral,
            "matchup_bp": matchup_bp,
            "weakness_hit": weakness_hit,
            "resistance_hit": resistance_hit,
            "matchup": matchup,
            "cooldown_turns": cooldown_turns,
            "cooldown_until_round": cooldown_until_round,
            "ready_round": cooldown_until_round,
            "damage": damage,
            "enemy_guard_before": enemy_before,
            "enemy_guard_after": int(state["enemy_guard"]),
            "focus_after": focus,
            "caption": caption,
        },
    )


def _finalize_round(
    state: dict[str, Any],
    encounter: dict[str, Any],
    profile_by_id: dict[int, dict[str, Any]],
) -> list[dict[str, Any]]:
    """모든 대원이 행동한 뒤 적의 예고 공격과 라운드 전환을 해결한다."""

    pending = _pending_round(state) or {}
    intent_power_delta = int(pending.get("intent_power_delta", 0))
    events: list[dict[str, Any]] = []
    wave = _current_wave(state)
    intent = _intent(encounter, int(state.get("intent_index", 0)), wave=wave)
    power = max(0, int(intent.get("power", 1)) + intent_power_delta)
    targets = _target_members(state, intent)
    target_events = []
    profile_names = {
        member_id: profile.get("snapshot", {}).get("name", "탐험대원")
        for member_id, profile in profile_by_id.items()
    }
    for target in targets:
        guard_before = int(target.get("guard", 0))
        blocked = min(guard_before, power)
        damage = max(0, power - blocked)
        target["guard"] = max(0, guard_before - power)
        target["hp"] = max(0, int(target["hp"]) - damage)
        target_events.append(
            {
                "member_id": int(target["member_id"]),
                "name": profile_names[int(target["member_id"])],
                "damage": damage,
                "blocked": blocked,
                "hp_after": int(target["hp"]),
            }
        )
    events.append(
        _push_event(
            state,
            {
                "type": "enemy_action",
                "action_name": intent.get("name", "수호자의 공격"),
                "effect_key": intent["effect_key"],
                "motion_profile": intent["motion_profile"],
                "motion": intent["motion"],
                "vfx_family": intent["vfx_family"],
                "kel": intent["kel"],
                "kel_fallback_family": intent["kel_fallback_family"],
                "kel_map_version": _battle_kel_map_version(state),
                "enemy_guard_before": int(state["enemy_guard"]),
                "enemy_guard_after": int(state["enemy_guard"]),
                "targets": target_events,
                "caption": intent.get("telegraph", "수호자의 공격이 밀려왔어요."),
            },
        )
    )
    if not _living_party(state):
        state["status"] = "defeat"
        state["defeat_reason"] = "party_down"
    elif int(state["round"]) >= int(state["max_rounds"]):
        state["status"] = "defeat"
        state["defeat_reason"] = "seal_completed"
    else:
        weakness_cycle = list(
            (wave or {}).get("weakness_cycle")
            or encounter.get("weakness_cycle")
            or AFFINITIES
        )
        state["round"] = int(state["round"]) + 1
        state["intent_index"] = int(state.get("intent_index", 0)) + 1
        state["weakness"] = weakness_cycle[
            (int(state["round"]) - 1) % len(weakness_cycle)
        ]
    if state["status"] == "defeat":
        events.append(
            _push_event(
                state,
                {
                    "type": "outcome",
                    "outcome": "defeat",
                    "caption": "수호자의 봉인이 완성돼 탐험대가 긴급 귀환해요.",
                },
            )
        )
    state["pending"] = None
    return events


def _enemy_cleared_events(state: dict[str, Any]) -> list[dict[str, Any]]:
    """장벽이 0이 된 순간의 처리 — 다음 웨이브 등장 또는 승리.

    웨이브가 남아 있으면 그 라운드는 거기서 끝난다. 아직 행동하지 않은 대원의
    차례와 적의 예고 공격은 실행되지 않고, 다음 라운드가 새 엉킴을 상대로
    시작된다. 승리 판정과 같은 문법이라 일괄·순차 어느 입력에서도 동일하다.
    """

    wave = _current_wave(state)
    waves = state.get("waves") or []
    if wave is not None and int(state.get("wave_index", 0)) < len(waves) - 1:
        events = [
            _push_event(
                state,
                {
                    "type": "wave_cleared",
                    "wave_index": int(state["wave_index"]),
                    "caption": wave["release_caption"],
                },
            )
        ]
        state["wave_index"] = int(state["wave_index"]) + 1
        next_wave = waves[int(state["wave_index"])]
        state["enemy_guard"] = int(next_wave["barrier"])
        state["enemy_max_guard"] = int(next_wave["barrier"])
        state["round"] = int(state["round"]) + 1
        state["intent_index"] = 0
        state["weakness"] = next_wave["weakness_cycle"][0]
        state["weak_element"] = next_wave["weak_element"]
        state["resist_element"] = next_wave["resist_element"]
        state["weak_kel"] = next_wave["weak_kel"]
        state["resist_kel"] = next_wave["resist_kel"]
        state["pending"] = None
        events.append(
            _push_event(
                state,
                {
                    "type": "wave_intro",
                    "wave_index": int(state["wave_index"]),
                    "enemy_name": next_wave["name"],
                    "caption": next_wave["appear_caption"],
                },
            )
        )
        return events

    state["status"] = "victory"
    state["pending"] = None
    caption = (
        wave["release_caption"]
        if wave is not None
        else "수호 장벽이 부서지고 장부지기가 길을 열었어요!"
    )
    return [
        _push_event(
            state,
            {
                "type": "outcome",
                "outcome": "victory",
                "caption": caption,
            },
        )
    ]


def resolve_guardian_round(
    battle: dict[str, Any],
    commands: list[dict[str, Any]],
    encounter: dict[str, Any],
    profiles: list[dict[str, Any]],
) -> dict[str, Any]:
    """한 라운드의 예약 행동과 적의 예고 공격을 순서대로 해결한다."""

    state = copy.deepcopy(battle)
    if state.get("status") != "active":
        raise CombatRuleError("EXPEDITION_COMBAT_FINISHED", "이미 끝난 전투예요.")
    pending = _pending_round(state)
    if pending is not None and pending.get("acted"):
        raise CombatRuleError(
            "EXPEDITION_COMBAT_ROUND_IN_PROGRESS",
            "이미 시작한 라운드는 대원별 명령으로 이어서 진행해 주세요.",
        )
    living_ids = [int(member["member_id"]) for member in _living_party(state)]
    command_ids = [int(command.get("member_id", 0)) for command in commands]
    if len(command_ids) != len(set(command_ids)):
        raise CombatRuleError(
            "EXPEDITION_COMBAT_DUPLICATE_MEMBER",
            "한 라운드에는 대원별 행동을 한 번만 정할 수 있어요.",
        )
    if set(command_ids) != set(living_ids):
        raise CombatRuleError(
            "EXPEDITION_COMBAT_COMMANDS_INCOMPLETE",
            "행동할 수 있는 모든 대원의 명령을 정해 주세요.",
        )

    profile_by_id = {int(profile["id"]): profile for profile in profiles}
    state["pending"] = None
    events: list[dict[str, Any]] = []
    round_over = False
    for command in commands:
        events.append(_apply_member_command(state, command, profile_by_id))
        if int(state["enemy_guard"]) <= 0:
            events.extend(_enemy_cleared_events(state))
            round_over = True
            break
    if not round_over:
        events.extend(_finalize_round(state, encounter, profile_by_id))
    state["last_exchange"] = events
    _extend_log(state, events)
    return state


def submit_guardian_action(
    battle: dict[str, Any],
    command: dict[str, Any],
    encounter: dict[str, Any],
    profiles: list[dict[str, Any]],
) -> dict[str, Any]:
    """순차 명령 한 건을 즉시 해결한다.

    스테이지 개편(stage-battle-v2.0)의 전투 문법이다. 대원 한 명의 행동을
    바로 판정해 돌려주고, 살아 있는 모든 대원이 행동하면 같은 응답에서 적의
    예고 공격과 라운드 전환까지 해결한다. `last_exchange`에는 이번 호출에서
    새로 일어난 이벤트만 담기고, 라운드 전체 기록은 `round_exchange`에 남는다.
    """

    state = copy.deepcopy(battle)
    if state.get("status") != "active":
        raise CombatRuleError("EXPEDITION_COMBAT_FINISHED", "이미 끝난 전투예요.")
    profile_by_id = {int(profile["id"]): profile for profile in profiles}
    events = [_apply_member_command(state, command, profile_by_id)]
    if int(state["enemy_guard"]) <= 0:
        events.extend(_enemy_cleared_events(state))
    else:
        pending = _pending_round(state) or {"acted": []}
        living_ids = {int(member["member_id"]) for member in _living_party(state)}
        if living_ids <= set(int(item) for item in pending.get("acted", [])):
            events.extend(_finalize_round(state, encounter, profile_by_id))
    state["last_exchange"] = events
    _extend_log(state, events)
    return state
