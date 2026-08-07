import pytest

from app.content.expeditions.combat import (
    CombatRuleError,
    SPECIES_SKILLS,
    guardian_battle_payload,
    new_guardian_battle,
    resolve_guardian_round,
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
