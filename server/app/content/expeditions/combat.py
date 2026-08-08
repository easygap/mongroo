"""탐험 수호전의 결정론적 전투 규칙.

HTTP와 데이터베이스에 의존하지 않는다. 클라이언트가 보낸 행동 순서를 그대로
계산하고, 같은 전투 상태와 명령에는 항상 같은 결과를 돌려준다. 전투 밸런스와
표시용 수치는 이 파일에서 함께 관리해 서버 판정과 UI 설명이 어긋나지 않게 한다.
"""

from __future__ import annotations

import copy
from typing import Any

from app.content.expeditions.tangles import tangle_definition


AFFINITIES = ("care", "focus", "courage", "insight")
AFFINITY_LABELS = {
    "care": "돌봄",
    "focus": "집중",
    "courage": "용기",
    "insight": "관찰",
}
AFFINITY_EFFECTS = {
    "care": "care_vines",
    "focus": "prism_burst",
    "courage": "ember_arc",
    "insight": "insight_arc",
}
FORM_AFFINITIES = {
    "sunny": "care",
    "rainy": "focus",
    "ember": "courage",
    "moonlit": "insight",
    "sparkling": "focus",
}

# 고유 스킬은 한 줄짜리 피해량 차이가 아니라 캐릭터를 고르는 이유를 만든다.
# power에는 해당 감정 능력치가 더해지고, 약점을 맞히면 별도 보너스가 붙는다.
SPECIES_SKILLS: dict[str, dict[str, Any]] = {
    "baby-pot": {
        "code": "sprout_cheer",
        "name": "새싹 응원",
        "description": "공격 후 모두에게 피해를 한 번 막는 잎사귀 보호막을 줘요.",
        "power": 14,
        "focus_cost": 2,
        "effect": "shield_all",
    },
    "handsome-pot": {
        "code": "warm_command",
        "name": "온기 지휘",
        "description": "공명 공격을 지휘하고 집중력 1을 되돌려 받아요.",
        "power": 17,
        "focus_cost": 2,
        "effect": "focus_refund",
    },
    "pretty-pot": {
        "code": "bloom_step",
        "name": "개화의 스텝",
        "description": "장벽을 흔든 뒤 가장 지친 동료의 체력을 1 회복해요.",
        "power": 15,
        "focus_cost": 2,
        "effect": "heal_lowest",
    },
    "tsundere-pot": {
        "code": "not_for_you_guard",
        "name": "착각하지 마 방패",
        "description": "강하게 받아치고 자신에게 두 겹의 방어를 둘러요.",
        "power": 16,
        "focus_cost": 2,
        "effect": "guard_self",
    },
    "zombie-pot": {
        "code": "unyielding_grab",
        "name": "끈질긴 붙잡기",
        "description": "체력이 1이면 위력이 크게 오르는 집념의 공격이에요.",
        "power": 18,
        "focus_cost": 2,
        "effect": "last_stand",
    },
    "gumiho-pot": {
        "code": "foxfire_feint",
        "name": "여우불 미혹",
        "description": "장벽을 홀리고 이번 라운드 수호자의 공격력을 낮춰요.",
        "power": 16,
        "focus_cost": 2,
        "effect": "weaken_intent",
    },
    "ninja-pot": {
        "code": "shadow_seam",
        "name": "그림자 틈베기",
        "description": "약점을 맞히면 장벽을 추가로 크게 찢어요.",
        "power": 18,
        "focus_cost": 2,
        "effect": "weakness_pierce",
    },
    "magical-pot": {
        "code": "prism_answer",
        "name": "프리즘 해답",
        "description": "현재 드러난 약점과 같은 공명으로 공격해요.",
        "power": 15,
        "focus_cost": 3,
        "effect": "prism_shift",
    },
    "aloof-pot": {
        "code": "cold_read",
        "name": "냉정한 간파",
        "description": "상성이 불리해도 빈틈을 읽어 피해 감소를 줄여요.",
        "power": 17,
        "focus_cost": 2,
        "effect": "steady_read",
    },
    "student-pot": {
        "code": "calculated_answer",
        "name": "계산된 해답",
        "description": "공격 뒤 집중력을 2 회복해 다음 행동을 준비해요.",
        "power": 14,
        "focus_cost": 2,
        "effect": "study_refund",
    },
    "archive_guide": {
        "code": "lantern_cover",
        "name": "기록 등불",
        "description": "공격과 함께 탐험대 전체에 얕은 보호막을 둘러요.",
        "power": 12,
        "focus_cost": 2,
        "effect": "shield_all",
    },
}


class CombatRuleError(ValueError):
    """클라이언트가 복구 가능한 전투 명령 오류."""

    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def _stats(profile: dict[str, Any]) -> dict[str, int]:
    raw = profile.get("snapshot", {}).get("stats", {})
    return {key: int(raw.get(key, 0)) for key in AFFINITIES}


def _member_affinity(profile: dict[str, Any]) -> str:
    form = profile.get("snapshot", {}).get("form", "mosaic")
    if form in FORM_AFFINITIES:
        return FORM_AFFINITIES[form]
    stats = _stats(profile)
    # 동률일 때도 서버 버전이나 dict 순서에 영향받지 않도록 고정 순서를 쓴다.
    return max(AFFINITIES, key=lambda key: (stats[key], -AFFINITIES.index(key)))


def member_battle_kit(
    profile: dict[str, Any], *, current_weakness: str | None = None
) -> dict[str, Any]:
    snapshot = profile.get("snapshot", {})
    species_code = snapshot.get("species", {}).get("code", "archive_guide")
    affinity = _member_affinity(profile)
    skill = dict(SPECIES_SKILLS.get(species_code, SPECIES_SKILLS["archive_guide"]))
    skill_affinity = (
        current_weakness
        if skill["effect"] == "prism_shift" and current_weakness in AFFINITIES
        else affinity
    )
    stats = _stats(profile)
    basic_power = 10 + stats[affinity] // 2
    skill_power = int(skill["power"]) + stats[skill_affinity]
    return {
        "affinity": affinity,
        "affinity_label": AFFINITY_LABELS[affinity],
        "basic": {
            "code": "attack",
            "name": "공명 공격",
            "description": "집중력 1을 얻고 자신의 감정 공명으로 장벽을 공격해요.",
            "power": basic_power,
            "focus_delta": 1,
            "affinity": affinity,
            "effect_key": AFFINITY_EFFECTS[affinity],
        },
        "skill": {
            **skill,
            "power": skill_power,
            "affinity": skill_affinity,
            "affinity_label": AFFINITY_LABELS[skill_affinity],
            "effect_key": AFFINITY_EFFECTS[skill_affinity],
        },
        "guard": {
            "code": "guard",
            "name": "마음 지키기",
            "description": "피해를 두 칸 막고 집중력 1을 얻어요.",
            "guard": 2,
            "focus_delta": 1,
        },
    }


def _resolve_waves(encounter: dict[str, Any]) -> list[dict[str, Any]]:
    """웨이브 엉킴 code를 전투 스냅샷용 정의로 펼친다.

    battle 상태에 펼친 값을 저장하므로 진행 중 run은 이후 카탈로그 패치의
    영향을 받지 않는다(시작 snapshot 유지 계약).
    """

    waves: list[dict[str, Any]] = []
    for code in encounter.get("waves") or []:
        tangle = tangle_definition(code)
        waves.append(
            {
                "code": code,
                "name": tangle["name"],
                "elite": bool(tangle["elite"]),
                "barrier": int(tangle["barrier"]),
                "weakness_cycle": list(tangle["weakness_cycle"]),
                "intents": [dict(intent) for intent in tangle["intents"]],
                "appear_caption": tangle["appear_caption"],
                "release_caption": tangle["release_caption"],
            }
        )
    return waves


def _current_wave(state: dict[str, Any]) -> dict[str, Any] | None:
    waves = state.get("waves") or []
    index = int(state.get("wave_index", 0))
    return waves[index] if 0 <= index < len(waves) else None


def new_guardian_battle(
    event_code: str,
    encounter: dict[str, Any],
    profiles: list[dict[str, Any]],
) -> dict[str, Any]:
    waves = _resolve_waves(encounter)
    if waves:
        first = waves[0]
        weakness_cycle = list(first["weakness_cycle"])
        barrier = int(first["barrier"])
        opening_caption = first["appear_caption"]
    else:
        weakness_cycle = list(encounter.get("weakness_cycle") or AFFINITIES)
        barrier = int(encounter.get("enemy_max_guard", 100))
        opening_caption = "돌비늘 장부지기가 길을 막았어요."
    return {
        "version": 1,
        "event_code": event_code,
        "status": "active",
        "round": 1,
        "max_rounds": int(encounter.get("max_rounds", 6)),
        "focus": int(encounter.get("starting_focus", 3)),
        "max_focus": int(encounter.get("max_focus", 5)),
        "enemy_kind": "tangle" if waves else "guardian",
        "waves": waves,
        "wave_index": 0,
        "enemy_guard": barrier,
        "enemy_max_guard": barrier,
        "weakness": weakness_cycle[0],
        "intent_index": 0,
        "party": [
            {
                "member_id": int(profile["id"]),
                "hp": 3,
                "max_hp": 3,
                "guard": 0,
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
        return {
            "code": "guardian_strike",
            "name": encounter.get("attack_name", "수호자의 공격"),
            "telegraph": encounter.get("telegraph", "공격을 준비하고 있어요."),
            "target": "front",
            "power": 1,
        }
    return dict(intents[index % len(intents)])


def guardian_battle_payload(
    state: dict[str, Any],
    encounter: dict[str, Any],
    profiles: list[dict[str, Any]],
) -> dict[str, Any]:
    """직렬화 상태에 이름·스킬·현재 적 의도를 결합한 클라이언트 계약."""

    profile_by_id = {int(profile["id"]): profile for profile in profiles}
    weakness = state.get("weakness", AFFINITIES[0])
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
                ),
            }
        )
    wave = _current_wave(state)
    intent = _intent(encounter, int(state.get("intent_index", 0)), wave=wave)
    pending = state.get("pending")
    acted = [
        int(member_id)
        for member_id in (
            pending.get("acted", []) if isinstance(pending, dict) else []
        )
    ]
    living_ids = [
        int(member["member_id"])
        for member in state.get("party", [])
        if int(member["hp"]) > 0
    ]
    return {
        **copy.deepcopy(state),
        "weakness_label": AFFINITY_LABELS.get(weakness, weakness),
        "enemy_kind": state.get("enemy_kind", "guardian"),
        "enemy": {
            "name": (
                wave["name"] if wave else encounter.get("enemy_name", "수호자")
            ),
            "kind": state.get("enemy_kind", "guardian"),
            "elite": bool(wave["elite"]) if wave else False,
            "guard": int(state.get("enemy_guard", 0)),
            "max_guard": int(state.get("enemy_max_guard", 100)),
            "weakness": weakness,
            "weakness_label": AFFINITY_LABELS.get(weakness, weakness),
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
    action = command.get("action")
    if action not in {"attack", "skill", "guard"}:
        raise CombatRuleError(
            "EXPEDITION_COMBAT_ACTION_INVALID",
            "공격, 고유 스킬, 마음 지키기 중 하나를 골라 주세요.",
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
    focus = int(state.get("focus", 0))
    max_focus = int(state.get("max_focus", 5))
    kit = member_battle_kit(profile, current_weakness=weakness)
    actor_name = profile.get("snapshot", {}).get("name", "탐험대원")
    enemy_before = int(state["enemy_guard"])
    damage = 0
    weakness_hit = False
    effect_key = "safe_guard"
    caption = ""

    if action == "guard":
        focus = min(max_focus, focus + int(kit["guard"]["focus_delta"]))
        member_state["guard"] = int(kit["guard"]["guard"])
        action_name = kit["guard"]["name"]
        caption = f"{actor_name}이(가) 마음을 다잡고 공격에 대비했어요."
    else:
        action_data = kit["skill"] if action == "skill" else kit["basic"]
        action_name = action_data["name"]
        if action == "skill":
            cost = int(action_data["focus_cost"])
            if focus < cost:
                raise CombatRuleError(
                    "EXPEDITION_COMBAT_FOCUS_SHORTAGE",
                    f"{actor_name}의 고유 스킬에 필요한 집중력이 부족해요.",
                )
            focus -= cost
        else:
            focus = min(max_focus, focus + int(action_data["focus_delta"]))
        affinity = action_data["affinity"]
        effect_key = action_data["effect_key"]
        damage = int(action_data["power"])
        weakness_hit = affinity == weakness
        if weakness_hit:
            damage += 7
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
        elif effect == "last_stand" and int(member_state["hp"]) == 1:
            damage += 8
        elif effect == "weaken_intent":
            pending["intent_power_delta"] = (
                int(pending.get("intent_power_delta", 0)) - 1
            )
        elif effect == "weakness_pierce" and weakness_hit:
            damage += 6
        elif effect == "steady_read" and not weakness_hit:
            damage += 5
        elif effect == "study_refund":
            focus = min(max_focus, focus + 2)
        state["enemy_guard"] = max(0, enemy_before - damage)
        caption = (
            f"{actor_name}의 {action_name}! 약점을 꿰뚫어 장벽 {damage} 피해."
            if weakness_hit
            else f"{actor_name}의 {action_name}! 장벽 {damage} 피해."
        )

    state["focus"] = focus
    return _push_event(
        state,
        {
            "type": "party_action",
            "member_id": member_id,
            "actor_name": actor_name,
            "action": action,
            "action_name": action_name,
            "effect_key": effect_key,
            "weakness_hit": weakness_hit,
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
                "effect_key": "enemy_wave",
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
        living_ids = {
            int(member["member_id"]) for member in _living_party(state)
        }
        if living_ids <= set(int(item) for item in pending.get("acted", [])):
            events.extend(_finalize_round(state, encounter, profile_by_id))
    state["last_exchange"] = events
    _extend_log(state, events)
    return state
