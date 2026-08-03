from app.services.adventure import FORM_STAT_MODIFIERS, _performance, character_stats


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
