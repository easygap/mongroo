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
from app.content.expeditions.combat_difficulty import (
    COMBAT_DIFFICULTY_VERSION,
    ENEMY_MECHANICS,
    STAGE_THREAT_PROFILES,
    difficulty_profile_for_encounter,
    enemy_mechanic,
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
        (5, 5),
        (6, 6),
        (8, 8),
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


def test_stage_threat_is_fixed_by_stage_and_never_reads_party_level():
    low_party = [_profile(1, 3)]
    high_party = [_profile(1, 30)]
    encounter = {
        "waves": ["tangled_ledger"],
        "max_rounds": 4,
        "starting_focus": 3,
        "max_focus": 5,
        "difficulty_code": "stage_7",
    }

    low = new_guardian_battle("fixed-threat-low", encounter, low_party)
    high = new_guardian_battle("fixed-threat-high", encounter, high_party)

    assert low["difficulty"] == high["difficulty"]
    assert low["difficulty"]["code"] == "stage_7"
    assert low["difficulty_version"] == COMBAT_DIFFICULTY_VERSION
    # 성장 보정은 이미 공개된 장벽에만 반영되고 적 공격 계수에는 섞이지 않는다.
    assert high["enemy_max_guard"] > low["enemy_max_guard"]
    assert low["difficulty"]["intent_power_bonus"] == 0


def test_stage_threat_curve_adds_barrier_and_pattern_depth_monotonically():
    ordered = [
        STAGE_THREAT_PROFILES[code]
        for code in ("stage_1", "stage_3", "stage_4", "stage_7", "stage_8")
    ]

    assert [profile["tier"] for profile in ordered] == [1, 2, 3, 4, 5]
    assert [profile["barrier_bp"] for profile in ordered] == sorted(
        profile["barrier_bp"] for profile in ordered
    )
    assert [profile["pattern_depth"] for profile in ordered] == sorted(
        profile["pattern_depth"] for profile in ordered
    )
    assert difficulty_profile_for_encounter({"boss_phases": [{}]})["code"] == (
        "stage_8"
    )


def test_every_enemy_mechanic_has_a_player_readable_counter_and_unlock_gate():
    assert len(ENEMY_MECHANICS) == 8
    for code, definition in ENEMY_MECHANICS.items():
        assert definition["counter"].endswith("요.")
        assert enemy_mechanic(code, unlock_level=2, mechanic_level=1) is None
        opened = enemy_mechanic(code, unlock_level=2, mechanic_level=2)
        assert opened is not None
        assert opened["code"] == code
