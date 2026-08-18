import copy
import hashlib
import json
from pathlib import Path

import pytest

from app.content.expeditions.skills import FORM_SKILLS, SIGNATURE_SKILLS
from app.content.expeditions.combat_identity import SPECIES_SKILLS
from app.content.expeditions.relationship_story import (
    RELATIONSHIP_MOMENTS,
    SPECIES_DUET_VOICES,
    SPECIES_RELATIONSHIP_LINES,
    relationship_beat,
    relationship_duet,
)
from app.content.expeditions.validator import (
    ContentValidationError,
    expand_map_templates,
    validate_content,
)
from app.services.expeditions import (
    _stage_arena,
    load_content,
    select_map_template,
    shipped_region_codes,
)


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


def test_every_region_ships_three_complete_branching_story_threads():
    regions = (
        "moss_archive",
        "echo_well",
        "starlight_seed_vault",
        "heartwood_observatory",
    )
    threads = [
        thread
        for region_code in regions
        for thread in load_content(region_code)["run_threads"]
    ]

    assert len(threads) == 12
    assert len({thread["code"] for thread in threads}) == 12
    assert (
        sum(
            len(thread["seed_variants"])
            + len(thread["echo_variants"])
            + len(thread["payoff_variants"])
            for thread in threads
        )
        == 84
    )
    assert all(
        set(thread["payoff_variants"])
        == {
            "careful",
            "bold",
            "relational",
        }
        for thread in threads
    )


def test_every_stage_builds_a_walkable_two_landmark_field():
    for region_code in shipped_region_codes():
        content = load_content(region_code)
        landmark_positions = {
            (float(node["x"]), float(node["y"]))
            for node in content["map"]["nodes"]
            if node["type"] not in {"entrance", "exit"}
        }
        for stage in content["stages"]:
            field, _events, event_code, story = _stage_arena(content, stage)
            nodes = {node["code"]: node for node in field["nodes"]}

            assert field["entrance"] == "stage_entry"
            assert field["initial_revealed"] == ["stage_entry", "stage_den"]
            assert field["edges"] == [["stage_entry", "stage_den"]]
            assert set(nodes) == {"stage_entry", "stage_den"}
            assert (nodes["stage_entry"]["x"], nodes["stage_entry"]["y"]) != (
                nodes["stage_den"]["x"],
                nodes["stage_den"]["y"],
            )
            assert (nodes["stage_den"]["x"], nodes["stage_den"]["y"]) in (
                landmark_positions
            )
            assert story["stage_no"] == stage["no"]
            assert story["title"] == stage["title"]
            assert story["approach"] and story["objective"]
            assert story["destination_name"] and story["destination_hint"]
            if stage["kind"] == "camp":
                assert event_code is None
            else:
                assert event_code


def test_every_current_species_pair_has_three_relationship_beats():
    species_codes = sorted(set(SPECIES_SKILLS) - {"archive_guide"})

    assert set(SPECIES_RELATIONSHIP_LINES) == set(species_codes)
    rendered = []
    for left_index, left_code in enumerate(species_codes):
        for right_code in species_codes[left_index:]:
            members = [
                {"name": "하나", "species_code": left_code},
                {"name": "두리", "species_code": right_code},
            ]
            for moment in RELATIONSHIP_MOMENTS:
                beat = relationship_beat(members, moment=moment, seed="story-test")
                assert beat is not None
                assert "하나" in beat["caption"] or "두리" in beat["caption"]
                assert "{" not in beat["caption"]
                rendered.append(beat)

    assert len(rendered) == 360


def test_every_distinct_species_pair_has_a_core_and_reprise_duet():
    species_codes = sorted(set(SPECIES_SKILLS) - {"archive_guide"})

    assert set(SPECIES_DUET_VOICES) == set(species_codes)
    core_codes: set[str] = set()
    reprise_codes: set[str] = set()
    for left_index, left_code in enumerate(species_codes):
        for right_code in species_codes[left_index + 1 :]:
            members = [
                {"name": "하나", "species_code": left_code},
                {"name": "두리", "species_code": right_code},
            ]
            core = relationship_duet(members)
            reprise = relationship_duet(members, reprise=True)

            assert core is not None
            assert reprise is not None
            assert core["variant"] == "core"
            assert len(core["lines"]) == 4
            assert core["narration"]
            assert reprise["variant"] == "reprise"
            assert len(reprise["lines"]) == 2
            assert reprise["narration"] == ""
            assert all(
                line["speaker_name"] in {"하나", "두리"}
                and line["text"]
                and len(line["text"]) <= 60
                for line in [*core["lines"], *reprise["lines"]]
            )
            core_codes.add(core["code"])
            reprise_codes.add(reprise["code"])

    assert len(core_codes) == 105
    assert len(reprise_codes) == 105


def test_map_templates_keep_landmarks_locked_to_the_region_art():
    templates = expand_map_templates(_content())
    coordinates = [
        {node["code"]: (node["x"], node["y"]) for node in template["nodes"]}
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
    assert encounter["max_rounds"] == 8
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
    assert [phase["threshold_bp"] for phase in encounter["boss_phases"]] == [
        10_000,
        6_600,
        3_300,
    ]
    assert [phase["name"] for phase in encounter["boss_phases"]] == [
        "색인 수호",
        "뿌리 봉쇄",
        "최종 말소",
    ]
    assert encounter["difficulty_code"] == "stage_8"
    assert all(phase["rule_name"] for phase in encounter["boss_phases"])
    assert all(len(phase["intents"]) == 2 for phase in encounter["boss_phases"])
    assert {
        intent.get("vfx_family")
        for phase in encounter["boss_phases"]
        for intent in phase["intents"]
        if intent.get("vfx_family")
    } == {
        "guardian.record-wave",
        "guardian.root-lockdown",
        "guardian.seal-crush",
        "guardian.final-redaction",
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
