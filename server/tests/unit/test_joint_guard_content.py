"""합동 수호전 콘텐츠가 설계 계약을 지키는지 본다.

`docs/guardian_raid_design.md` 10장의 콘텐츠 검사 항목이다. 이 콘텐츠는 판정을
하지 않는 순수 fixture라, 여기서 막지 못한 계약 위반은 전부 화면까지 그대로
나간다. 그래서 검사를 카탈로그 옆이 아니라 테스트에도 둔다 - validate 자신이
느슨해지면 validate를 부르는 테스트만으로는 알 수 없기 때문이다.
"""

import copy

import pytest

from app.content.expeditions.combat_identity import KEL_LABELS
from app.content.expeditions.joint_guard import (
    ALLOWED_INTENT_TARGETS,
    BEAST_CATALOG,
    DECISIVE_MOMENTS,
    DIFFICULTIES,
    LAYER_BARRIERS,
    LAYER_ROUNDS,
    beast_story,
    layer_warning,
    layers_for,
    moment_code_for_layer,
    round_schedule,
    validate_joint_guard_content,
)


def test_shipped_catalog_passes_its_own_validator():
    assert validate_joint_guard_content() == []


def test_four_beasts_one_per_region():
    assert len(BEAST_CATALOG) == 4
    regions = [beast["region_code"] for beast in BEAST_CATALOG.values()]
    assert sorted(regions) == [
        "echo_well",
        "heartwood_observatory",
        "moss_archive",
        "starlight_seed_vault",
    ]


def test_every_kel_is_weakness_twice_and_resistance_twice():
    """여섯 결이 정확히 같은 횟수로 등장한다.

    이것이 무너지면 특정 감정을 가진 캐릭터가 유리해지고, `세상에 나쁜 감정이
    없다`는 전제가 수치로 깨진다. 12겹 전체를 직접 세어 본다.
    """
    weak: dict[str, int] = {kel: 0 for kel in KEL_LABELS}
    resist: dict[str, int] = {kel: 0 for kel in KEL_LABELS}
    for beast in BEAST_CATALOG.values():
        for layer in beast["layers"]:
            weak[layer["weak_kel"]] += 1
            resist[layer["resist_kel"]] += 1

    assert sum(weak.values()) == 12
    assert set(weak.values()) == {2}, weak
    assert set(resist.values()) == {2}, resist


def test_no_layer_resists_and_is_weak_to_the_same_kel():
    for code, beast in BEAST_CATALOG.items():
        for index, layer in enumerate(beast["layers"]):
            assert layer["weak_kel"] != layer["resist_kel"], f"{code}[{index}]"


def test_each_layer_has_one_decisive_moment_with_a_bypass():
    """역할이 없어도 넘을 수 있어야 한다.

    설계서 12장이 금지하는 지름길 중 첫 번째가 `역할 미보유를 입장·시작 차단
    사유로 만드는 것`이다. 우회가 빠진 순간은 그 금지를 어긴다.
    """
    assert sorted(m["layer_index"] for m in DECISIVE_MOMENTS.values()) == [0, 1, 2]
    for code, moment in DECISIVE_MOMENTS.items():
        assert moment["optimal"], code
        assert moment["bypass"]["text"], code
        assert moment["round_no"] <= LAYER_ROUNDS, code
        # 예고 없이 오는 큰 패턴은 없다.
        assert moment["telegraph_rounds"] >= 1, code


def test_decisive_moments_never_block_actions_or_end_the_run():
    """즉사·전멸·행동 봉쇄가 없다(설계서 4.4).

    최악이어도 HP와 라운드를 잃는 것까지다. 위력 상한을 숫자로 못 박아 둔다.
    """
    for code, moment in DECISIVE_MOMENTS.items():
        assert moment["power"] <= 3, code
        assert moment["target"] in {"all", "front", "lowest", "none"}, code


def test_difficulties_offer_a_practice_run_and_the_full_dream():
    assert DIFFICULTIES["outer_walk"]["layers"] == 1
    assert DIFFICULTIES["outer_walk"]["tutorial"] is True
    assert DIFFICULTIES["three_layers"]["layers"] == 3


def test_layers_for_fills_barriers_and_matchups():
    layers = layers_for("ledger_keeper", "three_layers")
    assert [layer["barrier"] for layer in layers] == list(LAYER_BARRIERS)
    assert [layer["rounds"] for layer in layers] == [LAYER_ROUNDS] * 3
    assert [layer["moment_code"] for layer in layers] == [
        moment_code_for_layer(0),
        moment_code_for_layer(1),
        moment_code_for_layer(2),
    ]
    # 결 이름은 코드가 아니라 사람이 읽는 말로도 함께 나간다.
    assert layers[0]["weak_kel_label"] == KEL_LABELS[layers[0]["weak_kel"]]

    # `겉꿈 산책`은 같은 첫 겹을 걷지만 장벽이 더 두껍다. 한 겹으로 끝나는
    # 난이도라 뒤에 남길 체력을 아낄 이유가 없고, 두 난이도가 같은 장벽을
    # 쓰면 두 밴드를 동시에 만족시킬 수 없다는 것이 R4에서 확인됐다.
    walk = layers_for("ledger_keeper", "outer_walk")
    assert len(walk) == 1
    assert walk[0]["name"] == layers[0]["name"]
    assert walk[0]["weak_kel"] == layers[0]["weak_kel"]
    assert walk[0]["barrier"] > layers[0]["barrier"]
    assert walk[0]["barrier"] == walk[0]["max_barrier"]


@pytest.mark.parametrize("beast_code", sorted(BEAST_CATALOG))
def test_story_lines_pick_the_particle_from_the_name(beast_code):
    """`씨앗함를`처럼 조사가 틀린 문장이 화면에 나가지 않는다.

    끌어안은 것의 이름은 짐승마다 받침이 다르다. 원문에 조사를 박아 두면
    넷 중 둘이 틀린다.
    """
    for key in ("enter", "awake", "withdraw"):
        line = beast_story(beast_code, key)
        assert "{" not in line, line
        assert "를를" not in line and "을을" not in line
    enter = beast_story(beast_code, "enter")
    holding = BEAST_CATALOG[beast_code]["holding"]
    expected = "을" if _has_final(holding) else "를"
    assert f"{holding}{expected}" in enter, enter


def _has_final(word: str) -> bool:
    return (ord(word[-1]) - 0xAC00) % 28 != 0


def test_validator_catches_an_unbalanced_matchup_table(monkeypatch):
    """검사가 실제로 무언가를 막는지 확인한다.

    통과만 확인하면 validate가 빈 함수가 되어도 초록불이다. 균형을 일부러
    무너뜨려 같은 검사가 빨간불이 되는 것까지 본다.
    """
    broken = copy.deepcopy(BEAST_CATALOG)
    broken["ledger_keeper"]["layers"][0]["weak_kel"] = "mosaic"
    monkeypatch.setattr(
        "app.content.expeditions.joint_guard.BEAST_CATALOG", broken
    )
    errors = validate_joint_guard_content()
    assert any("약점으로 2번" in error for error in errors), errors


def test_validator_catches_win_lose_vocabulary(monkeypatch):
    """짐승은 이기는 상대가 아니다(설계서 7장)."""
    broken = copy.deepcopy(DECISIVE_MOMENTS)
    broken["big_toss"]["bypass"]["text"] = "전원 방어로 승리하세요."
    monkeypatch.setattr(
        "app.content.expeditions.joint_guard.DECISIVE_MOMENTS", broken
    )
    errors = validate_joint_guard_content()
    assert any("금지 표현" in error for error in errors), errors


def test_validator_catches_a_moment_without_a_bypass(monkeypatch):
    broken = copy.deepcopy(DECISIVE_MOMENTS)
    broken["tight_hug"]["bypass"] = {"text": "", "cost": ""}
    monkeypatch.setattr(
        "app.content.expeditions.joint_guard.DECISIVE_MOMENTS", broken
    )
    errors = validate_joint_guard_content()
    assert any("우회" in error for error in errors), errors


def test_catalog_carries_no_economy_reward():
    """경제 보상 0(설계서 6장).

    XP·씨앗 키가 카탈로그에 생기는 순간 그라인딩이 시작된다. 아예 없는 것을
    구조로 확인한다.
    """
    banned_keys = {"exp", "xp", "seeds", "seed", "reward", "currency"}

    def walk(node: object, path: str) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                assert key not in banned_keys, f"{path}.{key}"
                walk(value, f"{path}.{key}")
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, f"{path}[{index}]")

    walk(BEAST_CATALOG, "beasts")
    walk(DECISIVE_MOMENTS, "moments")
    walk(DIFFICULTIES, "difficulties")


@pytest.mark.parametrize("beast_code", sorted(BEAST_CATALOG))
def test_intents_reuse_the_existing_target_vocabulary(beast_code):
    """새 의도 종류를 만들지 않는다(설계서 4.3).

    `front|lowest|all` 밖으로 나가면 구버전 사용자가 다시 배워야 하고 앱의
    예고 표시도 갈라진다.
    """
    beast = BEAST_CATALOG[beast_code]
    intents = [*beast["intents"], beast["sleeptalk"]]
    assert len(beast["intents"]) >= 2
    for intent in intents:
        assert intent["target"] in ALLOWED_INTENT_TARGETS, intent
        assert 1 <= intent["power"] <= 3, intent


@pytest.mark.parametrize("beast_code", sorted(BEAST_CATALOG))
def test_sleeptalk_is_weaker_than_the_main_intent(beast_code):
    """예고 두 줄의 우선순위가 뒤집히지 않는다."""
    beast = BEAST_CATALOG[beast_code]
    weakest_main = min(intent["power"] for intent in beast["intents"])
    assert beast["sleeptalk"]["power"] <= weakest_main


def test_intent_codes_are_unique_across_the_catalog():
    codes = [
        intent["code"]
        for beast in BEAST_CATALOG.values()
        for intent in [*beast["intents"], beast["sleeptalk"]]
    ]
    assert len(codes) == len(set(codes)), codes


def test_beast_telegraphs_describe_a_gesture_not_a_threat(monkeypatch):
    """짐승 예고에 위협 어휘가 들어가면 걸린다.

    반대로 우리 편 행동 설명은 `공명 공격`이라는 정식 이름을 쓰므로 같은
    단어여도 막지 않는다 - 두 자리를 갈라 놓았는지 함께 확인한다.
    """
    broken = copy.deepcopy(BEAST_CATALOG)
    broken["ledger_keeper"]["intents"][0]["telegraph"] = "맨 앞 대원을 노려요."
    monkeypatch.setattr("app.content.expeditions.joint_guard.BEAST_CATALOG", broken)
    assert any("위협 어휘" in error for error in validate_joint_guard_content())


def test_player_action_text_may_say_gongyeok():
    """`기본 공격`은 정상 어휘다. 금지어 목록이 이 말을 잡으면 안 된다."""
    from app.content.expeditions.joint_guard import DECISIVE_MOMENTS as moments

    bypass = moments["deep_sleeptalk"]["bypass"]["text"]
    assert "공격" in bypass
    assert validate_joint_guard_content() == []


@pytest.mark.parametrize("beast_code", sorted(BEAST_CATALOG))
@pytest.mark.parametrize("layer_index", [0, 1, 2])
def test_round_schedule_has_one_entry_per_round(beast_code, layer_index):
    schedule = round_schedule(beast_code, layer_index)
    assert len(schedule) == LAYER_ROUNDS
    assert [entry["round_no"] for entry in schedule] == [1, 2, 3, 4]
    for entry in schedule:
        assert entry["target"] in ALLOWED_INTENT_TARGETS


@pytest.mark.parametrize("beast_code", sorted(BEAST_CATALOG))
@pytest.mark.parametrize("layer_index", [0, 1, 2])
def test_the_decisive_moment_lands_on_the_round_content_chose(
    beast_code, layer_index
):
    moment_code = moment_code_for_layer(layer_index)
    schedule = round_schedule(beast_code, layer_index)
    carrying = [entry for entry in schedule if entry.get("moment_code")]
    assert len(carrying) == 1, carrying
    assert carrying[0]["moment_code"] == moment_code
    assert carrying[0]["round_no"] == DECISIVE_MOMENTS[moment_code]["round_no"]


@pytest.mark.parametrize("beast_code", sorted(BEAST_CATALOG))
@pytest.mark.parametrize("layer_index", [0, 1, 2])
def test_every_decisive_moment_is_announced_before_it_arrives(
    beast_code, layer_index
):
    """예고 없이 오는 큰 패턴은 없다(설계서 4.4).

    `깊은 잠꼬대`는 2라운드에 오는데 예고는 2라운드 전이라 라운드 안에 자리가
    없다. 그때는 겹에 들어서는 순간 알려야 한다. 둘 중 하나로는 반드시
    알려지는지 본다 - 이 검사가 없으면 셋 중 하나가 조용히 기습이 된다.
    """
    schedule = round_schedule(beast_code, layer_index)
    in_round = [e for e in schedule if e.get("moment_warning")]
    at_entry = layer_warning(beast_code, layer_index)
    assert bool(in_round) != bool(at_entry), (in_round, at_entry)

    warning = in_round[0]["moment_warning"] if in_round else at_entry
    assert warning["code"] == moment_code_for_layer(layer_index)
    # 우회 경로를 예고와 함께 읽어 준다. 역할이 없어도 대비할 수 있어야 한다.
    assert warning["bypass"]


@pytest.mark.parametrize("beast_code", sorted(BEAST_CATALOG))
def test_sleeptalk_starts_at_the_second_layer(beast_code):
    """겉꿈은 기본 루프만 익히는 자리다(설계서 4.1)."""
    assert all(
        "sleeptalk" not in entry for entry in round_schedule(beast_code, 0)
    )
    for layer_index in (1, 2):
        schedule = round_schedule(beast_code, layer_index)
        assert all("sleeptalk" in entry for entry in schedule)
        assert schedule[0]["sleeptalk"]["code"] == BEAST_CATALOG[beast_code][
            "sleeptalk"
        ]["code"]


def test_deep_sleeptalk_raises_cost_instead_of_hitting():
    """비용을 올리는 순간은 때리지 않는다.

    `깊은 잠꼬대`는 위력 0이고 다음 라운드 집중력 비용을 +1 한다. 이 순간이
    피해를 주는 쪽으로 바뀌면 `행동 봉쇄 금지` 계약과 부딪힌다.
    """
    schedule = round_schedule("ledger_keeper", 2)
    moment_round = next(e for e in schedule if e.get("moment_code"))
    assert moment_round["focus_surcharge_next_round"] == 1
    assert moment_round["code"] != "deep_sleeptalk"


@pytest.mark.parametrize("beast_code", sorted(BEAST_CATALOG))
def test_the_hug_leaves_an_echo_on_the_next_round(beast_code):
    """`꼭 끌어안기`의 여운을 빠뜨리지 않는다(설계서 4.4).

    이 순간만 다음 라운드에 `all` 위력 1이 한 번 더 온다. 순간을 넘긴 뒤
    바로 숨을 돌릴 수 없다는 것이 선잠을 겉꿈과 다르게 만드는 부분이라,
    일정에서 조용히 사라지면 난이도 곡선이 통째로 평평해진다.
    """
    moment = DECISIVE_MOMENTS["tight_hug"]
    schedule = round_schedule(beast_code, moment["layer_index"])
    echoes = [e for e in schedule if e.get("follow_up_from")]
    assert len(echoes) == 1, echoes
    echo = echoes[0]
    assert echo["round_no"] == moment["round_no"] + moment["follow_up"]["after_rounds"]
    assert echo["follow_up_from"]["power"] == moment["follow_up"]["power"]
    assert echo["follow_up_from"]["target"] == moment["follow_up"]["target"]


@pytest.mark.parametrize("layer_index", [0, 2])
def test_other_layers_have_no_follow_up(layer_index):
    schedule = round_schedule("ledger_keeper", layer_index)
    assert not [e for e in schedule if e.get("follow_up_from")]
