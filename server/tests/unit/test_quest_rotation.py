from dataclasses import dataclass
from datetime import date, timedelta

from app.services.quest_rotation import QuestHistory, choose_daily_quest


@dataclass(frozen=True)
class Candidate:
    id: int
    code: str
    category: str
    burden_level: int


TODAY = date(2026, 7, 13)


def _catalog() -> list[Candidate]:
    return [
        Candidate(1, "A", "senses", 1),
        Candidate(2, "B", "rest", 1),
        Candidate(3, "C", "reflection", 1),
        Candidate(4, "D", "space", 2),
        Candidate(5, "E", "movement", 2),
    ]


def test_rotation_is_deterministic_and_catalog_order_independent():
    forward = choose_daily_quest(_catalog(), [], user_id=31, today=TODAY)
    reversed_order = choose_daily_quest(
        list(reversed(_catalog())), [], user_id=31, today=TODAY
    )

    assert forward.id == reversed_order.id


def test_rotation_avoids_recent_quest_when_an_alternative_exists():
    selected = choose_daily_quest(_catalog(), [], user_id=31, today=TODAY)
    history = [
        QuestHistory(
            quest_id=selected.id,
            category=selected.category,
            burden_level=selected.burden_level,
            quest_date=TODAY - timedelta(days=1),
        )
    ]

    next_selection = choose_daily_quest(_catalog(), history, user_id=31, today=TODAY)

    assert next_selection.id != selected.id


def test_rotation_uses_fresh_quest_before_target_burden():
    catalog = [
        Candidate(1, "FRESH_LIGHT", "rest", 1),
        Candidate(2, "RECENT_MEDIUM", "movement", 2),
    ]
    history = [
        QuestHistory(2, "movement", 2, TODAY - timedelta(days=1)),
    ]

    # user 14가 TODAY에 받는 목표 부담도는 2지만, 반복 방지가 우선이다.
    selected = choose_daily_quest(catalog, history, user_id=14, today=TODAY)

    assert selected.id == 1


def test_rotation_avoids_last_two_categories_when_possible():
    # 호출자가 역순 이력을 주더라도 날짜 기준 최근 두 건을 사용한다.
    history = [
        QuestHistory(92, "rest", 1, TODAY - timedelta(days=2)),
        QuestHistory(91, "senses", 1, TODAY - timedelta(days=1)),
    ]

    selected = choose_daily_quest(_catalog(), history, user_id=31, today=TODAY)

    assert selected.category not in {"senses", "rest"}


def test_rotation_uses_medium_burden_sparingly_but_does_not_starve_it():
    selections = [
        choose_daily_quest(_catalog(), [], user_id=user_id, today=TODAY)
        for user_id in range(1, 201)
    ]
    medium_count = sum(quest.burden_level == 2 for quest in selections)

    assert 20 <= medium_count <= 60
    assert medium_count < len(selections) / 2


def test_rotation_falls_back_when_only_one_burden_or_category_is_available():
    only = Candidate(1, "ONLY", "rest", 1)
    history = [QuestHistory(1, "rest", 1, TODAY - timedelta(days=1))]

    assert choose_daily_quest([only], history, user_id=7, today=TODAY) == only


def test_diary_context_prefers_matching_categories_without_changing_reward_rules():
    selected = choose_daily_quest(
        _catalog(),
        [],
        user_id=31,
        today=TODAY,
        preferred_categories=("movement", "body", "space"),
    )

    assert selected.category in {"movement", "space"}


def test_diary_context_falls_back_to_full_catalog_when_no_category_exists():
    selected = choose_daily_quest(
        _catalog(),
        [],
        user_id=31,
        today=TODAY,
        preferred_categories=("not-in-catalog",),
    )

    assert selected in _catalog()


def test_diary_context_does_not_reintroduce_recent_quest():
    catalog = [
        Candidate(1, "RECENT_CONTEXT", "reflection", 1),
        Candidate(2, "FRESH_OTHER", "rest", 1),
    ]
    history = [
        QuestHistory(1, "reflection", 1, TODAY - timedelta(days=1)),
    ]

    selected = choose_daily_quest(
        catalog,
        history,
        user_id=31,
        today=TODAY,
        preferred_categories=("reflection",),
    )

    assert selected.id == 2


def test_thirty_day_sequence_has_no_avoidable_fourteen_day_repeat():
    catalog = [
        Candidate(
            index,
            f"Q{index:02d}",
            f"category-{index % 10}",
            2 if index > 28 else 1,
        )
        for index in range(1, 37)
    ]
    history: list[QuestHistory] = []

    for day_offset in range(30):
        current_day = TODAY + timedelta(days=day_offset)
        recent = [
            entry
            for entry in history
            if entry.quest_date >= current_day - timedelta(days=14)
        ]
        selected = choose_daily_quest(catalog, recent, user_id=77, today=current_day)

        assert selected.id not in {entry.quest_id for entry in recent}
        if len(history) >= 2:
            assert selected.category not in {
                history[-1].category,
                history[-2].category,
            }
        history.append(
            QuestHistory(
                selected.id,
                selected.category,
                selected.burden_level,
                current_day,
            )
        )
