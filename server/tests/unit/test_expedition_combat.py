import itertools

import pytest

from app.content.expeditions.combat import (
    CombatRuleError,
    SPECIES_SKILLS,
    guardian_battle_payload,
    new_guardian_battle,
    resolve_guardian_round,
    submit_guardian_action,
)


def _profile(
    member_id: int,
    *,
    name: str,
    species: str,
    form: str,
    stats: dict[str, int],
) -> dict:
    return {
        "id": member_id,
        "position": member_id - 1,
        "is_guide": species == "archive_guide",
        "snapshot": {
            "name": name,
            "species": {"code": species},
            "form": form,
            "stats": stats,
        },
    }


def _encounter(**overrides) -> dict:
    return {
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
                "telegraph": "맨 앞 대원을 노려요.",
                "target": "front",
                "power": 1,
            },
            {
                "code": "wave",
                "name": "기록 파동",
                "telegraph": "모두를 노려요.",
                "target": "all",
                "power": 1,
            },
        ],
        **overrides,
    }


@pytest.fixture
def profiles() -> list[dict]:
    return [
        _profile(
            1,
            name="달빛이",
            species="ninja-pot",
            form="moonlit",
            stats={"care": 4, "focus": 5, "courage": 6, "insight": 7},
        ),
        _profile(
            2,
            name="안내자",
            species="archive_guide",
            form="mosaic",
            stats={"care": 6, "focus": 6, "courage": 5, "insight": 7},
        ),
    ]


def test_command_order_can_generate_focus_before_a_skill(profiles):
    battle = new_guardian_battle("keeper", _encounter(starting_focus=1), profiles)

    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 2, "action": "attack"},
            {"member_id": 1, "action": "skill"},
        ],
        _encounter(starting_focus=1),
        profiles,
    )

    assert resolved["focus"] == 0
    assert [event["member_id"] for event in resolved["last_exchange"][:2]] == [
        2,
        1,
    ]

    with pytest.raises(CombatRuleError) as error:
        resolve_guardian_round(
            battle,
            [
                {"member_id": 1, "action": "skill"},
                {"member_id": 2, "action": "attack"},
            ],
            _encounter(starting_focus=1),
            profiles,
        )
    assert error.value.code == "EXPEDITION_COMBAT_FOCUS_SHORTAGE"


def test_weakness_and_guard_change_the_exchange(profiles):
    battle = new_guardian_battle("keeper", _encounter(), profiles)
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "guard"},
            {"member_id": 2, "action": "attack"},
        ],
        _encounter(),
        profiles,
    )

    attack = resolved["last_exchange"][1]
    counter = resolved["last_exchange"][2]
    assert attack["weakness_hit"] is True
    assert attack["damage"] > 10
    assert counter["targets"] == [
        {
            "member_id": 1,
            "name": "달빛이",
            "damage": 0,
            "blocked": 1,
            "hp_after": 3,
        }
    ]
    assert resolved["round"] == 2
    assert resolved["weakness"] == "care"


def test_first_command_also_changes_the_front_target(profiles):
    battle = new_guardian_battle("keeper", _encounter(), profiles)
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 2, "action": "guard"},
            {"member_id": 1, "action": "attack"},
        ],
        _encounter(),
        profiles,
    )

    counter = next(
        event
        for event in resolved["last_exchange"]
        if event["type"] == "enemy_action"
    )
    assert counter["targets"][0]["member_id"] == 2
    assert [member["member_id"] for member in resolved["party"]] == [2, 1]


def test_breaking_the_guard_ends_the_battle_before_the_counter(profiles):
    battle = new_guardian_battle("keeper", _encounter(enemy_max_guard=10), profiles)
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "attack"},
            {"member_id": 2, "action": "attack"},
        ],
        _encounter(enemy_max_guard=10),
        profiles,
    )

    assert resolved["status"] == "victory"
    assert resolved["enemy_guard"] == 0
    assert all(
        event["type"] != "enemy_action" for event in resolved["last_exchange"]
    )


def test_round_limit_creates_a_real_defeat_state(profiles):
    encounter = _encounter(max_rounds=1)
    battle = new_guardian_battle("keeper", encounter, profiles)
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "guard"},
            {"member_id": 2, "action": "guard"},
        ],
        encounter,
        profiles,
    )

    assert resolved["status"] == "defeat"
    assert resolved["defeat_reason"] == "seal_completed"
    assert resolved["last_exchange"][-1]["outcome"] == "defeat"


def test_payload_exposes_every_species_unique_manual_skill(profiles):
    expected_species = {
        "baby-pot",
        "handsome-pot",
        "pretty-pot",
        "tsundere-pot",
        "zombie-pot",
        "gumiho-pot",
        "ninja-pot",
        "magical-pot",
        "aloof-pot",
        "student-pot",
    }
    assert expected_species <= set(SPECIES_SKILLS)
    assert len({SPECIES_SKILLS[code]["code"] for code in expected_species}) == 10

    payload = guardian_battle_payload(
        new_guardian_battle("keeper", _encounter(), profiles),
        _encounter(),
        profiles,
    )
    assert payload["enemy"]["intent"]["target"] == "front"
    assert payload["party"][0]["kit"]["skill"]["name"] == "그림자 틈베기"


def _submit_round(battle, commands, encounter, profiles):
    """순차 명령으로 한 라운드를 진행하고 최종 상태와 이벤트 흐름을 돌려준다."""

    state = battle
    events = []
    for command in commands:
        state = submit_guardian_action(state, command, encounter, profiles)
        events.extend(state["last_exchange"])
    return state, events


def _strip_runtime_fields(state):
    stripped = {
        key: value
        for key, value in state.items()
        if key not in {"pending", "round_exchange", "last_exchange"}
    }
    return stripped


def test_sequential_round_matches_batch_round_exactly(profiles):
    encounter = _encounter()
    actions = ["attack", "skill", "guard"]
    for first, second in itertools.product(actions, actions):
        commands = [
            {"member_id": 1, "action": first},
            {"member_id": 2, "action": second},
        ]
        batch_error = sequential_error = None
        batch = sequential = events = None
        try:
            batch = resolve_guardian_round(
                new_guardian_battle("keeper", encounter, profiles),
                commands,
                encounter,
                profiles,
            )
        except CombatRuleError as error:
            batch_error = error.code
        try:
            sequential, events = _submit_round(
                new_guardian_battle("keeper", encounter, profiles),
                commands,
                encounter,
                profiles,
            )
        except CombatRuleError as error:
            sequential_error = error.code

        # 규칙 오류(예: 집중력 부족)도 두 경로에서 같은 코드로 일어나야 한다.
        assert batch_error == sequential_error, (first, second)
        if batch_error is not None:
            continue
        assert _strip_runtime_fields(sequential) == _strip_runtime_fields(batch)
        assert events == batch["last_exchange"]
        assert sequential["round_exchange"] == batch["round_exchange"]


def test_sequential_round_matches_batch_across_multiple_rounds(profiles):
    encounter = _encounter(enemy_max_guard=200)
    rounds = [
        [
            {"member_id": 2, "action": "attack"},
            {"member_id": 1, "action": "skill"},
        ],
        [
            {"member_id": 1, "action": "guard"},
            {"member_id": 2, "action": "attack"},
        ],
        [
            {"member_id": 1, "action": "attack"},
            {"member_id": 2, "action": "guard"},
        ],
    ]
    batch = new_guardian_battle("keeper", encounter, profiles)
    sequential = new_guardian_battle("keeper", encounter, profiles)
    for commands in rounds:
        batch = resolve_guardian_round(batch, commands, encounter, profiles)
        sequential, _ = _submit_round(sequential, commands, encounter, profiles)
        assert _strip_runtime_fields(sequential) == _strip_runtime_fields(batch)


def test_partial_action_returns_only_new_events(profiles):
    encounter = _encounter()
    battle = new_guardian_battle("keeper", encounter, profiles)

    after_first = submit_guardian_action(
        battle, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    assert [event["type"] for event in after_first["last_exchange"]] == [
        "party_action"
    ]
    assert after_first["status"] == "active"
    assert after_first["round"] == 1
    assert after_first["pending"]["acted"] == [2]

    payload = guardian_battle_payload(after_first, encounter, profiles)
    assert payload["pending_round"] == {"acted": [2], "awaiting": [1]}

    after_second = submit_guardian_action(
        after_first, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    types = [event["type"] for event in after_second["last_exchange"]]
    assert types[0] == "party_action"
    assert "enemy_action" in types
    assert after_second["round"] == 2
    assert after_second["pending"] is None


def test_partial_rejects_duplicate_and_down_members(profiles):
    encounter = _encounter()
    battle = new_guardian_battle("keeper", encounter, profiles)
    after_first = submit_guardian_action(
        battle, {"member_id": 1, "action": "guard"}, encounter, profiles
    )

    with pytest.raises(CombatRuleError) as duplicate:
        submit_guardian_action(
            after_first, {"member_id": 1, "action": "attack"}, encounter, profiles
        )
    assert duplicate.value.code == "EXPEDITION_COMBAT_DUPLICATE_MEMBER"

    with pytest.raises(CombatRuleError) as unknown:
        submit_guardian_action(
            after_first, {"member_id": 9, "action": "attack"}, encounter, profiles
        )
    assert unknown.value.code == "EXPEDITION_COMBAT_MEMBER_INVALID"


def test_partial_focus_shortage_keeps_round_state_untouched(profiles):
    encounter = _encounter(starting_focus=1)
    battle = new_guardian_battle("keeper", encounter, profiles)

    with pytest.raises(CombatRuleError) as error:
        submit_guardian_action(
            battle, {"member_id": 1, "action": "skill"}, encounter, profiles
        )
    assert error.value.code == "EXPEDITION_COMBAT_FOCUS_SHORTAGE"
    # 원본 상태는 그대로여서 다른 카드를 다시 고를 수 있다.
    assert battle["pending"] is None
    assert battle["focus"] == 1

    recovered = submit_guardian_action(
        battle, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    assert recovered["pending"]["acted"] == [2]
    follow_up = submit_guardian_action(
        recovered, {"member_id": 1, "action": "skill"}, encounter, profiles
    )
    assert follow_up["round"] == 2


def test_partial_victory_ends_round_without_enemy_action(profiles):
    encounter = _encounter(enemy_max_guard=10)
    battle = new_guardian_battle("keeper", encounter, profiles)
    resolved = submit_guardian_action(
        battle, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    assert resolved["status"] == "victory"
    assert all(
        event["type"] != "enemy_action" for event in resolved["last_exchange"]
    )
    assert resolved["pending"] is None


def test_partial_front_target_follows_action_order(profiles):
    encounter = _encounter()
    battle = new_guardian_battle("keeper", encounter, profiles)
    state = submit_guardian_action(
        battle, {"member_id": 2, "action": "guard"}, encounter, profiles
    )
    state = submit_guardian_action(
        state, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    counter = next(
        event
        for event in state["last_exchange"]
        if event["type"] == "enemy_action"
    )
    assert counter["targets"][0]["member_id"] == 2
    assert [member["member_id"] for member in state["party"]] == [2, 1]


def test_batch_round_rejects_mixing_into_a_started_sequential_round(profiles):
    encounter = _encounter()
    battle = new_guardian_battle("keeper", encounter, profiles)
    started = submit_guardian_action(
        battle, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    with pytest.raises(CombatRuleError) as error:
        resolve_guardian_round(
            started,
            [
                {"member_id": 1, "action": "attack"},
                {"member_id": 2, "action": "attack"},
            ],
            encounter,
            profiles,
        )
    assert error.value.code == "EXPEDITION_COMBAT_ROUND_IN_PROGRESS"
