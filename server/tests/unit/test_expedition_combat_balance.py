import pytest

from app.content.expeditions.combat import new_guardian_battle
from app.content.expeditions.combat_balance import (
    COMBAT_BALANCE_VERSION,
    REGION_COMBAT_BANDS,
    combat_hp_for_level,
    growth_index_for_party,
    starting_focus_for_party,
    validate_tangle_balance,
)
from app.content.expeditions.tangles import TANGLE_CATALOG


def _profile(member_id: int, level: int, *, guide: bool = False) -> dict:
    return {
        "id": member_id,
        "position": member_id - 1,
        "is_guide": guide,
        "snapshot": {
            "name": f"대원 {member_id}",
            "species": {"code": "archive_guide" if guide else "bear-pot"},
            "form": "mosaic",
            "level": level,
            "rarity": 1,
            "stage": 5,
            "stats": {"care": 6, "focus": 6, "courage": 6, "insight": 6},
        },
    }


@pytest.mark.parametrize(
    ("level", "expected_hp"),
    [
        (-3, 3),
        (1, 3),
        (9, 3),
        (10, 4),
        (18, 4),
        (19, 5),
        (26, 5),
        (27, 6),
        (30, 6),
        (99, 6),
    ],
)
def test_combat_hp_follows_growth_milestones(level, expected_hp):
    assert combat_hp_for_level(level) == expected_hp


def test_starting_focus_uses_owned_party_average_and_ignores_guide_level():
    below = [_profile(1, 17), _profile(2, 30, guide=True)]
    at_milestone = [_profile(1, 17), _profile(2, 19), _profile(3, 1, guide=True)]

    assert starting_focus_for_party(
        below,
        configured_focus=3,
        max_focus=5,
    ) == (3, False, 17)
    assert starting_focus_for_party(
        at_milestone,
        configured_focus=3,
        max_focus=5,
    ) == (4, True, 18)


@pytest.mark.parametrize("configured_focus", [0, 1, 2, 4, 5])
def test_custom_starting_focus_does_not_receive_the_level_bonus(configured_focus):
    assert starting_focus_for_party(
        [_profile(1, 30)],
        configured_focus=configured_focus,
        max_focus=5,
    ) == (configured_focus, False, 30)


def test_new_battle_snapshots_balance_version_focus_and_member_hp():
    profiles = [_profile(1, 17), _profile(2, 19), _profile(3, 30, guide=True)]
    encounter = {
        "enemy_name": "테스트 엉킴",
        "enemy_max_guard": 100,
        "max_rounds": 4,
        "starting_focus": 3,
        "max_focus": 5,
        "weakness_cycle": ["care", "focus", "courage", "insight"],
    }

    battle = new_guardian_battle("balance-test", encounter, profiles)

    assert battle["balance_version"] == COMBAT_BALANCE_VERSION
    assert battle["configured_starting_focus"] == 3
    assert battle["starting_focus_level_bonus"] is True
    assert battle["average_party_level"] == 18
    assert battle["focus"] == 4
    assert [(member["hp"], member["max_hp"]) for member in battle["party"]] == [
        (4, 4),
        (5, 5),
        (6, 6),
    ]
    assert growth_index_for_party(profiles) == 59


def test_all_tangles_stay_inside_their_region_and_difficulty_bands():
    assert validate_tangle_balance(TANGLE_CATALOG) == []
    assert {tangle["region_code"] for tangle in TANGLE_CATALOG.values()} == set(
        REGION_COMBAT_BANDS
    )

    for region_code, band in REGION_COMBAT_BANDS.items():
        region_tangles = [
            tangle
            for tangle in TANGLE_CATALOG.values()
            if tangle["region_code"] == region_code
        ]
        assert len(region_tangles) == 3
        for tangle in region_tangles:
            difficulty = "elite" if tangle["elite"] else "normal"
            low, high = band[f"{difficulty}_barrier"]
            assert low <= tangle["barrier"] <= high
            intent_low, intent_high = band[f"{difficulty}_intent"]
            assert all(
                intent_low <= intent["power"] <= intent_high
                for intent in tangle["intents"]
            )


def test_wave_snapshot_keeps_region_and_unscaled_barrier_for_replay():
    profiles = [_profile(1, 18)]
    encounter = {
        "waves": ["tangled_ledger"],
        "max_rounds": 4,
        "starting_focus": 3,
        "max_focus": 5,
    }

    battle = new_guardian_battle("snapshot-test", encounter, profiles)
    wave = battle["waves"][0]

    assert wave["region_code"] == "moss_archive"
    assert wave["base_barrier"] == TANGLE_CATALOG["tangled_ledger"]["barrier"]
    assert wave["barrier"] == battle["enemy_max_guard"]
    assert wave["barrier"] >= wave["base_barrier"]
