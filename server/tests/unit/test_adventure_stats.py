from datetime import date

from app.services.adventure import (
    DUNGEON_APPROACHES,
    DUNGEON_SCENES,
    FORM_STAT_MODIFIERS,
    PATROL_ENCOUNTERS,
    PATROL_REACTIONS,
    _dungeon_approach_performance,
    _dungeon_scene,
    _milestone_payload,
    _patrol_encounter,
    _patrol_reaction,
    _performance,
    _route_payloads,
    character_stats,
)


def test_emotion_forms_have_equal_total_stat_budget():
    assert {sum(modifiers.values()) for modifiers in FORM_STAT_MODIFIERS.values()} == {
        4
    }


def test_growth_stage_increases_every_stat_without_changing_form_budget():
    for form in FORM_STAT_MODIFIERS:
        stage_two = character_stats(2, form)
        stage_three = character_stats(3, form)
        assert all(stage_three[stat] == value + 1 for stat, value in stage_two.items())


def test_research_bonus_only_changes_collection_and_caps_quantity():
    character = {
        "stats": {"care": 9, "focus": 9},
        "outfit": None,
    }
    score, quantity = _performance(
        character,
        ("care", "focus"),
        "patrol",
        research_bonus=10,
    )
    assert score == 18
    assert quantity == 3


def test_dungeon_approach_combines_growth_outfit_and_route_fit():
    character = {
        "stats": {"care": 7, "focus": 6, "courage": 6, "insight": 5},
        "outfit": {"bonus": {"context": "dungeon", "stat": "focus", "amount": 2}},
    }
    dungeon = {"stats": ("focus", "insight")}

    score, quantity, outcome = _dungeon_approach_performance(
        character,
        dungeon,
        DUNGEON_APPROACHES["focus"],
    )
    assert (score, quantity, outcome) == (10, 2, "resonant")

    score, quantity, outcome = _dungeon_approach_performance(
        character,
        dungeon,
        DUNGEON_APPROACHES["courage"],
        research_bonus=1,
    )
    assert (score, quantity, outcome) == (6, 2, "steady")


def test_patrol_preview_uses_collection_bonus_without_changing_currency():
    character = {
        "stage": 2,
        "stats": {"care": 9, "focus": 5, "courage": 5, "insight": 8},
        "outfit": None,
    }

    routes = _route_payloads(character, collection_bonus=1)
    edge = next(route for route in routes if route["code"] == "greenhouse_edge")
    locked = next(route for route in routes if route["code"] == "moonlit_lane")

    assert edge["performance_score"] == 17
    assert edge["projected_quantity"] == 3
    assert edge["best_match"] is True
    assert edge["reward"] == {
        "exp": 0,
        "seeds": 3,
        "item_code": "pressed_leaf_map",
    }
    assert locked["performance_score"] == 0
    assert locked["projected_quantity"] == 0
    assert locked["best_match"] is False


def test_patrol_preview_tie_recommends_latest_unlocked_route():
    character = {
        "stage": 3,
        "stats": {"care": 6, "focus": 6, "courage": 6, "insight": 6},
        "outfit": None,
    }

    routes = _route_payloads(character)
    best = [route["code"] for route in routes if route["best_match"]]

    assert best == ["moonlit_lane"]


def test_patrol_encounters_are_varied_and_deterministic_per_departure():
    assert set(PATROL_ENCOUNTERS) == {
        "greenhouse_edge",
        "moonlit_lane",
        "glass_rooftop",
        "dawn_canopy_walk",
    }
    assert all(len(encounters) == 3 for encounters in PATROL_ENCOUNTERS.values())
    encounters = [
        encounter
        for route_encounters in PATROL_ENCOUNTERS.values()
        for encounter in route_encounters
    ]
    assert len({encounter["code"] for encounter in encounters}) == 12
    assert all(set(encounter) == {"code", "title", "text"} for encounter in encounters)
    assert all(all(encounter.values()) for encounter in encounters)

    departure = date(2026, 8, 4)
    first = _patrol_encounter(17, departure, "moonlit_lane")
    second = _patrol_encounter(17, departure, "moonlit_lane")

    assert first == second
    assert first in PATROL_ENCOUNTERS["moonlit_lane"]

    assert set(PATROL_REACTIONS) == set(FORM_STAT_MODIFIERS)
    reactions = [reaction for lines in PATROL_REACTIONS.values() for reaction in lines]
    assert len(reactions) == 12
    assert len(set(reactions)) == 12
    assert all(reactions)
    reaction = _patrol_reaction(17, departure, "moonlit_lane", "moonlit")
    assert reaction == _patrol_reaction(
        17,
        departure,
        "moonlit_lane",
        "moonlit",
    )
    assert reaction in PATROL_REACTIONS["moonlit"]
    assert (
        _patrol_reaction(17, departure, "moonlit_lane", "unknown")
        in PATROL_REACTIONS["mosaic"]
    )


def test_dungeon_scenes_are_varied_and_deterministic_per_approach():
    assert set(DUNGEON_SCENES) == {
        "moss_archive",
        "echo_well",
        "starlight_seed_vault",
        "heartwood_observatory",
    }
    assert all(len(scenes) == 3 for scenes in DUNGEON_SCENES.values())
    scenes = [
        scene for dungeon_scenes in DUNGEON_SCENES.values() for scene in dungeon_scenes
    ]
    assert len({scene["code"] for scene in scenes}) == 12
    assert all(set(scene) == {"code", "title", "text"} for scene in scenes)
    assert all(all(scene.values()) for scene in scenes)

    local_day = date(2026, 8, 4)
    first = _dungeon_scene(17, local_day, "echo_well", "focus")
    second = _dungeon_scene(17, local_day, "echo_well", "focus")

    assert first == second
    assert first in DUNGEON_SCENES["echo_well"]


def test_adventure_milestones_start_with_diary_and_do_not_add_rewards():
    milestones = _milestone_payload(
        {
            "diary_days": 7,
            "patrol_returns": 5,
            "dungeon_runs": 4,
            "research_projects": 2,
            "chapter_completed": 0,
        }
    )

    assert milestones["current_title"] == "정원 길잡이"
    assert milestones["unlocked_count"] == 2
    assert milestones["total_count"] == 5
    assert milestones["items"][0] == {
        "code": "seven_day_diary",
        "name": "일곱 날의 마음",
        "description": "50자 이상 마음 일기를 서로 다른 7일에 남겨요.",
        "progress": 7,
        "target": 7,
        "unlocked": True,
        "title": "마음 기록가",
    }
    assert "reward" not in milestones["items"][0]
    assert milestones["items"][2]["progress"] == 4
    assert milestones["items"][2]["unlocked"] is False
