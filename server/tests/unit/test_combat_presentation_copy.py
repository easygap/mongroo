import pytest

from app.content.expeditions.combat_identity import combat_effect_summary


@pytest.mark.parametrize(
    ("effect", "expected"),
    [
        ("steady_read", "약점이 아닐 때 추가 피해"),
        ("weakness_pierce", "약점 적중 시 추가 피해"),
        ("last_stand", "체력이 낮을 때 추가 피해"),
        ("new_internal_effect", ""),
    ],
)
def test_effect_identifiers_do_not_leak_into_battle_captions(effect, expected):
    assert combat_effect_summary(effect, {}) == expected


def test_numeric_mechanics_keep_the_server_values():
    assert combat_effect_summary("shield_all", {"party_guard": 3}) == "전원 보호 3"
