import copy
import itertools
from collections import Counter

import pytest

from app.content.expeditions.combat import (
    CombatRuleError,
    SPECIES_SECONDARY_SKILLS,
    SPECIES_SKILLS,
    guardian_battle_payload,
    member_battle_kit,
    new_guardian_battle,
    resolve_guardian_round,
    submit_guardian_action,
)
from app.content.expeditions.combat_identity import (
    COMBAT_ROLE_PROFILES,
    CURRENT_KEL_MAP_VERSION,
    ELEMENT_KEL,
    ELEMENT_KEL_BY_VERSION,
    EMOTION_DISCIPLINES,
    FUSION_LAYER_PROFILES,
    INITIAL_KEL_MAP_VERSION,
    KEL_OPPOSITES,
    KEL_LABELS,
    TANGLE_ELEMENT_MATCHUPS,
    character_combat_stats,
    element_kel_map,
    validate_combat_identity_catalog,
)
from app.content.expeditions.combat_motion import (
    MOTION_ARCHETYPES,
    combat_motion,
)
from app.content.expeditions.tangles import (
    TANGLE_CATALOG,
    TANGLE_INTENT_PRESENTATION,
    tangle_definition,
    validate_tangle_catalog,
)


def _profile(
    member_id: int,
    *,
    name: str,
    species: str,
    form: str,
    stats: dict[str, int],
    level: int = 25,
    rarity: int = 1,
) -> dict:
    return {
        "id": member_id,
        "position": member_id - 1,
        "is_guide": species == "archive_guide",
        "snapshot": {
            "name": name,
            "species": {"code": species},
            "form": form,
            "level": level,
            "rarity": rarity,
            "stage": 5,
            "stats": stats,
        },
    }


def _encounter(**overrides) -> dict:
    return {
        "enemy_name": "돌비늘 장부지기",
        "enemy_max_guard": 100,
        "max_rounds": 6,
        "starting_focus": 3,
        "max_focus": 5,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "claw",
                "name": "장부 발톱",
                "telegraph": "맨 앞 대원을 노려요.",
                "target": "front",
                "power": 1,
            },
            {
                "code": "wave",
                "name": "기록 파동",
                "telegraph": "모두를 노려요.",
                "target": "all",
                "power": 1,
            },
        ],
        **overrides,
    }


@pytest.fixture
def profiles() -> list[dict]:
    return [
        _profile(
            1,
            name="달빛이",
            species="ninja-pot",
            form="moonlit",
            stats={"care": 4, "focus": 5, "courage": 6, "insight": 7},
        ),
        _profile(
            2,
            name="안내자",
            species="archive_guide",
            form="mosaic",
            stats={"care": 6, "focus": 6, "courage": 5, "insight": 7},
        ),
    ]


def test_command_order_can_generate_focus_before_a_skill(profiles):
    battle = new_guardian_battle("keeper", _encounter(starting_focus=1), profiles)

    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 2, "action": "attack"},
            {"member_id": 1, "action": "skill"},
        ],
        _encounter(starting_focus=1),
        profiles,
    )

    assert resolved["focus"] == 0
    assert [event["member_id"] for event in resolved["last_exchange"][:2]] == [
        2,
        1,
    ]

    with pytest.raises(CombatRuleError) as error:
        resolve_guardian_round(
            battle,
            [
                {"member_id": 1, "action": "skill"},
                {"member_id": 2, "action": "attack"},
            ],
            _encounter(starting_focus=1),
            profiles,
        )
    assert error.value.code == "EXPEDITION_COMBAT_FOCUS_SHORTAGE"


def test_weakness_and_guard_change_the_exchange(profiles):
    battle = new_guardian_battle("keeper", _encounter(), profiles)
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "guard"},
            {"member_id": 2, "action": "attack"},
        ],
        _encounter(),
        profiles,
    )

    attack = resolved["last_exchange"][1]
    counter = resolved["last_exchange"][2]
    assert attack["weakness_hit"] is True
    assert attack["damage"] > 10
    assert counter["targets"] == [
        {
            "member_id": 1,
            "name": "달빛이",
            "damage": 0,
            "blocked": 1,
            "hp_after": 5,
        }
    ]
    assert resolved["round"] == 2
    assert resolved["weakness"] == "care"


def test_first_command_also_changes_the_front_target(profiles):
    battle = new_guardian_battle("keeper", _encounter(), profiles)
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 2, "action": "guard"},
            {"member_id": 1, "action": "attack"},
        ],
        _encounter(),
        profiles,
    )

    counter = next(
        event for event in resolved["last_exchange"] if event["type"] == "enemy_action"
    )
    assert counter["targets"][0]["member_id"] == 2
    assert counter["effect_key"] == "ledger_claw"
    assert [member["member_id"] for member in resolved["party"]] == [2, 1]


def test_breaking_the_guard_ends_the_battle_before_the_counter(profiles):
    battle = new_guardian_battle("keeper", _encounter(enemy_max_guard=10), profiles)
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "attack"},
            {"member_id": 2, "action": "attack"},
        ],
        _encounter(enemy_max_guard=10),
        profiles,
    )

    assert resolved["status"] == "victory"
    assert resolved["enemy_guard"] == 0
    assert all(event["type"] != "enemy_action" for event in resolved["last_exchange"])


def test_round_limit_creates_a_real_defeat_state(profiles):
    encounter = _encounter(max_rounds=1)
    battle = new_guardian_battle("keeper", encounter, profiles)
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "guard"},
            {"member_id": 2, "action": "guard"},
        ],
        encounter,
        profiles,
    )

    assert resolved["status"] == "defeat"
    assert resolved["defeat_reason"] == "seal_completed"
    assert resolved["last_exchange"][-1]["outcome"] == "defeat"


def test_payload_exposes_every_species_unique_manual_skill(profiles):
    expected_species = {
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
        "maestro-pot",
        "nurse-pot",
        "restorer-pot",
        "marten-pot",
        "gal-pot",
    }
    assert expected_species <= set(SPECIES_SKILLS)
    assert expected_species <= set(SPECIES_SECONDARY_SKILLS)
    assert len({SPECIES_SKILLS[code]["code"] for code in expected_species}) == 15
    assert (
        len({SPECIES_SECONDARY_SKILLS[code]["code"] for code in expected_species}) == 15
    )

    payload = guardian_battle_payload(
        new_guardian_battle("keeper", _encounter(), profiles),
        _encounter(),
        profiles,
    )
    assert payload["enemy"]["intent"]["target"] == "front"
    assert payload["party"][0]["kit"]["skill"]["name"] == "맹독 틈베기"
    assert payload["party"][0]["kit"]["skill"]["effect_key"] == "venom_seam"

    action = submit_guardian_action(
        new_guardian_battle("keeper", _encounter(), profiles),
        {"member_id": 1, "action": "skill"},
        _encounter(),
        profiles,
    )["last_exchange"][0]
    assert action["motion_profile"] == "ninja-pot.venom-draw"


def test_combat_kit_v8_exposes_and_resolves_all_six_fixed_slots(profiles):
    encounter = _encounter(starting_focus=5, enemy_max_guard=500)
    payload = guardian_battle_payload(
        new_guardian_battle("keeper", encounter, profiles),
        encounter,
        profiles,
    )
    kit = payload["party"][0]["kit"]
    assert kit["version"] == 8
    assert [skill["slot"] for skill in kit["unique_skills"]] == [
        "unique_1",
        "unique_2",
    ]
    assert [skill["slot"] for skill in kit["selected_skills"]] == [
        "selected_1",
        "selected_2",
    ]

    for action in (
        "attack",
        "unique_1",
        "unique_2",
        "selected_1",
        "selected_2",
        "guard",
    ):
        resolved = submit_guardian_action(
            new_guardian_battle("keeper", encounter, profiles),
            {"member_id": 1, "action": action},
            encounter,
            profiles,
        )
        assert resolved["last_exchange"][0]["action"] == action

    legacy = submit_guardian_action(
        new_guardian_battle("keeper", encounter, profiles),
        {"member_id": 1, "action": "skill"},
        encounter,
        profiles,
    )
    assert legacy["last_exchange"][0]["action"] == "unique_1"


def _submit_round(battle, commands, encounter, profiles):
    """순차 명령으로 한 라운드를 진행하고 최종 상태와 이벤트 흐름을 돌려준다."""

    state = battle
    events = []
    for command in commands:
        state = submit_guardian_action(state, command, encounter, profiles)
        events.extend(state["last_exchange"])
    return state, events


def _strip_runtime_fields(state):
    stripped = {
        key: value
        for key, value in state.items()
        if key not in {"pending", "round_exchange", "last_exchange"}
    }
    return stripped


def test_sequential_round_matches_batch_round_exactly(profiles):
    encounter = _encounter()
    actions = ["attack", "skill", "guard"]
    for first, second in itertools.product(actions, actions):
        commands = [
            {"member_id": 1, "action": first},
            {"member_id": 2, "action": second},
        ]
        batch_error = sequential_error = None
        batch = sequential = events = None
        try:
            batch = resolve_guardian_round(
                new_guardian_battle("keeper", encounter, profiles),
                commands,
                encounter,
                profiles,
            )
        except CombatRuleError as error:
            batch_error = error.code
        try:
            sequential, events = _submit_round(
                new_guardian_battle("keeper", encounter, profiles),
                commands,
                encounter,
                profiles,
            )
        except CombatRuleError as error:
            sequential_error = error.code

        # 규칙 오류(예: 집중력 부족)도 두 경로에서 같은 코드로 일어나야 한다.
        assert batch_error == sequential_error, (first, second)
        if batch_error is not None:
            continue
        assert _strip_runtime_fields(sequential) == _strip_runtime_fields(batch)
        assert events == batch["last_exchange"]
        assert sequential["round_exchange"] == batch["round_exchange"]


def test_sequential_round_matches_batch_across_multiple_rounds(profiles):
    encounter = _encounter(enemy_max_guard=200)
    rounds = [
        [
            {"member_id": 2, "action": "attack"},
            {"member_id": 1, "action": "skill"},
        ],
        [
            {"member_id": 1, "action": "guard"},
            {"member_id": 2, "action": "attack"},
        ],
        [
            {"member_id": 1, "action": "attack"},
            {"member_id": 2, "action": "guard"},
        ],
    ]
    batch = new_guardian_battle("keeper", encounter, profiles)
    sequential = new_guardian_battle("keeper", encounter, profiles)
    for commands in rounds:
        batch = resolve_guardian_round(batch, commands, encounter, profiles)
        sequential, _ = _submit_round(sequential, commands, encounter, profiles)
        assert _strip_runtime_fields(sequential) == _strip_runtime_fields(batch)


def test_partial_action_returns_only_new_events(profiles):
    encounter = _encounter()
    battle = new_guardian_battle("keeper", encounter, profiles)

    after_first = submit_guardian_action(
        battle, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    assert [event["type"] for event in after_first["last_exchange"]] == ["party_action"]
    assert after_first["status"] == "active"
    assert after_first["round"] == 1
    assert after_first["pending"]["acted"] == [2]

    payload = guardian_battle_payload(after_first, encounter, profiles)
    assert payload["pending_round"] == {"acted": [2], "awaiting": [1]}

    after_second = submit_guardian_action(
        after_first, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    types = [event["type"] for event in after_second["last_exchange"]]
    assert types[0] == "party_action"
    assert "enemy_action" in types
    assert after_second["round"] == 2
    assert after_second["pending"] is None


def test_partial_rejects_duplicate_and_down_members(profiles):
    encounter = _encounter()
    battle = new_guardian_battle("keeper", encounter, profiles)
    after_first = submit_guardian_action(
        battle, {"member_id": 1, "action": "guard"}, encounter, profiles
    )

    with pytest.raises(CombatRuleError) as duplicate:
        submit_guardian_action(
            after_first, {"member_id": 1, "action": "attack"}, encounter, profiles
        )
    assert duplicate.value.code == "EXPEDITION_COMBAT_DUPLICATE_MEMBER"

    with pytest.raises(CombatRuleError) as unknown:
        submit_guardian_action(
            after_first, {"member_id": 9, "action": "attack"}, encounter, profiles
        )
    assert unknown.value.code == "EXPEDITION_COMBAT_MEMBER_INVALID"


def test_partial_focus_shortage_keeps_round_state_untouched(profiles):
    encounter = _encounter(starting_focus=1)
    battle = new_guardian_battle("keeper", encounter, profiles)

    with pytest.raises(CombatRuleError) as error:
        submit_guardian_action(
            battle, {"member_id": 1, "action": "skill"}, encounter, profiles
        )
    assert error.value.code == "EXPEDITION_COMBAT_FOCUS_SHORTAGE"
    # 원본 상태는 그대로여서 다른 카드를 다시 고를 수 있다.
    assert battle["pending"] is None
    assert battle["focus"] == 1

    recovered = submit_guardian_action(
        battle, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    assert recovered["pending"]["acted"] == [2]
    follow_up = submit_guardian_action(
        recovered, {"member_id": 1, "action": "skill"}, encounter, profiles
    )
    assert follow_up["round"] == 2


def test_partial_victory_ends_round_without_enemy_action(profiles):
    encounter = _encounter(enemy_max_guard=10)
    battle = new_guardian_battle("keeper", encounter, profiles)
    resolved = submit_guardian_action(
        battle, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    assert resolved["status"] == "victory"
    assert all(event["type"] != "enemy_action" for event in resolved["last_exchange"])
    assert resolved["pending"] is None


def test_partial_front_target_follows_action_order(profiles):
    encounter = _encounter()
    battle = new_guardian_battle("keeper", encounter, profiles)
    state = submit_guardian_action(
        battle, {"member_id": 2, "action": "guard"}, encounter, profiles
    )
    state = submit_guardian_action(
        state, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    counter = next(
        event for event in state["last_exchange"] if event["type"] == "enemy_action"
    )
    assert counter["targets"][0]["member_id"] == 2
    assert [member["member_id"] for member in state["party"]] == [2, 1]


def test_batch_round_rejects_mixing_into_a_started_sequential_round(profiles):
    encounter = _encounter()
    battle = new_guardian_battle("keeper", encounter, profiles)
    started = submit_guardian_action(
        battle, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    with pytest.raises(CombatRuleError) as error:
        resolve_guardian_round(
            started,
            [
                {"member_id": 1, "action": "attack"},
                {"member_id": 2, "action": "attack"},
            ],
            encounter,
            profiles,
        )
    assert error.value.code == "EXPEDITION_COMBAT_ROUND_IN_PROGRESS"


def _wave_encounter(codes: list[str], **overrides) -> dict:
    return {
        "kind": "guardian",
        "enemy_kind": "tangle",
        "waves": codes,
        "max_rounds": 4 * len(codes),
        "starting_focus": 3,
        "max_focus": 5,
        **overrides,
    }


def test_wave_battle_starts_from_the_first_tangle(profiles):
    encounter = _wave_encounter(["tangled_ledger", "drifting_pressings"])
    battle = new_guardian_battle("stage_wave_3", encounter, profiles)

    assert battle["enemy_kind"] == "tangle"
    assert battle["enemy_guard"] == 42
    assert battle["growth_index"] == 83
    assert battle["barrier_scale_bp"] == 12_433
    assert battle["max_rounds"] == 8
    # 첫 웨이브의 약점 순환과 등장 문구를 그대로 쓴다.
    assert battle["weakness"] == "insight"
    assert battle["battle_log"] == ["엉킨 장부 뭉치가 길을 반쯤 막고 웅크렸어요."]

    payload = guardian_battle_payload(battle, encounter, profiles)
    assert payload["enemy"]["name"] == "엉킨 장부 뭉치"
    assert payload["enemy"]["kind"] == "tangle"
    assert payload["wave"] == {"index": 1, "count": 2, "name": "엉킨 장부 뭉치"}


def test_early_levels_do_not_scale_enemy_barrier_before_power_rounding_moves():
    early_profiles = [
        _profile(
            1,
            name="초기 대원",
            species="baby-pot",
            form="sunny",
            stats={"care": 4, "focus": 4, "courage": 4, "insight": 4},
            level=3,
        )
    ]
    battle = new_guardian_battle(
        "early_guardian",
        {"kind": "guardian", "enemy_max_guard": 100},
        early_profiles,
    )

    assert battle["growth_index"] == 7
    assert battle["barrier_scale_bp"] == 10_000
    assert battle["enemy_guard"] == 100


def test_clearing_a_wave_ends_the_round_and_brings_the_next_tangle(profiles):
    encounter = _wave_encounter(["tangled_ledger", "drifting_pressings"])
    battle = new_guardian_battle("stage_wave_3", encounter, profiles)

    # 맹독 틈베기는 불 약점 엉킴에 중립이고, 안내자의 강철 공격이 마무리한다.
    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "skill"},
            {"member_id": 2, "action": "attack"},
        ],
        encounter,
        profiles,
    )

    types = [event["type"] for event in resolved["last_exchange"]]
    assert types == [
        "party_action",
        "party_action",
        "wave_cleared",
        "wave_intro",
    ]
    # 웨이브가 풀리면 그 라운드는 끝난다 — 남은 대원 차례도, 적 예고 공격도 없다.
    assert resolved["status"] == "active"
    assert resolved["wave_index"] == 1
    assert resolved["enemy_guard"] == 47
    assert resolved["round"] == 2
    assert resolved["weakness"] == "care"
    assert resolved["pending"] is None
    # Lv18 보너스 집중력도 웨이브를 넘어 이어진다. 4 - 스킬 2 + 기본 공격 1 = 3.
    assert resolved["focus"] == 3
    cleared = resolved["last_exchange"][2]
    assert cleared["caption"] == "엉킨 장부가 스르르 풀려 제자리 서가로 돌아갔어요."
    intro = resolved["last_exchange"][3]
    assert intro["enemy_name"] == "표류 압화 떼"

    payload = guardian_battle_payload(resolved, encounter, profiles)
    assert payload["wave"] == {"index": 2, "count": 2, "name": "표류 압화 떼"}


def test_final_wave_release_becomes_the_victory_caption(profiles):
    encounter = _wave_encounter(["tangled_ledger"])
    battle = new_guardian_battle("stage_wave_1", encounter, profiles)

    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "skill"},
            {"member_id": 2, "action": "attack"},
        ],
        encounter,
        profiles,
    )

    assert resolved["status"] == "victory"
    outcome = resolved["last_exchange"][-1]
    assert outcome["type"] == "outcome"
    assert outcome["caption"] == "엉킨 장부가 스르르 풀려 제자리 서가로 돌아갔어요."
    assert all(event["type"] != "enemy_action" for event in resolved["last_exchange"])


def test_sequential_wave_battle_matches_batch_exactly(profiles):
    encounter = _wave_encounter(["tangled_ledger", "drifting_pressings"])
    rounds = [
        [
            {"member_id": 1, "action": "skill"},
            {"member_id": 2, "action": "attack"},
        ],
        [
            {"member_id": 1, "action": "attack"},
            {"member_id": 2, "action": "attack"},
        ],
        [
            {"member_id": 1, "action": "attack"},
            {"member_id": 2, "action": "attack"},
        ],
    ]
    batch = new_guardian_battle("stage_wave_3", encounter, profiles)
    sequential = new_guardian_battle("stage_wave_3", encounter, profiles)
    for commands in rounds:
        if batch["status"] != "active":
            break
        remaining = [
            command
            for command in commands
            if any(
                member["member_id"] == command["member_id"] and member["hp"] > 0
                for member in batch["party"]
            )
        ]
        batch = resolve_guardian_round(batch, remaining, encounter, profiles)
        # 순차 제출은 웨이브가 풀리는 순간 라운드가 끝났다는 응답을 받으므로,
        # 남은 명령을 다음 라운드로 흘려보내지 않고 거기서 멈춘다.
        for command in remaining:
            sequential = submit_guardian_action(
                sequential, command, encounter, profiles
            )
            if any(
                event["type"] in {"wave_cleared", "outcome"}
                for event in sequential["last_exchange"]
            ):
                break
        assert _strip_runtime_fields(sequential) == _strip_runtime_fields(batch)

    # 웨이브 전환을 포함한 전 라운드에서 두 입력 방식의 결과가 같다.
    assert batch["wave_index"] == sequential["wave_index"]


def test_wave_round_budget_is_shared_across_waves(profiles):
    encounter = _wave_encounter(["tangled_ledger"], max_rounds=1)
    battle = new_guardian_battle("stage_wave_1", encounter, profiles)

    resolved = resolve_guardian_round(
        battle,
        [
            {"member_id": 1, "action": "guard"},
            {"member_id": 2, "action": "guard"},
        ],
        encounter,
        profiles,
    )

    assert resolved["status"] == "defeat"
    assert resolved["defeat_reason"] == "seal_completed"


def test_identity_catalog_separates_species_fantasy_from_emotion_material():
    validate_combat_identity_catalog()

    assert {
        SPECIES_SKILLS["gumiho-pot"]["element"],
        SPECIES_SECONDARY_SKILLS["gumiho-pot"]["element"],
    } == {"heart", "moon"}
    assert {
        SPECIES_SKILLS["ninja-pot"]["element"],
        SPECIES_SECONDARY_SKILLS["ninja-pot"]["element"],
    } == {"poison", "shadow"}
    assert EMOTION_DISCIPLINES["ember"]["primary_element"] == "fire"
    assert EMOTION_DISCIPLINES["rainy"]["primary_element"] == "water"
    assert EMOTION_DISCIPLINES["mosaic"]["primary_element"] == "steel"
    for form, discipline in EMOTION_DISCIPLINES.items():
        assert ELEMENT_KEL[discipline["primary_element"]] == form
        assert ELEMENT_KEL[discipline["secondary_element"]] == form

    generic_plant_words = ("잎", "뿌리", "덩굴", "꽃잎", "새싹")
    for species in set(SPECIES_SKILLS) - {"baby-pot", "archive_guide"}:
        text = " ".join(
            (
                SPECIES_SKILLS[species]["name"],
                SPECIES_SKILLS[species]["description"],
                SPECIES_SECONDARY_SKILLS[species]["name"],
                SPECIES_SECONDARY_SKILLS[species]["description"],
            )
        )
        assert not any(word in text for word in generic_plant_words)


def test_all_signature_elements_map_to_six_learnable_growth_kels():
    signature_elements = {
        skill["element"]
        for catalog in (SPECIES_SKILLS, SPECIES_SECONDARY_SKILLS)
        for species, skill in catalog.items()
        if species != "archive_guide"
    }
    assert signature_elements <= set(ELEMENT_KEL)
    assert {ELEMENT_KEL[element] for element in signature_elements} <= set(KEL_LABELS)
    assert set(ELEMENT_KEL.values()) == set(KEL_LABELS)


def test_kel_map_version_one_is_complete_and_unknown_versions_fail_closed():
    expected = {
        "light": "sunny",
        "nature": "sunny",
        "water": "rainy",
        "ice": "rainy",
        "poison": "rainy",
        "fire": "ember",
        "decay": "ember",
        "wind": "moonlit",
        "moon": "moonlit",
        "shadow": "moonlit",
        "lightning": "sparkling",
        "sound": "sparkling",
        "arcane": "sparkling",
        "heart": "sunny",
        "steel": "mosaic",
        "force": "mosaic",
        "gravity": "mosaic",
        "ink": "mosaic",
        "seal": "mosaic",
        "strike": "ember",
    }

    assert INITIAL_KEL_MAP_VERSION == 1
    assert CURRENT_KEL_MAP_VERSION == 1
    assert dict(ELEMENT_KEL_BY_VERSION[1]) == expected
    assert dict(element_kel_map(1)) == expected
    with pytest.raises(ValueError, match="지원하지 않는 결 매핑 버전"):
        element_kel_map(999)


def test_tangle_matchups_repeat_each_directed_opposing_axis_twice():
    weak_counts = Counter()
    resist_counts = Counter()
    axis_counts = Counter()
    for weak_element, resist_element in TANGLE_ELEMENT_MATCHUPS.values():
        weak_kel = ELEMENT_KEL[weak_element]
        resist_kel = ELEMENT_KEL[resist_element]
        assert KEL_OPPOSITES[weak_kel] == resist_kel
        weak_counts[weak_kel] += 1
        resist_counts[resist_kel] += 1
        axis_counts[(weak_kel, resist_kel)] += 1

    assert weak_counts == Counter({kel: 2 for kel in KEL_LABELS})
    assert resist_counts == Counter({kel: 2 for kel in KEL_LABELS})
    assert axis_counts == Counter(
        {(kel, opposite): 2 for kel, opposite in KEL_OPPOSITES.items()}
    )


def test_every_level_25_species_and_emotion_kit_has_multiple_labeled_kels():
    stats = {"care": 4, "focus": 5, "courage": 6, "insight": 7}
    for species, form in itertools.product(
        sorted(set(SPECIES_SKILLS) - {"archive_guide"}),
        sorted(EMOTION_DISCIPLINES),
    ):
        kit = member_battle_kit(
            _profile(
                1,
                name="결 전수 검수",
                species=species,
                form=form,
                stats=stats,
                level=25,
            )
        )
        actions = [
            kit["basic"],
            *kit["unique_skills"],
            *kit["selected_skills"],
        ]
        all_kels = set()
        for action in actions:
            assert len(action["kels"]) == len(action["kel_labels"])
            assert len(action["kels"]) == len(set(action["kels"]))
            assert action["kel_labels"] == [KEL_LABELS[kel] for kel in action["kels"]]
            all_kels.update(action["kels"])
        assert len(all_kels) >= 2


def test_battle_snapshots_kel_map_version_for_payload_and_events(profiles):
    encounter = _encounter(
        starting_focus=5,
        enemy_max_guard=500,
        weak_element="poison",
        resist_element="steel",
    )
    battle = new_guardian_battle("keeper", encounter, profiles)

    assert battle["kel_map_version"] == CURRENT_KEL_MAP_VERSION
    payload = guardian_battle_payload(battle, encounter, profiles)
    assert payload["kel_map_version"] == CURRENT_KEL_MAP_VERSION
    assert {member["kit"]["kel_map_version"] for member in payload["party"]} == {
        CURRENT_KEL_MAP_VERSION
    }

    state = submit_guardian_action(
        battle,
        {"member_id": 1, "action": "attack"},
        encounter,
        profiles,
    )
    assert state["last_exchange"][0]["kel_map_version"] == CURRENT_KEL_MAP_VERSION

    legacy_v2 = dict(battle)
    legacy_v2.pop("kel_map_version")
    assert (
        guardian_battle_payload(legacy_v2, encounter, profiles)["kel_map_version"]
        == INITIAL_KEL_MAP_VERSION
    )

    unknown = dict(battle)
    unknown["kel_map_version"] = 999
    with pytest.raises(CombatRuleError) as error:
        guardian_battle_payload(unknown, encounter, profiles)
    assert error.value.code == "EXPEDITION_COMBAT_KEL_MAP_UNSUPPORTED"


def test_signature_growth_uses_level_tier_rarity_curve_and_emotion_fusion():
    stats = {"care": 4, "focus": 5, "courage": 6, "insight": 7}
    low_common = member_battle_kit(
        _profile(
            1,
            name="여우",
            species="gumiho-pot",
            form="ember",
            stats=stats,
            level=1,
            rarity=1,
        )
    )
    low_rare = member_battle_kit(
        _profile(
            1,
            name="여우",
            species="gumiho-pot",
            form="ember",
            stats=stats,
            level=1,
            rarity=5,
        )
    )
    grown_common = member_battle_kit(
        _profile(
            1,
            name="여우",
            species="gumiho-pot",
            form="ember",
            stats=stats,
            level=30,
            rarity=1,
        )
    )
    grown_rare = member_battle_kit(
        _profile(
            1,
            name="여우",
            species="gumiho-pot",
            form="ember",
            stats=stats,
            level=30,
            rarity=5,
        )
    )

    assert low_rare["signature_scale_bp"] > low_common["signature_scale_bp"]
    assert grown_rare["signature_scale_bp"] > grown_common["signature_scale_bp"]
    assert grown_rare["signature_tier"] == 3
    assert low_rare["unique_skills"][0]["fusion_variant"] is None
    assert low_rare["unique_skills"][0]["fusion_vfx_family"] is None
    assert grown_rare["unique_skills"][0]["elements"] == ["heart", "fire"]
    assert grown_rare["unique_skills"][1]["elements"] == ["moon", "fire"]
    assert (
        grown_rare["unique_skills"][0]["fusion_variant"]
        == "gumiho-pot.ember.unique_1.t3"
    )
    assert (
        grown_rare["unique_skills"][0]["fusion_vfx_family"]
        == FUSION_LAYER_PROFILES["ember"]["vfx_family"]
    )
    assert (
        grown_rare["unique_skills"][0]["power"] > low_rare["unique_skills"][0]["power"]
    )


def test_all_character_emotion_t3_fusion_variants_are_unique_and_complete():
    stats = {"care": 4, "focus": 5, "courage": 6, "insight": 7}
    variants = set()
    for species, form in itertools.product(
        sorted(set(SPECIES_SKILLS) - {"archive_guide"}),
        sorted(EMOTION_DISCIPLINES),
    ):
        kit = member_battle_kit(
            _profile(
                1,
                name="융합 검수",
                species=species,
                form=form,
                stats=stats,
                level=25,
            )
        )
        for skill in kit["unique_skills"]:
            assert (
                skill["fusion_vfx_family"] == FUSION_LAYER_PROFILES[form]["vfx_family"]
            )
            assert skill["fusion_production_ready"] is False
            variants.add(skill["fusion_variant"])

    assert len(variants) == 15 * 6 * 2


@pytest.mark.parametrize("level", [3, 16, 30])
def test_matchup_multiplier_keeps_same_weight_across_level_bands(level):
    profile = _profile(
        1,
        name="여우",
        species="gumiho-pot",
        form="sparkling",
        stats={"care": 4, "focus": 5, "courage": 6, "insight": 7},
        level=level,
        rarity=3,
    )
    neutral = member_battle_kit(profile)["unique_skills"][0]
    weak = member_battle_kit(
        profile,
        current_weak_element="light",
        current_resist_element="water",
    )["unique_skills"][0]
    resisted = member_battle_kit(
        profile,
        current_weak_element="water",
        current_resist_element="light",
    )["unique_skills"][0]

    assert weak["matchup_bp"] == 15_000
    assert resisted["matchup_bp"] == 6_000
    assert abs(weak["power"] / neutral["power"] - 1.5) <= 0.05
    assert abs(resisted["power"] / neutral["power"] - 0.6) <= 0.05


def test_tier_power_keeps_signature_cooldown_floor_and_level_unlocks_slots():
    stats = {"care": 4, "focus": 5, "courage": 6, "insight": 7}
    level_15 = member_battle_kit(
        _profile(
            1,
            name="닌자",
            species="ninja-pot",
            form="moonlit",
            stats=stats,
            level=15,
        )
    )
    level_16 = member_battle_kit(
        _profile(
            1,
            name="닌자",
            species="ninja-pot",
            form="moonlit",
            stats=stats,
            level=16,
        )
    )
    level_3 = member_battle_kit(
        _profile(
            1,
            name="닌자",
            species="ninja-pot",
            form="moonlit",
            stats=stats,
            level=3,
        )
    )
    level_7 = member_battle_kit(
        _profile(
            1,
            name="닌자",
            species="ninja-pot",
            form="moonlit",
            stats=stats,
            level=7,
        )
    )
    level_25 = member_battle_kit(
        _profile(
            1,
            name="닌자",
            species="ninja-pot",
            form="moonlit",
            stats=stats,
            level=25,
        )
    )

    assert level_15["unique_skills"][0]["cooldown_turns"] == 1
    assert level_16["unique_skills"][0]["cooldown_turns"] == 1
    assert level_16["unique_skills"][0]["tier_power_bp"] == 11_000
    assert level_25["unique_skills"][0]["cooldown_turns"] == 1
    assert level_25["unique_skills"][1]["cooldown_turns"] == 2
    assert level_3["unique_skills"][0]["available"] is True
    assert level_3["unique_skills"][1]["available"] is False
    assert level_7["unique_skills"][1]["available"] is True
    assert level_3["selected_skills"][0]["available"] is False
    assert level_3["selected_skills"][1]["available"] is False


def test_all_fifteen_characters_have_distinct_roles_and_growth_stats():
    playable_species = set(SPECIES_SKILLS) - {"archive_guide"}

    assert len(playable_species) == 15
    assert playable_species <= set(COMBAT_ROLE_PROFILES)
    assert len({COMBAT_ROLE_PROFILES[code]["code"] for code in playable_species}) == 15

    for species in playable_species:
        starter = character_combat_stats(
            species,
            level=1,
            rarity=1,
            form="mosaic",
        )
        grown = character_combat_stats(
            species,
            level=30,
            rarity=5,
            form="sunny",
        )
        assert set(starter["values"]) == {
            "offense",
            "vitality",
            "support",
            "control",
        }
        assert all(
            grown["values"][key] >= starter["values"][key] for key in starter["values"]
        )


def test_restorer_reduces_intent_and_repairs_the_party():
    stats = {"care": 6, "focus": 6, "courage": 6, "insight": 7}
    restorer_profiles = [
        _profile(
            1,
            name="에단",
            species="restorer-pot",
            form="mosaic",
            stats=stats,
            level=25,
            rarity=5,
        ),
        _profile(
            2,
            name="길잡이",
            species="archive_guide",
            form="mosaic",
            stats=stats,
            level=25,
        ),
    ]
    encounter = _encounter(starting_focus=5, enemy_max_guard=2_000)
    battle = new_guardian_battle("restorer-mechanics", encounter, restorer_profiles)
    battle["party"][1]["hp"] -= 2

    parry = submit_guardian_action(
        battle,
        {"member_id": 1, "action": "unique_1"},
        encounter,
        restorer_profiles,
    )
    assert parry["party"][0]["guard"] >= 2
    assert parry["pending"]["intent_power_delta"] <= -2
    assert parry["last_exchange"][0]["effect_key"] == "patina_parry"

    repaired_start = new_guardian_battle(
        "restorer-repair", encounter, restorer_profiles
    )
    repaired_start["party"][1]["hp"] -= 2
    repaired = submit_guardian_action(
        repaired_start,
        {"member_id": 1, "action": "unique_2"},
        encounter,
        restorer_profiles,
    )
    assert repaired["party"][1]["hp"] == repaired["party"][1]["max_hp"]
    assert all(member["guard"] > 0 for member in repaired["party"])
    assert repaired["focus"] == 1


def test_restorer_defense_mechanics_open_by_growth_tier():
    stats = {"care": 6, "focus": 6, "courage": 6, "insight": 7}

    def unique_effects(level: int) -> tuple[dict, dict]:
        kit = member_battle_kit(
            _profile(
                1,
                name="에단",
                species="restorer-pot",
                form="mosaic",
                stats=stats,
                level=level,
                rarity=5,
            )
        )
        return tuple(skill["effect_values"] for skill in kit["unique_skills"])

    tier_1_parry, tier_1_seam = unique_effects(3)
    tier_2_parry, tier_2_seam = unique_effects(16)
    tier_3_parry, tier_3_seam = unique_effects(25)

    assert tier_1_parry == {"self_guard": 0, "intent_power_delta": 0}
    assert tier_2_parry["self_guard"] == 1
    assert tier_2_parry["intent_power_delta"] == 0
    assert tier_3_parry["self_guard"] == 2
    assert tier_3_parry["intent_power_delta"] < 0
    assert tier_1_seam["party_guard"] == 0
    assert tier_2_seam["party_guard"] >= 1
    assert tier_3_seam["heal_lowest"] > tier_2_seam["heal_lowest"]
    assert tier_3_seam["focus_refund"] == 1


def test_marten_marks_enemy_and_guards_the_den():
    stats = {"care": 5, "focus": 6, "courage": 7, "insight": 6}
    marten_profiles = [
        _profile(
            1,
            name="모루",
            species="marten-pot",
            form="moonlit",
            stats=stats,
            level=25,
            rarity=4,
        ),
        _profile(
            2,
            name="길잡이",
            species="archive_guide",
            form="mosaic",
            stats=stats,
            level=25,
        ),
    ]
    encounter = _encounter(starting_focus=5, enemy_max_guard=2_000)
    marked = submit_guardian_action(
        new_guardian_battle("marten-mark", encounter, marten_profiles),
        {"member_id": 1, "action": "unique_1"},
        encounter,
        marten_profiles,
    )
    assert marked["pending"]["enemy_vulnerability_bp"] >= 10_800
    assert marked["party"][0]["guard"] >= 1

    guarded = submit_guardian_action(
        new_guardian_battle("marten-den", encounter, marten_profiles),
        {"member_id": 1, "action": "unique_2"},
        encounter,
        marten_profiles,
    )
    assert guarded["pending"]["party_power_bp"] > 10_000
    assert all(member["guard"] > 0 for member in guarded["party"])


def test_marten_mark_opens_only_after_high_level_growth():
    stats = {"care": 5, "focus": 6, "courage": 7, "insight": 6}

    def rush_effects(level: int) -> dict:
        kit = member_battle_kit(
            _profile(
                1,
                name="모루",
                species="marten-pot",
                form="moonlit",
                stats=stats,
                level=level,
                rarity=4,
            )
        )
        return kit["unique_skills"][0]["effect_values"]

    tier_1 = rush_effects(3)
    tier_2 = rush_effects(16)
    tier_3 = rush_effects(25)

    assert tier_1 == {"enemy_vulnerability_bp": 10_000, "self_guard": 0}
    assert tier_2 == {"enemy_vulnerability_bp": 10_000, "self_guard": 1}
    assert tier_3["enemy_vulnerability_bp"] >= 10_800
    assert tier_3["self_guard"] == 1


def test_gal_relay_rewards_order_and_runway_adapts_to_weakness():
    stats = {"care": 6, "focus": 7, "courage": 6, "insight": 6}
    gal_profiles = [
        _profile(
            1,
            name="리아",
            species="gal-pot",
            form="sparkling",
            stats=stats,
            level=25,
            rarity=5,
        ),
        _profile(
            2,
            name="길잡이",
            species="archive_guide",
            form="mosaic",
            stats=stats,
            level=25,
        ),
    ]
    encounter = _encounter(starting_focus=5, enemy_max_guard=2_000)
    relay = submit_guardian_action(
        new_guardian_battle("gal-relay", encounter, gal_profiles),
        {"member_id": 1, "action": "unique_1"},
        encounter,
        gal_profiles,
    )
    assert relay["pending"]["party_power_bp"] >= 12_300
    assert relay["focus"] == 4
    assert relay["last_exchange"][0]["effect_key"] == "patchwork_relay"

    kit = member_battle_kit(
        gal_profiles[0],
        current_weakness="courage",
        current_weak_element="water",
        current_resist_element="light",
    )
    reversal = kit["unique_skills"][1]
    assert reversal["prism_shifted"] is True
    assert reversal["matchup"] == "weak"
    assert reversal["affinity"] == "courage"
    assert reversal["effect_key"] == "runway_reversal"


def test_white_garden_oath_revives_and_protects_a_downed_ally():
    stats = {"care": 7, "focus": 7, "courage": 5, "insight": 6}
    nurse_profiles = [
        _profile(
            1,
            name="백화",
            species="nurse-pot",
            form="sunny",
            stats=stats,
            level=25,
            rarity=5,
        ),
        _profile(
            2,
            name="안내자",
            species="archive_guide",
            form="mosaic",
            stats=stats,
            level=25,
        ),
    ]
    encounter = _encounter(starting_focus=5, enemy_max_guard=1_000)
    battle = new_guardian_battle("white-garden", encounter, nurse_profiles)
    battle["party"][1]["hp"] = 0

    state = submit_guardian_action(
        battle,
        {"member_id": 1, "action": "unique_2"},
        encounter,
        nurse_profiles,
    )
    action = state["last_exchange"][0]
    revived = next(item for item in state["party"] if item["member_id"] == 2)

    assert action["action"] == "unique_2"
    assert action["action_name"] == "백의정원 선서"
    assert action["vfx_family"] == "nurse-pot.white-garden-oath"
    assert action["effect_values"]["revive_count"] == 1
    assert "긴급 소생 1" in action["mechanic_summary"]
    assert action["presentation_tier"] == 3
    assert action["audio_layer"] == "signature"
    assert action["emotion_vfx_primary"].startswith("#")
    assert revived["hp"] > 0
    assert all(member["guard"] > 0 for member in state["party"])


def test_white_garden_revive_keeps_batch_and_sequential_rounds_identical():
    stats = {"care": 7, "focus": 7, "courage": 5, "insight": 6}
    nurse_profiles = [
        _profile(
            1,
            name="백화",
            species="nurse-pot",
            form="sunny",
            stats=stats,
            level=25,
            rarity=5,
        ),
        _profile(
            2,
            name="안내자",
            species="archive_guide",
            form="mosaic",
            stats=stats,
            level=25,
        ),
    ]
    encounter = _encounter(starting_focus=5, enemy_max_guard=1_000)
    batch_start = new_guardian_battle("white-garden-parity", encounter, nurse_profiles)
    batch_start["party"][1]["hp"] = 0
    sequential_start = copy.deepcopy(batch_start)
    command = {"member_id": 1, "action": "unique_2"}

    batch = resolve_guardian_round(
        batch_start,
        [command],
        encounter,
        nurse_profiles,
    )
    sequential = submit_guardian_action(
        sequential_start,
        command,
        encounter,
        nurse_profiles,
    )

    assert _strip_runtime_fields(sequential) == _strip_runtime_fields(batch)
    assert sequential["round_exchange"] == batch["round_exchange"]
    assert sequential["round"] == 2
    assert sequential["pending"] is None


def test_maestro_rewards_action_order_and_suppresses_the_enemy_intent():
    stats = {"care": 5, "focus": 7, "courage": 5, "insight": 7}
    maestro_profiles = [
        _profile(
            1,
            name="세렌",
            species="maestro-pot",
            form="moonlit",
            stats=stats,
            level=25,
            rarity=5,
        ),
        _profile(
            2,
            name="그림싹",
            species="ninja-pot",
            form="ember",
            stats=stats,
            level=25,
            rarity=4,
        ),
    ]
    encounter = _encounter(
        starting_focus=5,
        enemy_max_guard=2_000,
        intents=[
            {
                "code": "pressure_wave",
                "name": "압박 파동",
                "telegraph": "전원을 누르는 파동이에요.",
                "target": "all",
                "power": 5,
            }
        ],
    )

    def resolved(first_action: str) -> dict:
        return resolve_guardian_round(
            new_guardian_battle("maestro-order", encounter, maestro_profiles),
            [
                {"member_id": 1, "action": first_action},
                {"member_id": 2, "action": "attack"},
            ],
            encounter,
            maestro_profiles,
        )

    baseline = resolved("attack")
    downbeat = resolved("unique_1")
    coda = resolved("unique_2")

    def ninja_damage(state: dict) -> int:
        return next(
            event["damage"]
            for event in state["last_exchange"]
            if event["type"] == "party_action" and event["member_id"] == 2
        )

    def enemy_damage(state: dict) -> int:
        event = next(
            event for event in state["last_exchange"] if event["type"] == "enemy_action"
        )
        return max(target["damage"] for target in event["targets"])

    assert ninja_damage(downbeat) > ninja_damage(baseline)
    assert ninja_damage(coda) > ninja_damage(baseline)
    assert enemy_damage(coda) < enemy_damage(baseline)
    coda_event = next(
        event
        for event in coda["last_exchange"]
        if event.get("action_name") == "침묵의 코다"
    )
    assert coda_event["effect_values"]["intent_power_delta"] < 0
    assert coda_event["effect_values"]["enemy_vulnerability_bp"] > 10_000


def test_guardian_boss_changes_affinity_intent_and_staging_across_three_phases(
    profiles,
):
    encounter = _encounter(
        enemy_max_guard=1_000,
        boss_phases=[
            {
                "code": "seal_watch",
                "name": "봉인 감시",
                "threshold_bp": 10_000,
                "weak_element": "light",
                "resist_element": "shadow",
                "weakness_cycle": ["care", "focus"],
                "intent_power_bonus": 0,
                "focus_reward": 0,
            },
            {
                "code": "root_lock",
                "name": "뿌리 봉쇄",
                "threshold_bp": 6_600,
                "weak_element": "water",
                "resist_element": "fire",
                "weakness_cycle": ["focus", "insight"],
                "intent_power_bonus": 1,
                "focus_reward": 1,
            },
            {
                "code": "final_erasure",
                "name": "최종 말소",
                "threshold_bp": 3_300,
                "weak_element": "poison",
                "resist_element": "steel",
                "weakness_cycle": ["courage", "care"],
                "intent_power_bonus": 2,
                "focus_reward": 1,
            },
        ],
    )
    battle = new_guardian_battle("three-phase-keeper", encounter, profiles)
    max_guard = battle["enemy_max_guard"]
    battle["enemy_guard"] = (max_guard * 6_600 + 9_999) // 10_000 + 1

    phase_two = submit_guardian_action(
        battle,
        {"member_id": 1, "action": "attack"},
        encounter,
        profiles,
    )
    assert any(
        event.get("phase_code") == "root_lock" for event in phase_two["last_exchange"]
    )
    assert phase_two["weak_element"] == "water"
    assert (
        guardian_battle_payload(phase_two, encounter, profiles)["boss_phase"]["index"]
        == 2
    )

    phase_two["enemy_guard"] = (max_guard * 3_300 + 9_999) // 10_000 + 1
    phase_three = submit_guardian_action(
        phase_two,
        {"member_id": 2, "action": "attack"},
        encounter,
        profiles,
    )
    phase_payload = guardian_battle_payload(phase_three, encounter, profiles)
    phase_event = next(
        event
        for event in phase_three["last_exchange"]
        if event.get("phase_code") == "final_erasure"
    )

    assert phase_payload["boss_phase"]["index"] == 3
    assert phase_payload["boss_phase"]["name"] == "최종 말소"
    assert phase_payload["enemy"]["intent"]["power"] >= 3
    assert phase_three["weak_element"] == "poison"
    assert phase_event["presentation_tier"] == 3
    assert phase_event["audio_layer"] == "signature"


def test_server_cooldown_blocks_next_round_then_releases():
    stats = {"care": 4, "focus": 5, "courage": 6, "insight": 7}
    cooldown_profiles = [
        _profile(
            1,
            name="닌자",
            species="ninja-pot",
            form="moonlit",
            stats=stats,
            level=3,
        ),
        _profile(
            2,
            name="안내자",
            species="archive_guide",
            form="mosaic",
            stats=stats,
            level=25,
        ),
    ]
    encounter = _encounter(
        starting_focus=5,
        enemy_max_guard=500,
        max_rounds=6,
    )
    state = resolve_guardian_round(
        new_guardian_battle("keeper", encounter, cooldown_profiles),
        [
            {"member_id": 1, "action": "unique_1"},
            {"member_id": 2, "action": "guard"},
        ],
        encounter,
        cooldown_profiles,
    )
    payload = guardian_battle_payload(state, encounter, cooldown_profiles)
    assert payload["party"][0]["kit"]["unique_skills"][0]["cooldown_remaining"] == 1

    with pytest.raises(CombatRuleError) as error:
        submit_guardian_action(
            state,
            {"member_id": 1, "action": "unique_1"},
            encounter,
            cooldown_profiles,
        )
    assert error.value.code == "EXPEDITION_COMBAT_COOLDOWN"

    state = resolve_guardian_round(
        state,
        [
            {"member_id": 1, "action": "attack"},
            {"member_id": 2, "action": "guard"},
        ],
        encounter,
        cooldown_profiles,
    )
    payload = guardian_battle_payload(state, encounter, cooldown_profiles)
    assert payload["party"][0]["kit"]["unique_skills"][0]["cooldown_remaining"] == 0


def test_element_weakness_and_resistance_are_applied_server_side():
    stats = {"care": 4, "focus": 5, "courage": 6, "insight": 7}
    ninja = _profile(
        1,
        name="닌자",
        species="ninja-pot",
        form="moonlit",
        stats=stats,
        level=25,
    )
    guide = _profile(
        2,
        name="안내자",
        species="archive_guide",
        form="mosaic",
        stats=stats,
        level=25,
    )
    encounter = _encounter(
        starting_focus=5,
        enemy_max_guard=500,
        weak_element="poison",
        resist_element="steel",
    )
    battle = new_guardian_battle("keeper", encounter, [ninja, guide])
    kit = member_battle_kit(ninja, current_weak_element="poison")
    state = submit_guardian_action(
        battle,
        {"member_id": 1, "action": "unique_1"},
        encounter,
        [ninja, guide],
    )
    event = state["last_exchange"][0]
    assert event["matchup"] == "weak"
    assert event["weakness_hit"] is True
    assert event["damage"] == kit["unique_skills"][0]["power"]
    assert event["damage"] > kit["unique_skills"][0]["power_neutral"]

    steel_encounter = _encounter(
        starting_focus=5,
        enemy_max_guard=500,
        weak_element="water",
        resist_element="steel",
    )
    steel_kit = member_battle_kit(
        guide,
        current_weak_element="water",
        current_resist_element="steel",
    )
    state = submit_guardian_action(
        new_guardian_battle("keeper", steel_encounter, [guide]),
        {"member_id": 2, "action": "attack"},
        steel_encounter,
        [guide],
    )
    event = state["last_exchange"][0]
    assert event["matchup"] == "resist"
    assert event["resistance_hit"] is True
    assert event["damage"] == steel_kit["basic"]["power"]
    assert event["damage"] < steel_kit["basic"]["power_neutral"]


def test_six_motion_archetypes_expose_complete_phase_contracts():
    expected_phases = [
        "anticipation",
        "release",
        "travel",
        "contact",
        "reaction",
        "recovery",
    ]
    assert set(MOTION_ARCHETYPES) == {
        "dash",
        "draw",
        "cast",
        "brace",
        "channel",
        "leap",
    }
    for archetype in MOTION_ARCHETYPES:
        normal = combat_motion("test.profile", archetype=archetype)
        ultimate = combat_motion(
            "test.profile",
            archetype=archetype,
            ultimate=True,
        )
        assert [phase["name"] for phase in normal["phases"]] == expected_phases
        assert normal["total_ms"] == sum(phase["ms"] for phase in normal["phases"])
        assert ultimate["total_ms"] > normal["total_ms"]
    assert combat_motion("unknown.profile")["archetype"] == "cast"


def test_all_twenty_four_tangle_intents_have_unique_visual_contracts():
    intents = [
        intent for tangle in TANGLE_CATALOG.values() for intent in tangle["intents"]
    ]
    assert validate_tangle_catalog() == []
    assert len(intents) == len(TANGLE_INTENT_PRESENTATION) == 24
    assert len({intent["vfx_family"] for intent in intents}) == 24
    exact_intents = [
        intent for intent in intents if intent["effect_key"] == intent["code"]
    ]
    assert {intent["code"] for intent in exact_intents} == {
        "paper_flurry",
        "ink_mist",
        "petal_dart",
    }
    assert {intent["target"] for intent in exact_intents} == {
        "front",
        "all",
        "lowest",
    }
    for intent in intents:
        assert intent["motion"]["archetype"] == intent["archetype"]
        assert len(intent["motion"]["phases"]) == 6
        assert intent["kel_fallback_family"] == f"kel.{intent['kel']}"
        assert (
            intent["motion"]["impact_shake_px"]
            == {
                1: 2.2,
                2: 3.0,
                3: 3.8,
            }[intent["power"]]
        )


def test_round_events_snapshot_motion_and_vfx_without_name_branching(profiles):
    encounter = _encounter(
        waves=["tangled_ledger"],
        starting_focus=5,
        enemy_max_guard=500,
    )
    battle = new_guardian_battle("tangle-stage", encounter, profiles)
    skill_state = submit_guardian_action(
        battle,
        {"member_id": 1, "action": "unique_1"},
        encounter,
        profiles,
    )
    party_event = skill_state["last_exchange"][0]
    assert party_event["vfx_family"] == "ninja-pot.venom-seam"
    assert party_event["kel_fallback_family"] == "kel.rainy"
    assert party_event["motion"]["archetype"] == "draw"

    resolved = submit_guardian_action(
        skill_state,
        {"member_id": 2, "action": "guard"},
        encounter,
        profiles,
    )
    enemy_event = next(
        event for event in resolved["last_exchange"] if event["type"] == "enemy_action"
    )
    paper_flurry = tangle_definition("tangled_ledger")["intents"][0]
    assert enemy_event["action_name"] == paper_flurry["name"]
    assert enemy_event["effect_key"] == "paper_flurry"
    assert enemy_event["vfx_family"] == "tangled-ledger.paper-flurry"
    assert enemy_event["motion"]["archetype"] == "leap"

    guarded = submit_guardian_action(
        resolved,
        {"member_id": 1, "action": "guard"},
        encounter,
        profiles,
    )
    next_round = submit_guardian_action(
        guarded,
        {"member_id": 2, "action": "guard"},
        encounter,
        profiles,
    )
    ink_event = next(
        event
        for event in next_round["last_exchange"]
        if event["type"] == "enemy_action"
    )
    assert ink_event["effect_key"] == "ink_mist"
    assert ink_event["vfx_family"] == "tangled-ledger.ink-mist"
    assert ink_event["motion"]["archetype"] == "channel"


def test_petal_dart_targets_the_lowest_member_with_its_exact_effect(profiles):
    encounter = _encounter(
        waves=["drifting_pressings"],
        starting_focus=5,
        enemy_max_guard=500,
    )
    battle = new_guardian_battle("petal-dart-stage", encounter, profiles)
    battle["party"][1]["hp"] = 1

    first_round = submit_guardian_action(
        battle,
        {"member_id": 1, "action": "guard"},
        encounter,
        profiles,
    )
    first_round = submit_guardian_action(
        first_round,
        {"member_id": 2, "action": "guard"},
        encounter,
        profiles,
    )
    second_round = submit_guardian_action(
        first_round,
        {"member_id": 1, "action": "guard"},
        encounter,
        profiles,
    )
    second_round = submit_guardian_action(
        second_round,
        {"member_id": 2, "action": "guard"},
        encounter,
        profiles,
    )
    event = next(
        item for item in second_round["last_exchange"] if item["type"] == "enemy_action"
    )

    assert event["effect_key"] == "petal_dart"
    assert event["vfx_family"] == "drifting-pressings.petal-dart"
    assert event["motion"]["archetype"] == "draw"
    assert event["motion"]["total_ms"] == 720
    assert [target["member_id"] for target in event["targets"]] == [2]
