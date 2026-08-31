"""합동 수호전이 기존 전투 엔진 위에서 실제로 도는지 본다.

콘텐츠 검사(`test_joint_guard_content`)는 표가 맞는지만 본다. 여기서는 그 표를
엔진에 넣고 라운드를 실제로 굴려, 잠꼬대가 한 번 더 오는지·결정적 순간이 정한
라운드에 오는지·비용이 다음 라운드에만 오르는지를 확인한다.

이 세 가지는 엔진을 고쳐서 생긴 능력이라, 기존 전투가 한 줄도 달라지지 않았는지
함께 본다(`test_ordinary_battle_still_has_one_telegraph`).
"""

import copy

import pytest

from app.content.expeditions.combat import (
    _finalize_round,
    member_battle_kit,
    new_guardian_battle,
    resolve_guardian_round,
)
from app.content.expeditions.joint_guard import (
    BEAST_CATALOG,
    DECISIVE_MOMENTS,
    layer_encounter,
)


def _profile(member_id: int, *, form: str = "mosaic") -> dict:
    return {
        "id": member_id,
        "position": member_id - 1,
        "is_guide": False,
        "snapshot": {
            "name": f"대원{member_id}",
            "species": {"code": "ninja-pot"},
            "form": form,
            "level": 25,
            "rarity": 1,
            "stage": 5,
            "stats": {"care": 5, "focus": 5, "courage": 5, "insight": 5},
        },
    }


@pytest.fixture
def front_three() -> list[dict]:
    """전열 3명. 합동 수호전도 화면에 세 명까지만 세운다."""
    return [_profile(1), _profile(2), _profile(3)]


def _start(beast_code: str, layer_index: int, profiles: list[dict], *, hp: int | None = None):
    encounter = layer_encounter(beast_code, "three_layers", layer_index)
    battle = new_guardian_battle(
        f"joint_guard:{beast_code}:{layer_index}", encounter, profiles
    )
    if hp is not None:
        # 규칙을 보는 검사에서 도중에 판이 끝나 버리면 정작 볼 것을 못 본다.
        for member in battle["party"]:
            member["hp"] = hp
            member["max_hp"] = hp
    return battle, encounter


def _attack_all(battle: dict) -> list[dict]:
    """아직 서 있는 대원만 명령한다. 물러난 대원까지 넣으면 엔진이 거절한다."""
    return [
        {"member_id": int(member["member_id"]), "action": "attack"}
        for member in battle["party"]
        if int(member["hp"]) > 0
    ]


def _guard_all(battle: dict) -> list[dict]:
    """장벽을 깎지 않는 명령.

    예고가 **언제** 오는지를 보는 검사에서는 공격을 쓰면 안 된다. 장벽이 먼저
    0이 되면 그 라운드는 적 차례 없이 끝나고, 보려던 라운드가 아예 오지 않는다.
    """
    return [
        {"member_id": int(member["member_id"]), "action": "guard"}
        for member in battle["party"]
        if int(member["hp"]) > 0
    ]


def _enemy_actions(resolved: dict) -> list[dict]:
    return [
        event
        for event in resolved["last_exchange"]
        if event.get("type") == "enemy_action"
    ]


def test_outer_dream_has_one_telegraph(front_three):
    """겉꿈은 기본 루프만 익히는 자리라 예고가 하나다."""
    battle, encounter = _start("ledger_keeper", 0, front_three)
    resolved = resolve_guardian_round(
        battle, _attack_all(battle), encounter, front_three
    )
    assert len(_enemy_actions(resolved)) == 1


def test_half_sleep_adds_the_sleeptalk_telegraph(front_three):
    """선잠부터 잠꼬대가 한 줄 더 붙는다(설계서 4.3)."""
    battle, encounter = _start("ledger_keeper", 1, front_three)
    resolved = resolve_guardian_round(
        battle, _attack_all(battle), encounter, front_three
    )

    actions = _enemy_actions(resolved)
    assert len(actions) == 2
    assert actions[0]["skill_code"] == "page_snow"
    assert actions[1]["skill_code"] == BEAST_CATALOG["ledger_keeper"]["sleeptalk"]["code"]


def test_the_sleeptalk_actually_lands(front_three):
    """예고만 뜨고 아무 일도 안 일어나면 두 줄을 읽을 이유가 없다."""
    battle, encounter = _start("ledger_keeper", 1, front_three)
    resolved = resolve_guardian_round(
        battle, _attack_all(battle), encounter, front_three
    )

    sleeptalk = _enemy_actions(resolved)[1]
    assert sleeptalk["targets"], sleeptalk
    # 잠꼬대는 가장 지친 대원 한 명에게만 간다.
    assert len(sleeptalk["targets"]) == 1


def test_the_decisive_moment_arrives_on_its_round(front_three):
    """`꼭 끌어안기`는 선잠 3라운드에 온다. 그 전에는 오지 않는다."""
    moment = DECISIVE_MOMENTS["tight_hug"]
    battle, encounter = _start(
        "ledger_keeper", moment["layer_index"], front_three, hp=90
    )

    seen: list[str] = []
    for _ in range(int(moment["round_no"])):
        battle = resolve_guardian_round(
            battle, _guard_all(battle), encounter, front_three
        )
        seen.append(_enemy_actions(battle)[0]["skill_code"])
        if battle["status"] != "active":
            break

    assert seen[-1] == "tight_hug"
    assert "tight_hug" not in seen[:-1]


def test_the_hug_leaves_an_echo_the_next_round(front_three):
    """순간을 넘긴 다음 라운드에 여운이 한 번 더 온다."""
    moment = DECISIVE_MOMENTS["tight_hug"]
    battle, encounter = _start(
        "ledger_keeper", moment["layer_index"], front_three, hp=90
    )

    for _ in range(int(moment["round_no"])):
        battle = resolve_guardian_round(
            battle, _guard_all(battle), encounter, front_three
        )
        assert battle["status"] == "active"

    after = resolve_guardian_round(
        battle, _guard_all(battle), encounter, front_three
    )
    codes = [event["skill_code"] for event in _enemy_actions(after)]
    assert "tight_hug" in codes, codes


def test_deep_sleeptalk_raises_the_next_round_cost_only(front_three):
    """비용은 다음 라운드에만 오르고, 집중력을 버는 행동은 그대로다."""
    battle, encounter = _start("ledger_keeper", 2, front_three, hp=90)
    profile = front_three[0]

    def skill_costs(state: dict) -> list[int]:
        kit = member_battle_kit(
            profile,
            member_state=state["party"][0],
            round_number=int(state["round"]),
            focus_surcharge=max(0, int(state.get("focus_surcharge", 0))),
        )
        return [
            int(action["focus_cost"])
            for action in [*kit["unique_skills"], *kit["selected_skills"]]
            if int(action["focus_cost"]) > 0
        ]

    before = skill_costs(battle)
    assert int(battle.get("focus_surcharge", 0)) == 0

    # 2라운드가 `깊은 잠꼬대`다. 한 라운드를 넘기면 그 순간이 걸린다.
    battle = resolve_guardian_round(
        battle, _guard_all(battle), encounter, front_three
    )
    battle = resolve_guardian_round(
        battle, _guard_all(battle), encounter, front_three
    )

    assert int(battle["focus_surcharge"]) == 1
    during = skill_costs(battle)
    assert during == [cost + 1 for cost in before], (before, during)

    # 버는 행동은 올리지 않는다. 기본 공격·방어는 비용 키 자체가 없고
    # 집중력을 `버는` 쪽(`focus_delta`)이라, 여기에 1을 더하면 안 된다.
    kit = member_battle_kit(
        profile,
        member_state=battle["party"][0],
        round_number=int(battle["round"]),
        focus_surcharge=1,
    )
    assert int(kit["basic"].get("focus_cost", 0)) == 0
    assert int(kit["guard"].get("focus_cost", 0)) == 0
    assert int(kit["basic"]["focus_delta"]) > 0

    # 한 라운드만이다.
    battle = resolve_guardian_round(
        battle, _guard_all(battle), encounter, front_three
    )
    assert int(battle["focus_surcharge"]) == 0


def test_a_fallen_party_is_not_hit_again(front_three):
    """앞 예고로 모두 물러났으면 뒤따르는 예고는 오지 않는다."""
    battle, encounter = _start("ledger_keeper", 1, front_three)
    for member in battle["party"]:
        member["hp"] = 1
        member["guard"] = 0

    resolved = resolve_guardian_round(
        battle, _attack_all(battle), encounter, front_three
    )

    assert resolved["status"] == "defeat"
    assert len(_enemy_actions(resolved)) == 1


def test_ordinary_battle_still_has_one_telegraph():
    """엔진을 고쳤어도 기존 전투는 그대로다.

    잠꼬대·여운·비용 상승은 전부 콘텐츠에 그 키가 있을 때만 붙는다. 기존
    수호자 전투에는 없으므로 예고는 지금까지처럼 한 줄이어야 한다.
    """
    profiles = [_profile(1), _profile(2)]
    encounter = {
        "enemy_name": "돌비늘 장부지기",
        "enemy_max_guard": 100,
        "max_rounds": 6,
        "starting_focus": 3,
        "max_focus": 5,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "claw",
                "name": "장부 발톱",
                "telegraph": "맨 앞 대원 쪽으로 기울어요.",
                "target": "front",
                "power": 1,
            }
        ],
    }
    battle = new_guardian_battle("stage_boss", encounter, profiles)
    resolved = resolve_guardian_round(
        battle,
        [{"member_id": 1, "action": "attack"}, {"member_id": 2, "action": "attack"}],
        encounter,
        profiles,
    )
    assert len(_enemy_actions(resolved)) == 1
    assert int(resolved.get("focus_surcharge", 0)) == 0


def test_weaken_intent_covers_the_whole_round(front_three):
    """`이번 라운드 위력을 낮춰요`는 두 예고 모두에 걸린다.

    스킬 문장이 약속한 것은 이번 **라운드**다. 주 예고만 약해지고 잠꼬대가
    그대로 들어오면 그 문장이 거짓이 된다. 그래서 합계가 아니라 잠꼬대 쪽
    피해를 따로 본다 - 합계만 보면 주 예고가 줄어든 것으로도 통과한다.

    `resolve_guardian_round`는 라운드를 시작하며 pending을 비우므로, 누적된
    감소치를 들고 적 차례만 도는 `_finalize_round`를 직접 부른다.
    """
    battle, encounter = _start("ledger_keeper", 1, front_three, hp=90)
    profile_by_id = {int(p["id"]): p for p in front_three}

    def sleeptalk_damage(delta: int) -> int:
        state = copy.deepcopy(battle)
        state["pending"] = {
            "acted": [1, 2, 3],
            "intent_power_delta": delta,
            "weakness_hit": False,
            "guard_actions": 0,
        }
        events = _finalize_round(state, encounter, profile_by_id)
        sleeptalk_code = BEAST_CATALOG["ledger_keeper"]["sleeptalk"]["code"]
        for event in events:
            if event.get("skill_code") == sleeptalk_code:
                return sum(int(t["damage"]) for t in event["targets"])
        raise AssertionError("잠꼬대 예고가 없습니다")

    assert sleeptalk_damage(-1) < sleeptalk_damage(0)
