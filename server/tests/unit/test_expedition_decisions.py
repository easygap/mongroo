import copy

import pytest

from app.content.expeditions.decisions import (
    decision_result,
    failure_cost,
    success_chance,
)
from app.content.expeditions.validator import ContentValidationError, validate_content
from app.services.expeditions import load_content


@pytest.mark.parametrize(
    "value,expected", [(3, 0), (4, 25), (5, 50), (6, 75), (7, 100)]
)
def test_preview_matches_all_four_possible_rolls(value, expected):
    assert success_chance(value, 8) == expected
    assert success_chance(value, 8, guaranteed=True) == 100


def test_repair_caps_resource_and_reports_only_the_actual_change():
    choice = {"success_effect": {"trail_light": 2}, "collects_loot": False}
    result = decision_result(choice, "clear", resolve=5, trail_light=11)
    assert result["trail_light"] == 12
    assert result["resource_changes"] == {"resolve": 0, "trail_light": 1}
    assert not result["collects_loot"]


def test_failed_decision_never_grants_success_effects():
    choice = {"success_effect": {"trail_light": 2, "finding": "주소 조각"}}
    result = decision_result(choice, "detour", resolve=3, trail_light=7)
    assert result["trail_light"] == 7
    assert result["finding"] is None
    assert not result["collects_loot"]


def test_old_saved_choices_preserve_their_reward_rules():
    for outcome in ("safe", "clear", "flourish"):
        result = decision_result({}, outcome, resolve=6, trail_light=10)
        assert result["collects_loot"]
        assert result["result_text"] == ""


def test_new_content_rejects_unbounded_recovery():
    content = copy.deepcopy(load_content())
    content["events"]["wet_label_order"]["choices"][1]["success_effect"] = {
        "trail_light": 999
    }
    with pytest.raises(ContentValidationError, match="회복 효과"):
        validate_content(content)


@pytest.mark.parametrize(
    "pending,expected",
    [
        ({}, 2),
        ({"resolve_guard": True}, 0),
        ({"resolve_cost_delta": -1}, 1),
        ({"resolve_cost_delta": -9}, 0),
    ],
)
def test_preview_and_resolution_use_the_same_skill_adjusted_risk(pending, expected):
    assert failure_cost({"resolve_cost": 2}, pending) == expected
