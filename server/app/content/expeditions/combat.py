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
    character_combat_stats,
    combat_effect_summary,
    combat_effect_values,
    combat_tier,
    element_kel_map,
    EMOTION_VFX_PALETTES,
    rarity_scale_bp,
    scaled_power,
)
from app.content.expeditions.combat_difficulty import (
    COMBAT_DIFFICULTY_VERSION,
    difficulty_profile_for_encounter,
    enemy_mechanic,
)
from app.content.expeditions.combat_motion import (
    combat_motion,
    kel_fallback_family,
    present_intent,
)
from app.content.expeditions.skill_book_effects import (
    CHOICE_KELS,
    COMMAND_FOCUS_COST_BY_GRADE,
    NOTHING_TO_CHOOSE,
    all_hit_reduction,
    book_state,
    command_action,
    focus_trigger,
    intent_preview_open,
    kit_modifiers,
    oath_matchup_bp,
    opening_modifiers,
    take_weakness_bonus,
    validate_choice,
)
from app.content.expeditions.skill_books import SKILL_BOOK_CATALOG
from app.content.expeditions.tangles import CONTACT_MATERIALS, tangle_definition
from app.core.korean import korean_subject, korean_topic


# 전용 재질이 없는 구형 수호자에게 쓸 안전 기본값. 단단한 무언가에 닿았다는
# 사실만 전하고 재질을 과장하지 않는다.
DEFAULT_CONTACT_MATERIAL = "stone"

# 네 스킬 슬롯. 기본 공격과 마음 지키기는 어떤 제약에서도 남겨 둔다.
SKILL_ACTIONS = frozenset({"unique_1", "unique_2", "selected_1", "selected_2"})

# 고를 수 있는 성장결. 저장된 값이 깨져도 판정이 흔들리지 않게 좁힌다.
ELEMENT_KEL_CHOICES = frozenset(CHOICE_KELS)

# 전투당 1회를 쿨타임으로 표현한다. 최대 라운드보다 길면 그 전투에서 다시
# 열리지 않는다. 라운드 상한이 늘어나는 기록서까지 고려해 넉넉히 잡는다.
_ONCE_PER_BATTLE_COOLDOWN = 99

# 캐릭터, 감정 성장, 레벨/희귀도 계수의 단일 원본은 combat_identity.py다.
AFFINITIES = IDENTITY_AFFINITIES
AFFINITY_LABELS = IDENTITY_AFFINITY_LABELS
SPECIES_SKILLS = IDENTITY_SPECIES_SKILLS
SPECIES_SECONDARY_SKILLS = IDENTITY_SPECIES_SECONDARY_SKILLS
FORM_COMBAT_SKILLS = IDENTITY_FORM_COMBAT_SKILLS
FIELD_NOTE_SKILL = IDENTITY_FIELD_NOTE_SKILL

PRISM_SHIFT_EFFECTS = frozenset({"prism_shift", "runway_reversal"})


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
    choice_context: dict[str, dict[str, Any]] | None = None,
    enemy_guard_bp: int = 10_000,
    party_unique2_power: int = 0,
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
    combat_profile = character_combat_stats(
        str(species_code), level=level, rarity=rarity, form=str(form)
    )
    combat_stats = dict(combat_profile["values"])
    emotion_palette = dict(
        EMOTION_VFX_PALETTES.get(form, EMOTION_VFX_PALETTES["mosaic"])
    )
    signature_scale = rarity_scale_bp(level, rarity)
    basic_scale = basic_scale_bp(level, rarity)
    weak_kel = element_kels.get(str(current_weak_element))
    resist_kel = element_kels.get(str(current_resist_element))
    state_cooldowns = member_state or {}
    # 다음 공격 한 번에만 실리는 성장결 덮어쓰기. 고유기(signature)는 품종의
    # 정체성이라 바꾸지 않는다.
    kel_override = (member_state or {}).get("kel_override")
    if kel_override not in ELEMENT_KEL_CHOICES:
        kel_override = None
    cooldowns = state_cooldowns.get("ready_round") or state_cooldowns.get(
        "cooldown_until_round", {}
    )

    def cooldown_remaining(code: str) -> int:
        return max(0, int(cooldowns.get(code, 0)) - int(round_number))

    # 그림자 맹세 — 이 대원이 쓰는 상성 배율을 통째로 갈아 끼운다. 약점은 더
    # 아프고 중립은 덜 아프다. 내성은 원래 값 그대로다(중복하지 않는다).
    matchup_bp_table = {**MATCHUP_POWER_BP, **oath_matchup_bp(snapshot)}

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
            if skill["effect"] in PRISM_SHIFT_EFFECTS and current_weakness in AFFINITIES
            else affinity
        )
        element = str(skill["element"])
        prism_shifted = skill["effect"] in PRISM_SHIFT_EFFECTS and weak_kel is not None
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
        # 마음결 조율기로 고른 결이 있으면 이 공격의 결을 그것으로 바꾼다.
        # 상성을 여기서 다시 계산하므로 앱의 예상 피해도 바뀐 결을 반영한다.
        # 프리즘 스킬은 이미 스스로 약점에 맞추므로 덮어쓰지 않는다 — 덮으면
        # 오히려 상성이 나빠질 수 있다.
        if kel_override and not prism_shifted:
            kels = [kel_override]
            skill_kel = kel_override
        matchup = _kel_matchup(kels, weak_kel=weak_kel, resist_kel=resist_kel)
        matchup_key = "prism_weak" if prism_shifted and matchup == "weak" else matchup
        matchup_bp = matchup_bp_table[matchup_key]
        cooldown_turns = int(skill["cooldown_turns"])
        if source == "signature" and tier >= 3 and cooldown_turns > 0:
            cooldown_turns = max(1, cooldown_turns - 1)
        raw_power = (
            int(skill["power"])
            + stats[skill_affinity]
            + max(0, (int(combat_stats["offense"]) - 20) // 6)
            # 고리수 기록부 — 파티 전원의 고유 II에 실리는 정액. `또렷한 겨냥`이
            # 기본 공격에 붙는 것과 같은 자리(raw_power)라 정액 계약이 같다.
            + (party_unique2_power if slot == "unique_2" else 0)
        )
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
        effect_values = combat_effect_values(
            str(skill["effect"]),
            tier=tier,
            combat_stats=combat_stats,
            skill_code=str(skill["code"]),
        )
        vfx_intensity = (0.86, 1.0, 1.14)[tier - 1]
        audio_layer = ("light", "full", "signature")[tier - 1]
        impact_shake = (2.2, 3.2, 4.4)[tier - 1]
        if slot == "unique_2":
            impact_shake += 0.8
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
            "effect_values": effect_values,
            "mechanic_summary": combat_effect_summary(
                str(skill["effect"]), effect_values
            ),
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
            "fusion_production_ready": True if fusion_profile is not None else None,
            "prism_shifted": prism_shifted,
            "presentation_tier": tier,
            "vfx_intensity": vfx_intensity,
            "audio_layer": audio_layer,
            "camera_profile": (
                "ultimate"
                if slot == "unique_2" and tier >= 3
                else "impact"
                if tier >= 2
                else "steady"
            ),
            "emotion_vfx_primary": emotion_palette["primary"],
            "emotion_vfx_secondary": emotion_palette["secondary"],
            "damage_type_label": DAMAGE_TYPE_LABELS[skill["damage_type"]],
            "effect_key": (
                str(skill["code"])
                if source == "signature"
                else ELEMENT_RUNTIME_EFFECTS[element]
            ),
            "kel_fallback_family": kel_fallback_family(skill_kel),
            "motion": combat_motion(
                str(skill["motion_profile"]),
                ultimate=slot == "unique_2" and tier >= 2,
                impact_shake_px=impact_shake,
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
    # 고리수 기록부 — 파티 전원의 고유 II에 정액이 실린다. 위력만 올리고
    # 비용·쿨타임은 건드리지 않는다.
    unique_2 = resolve_skill(
        SPECIES_SECONDARY_SKILLS.get(
            species_code, SPECIES_SECONDARY_SKILLS["archive_guide"]
        ),
        slot="unique_2",
        source="signature",
        unlock_level=7,
    )
    # 선택 슬롯은 출발 시점에 얼린 장착을 따른다. 스냅샷이 없는 예전 런은
    # 지금까지와 같은 안전 기본값(성장결 기본 스킬 + 현장 기록서)으로 읽힌다.
    loadout_slots = (snapshot.get("skill_loadout") or {}).get("slots") or {}
    # 조율기가 무엇과 비교해 `지금과 다른 결`을 따지는지의 기준. 명령 스킬 자신의
    # 결이 아니라 **이 대원이 평소 때리는 결**이어야 한다. 둘은 감정 폼에 따라
    # 다를 수 있고, 다르면 사용자가 고른 결이 영문 없이 거절된다.
    default_kel = element_kels[str(discipline["primary_element"])]
    # 무엇을 고를 수 있고 지금은 무엇인지. 성장결 여섯은 전투와 무관하게 같아서
    # 여기서 만들고, 대원·기록서처럼 그 전투를 봐야 아는 것은 호출부가 넘긴다.
    choices: dict[str, dict[str, Any]] = {
        "kel": {
            "options": [
                {"value": kel, "label": KEL_LABELS[kel]} for kel in CHOICE_KELS
            ],
            "current": default_kel,
        },
        **(choice_context or {}),
    }
    # 마음결 대백과로 바꿔 낀 B1은 이 전투 동안 유지된다. 얼려 둔 장착 위에
    # 덮어쓰되 스냅샷 자체는 건드리지 않는다 — 런이 끝나면 원래 장착이다.
    swapped_b1 = (member_state or {}).get("b1_override")
    selected_1 = _resolve_selected_slot(
        (
            {"source": "skillbook", "code": swapped_b1}
            if swapped_b1 in SKILL_BOOK_CATALOG
            else loadout_slots.get("B1")
        ),
        resolve_skill=resolve_skill,
        form=form,
        default_kel=default_kel,
        choices=choices,
        slot="selected_1",
        unlock_level=9,
    )
    selected_2 = _resolve_selected_slot(
        loadout_slots.get("B2"),
        resolve_skill=resolve_skill,
        form=form,
        default_kel=default_kel,
        choices=choices,
        slot="selected_2",
        unlock_level=23,
    )
    basic_element = str(discipline["primary_element"])
    # 장착한 기록서의 정액 보정. 등급·tier로 자라지 않고 문장의 숫자 그대로다.
    book_modifiers = kit_modifiers(
        snapshot, b1_override=swapped_b1, enemy_guard_bp=enemy_guard_bp
    )
    basic_raw_power = (
        10
        + stats[affinity] // 2
        + max(0, (int(combat_stats["offense"]) - 20) // 8)
        + book_modifiers.get("basic_power", 0)
    )
    basic_kel = element_kels[basic_element]
    # 조율기로 고른 결은 기본 공격에도 실린다. 설계상 `다음 공격`이지 `다음
    # 스킬`이 아니다.
    if kel_override:
        basic_kel = kel_override
    basic_matchup = _kel_matchup([basic_kel], weak_kel=weak_kel, resist_kel=resist_kel)
    basic_neutral_power = scaled_power(
        scaled_power(basic_raw_power, basic_scale), TIER_POWER_BP[tier]
    )
    return {
        "version": 8,
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
        "role": combat_profile["role"],
        "role_label": combat_profile["role_label"],
        "combat_stats": combat_stats,
        "combat_stat_labels": combat_profile["labels"],
        "emotion_vfx_palette": emotion_palette,
        "primary_element": basic_element,
        "primary_element_label": ELEMENT_LABELS[basic_element],
        "secondary_element": discipline["secondary_element"],
        "secondary_element_label": ELEMENT_LABELS[discipline["secondary_element"]],
        # 조율기로 바꿔 둔 결이 있으면 키트가 그 사실을 밝힌다. 앱이 "지금
        # 무슨 결로 나가는지"를 그대로 보여 줄 수 있고, 예상 피해도 이미 바뀐
        # 상성으로 계산돼 있다.
        "kel_override": kel_override,
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
            "matchup_bp": matchup_bp_table[basic_matchup],
            "effect_power_bp": 10_000,
            "effect_values": {},
            "mechanic_summary": "집중 회복 1",
            "power": scaled_power(
                basic_neutral_power, matchup_bp_table[basic_matchup]
            ),
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
            "presentation_tier": tier,
            "vfx_intensity": (0.86, 1.0, 1.14)[tier - 1],
            "audio_layer": ("light", "full", "signature")[tier - 1],
            "camera_profile": "steady" if tier == 1 else "impact",
            "emotion_vfx_primary": emotion_palette["primary"],
            "emotion_vfx_secondary": emotion_palette["secondary"],
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
            "guard": 2
            + max(0, (int(combat_stats["vitality"]) - 12) // 10)
            + book_modifiers.get("guard", 0),
            "focus_delta": 1,
            "motion_profile": "guard.channel",
            "vfx_family": "common.safe-guard",
            "effect_key": "safe_guard",
            "kel_fallback_family": None,
            "motion": combat_motion("guard.channel", impact_shake_px=0.0),
            "mechanic_summary": "피해 방어 · 집중 회복 1",
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
                "contact_material": tangle["contact_material"],
                "appear_caption": tangle["appear_caption"],
                "release_caption": tangle["release_caption"],
            }
        )
    return waves


def _resolve_boss_phases(
    encounter: dict[str, Any],
    *,
    element_kels: Any,
) -> list[dict[str, Any]]:
    phases: list[dict[str, Any]] = []
    for index, raw in enumerate(encounter.get("boss_phases") or []):
        phase = dict(raw)
        weak_element = str(phase.get("weak_element", encounter.get("weak_element")))
        resist_element = str(
            phase.get("resist_element", encounter.get("resist_element"))
        )
        phases.append(
            {
                **phase,
                "index": index + 1,
                "threshold_bp": int(phase.get("threshold_bp", 10_000)),
                "weak_element": weak_element,
                "resist_element": resist_element,
                "weak_kel": element_kels[weak_element],
                "resist_kel": element_kels[resist_element],
                "weakness_cycle": list(
                    phase.get("weakness_cycle")
                    or encounter.get("weakness_cycle")
                    or AFFINITIES
                ),
                "intent_power_bonus": int(phase.get("intent_power_bonus", 0)),
                "focus_reward": int(phase.get("focus_reward", 0)),
                "rule_name": phase.get("rule_name"),
                "rule_summary": phase.get("rule_summary"),
                "mechanic_code": phase.get("mechanic_code"),
                "phase_gate": phase.get("phase_gate"),
            }
        )
    return phases


def _current_boss_phase(state: dict[str, Any]) -> dict[str, Any] | None:
    phases = state.get("boss_phases") or []
    index = int(state.get("boss_phase_index", 0))
    return phases[index] if 0 <= index < len(phases) else None


def _boss_phase_payload(state: dict[str, Any]) -> dict[str, Any] | None:
    phase = _current_boss_phase(state)
    if phase is None:
        return None
    phases = state.get("boss_phases") or []
    index = int(state.get("boss_phase_index", 0))
    next_phase = phases[index + 1] if index + 1 < len(phases) else None
    max_guard = max(1, int(state.get("enemy_max_guard", 1)))
    return {
        "index": index + 1,
        "count": len(phases),
        "code": phase.get("code", f"phase_{index + 1}"),
        "name": phase.get("name", f"{index + 1}페이즈"),
        "tone": phase.get("tone", "mosaic"),
        "intent_power_bonus": int(phase.get("intent_power_bonus", 0)),
        "rule_name": phase.get("rule_name"),
        "rule_summary": phase.get("rule_summary"),
        "phase_gate": phase.get("phase_gate"),
        "phase_gate_ready": bool(state.get("boss_phase_gate_ready", False)),
        "next_threshold_guard": (
            max(1, (max_guard * int(next_phase["threshold_bp"]) + 9_999) // 10_000)
            if next_phase is not None
            else None
        ),
    }


def _cap_boss_damage_at_next_phase(state: dict[str, Any], damage: int) -> int:
    """한 행동이 보스 페이즈를 건너뛰지 않도록 다음 경계에서 멈춘다.

    높은 성장 파티도 세 규칙을 순서대로 보게 하되 별도 무적 시간은 만들지 않는다.
    다음 대원의 행동은 새 상성·기믹으로 바로 이어져 전투 흐름도 끊기지 않는다.
    """

    phases = state.get("boss_phases") or []
    index = int(state.get("boss_phase_index", 0))
    if damage <= 0 or not phases:
        return max(0, damage)
    guard = int(state.get("enemy_guard", 0))
    gate_locked = bool(phases[index].get("phase_gate")) and not bool(
        state.get("boss_phase_gate_ready", False)
    )
    if index + 1 >= len(phases):
        return min(damage, max(0, guard - 1)) if gate_locked else damage
    max_guard = max(1, int(state.get("enemy_max_guard", 1)))
    threshold = (
        max_guard * int(phases[index + 1]["threshold_bp"]) + 9_999
    ) // 10_000
    if gate_locked:
        # 대표 패턴을 한 번 해결하기 전에는 경계 바로 위에서 멈춘다.
        return min(damage, max(0, guard - (threshold + 1)))
    return min(damage, max(0, guard - threshold))


def _advance_boss_phase(state: dict[str, Any]) -> list[dict[str, Any]]:
    phases = state.get("boss_phases") or []
    events: list[dict[str, Any]] = []
    if not phases or int(state.get("enemy_guard", 0)) <= 0:
        return events
    max_guard = max(1, int(state.get("enemy_max_guard", 1)))
    index = int(state.get("boss_phase_index", 0))
    while index + 1 < len(phases):
        next_phase = phases[index + 1]
        threshold = (max_guard * int(next_phase["threshold_bp"]) + 9_999) // 10_000
        if int(state["enemy_guard"]) > threshold:
            break
        index += 1
        phase = phases[index]
        state["boss_phase_index"] = index
        state["boss_phase_gate_ready"] = False
        state["weakness"] = phase["weakness_cycle"][0]
        state["weak_element"] = phase["weak_element"]
        state["resist_element"] = phase["resist_element"]
        state["weak_kel"] = phase["weak_kel"]
        state["resist_kel"] = phase["resist_kel"]
        state["intent_index"] = 0
        state["focus"] = min(
            int(state.get("max_focus", 5)),
            int(state.get("focus", 0)) + int(phase.get("focus_reward", 0)),
        )
        events.append(
            _push_event(
                state,
                {
                    "type": "boss_phase",
                    "phase_index": index + 1,
                    "phase_count": len(phases),
                    "phase_code": phase.get("code", f"phase_{index + 1}"),
                    "phase_name": phase.get("name", f"{index + 1}페이즈"),
                    "effect_key": "boss_phase_break",
                    "vfx_family": "guardian.phase-break",
                    "presentation_tier": min(3, index + 1),
                    "audio_layer": "signature" if index + 1 >= 3 else "full",
                    "caption": phase.get(
                        "intro_caption", "수호자가 새로운 봉인 자세를 펼쳤어요."
                    ),
                },
            )
        )
    return events


def _party_growth_scale_bp(profiles: list[dict[str, Any]]) -> tuple[int, int]:
    growth_index = growth_index_for_party(profiles)
    # Lv1~3에서는 계수 반올림으로 플레이어 위력이 아직 오르지 않을 수 있다.
    # 이 구간부터 장벽만 두꺼워지는 역성장을 막고, 이후 90% 구간에서 1.30배까지
    # 선형 보간한다.
    scalable_growth = max(0, growth_index - 10)
    barrier_bonus_bp = (3_000 * scalable_growth + 45) // 90
    return growth_index, 10_000 + barrier_bonus_bp


def _combat_hp_for_profile(profile: dict[str, Any]) -> int:
    snapshot = profile.get("snapshot", {})
    level = combat_level_from_snapshot(snapshot)
    rarity = max(1, min(5, int(snapshot.get("rarity", 1))))
    species_code = str(snapshot.get("species", {}).get("code", "archive_guide"))
    form = str(snapshot.get("form", "mosaic"))
    stats = character_combat_stats(species_code, level=level, rarity=rarity, form=form)[
        "values"
    ]
    vitality_bonus = max(0, (int(stats["vitality"]) - 8) // 6)
    return combat_hp_for_level(level) + vitality_bonus


def _current_wave(state: dict[str, Any]) -> dict[str, Any] | None:
    waves = state.get("waves") or []
    index = int(state.get("wave_index", 0))
    return waves[index] if 0 <= index < len(waves) else None


def _resolve_selected_slot(
    decision: dict[str, Any] | None,
    *,
    resolve_skill: Any,
    form: str,
    default_kel: str,
    choices: dict[str, dict[str, Any]],
    slot: str,
    unlock_level: int,
) -> dict[str, Any]:
    """얼려 둔 장착 결정 하나를 실제 행동 payload로 바꾼다.

    감정 포인터와 현장 기록서는 지금까지와 똑같이 동작한다. 장착한 기록서는
    카탈로그에서 이름·등급을 가져와 슬롯에 보여 주되, 아직 전투 판정에 연결된
    기믹이 없으면 **누를 수 없는 상태로 정직하게 표시한다.** 없는 효과를
    있는 것처럼 보여 주지 않는다.
    """

    source = (decision or {}).get("source")
    code = (decision or {}).get("code")

    if source == "skillbook" and code in SKILL_BOOK_CATALOG:
        book = SKILL_BOOK_CATALOG[code]
        action = (
            command_action(str(code))
            if book["activation_mode"] == "command"
            else None
        )
        base = (
            FORM_COMBAT_SKILLS.get(form, FORM_COMBAT_SKILLS["mosaic"])
            if slot == "selected_1"
            else FIELD_NOTE_SKILL
        )
        if action is not None:
            # 쿨타임과 준비 라운드는 스킬 코드로 추적된다. 누를 수 있는 책은
            # 자기 코드로 해석해야 `전투당 1회`가 그 책에 걸린다.
            base = {
                **base,
                "code": book["code"],
                "name": book["name"],
                "description": book["effect_summary"],
                "tier_names": [book["name"]] * 3,
            }
        payload = resolve_skill(
            base,
            slot=slot,
            source="skillbook",
            unlock_level=unlock_level,
        )
        book_summary = {
            "code": book["code"],
            "name": book["name"],
            "grade": book["grade"],
            "activation_mode": book["activation_mode"],
            "effect_summary": book["effect_summary"],
        }
        if action is not None:
            kind = action.get("choice_kind")
            picked = choices.get(str(kind)) if kind else None
            options = list((picked or {}).get("options") or [])
            # 고를 것이 있다고 해 놓고 후보가 비면 누를 수 없다. 눌러 본 뒤
            # 거절당하는 대신 왜 못 쓰는지 슬롯에서 바로 읽히게 한다.
            nothing_to_choose = kind is not None and not options
        if action is not None:
            # 7.5.1 — 대원 행동 1회를 쓰고, 비용은 등급을 따르며, 전투당 한 번이다.
            # 기록서는 피해를 주지 않는 지원 도구라 위력은 0이고, 효과 값은
            # 정액이라 tier·지원 능력치로 자라지 않는다.
            grade = int(book["grade"])
            payload.update(
                {
                    "equipped_book": book_summary,
                    "available": not nothing_to_choose,
                    "lock_reason": (
                        NOTHING_TO_CHOOSE.get(str(kind), "지금은 고를 것이 없어요.")
                        if nothing_to_choose
                        else None
                    ),
                    "focus_cost": COMMAND_FOCUS_COST_BY_GRADE[grade],
                    "focus_delta": 0,
                    "power": 0,
                    "raw_power": 0,
                    "power_neutral": 0,
                    "matchup": "neutral",
                    "matchup_bp": 10_000,
                    "effect": action["effect"],
                    "effect_values": dict(action["effect_values"]),
                    "mechanic_summary": book["effect_summary"],
                    # 전투당 1회 — 이번 전투가 끝날 때까지 다시 열리지 않는다.
                    "cooldown_turns": _ONCE_PER_BATTLE_COOLDOWN,
                    # 고를 것이 있으면 무엇을 고르는지와 후보를 함께 준다.
                    # 앱이 목록을 자체적으로 만들지 않게 하기 위해서다. 판정도
                    # 이 목록으로 하므로 화면에 보인 것을 골랐는데 거절당하는
                    # 일이 없다.
                    "choice_kind": kind,
                    # 무엇과 비교해 `지금과 다른 것`을 따지는지도 함께 밝힌다.
                    # 앱은 이 값으로 현재 표시만 하고 판정은 서버가 한다.
                    "choice_current": (picked or {}).get("current"),
                    "choice_options": options,
                }
            )
            return payload

        payload.update(
            {
                "equipped_book": book_summary,
                # opening·trigger는 스스로 발동해 대원 행동을 소비하지 않고,
                # command라도 기믹이 아직 없으면 누를 수 없다.
                "available": False,
                "lock_reason": (
                    "효과를 준비하고 있어요"
                    if book.get("combat_effect") is not True
                    else "때가 되면 스스로 펼쳐져요"
                ),
            }
        )
        return payload

    if slot == "selected_1":
        return resolve_skill(
            FORM_COMBAT_SKILLS.get(form, FORM_COMBAT_SKILLS["mosaic"]),
            slot=slot,
            source="emotion",
            unlock_level=unlock_level,
        )
    return resolve_skill(
        FIELD_NOTE_SKILL,
        slot=slot,
        source="skillbook",
        unlock_level=unlock_level,
    )


def target_contact_material(state: dict[str, Any]) -> str:
    """우리 공격이 닿는 대상의 재질. 접촉 프레임의 소리를 고르는 값이다.

    엉킴 웨이브가 있으면 그 몸체 재질을, 구형 수호자 전투에는 전투 생성 때
    스냅샷한 값을 쓴다. 저장 중인 run이 카탈로그 변경에 흔들리지 않도록
    상태에 기록한 값을 우선한다.
    """

    wave = _current_wave(state)
    if wave is not None and wave.get("contact_material") in CONTACT_MATERIALS:
        return str(wave["contact_material"])
    material = state.get("contact_material")
    if material in CONTACT_MATERIALS:
        return str(material)
    return DEFAULT_CONTACT_MATERIAL


def new_guardian_battle(
    event_code: str,
    encounter: dict[str, Any],
    profiles: list[dict[str, Any]],
) -> dict[str, Any]:
    kel_map_version = CURRENT_KEL_MAP_VERSION
    element_kels = element_kel_map(kel_map_version)
    waves = _resolve_waves(encounter, kel_map_version=kel_map_version)
    boss_phases = _resolve_boss_phases(encounter, element_kels=element_kels)
    difficulty = difficulty_profile_for_encounter(encounter)
    growth_index, barrier_scale_bp = _party_growth_scale_bp(profiles)
    effective_barrier_scale_bp = (
        barrier_scale_bp * int(difficulty["barrier_bp"]) + 5_000
    ) // 10_000
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
        wave["barrier"] = scaled_power(
            int(wave["barrier"]), effective_barrier_scale_bp
        )
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
        barrier = scaled_power(base_barrier, effective_barrier_scale_bp)
        opening_caption = "돌비늘 장부지기가 길을 막았어요."
        if boss_phases:
            opening = boss_phases[0]
            weakness_cycle = list(opening["weakness_cycle"])
            weak_element = opening["weak_element"]
            resist_element = opening["resist_element"]
            opening_caption = (
                f"{opening_caption} "
                f"{opening.get('intro_caption', '첫 번째 봉인이 깨어났어요.')}"
            )
    # opening 기록서는 첫 명령 전에 한 번만 적용된다. 집중력은 파티가 나눠 쓰는
    # 자원이라 전투 하나에 한 번 더해지고, 상한은 책 문장대로 그대로 지킨다.
    opening = opening_modifiers(profiles)
    max_focus = max(1, max_focus + int(opening["max_focus"]))
    starting_focus = max(0, min(max_focus, starting_focus + int(opening["focus"])))

    return {
        "version": 3,
        "balance_version": COMBAT_BALANCE_VERSION,
        "skill_book_opening": opening,
        "difficulty_version": COMBAT_DIFFICULTY_VERSION,
        "difficulty": difficulty,
        "kel_map_version": kel_map_version,
        "event_code": event_code,
        "status": "active",
        "round": 1,
        "max_rounds": int(encounter.get("max_rounds", 6))
        + int(opening["max_rounds"]),
        "focus": starting_focus,
        "max_focus": max_focus,
        "configured_starting_focus": configured_focus,
        "starting_focus_level_bonus": starting_focus_level_bonus,
        "average_party_level": average_party_level,
        "enemy_kind": "tangle" if waves else "guardian",
        "contact_material": (
            encounter.get("contact_material")
            if encounter.get("contact_material") in CONTACT_MATERIALS
            else DEFAULT_CONTACT_MATERIAL
        ),
        "waves": waves,
        "wave_index": 0,
        "boss_phases": boss_phases,
        "boss_phase_index": 0,
        "boss_phase_gate_ready": False,
        "enemy_guard": barrier,
        "enemy_max_guard": barrier,
        "growth_index": growth_index,
        "barrier_scale_bp": barrier_scale_bp,
        "effective_barrier_scale_bp": effective_barrier_scale_bp,
        "weakness": weakness_cycle[0],
        "weak_element": weak_element,
        "resist_element": resist_element,
        "weak_kel": element_kels.get(str(weak_element)),
        "resist_kel": element_kels.get(str(resist_element)),
        "intent_index": 0,
        "party": [
            {
                "member_id": int(profile["id"]),
                "hp": _combat_hp_for_profile(profile),
                "max_hp": _combat_hp_for_profile(profile),
                "guard": 0,
                "cooldown_until_round": {},
                "ready_round": {},
                "statuses": {},
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
    boss_phase: dict[str, Any] | None = None,
    difficulty: dict[str, Any] | None = None,
) -> dict[str, Any]:
    intents = (
        (wave or {}).get("intents")
        or (boss_phase or {}).get("intents")
        or encounter.get("intents")
        or []
    )
    if not intents:
        presented = present_intent(
            {
                "code": "guardian_strike",
                "name": encounter.get("attack_name", "수호자의 공격"),
                "telegraph": encounter.get("telegraph", "공격을 준비하고 있어요."),
                "target": "front",
                "power": 1,
            }
        )
    else:
        presented = present_intent(dict(intents[index % len(intents)]))
    threat = difficulty or {}
    presented["power"] = int(presented.get("power", 1)) + int(
        threat.get("intent_power_bonus", 0)
    )
    if boss_phase is not None:
        presented["power"] = int(presented.get("power", 1)) + int(
            boss_phase.get("intent_power_bonus", 0)
        )
        presented["boss_phase"] = int(boss_phase.get("index", 1))
    mechanic = enemy_mechanic(
        presented.get("mechanic_code"),
        unlock_level=int(presented.get("mechanic_unlock", 1)),
        mechanic_level=int(threat.get("mechanic_level", 0)),
    )
    if mechanic is not None:
        presented["mechanic"] = mechanic
    return presented


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
    # 이번 라운드 예고는 선택 후보(누구에게 넘길까)를 정하는 데 필요해서 파티를
    # 돌기 전에 먼저 읽는다. 아래에서 그대로 다시 쓴다.
    wave = _current_wave(state)
    boss_phase = _current_boss_phase(state)
    payload_intent = _intent(
        encounter,
        int(state.get("intent_index", 0)),
        wave=wave,
        boss_phase=boss_phase,
        difficulty=state.get("difficulty"),
    )
    # 마무리 결심이 보는 장벽 비율과 고리수 기록부의 파티 보정. 파티를 돌기
    # 전에 한 번만 구한다.
    enemy_guard_bp = _enemy_guard_bp(state)
    party_unique2_power = int(
        (state.get("skill_book_opening") or {}).get("unique2_power", 0)
    )
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
                    enemy_guard_bp=enemy_guard_bp,
                    party_unique2_power=party_unique2_power,
                    choice_context=_battle_choice_context(
                        state,
                        member_state=member_state,
                        profile_by_id=profile_by_id,
                        intent=payload_intent,
                    ),
                ),
            }
        )
    intent = payload_intent
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
    required_member_ids = (
        [int(member_id) for member_id in pending.get("required_member_ids", [])]
        if isinstance(pending, dict) and "required_member_ids" in pending
        else living_ids
    )
    return {
        **copy.deepcopy(state),
        "kel_map_version": kel_map_version,
        "weakness_label": AFFINITY_LABELS.get(weakness, weakness),
        # 지역 BGM을 고를 값. 엉킴 전투에서는 현재 웨이브의 지역이고, 웨이브가
        # 없는 구형 수호자에는 없다(앱이 첫 지역 곡으로 떨어진다).
        "region_code": (wave or {}).get("region_code"),
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
            # 잔향 읽기 — 다음 라운드 예고를 미리 열어 준다. 공정한 선택 정보라
            # 숨기지 않고, 책을 쓰지 않은 전투에서는 아예 나타나지 않는다.
            "next_intent": (
                _intent(
                    encounter,
                    int(state.get("intent_index", 0)) + 1,
                    wave=wave,
                    boss_phase=boss_phase,
                )
                if intent_preview_open(state, round_number=int(state.get("round", 1)))
                else None
            ),
        },
        "wave": (
            {
                "index": int(state.get("wave_index", 0)) + 1,
                "count": len(state.get("waves") or []),
                "code": wave["code"],
                "name": wave["name"],
            }
            if wave
            else None
        ),
        "boss_phase": _boss_phase_payload(state),
        "threat": copy.deepcopy(state.get("difficulty") or {}),
        "pending_round": {
            "acted": acted,
            "awaiting": [
                member_id
                for member_id in required_member_ids
                if member_id not in acted and member_id in living_ids
            ],
            "weakness_hit": bool((pending or {}).get("weakness_hit", False)),
            "guard_actions": int((pending or {}).get("guard_actions", 0)),
        },
        "party": party,
    }


def _living_party(state: dict[str, Any]) -> list[dict[str, Any]]:
    return [member for member in state.get("party", []) if int(member["hp"]) > 0]


def _battle_choice_context(
    state: dict[str, Any],
    *,
    member_state: dict[str, Any],
    profile_by_id: dict[int, dict[str, Any]],
    intent: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    """그 전투를 봐야 아는 선택 후보를 한 곳에서 만든다.

    이 함수가 만든 목록이 앱에 그대로 내려가고, 명령이 들어올 때도 **같은
    목록으로** 판정한다. 만드는 곳과 판정하는 곳이 갈라지면 화면에 보인 것을
    골랐는데 거절당하는 일이 생긴다.
    """

    member_id = int(member_state["member_id"])
    living = _living_party(state)

    def name_of(other: dict[str, Any]) -> str:
        snapshot = (profile_by_id.get(int(other["member_id"])) or {}).get(
            "snapshot"
        ) or {}
        return str(snapshot.get("name") or other.get("name") or "탐험대원")

    # ── 누구에게 넘길까(아홉 꼬리의 잔상) ─────────────────────────────────
    # 전체 공격은 넘길 대상이라는 개념이 없다. 하나로 몰아 주면 전체기를 단일기로
    # 바꾸는 셈이라 후보를 비워 슬롯이 잠긴 채 보이게 한다.
    targeted = (
        [] if intent.get("target", "front") == "all" else _target_members(state, intent)
    )
    current_target = str(int(targeted[0]["member_id"])) if targeted else None
    member_options = (
        [
            {"value": str(int(other["member_id"])), "label": name_of(other)}
            for other in living
            if str(int(other["member_id"])) != current_target
        ]
        if targeted
        else []
    )

    # ── 어떤 책으로 바꿔 낄까(마음결 대백과) ──────────────────────────────
    loadout = ((profile_by_id.get(member_id) or {}).get("snapshot") or {}).get(
        "skill_loadout"
    ) or {}
    current_b1 = member_state.get("b1_override") or (
        (loadout.get("slots") or {}).get("B1") or {}
    ).get("code")
    # 파티 안에서 같은 책을 둘이 들 수 없다는 규칙은 전투 중 교체에도 그대로
    # 적용된다. 출발에서만 막고 여기서 뚫리면 규칙이 아니다.
    taken = _party_equipped_codes(state, list(profile_by_id.values()))
    # 읽는 순서는 이름순이다. 스냅샷이 어떤 순서로 얼렸든 화면에서는 늘 같은
    # 자리에 있어야 손이 기억한다.
    book_options = sorted(
        (
            {"value": code, "label": str(SKILL_BOOK_CATALOG[code]["name"])}
            for code in (loadout.get("owned_codes") or [])
            if code in SKILL_BOOK_CATALOG and code not in taken
        ),
        key=lambda option: option["label"],
    )

    return {
        "member": {"options": member_options, "current": current_target},
        "book": {"options": book_options, "current": current_b1},
    }


def _party_equipped_codes(
    state: dict[str, Any], profiles: list[dict[str, Any]]
) -> set[str]:
    """지금 파티가 실제로 끼고 있는 기록서 코드 전부.

    스냅샷의 두 칸과 전투 중 교체분을 함께 본다. `파티 안 중복 금지`를 전투 중
    교체에도 그대로 적용하려면 두 가지를 같이 봐야 한다.
    """

    override_by_member = {
        int(member["member_id"]): member.get("b1_override")
        for member in state.get("party", [])
    }
    codes: set[str] = set()
    for profile in profiles:
        member_id = int(profile.get("id", 0))
        slots = ((profile.get("snapshot") or {}).get("skill_loadout") or {}).get(
            "slots"
        ) or {}
        for slot, decision in slots.items():
            code = (decision or {}).get("code")
            # 교체된 첫 칸은 원래 책이 아니라 지금 낀 책이 자리를 차지한다.
            if slot == "B1" and override_by_member.get(member_id):
                continue
            if code:
                codes.add(str(code))
        if override := override_by_member.get(member_id):
            codes.add(str(override))
    return codes


def _enemy_guard_bp(state: dict[str, Any]) -> int:
    """남은 적 장벽을 만분율로. `장벽 20% 이하` 판정의 단일 원본이다.

    장벽이 0이면 전투가 이미 끝나 있으므로 0을 그대로 돌려준다.
    """

    maximum = max(1, int(state.get("enemy_max_guard", 1)))
    return max(0, int(state.get("enemy_guard", 0))) * 10_000 // maximum


def _target_members(
    state: dict[str, Any], intent: dict[str, Any]
) -> list[dict[str, Any]]:
    living = _living_party(state)
    target = intent.get("target", "front")
    if target == "all":
        return living
    # 아홉 꼬리의 잔상 — 이 라운드에 한해 예고된 공격을 다른 대원이 받는다.
    # 넘겨받은 대원이 그 사이 쓰러졌으면 원래 규칙으로 돌아간다.
    retarget = _retargeted_member_id(state)
    if retarget is not None:
        for member in living:
            if int(member["member_id"]) == retarget:
                return [member]
    if target == "lowest":
        return [min(living, key=lambda item: (int(item["hp"]), item["member_id"]))]
    return [living[0]]


def _retargeted_member_id(state: dict[str, Any]) -> int | None:
    """이번 라운드에 예고를 넘겨받은 대원. 라운드가 지나면 저절로 풀린다."""

    handoff = book_state(state).get("intent_target")
    if not isinstance(handoff, dict):
        return None
    if int(handoff.get("round", 0)) != int(state.get("round", 1)):
        return None
    return int(handoff.get("member_id", 0)) or None


def _pending_round(state: dict[str, Any]) -> dict[str, Any] | None:
    pending = state.get("pending")
    return pending if isinstance(pending, dict) else None


def _begin_round_if_needed(state: dict[str, Any]) -> dict[str, Any]:
    """라운드의 첫 행동 직전에 방어를 정리하고 진행 중 상태를 만든다."""

    pending = _pending_round(state)
    if pending is not None:
        return pending
    # 방어는 라운드 단위다. 지난 적 행동 뒤 남은 수치를 다음 라운드에 이월하지
    # 않는다 — `두 겹 잎방패`를 든 대원만 남은 방어 1칸을 가져간다.
    carry = (state.get("skill_book_opening") or {}).get("guard_carry") or {}
    for member in state.get("party", []):
        leftover = int(member.get("guard", 0))
        keep = int(carry.get(str(int(member["member_id"])), 0))
        member["guard"] = min(leftover, keep)
    pending = {
        "acted": [],
        "required_member_ids": [
            int(member["member_id"]) for member in _living_party(state)
        ],
        "intent_power_delta": 0,
        "weakness_hit": False,
        "guard_actions": 0,
    }
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
    encounter: dict[str, Any],
) -> dict[str, Any]:
    """대원 한 명의 행동을 해석해 상태를 바꾸고 이벤트 하나를 돌려준다.

    일괄 라운드와 순차 명령이 같은 함수를 지나므로 두 입력 방식의 판정
    결과는 정의상 동일하다.
    """

    pending = _begin_round_if_needed(state)
    member_id = int(command.get("member_id", 0))
    requested_action = command.get("action")
    choice = command.get("choice")
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
    # 발아 시계의 태엽 — 집중력 +2를 받은 대가로 1라운드에 스킬을 쓸 수 없다.
    # 기본 공격과 마음 지키기는 남겨 둔다. `집중력 0~5에서 최소 한 행동은 항상
    # 합법`이라는 밸런스 불변식을 반대급부가 깨뜨리면 안 되기 때문이다.
    if (
        action in SKILL_ACTIONS
        and int(state.get("round", 1)) <= 1
        and member_id
        in {
            int(value)
            for value in (state.get("skill_book_opening") or {}).get(
                "first_round_skill_locked", []
            )
        }
    ):
        raise CombatRuleError(
            "EXPEDITION_COMBAT_FIRST_ROUND_SKILL_LOCKED",
            "태엽을 감는 동안이라 첫 라운드에는 기본 공격과 마음 지키기만 쓸 수 있어요.",
        )
    # 고리수 기록부 — 파티 전원이 고유 II를 +4 받는 대가로, 장착자는 그 전투
    # 내내 몸을 뺄 수 없다. 라운드가 아니라 전투 단위다.
    if action == "guard" and member_id in {
        int(value)
        for value in (state.get("skill_book_opening") or {}).get("guard_locked", [])
    }:
        raise CombatRuleError(
            "EXPEDITION_COMBAT_GUARD_LOCKED",
            "고리수를 세는 동안이라 이 전투에서는 마음 지키기를 쓸 수 없어요.",
        )
    # 아홉 꼬리의 잔상 — 예고를 넘겨받은 대원은 그 라운드에 몸을 뺄 수 없다.
    if action == "guard" and _retargeted_member_id(state) == member_id:
        raise CombatRuleError(
            "EXPEDITION_COMBAT_GUARD_BLOCKED",
            "잔상을 대신 받은 대원이라 이번 라운드에는 마음 지키기를 쓸 수 없어요.",
        )
    # 마음결 대백과 — 책을 바꿔 낀 라운드에는 스킬이 잠긴다. 기본 공격과 마음
    # 지키기는 남겨 `최소 한 행동은 항상 합법` 불변식을 지킨다.
    if (
        action in SKILL_ACTIONS
        and int(member_state.get("skill_blocked_round", 0))
        == int(state.get("round", 1))
    ):
        raise CombatRuleError(
            "EXPEDITION_COMBAT_SKILL_BLOCKED",
            "기록서를 바꿔 끼는 중이라 이번 라운드에는 기본 공격과 마음 지키기만 쓸 수 있어요.",
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
        enemy_guard_bp=_enemy_guard_bp(state),
        party_unique2_power=int(
            (state.get("skill_book_opening") or {}).get("unique2_power", 0)
        ),
        choice_context=_battle_choice_context(
            state,
            member_state=member_state,
            profile_by_id=profile_by_id,
            intent=_intent(
                encounter,
                int(state.get("intent_index", 0)),
                wave=_current_wave(state),
                boss_phase=_current_boss_phase(state),
                difficulty=state.get("difficulty"),
            ),
        ),
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
    effect_values: dict[str, int] = {}
    mechanic_summary = ""
    presentation_tier = 1
    vfx_intensity = 0.86
    audio_layer = "light"
    camera_profile = "steady"
    emotion_vfx_primary = None
    emotion_vfx_secondary = None
    caption = ""

    # 전투당 한 번 터지는 기록서 트리거. 상한은 여기서 함께 지킨다.
    trigger_focus, trigger_code = focus_trigger(
        profile.get("snapshot") or {},
        action=str(action),
        fired=state.get("skill_book_triggers") or {},
        member_id=member_id,
    )
    if trigger_code is not None:
        state.setdefault("skill_book_triggers", {})[
            f"{member_id}:{trigger_code}"
        ] = True

    if action == "guard":
        focus = min(
            max_focus,
            focus + int(kit["guard"]["focus_delta"]) + trigger_focus,
        )
        member_state["guard"] = int(kit["guard"]["guard"])
        pending["guard_actions"] = int(pending.get("guard_actions", 0)) + 1
        action_name = kit["guard"]["name"]
        caption = f"{korean_subject(actor_name)} 마음을 다잡고 공격에 대비했어요."
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
                # 전투당 1회짜리는 남은 턴 수를 세어 봐야 의미가 없다.
                # `99턴 뒤`가 아니라 이 전투에서 끝났다고 말해야 읽힌다.
                once_per_battle = remaining >= int(state.get("max_rounds", 6))
                raise CombatRuleError(
                    "EXPEDITION_COMBAT_COOLDOWN",
                    f"{korean_topic(action_name)} 이 전투에서 한 번만 쓸 수 있어요."
                    if once_per_battle
                    else f"{korean_topic(action_name)} {remaining}턴 뒤 다시 사용할 수 있어요.",
                )
            # 고를 것이 있는 기록서는 무엇을 골랐는지 먼저 본다. 집중력을
            # 쓰기 전에 막아야 잘못 고른 선택으로 자원이 사라지지 않는다.
            book = action_data.get("equipped_book")
            if book is not None:
                problem = validate_choice(
                    str(book["code"]),
                    choice if isinstance(choice, str) else None,
                    current=action_data.get("choice_current"),
                    # 앱에 내려보낸 바로 그 목록으로 판정한다.
                    allowed=[
                        str(option["value"])
                        for option in action_data.get("choice_options") or []
                    ],
                )
                if problem:
                    raise CombatRuleError(
                        "EXPEDITION_COMBAT_CHOICE_REQUIRED", problem
                    )
            cost = int(action_data["focus_cost"])
            if focus < cost:
                raise CombatRuleError(
                    "EXPEDITION_COMBAT_FOCUS_SHORTAGE",
                    f"{actor_name}의 스킬에 필요한 집중력이 부족해요.",
                )
            focus -= cost
            # 집중의 매듭 — 스킬을 쓴 뒤 한 칸 돌려받는다. 비용을 낸 뒤에
            # 더해야 `쓸 수 있는지` 판정이 트리거로 느슨해지지 않는다.
            focus = min(max_focus, focus + trigger_focus)
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
        # 고른 결은 공격 한 번까지다. 실제로 때린 뒤 지워야 `다음 공격 하나`라는
        # 약속이 지켜진다. 프리즘 스킬은 결을 받지 않았으므로 그대로 남겨 둔다.
        if member_state.get("kel_override") and action_kel == member_state.get(
            "kel_override"
        ):
            member_state.pop("kel_override", None)
        action_kels = [str(item) for item in action_data.get("kels", [])]
        fusion_variant = action_data.get("fusion_variant")
        fusion_vfx_family = action_data.get("fusion_vfx_family")
        effect_values = {
            str(key): int(value)
            for key, value in dict(action_data.get("effect_values") or {}).items()
        }
        mechanic_summary = str(action_data.get("mechanic_summary") or "")
        presentation_tier = int(action_data.get("presentation_tier", 1))
        vfx_intensity = float(action_data.get("vfx_intensity", 0.86))
        audio_layer = str(action_data.get("audio_layer", "light"))
        camera_profile = str(action_data.get("camera_profile", "steady"))
        emotion_vfx_primary = action_data.get("emotion_vfx_primary")
        emotion_vfx_secondary = action_data.get("emotion_vfx_secondary")
        power_neutral = int(action_data.get("power_neutral", action_data["power"]))
        matchup_bp = int(action_data.get("matchup_bp", 10_000))
        damage = int(action_data["power"])
        # 지휘 버프와 적 취약은 사용한 스킬 자신이 아니라 같은 라운드의
        # 뒤쪽 행동부터 적용된다. 행동 순서를 고르는 이유가 실제 판정에 남는다.
        damage = scaled_power(damage, int(pending.get("party_power_bp", 10_000)))
        damage = scaled_power(
            damage, int(pending.get("enemy_vulnerability_bp", 10_000))
        )
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
        if weakness_hit:
            pending["weakness_hit"] = True
        effect = action_data.get("effect")
        if effect == "shield_all":
            for target in _living_party(state):
                target["guard"] = int(target["guard"]) + int(
                    effect_values.get("party_guard", 1)
                )
        elif effect == "focus_refund":
            focus = min(max_focus, focus + int(effect_values.get("focus_refund", 1)))
        elif effect == "heal_lowest":
            target = min(
                _living_party(state),
                key=lambda item: (int(item["hp"]), item["member_id"]),
            )
            target["hp"] = min(
                int(target["max_hp"]),
                int(target["hp"]) + int(effect_values.get("heal_lowest", 1)),
            )
            target["guard"] = int(target["guard"]) + int(
                effect_values.get("target_guard", 0)
            )
        elif effect == "book_intent_preview":
            # 다음 라운드 예고를 한 라운드 동안 미리 볼 수 있게 연다.
            book_state(state)["intent_preview_until_round"] = round_number + int(
                effect_values.get("intent_preview_rounds", 1)
            )
        elif effect == "book_weakness_engrave":
            # 다음 약점 일치 공격에 실릴 추가 피해를 적어 둔다.
            book_state(state)["weakness_bonus"] = int(
                effect_values.get("weakness_bonus", 3)
            )
        elif effect == "book_kel_override":
            # 고른 결은 이 대원의 다음 공격 한 번에만 실린다. 키트가 다음 라운드에
            # 이 값을 읽어 상성을 다시 계산하므로 확정 전에 예상 피해가 보인다.
            if isinstance(choice, str) and choice:
                member_state["kel_override"] = choice
        elif effect == "book_intent_retarget":
            # 예고된 공격을 이 라운드에 한해 다른 대원이 받는다. 넘겨받은 대원은
            # 그 라운드에 마음 지키기를 쓸 수 없다 — 설계서의 반대급부다.
            if isinstance(choice, str) and choice.isdigit():
                book_state(state)["intent_target"] = {
                    "round": round_number,
                    "member_id": int(choice),
                }
        elif effect == "book_swap_b1":
            # 첫 칸을 이 전투 동안 다른 책으로 바꿔 낀다. 대신 바꾼 라운드에는
            # 스킬을 쓸 수 없다. 스냅샷은 건드리지 않아 런이 끝나면 원래 장착이다.
            if isinstance(choice, str) and choice:
                member_state["b1_override"] = choice
                member_state["skill_blocked_round"] = round_number
        elif effect == "book_revive_one":
            # HP 0 대원 1명을 HP 1로 복귀. 정액이라 등급·tier로 자라지 않는다.
            downed = sorted(
                (
                    target
                    for target in state.get("party", [])
                    if int(target["hp"]) <= 0
                ),
                key=lambda item: int(item["member_id"]),
            )
            revived = int(effect_values.get("revive_count", 1))
            for target in downed[:revived]:
                target["hp"] = max(1, int(effect_values.get("revive_hp", 1)))
        elif effect == "guard_self":
            member_state["guard"] = int(member_state["guard"]) + int(
                effect_values.get("self_guard", 2)
            )
        elif (
            not modern_matchup
            and effect == "last_stand"
            and int(member_state["hp"]) == 1
        ):
            damage += 8
        elif effect == "weaken_intent":
            pending["intent_power_delta"] = int(
                pending.get("intent_power_delta", 0)
            ) + int(effect_values.get("intent_power_delta", -1))
        elif not modern_matchup and effect == "weakness_pierce" and weakness_hit:
            damage += 6
        elif not modern_matchup and effect == "steady_read" and not weakness_hit:
            damage += 5
        elif effect == "study_refund":
            focus = min(max_focus, focus + int(effect_values.get("focus_refund", 2)))
        elif effect == "triage_heal":
            target = min(
                _living_party(state),
                key=lambda item: (int(item["hp"]), item["member_id"]),
            )
            target["hp"] = min(
                int(target["max_hp"]),
                int(target["hp"]) + int(effect_values.get("heal_lowest", 2)),
            )
            target["guard"] = int(target["guard"]) + int(
                effect_values.get("target_guard", 0)
            )
        elif effect == "white_garden_oath":
            revive_count = int(effect_values.get("revive_count", 0))
            if revive_count > 0:
                downed = sorted(
                    (
                        target
                        for target in state.get("party", [])
                        if int(target["hp"]) <= 0
                    ),
                    key=lambda item: int(item["member_id"]),
                )
                for target in downed[:revive_count]:
                    target["hp"] = min(
                        int(target["max_hp"]),
                        max(1, int(effect_values.get("revive_hp", 1))),
                    )
            living = _living_party(state)
            heal_all = int(effect_values.get("heal_all", 0))
            party_guard = int(effect_values.get("party_guard", 0))
            for target in living:
                target["hp"] = min(int(target["max_hp"]), int(target["hp"]) + heal_all)
                target["guard"] = int(target["guard"]) + party_guard
            heal_lowest = int(effect_values.get("heal_lowest", 0))
            if heal_lowest > 0 and living:
                target = min(
                    living, key=lambda item: (int(item["hp"]), item["member_id"])
                )
                target["hp"] = min(
                    int(target["max_hp"]), int(target["hp"]) + heal_lowest
                )
        elif effect == "resonance_boost":
            pending["party_power_bp"] = max(
                int(pending.get("party_power_bp", 10_000)),
                int(effect_values.get("party_power_bp", 10_000)),
            )
            focus = min(max_focus, focus + int(effect_values.get("focus_refund", 0)))
        elif effect == "silent_coda":
            pending["intent_power_delta"] = int(
                pending.get("intent_power_delta", 0)
            ) + int(effect_values.get("intent_power_delta", -1))
            pending["enemy_vulnerability_bp"] = max(
                int(pending.get("enemy_vulnerability_bp", 10_000)),
                int(effect_values.get("enemy_vulnerability_bp", 10_000)),
            )
        elif effect == "patina_parry":
            member_state["guard"] = int(member_state["guard"]) + int(
                effect_values.get("self_guard", 0)
            )
            pending["intent_power_delta"] = int(
                pending.get("intent_power_delta", 0)
            ) + int(effect_values.get("intent_power_delta", 0))
        elif effect == "golden_seam":
            living = _living_party(state)
            if living:
                target = min(
                    living, key=lambda item: (int(item["hp"]), item["member_id"])
                )
                target["hp"] = min(
                    int(target["max_hp"]),
                    int(target["hp"]) + int(effect_values.get("heal_lowest", 0)),
                )
                for ally in living:
                    ally["guard"] = int(ally["guard"]) + int(
                        effect_values.get("party_guard", 0)
                    )
            focus = min(max_focus, focus + int(effect_values.get("focus_refund", 0)))
        elif effect == "softpaw_rush":
            pending["enemy_vulnerability_bp"] = max(
                int(pending.get("enemy_vulnerability_bp", 10_000)),
                int(effect_values.get("enemy_vulnerability_bp", 10_000)),
            )
            member_state["guard"] = int(member_state["guard"]) + int(
                effect_values.get("self_guard", 0)
            )
        elif effect == "den_guardian_roar":
            for target in _living_party(state):
                target["guard"] = int(target["guard"]) + int(
                    effect_values.get("party_guard", 0)
                )
            pending["party_power_bp"] = max(
                int(pending.get("party_power_bp", 10_000)),
                int(effect_values.get("party_power_bp", 10_000)),
            )
            focus = min(max_focus, focus + int(effect_values.get("focus_refund", 0)))
        elif effect == "patchwork_relay":
            pending["party_power_bp"] = max(
                int(pending.get("party_power_bp", 10_000)),
                int(effect_values.get("party_power_bp", 10_000)),
            )
            focus = min(max_focus, focus + int(effect_values.get("focus_refund", 0)))
        elif effect == "runway_reversal":
            pending["party_power_bp"] = max(
                int(pending.get("party_power_bp", 10_000)),
                int(effect_values.get("party_power_bp", 10_000)),
            )
        # 레벨 성장 기믹은 effect 종류와 독립된 공통 키로 정규화한다. 고유기
        # 전용 처리와 중복되지 않고, 서버 이벤트·상세 UI에도 같은 수치가 남는다.
        focus = min(
            max_focus,
            focus + int(effect_values.get("tier_focus_refund", 0)),
        )
        member_state["guard"] = int(member_state["guard"]) + int(
            effect_values.get("tier_self_guard", 0)
        )
        member_state["hp"] = min(
            int(member_state["max_hp"]),
            int(member_state["hp"]) + int(effect_values.get("tier_self_heal", 0)),
        )
        for target in _living_party(state):
            target["guard"] = int(target["guard"]) + int(
                effect_values.get("tier_party_guard", 0)
            )
        pending["party_power_bp"] = max(
            int(pending.get("party_power_bp", 10_000)),
            int(effect_values.get("tier_party_power_bp", 10_000)),
        )
        pending["enemy_vulnerability_bp"] = max(
            int(pending.get("enemy_vulnerability_bp", 10_000)),
            int(effect_values.get("tier_enemy_vulnerability_bp", 10_000)),
        )
        pending["intent_power_delta"] = int(pending.get("intent_power_delta", 0)) + int(
            effect_values.get("tier_intent_power_delta", 0)
        )
        if weakness_hit:
            focus = min(
                max_focus,
                focus + int(effect_values.get("tier_focus_refund_on_weakness", 0)),
            )
            member_state["guard"] = int(member_state["guard"]) + int(
                effect_values.get("tier_self_guard_on_weakness", 0)
            )
            pending["party_power_bp"] = max(
                int(pending.get("party_power_bp", 10_000)),
                int(effect_values.get("tier_party_power_bp_on_weakness", 10_000)),
            )
            pending["enemy_vulnerability_bp"] = max(
                int(pending.get("enemy_vulnerability_bp", 10_000)),
                int(
                    effect_values.get("tier_enemy_vulnerability_bp_on_weakness", 10_000)
                ),
            )
        else:
            member_state["guard"] = int(member_state["guard"]) + int(
                effect_values.get("tier_self_guard_on_nonweak", 0)
            )
            pending["intent_power_delta"] = int(
                pending.get("intent_power_delta", 0)
            ) + int(effect_values.get("tier_intent_power_delta_on_nonweak", 0))
        if resistance_hit:
            focus = min(
                max_focus,
                focus + int(effect_values.get("tier_focus_refund_on_resist", 0)),
            )
            member_state["guard"] = int(member_state["guard"]) + int(
                effect_values.get("tier_self_guard_on_resist", 0)
            )
        critical = int(member_state["hp"]) <= max(
            1, (int(member_state["max_hp"]) + 2) // 3
        )
        if critical:
            member_state["guard"] = int(member_state["guard"]) + int(
                effect_values.get("tier_self_guard_when_critical", 0)
            )
            member_state["hp"] = min(
                int(member_state["max_hp"]),
                int(member_state["hp"])
                + int(effect_values.get("tier_self_heal_when_critical", 0)),
            )
            pending["intent_power_delta"] = int(
                pending.get("intent_power_delta", 0)
            ) + int(effect_values.get("tier_intent_power_delta_when_critical", 0))
        if any(
            int(target["hp"]) < int(target["max_hp"]) for target in _living_party(state)
        ):
            focus = min(
                max_focus,
                focus
                + int(effect_values.get("tier_focus_refund_when_ally_wounded", 0)),
            )
        if damage == enemy_before:
            focus = min(
                max_focus,
                focus
                + int(effect_values.get("tier_focus_refund_on_exact_finisher", 0)),
            )
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
        # 약점 각인 — 기다리던 추가 피해는 약점을 실제로 맞힌 공격에만 실린다.
        if weakness_hit and damage > 0:
            damage += take_weakness_bonus(state)
        damage = _cap_boss_damage_at_next_phase(state, damage)
        state["enemy_guard"] = max(0, enemy_before - damage)
        if weakness_hit:
            caption = f"{actor_name}의 {action_name}! 약점을 꿰뚫어 장벽 {damage} 피해."
        elif resistance_hit:
            caption = (
                f"{actor_name}의 {action_name}! 내성에 막혔지만 장벽 {damage} 피해."
            )
        else:
            caption = f"{actor_name}의 {action_name}! 장벽 {damage} 피해."
        if mechanic_summary:
            caption = f"{caption} {mechanic_summary}."

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
            # 지키기는 우리 쪽에서 받아 내는 소리라 대상 재질을 쓰지 않는다.
            "contact_material": (
                "guard" if action == "guard" else target_contact_material(state)
            ),
            "element": action_element,
            "elements": action_elements,
            "kel": action_kel,
            "kels": action_kels,
            "fusion_variant": fusion_variant,
            "fusion_vfx_family": fusion_vfx_family,
            "effect_values": effect_values,
            "mechanic_summary": mechanic_summary,
            "presentation_tier": presentation_tier,
            "vfx_intensity": vfx_intensity,
            "audio_layer": audio_layer,
            "camera_profile": camera_profile,
            "emotion_vfx_primary": emotion_vfx_primary,
            "emotion_vfx_secondary": emotion_vfx_secondary,
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
            # 이 장벽이 무슨 결이었는지. `장벽 3종 열기` 같은 조건은 횟수가
            # 아니라 가짓수를 묻는데, 전투가 끝나면 이 값이 사라진다.
            "enemy_weak_kel": state.get("weak_kel"),
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
    boss_phase = _current_boss_phase(state)
    intent = _intent(
        encounter,
        int(state.get("intent_index", 0)),
        wave=wave,
        boss_phase=boss_phase,
        difficulty=state.get("difficulty"),
    )
    mechanic = intent.get("mechanic") if isinstance(intent.get("mechanic"), dict) else None
    mechanic_triggered = False
    mechanic_power_bonus = 0
    if mechanic is not None:
        trigger = mechanic.get("trigger")
        mechanic_triggered = (
            trigger == "no_weakness_hit" and not bool(pending.get("weakness_hit"))
        ) or (
            trigger == "no_guard_action" and int(pending.get("guard_actions", 0)) <= 0
        )
        if mechanic_triggered and mechanic.get("effect") == "power_bonus":
            mechanic_power_bonus = int(mechanic.get("value", 0))
    power = max(
        0,
        int(intent.get("power", 1)) + intent_power_delta + mechanic_power_bonus,
    )
    targets = _target_members(state, intent)
    target_events = []
    profile_names = {
        member_id: profile.get("snapshot", {}).get("name", "탐험대원")
        for member_id, profile in profile_by_id.items()
    }
    for target in targets:
        guard_before = int(target.get("guard", 0))
        statuses = target.setdefault("statuses", {})
        status_power = int(statuses.get("exposed", 0))
        target_power = power + status_power
        blocked = min(guard_before, target_power)
        raw_damage = max(0, target_power - blocked)
        hit_cap_bp = int(
            (state.get("difficulty") or {}).get("single_hit_cap_bp", 10_000)
        )
        damage_cap = max(1, (int(target["max_hp"]) * hit_cap_bp + 9_999) // 10_000)
        damage = min(raw_damage, damage_cap)
        # 흔들리지 않는 축 — 적이 **전원을 노릴 때만** 정액 1을 덜어 낸다.
        # 상한을 적용한 뒤에 뺀다. `피해 −1`은 실제로 깎이는 체력에 대한
        # 약속이고, 상한 앞에서 빼면 상한에 먹혀 아무 일도 안 일어난다.
        if intent.get("target") == "all":
            damage = max(
                0,
                damage
                - all_hit_reduction(
                    (profile_by_id.get(int(target["member_id"])) or {}).get("snapshot")
                ),
            )
        target["guard"] = max(0, guard_before - target_power)
        target["hp"] = max(0, int(target["hp"]) - damage)
        # 빈틈은 다음으로 실제 적중한 공격 한 번에만 소비한다.
        if status_power > 0:
            remaining_exposed = max(0, status_power - 1)
            if remaining_exposed:
                statuses["exposed"] = remaining_exposed
            else:
                statuses.pop("exposed", None)
        target_events.append(
            {
                "member_id": int(target["member_id"]),
                "name": profile_names[int(target["member_id"])],
                "damage": damage,
                "blocked": blocked,
                "hp_after": int(target["hp"]),
                **({"damage_capped": True} if damage < raw_damage else {}),
            }
        )
    unblocked = any(int(target["damage"]) > 0 for target in target_events)
    if mechanic is not None and mechanic.get("trigger") == "on_unblocked":
        mechanic_triggered = unblocked
    mechanic_caption = None
    if mechanic_triggered and mechanic is not None:
        mechanic_value = int(mechanic.get("value", 0))
        if mechanic.get("effect") == "focus_drain":
            before = int(state.get("focus", 0))
            state["focus"] = max(0, before - mechanic_value)
            mechanic_caption = f"{mechanic['name']}로 집중력이 {before - int(state['focus'])} 줄었어요."
        elif mechanic.get("effect") == "expose":
            for target, result in zip(targets, target_events, strict=True):
                if int(result["damage"]) <= 0:
                    continue
                statuses = target.setdefault("statuses", {})
                statuses["exposed"] = min(
                    1, int(statuses.get("exposed", 0)) + mechanic_value
                )
            mechanic_caption = f"{mechanic['name']}이 남아 다음 피격 위력이 1 높아져요."
        elif mechanic.get("effect") == "barrier_mend":
            before = int(state["enemy_guard"])
            state["enemy_guard"] = min(
                int(state["enemy_max_guard"]), before + mechanic_value
            )
            repaired = int(state["enemy_guard"]) - before
            if repaired > 0:
                mechanic_caption = f"{mechanic['name']}이 장벽을 {repaired} 복구했어요."
        elif mechanic.get("effect") == "power_bonus":
            mechanic_caption = f"{mechanic['name']}의 파훼에 실패해 위력이 {mechanic_value} 높아졌어요."
    phase_gate = (boss_phase or {}).get("phase_gate")
    if phase_gate == "resolve_intent":
        state["boss_phase_gate_ready"] = True
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
                "contact_material": intent["contact_material"],
                "kel_map_version": _battle_kel_map_version(state),
                "enemy_guard_before": int(state["enemy_guard"]),
                "enemy_guard_after": int(state["enemy_guard"]),
                "targets": target_events,
                "mechanic": copy.deepcopy(mechanic),
                "mechanic_triggered": mechanic_triggered,
                "mechanic_caption": mechanic_caption,
                "caption": intent.get("telegraph", "수호자의 공격이 밀려왔어요."),
            },
        )
    )
    if mechanic_caption:
        events[-1]["caption"] = f"{events[-1]['caption']} {mechanic_caption}"
    if not _living_party(state):
        state["status"] = "defeat"
        state["defeat_reason"] = "party_down"
    elif int(state["round"]) >= int(state["max_rounds"]):
        state["status"] = "defeat"
        state["defeat_reason"] = "seal_completed"
    else:
        weakness_cycle = list(
            (wave or {}).get("weakness_cycle")
            or (boss_phase or {}).get("weakness_cycle")
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
                    # 풀려남 cadence는 지역마다 다른 두 음이다. 앱이 지도 문맥
                    # 없이도 고를 수 있게 이벤트에 지역을 함께 실어 보낸다.
                    "region_code": wave.get("region_code"),
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
    region_code = (wave or {}).get("region_code")
    return [
        _push_event(
            state,
            {
                "type": "outcome",
                "outcome": "victory",
                # 엉킴 전투에서만 풀려남 cadence를 고를 지역이 있다. 구형 수호자
                # 응답에는 없던 키를 새로 만들지 않는다.
                **({"region_code": region_code} if region_code else {}),
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
        phase_before = int(state.get("boss_phase_index", 0))
        events.append(
            _apply_member_command(state, command, profile_by_id, encounter)
        )
        if int(state["enemy_guard"]) <= 0:
            events.extend(_enemy_cleared_events(state))
            round_over = True
            break
        events.extend(_advance_boss_phase(state))
        if int(state.get("boss_phase_index", 0)) != phase_before:
            # 새 상성과 예고를 본 뒤 다음 라운드에 대응하게 한다.
            state["pending"] = None
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
    phase_before = int(state.get("boss_phase_index", 0))
    events = [_apply_member_command(state, command, profile_by_id, encounter)]
    if int(state["enemy_guard"]) <= 0:
        events.extend(_enemy_cleared_events(state))
    else:
        events.extend(_advance_boss_phase(state))
        if int(state.get("boss_phase_index", 0)) != phase_before:
            # 페이즈 전환은 한 번의 결과 사건이다. 새 공격은 다음 명령 라운드에서
            # 예고하므로 사용자가 보지 못한 패턴에 즉시 맞지 않는다.
            state["pending"] = None
            state["last_exchange"] = events
            _extend_log(state, events)
            return state
        pending = _pending_round(state) or {"acted": []}
        required_member_ids = {
            int(item)
            for item in pending.get(
                "required_member_ids",
                [member["member_id"] for member in _living_party(state)],
            )
        }
        if required_member_ids <= set(int(item) for item in pending.get("acted", [])):
            events.extend(_finalize_round(state, encounter, profile_by_id))
    state["last_exchange"] = events
    _extend_log(state, events)
    return state
