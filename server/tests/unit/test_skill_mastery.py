"""숙련 기록과 해금 조건 판정.

설계서 11.6의 핵심 계약은 하나다 — **숙련은 성능을 1도 바꾸지 않는다.**
그래서 이 파일은 수치가 아니라 `무엇을 세는가`와 `언제 열리는가`만 검사한다.
"""

from app.services.skill_mastery import (
    COLLECTION_UNLOCKS,
    MASTERY_THRESHOLDS,
    MASTERY_UNLOCKS,
    MAX_MASTERY_LEVEL,
    _used_actions,
    mastery_level_for,
)


def test_mastery_level_climbs_in_five_steps_and_stops():
    assert mastery_level_for(0) == 0
    assert mastery_level_for(MASTERY_THRESHOLDS[0] - 1) == 0
    assert mastery_level_for(MASTERY_THRESHOLDS[0]) == 1
    assert mastery_level_for(MASTERY_THRESHOLDS[-1]) == MAX_MASTERY_LEVEL
    # 아무리 오래 써도 5단계를 넘지 않는다. 성능 축이 아니기 때문이다.
    assert mastery_level_for(100000) == MAX_MASTERY_LEVEL
    assert MAX_MASTERY_LEVEL == 5


def test_mastery_thresholds_only_grow():
    assert list(MASTERY_THRESHOLDS) == sorted(set(MASTERY_THRESHOLDS))


def test_only_party_actions_of_real_characters_are_counted():
    """길잡이와 적 행동은 숙련이 되지 않는다."""

    events = [
        {"type": "party_action", "member_id": 1, "action": "guard"},
        {"type": "party_action", "member_id": 1, "action": "attack"},
        {"type": "party_action", "member_id": 1, "action": "guard"},
        # 길잡이 — plant_id가 없어 세지 않는다.
        {"type": "party_action", "member_id": 9, "action": "guard"},
        # 적 행동과 결과 이벤트는 대상이 아니다.
        {"type": "enemy_action", "member_id": 1, "action": "guard"},
        {"type": "outcome", "outcome": "victory"},
        # 형식이 깨진 이벤트도 조용히 건너뛴다.
        {"type": "party_action", "member_id": None, "action": "guard"},
    ]
    used = _used_actions(events, {1: 77})
    assert used == [(77, "guard"), (77, "attack"), (77, "guard")]


def test_unlock_conditions_only_list_books_we_can_actually_count():
    """근거 없는 조건을 열린 척 등록하지 않는다."""

    from app.content.expeditions.skill_books import SKILL_BOOK_CATALOG

    for code, source, skill_code, goal in MASTERY_UNLOCKS:
        book = SKILL_BOOK_CATALOG[code]
        # 카탈로그가 말하는 획득 경로와 판정이 어긋나면 안 된다.
        assert book["acquire_kind"] == source, code
        assert goal > 0
        # 여섯 행동 코드만 센다.
        assert skill_code in {
            "attack",
            "unique_1",
            "unique_2",
            "selected_1",
            "selected_2",
            "guard",
        }

    for code, source, goal in COLLECTION_UNLOCKS:
        assert SKILL_BOOK_CATALOG[code]["acquire_kind"] == source, code
        assert goal > 0


def test_double_leaf_matches_the_documented_condition():
    """설계서 7.4의 `마음 지키기 누적 30회`를 그대로 옮겼는지 본다."""

    from app.content.expeditions.skill_books import SKILL_BOOK_CATALOG

    condition = next(item for item in MASTERY_UNLOCKS if item[0] == "double_leaf")
    assert condition[2] == "guard"
    assert condition[3] == 30
    assert SKILL_BOOK_CATALOG["double_leaf"]["unlock_hint"] == "마음 지키기 누적 30회"
