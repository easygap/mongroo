"""장거리 개척 콘텐츠 계약.

표를 손으로 고치다 보면 조용히 깨지는 것들이 있다. 여기서 매번 다시 센다.
"""

import copy

import pytest

from app.content.expeditions.journey import (
    DIRECTIONS,
    LEG_PARTY_SIZE,
    max_own_members,
    route_of,
    routes_for,
    validate_journey_content,
)


def test_shipped_content_is_consistent():
    assert validate_journey_content() == []


def test_three_directions_match_the_design_table():
    """설계서 9.8의 표. 구간 수와 예상 시간을 코드가 그대로 들고 있다."""

    assert [
        (code, spec["max_legs"], spec["minutes"], spec["requires_region"])
        for code, spec in DIRECTIONS.items()
    ] == [
        ("beyond_the_well", 2, (16, 24), "echo_well"),
        ("starlight_crossing", 3, (22, 32), "starlight_seed_vault"),
        ("outside_the_greenhouse", 3, (25, 35), "heartwood_observatory"),
    ]


@pytest.mark.parametrize("code", list(DIRECTIONS))
def test_own_member_ceiling_is_two_per_leg(code):
    """`자체 캐릭터 최대 사용`은 따로 적지 않고 구간 수에서 나온다.

    설계서 표의 `4 / 4~6 / 6`이 이 계산과 같아야 한다. 두 값을 각각 들고 있으면
    구간 수만 고치고 최대 인원을 안 고치는 날이 온다.
    """

    assert max_own_members(code) == DIRECTIONS[code]["max_legs"] * LEG_PARTY_SIZE


@pytest.mark.parametrize("code", list(DIRECTIONS))
def test_every_camp_offers_two_different_places(code):
    """갈림길 둘이 같은 지역이면 고르는 의미가 없다."""

    for index in range(DIRECTIONS[code]["max_legs"]):
        routes = routes_for(code, index)
        assert len(routes) == 2, (code, index)
        assert len({route["region_code"] for route in routes}) == 2, (code, index)
        for route in routes:
            assert route["hint"], (code, index, route["code"])
            assert route_of(code, index, route["code"]) == route


def test_routes_outside_the_direction_are_empty():
    # 구간 수를 넘겨 물으면 빈 목록이다. 야영지에서 `다음 갈림길`을 계산할 때
    # 이 자리가 곧 `더 갈 곳이 없다`는 뜻이 된다.
    assert routes_for("beyond_the_well", 2) == []
    assert routes_for("beyond_the_well", -1) == []
    assert routes_for("no_such_direction", 0) == []
    assert route_of("beyond_the_well", 0, "no_such_route") is None


def test_validator_catches_a_camp_that_leads_to_one_place(monkeypatch):
    broken = copy.deepcopy(DIRECTIONS)
    first = broken["beyond_the_well"]["routes"][0]
    first[1]["region_code"] = first[0]["region_code"]
    monkeypatch.setattr("app.content.expeditions.journey.DIRECTIONS", broken)
    errors = validate_journey_content()
    assert any("같은 지역을" in error for error in errors), errors


def test_validator_catches_a_route_to_nowhere(monkeypatch):
    broken = copy.deepcopy(DIRECTIONS)
    broken["beyond_the_well"]["routes"][0][0]["region_code"] = "no_such_region"
    monkeypatch.setattr("app.content.expeditions.journey.DIRECTIONS", broken)
    errors = validate_journey_content()
    assert any("없는 지역을 가리킵니다" in error for error in errors), errors


def test_validator_catches_a_leg_count_that_lost_its_routes(monkeypatch):
    broken = copy.deepcopy(DIRECTIONS)
    broken["starlight_crossing"]["routes"].pop()
    monkeypatch.setattr("app.content.expeditions.journey.DIRECTIONS", broken)
    errors = validate_journey_content()
    assert any("갈림길 표는" in error for error in errors), errors
