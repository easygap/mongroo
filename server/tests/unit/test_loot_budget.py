"""가치 예산 규칙.

일반 탐험과 장거리 개척이 같은 함수를 지나므로, 규칙이 갈라지지 않는지는
여기서 한 번만 지키면 된다.
"""

from dataclasses import dataclass

import pytest

from app.content.expeditions.loot_budget import (
    LootBudgetError,
    budget_of,
    select_within_budget,
)


@dataclass
class _Row:
    id: int
    item_code: str
    value_units: int
    loot_kind: str
    quantity: int = 1


def _codes(rows) -> list[str]:
    return [row.item_code for row in rows]


def _field(index: int, value: int = 1) -> _Row:
    return _Row(id=index, item_code=f"field_{index}", value_units=value, loot_kind="field")


def _objective(index: int = 9, value: int = 1) -> _Row:
    return _Row(
        id=index, item_code="objective", value_units=value, loot_kind="objective"
    )


def test_auto_fill_takes_the_objective_first_then_discovery_order():
    """설계서 9.8: 목표 재료 우선, 그다음 먼저 발견한 순서."""

    # id가 작을수록 먼저 발견한 것이다. 목표는 마지막에 확보했어도 맨 앞에 선다.
    rows = [_field(1), _field(2), _field(3), _objective(9)]
    picked = select_within_budget(rows, budget=2, slots=3)
    assert _codes(picked.granted) == ["objective", "field_1"]
    assert _codes(picked.recorded) == ["field_2", "field_3"]
    assert picked.spent_units == 2


def test_slots_cap_bites_before_the_budget_runs_out():
    rows = [_field(1), _field(2), _field(3), _objective(9)]
    picked = select_within_budget(rows, budget=4, slots=1)
    assert _codes(picked.granted) == ["objective"]
    assert len(picked.recorded) == 3


def test_a_costlier_objective_eats_more_of_the_budget():
    """관측실 목표는 가치 2다. 예산 4면 목표 + 현장 재료 둘이 정확히 찬다."""

    rows = [_field(1), _field(2), _field(3), _objective(9, value=2)]
    picked = select_within_budget(rows, budget=4, slots=3)
    assert _codes(picked.granted) == ["objective", "field_1", "field_2"]
    assert picked.spent_units == 4


def test_a_candidate_that_does_not_fit_is_skipped_not_stopped_on():
    """예산이 1 남았는데 다음 후보가 2면, 그 뒤의 1짜리는 담을 수 있어야 한다."""

    rows = [_objective(1, value=2), _field(2, value=2), _field(3, value=1)]
    picked = select_within_budget(rows, budget=3, slots=3)
    assert _codes(picked.granted) == ["objective", "field_3"]
    assert picked.spent_units == 3


def test_core_finds_ride_along_without_spending_the_budget():
    """핵심 발견은 고르든 말든 남는다(설계서 9.1)."""

    core = _Row(id=1, item_code="core_note", value_units=2, loot_kind="core")
    rows = [core, _field(2), _objective(9)]
    picked = select_within_budget(rows, budget=1, slots=1)
    assert "core_note" in _codes(picked.granted)
    assert picked.spent_units == 1
    # 예산을 쓰지 않았으므로 기록으로 밀려나지도 않는다.
    assert "core_note" not in _codes(picked.recorded)


def test_an_explicit_pick_is_honoured_inside_the_budget():
    rows = [_field(1), _field(2), _objective(9)]
    picked = select_within_budget(rows, budget=2, slots=2, selected_ids=[2, 1])
    assert _codes(picked.granted) == ["field_2", "field_1"]
    assert _codes(picked.recorded) == ["objective"]


def test_an_empty_pick_falls_back_to_the_server_filling_it():
    # 앱이 `아무것도 안 고름`을 빈 배열로 보내도 자동 채우기로 간다.
    rows = [_field(1), _objective(9)]
    assert select_within_budget(
        rows, budget=1, slots=1, selected_ids=[]
    ).granted == select_within_budget(rows, budget=1, slots=1).granted


def test_picking_over_the_budget_is_refused_not_trimmed():
    """조용히 잘라 내면 무엇이 빠졌는지 알 길이 없다."""

    rows = [_field(1), _field(2), _objective(9)]
    with pytest.raises(LootBudgetError) as error:
        select_within_budget(rows, budget=1, slots=3, selected_ids=[1, 2])
    assert error.value.code == "EXPEDITION_LOOT_INVALID"
    assert "예산" in error.value.message


def test_picking_more_than_the_slots_is_refused():
    rows = [_field(1), _field(2), _objective(9)]
    with pytest.raises(LootBudgetError):
        select_within_budget(rows, budget=9, slots=1, selected_ids=[1, 2])


def test_picking_something_from_another_run_is_refused():
    rows = [_field(1), _objective(9)]
    with pytest.raises(LootBudgetError):
        select_within_budget(rows, budget=9, slots=9, selected_ids=[404])


def test_core_cannot_be_picked_as_if_it_spent_budget():
    # 핵심 발견은 고르는 대상이 아니다. 후보 목록에 없으므로 id로 집으면 거절된다.
    core = _Row(id=1, item_code="core_note", value_units=1, loot_kind="core")
    with pytest.raises(LootBudgetError):
        select_within_budget([core], budget=2, slots=2, selected_ids=[1])


def test_old_snapshots_without_a_budget_read_as_one_slot():
    """진행 중이던 run이 갑자기 더 받거나 덜 받게 만들지 않는다."""

    assert budget_of({"exp": 6, "seeds": 2}) == (1, 1)
    assert budget_of({"loot_value_units": 4, "loot_slots": 3}) == (4, 3)
