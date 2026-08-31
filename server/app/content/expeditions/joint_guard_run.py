"""합동 수호전 한 판의 상태 기계 — 겹·교대·귀환.

전투 판정은 하지 않는다. 겹마다 기존 수호자 전투를 하나 세우고
(`combat.new_guardian_battle`), 명령은 그대로 엔진에 넘긴다. 이 모듈이 맡는
것은 그 위에 있는 것들이다.

- 여섯 명의 명단과 전열 셋. 화면에 서는 것은 늘 셋이고 나머지는 뒤에서 기다린다.
- 겹 전환. 장벽이 0이 되면 전투는 `victory`로 끝나지만 판은 끝나지 않는다.
  다음 겹을 세우고 이어 간다.
- 교대. 라운드가 해결된 뒤에만, 라운드당 한 번.
- 귀환. 라운드를 다 쓰거나 세울 사람이 없으면 안전하게 돌아온다. 아무것도
  잃지 않는다(설계서 3항).

HP는 명단이 들고 있다. 물러난 대원도 뒤에서 그대로 기다리고 회복되지 않는다 —
일으키는 것은 돌봄의 일이지 대기석의 효과가 아니다(설계서 12장 금지 항목).

집중력은 판 전체가 나눠 쓰는 하나의 게이지라 겹이 바뀌어도 이어진다. 겹마다
3으로 되돌리면 앞 겹에서 아껴 둔 집중력이 사라져, 교대와 겹 전환을 걸쳐 자원을
운용하는 이 콘텐츠의 축이 무너진다.
"""

from typing import Any

from app.content.expeditions.combat import (
    CombatRuleError,
    combat_hp_for_profile,
    guardian_battle_payload,
    new_guardian_battle,
    submit_guardian_action,
)
from app.content.expeditions.joint_guard import (
    BEAST_CATALOG,
    DIFFICULTIES,
    beast_story,
    layer_encounter,
    layer_warning,
    layers_for,
)


PARTY_SIZE = 6
FRONT_SIZE = 3
SWAPS_PER_ROUND = 1


def new_joint_guard(
    beast_code: str,
    difficulty: str,
    roster: list[dict[str, Any]],
) -> dict[str, Any]:
    """명단 여섯을 받아 첫 겹을 세운다.

    `roster`는 `{"profile": …, "formation": "front"|"back"}` 여섯 개다. 빈자리를
    길잡이로 채우는 것은 호출부의 일이고, 여기서는 여섯이 채워져 있다고 본다.
    """
    if beast_code not in BEAST_CATALOG:
        raise CombatRuleError("JOINT_GUARD_UNKNOWN_BEAST", "그런 수호짐승은 없어요.")
    if difficulty not in DIFFICULTIES:
        raise CombatRuleError("JOINT_GUARD_UNKNOWN_DIFFICULTY", "그런 난이도는 없어요.")
    if len(roster) != PARTY_SIZE:
        raise CombatRuleError(
            "JOINT_GUARD_PARTY_SIZE", f"{PARTY_SIZE}명으로 편성해 주세요."
        )
    front = [entry for entry in roster if entry.get("formation") == "front"]
    if len(front) != FRONT_SIZE:
        raise CombatRuleError(
            "JOINT_GUARD_FORMATION", f"전열은 {FRONT_SIZE}명이어야 해요."
        )
    member_ids = [int(entry["profile"]["id"]) for entry in roster]
    if len(set(member_ids)) != PARTY_SIZE:
        raise CombatRuleError(
            "JOINT_GUARD_DUPLICATE_MEMBER", "같은 대원을 두 번 넣을 수 없어요."
        )

    state: dict[str, Any] = {
        "version": 1,
        "beast_code": beast_code,
        "difficulty": difficulty,
        "status": "active",
        "layers": layers_for(beast_code, difficulty),
        "layer_index": 0,
        # 여섯 명 모두 여기서 HP를 받는다. 전투는 전열 셋만 들고 있으므로
        # 후열까지 채워 두지 않으면 뒤에 선 대원이 `지쳐서 물러난` 상태로
        # 오해받아 교대가 막힌다.
        "roster": [
            {
                "member_id": int(entry["profile"]["id"]),
                "formation": str(entry["formation"]),
                "profile": entry["profile"],
                "hp": combat_hp_for_profile(entry["profile"]),
                "max_hp": combat_hp_for_profile(entry["profile"]),
            }
            for entry in roster
        ],
        "swaps_used_this_round": 0,
        "log": [beast_story(beast_code, "enter")],
        "battle": None,
    }
    _open_layer(state, carry_focus=None)
    return state


def _front_entries(state: dict[str, Any]) -> list[dict[str, Any]]:
    return [entry for entry in state["roster"] if entry["formation"] == "front"]


def _front_profiles(state: dict[str, Any]) -> list[dict[str, Any]]:
    return [entry["profile"] for entry in _front_entries(state)]


def _encounter(state: dict[str, Any]) -> dict[str, Any]:
    return layer_encounter(
        str(state["beast_code"]),
        str(state["difficulty"]),
        int(state["layer_index"]),
    )


def _open_layer(state: dict[str, Any], *, carry_focus: int | None) -> None:
    """다음 겹의 전투를 세운다. 명단이 들고 있던 HP를 그대로 얹는다."""
    encounter = _encounter(state)
    battle = new_guardian_battle(
        f"joint_guard:{state['beast_code']}:{state['layer_index']}",
        encounter,
        _front_profiles(state),
    )
    # 새 겹은 새 전투지만 대원은 같은 사람이다. 명단이 들고 있던 HP를 그대로
    # 얹어야 앞 겹에서 다친 대원이 조용히 회복되지 않는다.
    by_id = {int(entry["member_id"]): entry for entry in state["roster"]}
    for member in battle["party"]:
        entry = by_id[int(member["member_id"])]
        member["max_hp"] = int(entry["max_hp"])
        member["hp"] = int(entry["hp"])
    if carry_focus is not None:
        battle["focus"] = max(0, min(int(battle["max_focus"]), int(carry_focus)))
    state["battle"] = battle
    state["swaps_used_this_round"] = 0
    layer = state["layers"][int(state["layer_index"])]
    state["log"].append(f"{layer['name']}에 들어섰어요.")


def _sync_roster_hp(state: dict[str, Any]) -> None:
    """전투가 깎은 HP를 명단으로 돌려 놓는다. 명단이 단일 원본이다."""
    by_id = {int(entry["member_id"]): entry for entry in state["roster"]}
    for member in state["battle"]["party"]:
        entry = by_id[int(member["member_id"])]
        entry["hp"] = int(member["hp"])
        entry["max_hp"] = int(member["max_hp"])


def _standing_reserves(state: dict[str, Any]) -> list[dict[str, Any]]:
    """아직 서 있는 후열. HP 0으로 물러난 대원은 들어올 수 없다."""
    return [
        entry
        for entry in state["roster"]
        if entry["formation"] == "back" and int(entry["hp"] or 0) > 0
    ]


def submit_joint_guard_command(
    state: dict[str, Any],
    command: dict[str, Any],
) -> dict[str, Any]:
    """전열 한 명의 명령을 판정한다. 라운드가 끝나면 겹 전환까지 본다."""
    if state["status"] != "active":
        raise CombatRuleError("JOINT_GUARD_FINISHED", "이미 끝난 판이에요.")

    encounter = _encounter(state)
    state["battle"] = submit_guardian_action(
        state["battle"], command, encounter, _front_profiles(state)
    )
    _sync_roster_hp(state)
    _advance(state)
    return state


def _advance(state: dict[str, Any]) -> None:
    """전투가 끝난 뒤 판이 어떻게 되는지 정한다."""
    battle = state["battle"]
    status = str(battle.get("status"))

    if status == "victory":
        # 겹 하나가 얕아졌을 뿐이다. 승패 언어를 쓰지 않는다.
        state["log"].append(beast_story(str(state["beast_code"]), "layer_opened"))
        if int(state["layer_index"]) + 1 >= len(state["layers"]):
            state["status"] = "awake"
            state["log"].append(beast_story(str(state["beast_code"]), "awake"))
            return
        state["layer_index"] = int(state["layer_index"]) + 1
        _open_layer(state, carry_focus=int(battle.get("focus", 0)))
        return

    if status == "defeat":
        # 라운드를 다 쓴 것과 전열이 모두 물러난 것은 다르다. 뒤에 설 사람이
        # 있으면 판은 이어진다 - 물러난 자리를 메우는 것이지 진 것이 아니다.
        if battle.get("defeat_reason") == "party_down" and _standing_reserves(state):
            return
        state["status"] = "withdrawn"
        state["log"].append(beast_story(str(state["beast_code"]), "withdraw"))
        return

    # 라운드가 넘어갔으면 교대 한 번이 다시 열린다.
    if int(battle.get("round", 1)) != int(state.get("last_round", 0)):
        state["swaps_used_this_round"] = 0
        state["last_round"] = int(battle.get("round", 1))


def swap_joint_guard_member(
    state: dict[str, Any],
    *,
    out_member_id: int,
    in_member_id: int,
) -> dict[str, Any]:
    """전열 한 명을 후열 한 명과 바꾼다.

    라운드 사이에만, 라운드당 한 번이다. 나가는 대원의 HP는 그대로 유지되고,
    들어온 대원은 다음 라운드부터 명령을 받는다.
    """
    if state["status"] != "active":
        raise CombatRuleError("JOINT_GUARD_FINISHED", "이미 끝난 판이에요.")
    if int(state["swaps_used_this_round"]) >= SWAPS_PER_ROUND:
        raise CombatRuleError(
            "JOINT_SWAP_LIMIT", "이번 라운드에는 이미 한 번 교대했어요."
        )
    battle = state["battle"]
    if (battle.get("pending") or {}).get("acted"):
        raise CombatRuleError(
            "JOINT_SWAP_MID_ROUND", "라운드가 끝난 뒤에 교대할 수 있어요."
        )

    by_id = {int(entry["member_id"]): entry for entry in state["roster"]}
    going_out = by_id.get(int(out_member_id))
    coming_in = by_id.get(int(in_member_id))
    if going_out is None or going_out["formation"] != "front":
        raise CombatRuleError("JOINT_SWAP_NOT_FRONT", "전열 대원을 골라 주세요.")
    if coming_in is None or coming_in["formation"] != "back":
        raise CombatRuleError("JOINT_SWAP_NOT_BACK", "후열 대원을 골라 주세요.")
    if int(coming_in["hp"] or 0) <= 0:
        raise CombatRuleError(
            "JOINT_SWAP_DOWN", "지쳐서 물러난 대원은 아직 설 수 없어요."
        )

    going_out["formation"] = "back"
    coming_in["formation"] = "front"
    state["swaps_used_this_round"] = int(state["swaps_used_this_round"]) + 1

    # 전투가 들고 있는 전열 목록을 새 편성으로 맞춘다. 장벽·라운드·집중력은
    # 그대로다 - 교대는 판을 다시 시작하는 것이 아니다.
    for member in battle["party"]:
        if int(member["member_id"]) == int(out_member_id):
            member["member_id"] = int(in_member_id)
            member["hp"] = int(coming_in["hp"])
            member["max_hp"] = int(coming_in["max_hp"])
            member["guard"] = 0
            member["cooldown_until_round"] = {}
            member["ready_round"] = {}
            member["statuses"] = {}
            break

    # 전열이 다시 서면 판은 이어진다.
    if battle.get("status") == "defeat" and battle.get("defeat_reason") == "party_down":
        battle["status"] = "active"
        battle["defeat_reason"] = None
    return state


def joint_guard_payload(state: dict[str, Any]) -> dict[str, Any]:
    """앱이 읽는 모양. 경제 보상은 어디에도 없다(설계서 6장)."""
    beast = BEAST_CATALOG[str(state["beast_code"])]
    layer = state["layers"][int(state["layer_index"])]
    encounter = _encounter(state)
    return {
        "beast": {
            "code": str(state["beast_code"]),
            "name": beast["name"],
            "dream_scene": beast["dream_scene"],
            "holding": beast["holding"],
        },
        "difficulty": {
            "code": str(state["difficulty"]),
            **{
                key: DIFFICULTIES[str(state["difficulty"])][key]
                for key in ("name", "summary", "tutorial")
            },
        },
        "status": str(state["status"]),
        "layer": {
            "index": int(layer["index"]),
            "name": str(layer["name"]),
            "count": len(state["layers"]),
            "weak_kel": layer["weak_kel"],
            "weak_kel_label": layer["weak_kel_label"],
            "resist_kel": layer["resist_kel"],
            "resist_kel_label": layer["resist_kel_label"],
            "warning": layer_warning(
                str(state["beast_code"]), int(state["layer_index"])
            ),
        },
        "swaps_left": max(
            0, SWAPS_PER_ROUND - int(state.get("swaps_used_this_round", 0))
        ),
        "front": [
            {
                "member_id": int(entry["member_id"]),
                "name": entry["profile"].get("snapshot", {}).get("name", "대원"),
                "hp": int(entry["hp"] or 0),
                "max_hp": int(entry["max_hp"] or 0),
            }
            for entry in _front_entries(state)
        ],
        "reserves": [
            {
                "member_id": int(entry["member_id"]),
                "name": entry["profile"].get("snapshot", {}).get("name", "대원"),
                "hp": int(entry["hp"] or 0),
                "max_hp": int(entry["max_hp"] or 0),
                "can_swap_in": int(entry["hp"] or 0) > 0,
            }
            for entry in state["roster"]
            if entry["formation"] == "back"
        ],
        "battle": guardian_battle_payload(
            state["battle"], encounter, _front_profiles(state)
        ),
        "log": list(state["log"]),
    }
