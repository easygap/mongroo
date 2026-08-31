"""합동 수호전 한 판이 겹·교대·귀환을 설계대로 굴리는지 본다.

전투 판정은 엔진 몫이라 여기서 다시 보지 않는다. 이 파일이 지키는 것은 그
위의 규칙들이다 - 겹이 열리면 이어지는지, 교대가 라운드당 한 번인지, 물러난
대원이 뒤에서 회복되지 않는지, 그리고 **아무것도 잃지 않는지**.
"""

import pytest

from app.content.expeditions.combat import CombatRuleError
from app.content.expeditions.joint_guard_run import (
    joint_guard_payload,
    new_joint_guard,
    submit_joint_guard_command,
    swap_joint_guard_member,
)


def _profile(member_id: int) -> dict:
    return {
        "id": member_id,
        "position": member_id - 1,
        "is_guide": False,
        "snapshot": {
            "name": f"대원{member_id}",
            "species": {"code": "ninja-pot"},
            "form": "mosaic",
            "level": 25,
            "rarity": 1,
            "stage": 5,
            "stats": {"care": 5, "focus": 5, "courage": 5, "insight": 5},
        },
    }


def _roster() -> list[dict]:
    return [
        {"profile": _profile(i), "formation": "front" if i <= 3 else "back"}
        for i in range(1, 7)
    ]


def _start(difficulty: str = "three_layers"):
    return new_joint_guard("ledger_keeper", difficulty, _roster())


def _front_ids(state: dict) -> list[int]:
    return [
        int(entry["member_id"])
        for entry in state["roster"]
        if entry["formation"] == "front"
    ]


def _open_the_layer(state: dict) -> dict:
    """장벽을 한 대만 남기고 마지막 한 방을 넣어 겹을 연다."""
    state["battle"]["enemy_guard"] = 1
    return submit_joint_guard_command(
        state, {"member_id": _front_ids(state)[0], "action": "attack"}
    )


def test_six_members_three_in_front():
    state = _start()
    assert len(state["roster"]) == 6
    assert len(_front_ids(state)) == 3
    assert state["status"] == "active"


@pytest.mark.parametrize(
    "roster, code",
    [
        ([], "JOINT_GUARD_PARTY_SIZE"),
        (
            [
                {"profile": _profile(i), "formation": "front"}
                for i in range(1, 7)
            ],
            "JOINT_GUARD_FORMATION",
        ),
        (
            [
                {"profile": _profile(1), "formation": "front" if i <= 3 else "back"}
                for i in range(1, 7)
            ],
            "JOINT_GUARD_DUPLICATE_MEMBER",
        ),
    ],
)
def test_bad_rosters_are_refused(roster, code):
    with pytest.raises(CombatRuleError) as error:
        new_joint_guard("ledger_keeper", "three_layers", roster)
    assert error.value.code == code


def test_opening_a_layer_continues_the_run():
    """겹이 열려도 판은 끝나지 않는다. 다음 겹이 이어진다."""
    state = _start()
    assert state["layer_index"] == 0

    state = _open_the_layer(state)

    assert state["status"] == "active"
    assert state["layer_index"] == 1
    assert state["battle"]["status"] == "active"
    # 승패 언어를 쓰지 않는다.
    assert "꿈이 한 겹 얕아졌어요." in state["log"]
    assert not any("승리" in line for line in state["log"])


def test_focus_carries_across_layers():
    """집중력은 판 전체가 나눠 쓰는 하나의 게이지다."""
    state = _start()
    state["battle"]["focus"] = 5
    state = _open_the_layer(state)
    # 기본 공격이 1을 벌어 상한에 걸린 채로 넘어온다.
    assert int(state["battle"]["focus"]) == 5


def test_hp_carries_across_layers():
    """겹이 바뀌어도 깎인 HP는 회복되지 않는다."""
    state = _start()
    hurt = _front_ids(state)[1]
    for entry in state["roster"]:
        if int(entry["member_id"]) == hurt:
            entry["hp"] = 3
    for member in state["battle"]["party"]:
        if int(member["member_id"]) == hurt:
            member["hp"] = 3

    state = _open_the_layer(state)

    carried = next(
        member
        for member in state["battle"]["party"]
        if int(member["member_id"]) == hurt
    )
    assert int(carried["hp"]) == 3


def test_the_last_layer_wakes_the_beast():
    """겉꿈 산책은 한 겹이라 그 겹을 열면 짐승이 깨어난다."""
    state = _start("outer_walk")
    assert len(state["layers"]) == 1

    state = _open_the_layer(state)

    assert state["status"] == "awake"
    assert any("깨어났어요" in line for line in state["log"])


def test_running_out_of_rounds_returns_safely():
    """라운드를 다 써도 잃는 것은 없다. 귀환 문구에 패배가 없다."""
    state = _start()
    # 마지막 라운드에서 전원이 행동하면 그 라운드로 겹이 닫힌다.
    state["battle"]["round"] = int(state["battle"]["max_rounds"])
    for member_id in _front_ids(state):
        state = submit_joint_guard_command(
            state, {"member_id": member_id, "action": "guard"}
        )

    assert state["status"] == "withdrawn"
    assert any("다치지 않았어요" in line for line in state["log"])
    assert not any("패배" in line for line in state["log"])


def test_a_downed_front_line_waits_for_a_swap():
    """전열이 모두 물러나도 뒤에 설 사람이 있으면 판은 이어진다."""
    state = _start()
    state["battle"]["status"] = "defeat"
    state["battle"]["defeat_reason"] = "party_down"
    for member in state["battle"]["party"]:
        member["hp"] = 0
    from app.content.expeditions.joint_guard_run import _advance

    _advance(state)
    assert state["status"] == "active"


def test_a_downed_front_line_with_no_reserves_returns():
    state = _start()
    for entry in state["roster"]:
        entry["hp"] = 0
    state["battle"]["status"] = "defeat"
    state["battle"]["defeat_reason"] = "party_down"
    from app.content.expeditions.joint_guard_run import _advance

    _advance(state)
    assert state["status"] == "withdrawn"


def test_swapping_moves_one_member_each_way():
    state = _start()
    out_id, in_id = _front_ids(state)[0], 4

    state = swap_joint_guard_member(state, out_member_id=out_id, in_member_id=in_id)

    assert in_id in _front_ids(state)
    assert out_id not in _front_ids(state)
    assert int(state["swaps_used_this_round"]) == 1


def test_only_one_swap_per_round():
    """라운드당 한 번이다(설계서 4.2)."""
    state = _start()
    state = swap_joint_guard_member(state, out_member_id=1, in_member_id=4)
    with pytest.raises(CombatRuleError) as error:
        swap_joint_guard_member(state, out_member_id=2, in_member_id=5)
    assert error.value.code == "JOINT_SWAP_LIMIT"


def test_a_swapped_out_member_keeps_their_wounds():
    """물러난 대원은 뒤에서 회복되지 않는다.

    대기석을 회복 슬롯으로 만들면 돌봄 역할이 의미를 잃는다(설계서 12장).
    """
    state = _start()
    for entry in state["roster"]:
        if int(entry["member_id"]) == 1:
            entry["hp"] = 2

    state = swap_joint_guard_member(state, out_member_id=1, in_member_id=4)

    benched = next(e for e in state["roster"] if int(e["member_id"]) == 1)
    assert benched["formation"] == "back"
    assert int(benched["hp"]) == 2


def test_a_fallen_reserve_cannot_step_in():
    state = _start()
    for entry in state["roster"]:
        if int(entry["member_id"]) == 4:
            entry["hp"] = 0
    with pytest.raises(CombatRuleError) as error:
        swap_joint_guard_member(state, out_member_id=1, in_member_id=4)
    assert error.value.code == "JOINT_SWAP_DOWN"


def test_swap_needs_a_front_and_a_back():
    state = _start()
    with pytest.raises(CombatRuleError):
        swap_joint_guard_member(state, out_member_id=4, in_member_id=5)
    with pytest.raises(CombatRuleError):
        swap_joint_guard_member(state, out_member_id=1, in_member_id=2)


def test_swap_is_refused_in_the_middle_of_a_round():
    """라운드 해결이 끝난 뒤에만 교대한다."""
    state = _start()
    state = submit_joint_guard_command(
        state, {"member_id": _front_ids(state)[0], "action": "guard"}
    )
    with pytest.raises(CombatRuleError) as error:
        swap_joint_guard_member(state, out_member_id=_front_ids(state)[1], in_member_id=4)
    assert error.value.code == "JOINT_SWAP_MID_ROUND"


def test_payload_carries_no_economy_reward():
    """경제 보상 0(설계서 6장). 응답에 재화 키가 아예 없다."""
    payload = joint_guard_payload(_start())
    banned = {"exp", "xp", "seeds", "seed_balance", "reward", "rewards", "currency"}

    def walk(node, path=""):
        if isinstance(node, dict):
            for key, value in node.items():
                assert key not in banned, f"{path}.{key}"
                walk(value, f"{path}.{key}")
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, f"{path}[{index}]")

    walk(payload)


def test_payload_reads_the_layer_matchup_and_reserves():
    payload = joint_guard_payload(_start())
    assert payload["layer"]["name"] == "겉꿈"
    assert payload["layer"]["count"] == 3
    assert payload["layer"]["weak_kel_label"] == "햇살결"
    assert len(payload["front"]) == 3
    assert len(payload["reserves"]) == 3
    assert all(member["can_swap_in"] for member in payload["reserves"])
    assert payload["swaps_left"] == 1


def test_the_deep_layer_warning_reaches_the_payload():
    """라운드 안에 예고할 자리가 없는 순간은 겹 입장에서 알린다."""
    state = _start()
    state["layer_index"] = 2
    from app.content.expeditions.joint_guard_run import _open_layer

    _open_layer(state, carry_focus=None)

    warning = joint_guard_payload(state)["layer"]["warning"]
    assert warning is not None
    assert warning["code"] == "deep_sleeptalk"
    assert warning["bypass"]
