"""마음결 기록서 카탈로그와 장착 판정 계약.

`docs/character_skill_growth_design.md` 7장이 획득·경제·장착·해금의 단일 원본이고,
`docs/adventure_100_point_execution_contract.md` 4.4가 선택 슬롯 해석 순서를 정한다.
두 문서의 문장을 그대로 검사한다.
"""

from app.content.expeditions.skill_books import (
    ACTIVATION_ROSTER,
    DEFAULT_LOADOUT,
    GRADE_ALLOWED_SLOTS,
    SKILL_BOOK_CATALOG,
    SLOT_UNLOCK_LEVEL,
    is_combat_skill_book,
    resolve_loadout,
    skill_book,
    validate_skill_book_catalog,
)


ALL_CODES = frozenset(SKILL_BOOK_CATALOG)


def test_combat_catalog_matches_the_design_contract():
    """전투 기록서 20종의 등급·모드 분포가 설계서 표와 같다."""

    assert validate_skill_book_catalog() == []
    assert len(SKILL_BOOK_CATALOG) == 20

    grades = [book["grade"] for book in SKILL_BOOK_CATALOG.values()]
    # 1등급 14종·2등급 14종의 절반이 전투형이고, 3등급 8종 중 6종이 전투형이다.
    assert grades.count(1) == 7
    assert grades.count(2) == 7
    assert grades.count(3) == 6

    # 7.5.1의 닫힌 목록과 정확히 일치해야 한다. 문구에서 모드를 추측하지 않는다.
    assert sum(len(codes) for codes in ACTIVATION_ROSTER.values()) == 20
    for mode, codes in ACTIVATION_ROSTER.items():
        actual = {
            code
            for code, book in SKILL_BOOK_CATALOG.items()
            if book["activation_mode"] == mode
        }
        assert actual == set(codes), mode


def test_every_book_is_reward_neutral_and_permanent():
    """기록서는 보상을 1도 바꾸지 않고 소모되지 않는다."""

    for code, book in SKILL_BOOK_CATALOG.items():
        assert book["reward_affecting"] is False, code
        # 소모·강화·합성·분해 개념 자체를 카탈로그에 두지 않는다.
        assert "charges" not in book, code
        assert "consumable" not in book, code


def test_grade_three_is_second_slot_only_and_cannot_be_bought():
    """가장 강한 도구는 가장 오래 키운 캐릭터에게만, 그리고 도전으로만 열린다."""

    assert GRADE_ALLOWED_SLOTS[3] == ("B2",)
    for code, book in SKILL_BOOK_CATALOG.items():
        if book["grade"] != 3:
            continue
        assert book["min_slot"] == "B2", code
        assert book["acquire_kind"] == "challenge", code
        assert book["price_seeds"] is None, code
        # 예산 2를 쓰는 대신 반드시 반대급부를 함께 가진다.
        assert book["tradeoff"], code


def test_catalog_hands_out_copies():
    """호출부가 카탈로그 원본을 바꿔 다음 전투에 새게 하지 않는다."""

    first = skill_book("clear_aim")
    assert first is not None
    first["effect_summary"] = "바꿔치기"
    assert SKILL_BOOK_CATALOG["clear_aim"]["effect_summary"] != "바꿔치기"
    assert skill_book("no_such_book") is None
    assert is_combat_skill_book("clear_aim")
    # 탐험 기록서는 이 카탈로그에 없다. 전투 슬롯 판정에 끼어들지 않는다.
    assert not is_combat_skill_book("retrace")
    assert not is_combat_skill_book(None)


def test_missing_loadout_falls_back_to_the_safe_default():
    """장착 기능을 아직 열지 않은 계정도 여섯 슬롯이 비지 않는다."""

    resolved = resolve_loadout(None, owned_codes=frozenset(), level=30)
    assert resolved["B1"]["source"] == "emotion"
    assert resolved["B1"]["code"] == DEFAULT_LOADOUT["B1"]
    assert resolved["B2"]["source"] == "default_book"
    assert resolved["B2"]["code"] == DEFAULT_LOADOUT["B2"]
    # 아무것도 저장하지 않은 상태는 `되돌려졌다`가 아니다.
    assert resolved["B1"]["fell_back"] is False
    assert resolved["B2"]["fell_back"] is False


def test_slots_open_at_their_unlock_levels():
    """B1은 Lv9, B2는 Lv23부터다. 잠긴 슬롯은 이유를 함께 돌려준다."""

    assert SLOT_UNLOCK_LEVEL == {"B1": 9, "B2": 23}
    low = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "short_cheer"},
        owned_codes=ALL_CODES,
        level=5,
    )
    assert low["B1"]["locked"] is True
    assert low["B2"]["locked"] is True
    assert "Lv9" in low["B1"]["lock_reason"]
    assert "Lv23" in low["B2"]["lock_reason"]

    middle = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "short_cheer"},
        owned_codes=ALL_CODES,
        level=9,
    )
    assert middle["B1"]["code"] == "clear_aim"
    assert middle["B2"]["locked"] is True


def test_owned_books_equip_and_unowned_books_fall_back():
    """소유와 장착은 분리된다. 보유하지 않은 책은 장착되지 않는다."""

    equipped = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "short_cheer"},
        owned_codes=frozenset({"clear_aim", "short_cheer"}),
        level=30,
    )
    assert equipped["B1"]["source"] == "skillbook"
    assert equipped["B1"]["code"] == "clear_aim"
    assert equipped["B2"]["code"] == "short_cheer"
    assert equipped["B2"]["fell_back"] is False

    missing = resolve_loadout(
        {"slot_b2_code": "reviving_root"},
        owned_codes=frozenset({"clear_aim"}),
        level=30,
    )
    assert missing["B2"]["code"] == DEFAULT_LOADOUT["B2"]
    assert missing["B2"]["fell_back"] is True
    assert missing["B2"]["lock_reason"] == "아직 서고에 없어요"


def test_grade_three_in_the_first_slot_is_refused_without_blocking_departure():
    """3등급을 B1에 저장해도 출발을 막지 않고 기본값으로 내려온다."""

    resolved = resolve_loadout(
        {"slot_b1_code": "shadow_oath"},
        owned_codes=ALL_CODES,
        level=30,
    )
    assert resolved["B1"]["source"] == "emotion"
    assert resolved["B1"]["fell_back"] is True
    assert "두 번째 칸" in resolved["B1"]["lock_reason"]

    allowed = resolve_loadout(
        {"slot_b2_code": "shadow_oath"},
        owned_codes=ALL_CODES,
        level=30,
    )
    assert allowed["B2"]["code"] == "shadow_oath"
    assert allowed["B2"]["fell_back"] is False


def test_two_slots_cannot_share_a_stack_group():
    """같은 stack_group을 두 칸에 함께 두면 뒤 칸이 기본값으로 내려온다."""

    # clear_aim과 final_resolve는 둘 다 basic_power다.
    assert (
        SKILL_BOOK_CATALOG["clear_aim"]["stack_group"]
        == SKILL_BOOK_CATALOG["final_resolve"]["stack_group"]
    )
    resolved = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "final_resolve"},
        owned_codes=ALL_CODES,
        level=30,
    )
    assert resolved["B1"]["code"] == "clear_aim"
    assert resolved["B2"]["code"] == DEFAULT_LOADOUT["B2"]
    assert "같은 결" in resolved["B2"]["lock_reason"]

    # 다른 그룹이면 둘 다 남는다.
    fine = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "short_cheer"},
        owned_codes=ALL_CODES,
        level=30,
    )
    assert fine["B1"]["code"] == "clear_aim"
    assert fine["B2"]["code"] == "short_cheer"


def test_exploration_books_rest_in_combat_instead_of_erroring():
    """수호 프리셋에 탐험 기록서를 넣어도 출발을 막지 않는다."""

    resolved = resolve_loadout(
        {"slot_b2_code": "retrace"},
        owned_codes=frozenset({"retrace"}),
        level=30,
    )
    assert resolved["B2"]["code"] == DEFAULT_LOADOUT["B2"]
    assert resolved["B2"]["lock_reason"] == "이 기록서는 전투에서 쉬어요"


def test_only_command_books_take_a_member_action():
    """opening·trigger는 스스로 발동하므로 벨트에서 누를 수 없다."""

    for code, book in SKILL_BOOK_CATALOG.items():
        if book["grade"] == 3:
            slot, other = "slot_b2_code", "B2"
        else:
            slot, other = "slot_b1_code", "B1"
        resolved = resolve_loadout(
            {slot: code}, owned_codes=ALL_CODES, level=30
        )[other]
        assert resolved["code"] == code, code
        if book["activation_mode"] == "command":
            assert resolved["locked"] is False, code
            assert resolved["lock_reason"] is None, code
        else:
            # 자리를 비워 벨트 위치를 바꾸지 않고, 왜 못 누르는지 알려 준다.
            assert resolved["locked"] is True, code
            assert resolved["lock_reason"] == "때가 되면 스스로 펼쳐져요", code


def test_ownership_check_can_be_skipped_before_the_store_is_wired():
    """소유권 저장소를 붙이기 전 호출부는 카탈로그만으로 해석할 수 있다."""

    resolved = resolve_loadout(
        {"slot_b1_code": "clear_aim"}, owned_codes=None, level=30
    )
    assert resolved["B1"]["code"] == "clear_aim"
    assert resolved["B1"]["fell_back"] is False


def test_emotion_pointers_stay_in_either_slot():
    """감정 스킬 포인터는 두 칸 어디에나 둘 수 있다."""

    resolved = resolve_loadout(
        {"slot_b1_code": "emotion.secondary", "slot_b2_code": "emotion.primary"},
        owned_codes=frozenset(),
        level=30,
    )
    assert resolved["B1"]["source"] == "emotion"
    assert resolved["B1"]["code"] == "emotion.secondary"
    assert resolved["B2"]["source"] == "emotion"
    assert resolved["B2"]["code"] == "emotion.primary"
    assert resolved["B2"]["fell_back"] is False


def _profile(snapshot_extra: dict | None = None) -> dict:
    return {
        "id": 1,
        "snapshot": {
            "name": "달빛이",
            "species": {"code": "baby-pot"},
            "form": "sunny",
            "level": 30,
            "stage": 5,
            "rarity": 3,
            "stats": {"care": 7, "focus": 6, "courage": 5, "insight": 6},
            **(snapshot_extra or {}),
        },
    }


def test_battle_kit_uses_the_frozen_loadout_from_the_snapshot():
    """출발 시점에 얼린 장착이 실제 여섯 슬롯을 정한다."""

    from app.content.expeditions.combat import member_battle_kit

    equipped = member_battle_kit(
        _profile(
            {
                "skill_loadout": {
                    "preset_code": "guard",
                    "slots": {
                        "B1": {"source": "skillbook", "code": "clear_aim"},
                        "B2": {"source": "default_book", "code": "field_note_echo"},
                    },
                }
            }
        )
    )
    selected = {item["slot"]: item for item in equipped["selected_skills"]}
    assert selected["selected_1"]["equipped_book"]["code"] == "clear_aim"
    # 기믹이 아직 없으므로 누를 수 없는 상태로 정직하게 표시한다.
    assert selected["selected_1"]["available"] is False
    assert selected["selected_1"]["lock_reason"]
    assert "equipped_book" not in selected["selected_2"]


def test_battle_kit_without_a_snapshot_keeps_the_safe_default():
    """장착 기능 이전에 출발한 런은 지금까지와 똑같이 재생된다."""

    from app.content.expeditions.combat import member_battle_kit

    kit = member_battle_kit(_profile())
    selected = {item["slot"]: item for item in kit["selected_skills"]}
    assert selected["selected_1"]["source"] == "emotion"
    assert selected["selected_2"]["source"] == "skillbook"
    assert selected["selected_2"]["code"] == "field_note_echo"
    assert selected["selected_1"]["available"] is True
    assert "equipped_book" not in selected["selected_1"]


def test_catalog_and_effect_table_agree_on_what_is_wired():
    """카탈로그의 `combat_effect`와 실제 수치표가 어긋나면 안 된다."""

    from app.content.expeditions.skill_book_effects import IMPLEMENTED_CODES

    wired = {
        code for code, book in SKILL_BOOK_CATALOG.items() if book["combat_effect"]
    }
    assert wired == set(IMPLEMENTED_CODES)
    # 아직 연결하지 않은 책은 효과를 주장하지 않는다.
    for code, book in SKILL_BOOK_CATALOG.items():
        assert isinstance(book["combat_effect"], bool), code


def test_book_effects_are_flat_and_never_scale():
    """정액 계약 — 등급·tier·지원 능력치로 자라지 않는다."""

    from app.content.expeditions.combat import member_battle_kit

    def kit_with(code: str, *, stats: dict, rarity: int, level: int):
        return member_battle_kit(
            _profile(
                {
                    "stats": stats,
                    "rarity": rarity,
                    "level": level,
                    "skill_loadout": {
                        "preset_code": "guard",
                        "slots": {
                            "B1": {"source": "skillbook", "code": code},
                            "B2": {"source": "default_book", "code": "field_note_echo"},
                        },
                    },
                }
            )
        )

    weak = {"care": 3, "focus": 3, "courage": 3, "insight": 3}
    strong = {"care": 9, "focus": 9, "courage": 9, "insight": 9}

    # 잎사귀 각반 — 방어량 2 → 3. 어떤 캐릭터가 들어도 정확히 +1이다.
    for stats, rarity, level in ((weak, 1, 9), (strong, 5, 30)):
        bare = member_battle_kit(
            _profile({"stats": stats, "rarity": rarity, "level": level})
        )
        with_book = kit_with("leaf_greave", stats=stats, rarity=rarity, level=level)
        assert with_book["guard"]["guard"] - bare["guard"]["guard"] == 1

    # 또렷한 겨냥 — 기본 공격 위력 +3. 정액이라 등급 계수를 타지 않는다.
    for stats, rarity, level in ((weak, 1, 9), (strong, 5, 30)):
        bare = member_battle_kit(
            _profile({"stats": stats, "rarity": rarity, "level": level})
        )
        with_book = kit_with("clear_aim", stats=stats, rarity=rarity, level=level)
        assert with_book["basic"]["raw_power"] - bare["basic"]["raw_power"] == 3


def test_opening_books_change_the_battle_start_once():
    """전투 시작 보정은 파티 자원에 한 번만 더해지고 상한을 지킨다."""

    from app.content.expeditions.skill_book_effects import opening_modifiers

    def party(*codes):
        return [
            {
                "id": index + 1,
                "snapshot": {
                    "skill_loadout": {
                        "slots": {
                            "B1": {"source": "skillbook", "code": code},
                            "B2": {"source": "emotion", "code": "emotion.primary"},
                        }
                    }
                },
            }
            for index, code in enumerate(codes)
        ]

    assert opening_modifiers(party())["focus"] == 0
    assert opening_modifiers(party("first_breath"))["focus"] == 1
    # 발아 시계의 태엽 — 집중력 +2에 1라운드 스킬 사용 불가라는 반대급부.
    gear = opening_modifiers(party("germination_gear"))
    assert gear["focus"] == 2
    assert gear["first_round_skill_locked"] == [1]
    # 물결 종지기의 종 — 라운드 +1에 집중력 최대치 −1.
    chime = opening_modifiers(party("bellringer_chime"))
    assert chime["max_rounds"] == 1
    assert chime["max_focus"] == -1
    # 효과가 없는 책은 아무것도 더하지 않는다.
    assert opening_modifiers(party("short_cheer"))["books"] == []


def test_first_breath_actually_starts_the_battle_with_more_focus():
    """구매 → 장착 → 전투까지 한 권이 끝까지 이어진다."""

    from app.content.expeditions.combat import new_guardian_battle

    encounter = {
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
                "telegraph": "노려요.",
                "target": "front",
                "power": 1,
            }
        ],
    }
    bare = new_guardian_battle("no-book", encounter, [_profile()])
    equipped = new_guardian_battle(
        "with-book",
        encounter,
        [
            _profile(
                {
                    "skill_loadout": {
                        "slots": {
                            "B1": {"source": "skillbook", "code": "first_breath"},
                            "B2": {"source": "emotion", "code": "emotion.primary"},
                        }
                    }
                }
            )
        ],
    )
    assert equipped["focus"] == bare["focus"] + 1
    assert equipped["focus"] <= equipped["max_focus"]
    assert equipped["skill_book_opening"]["books"] == ["first_breath"]


def test_starting_focus_never_passes_the_cap():
    """`상한 5 유지`는 책 문장에 적힌 조건이다."""

    from app.content.expeditions.combat import new_guardian_battle

    encounter = {
        "enemy_name": "돌비늘 장부지기",
        "enemy_max_guard": 100,
        "max_rounds": 6,
        # 이미 상한까지 찬 상태에서 시작하는 전투.
        "starting_focus": 5,
        "max_focus": 5,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "claw",
                "name": "장부 발톱",
                "telegraph": "노려요.",
                "target": "front",
                "power": 1,
            }
        ],
    }
    battle = new_guardian_battle(
        "capped",
        encounter,
        [
            _profile(
                {
                    "skill_loadout": {
                        "slots": {
                            "B1": {"source": "skillbook", "code": "germination_gear"},
                            "B2": {"source": "emotion", "code": "emotion.primary"},
                        }
                    }
                }
            )
        ],
    )
    assert battle["focus"] == battle["max_focus"] == 5


def _encounter_fixture() -> dict:
    return {
        "enemy_name": "돌비늘 장부지기",
        "enemy_max_guard": 400,
        "max_rounds": 6,
        "starting_focus": 3,
        "max_focus": 5,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "claw",
                "name": "장부 발톱",
                "telegraph": "노려요.",
                "target": "front",
                "power": 1,
            }
        ],
    }


def _party_with(code: str | None) -> list[dict]:
    slots = (
        {
            "B1": {"source": "skillbook", "code": code},
            "B2": {"source": "emotion", "code": "emotion.primary"},
        }
        if code
        else None
    )
    return [
        _profile({"skill_loadout": {"slots": slots}} if slots else None),
        {
            **_profile(),
            "id": 2,
            "snapshot": {**_profile()["snapshot"], "name": "볕이"},
        },
    ]


def test_germination_gear_locks_skills_in_the_first_round():
    """집중력 +2를 받은 대원은 1라운드에 스킬을 쓸 수 없다."""

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _party_with("germination_gear")
    battle = new_guardian_battle("gear", encounter, profiles)
    assert battle["skill_book_opening"]["first_round_skill_locked"] == [1]

    for action in ("unique_1", "unique_2", "selected_1", "selected_2"):
        try:
            submit_guardian_action(
                battle, {"member_id": 1, "action": action}, encounter, profiles
            )
        except CombatRuleError as error:
            assert error.code == "EXPEDITION_COMBAT_FIRST_ROUND_SKILL_LOCKED"
        else:  # pragma: no cover - 반대급부가 없으면 이득만 남는다
            raise AssertionError(f"{action}이 1라운드에 통과했습니다")

    # 밸런스 불변식 — 최소 한 행동은 언제나 합법이어야 한다.
    for action in ("attack", "guard"):
        fresh = new_guardian_battle("gear", encounter, profiles)
        assert submit_guardian_action(
            fresh, {"member_id": 1, "action": action}, encounter, profiles
        )

    # 대가를 지지 않은 다른 대원은 1라운드에도 자유롭다.
    assert submit_guardian_action(
        new_guardian_battle("gear", encounter, profiles),
        {"member_id": 2, "action": "unique_1"},
        encounter,
        profiles,
    )


def test_germination_gear_lock_lifts_after_the_first_round():
    """반대급부는 1라운드까지다. 그 뒤에는 평소처럼 쓴다."""

    from app.content.expeditions.combat import new_guardian_battle, submit_guardian_action

    encounter = _encounter_fixture()
    profiles = _party_with("germination_gear")
    state = new_guardian_battle("gear", encounter, profiles)
    for member_id in (1, 2):
        state = submit_guardian_action(
            state, {"member_id": member_id, "action": "attack"}, encounter, profiles
        )
    assert int(state["round"]) >= 2
    assert submit_guardian_action(
        state, {"member_id": 1, "action": "unique_1"}, encounter, profiles
    )


def test_bellringer_chime_pays_with_a_lower_focus_cap():
    """라운드 +1을 받은 대신 그 전투의 집중력 최대치가 1 줄어든다."""

    from app.content.expeditions.combat import new_guardian_battle, submit_guardian_action

    encounter = _encounter_fixture()
    bare = new_guardian_battle("bare", encounter, _party_with(None))
    profiles = _party_with("bellringer_chime")
    chimed = new_guardian_battle("chime", encounter, profiles)

    assert chimed["max_rounds"] == bare["max_rounds"] + 1
    assert chimed["max_focus"] == bare["max_focus"] - 1

    # 줄어든 상한이 실제 판정에서도 지켜진다. 지키기로 집중력을 계속 모아도
    # 원래 상한(5)까지 오르지 않는다.
    state = chimed
    for _ in range(3):
        if state.get("status") != "active":
            break
        for member_id in (1, 2):
            state = submit_guardian_action(
                state, {"member_id": member_id, "action": "guard"}, encounter, profiles
            )
    assert int(state["focus"]) <= int(chimed["max_focus"])
    assert int(chimed["max_focus"]) == 4


def _party_book(code: str) -> list[dict]:
    return [
        _profile(
            {
                "skill_loadout": {
                    "slots": {
                        "B1": {"source": "skillbook", "code": code},
                        "B2": {"source": "emotion", "code": "emotion.primary"},
                    }
                }
            }
        ),
        {
            **_profile(),
            "id": 2,
            "snapshot": {**_profile()["snapshot"], "name": "볕이"},
        },
    ]


def _battle_with(code: str, encounter: dict, profiles: list[dict], focus: int):
    """집중력에 여유를 둔 전투를 만든다.

    Lv30 파티는 시작 집중력이 이미 상한이라 +1이 상한에 먹혀 보이지 않는다.
    트리거가 실제로 더해지는지 보려면 여유가 있어야 한다.
    """

    from app.content.expeditions.combat import new_guardian_battle

    state = new_guardian_battle(code, encounter, profiles)
    state["focus"] = focus
    return state


def test_bracing_adds_one_focus_on_guard_once_per_battle():
    """전투 1회 — 두 번째 방어에는 더 붙지 않는다."""

    from app.content.expeditions.combat import submit_guardian_action

    encounter = _encounter_fixture()
    bare_profiles = _party_book("clear_aim")
    book_profiles = _party_book("bracing")

    bare = submit_guardian_action(
        _battle_with("bare", encounter, bare_profiles, 0),
        {"member_id": 1, "action": "guard"},
        encounter,
        bare_profiles,
    )
    braced = submit_guardian_action(
        _battle_with("braced", encounter, book_profiles, 0),
        {"member_id": 1, "action": "guard"},
        encounter,
        book_profiles,
    )
    # 지키기 기본 +1에 버티는 자세 +1이 더해진다.
    assert bare["focus"] == 1
    assert braced["focus"] == 2

    # 같은 대원이 다시 방어해도 이번에는 기본 +1뿐이다.
    second = submit_guardian_action(
        braced, {"member_id": 2, "action": "guard"}, encounter, book_profiles
    )
    third = submit_guardian_action(
        second, {"member_id": 1, "action": "guard"}, encounter, book_profiles
    )
    assert third["focus"] - second["focus"] == 1


def test_focus_knot_refunds_one_focus_after_a_skill():
    """스킬 비용을 낸 뒤 한 칸 돌려받는다. 비용 판정은 느슨해지지 않는다."""

    from app.content.expeditions.combat import (
        CombatRuleError,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    bare_profiles = _party_book("clear_aim")
    book_profiles = _party_book("focus_knot")

    bare = submit_guardian_action(
        _battle_with("bare", encounter, bare_profiles, 3),
        {"member_id": 1, "action": "unique_1"},
        encounter,
        bare_profiles,
    )
    knotted = submit_guardian_action(
        _battle_with("knot", encounter, book_profiles, 3),
        {"member_id": 1, "action": "unique_1"},
        encounter,
        book_profiles,
    )
    assert knotted["focus"] == bare["focus"] + 1

    # 집중력이 모자라면 트리거가 있어도 쓸 수 없다.
    poor = _battle_with("poor", encounter, book_profiles, 0)
    try:
        submit_guardian_action(
            poor, {"member_id": 1, "action": "unique_1"}, encounter, book_profiles
        )
    except CombatRuleError as error:
        assert "집중력" in error.message
    else:  # pragma: no cover
        raise AssertionError("비용 판정이 트리거로 느슨해졌습니다")


def test_a_fired_trigger_is_remembered_in_the_battle_state():
    """저장된 런을 이어서 해도 같은 책이 두 번 터지지 않는다."""

    from app.content.expeditions.combat import submit_guardian_action

    encounter = _encounter_fixture()
    profiles = _party_book("bracing")
    state = submit_guardian_action(
        _battle_with("memory", encounter, profiles, 0),
        {"member_id": 1, "action": "guard"},
        encounter,
        profiles,
    )
    assert state["skill_book_triggers"] == {"1:bracing": True}


def test_command_book_becomes_a_real_action_with_grade_priced_focus():
    """7.5.1 — 대원 행동 1회를 쓰고, 비용은 등급을 따르며, 전투당 한 번이다."""

    from app.content.expeditions.combat import member_battle_kit

    kit = member_battle_kit(
        _profile(
            {
                "skill_loadout": {
                    "slots": {
                        "B1": {"source": "skillbook", "code": "short_cheer"},
                        "B2": {"source": "emotion", "code": "emotion.primary"},
                    }
                }
            }
        )
    )
    slot = next(
        item for item in kit["selected_skills"] if item["slot"] == "selected_1"
    )
    assert slot["available"] is True
    assert slot["lock_reason"] is None
    assert slot["code"] == "short_cheer"
    assert slot["name"] == "짧은 격려"
    # 1등급은 집중력 0으로 쓴다.
    assert slot["focus_cost"] == 0
    # 기록서는 피해를 주지 않는 지원 도구다.
    assert slot["power"] == 0
    # 전투당 1회 — 최대 라운드보다 긴 쿨타임으로 표현한다.
    assert slot["cooldown_turns"] > 7
    assert slot["equipped_book"]["grade"] == 1


def test_short_cheer_heals_exactly_one_and_never_scales():
    """정액 계약 — 어떤 캐릭터가 써도 정확히 1만 회복한다."""

    from app.content.expeditions.combat import (
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("short_cheer")
    for stats, rarity, level in (
        ({"care": 3, "focus": 3, "courage": 3, "insight": 3}, 1, 9),
        ({"care": 9, "focus": 9, "courage": 9, "insight": 9}, 5, 30),
    ):
        profiles[0]["snapshot"].update(
            {"stats": stats, "rarity": rarity, "level": level}
        )
        state = new_guardian_battle("cheer", encounter, profiles)
        # 회복을 확인하려면 다친 대원이 있어야 한다.
        state["party"][1]["hp"] = 1
        healed = submit_guardian_action(
            state, {"member_id": 1, "action": "selected_1"}, encounter, profiles
        )
        assert healed["party"][1]["hp"] == 2, (stats, rarity, level)


def test_short_cheer_can_only_be_used_once_per_battle():
    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("short_cheer")
    state = new_guardian_battle("once", encounter, profiles)
    state["party"][1]["hp"] = 1
    state = submit_guardian_action(
        state, {"member_id": 1, "action": "selected_1"}, encounter, profiles
    )
    state = submit_guardian_action(
        state, {"member_id": 2, "action": "guard"}, encounter, profiles
    )
    try:
        submit_guardian_action(
            state, {"member_id": 1, "action": "selected_1"}, encounter, profiles
        )
    except CombatRuleError as error:
        assert error.code == "EXPEDITION_COMBAT_COOLDOWN"
        # 전투당 1회짜리는 남은 턴 수 대신 이 전투에서 끝났다고 알려 준다.
        assert "이 전투에서 한 번만" in error.message
        assert "턴 뒤" not in error.message
    else:  # pragma: no cover - 전투당 1회 계약 위반
        raise AssertionError("같은 전투에서 두 번 사용됐습니다")


def test_books_without_a_mechanic_stay_locked_and_say_so():
    """기믹이 없는 책은 이름만 보이고 누를 수 없다. 있는 척하지 않는다.

    카탈로그가 아직 `combat_effect: false`로 둔 책 전부를 훑는다. 예시 하나를
    박아 두면 그 책이 연결되는 날 테스트를 고치느라 계약이 흐려진다.
    """

    from app.content.expeditions.combat import member_battle_kit

    unwired = [
        code for code, book in SKILL_BOOK_CATALOG.items() if not book["combat_effect"]
    ]
    for code in unwired:
        kit = member_battle_kit(
            _profile(
                {
                    "skill_loadout": {
                        "slots": {
                            "B1": {"source": "skillbook", "code": code},
                            "B2": {"source": "emotion", "code": "emotion.primary"},
                        }
                    }
                }
            )
        )
        slot = next(
            item for item in kit["selected_skills"] if item["slot"] == "selected_1"
        )
        assert slot["available"] is False, code
        assert slot["lock_reason"] == "효과를 준비하고 있어요", code
        assert slot["equipped_book"]["code"] == code


def test_reviving_root_brings_one_downed_member_back_at_one_hp():
    """설계서 7.4 — HP 0 대원 1명을 HP 1로 복귀. 정액이다."""

    from app.content.expeditions.combat import (
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("reviving_root")
    for stats, rarity in (
        ({"care": 3, "focus": 3, "courage": 3, "insight": 3}, 1),
        ({"care": 9, "focus": 9, "courage": 9, "insight": 9}, 5),
    ):
        profiles[0]["snapshot"].update({"stats": stats, "rarity": rarity})
        state = new_guardian_battle("revive", encounter, profiles)
        state["party"][1]["hp"] = 0
        revived = submit_guardian_action(
            state, {"member_id": 1, "action": "selected_1"}, encounter, profiles
        )
        # 어떤 캐릭터가 써도 정확히 1로 돌아온다. 능력치로 자라지 않는다.
        assert revived["party"][1]["hp"] == 1, (stats, rarity)


def test_reviving_root_costs_one_focus_as_a_grade_two_book():
    from app.content.expeditions.combat import member_battle_kit

    kit = member_battle_kit(
        _profile(
            {
                "skill_loadout": {
                    "slots": {
                        "B1": {"source": "skillbook", "code": "reviving_root"},
                        "B2": {"source": "emotion", "code": "emotion.primary"},
                    }
                }
            }
        )
    )
    slot = next(
        item for item in kit["selected_skills"] if item["slot"] == "selected_1"
    )
    assert slot["available"] is True
    # 7.5.1 — 2등급 command는 집중력 1이다.
    assert slot["focus_cost"] == 1


def test_double_leaf_carries_one_guard_into_the_next_round():
    """지키기 잔여 방어 1칸만 넘어간다. 나머지는 평소대로 사라진다."""

    from app.content.expeditions.combat import _begin_round_if_needed

    encounter = _encounter_fixture()
    profiles = _party_book("double_leaf")
    from app.content.expeditions.combat import new_guardian_battle

    state = new_guardian_battle("carry", encounter, profiles)
    assert state["skill_book_opening"]["guard_carry"] == {"1": 1}

    # 라운드가 끝난 상태를 만든다.
    state["pending"] = None
    state["party"][0]["guard"] = 3
    state["party"][1]["guard"] = 3
    _begin_round_if_needed(state)

    # 책을 든 대원만 1칸을 가져간다.
    assert state["party"][0]["guard"] == 1
    assert state["party"][1]["guard"] == 0


def test_double_leaf_cannot_carry_more_than_is_left():
    """남은 방어가 없으면 이월할 것도 없다."""

    from app.content.expeditions.combat import (
        _begin_round_if_needed,
        new_guardian_battle,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("double_leaf")
    state = new_guardian_battle("carry-none", encounter, profiles)
    state["pending"] = None
    state["party"][0]["guard"] = 0
    _begin_round_if_needed(state)
    assert state["party"][0]["guard"] == 0


def test_a_party_without_the_book_never_carries_guard():
    from app.content.expeditions.combat import (
        _begin_round_if_needed,
        new_guardian_battle,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("clear_aim")
    state = new_guardian_battle("no-carry", encounter, profiles)
    assert state["skill_book_opening"]["guard_carry"] == {}
    state["pending"] = None
    state["party"][0]["guard"] = 3
    _begin_round_if_needed(state)
    assert state["party"][0]["guard"] == 0


def test_echo_read_opens_the_next_round_intent_for_one_round():
    """전투 1회, 다음 라운드 예고를 미리 본다. 쓰지 않으면 나타나지 않는다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
        submit_guardian_action,
    )

    # 예고가 하나뿐인 적은 `다음 예고`도 같은 행동이라 미리 봐야 의미가 없다.
    # 두 예고를 번갈아 쓰는 적으로 확인한다.
    encounter = _encounter_fixture()
    encounter["intents"] = [
        *encounter["intents"],
        {
            "code": "wave",
            "name": "기록 파동",
            "telegraph": "모두를 노려요.",
            "target": "all",
            "power": 1,
        },
    ]
    profiles = _party_book("echo_read")

    plain = new_guardian_battle("plain", encounter, profiles)
    assert guardian_battle_payload(plain, encounter, profiles)["enemy"]["next_intent"] is None

    used = submit_guardian_action(
        plain, {"member_id": 1, "action": "selected_1"}, encounter, profiles
    )
    payload = guardian_battle_payload(used, encounter, profiles)
    preview = payload["enemy"]["next_intent"]
    assert preview is not None
    # 지금 예고와 다음 예고는 서로 다른 행동이다.
    assert preview["code"] != payload["enemy"]["intent"]["code"]
    # 예고를 읽는 데 필요한 정보가 함께 온다.
    assert preview["telegraph"]
    assert preview["target"] in {"front", "lowest", "all"}


def test_weakness_engrave_lands_only_on_a_weakness_hit_and_once():
    """기다리던 +3은 약점을 실제로 맞힌 공격에만, 한 번만 실린다."""

    from app.content.expeditions.combat import new_guardian_battle
    from app.content.expeditions.skill_book_effects import (
        book_state,
        take_weakness_bonus,
    )

    encounter = _encounter_fixture()
    state = new_guardian_battle("engrave", encounter, _party_book("weakness_engrave"))

    # 아직 쓰지 않았으면 실릴 것이 없다.
    assert take_weakness_bonus(state) == 0

    book_state(state)["weakness_bonus"] = 3
    # 처음 약점 공격이 가져가고,
    assert take_weakness_bonus(state) == 3
    # 그 뒤로는 남지 않는다.
    assert take_weakness_bonus(state) == 0


def test_choice_needing_books_are_declared_but_not_wired():
    """선택을 받아야 하는 책은 계약만 적어 두고 열지 않는다."""

    from app.content.expeditions.skill_book_effects import (
        CHOICE_REQUIRED,
        COMMAND_ACTIONS,
    )

    from app.content.expeditions.skill_book_effects import choice_kind

    for code in CHOICE_REQUIRED:
        assert SKILL_BOOK_CATALOG[code]["activation_mode"] == "command"
        if code in COMMAND_ACTIONS:
            # 열린 책은 무엇을 고르는지 반드시 밝혀야 한다. 고를 것을 모르면
            # 앱이 선택지를 만들 수 없고 사용자가 막힌다.
            assert choice_kind(code), code
            assert SKILL_BOOK_CATALOG[code]["combat_effect"] is True, code
        else:
            # 아직 안 연 책은 효과를 주장하지 않는다.
            assert SKILL_BOOK_CATALOG[code]["combat_effect"] is False, code


def _kel_encounter() -> dict:
    """성장결 약점이 실제로 있는 교전.

    기본 교전 fixture는 `weak_element`가 없어 모든 공격이 neutral이다. 조율기는
    상성을 바꾸는 책이라 바꿀 상성이 있어야 검증이 된다. 기본 캐릭터의 결이
    `sunny`이므로 약점을 `fire`(=ember)로 두면 고르기 전과 후가 갈린다.
    """

    return {**_encounter_fixture(), "weak_element": "fire"}


def test_resonance_tuner_shows_what_there_is_to_choose():
    """앱이 선택지를 스스로 만들지 않도록 서버가 후보까지 내려보낸다."""

    from app.content.expeditions.combat import member_battle_kit
    from app.content.expeditions.skill_book_effects import CHOICE_KELS

    kit = member_battle_kit(_party_book("resonance_tuner")[0])
    slot = [item for item in kit["selected_skills"] if item["slot"] == "selected_1"][0]

    assert slot["choice_kind"] == "kel"
    assert [option["value"] for option in slot["choice_options"]] == list(CHOICE_KELS)
    # 이름표까지 함께 준다. 앱이 코드→한글 표를 따로 들고 있으면 어긋난다.
    assert all(option["label"] for option in slot["choice_options"])

    # 고를 것이 없는 책은 빈 목록이라 앱이 선택 화면을 띄우지 않는다.
    plain = member_battle_kit(_party_book("short_cheer")[0])
    plain_slot = [
        item for item in plain["selected_skills"] if item["slot"] == "selected_1"
    ][0]
    assert plain_slot["choice_kind"] is None
    assert plain_slot["choice_options"] == []


def test_resonance_tuner_rejects_a_missing_or_pointless_choice():
    """고르지 않았거나 지금과 같은 결이면 집중력을 쓰기 전에 막는다."""

    import pytest

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _kel_encounter()
    profiles = _party_book("resonance_tuner")

    for bad in (None, "", "ember_x", "sunny"):
        state = new_guardian_battle("tune", encounter, profiles)
        before = int(state["focus"])
        command = {"member_id": 1, "action": "selected_1"}
        if bad is not None:
            command["choice"] = bad
        with pytest.raises(CombatRuleError) as caught:
            submit_guardian_action(state, command, encounter, profiles)
        assert caught.value.code == "EXPEDITION_COMBAT_CHOICE_REQUIRED"
        # 막힌 명령은 집중력을 가져가지 않는다.
        assert int(state["focus"]) == before


def test_resonance_tuner_changes_the_next_attack_and_then_lets_go():
    """고른 결은 다음 공격 하나에만 실리고, 그 뒤에는 원래대로 돌아온다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _kel_encounter()
    profiles = _party_book("resonance_tuner")
    state = new_guardian_battle("tune", encounter, profiles)

    def basic_of(current: dict) -> dict:
        member = guardian_battle_payload(current, encounter, profiles)["party"][0]
        return member["kit"]["basic"]

    plain = basic_of(state)
    assert plain["kel"] == "sunny"
    assert plain["matchup"] == "neutral"

    state = submit_guardian_action(
        state,
        {"member_id": 1, "action": "selected_1", "choice": "ember"},
        encounter,
        profiles,
    )

    tuned = basic_of(state)
    # 확정 전에 바뀐 상성과 늘어난 예상 피해가 그대로 보인다.
    assert tuned["kel"] == "ember"
    assert tuned["matchup"] == "weak"
    assert tuned["power"] > plain["power"]

    state = submit_guardian_action(
        state, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    # 다른 대원이 때려도 내 결은 그대로 남아 있다. 조율은 나에게 건 것이다.
    assert basic_of(state)["kel"] == "ember"

    state = submit_guardian_action(
        state, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    # 한 번 쓰고 나면 원래 결로 돌아온다.
    assert basic_of(state)["kel"] == "sunny"
    assert basic_of(state)["matchup"] == "neutral"


def test_resonance_tuner_is_a_once_per_battle_command():
    """조율기도 전투 1회다. 매 라운드 상성을 갈아 끼우지 못한다."""

    import pytest

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _kel_encounter()
    profiles = _party_book("resonance_tuner")
    state = new_guardian_battle("tune", encounter, profiles)
    state = submit_guardian_action(
        state,
        {"member_id": 1, "action": "selected_1", "choice": "ember"},
        encounter,
        profiles,
    )
    state = submit_guardian_action(
        state, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    with pytest.raises(CombatRuleError) as caught:
        submit_guardian_action(
            state,
            {"member_id": 1, "action": "selected_1", "choice": "rainy"},
            encounter,
            profiles,
        )
    assert caught.value.code == "EXPEDITION_COMBAT_COOLDOWN"
    assert "한 번만" in caught.value.message


def _b2_party(code: str, *, owned: list[str] | None = None) -> list[dict]:
    """3등급 책을 **두 번째 칸**에 끼운 파티.

    아홉 꼬리의 잔상과 마음결 대백과는 3등급이라 B2에서만 펼쳐진다(7.2). 대백과가
    바꾸는 대상은 첫 칸이므로, 책이 첫 칸에 있으면 자기 자신을 바꾸는 이상한
    상황이 된다. 실제 장착 규칙대로 두고 시험한다.
    """

    party = _party_book(code)
    party[0]["snapshot"]["skill_loadout"] = {
        "slots": {
            "B1": {"source": "skillbook", "code": "clear_aim"},
            "B2": {"source": "skillbook", "code": code},
        },
        "owned_codes": owned or [],
    }
    return party


def test_afterimage_hands_the_telegraphed_hit_to_someone_else():
    """예고된 공격을 고른 대원이 대신 받는다. 그 라운드에만."""

    from app.content.expeditions.combat import (
        _retargeted_member_id,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()

    # 책이 없으면 먼저 행동한 대원(1번)이 front 예고를 받는다.
    bare = _party_book("clear_aim")
    plain = new_guardian_battle("bare", encounter, bare)
    for member_id in (1, 2):
        plain = submit_guardian_action(
            plain, {"member_id": member_id, "action": "attack"}, encounter, bare
        )
    assert [int(member["hp"]) for member in plain["party"]] == [7, 8]

    # 잔상을 쓰면 2번이 대신 받는다.
    profiles = _b2_party("nine_tail_afterimage")
    state = new_guardian_battle("fox", encounter, profiles)
    state = submit_guardian_action(
        state,
        {"member_id": 1, "action": "selected_2", "choice": "2"},
        encounter,
        profiles,
    )
    state = submit_guardian_action(
        state, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    assert [int(member["hp"]) for member in state["party"]] == [8, 7]
    # 라운드가 넘어가면 저절로 풀린다 — 다음 라운드까지 끌고 가지 않는다.
    assert int(state["round"]) == 2
    assert _retargeted_member_id(state) is None


def test_afterimage_target_cannot_guard_that_round():
    """반대급부 — 잔상을 대신 받은 대원은 그 라운드에 몸을 뺄 수 없다."""

    import pytest

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _b2_party("nine_tail_afterimage")
    state = new_guardian_battle("fox", encounter, profiles)
    state = submit_guardian_action(
        state,
        {"member_id": 1, "action": "selected_2", "choice": "2"},
        encounter,
        profiles,
    )
    with pytest.raises(CombatRuleError) as caught:
        submit_guardian_action(
            state, {"member_id": 2, "action": "guard"}, encounter, profiles
        )
    assert caught.value.code == "EXPEDITION_COMBAT_GUARD_BLOCKED"
    # 다른 행동은 막지 않는다. `최소 한 행동은 항상 합법`이 지켜진다.
    submit_guardian_action(
        state, {"member_id": 2, "action": "attack"}, encounter, profiles
    )


def test_afterimage_offers_everyone_but_the_current_target():
    """지금 노려지는 대원은 후보에서 빠진다 — 넘길 곳이 아니다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
    )

    encounter = _encounter_fixture()
    profiles = _b2_party("nine_tail_afterimage")
    payload = guardian_battle_payload(
        new_guardian_battle("fox", encounter, profiles), encounter, profiles
    )
    slot = [
        item
        for item in payload["party"][0]["kit"]["selected_skills"]
        if item["slot"] == "selected_2"
    ][0]

    assert slot["available"] is True
    assert slot["choice_kind"] == "member"
    assert slot["choice_current"] == "1"
    # 이름표는 서버가 준다. 앱이 대원 이름을 따로 찾아 붙이지 않는다.
    assert slot["choice_options"] == [{"value": "2", "label": "볕이"}]


def test_afterimage_stays_locked_against_an_attack_on_everyone():
    """전체 공격은 넘길 대상이 없다. 눌러 본 뒤 거절하는 대신 미리 잠근다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
    )

    encounter = {
        **_encounter_fixture(),
        "intents": [
            {
                "code": "sweep",
                "name": "장부 쓸기",
                "telegraph": "모두를 노려요.",
                "target": "all",
                "power": 1,
            }
        ],
    }
    profiles = _b2_party("nine_tail_afterimage")
    payload = guardian_battle_payload(
        new_guardian_battle("fox", encounter, profiles), encounter, profiles
    )
    slot = [
        item
        for item in payload["party"][0]["kit"]["selected_skills"]
        if item["slot"] == "selected_2"
    ][0]

    assert slot["available"] is False
    assert slot["lock_reason"] == "넘길 다른 대원이 없어요."
    assert slot["choice_options"] == []


def test_encyclopedia_swaps_the_first_slot_for_the_rest_of_the_battle():
    """바꿔 낀 책은 슬롯에도 보이고 그 책의 수치도 실제로 붙는다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _b2_party("heart_encyclopedia", owned=["leaf_greave"])
    state = new_guardian_battle("book", encounter, profiles)

    def first_slot(current: dict) -> dict:
        member = guardian_battle_payload(current, encounter, profiles)["party"][0]
        return [
            item
            for item in member["kit"]["selected_skills"]
            if item["slot"] == "selected_1"
        ][0]

    def guard_of(current: dict) -> int:
        member = guardian_battle_payload(current, encounter, profiles)["party"][0]
        return int(member["kit"]["guard"]["guard"])

    assert first_slot(state)["equipped_book"]["code"] == "clear_aim"
    guard_before = guard_of(state)

    state = submit_guardian_action(
        state,
        {"member_id": 1, "action": "selected_2", "choice": "leaf_greave"},
        encounter,
        profiles,
    )

    assert first_slot(state)["equipped_book"]["code"] == "leaf_greave"
    # 이름만 바뀌고 효과는 안 붙는 상태를 만들지 않는다 — 잎사귀 각반의 +1이
    # 실제 방어량에 실린다.
    assert guard_of(state) == guard_before + 1
    # 스냅샷은 건드리지 않는다. 런이 끝나면 원래 장착 그대로다.
    assert profiles[0]["snapshot"]["skill_loadout"]["slots"]["B1"]["code"] == "clear_aim"


def test_encyclopedia_locks_skills_for_the_round_it_swapped():
    """반대급부 — 바꿔 끼는 라운드에는 기본 공격과 마음 지키기만 남는다."""

    import pytest

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _b2_party("heart_encyclopedia", owned=["leaf_greave"])
    state = new_guardian_battle("book", encounter, profiles)
    state = submit_guardian_action(
        state,
        {"member_id": 1, "action": "selected_2", "choice": "leaf_greave"},
        encounter,
        profiles,
    )
    state = submit_guardian_action(
        state, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    # 라운드가 바뀌었으니 잠금은 풀려 있다.
    assert int(state["round"]) == 2
    submit_guardian_action(
        state, {"member_id": 1, "action": "unique_1"}, encounter, profiles
    )

    # 같은 라운드였다면 막혔다.
    same_round = new_guardian_battle("book2", encounter, profiles)
    same_round["party"][0]["skill_blocked_round"] = 1
    with pytest.raises(CombatRuleError) as caught:
        submit_guardian_action(
            same_round, {"member_id": 1, "action": "unique_1"}, encounter, profiles
        )
    assert caught.value.code == "EXPEDITION_COMBAT_SKILL_BLOCKED"
    submit_guardian_action(
        same_round, {"member_id": 1, "action": "attack"}, encounter, profiles
    )


def test_encyclopedia_only_offers_books_frozen_at_departure():
    """후보는 출발 스냅샷이 정한다. 런 도중에 산 책은 끼어들지 않는다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
    )

    encounter = _encounter_fixture()
    # 이미 끼고 있는 책과 3등급 책은 후보가 아니다(첫 칸에 들어갈 수 없다).
    profiles = _b2_party(
        "heart_encyclopedia",
        owned=["clear_aim", "leaf_greave", "first_breath"],
    )
    payload = guardian_battle_payload(
        new_guardian_battle("book", encounter, profiles), encounter, profiles
    )
    slot = [
        item
        for item in payload["party"][0]["kit"]["selected_skills"]
        if item["slot"] == "selected_2"
    ][0]

    assert slot["choice_kind"] == "book"
    assert slot["choice_current"] == "clear_aim"
    # 지금 낀 clear_aim은 빠지고 나머지만 남는다. 순서는 스냅샷이 얼린 순서가
    # 아니라 이름순이라 화면에서 늘 같은 자리에 있다.
    assert [option["label"] for option in slot["choice_options"]] == [
        "잎사귀 각반",
        "첫 호흡",
    ]
    assert all(option["label"] for option in slot["choice_options"])

    # 가진 책이 없으면 바꿔 낄 것이 없어 잠긴다.
    bare = _b2_party("heart_encyclopedia")
    empty = guardian_battle_payload(
        new_guardian_battle("book", encounter, bare), encounter, bare
    )
    empty_slot = [
        item
        for item in empty["party"][0]["kit"]["selected_skills"]
        if item["slot"] == "selected_2"
    ][0]
    assert empty_slot["available"] is False
    assert empty_slot["lock_reason"] == "바꿔 낄 다른 기록서가 없어요."


def test_choice_is_judged_against_the_list_the_app_was_given():
    """화면에 없던 값은 거절한다 — 목록과 판정이 같은 곳에서 나온다."""

    import pytest

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _b2_party("heart_encyclopedia", owned=["leaf_greave"])

    for bad in ("clear_aim", "double_leaf", "없는책"):
        state = new_guardian_battle("book", encounter, profiles)
        with pytest.raises(CombatRuleError) as caught:
            submit_guardian_action(
                state,
                {"member_id": 1, "action": "selected_2", "choice": bad},
                encounter,
                profiles,
            )
        assert caught.value.code == "EXPEDITION_COMBAT_CHOICE_REQUIRED"

    # 파티의 다른 대원이 들고 있는 책도 후보가 아니다 — 파티 내 중복 금지는
    # 전투 중 교체에도 그대로 적용된다.
    shared = _b2_party("heart_encyclopedia", owned=["field_note_echo"])
    state = new_guardian_battle("book", encounter, shared)
    with pytest.raises(CombatRuleError):
        submit_guardian_action(
            state,
            {"member_id": 1, "action": "selected_2", "choice": "field_note_echo"},
            encounter,
            shared,
        )


def test_final_resolve_only_fires_under_a_fifth_of_the_barrier():
    """마무리 결심 — 장벽 20% 이하에서만 +5. 경계 바로 위에서는 붙지 않는다."""

    from app.content.expeditions.combat import member_battle_kit

    profile = _party_book("final_resolve")[0]
    bare = _party_book("clear_aim")[0]

    def raw_power(target: dict, guard_bp: int) -> int:
        return int(
            member_battle_kit(target, enemy_guard_bp=guard_bp)["basic"]["raw_power"]
        )

    full = raw_power(profile, 10_000)
    # 20%를 갓 넘으면 아직 아니다.
    assert raw_power(profile, 2_001) == full
    # 정확히 20%부터 붙는다 — 경계는 포함이다.
    assert raw_power(profile, 2_000) == full + 5
    assert raw_power(profile, 0) == full + 5

    # 책이 없으면 장벽이 아무리 낮아도 그대로다.
    assert raw_power(bare, 0) == raw_power(bare, 10_000)


def test_final_resolve_is_visible_before_the_button_is_pressed():
    """확정 전에 이미 오른 위력이 보인다. 눌러 봐야 아는 효과가 아니다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("final_resolve")

    # 장벽은 전투 시작에서 난이도 계수로 조정된다. 20%는 fixture의 400이 아니라
    # **실제로 세워진 장벽**을 기준으로 세야 한다.
    opened = new_guardian_battle("resolve", encounter, profiles)
    threshold = int(opened["enemy_max_guard"]) * 2_000 // 10_000

    def shown_power(guard: int) -> int:
        state = new_guardian_battle("resolve", encounter, profiles)
        state["enemy_guard"] = guard
        payload = guardian_battle_payload(state, encounter, profiles)
        return int(payload["party"][0]["kit"]["basic"]["power"])

    assert shown_power(threshold + 1) < shown_power(threshold)


def test_steady_axis_only_softens_attacks_on_everyone():
    """흔들리지 않는 축 — 전체 공격만 정액 1을 덜어 낸다. 단일기는 그대로."""

    from app.content.expeditions.combat import (
        new_guardian_battle,
        submit_guardian_action,
    )

    def hp_after(intent_target: str, code: str) -> list[int]:
        encounter = {
            **_encounter_fixture(),
            "intents": [
                {
                    "code": "sweep",
                    "name": "장부 쓸기",
                    "telegraph": "노려요.",
                    "target": intent_target,
                    # 방어를 안 하면 그대로 들어올 만큼만.
                    "power": 3,
                }
            ],
        }
        profiles = _party_book(code)
        state = new_guardian_battle("axis", encounter, profiles)
        for member_id in (1, 2):
            state = submit_guardian_action(
                state, {"member_id": member_id, "action": "attack"}, encounter, profiles
            )
        return [int(member["hp"]) for member in state["party"]]

    # 전체 공격 — 책을 든 1번만 1 덜 맞는다. 2번은 그대로다.
    assert hp_after("all", "clear_aim") == [5, 5]
    assert hp_after("all", "steady_axis") == [6, 5]

    # 단일 공격에는 붙지 않는다. `all 공격 피해 −1`이라고 적혀 있다.
    assert hp_after("front", "clear_aim") == hp_after("front", "steady_axis")


def test_ringcount_record_lifts_the_whole_party_and_costs_the_holder_their_guard():
    """고리수 기록부 — 파티 전원 고유 II +4, 장착자는 그 전투 내내 방어 불가."""

    import pytest

    from app.content.expeditions.combat import (
        CombatRuleError,
        guardian_battle_payload,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()

    def unique_powers(code: str) -> list[tuple[int, int]]:
        profiles = _b2_party(code)
        payload = guardian_battle_payload(
            new_guardian_battle("ring", encounter, profiles), encounter, profiles
        )
        return [
            (
                int(member["kit"]["unique_skills"][0]["raw_power"]),
                int(member["kit"]["unique_skills"][1]["raw_power"]),
            )
            for member in payload["party"]
        ]

    bare = unique_powers("clear_aim")
    ringed = unique_powers("ringcount_record")

    for (bare_one, bare_two), (ring_one, ring_two) in zip(bare, ringed, strict=True):
        # 고유 I은 그대로, 고유 II만 정확히 +4다.
        assert ring_one == bare_one
        assert ring_two - bare_two == 4
    # 장착자뿐 아니라 파티 전원이다 — 두 번째 대원도 받았다.
    assert len(ringed) == 2

    # 반대급부는 그 전투 내내다. 라운드가 지나도 풀리지 않는다.
    profiles = _b2_party("ringcount_record")
    state = new_guardian_battle("ring", encounter, profiles)
    for round_number in (1, 2):
        with pytest.raises(CombatRuleError) as caught:
            submit_guardian_action(
                state, {"member_id": 1, "action": "guard"}, encounter, profiles
            )
        assert caught.value.code == "EXPEDITION_COMBAT_GUARD_LOCKED"
        # 기본 공격은 언제나 남는다 — 최소 한 행동은 항상 합법이다.
        state = submit_guardian_action(
            state, {"member_id": 1, "action": "attack"}, encounter, profiles
        )
        # 책을 안 든 대원은 멀쩡히 몸을 뺀다.
        state = submit_guardian_action(
            state, {"member_id": 2, "action": "guard"}, encounter, profiles
        )
        assert int(state["round"]) == round_number + 1


def test_shadow_oath_sharpens_weakness_and_dulls_neutral_without_touching_resist():
    """그림자 맹세 — 약점 1.50 → 1.70, 중립 1.00 → 0.60, 내성은 그대로."""

    from app.content.expeditions.combat import MATCHUP_POWER_BP, member_battle_kit

    assert MATCHUP_POWER_BP == {
        "weak": 15_000,
        "prism_weak": 13_000,
        "neutral": 10_000,
        "resist": 6_000,
    }

    from app.content.expeditions.combat_identity import scaled_power

    # 비교 상대는 **행동 수치를 건드리지 않는** 책이어야 한다. `또렷한 겨냥`은
    # 기본 공격 위력을 +3 하므로 여기서는 기준이 될 수 없다.
    def basic(code: str, **kwargs) -> dict:
        return member_battle_kit(_b2_party(code)[0], **kwargs)["basic"]

    # 기본 캐릭터의 결은 sunny다. fire(=ember)를 약점으로 두면 중립,
    # light(=sunny)를 약점으로 두면 약점이 된다.
    neutral_bare = basic("first_breath", current_weak_element="fire")
    neutral_oath = basic("shadow_oath", current_weak_element="fire")
    assert neutral_bare["matchup"] == neutral_oath["matchup"] == "neutral"
    assert neutral_bare["matchup_bp"] == 10_000
    assert neutral_oath["matchup_bp"] == 6_000
    assert neutral_oath["power"] < neutral_bare["power"]

    weak_bare = basic("first_breath", current_weak_element="light")
    weak_oath = basic("shadow_oath", current_weak_element="light")
    assert weak_bare["matchup"] == weak_oath["matchup"] == "weak"
    assert weak_bare["matchup_bp"] == 15_000
    assert weak_oath["matchup_bp"] == 17_000
    assert weak_oath["power"] > weak_bare["power"]
    # 배율이 실제로 위력에 곱해졌는지까지 본다. 표만 바뀌고 계산이 안 바뀌는
    # 상태를 잡기 위해서다.
    assert weak_oath["power"] == scaled_power(weak_oath["power_neutral"], 17_000)
    assert neutral_oath["power"] == scaled_power(neutral_oath["power_neutral"], 6_000)

    # 내성은 덮지 않는다. `원래 내성과 중복하지 않음` — 덮으면 중립 0.60과
    # 내성 0.60이 겹쳐 두 배로 아프다.
    resist_bare = basic("first_breath", current_resist_element="light")
    resist_oath = basic("shadow_oath", current_resist_element="light")
    assert resist_bare["matchup"] == resist_oath["matchup"] == "resist"
    assert resist_bare["matchup_bp"] == resist_oath["matchup_bp"] == 6_000
    assert resist_oath["power"] == resist_bare["power"]


def test_shadow_oath_is_the_holders_alone():
    """맹세는 장착자 한 명의 것이다. 파티 전원 문구가 없는 책이다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
    )

    encounter = {**_encounter_fixture(), "weak_element": "light"}
    profiles = _b2_party("shadow_oath")
    payload = guardian_battle_payload(
        new_guardian_battle("oath", encounter, profiles), encounter, profiles
    )
    holder, other = payload["party"]
    assert int(holder["kit"]["basic"]["matchup_bp"]) == 17_000
    assert int(other["kit"]["basic"]["matchup_bp"]) == 15_000


# ── 파는데 아무 일도 안 하는 책은 없어야 한다 ────────────────────────────────
#
# `first_signal`(선제 신호)이 그런 상태였다. 효과 문장이 `적 의도 공개 후 1라운드
# 명령 순서 재배치`인데, 순차 명령 독(stage-battle-v2.0)에서는 **모든 플레이어가
# 이미 매 라운드 공짜로 하는 일**이다. 순서를 미리 제출하고 잠그던 예약형 패널
# 시절 설계라, 그 패널이 교체되면서 팔 것이 사라졌다. 0038에서 상점에서 내렸다.
#
# 예외 목록을 손으로 들고 있지 않는다. `is_active`가 곧 답이라 새 책이 같은
# 상태가 되면 목록을 고치지 않아도 바로 걸린다.


def test_no_active_book_is_sold_while_doing_nothing_in_combat():
    """씨앗을 받는 책은 전투에서 실제로 무언가 해야 한다.

    파는데 아무 일도 안 하는 책은 환불 사유다. 효과를 연결하거나 상점에서
    내리거나 둘 중 하나여야 하고, 어중간한 상태로 출시되지 않는다.
    """

    sold_and_inert = {
        code
        for code, book in SKILL_BOOK_CATALOG.items()
        if book["is_active"]
        and book["acquire_kind"] == "shop"
        and book["price_seeds"]
        and not book["combat_effect"]
    }
    assert sold_and_inert == set()


def test_a_retired_book_says_why_and_keeps_its_price_history():
    """내린 책은 이유를 남긴다. 조용히 사라지면 산 사람이 영문을 모른다."""

    retired = {
        code for code, book in SKILL_BOOK_CATALOG.items() if not book["is_active"]
    }
    assert retired == {"first_signal"}
    for code in retired:
        book = SKILL_BOOK_CATALOG[code]
        assert book["retired_reason"], code
        # 값은 지우지 않는다. 이미 산 사람의 구매 이력과 맞춰 봐야 한다.
        assert book["price_seeds"] == 120
        # 서고에서 사라지지도 않는다 — 카탈로그에 그대로 남아 있다.
        assert book["name"] == "선제 신호"


def test_a_live_book_never_carries_a_retirement_reason():
    """살아 있는 책에 내린 이유가 붙어 있으면 둘 중 하나가 거짓말이다."""

    for code, book in SKILL_BOOK_CATALOG.items():
        if book["is_active"]:
            assert book["retired_reason"] is None, code


def test_the_retired_book_is_at_least_honest_in_the_slot():
    """열지 않은 이상, 슬롯은 효과가 없다고 정직하게 말해야 한다."""

    from app.content.expeditions.combat import member_battle_kit

    for code, book in SKILL_BOOK_CATALOG.items():
        if book["combat_effect"]:
            continue
        kit = member_battle_kit(
            _profile(
                {
                    "skill_loadout": {
                        "slots": {
                            "B1": {"source": "skillbook", "code": code},
                            "B2": {"source": "emotion", "code": "emotion.primary"},
                        }
                    }
                }
            )
        )
        slot = next(
            item for item in kit["selected_skills"] if item["slot"] == "selected_1"
        )
        assert slot["available"] is False, code
        assert slot["lock_reason"] == "효과를 준비하고 있어요", code


def test_node_layout_is_pinned_because_the_app_mirrors_it():
    """지도 노드 자리는 함부로 옮길 수 없다.

    앱이 이 좌표를 **손으로 베껴** 걸을 수 있는 땅과 대조한다
    (`expedition_models_test.dart`의 `_nodeLayout`). 서버에서 조용히 옮기면
    앱은 옛 자리를 기준으로 `노드가 땅 안에 있다`고 통과시키고, 실제 화면에서는
    벽 속에 박힌 노드가 된다.

    자리를 옮기려면 이 표와 앱의 표를 **함께** 고쳐야 한다. 그러라고 여기 박아 둔다.
    """

    import importlib.util
    import pathlib

    spec = importlib.util.spec_from_file_location(
        "build_region_packs",
        pathlib.Path(__file__).resolve().parents[2] / "scripts" / "build_region_packs.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    layout = {
        code: (round(x, 3), round(y, 3))
        for code, _kind, x, y, _cost, _threat in module.NODE_LAYOUT
    }
    assert layout == {
        "entrance": (0.08, 0.50),
        "first_event": (0.27, 0.30),
        "second_event": (0.27, 0.70),
        "camp": (0.48, 0.50),
        "discovery": (0.50, 0.20),
        "guardian": (0.69, 0.50),
        "objective": (0.86, 0.32),
        "exit": (0.94, 0.62),
    }


def test_region_order_follows_the_story_not_the_alphabet():
    """지역을 지나가는 순서는 이야기가 정한다.

    알파벳순으로 정렬하면 관측실이 보관고보다 먼저 열리는데, 보관고의 마지막
    장이 `다음 편지는 마음나무 관측실로 향해요`로 끝난다. 정반대다.

    이 어긋남은 **걸어 보기 전에는 안 보인다** — 실제로 앱을 띄워 우물정원을
    열어 보고서야 찾았다. 그래서 여기 못 박는다.
    """

    from app.services.expeditions import load_content, region_order

    order = region_order()
    assert order == [
        "moss_archive",
        "echo_well",
        "starlight_seed_vault",
        "heartwood_observatory",
    ]

    # 각 지역의 마지막 이야기가 **다음 지역의 이름**을 부른다. 순서가 바뀌면
    # 이 대조가 깨진다.
    following = {
        "moss_archive": "메아리 우물정원",
        "echo_well": "별빛 씨앗 보관고",
        "starlight_seed_vault": "마음나무 관측실",
    }
    for index, code in enumerate(order[:-1]):
        expected_name = load_content(order[index + 1])["region"]["name"]
        assert following[code] == expected_name, code
        caption = load_content(code)["stages"][-1]["story"]["caption"]
        assert expected_name in caption, (
            f"{code}의 마지막 이야기가 다음 지역({expected_name})을 가리키지 않습니다"
        )

    # 순서는 `recommended_stage`가 단일 원본이다. 손으로 든 목록이 아니다.
    stages = [load_content(code)["region"]["recommended_stage"] for code in order]
    assert stages == sorted(stages), "권장 단계가 순서와 어긋납니다"
