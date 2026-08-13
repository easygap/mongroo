import json
from pathlib import Path

from app.content.expeditions.combat_simulator import (
    POLICIES,
    STAGE_DIFFICULTY_BY_SHAPE,
    boss_simulation_cases,
    encounter_for_case,
    party_for_case,
    simulate_case,
    simulation_cases,
)
from app.content.expeditions.combat_balance import COMBAT_BALANCE_VERSION


def test_exact_matrix_covers_all_identity_and_stage_cells_once():
    cases = list(simulation_cases())

    assert len(cases) == 14_400
    assert len({case.key for case in cases}) == len(cases)
    assert len({case.species for case in cases}) == 15
    assert len({case.form for case in cases}) == 6
    assert {case.rarity for case in cases} == {1, 2, 3, 4, 5}
    assert len({case.region_code for case in cases}) == 4
    assert {case.stage_shape for case in cases} == {
        "tutorial",
        "standard",
        "elite",
        "mixed",
    }


def test_boss_matrix_uses_the_actual_three_phase_stage_eight_encounter():
    cases = list(boss_simulation_cases())

    assert len(cases) == 450
    assert len({case.key for case in cases}) == 450
    assert {case.level for case in cases} == {9}
    assert {case.stage_shape for case in cases} == {"boss"}
    encounter = encounter_for_case(cases[0])
    assert encounter["difficulty_code"] == "stage_8"
    assert [phase["threshold_bp"] for phase in encounter["boss_phases"]] == [
        10_000,
        6_600,
        3_300,
    ]


def test_free_party_fixture_has_one_owned_member_and_two_level_sixteen_guides():
    case = next(iter(simulation_cases()))
    party = party_for_case(case)

    assert [member["is_guide"] for member in party] == [False, True, True]
    assert [member["snapshot"]["level"] for member in party] == [case.level, 16, 16]
    assert party[0]["snapshot"]["species"]["code"] == case.species


def test_each_stage_shape_runs_with_its_public_fixed_threat_profile():
    cases = list(simulation_cases())

    for stage_shape, difficulty_code in STAGE_DIFFICULTY_BY_SHAPE.items():
        case = next(case for case in cases if case.stage_shape == stage_shape)
        assert encounter_for_case(case)["difficulty_code"] == difficulty_code


def test_each_policy_replays_the_same_case_deterministically():
    case = next(
        case
        for case in simulation_cases()
        if case.region_code == "moss_archive"
        and case.stage_shape == "standard"
        and case.level == 3
        and case.rarity == 1
    )

    for policy in POLICIES:
        first = simulate_case(case, policy)
        second = simulate_case(case, policy)
        assert first == second
        assert first.case == case
        assert first.max_rounds == 8
        assert sum(first.actions.values()) > 0
        assert sum(first.opportunities.values()) >= sum(first.actions.values())


def test_neutral_max_damage_policy_does_not_peek_at_matchup_power():
    case = next(
        case
        for case in simulation_cases()
        if case.species == "aloof-pot"
        and case.form == "sunny"
        and case.rarity == 1
        and case.level == 9
        and case.region_code == "moss_archive"
        and case.stage_shape == "tutorial"
    )

    neutral = simulate_case(case, "max_damage")
    weakness = simulate_case(case, "weakness_first")

    assert neutral.actions["unique_1"] == 1
    assert weakness.actions["unique_2"] == 1
    assert weakness.weakness_hits > neutral.weakness_hits


def test_checked_in_full_balance_report_passes_every_release_gate():
    repository_root = Path(__file__).resolve().parents[3]
    report = json.loads(
        (repository_root / "docs" / "expedition_combat_balance_report.json").read_text(
            encoding="utf-8"
        )
    )

    assert report["engine"] == "deterministic-exact-enumeration"
    assert report["combat_balance_version"] == COMBAT_BALANCE_VERSION
    assert report["dimensions"]["cases_per_policy"] == 14_400
    assert report["dimensions"]["boss_cases_per_policy"] == 450
    assert report["dimensions"]["total_battles"] == 44_550
    assert report["difficulty_fixture"] == STAGE_DIFFICULTY_BY_SHAPE
    assert report["balance_gates"]["all_passed"] is True
    assert all(check["pass"] for check in report["balance_gates"]["checks"].values())
