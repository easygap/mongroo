"""합동 수호전 밸런스 — 체크인된 리포트와 시뮬레이터 자체를 본다.

전 편성을 도는 데 40초쯤 걸려서 매 테스트마다 돌리지 않는다. 대신
`docs/joint_guard_balance_report.json`을 저장소에 두고, **그 리포트가 지금
콘텐츠에서 나온 것인지**를 여기서 확인한다. 장벽을 손대고 리포트를 다시 만들지
않으면 이 파일이 먼저 빨간불이 된다.

리포트를 다시 만들려면:

    python -m app.content.expeditions.joint_guard_simulator
"""

import copy
import json
from pathlib import Path

import pytest

from app.content.expeditions.joint_guard import (
    BEAST_CATALOG,
    DIFFICULTIES,
    JOINT_GUARD_VERSION,
    LAYER_BARRIERS,
    validate_joint_guard_content,
)
from app.content.expeditions.joint_guard_simulator import (
    FORMS,
    SPECIES_CODES,
    REFERENCE_POLICY,
    JointGuardCase,
    roster_for,
    simulate,
)

REPORT_PATH = (
    Path(__file__).resolve().parents[3] / "docs" / "joint_guard_balance_report.json"
)


@pytest.fixture(scope="module")
def report() -> dict:
    return json.loads(REPORT_PATH.read_text(encoding="utf-8"))


def test_checked_in_report_passes_every_measurable_gate(report):
    """설계서 5.1·5.2의 합격선.

    `unmeasurable`은 불합격이 아니다 — 잴 수 없는 것을 통과로도 불합격으로도
    적지 않는다. 잴 수 있는 것 중 하나라도 False면 여기서 걸린다.
    """
    gates = report["gates"]
    failed = [name for name, value in gates.items() if value is False]
    assert not failed, failed
    # 잴 수 있는 항목이 실제로 있어야 한다. 전부 unmeasurable이 되면 이 검사가
    # 아무것도 지키지 않는다.
    assert sum(1 for value in gates.values() if value is True) >= 5


def test_report_was_generated_from_the_shipped_content(report):
    """리포트가 지금 fixture에서 나온 것인지 본다.

    장벽만 고치고 리포트를 안 만들면 `밴드 안`이라고 적힌 낡은 숫자가 남는다.
    """
    assert report["joint_guard_version"] == JOINT_GUARD_VERSION
    assert report["layer_barriers"] == list(LAYER_BARRIERS)
    assert report["difficulty_barrier_scale_bp"] == {
        code: int(spec.get("barrier_scale_bp", 10_000))
        for code, spec in DIFFICULTIES.items()
    }
    assert report["dimensions"]["species"] == len(SPECIES_CODES)
    assert report["dimensions"]["forms"] == len(FORMS)
    assert report["dimensions"]["beasts"] == len(BEAST_CATALOG)
    assert report["engine"] == "deterministic-exact-enumeration"
    assert report["reference_policy"] == REFERENCE_POLICY


def test_reported_bands_match_the_design(report):
    """숫자를 직접 읽어 밴드 안인지 다시 센다.

    `gates`가 True인 것만 믿지 않는다 - 게이트 함수가 느슨해져도 여기서 걸린다.
    """
    outer = report["difficulty"]["outer_walk"]["clear_rate"]
    three = report["difficulty"]["three_layers"]["clear_rate"]
    solo = report["solo"]["clear_rate"]

    assert 85.0 <= outer <= 95.0, outer
    assert 50.0 <= three <= 70.0, three
    # 캐릭터 하나에 길잡이 다섯으로도 절반 가까이 간다(설계서 5.2).
    assert solo >= 45.0, solo


def test_no_form_is_locked_out(report):
    """어느 결도 못 깨는 결이 되지 않는다.

    설계서가 약속한 것은 `어느 결도 필수 입장 조건이 되지 않는다`이다. 밴드
    위로 올라간 결은 쉬울 뿐이지만, 밴드 **아래**로 크게 떨어진 결은 그 감정을
    고른 사람에게 벌이 된다.
    """
    for difficulty, floor in (("outer_walk", 80.0), ("three_layers", 45.0)):
        for form, summary in report["form_by_difficulty"][difficulty].items():
            assert summary["clear_rate"] >= floor, (difficulty, form, summary)


def test_matchup_reading_beats_not_reading(report):
    """상성표가 장식이 아니어야 한다."""
    for entry in report["auto_vs_manual"].values():
        assert entry["gap_points"] <= 0.0, entry


def test_simulation_is_deterministic():
    """같은 편성은 언제 돌려도 같은 결과다. 난수가 없기 때문이다."""
    case = JointGuardCase(
        beast_code="ledger_keeper",
        difficulty="three_layers",
        species="ninja-pot",
        form="sunny",
        level=23,
        rarity=1,
        real_members=1,
    )
    first = simulate(case, REFERENCE_POLICY)
    second = simulate(case, REFERENCE_POLICY)
    assert (first.awake, first.rounds, first.commands, first.swaps) == (
        second.awake,
        second.rounds,
        second.commands,
        second.swaps,
    )


@pytest.mark.parametrize("real_members", [1, 3, 6])
def test_roster_fills_the_rest_with_guides(real_members):
    case = JointGuardCase(
        beast_code="echo_keeper",
        difficulty="outer_walk",
        species="ninja-pot",
        form="mosaic",
        level=23,
        rarity=1,
        real_members=real_members,
    )
    roster = roster_for(case)

    assert len(roster) == 6
    assert sum(1 for e in roster if e["formation"] == "front") == 3
    guides = [e for e in roster if e["profile"]["is_guide"]]
    assert len(guides) == 6 - real_members
    # 실제 캐릭터가 앞에서부터 선다. 뒤로 몰면 편성 크기가 아니라 배치를 잰다.
    assert all(not e["profile"]["is_guide"] for e in roster[:real_members])


def test_each_layer_uses_four_distinct_matchups():
    """겹마다 네 짐승의 상성이 서로 달라야 한다.

    열(결) 균형만 맞추면 행이 쏠릴 수 있다. 실제로 첫 겹 약점이 햇살결
    둘·달빛결 둘이라, 첫 겹만 걷는 `겉꿈 산책`에서 달빛결만 99.6%로 밴드를
    벗어났다.
    """
    for index in range(3):
        for axis in ("weak_kel", "resist_kel"):
            row = [beast["layers"][index][axis] for beast in BEAST_CATALOG.values()]
            assert len(set(row)) == len(row), (index, axis, row)


def test_validator_catches_a_row_that_leans_one_way(monkeypatch):
    broken = copy.deepcopy(BEAST_CATALOG)
    # 첫 겹의 약점 둘을 같게 만든다.
    broken["echo_keeper"]["layers"][0]["weak_kel"] = broken["ledger_keeper"][
        "layers"
    ][0]["weak_kel"]
    monkeypatch.setattr("app.content.expeditions.joint_guard.BEAST_CATALOG", broken)
    errors = validate_joint_guard_content()
    assert any("겹의 weak_kel" in error for error in errors), errors


def test_every_beast_intent_has_its_own_visual_family():
    """짐승 열두 의도가 저마다의 연출을 쓴다.

    이 검사가 생기기 전까지 전부 `guardian.enemy-wave` 하나로 떨어졌다.
    `present_intent`가 `아직 전용 연출이 없는 일반 수호자`용 호환 계층이라고
    스스로 적어 두고 있었는데, 정작 짐승 넷이 거기에 얹혀 있었다 — 설계서
    9장이 금지한 `공용 연출로 끝내는 것`이다.

    잠꼬대도 자기 이름과 대상을 가진 의도라 함께 센다.
    """

    from app.content.expeditions.joint_guard import BEAST_CATALOG

    families: set[str] = set()
    for beast in BEAST_CATALOG.values():
        for intent in list(beast["intents"]) + [beast["sleeptalk"]]:
            family = intent["vfx_family"]
            assert family, intent["code"]
            assert family != "guardian.enemy-wave", intent["code"]
            # 의도 코드가 곧 이펙트 키다. 엉킴과 같은 규칙이다.
            assert intent["effect_key"] == intent["code"]
            assert intent["kel_fallback_family"] == f"kel.{intent['kel']}"
            families.add(family)
    assert len(families) == 12
