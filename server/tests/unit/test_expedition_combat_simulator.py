import json
from pathlib import Path

from app.content.expeditions.combat_simulator import (
    POLICIES,
    party_for_case,
    simulate_case,
    simulation_cases,
)


def test_exact_matrix_covers_all_identity_and_stage_cells_once():
    cases = list(simulation_cases())

    assert len(cases) == 9_600
    assert len({case.key for case in cases}) == len(cases)
    assert len({case.species for case in cases}) == 10
    assert len({case.form for case in cases}) == 6
    assert {case.rarity for case in cases} == {1, 2, 3, 4, 5}
    assert len({case.region_code for case in cases}) == 4
    assert {case.stage_shape for case in cases} == {
        "tutorial",
        "standard",
        "elite",
        "mixed",
    }


def test_free_party_fixture_has_one_owned_member_and_two_level_sixteen_guides():
    case = next(iter(simulation_cases()))
    party = party_for_case(case)

    assert [member["is_guide"] for member in party] == [False, True, True]
    assert [member["snapshot"]["level"] for member in party] == [case.level, 16, 16]
    assert party[0]["snapshot"]["species"]["code"] == case.species


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
    case = next(iter(simulation_cases()))

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
    assert report["dimensions"]["cases_per_policy"] == 9_600
    assert report["dimensions"]["total_battles"] == 28_800
    assert report["balance_gates"]["all_passed"] is True
    assert all(
        check["pass"]
        for check in report["balance_gates"]["checks"].values()
    )
