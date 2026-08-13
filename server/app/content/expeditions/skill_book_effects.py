"""장착한 기록서가 전투 수치에 미치는 효과.

**모든 기록서 효과는 정액이다.** 캐릭터 등급·tier·지원 능력치로 자라지 않는다.
설계서 7.3~7.5가 책마다 정확한 숫자를 문장으로 정해 뒀고(`방어량 2 → 3`,
`위력 +3`, `집중력 +1`), 그 숫자가 곧 값이다. 계수를 곱하면 문장이 거짓이 된다.

효과를 판정 코드 안에 흩뿌리지 않고 여기 모으는 이유는 두 가지다. 어떤 책이
무엇을 바꾸는지 한 파일에서 읽히고, 전투 해결 코드에는 작은 호출 지점만 남는다.

아직 전용 기믹이 필요한 책(의도 공개·대상 변경·지연 버프 등)은 여기에 없고
카탈로그의 `combat_effect`가 `None`으로 남아 벨트에서 잠금으로 읽힌다.
"""

from __future__ import annotations

from typing import Any, Iterable, Mapping, MutableMapping


# 전투 시작 전에 한 번만 적용되는 효과(activation_mode=opening).
# 값은 설계서 문장 그대로다.
OPENING_MODIFIERS: dict[str, dict[str, int]] = {
    # 전투 시작 시 집중력 +1 (상한 5 유지)
    "first_breath": {"focus": 1},
    # 전투 시작 집중력 +2 (상한 5 유지) / 반대급부는 1라운드 스킬 사용 불가
    "germination_gear": {"focus": 2, "first_round_skill_locked": 1},
    # 라운드 제한 6 → 7 / 반대급부는 그 전투에서 집중력 최대치 −1
    "bellringer_chime": {"max_rounds": 1, "max_focus": -1},
}

# 행동 수치에 그대로 더해지는 효과(activation_mode=trigger).
# 조건이 붙는 책(`final_resolve`처럼 장벽 비율을 보는 것)은 여기 없다.
KIT_MODIFIERS: dict[str, dict[str, int]] = {
    # 마음 지키기 방어량 2 → 3
    "leaf_greave": {"guard": 1},
    # 기본 공격 위력 +3
    "clear_aim": {"basic_power": 3},
}

# 7.5.1 — command 기록서는 대원 행동 1회를 소비한다. 집중력 비용은 등급을 따르고
# 전투당 한 번만 쓴다. 여기 있는 책만 실제로 누를 수 있는 행동이 된다.
COMMAND_FOCUS_COST_BY_GRADE = {1: 0, 2: 1, 3: 2}

# (코드, 엔진 effect 이름, 정액 효과 값)
COMMAND_ACTIONS: dict[str, dict[str, Any]] = {
    # 전투 1회, 1라운드에 최저 HP 대원 1 회복
    "short_cheer": {
        "effect": "heal_lowest",
        "effect_values": {"heal_lowest": 1},
    },
    # 전투 1회, HP 0 대원 1명을 HP 1로 복귀
    "reviving_root": {
        "effect": "book_revive_one",
        "effect_values": {"revive_count": 1, "revive_hp": 1},
    },
    # 전투 1회, 다음 라운드 적 의도 1개를 미리 공개
    "echo_read": {
        "effect": "book_intent_preview",
        "effect_values": {"intent_preview_rounds": 1},
    },
    # 전투 1회, 다음 약점 일치 공격의 추가 피해 +3
    "weakness_engrave": {
        "effect": "book_weakness_engrave",
        "effect_values": {"weakness_bonus": 3},
    },
    # 전투 1회, 자신의 다음 공격 성장결을 확정 전에 고른 다른 결로 변경
    "resonance_tuner": {
        "effect": "book_kel_override",
        "effect_values": {},
        # 사용자가 여섯 성장결 중 하나를 고른다. `지금과 다른 결`만 허용한다.
        "choice_kind": "kel",
    },
}

# 여섯 성장결. 고를 수 있는 값의 단일 원본이다.
CHOICE_KELS = ("sunny", "rainy", "ember", "moonlit", "sparkling", "mosaic")


def choice_kind(code: str) -> str | None:
    """이 책이 사용자의 선택을 요구하는지, 무엇을 고르는지."""

    action = COMMAND_ACTIONS.get(code)
    return None if action is None else action.get("choice_kind")


def validate_choice(code: str, choice: str | None, *, current: str | None) -> str:
    """고른 값이 이 책에 유효한지 본다. 문제가 있으면 사유를 문장으로 돌려준다.

    빈 문자열이면 통과다. 판정은 서버가 하고 앱은 다시 계산하지 않는다.
    """

    kind = choice_kind(code)
    if kind is None:
        return "" if choice is None else "이 기록서는 고를 것이 없어요."
    if not choice:
        return "무엇으로 바꿀지 먼저 골라 주세요."
    if kind == "kel":
        if choice not in CHOICE_KELS:
            return "그런 성장결은 없어요."
        # `다른 결로 변경`이라 지금과 같은 결은 고를 수 없다.
        if current is not None and choice == current:
            return "지금과 다른 결을 골라 주세요."
    return ""

# 라운드가 넘어갈 때 방어를 이월하는 책. 값은 설계서 문장 그대로 1이다.
GUARD_CARRY = {"double_leaf": 1}


# ── command 기록서가 남기는 전투 상태 ────────────────────────────────────────
#
# 쓰고 바로 끝나지 않고 **다음 무언가를 기다리는** 책들이 있다. 그 대기 상태를
# 전투 여기저기에 흩뿌리지 않고 `state["skill_book_state"]` 한 곳에 모은다.
# 저장된 런이 그대로 이어지려면 상태가 JSON으로 왕복돼야 하므로 키는 문자열이고
# 값은 정수·불리언·목록만 쓴다.
#
# | 키 | 남기는 책 | 언제 소모되나 |
# |---|---|---|
# | `intent_preview_until_round` | echo_read | 그 라운드가 지나면 |
# | `weakness_bonus` | weakness_engrave | 다음 약점 일치 공격 한 번 |
# | `kel_override` | resonance_tuner | 그 대원의 다음 공격 |
# | `intent_target` | nine_tail_afterimage | 그 라운드 적 공격 |
# | `guard_blocked` | nine_tail_afterimage 반대급부 | 라운드 끝 |
# | `b1_override` / `skill_blocked` | heart_encyclopedia | 라운드 끝 |
#
# 아래 셋은 **사용자의 선택**을 함께 받아야 한다(어느 결로 바꿀지, 누구에게
# 넘길지, 어떤 책으로 교체할지). 명령 요청에 `choice`를 더하는 계약이 먼저
# 필요해서 여기 표에만 적어 두고 아직 구현하지 않는다.
CHOICE_REQUIRED = frozenset(
    {"resonance_tuner", "nine_tail_afterimage", "heart_encyclopedia"}
)

SKILL_BOOK_STATE_KEY = "skill_book_state"


def book_state(state: MutableMapping[str, Any]) -> dict[str, Any]:
    """전투 상태의 기록서 칸을 꺼낸다. 없으면 만들어 준다."""

    current = state.get(SKILL_BOOK_STATE_KEY)
    if not isinstance(current, dict):
        current = {}
        state[SKILL_BOOK_STATE_KEY] = current
    return current


def take_weakness_bonus(state: MutableMapping[str, Any]) -> int:
    """약점 일치 공격에 실릴 추가 피해를 꺼내며 소모한다.

    `다음 약점 일치 공격`이라 한 번 실리면 사라진다. 약점을 못 맞힌 공격은
    아무것도 쓰지 않으므로 기다리던 값이 남아 있다.
    """

    books = book_state(state)
    bonus = int(books.get("weakness_bonus", 0))
    if bonus:
        books["weakness_bonus"] = 0
    return bonus


def intent_preview_open(state: Mapping[str, Any], *, round_number: int) -> bool:
    """지금 다음 라운드 예고를 미리 볼 수 있는지."""

    books = state.get(SKILL_BOOK_STATE_KEY) or {}
    return int(books.get("intent_preview_until_round", 0)) > int(round_number)


def command_action(code: str) -> dict[str, Any] | None:
    """누를 수 있는 기록서 행동의 정의. 없으면 아직 기믹이 없는 책이다."""

    action = COMMAND_ACTIONS.get(code)
    return dict(action) if action is not None else None


# 전투당 한 번만 터지는 트리거. 정해진 행동을 처음 골랐을 때 집중력을 더한다.
# (코드, 어떤 행동에서, 몇 칸)
FOCUS_TRIGGERS: dict[str, dict[str, Any]] = {
    # 전투 1회, 방어를 고르면 집중력 1 추가 생성
    "bracing": {"on": "guard", "focus": 1},
    # 전투 1회, 스킬 사용 후 집중력 1 환급
    "focus_knot": {"on": "skill", "focus": 1},
}

# 이 세 표에 있는 코드가 카탈로그의 `combat_effect`와 일치해야 한다.
IMPLEMENTED_CODES = (
    frozenset(OPENING_MODIFIERS)
    | frozenset(KIT_MODIFIERS)
    | frozenset(FOCUS_TRIGGERS)
    | frozenset(COMMAND_ACTIONS)
    | frozenset(GUARD_CARRY)
)

# 네 스킬 슬롯. 기본 공격과 지키기는 `스킬`이 아니다.
_SKILL_SLOTS = frozenset({"unique_1", "unique_2", "selected_1", "selected_2"})


def focus_trigger(
    snapshot: Mapping[str, Any] | None,
    *,
    action: str,
    fired: Mapping[str, Any] | None,
    member_id: int,
) -> tuple[int, str | None]:
    """이번 행동에서 터지는 집중력 트리거를 찾는다.

    `전투 1회`라서 이미 터진 책은 다시 세지 않는다. 어떤 책이 터졌는지는 전투
    상태에 남으므로 저장된 런을 이어서 해도 두 번 터지지 않는다.

    돌려주는 값은 (더할 집중력, 터진 책 코드)다. 상한은 호출부가 적용한다 —
    집중력 상한은 전투 상태가 알고 이 모듈은 모른다.
    """

    lane = "skill" if action in _SKILL_SLOTS else action
    already = fired or {}
    for code in equipped_book_codes(snapshot):
        trigger = FOCUS_TRIGGERS.get(code)
        if trigger is None or trigger["on"] != lane:
            continue
        if already.get(f"{member_id}:{code}"):
            continue
        return int(trigger["focus"]), code
    return 0, None


def equipped_book_codes(snapshot: Mapping[str, Any] | None) -> list[str]:
    """얼려 둔 장착에서 실제로 붙은 기록서 코드만 뽑는다.

    감정 포인터·기본 기록서·잠긴 슬롯은 기록서가 아니므로 제외한다.
    """

    slots = ((snapshot or {}).get("skill_loadout") or {}).get("slots") or {}
    codes: list[str] = []
    for slot in ("B1", "B2"):
        decision = slots.get(slot) or {}
        if decision.get("source") != "skillbook":
            continue
        code = decision.get("code")
        if isinstance(code, str):
            codes.append(code)
    return codes


def kit_modifiers(snapshot: Mapping[str, Any] | None) -> dict[str, int]:
    """한 캐릭터의 행동 수치 보정 합계.

    두 슬롯이 같은 `stack_group`을 쓸 수 없다는 규칙은 장착 단계에서 이미
    지켜졌으므로 여기서는 단순히 더한다.
    """

    total: dict[str, int] = {}
    for code in equipped_book_codes(snapshot):
        for key, value in KIT_MODIFIERS.get(code, {}).items():
            total[key] = total.get(key, 0) + int(value)
    return total


def opening_modifiers(
    profiles: Iterable[Mapping[str, Any]],
) -> dict[str, Any]:
    """파티 전체의 전투 시작 보정을 모은다.

    집중력은 파티가 나눠 쓰는 자원이라 캐릭터별이 아니라 전투 하나에 한 번
    더해진다. 같은 책을 두 사람이 함께 들고 나갈 수 없으므로(출발 시 422)
    같은 효과가 두 번 더해지지 않는다.
    """

    focus = 0
    max_focus = 0
    max_rounds = 0
    locked_members: list[int] = []
    carry_members: dict[str, int] = {}
    applied: list[str] = []
    for profile in profiles:
        snapshot = profile.get("snapshot") or {}
        for code in equipped_book_codes(snapshot):
            # 방어 이월은 라운드마다 일어나지만, 누가 그 책을 들었는지는 출발
            # 시점에 정해진다. 라운드 정리는 전투 상태만 보므로 여기서 남긴다.
            if code in GUARD_CARRY:
                carry_members[str(int(profile.get("id", 0)))] = GUARD_CARRY[code]
            modifier = OPENING_MODIFIERS.get(code)
            if modifier is None:
                continue
            applied.append(code)
            focus += int(modifier.get("focus", 0))
            max_focus += int(modifier.get("max_focus", 0))
            max_rounds += int(modifier.get("max_rounds", 0))
            if modifier.get("first_round_skill_locked"):
                locked_members.append(int(profile.get("id", 0)))
    return {
        "focus": focus,
        "max_focus": max_focus,
        "max_rounds": max_rounds,
        # 반대급부를 진 대원. 1라운드에 스킬을 고를 수 없다.
        "first_round_skill_locked": locked_members,
        # 라운드가 넘어갈 때 방어를 이 만큼 남겨 둘 대원.
        "guard_carry": carry_members,
        "books": applied,
    }
