import pytest

from app.services.plants import (
    LEVEL_EXP_THRESHOLDS,
    level_from_exp,
    next_stage_exp,
    stage_from_exp,
)


def test_stage_thresholds():
    assert stage_from_exp(0) == 1
    assert stage_from_exp(19) == 1
    assert stage_from_exp(20) == 2
    assert stage_from_exp(99) == 2
    assert stage_from_exp(100) == 3
    assert stage_from_exp(249) == 3
    assert stage_from_exp(250) == 4
    assert stage_from_exp(449) == 4
    assert stage_from_exp(450) == 5
    assert stage_from_exp(5000) == 5


def test_next_stage_exp():
    assert next_stage_exp(0) == 20
    assert next_stage_exp(20) == 100
    assert next_stage_exp(449) == 450
    assert next_stage_exp(450) is None


@pytest.mark.parametrize(
    ("level", "threshold"),
    list(enumerate(LEVEL_EXP_THRESHOLDS, start=1)),
)
def test_every_combat_level_threshold(level, threshold):
    assert level_from_exp(threshold) == level
    if level > 1:
        assert level_from_exp(threshold - 1) == level - 1


def test_combat_level_is_capped_at_thirty():
    assert level_from_exp(5000) == 30
