import copy
import hashlib
import json
from pathlib import Path

import pytest

from app.content.expeditions.skills import FORM_SKILLS, SIGNATURE_SKILLS
from app.content.expeditions.validator import (
    ContentValidationError,
    expand_map_templates,
    validate_content,
)
from app.services.expeditions import select_map_template


CONTENT_PATH = (
    Path(__file__).resolve().parents[2]
    / "app"
    / "content"
    / "expeditions"
    / "v1"
    / "moss_archive.json"
)


def _content() -> dict:
    with CONTENT_PATH.open(encoding="utf-8") as file:
        return json.load(file)


def test_moss_archive_has_three_valid_reachable_topologies():
    content = _content()

    validate_content(content)
    templates = expand_map_templates(content)

    assert [template["code"] for template in templates] == [
        "archive_loop_a",
        "archive_crossroads_b",
        "archive_ring_c",
    ]
    assert all(len(template["nodes"]) == 8 for template in templates)
    assert all(
        template["entrance"] in template["initial_revealed"] for template in templates
    )


def test_map_templates_keep_landmarks_locked_to_the_region_art():
    templates = expand_map_templates(_content())
    coordinates = [
        {
            node["code"]: (node["x"], node["y"])
            for node in template["nodes"]
        }
        for template in templates
    ]

    assert all(items == coordinates[0] for items in coordinates[1:])


def test_map_selection_is_deterministic_and_uses_all_templates_over_many_seeds():
    content = _content()
    selected: set[str] = set()

    for index in range(10_000):
        seed = hashlib.sha256(f"expedition-seed:{index}".encode()).hexdigest()
        first = select_map_template(content, seed, "heart_resonance")["code"]
        second = select_map_template(content, seed, "heart_resonance")["code"]
        assert first == second
        selected.add(first)

    assert selected == {"archive_loop_a", "archive_crossroads_b", "archive_ring_c"}


def test_tutorial_always_uses_fixed_map_even_when_seed_changes():
    content = _content()
    codes = {
        select_map_template(
            content,
            hashlib.sha256(str(index).encode()).hexdigest(),
            "tutorial",
        )["code"]
        for index in range(100)
    }
    assert codes == {"archive_loop_a"}


def test_validator_rejects_event_without_safe_choice():
    content = copy.deepcopy(_content())
    content["events"]["wet_label_order"]["choices"] = [
        choice
        for choice in content["events"]["wet_label_order"]["choices"]
        if not choice.get("safe")
    ]

    with pytest.raises(ContentValidationError) as error:
        validate_content(content)

    assert "안전 선택" in str(error.value)


def test_validator_rejects_route_that_bypasses_the_objective():
    content = copy.deepcopy(_content())
    content["map_templates"][0]["edges"].append(["pressed_gallery", "exit"])

    with pytest.raises(ContentValidationError) as error:
        validate_content(content)

    assert "목표를 거치지 않고 출구" in str(error.value)


def test_every_node_has_a_supported_environment_scene():
    content = _content()

    validate_content(content)

    scenes = {node["scene_key"] for node in content["map"]["nodes"]}
    assert scenes == {
        "dungeon_gate",
        "flooded_cave",
        "root_tunnel",
        "echo_well",
        "treasure_vault",
        "monster_den",
        "moon_tower",
    }


def test_validator_rejects_unknown_environment_scene():
    content = copy.deepcopy(_content())
    content["map"]["nodes"][0]["scene_key"] = "temporary_icon"

    with pytest.raises(ContentValidationError) as error:
        validate_content(content)

    assert "지원하지 않는 장면" in str(error.value)


def test_guardian_encounter_requires_authoritative_vfx_contract():
    content = copy.deepcopy(_content())
    del content["events"]["ledger_keeper"]["choices"][0]["effect_key"]

    with pytest.raises(ContentValidationError) as error:
        validate_content(content)

    assert "지원하지 않는 전투 이펙트" in str(error.value)


def test_guardian_encounter_defines_manual_round_contract():
    event = _content()["events"]["ledger_keeper"]
    encounter = event["encounter"]

    assert encounter["kind"] == "guardian"
    assert encounter["enemy_name"] == "돌비늘 장부지기"
    assert encounter["enemy_max_guard"] == 100
    assert encounter["max_rounds"] == 6
    assert encounter["starting_focus"] < encounter["max_focus"]
    assert encounter["weakness_cycle"] == [
        "insight",
        "care",
        "courage",
        "focus",
    ]
    assert {intent["target"] for intent in encounter["intents"]} == {
        "front",
        "all",
        "lowest",
    }
    assert {choice["effect_key"] for choice in event["choices"]} == {
        "insight_arc",
        "care_vines",
        "safe_guard",
    }


def test_guardian_encounter_rejects_missing_manual_combat_rules():
    content = copy.deepcopy(_content())
    content["events"]["ledger_keeper"]["encounter"]["intents"] = []

    with pytest.raises(ContentValidationError) as error:
        validate_content(content)

    assert "예고 공격이 2개 이상" in str(error.value)


def test_all_species_and_growth_forms_have_distinct_non_reward_skills():
    assert set(SIGNATURE_SKILLS) == {
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
    assert set(FORM_SKILLS) == {
        "sunny",
        "rainy",
        "ember",
        "moonlit",
        "sparkling",
        "mosaic",
    }
    definitions = [*SIGNATURE_SKILLS.values(), *FORM_SKILLS.values()]
    assert len({item["code"] for item in definitions}) == 16
    assert all(item["modes"] and item["phases"] for item in definitions)
    assert all("reward" not in item and "loot" not in item for item in definitions)
