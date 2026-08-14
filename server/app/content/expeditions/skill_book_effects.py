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

from typing import Any, Iterable, Mapping, MutableMapping, Sequence


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

# 조건이 붙은 정액 보정. 조건을 만족하는 동안에만 더해지고 풀리면 사라진다.
# 값이 자라지 않는 것은 무조건 보정과 같다.
LOW_BARRIER_MODIFIERS: dict[str, dict[str, int]] = {
    # 적 장벽 20% 이하일 때 기본 공격 위력 +5
    "final_resolve": {"basic_power": 5},
}

# `장벽 20% 이하`의 단일 원본. 앱은 이 값을 다시 계산하지 않고 서버가 이미
# 반영해 내려보낸 위력을 읽는다.
LOW_BARRIER_BP = 2_000

# 적이 **전원을 노리는** 공격에서 덜어 내는 피해. 정액 차감이라 광역기가 셀수록
# 체감이 옅어지고 약할수록 크다 — 정액 규칙이 만드는 의도한 곡선이다.
ALL_HIT_REDUCTION: dict[str, int] = {"steady_axis": 1}

# 파티 전원에게 한 번 걸리는 전투 시작 보정. 장착자 개인이 아니라 전투 하나에
# 걸리므로 `opening_modifiers`가 모아서 전투 상태에 남긴다.
PARTY_OPENING_MODIFIERS: dict[str, dict[str, int]] = {
    # 파티 전원 고유 II 위력 +4
    "ringcount_record": {"unique2_power": 4},
}

# 그 전투 내내 마음 지키기를 고를 수 없는 책(반대급부).
GUARD_LOCKED_BOOKS = frozenset({"ringcount_record"})

# 장착자 한 명의 상성 배율을 갈아 끼우는 책. 기본값은 `MATCHUP_POWER_BP`
# (weak 15000 / neutral 10000 / resist 6000)이고 여기 적힌 열쇠만 덮는다.
# **내성은 덮지 않는다** — 설계서의 `원래 내성과 중복하지 않음`이 그 뜻이다.
# 덮으면 중립 0.60과 내성 0.60이 겹쳐 두 배로 아프다.
OATH_MATCHUP_BP: dict[str, dict[str, int]] = {
    # 약점 배율 ×1.50 → ×1.70, 중립은 ×0.60
    "shadow_oath": {"weak": 17_000, "neutral": 6_000},
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
    # 아홉 꼬리의 잔상 — 예고된 공격을 다른 대원이 받는다. 대신 그 대원은 그
    # 라운드에 마음 지키기를 쓸 수 없다(설계서의 반대급부). 전체 공격은 넘길
    # 대상이라는 개념이 없어 전투 쪽에서 후보가 비고, 슬롯은 잠긴 채 보인다.
    "nine_tail_afterimage": {
        "effect": "book_intent_retarget",
        "effect_values": {},
        "choice_kind": "member",
    },
    # 마음결 대백과 — B1을 출발 스냅샷에 얼려 둔 다른 보유 책으로 바꾼다. 대신
    # 바꾼 라운드에는 스킬을 쓸 수 없다.
    "heart_encyclopedia": {
        "effect": "book_swap_b1",
        "effect_values": {},
        "choice_kind": "book",
    },
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


# 고를 것이 없을 때 슬롯에 붙는 사유. 파티가 한 명뿐이거나 예비 기록서가
# 없으면 누를 수 있는 것처럼 보여 놓고 거절하는 대신 미리 잠근다.
NOTHING_TO_CHOOSE = {
    "kel": "바꿀 성장결이 없어요.",
    "member": "넘길 다른 대원이 없어요.",
    "book": "바꿔 낄 다른 기록서가 없어요.",
}


def choice_options(kind: str | None) -> tuple[str, ...]:
    """후보가 전투 상황과 무관하게 고정된 종류만 여기서 답한다.

    성장결 여섯은 언제나 같지만, 대원과 기록서는 그 전투의 파티와 출발 스냅샷을
    봐야 안다. 그런 종류는 빈 튜플을 돌려주고 전투 쪽이 채운다.
    """

    return CHOICE_KELS if kind == "kel" else ()


def validate_choice(
    code: str,
    choice: str | None,
    *,
    current: str | None,
    allowed: Sequence[str] | None = None,
) -> str:
    """고른 값이 이 책에 유효한지 본다. 문제가 있으면 사유를 문장으로 돌려준다.

    빈 문자열이면 통과다. 판정은 서버가 하고 앱은 다시 계산하지 않는다.

    `allowed`는 그 전투에서 실제로 고를 수 있었던 후보다. 앱에 내려보낸 목록과
    **같은 목록으로 판정해야** 화면에 보인 것을 골랐는데 거절당하는 일이 없다.
    넘기지 않으면 종류가 고정 후보를 가진 경우(성장결)만 검사한다.
    """

    kind = choice_kind(code)
    if kind is None:
        return "" if choice is None else "이 기록서는 고를 것이 없어요."
    if not choice:
        return "무엇으로 바꿀지 먼저 골라 주세요."

    candidates = tuple(allowed) if allowed is not None else choice_options(kind)
    if candidates and choice not in candidates:
        return _NOT_A_CANDIDATE.get(kind, "지금 고를 수 없는 값이에요.")
    # `다른 것으로 변경`이라 지금과 같은 것은 고를 수 없다.
    if current is not None and choice == current:
        return _SAME_AS_NOW.get(kind, "지금과 다른 것을 골라 주세요.")
    return ""


_NOT_A_CANDIDATE = {
    "kel": "그런 성장결은 없어요.",
    "member": "지금 넘길 수 없는 대원이에요.",
    "book": "출발할 때 가져오지 않은 기록서예요.",
}

_SAME_AS_NOW = {
    "kel": "지금과 다른 결을 골라 주세요.",
    "member": "이미 이 대원이 노려지고 있어요.",
    "book": "이미 끼고 있는 기록서예요.",
}

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
# 아래 셋은 **사용자의 선택**을 함께 받는다(어느 결로 바꿀지, 누구에게 넘길지,
# 어떤 책으로 교체할지). 명령 요청의 `choice`와 슬롯의 `choice_options`가 그
# 계약이고, 후보 목록과 판정은 서버만 쥔다.
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
    | frozenset(LOW_BARRIER_MODIFIERS)
    | frozenset(ALL_HIT_REDUCTION)
    | frozenset(PARTY_OPENING_MODIFIERS)
    | frozenset(OATH_MATCHUP_BP)
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


def kit_modifiers(
    snapshot: Mapping[str, Any] | None,
    *,
    b1_override: str | None = None,
    enemy_guard_bp: int = 10_000,
) -> dict[str, int]:
    """한 캐릭터의 행동 수치 보정 합계.

    두 슬롯이 같은 `stack_group`을 쓸 수 없다는 규칙은 장착 단계에서 이미
    지켜졌으므로 여기서는 단순히 더한다.

    `b1_override`는 마음결 대백과로 전투 중에 바꿔 낀 첫 칸이다. 슬롯에는 새 책이
    보이는데 그 책의 수치는 안 붙는 상태를 만들지 않으려고 함께 본다.
    """

    codes = list(equipped_book_codes(snapshot))
    if b1_override:
        slots = ((snapshot or {}).get("skill_loadout") or {}).get("slots") or {}
        replaced = (slots.get("B1") or {}).get("code")
        codes = [code for code in codes if code != replaced] + [b1_override]

    # 장벽이 얼마 안 남았을 때만 붙는 보정. 조건은 서버가 판정하고 앱은 이미
    # 반영된 위력을 읽는다 — 두 곳이 20%를 각자 계산하면 어긋난다.
    tables = [KIT_MODIFIERS]
    if int(enemy_guard_bp) <= LOW_BARRIER_BP:
        tables.append(LOW_BARRIER_MODIFIERS)

    total: dict[str, int] = {}
    for code in codes:
        for table in tables:
            for key, value in table.get(code, {}).items():
                total[key] = total.get(key, 0) + int(value)
    return total


def oath_matchup_bp(snapshot: Mapping[str, Any] | None) -> dict[str, int]:
    """이 캐릭터가 쓰는 상성 배율 중 덮어쓸 부분.

    비어 있으면 기본 배율 그대로다. 두 칸에 같은 `stack_group`을 둘 수 없어
    맹세가 겹쳐 쌓이는 일은 장착 단계에서 이미 막혀 있다.
    """

    override: dict[str, int] = {}
    for code in equipped_book_codes(snapshot):
        override.update(OATH_MATCHUP_BP.get(code, {}))
    return override


def all_hit_reduction(snapshot: Mapping[str, Any] | None) -> int:
    """적이 전원을 노릴 때 이 캐릭터가 덜 받는 피해."""

    return sum(
        ALL_HIT_REDUCTION.get(code, 0) for code in equipped_book_codes(snapshot)
    )


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
    unique2_power = 0
    locked_members: list[int] = []
    guard_locked: list[int] = []
    carry_members: dict[str, int] = {}
    applied: list[str] = []
    for profile in profiles:
        snapshot = profile.get("snapshot") or {}
        for code in equipped_book_codes(snapshot):
            # 방어 이월은 라운드마다 일어나지만, 누가 그 책을 들었는지는 출발
            # 시점에 정해진다. 라운드 정리는 전투 상태만 보므로 여기서 남긴다.
            if code in GUARD_CARRY:
                carry_members[str(int(profile.get("id", 0)))] = GUARD_CARRY[code]
            # 그 전투 내내 몸을 뺄 수 없는 반대급부. 라운드가 아니라 전투
            # 단위라 여기서 한 번만 정해 둔다.
            if code in GUARD_LOCKED_BOOKS:
                guard_locked.append(int(profile.get("id", 0)))
            if party := PARTY_OPENING_MODIFIERS.get(code):
                applied.append(code)
                unique2_power += int(party.get("unique2_power", 0))
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
        # 파티 전원의 고유 II에 실리는 정액 보정.
        "unique2_power": unique2_power,
        # 반대급부를 진 대원. 1라운드에 스킬을 고를 수 없다.
        "first_round_skill_locked": locked_members,
        # 반대급부를 진 대원. 그 전투 내내 마음 지키기를 고를 수 없다.
        "guard_locked": guard_locked,
        # 라운드가 넘어갈 때 방어를 이 만큼 남겨 둘 대원.
        "guard_carry": carry_members,
        "books": applied,
    }
