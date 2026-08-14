"""마음결 기록서 — 전투 기록서 20종의 단일 원본.

`docs/character_skill_growth_design.md` 7장이 획득·경제·장착·해금 계약의 단일
원본이라고 스스로 밝히고 있다. 이 모듈은 그 7.3~7.5.1 표를 코드로 옮긴 것이며,
표에 없는 수치나 예외를 구현 편의로 추가하지 않는다.

기록서는 **계정 귀속 영구 라이선스**다. 소모되지 않고, 파괴되지 않으며, 강화·합성·
분해가 없다. 그래서 소유(누가 가졌나)와 장착(어느 캐릭터의 어느 슬롯에 넣었나)을
분리한다. 보유해도 자동으로 장착되지 않는다.

여기에는 **전투 기록서 20종만** 있다. 탐험 기록서 16종은 사건·지도 문맥에서만
동작하므로 전투 슬롯 판정에 끼어들지 않는다. 전투 슬롯이 탐험 기록서를 만나면
막지 않고 `전투에서 쉬어요`로 읽히게 둔다(7.5.1).
"""

from __future__ import annotations

import copy
from typing import Any


# 7.2 등급과 슬롯. 3등급은 B2 전용이라 만개(Lv23) 전에는 규칙 변경형 효과를 쓸 수 없다.
SKILL_BOOK_SLOTS = ("B1", "B2")
SKILL_BOOK_GRADES = (1, 2, 3)
SKILL_BOOK_ACTIVATION_MODES = ("command", "opening", "trigger")

# 6.1 슬롯 해금 레벨. B1은 stage 3 / Lv9, B2는 stage 5 / Lv23이다.
SLOT_UNLOCK_LEVEL = {"B1": 9, "B2": 23}

# 7.2 등급별 장착 가능 슬롯.
GRADE_ALLOWED_SLOTS = {
    1: ("B1", "B2"),
    2: ("B1", "B2"),
    3: ("B2",),
}

# 7.5.1 전투 기록서 activation 단일 원본. 효과 문장에서 모드를 추측하지 않는다.
# 이 표와 카탈로그가 어긋나면 검증기가 막는다.
ACTIVATION_ROSTER: dict[str, tuple[str, ...]] = {
    "command": (
        "short_cheer",
        "echo_read",
        "resonance_tuner",
        "reviving_root",
        "weakness_engrave",
        "nine_tail_afterimage",
        "heart_encyclopedia",
    ),
    "opening": (
        "first_breath",
        "first_signal",
        "bellringer_chime",
        "germination_gear",
        "ringcount_record",
        "shadow_oath",
    ),
    "trigger": (
        "leaf_greave",
        "clear_aim",
        "bracing",
        "final_resolve",
        "double_leaf",
        "focus_knot",
        "steady_axis",
    ),
}


# `skill_book_effects.py`가 실제 수치를 가진 책. 카탈로그와 어긋나면 검증기가 막는다.
_IMPLEMENTED_EFFECT_CODES = frozenset(
    {
        "first_breath",
        "germination_gear",
        "bellringer_chime",
        "leaf_greave",
        "clear_aim",
        "bracing",
        "focus_knot",
        "short_cheer",
        "reviving_root",
        "double_leaf",
        "echo_read",
        "weakness_engrave",
        "resonance_tuner",
        "nine_tail_afterimage",
        "heart_encyclopedia",
        "final_resolve",
        "steady_axis",
        "ringcount_record",
        "shadow_oath",
    }
)


def _book(
    code: str,
    name: str,
    *,
    grade: int,
    activation_mode: str,
    effect_summary: str,
    stack_group: str,
    acquire_kind: str,
    price_seeds: int | None = None,
    unlock_hint: str | None = None,
    tradeoff: str | None = None,
    is_active: bool = True,
    retired_reason: str | None = None,
) -> dict[str, Any]:
    return {
        "code": code,
        "name": name,
        "grade": grade,
        # 이 모듈은 전투 기록서만 담는다.
        "space": "combat",
        "min_slot": "B2" if grade == 3 else "B1",
        "activation_mode": activation_mode,
        "effect_summary": effect_summary,
        "stack_group": stack_group,
        "effect_budget": 2 if grade == 3 else 1,
        "acquire_kind": acquire_kind,
        "price_seeds": price_seeds,
        "unlock_hint": unlock_hint,
        # 3등급은 예산 2를 쓰는 대신 반드시 반대급부를 함께 가진다(7.2).
        "tradeoff": tradeoff,
        # 어떤 기록서도 XP·씨앗·수집품 수량을 바꾸지 않는다(7.1). 상수다.
        "reward_affecting": False,
        # 내린 책. 새로 얻을 수는 없지만 이미 가진 사람에게는 서고에 남는다 —
        # 산 것을 조용히 지우지 않는다.
        "is_active": is_active,
        "retired_reason": retired_reason,
        # 전투 판정에 연결됐는지. `skill_book_effects.py`가 실제 수치를 갖고
        # 있고, 아직 전용 기믹이 필요한 책은 `False`로 남아 벨트에서 잠금과
        # 이유로 읽힌다. 효과를 지어내지 않는다.
        #
        # 모든 기록서 효과는 **정액**이다. 설계서가 정한 숫자를 그대로 쓰고
        # 캐릭터 등급·tier·지원 능력치로 키우지 않는다.
        "combat_effect": code in _IMPLEMENTED_EFFECT_CODES,
    }


SKILL_BOOK_CATALOG: dict[str, dict[str, Any]] = {
    # ── 1등급 낱장 기록 — 씨앗 40, 상점 상시 (7.3) ──────────────────────────
    "first_breath": _book(
        "first_breath",
        "첫 호흡",
        grade=1,
        activation_mode="opening",
        effect_summary="전투 시작 시 집중력 +1 (상한 5 유지)",
        stack_group="focus_start",
        acquire_kind="shop",
        price_seeds=40,
    ),
    "leaf_greave": _book(
        "leaf_greave",
        "잎사귀 각반",
        grade=1,
        activation_mode="trigger",
        effect_summary="마음 지키기 방어량 2 → 3",
        stack_group="guard_value",
        acquire_kind="shop",
        price_seeds=40,
    ),
    "clear_aim": _book(
        "clear_aim",
        "또렷한 겨냥",
        grade=1,
        activation_mode="trigger",
        effect_summary="기본 공격 위력 +3",
        stack_group="basic_power",
        acquire_kind="shop",
        price_seeds=40,
    ),
    "short_cheer": _book(
        "short_cheer",
        "짧은 격려",
        grade=1,
        activation_mode="command",
        effect_summary="전투 1회, 1라운드에 최저 HP 대원 1 회복",
        stack_group="heal",
        acquire_kind="shop",
        price_seeds=40,
    ),
    "echo_read": _book(
        "echo_read",
        "잔향 읽기",
        grade=1,
        activation_mode="command",
        effect_summary="전투 1회, 다음 라운드 적 의도 1개를 미리 공개",
        stack_group="intent_hint",
        acquire_kind="shop",
        price_seeds=40,
    ),
    "bracing": _book(
        "bracing",
        "버티는 자세",
        grade=1,
        activation_mode="trigger",
        effect_summary="전투 1회, 방어를 고르면 집중력 1 추가 생성",
        stack_group="focus_gain",
        acquire_kind="shop",
        price_seeds=40,
    ),
    "final_resolve": _book(
        "final_resolve",
        "마무리 결심",
        grade=1,
        activation_mode="trigger",
        effect_summary="적 장벽 20% 이하일 때 기본 공격 위력 +5",
        stack_group="basic_power",
        acquire_kind="shop",
        price_seeds=40,
    ),
    # ── 2등급 엮은 기록서 — 상점 씨앗 120 또는 해금 (7.4) ───────────────────
    "resonance_tuner": _book(
        "resonance_tuner",
        "마음결 조율기",
        grade=2,
        activation_mode="command",
        effect_summary="전투 1회, 자신의 다음 공격 성장결을 확정 전에 고른 다른 결로 변경",
        stack_group="kel_swap",
        acquire_kind="shop",
        price_seeds=120,
    ),
    "double_leaf": _book(
        "double_leaf",
        "두 겹 잎방패",
        grade=2,
        activation_mode="trigger",
        effect_summary="마음 지키기 잔여 방어 1을 다음 라운드로 이월",
        stack_group="guard_carry",
        acquire_kind="unlock",
        unlock_hint="마음 지키기 누적 30회",
    ),
    "focus_knot": _book(
        "focus_knot",
        "집중의 매듭",
        grade=2,
        activation_mode="trigger",
        effect_summary="전투 1회, 스킬 사용 후 집중력 1 환급",
        stack_group="focus_refund",
        acquire_kind="shop",
        price_seeds=120,
    ),
    "reviving_root": _book(
        "reviving_root",
        "되살아나는 뿌리",
        grade=2,
        activation_mode="command",
        effect_summary="전투 1회, HP 0 대원 1명을 HP 1로 복귀",
        stack_group="revive",
        acquire_kind="unlock",
        unlock_hint="안전 귀환 5회",
    ),
    "weakness_engrave": _book(
        "weakness_engrave",
        "약점 각인",
        grade=2,
        activation_mode="command",
        effect_summary="전투 1회, 다음 약점 일치 공격의 추가 피해 +3",
        stack_group="weakness_bonus",
        acquire_kind="unlock",
        unlock_hint="수호자 장벽 3종 열기",
    ),
    # 내린 책(0038). 효과 문장은 `적 의도 공개 후 1라운드 명령 순서 재배치`인데,
    # 순차 명령 독에서는 **모든 플레이어가 이미 매 라운드 공짜로 하는 일**이다.
    # 적 의도는 명령 전에 늘 공개되고, 대기 중인 대원은 아무나 골라 아무 순서로
    # 행동시킬 수 있다. 순서를 미리 제출하고 잠그던 예약형 패널 시절 설계라,
    # 그 패널이 교체되면서 팔 것이 사라졌다.
    "first_signal": _book(
        "first_signal",
        "선제 신호",
        grade=2,
        activation_mode="opening",
        effect_summary="전투 1회, 적 의도 공개 후 1라운드 명령 순서 재배치",
        stack_group="order_swap",
        acquire_kind="shop",
        price_seeds=120,
        is_active=False,
        retired_reason="지금 전투에서는 순서를 언제든 바꿀 수 있어 상점에서 내렸어요",
    ),
    "steady_axis": _book(
        "steady_axis",
        "흔들리지 않는 축",
        grade=2,
        activation_mode="trigger",
        effect_summary="적 `all` 공격 피해 −1",
        stack_group="all_mitigation",
        acquire_kind="shop",
        price_seeds=120,
    ),
    # ── 3등급 원본 서고 — 구매 불가, 도전 고정 달성만 (7.5) ─────────────────
    "bellringer_chime": _book(
        "bellringer_chime",
        "물결 종지기의 종",
        grade=3,
        activation_mode="opening",
        effect_summary="전투 1회, 라운드 제한 6 → 7",
        stack_group="round_limit",
        acquire_kind="challenge",
        unlock_hint="우물정원 깊은 조사",
        tradeoff="사용한 전투에서 집중력 최대치 −1",
    ),
    "germination_gear": _book(
        "germination_gear",
        "발아 시계의 태엽",
        grade=3,
        activation_mode="opening",
        effect_summary="전투 시작 집중력 +2 (상한 5 유지)",
        stack_group="focus_start",
        acquire_kind="challenge",
        unlock_hint="보관고 깊은 조사",
        tradeoff="1라운드에 스킬 사용 불가",
    ),
    "ringcount_record": _book(
        "ringcount_record",
        "나이테 관측 기록",
        grade=3,
        activation_mode="opening",
        effect_summary="파티 전원 고유 II 위력 +4",
        stack_group="unique2_power",
        acquire_kind="challenge",
        unlock_hint="관측실 깊은 조사",
        tradeoff="장착자는 그 전투에서 방어 선택 불가",
    ),
    "nine_tail_afterimage": _book(
        "nine_tail_afterimage",
        "아홉 꼬리의 잔상",
        grade=3,
        activation_mode="command",
        effect_summary="전투 1회, 적 예고 대상을 다른 대원으로 변경",
        stack_group="intent_retarget",
        acquire_kind="challenge",
        unlock_hint="여우비로 수호자 장벽 10회 열기",
        tradeoff="대상이 된 대원은 그 라운드 방어 불가",
    ),
    "shadow_oath": _book(
        "shadow_oath",
        "그림자 서약",
        grade=3,
        activation_mode="opening",
        effect_summary="약점 배율 ×1.50 → ×1.70",
        stack_group="matchup_scale",
        acquire_kind="challenge",
        unlock_hint="그림싹으로 약점 일치 공격 30회",
        tradeoff="중립 공격은 ×0.60, 원래 내성과 중복하지 않음",
    ),
    "heart_encyclopedia": _book(
        "heart_encyclopedia",
        "마음결 대백과",
        grade=3,
        activation_mode="command",
        effect_summary="전투 1회, B1을 시작 snapshot의 다른 보유 책으로 교체",
        stack_group="book_swap",
        acquire_kind="challenge",
        unlock_hint="기록서 24종 보유",
        tradeoff="교체한 라운드에는 스킬 사용 불가",
    ),
}


def skill_book(code: str) -> dict[str, Any] | None:
    """카탈로그 사본을 돌려준다. 호출부가 원본을 바꾸지 못하게 한다."""

    book = SKILL_BOOK_CATALOG.get(code)
    return copy.deepcopy(book) if book is not None else None


def is_combat_skill_book(code: str | None) -> bool:
    return code in SKILL_BOOK_CATALOG


# 아직 장착 기능을 열지 않은 계정이 받는 안전 기본값(실행 계약 4.4).
# 성장결 기본 스킬과 현장 기록서라 어떤 계정에서도 여섯 슬롯이 비지 않는다.
EMOTION_POINTERS = ("emotion.primary", "emotion.secondary")
DEFAULT_LOADOUT = {"B1": "emotion.primary", "B2": "field_note_echo"}


def _slot_result(
    slot: str,
    *,
    source: str,
    code: str | None,
    book: dict[str, Any] | None = None,
    locked: bool = False,
    lock_reason: str | None = None,
    fell_back: bool = False,
) -> dict[str, Any]:
    return {
        "slot": slot,
        "source": source,
        "code": code,
        "book": book,
        "locked": locked,
        "lock_reason": lock_reason,
        # 저장된 선택을 쓰지 못하고 기본값으로 내려왔는지. 앱이 `왜 이게 아니지`를
        # 설명할 수 있어야 해서 조용히 바꾸지 않고 사실을 함께 돌려준다.
        "fell_back": fell_back,
    }


def resolve_loadout(
    loadout: dict[str, Any] | None,
    *,
    owned_codes: set[str] | frozenset[str] | None = None,
    level: int = 1,
) -> dict[str, dict[str, Any]]:
    """저장된 장착을 검증해 두 선택 슬롯의 최종 내용을 정한다.

    실행 계약 4.4가 요구하는 순서를 그대로 따른다. 저장된 `combat_loadout`을
    우선하고, 쓸 수 없으면 안전 기본값으로 내려온다. **막지 않고 내려온다** —
    장착이 잘못됐다고 출발을 거부하면 사용자는 이유도 모른 채 갇힌다.

    검사하는 것은 네 가지다.

    * 소유권 — 보유하지 않은 책은 장착할 수 없다. 소유와 장착은 분리돼 있고,
      보유해도 자동 장착하지 않는다.
    * 슬롯 해금 — B1은 Lv9, B2는 Lv23부터다. 잠긴 슬롯은 비운다.
    * 등급 제한 — 3등급은 B2 전용이다. 가장 강한 도구는 가장 오래 키운
      캐릭터에게만 열린다.
    * `stack_group` — 두 슬롯이 같은 그룹을 쓰면 뒤 슬롯을 비운다.

    `owned_codes`가 `None`이면 소유권을 확인하지 않는다. 아직 소유권 저장소를
    붙이지 않은 호출부가 카탈로그만으로 해석할 수 있게 하기 위한 통로이며,
    소유권이 연결된 뒤에는 항상 집합을 넘긴다.
    """

    stored = loadout or {}
    requested = {
        "B1": stored.get("slot_b1_code") or stored.get("B1"),
        "B2": stored.get("slot_b2_code") or stored.get("B2"),
    }
    resolved: dict[str, dict[str, Any]] = {}
    used_stack_groups: set[str] = set()

    def fallback(slot: str, reason: str | None) -> dict[str, Any]:
        code = DEFAULT_LOADOUT[slot]
        return _slot_result(
            slot,
            source="emotion" if code in EMOTION_POINTERS else "default_book",
            code=code,
            lock_reason=reason,
            fell_back=reason is not None,
        )

    for slot in SKILL_BOOK_SLOTS:
        requested_code = requested.get(slot)
        unlock_level = SLOT_UNLOCK_LEVEL[slot]
        if level < unlock_level:
            resolved[slot] = _slot_result(
                slot,
                source="locked",
                code=None,
                locked=True,
                lock_reason=f"Lv{unlock_level}부터 열려요",
                fell_back=requested_code is not None,
            )
            continue

        if requested_code is None:
            resolved[slot] = fallback(slot, None)
            continue

        if requested_code in EMOTION_POINTERS:
            resolved[slot] = _slot_result(
                slot, source="emotion", code=requested_code
            )
            continue

        book = SKILL_BOOK_CATALOG.get(requested_code)
        if book is None:
            # 탐험 기록서이거나 이 버전이 모르는 코드다. 출발을 막지 않고
            # 안전 기본값으로 내려오되 이유는 남긴다.
            resolved[slot] = fallback(slot, "이 기록서는 전투에서 쉬어요")
            continue

        reason: str | None = None
        if owned_codes is not None and requested_code not in owned_codes:
            reason = "아직 서고에 없어요"
        elif slot not in GRADE_ALLOWED_SLOTS[int(book["grade"])]:
            reason = "3등급은 두 번째 칸에서만 펼쳐져요"
        elif book["stack_group"] in used_stack_groups:
            reason = "같은 결의 기록서를 두 칸에 함께 둘 수 없어요"

        if reason is not None:
            resolved[slot] = fallback(slot, reason)
            continue

        used_stack_groups.add(str(book["stack_group"]))
        resolved[slot] = _slot_result(
            slot,
            source="skillbook",
            code=requested_code,
            book=book,
            # opening·trigger는 스스로 발동해 대원 행동을 소비하지 않는다.
            # 벨트에서는 누를 수 없는 자리로 두되 비워서 위치를 바꾸지 않는다.
            locked=book["activation_mode"] != "command",
            lock_reason=(
                None
                if book["activation_mode"] == "command"
                else "때가 되면 스스로 펼쳐져요"
            ),
        )

    return resolved


def validate_skill_book_catalog() -> list[str]:
    """카탈로그가 설계서 계약을 어기는 지점을 모아 돌려준다."""

    errors: list[str] = []
    for code, book in SKILL_BOOK_CATALOG.items():
        prefix = f"skill_books.{code}"
        if book["code"] != code:
            errors.append(f"{prefix}.code: 키와 code가 다릅니다")
        if not str(book.get("name", "")).strip():
            errors.append(f"{prefix}.name: 이름이 필요합니다")
        if not str(book.get("effect_summary", "")).strip():
            errors.append(f"{prefix}.effect_summary: 정확한 효과 문장이 필요합니다")
        grade = book.get("grade")
        if grade not in SKILL_BOOK_GRADES:
            errors.append(f"{prefix}.grade: 1~3이어야 합니다")
            continue
        if book.get("activation_mode") not in SKILL_BOOK_ACTIVATION_MODES:
            errors.append(f"{prefix}.activation_mode: command|opening|trigger여야 합니다")
        # 7.2 — 3등급은 B2 전용이고 예산 2를 쓴다.
        if book.get("min_slot") != ("B2" if grade == 3 else "B1"):
            errors.append(f"{prefix}.min_slot: 3등급만 B2 전용입니다")
        if book.get("effect_budget") != (2 if grade == 3 else 1):
            errors.append(f"{prefix}.effect_budget: 3등급만 2입니다")
        # 7.2 — 3등급은 예산 2를 쓰는 대신 반드시 반대급부를 함께 가진다.
        if grade == 3 and not str(book.get("tradeoff") or "").strip():
            errors.append(f"{prefix}.tradeoff: 3등급은 반대급부가 필요합니다")
        if grade != 3 and book.get("tradeoff"):
            errors.append(f"{prefix}.tradeoff: 1·2등급에는 반대급부를 두지 않습니다")
        # 7.1 — 모든 기록서는 보상에 영향을 주지 않는다. 예외를 만들 수 없다.
        if book.get("reward_affecting") is not False:
            errors.append(f"{prefix}.reward_affecting: 항상 false여야 합니다")
        # 7.6 — 세 경로 어디에도 확률이 없다. 구매는 가격이, 나머지는 조건이 있다.
        kind = book.get("acquire_kind")
        if kind not in {"shop", "unlock", "challenge"}:
            errors.append(f"{prefix}.acquire_kind: shop|unlock|challenge여야 합니다")
        elif kind == "shop":
            expected = 40 if grade == 1 else 120
            if book.get("price_seeds") != expected:
                errors.append(f"{prefix}.price_seeds: {grade}등급 상점가는 {expected}입니다")
            if book.get("unlock_hint"):
                errors.append(f"{prefix}.unlock_hint: 상점 항목에는 조건이 없습니다")
        else:
            if book.get("price_seeds") is not None:
                errors.append(f"{prefix}.price_seeds: 구매할 수 없는 경로입니다")
            if not str(book.get("unlock_hint") or "").strip():
                errors.append(f"{prefix}.unlock_hint: 획득 조건을 사전 공개해야 합니다")
        # 7.5 — 3등급은 구매할 수 없다.
        if grade == 3 and kind != "challenge":
            errors.append(f"{prefix}.acquire_kind: 3등급은 도전 고정 달성만입니다")

    # 7.5.1의 닫힌 목록과 카탈로그가 정확히 일치해야 한다.
    for mode, codes in ACTIVATION_ROSTER.items():
        listed = set(codes)
        actual = {
            code
            for code, book in SKILL_BOOK_CATALOG.items()
            if book["activation_mode"] == mode
        }
        for code in sorted(listed - actual):
            errors.append(f"skill_books.{code}: {mode} 목록에 있으나 카탈로그에 없습니다")
        for code in sorted(actual - listed):
            errors.append(f"skill_books.{code}: {mode}인데 닫힌 목록에 없습니다")

    return errors
